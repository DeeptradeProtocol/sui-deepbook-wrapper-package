module deepbook_wrapper::fee;

use deepbook::constants::fee_penalty_multiplier;
use deepbook::pool::Pool;
use deepbook_wrapper::admin::AdminCap;
use deepbook_wrapper::helper::{
    calculate_deep_required,
    get_sui_per_deep,
    calculate_market_order_params
};
use deepbook_wrapper::math;
use deepbook_wrapper::ticket::{
    AdminTicket,
    validate_ticket,
    destroy_ticket,
    update_default_fees_ticket_type,
    update_pool_specific_fees_ticket_type
};
use multisig::multisig;
use pyth::price_info::PriceInfoObject;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event;
use sui::table::{Self, Table};

// === Errors ===
/// Error when the sender is not a multisig address
const ESenderIsNotMultisig: u64 = 1;
const EInvalidFeePrecision: u64 = 2;
const EFeeOutOfRange: u64 = 3;
const EInvalidFeeHierarchy: u64 = 4;

// === Constants ===
/// The multiple that fee rates must adhere to (e.g., 10,000 = 0.0001% precision)
const FEE_PRECISION_MULTIPLE: u64 = 10_000;
/// The minimum allowed fee rate (0 bps)
const MIN_FEE_RATE: u64 = 0;
/// The maximum allowed taker fee rate (20 bps = 0.20%)
const MAX_TAKER_FEE_RATE: u64 = 2_000_000;
/// The maximum allowed maker fee rate (10 bps = 0.10%)
const MAX_MAKER_FEE_RATE: u64 = 1_000_000;

// === Default Fee Constants for Initialization ===
const DEFAULT_DEEP_TAKER_FEE_BPS: u64 = 600_000; // 6 bps
const DEFAULT_DEEP_MAKER_FEE_BPS: u64 = 300_000; // 3 bps
const DEFAULT_INPUT_COIN_TAKER_FEE_BPS: u64 = 500_000; // 5 bps
const DEFAULT_INPUT_COIN_MAKER_FEE_BPS: u64 = 200_000; // 2 bps

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
    _admin: &AdminCap,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    validate_pool_fee_config(&new_fees);

    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );
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
    _admin: &AdminCap,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    validate_pool_fee_config(&new_fees);

    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );
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
    let PoolFeeConfig { deep_fee_type_taker_rate, deep_fee_type_maker_rate, .. } = config;
    (deep_fee_type_taker_rate, deep_fee_type_maker_rate)
}

/// Get the input coin fee type rates from a pool fee config.
/// Returns (taker_fee_rate, maker_fee_rate) in billionths.
public fun input_coin_fee_type_rates(config: PoolFeeConfig): (u64, u64) {
    let PoolFeeConfig { input_coin_fee_type_taker_rate, input_coin_fee_type_maker_rate, .. } =
        config;
    (input_coin_fee_type_taker_rate, input_coin_fee_type_maker_rate)
}

/// Calculates the total fee estimate for a limit order in SUI coins
/// Uses oracle price feeds and reference pool to calculate the best DEEP/SUI price.
/// Fee is only charged when using DEEP from wrapper reserves for non-whitelisted pools
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool for price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - trading_fee_config: Trading fee configuration object
/// - deep_in_balance_manager: Amount of DEEP available in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - quantity: Order quantity in base tokens
/// - price: Order price in quote tokens per base token
/// - clock: System clock for timestamp verification
///
/// Returns:
/// - u64: The estimated total fee in SUI coins
/// - u64: Deep reserves coverage fee
/// - u64: Protocol fee
/// - u64: DEEP required for the order
///   Returns (0, 0, 0, deep_required) for whitelisted pools or when user provides all required DEEP
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
    clock: &Clock,
): (u64, u64, u64, u64) {
    // Check if pool is whitelisted
    let is_pool_whitelisted = pool.whitelisted();

    // Get the best DEEP/SUI price
    let sui_per_deep = get_sui_per_deep(
        deep_usd_price_info,
        sui_usd_price_info,
        reference_pool,
        clock,
    );

    // Get the protocol fee rate
    let protocol_fee_rate = trading_fee_config.deep_fee_type_rate;

    // Get DEEP required for the order
    let deep_required = calculate_deep_required(pool, quantity, price);

    // Call the core logic function to get fee components
    let (total_fee, deep_reserves_coverage_fee, protocol_fee) = estimate_full_order_fee_core(
        protocol_fee_rate,
        is_pool_whitelisted,
        deep_in_balance_manager,
        deep_in_wallet,
        deep_required,
        sui_per_deep,
    );

    (total_fee, deep_reserves_coverage_fee, protocol_fee, deep_required)
}

