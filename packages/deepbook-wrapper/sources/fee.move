module deepbook_wrapper::fee;

use deepbook::constants::fee_penalty_multiplier;
use deepbook::pool::Pool;
use deepbook_wrapper::helper::{
    calculate_deep_required,
    calculate_order_amount,
    calculate_discount_rate,
    get_sui_per_deep,
    calculate_market_order_params,
    apply_discount
};
use deepbook_wrapper::math;
use deepbook_wrapper::ticket::{
    AdminTicket,
    validate_ticket,
    destroy_ticket,
    update_default_fees_ticket_type,
    update_pool_specific_fees_ticket_type
};
use pyth::price_info::PriceInfoObject;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event;
use sui::table::{Self, Table};

// === Errors ===
const EInvalidFeePrecision: u64 = 1;
const EFeeOutOfRange: u64 = 2;
const EInvalidFeeHierarchy: u64 = 3;
const EInvalidDiscountPrecision: u64 = 4;
const EDiscountOutOfRange: u64 = 5;
const EInvalidRatioSum: u64 = 6;
const EZeroOrderAmount: u64 = 7;

// === Constants ===
/// The multiple that fee rates must adhere to, aligned with DeepBook (0.01 bps = 0.0001%)
const FEE_PRECISION_MULTIPLE: u64 = 1000;
/// The minimum allowed fee rate (0 bps)
const MIN_FEE_RATE: u64 = 0;
/// The maximum allowed taker fee rate (20 bps = 0.20%)
const MAX_TAKER_FEE_RATE: u64 = 2_000_000;
/// The maximum allowed maker fee rate (10 bps = 0.10%)
const MAX_MAKER_FEE_RATE: u64 = 1_000_000;
/// The minimum allowed discount rate (0%)
const MIN_DISCOUNT_RATE: u64 = 0;
/// The maximum allowed discount rate (100%)
const MAX_DISCOUNT_RATE: u64 = 1_000_000_000;

// Default fee rates for initialization
const DEFAULT_DEEP_TAKER_FEE_BPS: u64 = 600_000; // 6 bps
const DEFAULT_DEEP_MAKER_FEE_BPS: u64 = 300_000; // 3 bps
const DEFAULT_INPUT_COIN_TAKER_FEE_BPS: u64 = 500_000; // 5 bps
const DEFAULT_INPUT_COIN_MAKER_FEE_BPS: u64 = 200_000; // 2 bps
const DEFAULT_DEEP_FEE_DISCOUNT_RATE: u64 = 250_000_000; // 2500 bps (25%)

// === Structs ===
/// Configuration object containing trading fee rates
public struct TradingFeeConfig has key {
    id: UID,
    default_fees: PoolFeeConfig,
    pool_specific_fees: Table<ID, PoolFeeConfig>,
}

/// Struct to hold a complete fee configuration
public struct PoolFeeConfig has copy, drop, store {
    deep_fee_type_taker_rate: u64,
    deep_fee_type_maker_rate: u64,
    input_coin_fee_type_taker_rate: u64,
    input_coin_fee_type_maker_rate: u64,
    max_deep_fee_discount_rate: u64,
}

// === Events ===
/// Event for when default fees are updated
public struct DefaultFeesUpdated has copy, drop {
    new_fees: PoolFeeConfig,
}

/// Event for when a pool-specific fee config is updated
public struct PoolFeesUpdated has copy, drop {
    pool_id: ID,
    new_fees: PoolFeeConfig,
}

// === Public-Mutative Functions ===
/// Updates the default fee rates.
public fun update_default_fees(
    config: &mut TradingFeeConfig,
    ticket: AdminTicket,
    new_fees: PoolFeeConfig,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    validate_pool_fee_config(&new_fees);

    validate_ticket(&ticket, update_default_fees_ticket_type(), clock, ctx);
    destroy_ticket(ticket);

    config.default_fees = new_fees;

    event::emit(DefaultFeesUpdated { new_fees });
}