/// Calculates the total fee estimate for a market order in SUI coins
/// Uses oracle price feeds and reference pool to calculate the best DEEP/SUI price.
/// Fee is only charged when using DEEP from wrapper reserves for non-whitelisted pools
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool for price calculation
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
/// - u64: The estimated total fee in SUI coins
/// - u64: Deep reserves coverage fee
/// - u64: Protocol fee
/// - u64: DEEP required for the order
///   Returns (0, 0, 0, deep_required) for whitelisted pools or when user provides all required DEEP
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
): (u64, u64, u64, u64) {
    // Check if pool is whitelisted
    let is_pool_whitelisted = pool.whitelisted();

    // Get the best DEEP/SUI price
    let sui_per_deep = get_sui_per_deep(
        deep_usd_price_info,
        sui_usd_price_info,
        reference_pool,
        clock,
    );

    // Get the protocol fee rate
    let protocol_fee_rate = trading_fee_config.deep_fee_type_rate;

    // Get DEEP required for the order
    let (_, deep_required) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    // Call the core logic function to get fee components
    let (total_fee, deep_reserves_coverage_fee, protocol_fee) = estimate_full_order_fee_core(
        protocol_fee_rate,
        is_pool_whitelisted,
        deep_in_balance_manager,
        deep_in_wallet,
        deep_required,
        sui_per_deep,
    );

    (total_fee, deep_reserves_coverage_fee, protocol_fee, deep_required)
}

// === Public-Package Functions ===
/// Core logic for calculating the total fee for an order in SUI coins
/// Determines if user needs to use wrapper DEEP reserves and calculates
/// the appropriate fee based on the DEEP/SUI price
///
/// Parameters:
/// - protocol_fee_rate: Protocol fee rate in billionths
/// - is_pool_whitelisted: Whether the pool is whitelisted by DeepBook
/// - balance_manager_deep: Amount of DEEP in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - deep_required: Total amount of DEEP required for the order
/// - sui_per_deep: Current DEEP/SUI price from reference pool
///
/// Returns:
/// - u64: The total fee in SUI coins
/// - u64: Deep reserves coverage fee
/// - u64: Protocol fee
///   Returns (0, 0, 0) for whitelisted pools or when user provides all required DEEP
///
/// Fee consists of two components when using wrapper DEEP reserves:
/// 1. Deep reserves coverage fee: Cost of DEEP being borrowed
/// 2. Protocol fee: Additional fee based on protocol_fee_rate
public(package) fun estimate_full_order_fee_core(
    protocol_fee_rate: u64,
    is_pool_whitelisted: bool,
    balance_manager_deep: u64,
    deep_in_wallet: u64,
    deep_required: u64,
    sui_per_deep: u64,
): (u64, u64, u64) {
    // Determine if user needs to use wrapper DEEP reserves
    let will_use_wrapper_deep = balance_manager_deep + deep_in_wallet < deep_required;

    if (is_pool_whitelisted || !will_use_wrapper_deep) {
        (0, 0, 0) // No fee for whitelisted pools or when user provides all DEEP
    } else {
        // Calculate the amount of DEEP to take from reserves
        let deep_from_reserves = deep_required - balance_manager_deep - deep_in_wallet;

        // Calculate fee based on order amount, including both protocol fee and deep reserves coverage fee
        calculate_full_order_fee(protocol_fee_rate, sui_per_deep, deep_from_reserves)
    }
}