/// Updates or creates a pool-specific fee configuration.
public fun update_pool_specific_fees<BaseToken, QuoteToken>(
    config: &mut TradingFeeConfig,
    ticket: AdminTicket,
    pool: &Pool<BaseToken, QuoteToken>,
    new_fees: PoolFeeConfig,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    validate_pool_fee_config(&new_fees);

    validate_ticket(&ticket, update_pool_specific_fees_ticket_type(), clock, ctx);
    destroy_ticket(ticket);

    let pool_id = object::id(pool);

    if (config.pool_specific_fees.contains(pool_id)) {
        config.pool_specific_fees.remove(pool_id);
    };
    config.pool_specific_fees.add(pool_id, new_fees);

    event::emit(PoolFeesUpdated { pool_id, new_fees });
}

// === Public-View Functions ===
/// Get pool-specific fee rates if configured, otherwise default fee rates.
/// Returns (taker_fee_rate, maker_fee_rate) in billionths.
public fun get_fee_rates<BaseToken, QuoteToken>(
    config: &TradingFeeConfig,
    pool: &Pool<BaseToken, QuoteToken>,
): PoolFeeConfig {
    let pool_id = object::id(pool);

    if (config.pool_specific_fees.contains(pool_id)) {
        *config.pool_specific_fees.borrow(pool_id)
    } else {
        config.default_fees
    }
}

/// Get the deep fee type rates from a pool fee config.
/// Returns (taker_fee_rate, maker_fee_rate) in billionths.
public fun deep_fee_type_rates(config: PoolFeeConfig): (u64, u64) {
    (config.deep_fee_type_taker_rate, config.deep_fee_type_maker_rate)
}

/// Get the input coin fee type rates from a pool fee config.
/// Returns (taker_fee_rate, maker_fee_rate) in billionths.
public fun input_coin_fee_type_rates(config: PoolFeeConfig): (u64, u64) {
    (config.input_coin_fee_type_taker_rate, config.input_coin_fee_type_maker_rate)
}

public fun max_deep_fee_discount_rate(config: PoolFeeConfig): u64 {
    config.max_deep_fee_discount_rate
}

/// Estimate the total fee for a limit order using DEEP fee type
///
/// This function uses oracle price feeds and reference pool to get the best DEEP/SUI price,
/// then calculates fees including coverage fees and protocol fees with discount applied.
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool for DEEP/SUI price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - trading_fee_config: Trading fee configuration object
/// - deep_in_balance_manager: Amount of DEEP available in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - quantity: Order quantity in base tokens
/// - price: Order price in quote tokens per base token
/// - is_bid: True for buy orders, false for sell orders
/// - clock: System clock for timestamp verification
///
/// Returns:
/// - total_fee: Combined coverage fee and protocol fee
/// - deep_reserves_coverage_fee: SUI cost of borrowed DEEP from reserves
/// - protocol_fee: Protocol fee after discount applied
/// - deep_required: Total amount of DEEP required for the order
/// - discount_rate: Actual discount rate applied to protocol fee
public fun estimate_full_fee_limit<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    pool: &Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    trading_fee_config: &TradingFeeConfig,
    deep_in_balance_manager: u64,
    deep_in_wallet: u64,
    quantity: u64,
    price: u64,
    is_bid: bool,
    clock: &Clock,
): (u64, u64, u64, u64, u64) {
    // Get the best DEEP/SUI price
    let sui_per_deep = get_sui_per_deep(
        deep_usd_price_info,
        sui_usd_price_info,
        reference_pool,
        clock,
    );

    // Get the protocol fee rates for the pool and max discount rate
    let pool_fee_config = trading_fee_config.get_fee_rates(pool);
    let (protocol_taker_fee_rate, _) = pool_fee_config.deep_fee_type_rates();
    let max_discount_rate = pool_fee_config.max_deep_fee_discount_rate();

    // Get DEEP required for the order
    let deep_required = calculate_deep_required(pool, quantity, price);

    // Calculate the order amount
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // Call the core logic function to get fee components
    let (
        total_fee,
        deep_reserves_coverage_fee,
        protocol_fee,
        discount_rate,
    ) = estimate_full_order_fee_core(
        deep_in_balance_manager,
        deep_in_wallet,
        deep_required,
        sui_per_deep,
        protocol_taker_fee_rate,
        order_amount,
        max_discount_rate,
    );

    (total_fee, deep_reserves_coverage_fee, protocol_fee, deep_required, discount_rate)
}

/// Estimate the total fee for a market order using DEEP fee type
///
/// This function uses oracle price feeds and reference pool to get the best DEEP/SUI price,
/// then calculates fees including coverage fees and protocol fees with discount applied.
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool for DEEP/SUI price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - trading_fee_config: Trading fee configuration object
/// - deep_in_balance_manager: Amount of DEEP available in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - clock: System clock for timestamp verification
///
/// Returns:
/// - total_fee: Combined coverage fee and protocol fee
/// - deep_reserves_coverage_fee: SUI cost of borrowed DEEP from reserves
/// - protocol_fee: Protocol fee after discount applied
/// - deep_required: Total amount of DEEP required for the order
/// - discount_rate: Actual discount rate applied to protocol fee
public fun estimate_full_fee_market<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    pool: &Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    trading_fee_config: &TradingFeeConfig,
    deep_in_balance_manager: u64,
    deep_in_wallet: u64,
    order_amount: u64,
    is_bid: bool,
    clock: &Clock,
): (u64, u64, u64, u64, u64) {
    // Get the best DEEP/SUI price
    let sui_per_deep = get_sui_per_deep(
        deep_usd_price_info,
        sui_usd_price_info,
        reference_pool,
        clock,
    );

    // Get the protocol fee rates for the pool and max discount rate
    let pool_fee_config = trading_fee_config.get_fee_rates(pool);
    let (protocol_taker_fee_rate, _) = pool_fee_config.deep_fee_type_rates();
    let max_discount_rate = pool_fee_config.max_deep_fee_discount_rate();

    // Get DEEP required for the order
    let (_, deep_required) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    // Call the core logic function to get fee components
    let (
        total_fee,
        deep_reserves_coverage_fee,
        protocol_fee,
        discount_rate,
    ) = estimate_full_order_fee_core(
        deep_in_balance_manager,
        deep_in_wallet,
        deep_required,
        sui_per_deep,
        protocol_taker_fee_rate,
        order_amount,
        max_discount_rate,
    );

    (total_fee, deep_reserves_coverage_fee, protocol_fee, deep_required, discount_rate)
}

// === Public-Package Functions ===
/// Calculate the total fee for an order using DEEP fee type
///
/// This function determines if the user needs to borrow DEEP from wrapper reserves and calculates
/// the appropriate fees including coverage fees and protocol fees with discount applied.
///
/// Parameters:
/// - balance_manager_deep: Amount of DEEP in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - deep_required: Total amount of DEEP required for the order
/// - sui_per_deep: Current DEEP/SUI price for coverage fee calculation
/// - protocol_taker_fee_rate: Protocol fee rate for taker portion (in billionths)
/// - order_amount: Total order amount to calculate protocol fees on
/// - max_discount_rate: Maximum discount rate available (in billionths)
///
/// Returns:
/// - total_fee: Combined coverage fee and protocol fee
/// - deep_reserves_coverage_fee: SUI cost of borrowed DEEP from reserves
/// - protocol_fee: Protocol fee after discount applied
/// - discount_rate: Actual discount rate applied to protocol fee
public(package) fun estimate_full_order_fee_core(
    balance_manager_deep: u64,
    deep_in_wallet: u64,
    deep_required: u64,
    sui_per_deep: u64,
    protocol_taker_fee_rate: u64,
    order_amount: u64,
    max_discount_rate: u64,
): (u64, u64, u64, u64) {
    let deep_from_reserves = if (balance_manager_deep + deep_in_wallet < deep_required)
        deep_required - balance_manager_deep - deep_in_wallet else 0;

    // Calculate the deep reserves coverage fee
    let deep_reserves_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );

    // Calculate the discount rate
    let discount_rate = calculate_discount_rate(
        max_discount_rate,
        deep_from_reserves,
        deep_required,
    );

    // Calculate protocol fee assuming order is fully taker to show fee upper limit
    // Apply user's discount to the calculated fee
    let (protocol_fee, _, _) = calculate_protocol_fees(
        1_000_000_000, // 100% taker ratio
        0, // 0% maker ratio
        protocol_taker_fee_rate,
        0, // no need to specify maker fee rate for 0% maker ratio
        order_amount,
        discount_rate,
    );

    let total_fee = deep_reserves_coverage_fee + protocol_fee;

    (total_fee, deep_reserves_coverage_fee, protocol_fee, discount_rate)
}