/// Calculates the total fee amount in SUI coins for an order using DEEP from reserves
/// Combines both the deep reserves coverage fee and protocol fee
///
/// Parameters:
/// - protocol_fee_rate: Protocol fee rate in billionths
/// - sui_per_deep: Current DEEP/SUI price from reference pool
/// - deep_from_reserves: Amount of DEEP taken from wrapper reserves
///
/// Returns:
/// - u64: Total fee amount in SUI coins (reserves coverage fee + protocol fee)
/// - u64: Deep reserves coverage fee
/// - u64: Protocol fee
///
/// The total fee consists of:
/// 1. Deep reserves coverage fee: SUI equivalent of borrowed DEEP
/// 2. Protocol fee: Additional fee calculated as percentage of borrowed DEEP
public(package) fun calculate_full_order_fee(
    protocol_fee_rate: u64,
    sui_per_deep: u64,
    deep_from_reserves: u64,
): (u64, u64, u64) {
    // Calculate the deep reserves coverage fee
    let deep_reserves_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );

    // Calculate the protocol fee
    let protocol_fee = calculate_protocol_fee(
        protocol_fee_rate,
        sui_per_deep,
        deep_from_reserves,
    );

    let total_fee = deep_reserves_coverage_fee + protocol_fee;

    (total_fee, deep_reserves_coverage_fee, protocol_fee)
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

/// Calculates the protocol fee for using DEEP from wrapper reserves
/// Fee is calculated as a percentage (protocol_fee_rate) of the borrowed DEEP value in SUI
///
/// Parameters:
/// - protocol_fee_rate: Protocol fee rate in billionths
/// - sui_per_deep: Current DEEP/SUI price from reference pool
/// - deep_from_reserves: Amount of DEEP taken from wrapper reserves
///
/// Returns:
/// - u64: Protocol fee amount in SUI coins
///
/// The calculation is done in two steps:
/// 1. Calculate fee amount in DEEP using protocol_fee_rate
/// 2. Convert DEEP fee to SUI using current price
public(package) fun calculate_protocol_fee(
    protocol_fee_rate: u64,
    sui_per_deep: u64,
    deep_from_reserves: u64,
): u64 {
    let protocol_fee_in_deep = math::mul(deep_from_reserves, protocol_fee_rate);
    let protocol_fee_in_sui = math::mul(protocol_fee_in_deep, sui_per_deep);

    protocol_fee_in_sui
}

/// Calculates protocol fee based on DeepBook's taker fee when paid in input coins
/// Protocol fee is calculated as protocol_fee_multiplier of the DeepBook fee
///
/// # Parameters
/// * `protocol_fee_multiplier` - Protocol fee multiplier in billionths
/// * `amount` - The amount to calculate fee on
/// * `taker_fee` - DeepBook's taker fee rate in billionths
///
/// # Returns
/// * `u64` - The calculated protocol fee amount
public(package) fun calculate_input_coin_protocol_fee(
    protocol_fee_multiplier: u64,
    amount: u64,
    taker_fee: u64,
): u64 {
    let deepbook_fee = calculate_fee_by_rate(amount, taker_fee);
    let protocol_fee = math::mul(deepbook_fee, protocol_fee_multiplier);

    protocol_fee
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

fun init(ctx: &mut TxContext) {
    let trading_fee_config = TradingFeeConfig {
        id: object::new(ctx),
        default_fees: PoolFeeConfig {
            deep_fee_type_taker_rate: DEFAULT_DEEP_TAKER_FEE_BPS,
            deep_fee_type_maker_rate: DEFAULT_DEEP_MAKER_FEE_BPS,
            input_coin_fee_type_taker_rate: DEFAULT_INPUT_COIN_TAKER_FEE_BPS,
            input_coin_fee_type_maker_rate: DEFAULT_INPUT_COIN_MAKER_FEE_BPS,
        },
        pool_specific_fees: table::new(ctx),
    };

    // Share the trading fee config object
    transfer::share_object(trading_fee_config);
}