/// Calculates the fee for using DEEP from wrapper reserves
/// This fee represents the SUI equivalent value of the borrowed DEEP
///
/// Parameters:
/// - sui_per_deep: Current DEEP/SUI price from reference pool
/// - deep_from_reserves: Amount of DEEP taken from wrapper reserves
///
/// Returns:
/// - u64: Fee amount in SUI coins for borrowing DEEP from reserves
public(package) fun calculate_deep_reserves_coverage_order_fee(
    sui_per_deep: u64,
    deep_from_reserves: u64,
): u64 {
    math::mul(deep_from_reserves, sui_per_deep)
}

/// Calculate protocol fees for orders with both taker and maker portions
///
/// This function splits the order amount by taker/maker ratios, applies respective fee rates,
/// and applies discount to both fee components.
///
/// Parameters:
/// - taker_ratio: Proportion of order acting as taker (in billionths, e.g., 1_000_000_000 = 100%)
/// - maker_ratio: Proportion of order acting as maker (in billionths)
/// - protocol_taker_fee_rate: Fee rate for taker portion (in billionths)
/// - protocol_maker_fee_rate: Fee rate for maker portion (in billionths)
/// - order_amount: Total order amount to calculate fees on
/// - discount_rate: Discount rate to apply to calculated fees (in billionths)
///
/// Returns:
/// - total_protocol_fee: Combined taker and maker fees after discount
/// - protocol_taker_fee: Taker portion fee after discount
/// - protocol_maker_fee: Maker portion fee after discount
public(package) fun calculate_protocol_fees(
    taker_ratio: u64,
    maker_ratio: u64,
    protocol_taker_fee_rate: u64,
    protocol_maker_fee_rate: u64,
    order_amount: u64,
    discount_rate: u64,
): (u64, u64, u64) {
    // Validate input parameters
    assert!(taker_ratio + maker_ratio <= 1_000_000_000, EInvalidRatioSum);
    assert!(order_amount > 0, EZeroOrderAmount);

    let taker_amount = math::mul(order_amount, taker_ratio);
    let maker_amount = math::mul(order_amount, maker_ratio);

    let mut protocol_taker_fee = calculate_fee_by_rate(taker_amount, protocol_taker_fee_rate);
    let mut protocol_maker_fee = calculate_fee_by_rate(maker_amount, protocol_maker_fee_rate);

    // Apply discount to the protocol fees
    protocol_taker_fee = apply_discount(protocol_taker_fee, discount_rate);
    protocol_maker_fee = apply_discount(protocol_maker_fee, discount_rate);

    let total_protocol_fee = protocol_taker_fee + protocol_maker_fee;

    (total_protocol_fee, protocol_taker_fee, protocol_maker_fee)
}

/// Calculates DeepBook's fee when paid in input coins, applying the fee penalty multiplier
/// The fee is calculated by first applying the fee penalty multiplier to the taker fee rate,
/// then calculating the fee based on the resulting rate
///
/// # Parameters
/// * `amount` - The amount to calculate fee on
/// * `taker_fee` - DeepBook's taker fee rate in billionths
///
/// # Returns
/// * `u64` - The calculated DeepBook fee amount with penalty multiplier applied
public(package) fun calculate_input_coin_deepbook_fee(amount: u64, taker_fee: u64): u64 {
    let fee_penalty_multiplier = fee_penalty_multiplier();
    let input_coin_fee_rate = math::mul(taker_fee, fee_penalty_multiplier);
    let input_coin_fee = calculate_fee_by_rate(amount, input_coin_fee_rate);

    input_coin_fee
}

/// Calculates fee by applying a rate to an amount
///
/// # Parameters
/// * `amount` - The amount to calculate fee on
/// * `fee_rate` - The fee rate in billionths (e.g., 1,000,000 = 0.1%)
///
/// # Returns
/// * `u64` - The calculated fee amount
public(package) fun calculate_fee_by_rate(amount: u64, fee_rate: u64): u64 {
    math::mul(amount, fee_rate)
}

/// Charges a swap fee on a coin and returns the fee amount as a Balance.
/// Allows collecting fees directly from a coin during swap operations.
///
/// # Returns
/// * `Balance<CoinType>` - The fee amount as a Balance object
///
/// # Parameters
/// * `coin` - The coin to charge fee from
/// * `fee_bps` - The fee rate in billionths
public(package) fun charge_swap_fee<CoinType>(
    coin: &mut Coin<CoinType>,
    fee_bps: u64,
): Balance<CoinType> {
    let coin_balance = coin.balance_mut();
    let value = coin_balance.value();
    coin_balance.split(calculate_fee_by_rate(value, fee_bps))
}

// === Private Functions ===
/// Validates that the fee rates in a PoolFeeConfig are within the allowed precision and range.
fun validate_pool_fee_config(fees: &PoolFeeConfig) {
    validate_fee_pair(
        fees.deep_fee_type_taker_rate,
        fees.deep_fee_type_maker_rate,
    );
    validate_fee_pair(
        fees.input_coin_fee_type_taker_rate,
        fees.input_coin_fee_type_maker_rate,
    );
    validate_discount_rate(fees.max_deep_fee_discount_rate);
}

/// Validates a single taker/maker fee pair against precision, range, and consistency rules.
fun validate_fee_pair(taker_rate: u64, maker_rate: u64) {
    // --- Precision Checks ---
    assert!(taker_rate % FEE_PRECISION_MULTIPLE == 0, EInvalidFeePrecision);
    assert!(maker_rate % FEE_PRECISION_MULTIPLE == 0, EInvalidFeePrecision);

    // --- Range Checks ---
    assert!(taker_rate >= MIN_FEE_RATE && taker_rate <= MAX_TAKER_FEE_RATE, EFeeOutOfRange);
    assert!(maker_rate >= MIN_FEE_RATE && maker_rate <= MAX_MAKER_FEE_RATE, EFeeOutOfRange);

    // --- Hierarchy Check ---
    assert!(maker_rate <= taker_rate, EInvalidFeeHierarchy);
}

/// Validates the discount rate against precision and range rules.
fun validate_discount_rate(discount_rate: u64) {
    // --- Precision Check ---
    assert!(discount_rate % FEE_PRECISION_MULTIPLE == 0, EInvalidDiscountPrecision);
    // --- Range Check ---
    assert!(
        discount_rate >= MIN_DISCOUNT_RATE && discount_rate <= MAX_DISCOUNT_RATE,
        EDiscountOutOfRange,
    );
}

fun init(ctx: &mut TxContext) {
    let trading_fee_config = TradingFeeConfig {
        id: object::new(ctx),
        default_fees: PoolFeeConfig {
            deep_fee_type_taker_rate: DEFAULT_DEEP_TAKER_FEE_BPS,
            deep_fee_type_maker_rate: DEFAULT_DEEP_MAKER_FEE_BPS,
            input_coin_fee_type_taker_rate: DEFAULT_INPUT_COIN_TAKER_FEE_BPS,
            input_coin_fee_type_maker_rate: DEFAULT_INPUT_COIN_MAKER_FEE_BPS,
            max_deep_fee_discount_rate: DEFAULT_DEEP_FEE_DISCOUNT_RATE,
        },
        pool_specific_fees: table::new(ctx),
    };

    // Share the trading fee config object
    transfer::share_object(trading_fee_config);
}
