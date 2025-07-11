module deepbook_wrapper::order;

use deepbook::balance_manager::{BalanceManager, TradeProof};
use deepbook::constants;
use deepbook::order_info::OrderInfo;
use deepbook::pool::Pool;
use deepbook_wrapper::fee::{
    TradingFeeConfig,
    calculate_protocol_fees,
    calculate_input_coin_deepbook_fee,
    calculate_deep_reserves_coverage_order_fee
};
use deepbook_wrapper::helper::{
    calculate_deep_required,
    transfer_if_nonzero,
    calculate_order_amount,
    get_sui_per_deep,
    calculate_market_order_params,
    calculate_order_taker_maker_ratio,
    validate_slippage,
    apply_slippage,
    calculate_discount_rate
};
use deepbook_wrapper::wrapper::{
    Wrapper,
    join_deep_reserves_coverage_fee,
    join_protocol_fee,
    add_unsettled_fee,
    deep_reserves,
    split_deep_reserves
};
use pyth::price_info::PriceInfoObject;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::sui::SUI;
use token::deep::DEEP;

// === Errors ===
/// Error when trying to use deep from reserves but there is not enough available
const EInsufficientDeepReserves: u64 = 1;

/// Error when user doesn't have enough coins to cover the required fee
const EInsufficientFee: u64 = 2;

/// Error when user doesn't have enough input coins to create the order
const EInsufficientInput: u64 = 3;

/// Error when the caller is not the owner of the balance manager
const EInvalidOwner: u64 = 4;

/// Error when actual deep required exceeds the max deep required
const EDeepRequiredExceedsMax: u64 = 5;

/// Error when actual sui fee exceeds the max sui fee
const ESuiFeeExceedsMax: u64 = 6;

/// Not supported parameters errors
const ENotSupportedExpireTimestamp: u64 = 7;
const ENotSupportedSelfMatchingOption: u64 = 8;

// === Structs ===
/// Tracks how DEEP will be sourced for an order
/// Used to coordinate token sourcing from user wallet and wrapper reserves
public struct DeepPlan has copy, drop {
    /// Whether DEEP from wrapper reserves is needed for this order
    use_wrapper_deep_reserves: bool,
    /// Amount of DEEP to take from user's wallet
    from_user_wallet: u64,
    /// Amount of DEEP to take from wrapper reserves
    from_deep_reserves: u64,
    /// Whether wrapper DEEP reserves has enough DEEP to cover the order
    deep_reserves_cover_order: bool,
}

/// Tracks fee charging strategy for an order
/// Determines amount and sources for fee payment
/// Fees are always paid in SUI
public struct CoverageFeePlan has copy, drop {
    /// Amount of coverage fee to take from user's wallet
    from_wallet: u64,
    /// Amount of coverage fee to take from user's balance manager
    from_balance_manager: u64,
    /// Whether user has enough coins to cover the fee
    user_covers_fee: bool,
}

public struct ProtocolFeePlan has copy, drop {
    taker_fee_from_wallet: u64,
    taker_fee_from_balance_manager: u64,
    maker_fee_from_wallet: u64,
    maker_fee_from_balance_manager: u64,
    user_covers_fee: bool,
}

/// Tracks input coin requirements for an order
/// Plans how input coins will be sourced from user wallet and balance manager
public struct InputCoinDepositPlan has copy, drop {
    /// Total amount of input coins needed for the order
    order_amount: u64,
    /// Amount of input coins to take from user's wallet
    from_user_wallet: u64,
    /// Whether user has enough input coins for the order
    user_has_enough_input_coin: bool,
}

// === Public-Mutative Functions ===
/// Creates a limit order on DeepBook using coins from various sources
/// This function orchestrates the entire limit order creation process through the following steps:
/// 1. Creates plans for:
///    - DEEP coin sourcing from user wallet and wrapper reserves
///    - Fee collection in SUI coins
///    - Input coin deposits from wallet to balance manager
/// 2. Executes the plans through shared preparation logic that:
///    - Sources DEEP coins according to the DEEP plan
///    - Collects fees according to the fee plan
///    - Deposits input coins according to the input coin deposit plan
/// 3. Places the limit order on DeepBook and returns the order info
///
/// Parameters:
/// - wrapper: The DeepBook wrapper instance managing the order process
/// - trading_fee_config: Trading fee configuration object
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool for price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - deep_coin: DEEP coins from user's wallet
/// - sui_coin: SUI coins for fee payment
/// - price: Order price in quote tokens per base token
/// - quantity: Order quantity in base tokens
/// - is_bid: True for buy orders, false for sell orders
/// - expire_timestamp: Order expiration timestamp
/// - order_type: Type of order (e.g., GTC, IOC, FOK)
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - estimated_deep_required: Amount of DEEP tokens required for the order creation
/// - estimated_deep_required_slippage: Maximum acceptable slippage for estimated DEEP requirement in billionths (e.g., 10_000_000 = 1%)
/// - estimated_sui_fee: Estimated SUI fee which we can take as a protocol for the order creation
/// - estimated_sui_fee_slippage: Maximum acceptable slippage for estimated SUI fee in billionths (e.g., 10_000_000 = 1%)
/// - clock: System clock for timestamp verification
public fun create_limit_order<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    wrapper: &mut Wrapper,
    trading_fee_config: &TradingFeeConfig,
    pool: &mut Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    deep_coin: Coin<DEEP>,
    sui_coin: Coin<SUI>,
    price: u64,
    quantity: u64,
    is_bid: bool,
    expire_timestamp: u64,
    order_type: u8,
    self_matching_option: u8,
    client_order_id: u64,
    estimated_deep_required: u64,
    estimated_deep_required_slippage: u64,
    estimated_sui_fee: u64,
    estimated_sui_fee_slippage: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo) {
    wrapper.verify_version();

    // Verify the order expire timestamp is the max possible expire timestamp
    let max_expire_timestamp = constants::max_u64();
    assert!(expire_timestamp == max_expire_timestamp, ENotSupportedExpireTimestamp);

    // Verify the self matching option is self matching allowed
    assert!(
        self_matching_option == constants::self_matching_allowed(),
        ENotSupportedSelfMatchingOption,
    );

    // Calculate DEEP required for limit order
    let deep_required = calculate_deep_required(pool, quantity, price);

    // Calculate order amount based on order type
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // Prepare order execution
    let (proof, protocol_fee_discount_rate) = prepare_order_execution(
        wrapper,
        trading_fee_config,
        pool,
        reference_pool,
        deep_usd_price_info,
        sui_usd_price_info,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        deep_coin,
        sui_coin,
        deep_required,
        order_amount,
        is_bid,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
        clock,
        ctx,
    );

    // Place limit order
    let order_info = pool.place_limit_order(
        balance_manager,
        &proof,
        client_order_id,
        order_type,
        self_matching_option,
        price,
        quantity,
        is_bid,
        true, // Using DEEP for fees
        expire_timestamp,
        clock,
        ctx,
    );

    // Charge protocol fees
    charge_protocol_fees(
        wrapper,
        trading_fee_config,
        pool,
        balance_manager,
        base_coin,
        quote_coin,
        &order_info,
        order_amount,
        protocol_fee_discount_rate,
        true,
        ctx,
    );

    order_info
}

/// Creates a market order on DeepBook using coins from various sources
/// This function orchestrates the entire market order creation process through the following steps:
/// 1. Creates plans for:
///    - DEEP coin sourcing from user wallet and wrapper reserves
///    - Fee collection in SUI coins
///    - Input coin deposits from wallet to balance manager
/// 2. Executes the plans through shared preparation logic that:
///    - Sources DEEP coins according to the DEEP plan
///    - Collects fees according to the fee plan
///    - Deposits input coins according to the input coin deposit plan
/// 3. Places the market order on DeepBook and returns the order info
///
/// Parameters:
/// - wrapper: The DeepBook wrapper instance managing the order process
/// - trading_fee_config: Trading fee configuration object
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool for price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - deep_coin: DEEP coins from user's wallet
/// - sui_coin: SUI coins for fee payment
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks). For bids, this amount
///                 will be converted into base quantity using current order book state
/// - is_bid: True for buy orders, false for sell orders
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - estimated_deep_required: Amount of DEEP tokens required for the order creation
/// - estimated_deep_required_slippage: Maximum acceptable slippage for estimated DEEP requirement in billionths (e.g., 10_000_000 = 1%)
/// - estimated_sui_fee: Estimated SUI fee which we can take as a protocol for the order creation
/// - estimated_sui_fee_slippage: Maximum acceptable slippage for estimated SUI fee in billionths (e.g., 10_000_000 = 1%)
/// - clock: System clock for timestamp verification
public fun create_market_order<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    wrapper: &mut Wrapper,
    trading_fee_config: &TradingFeeConfig,
    pool: &mut Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    deep_coin: Coin<DEEP>,
    sui_coin: Coin<SUI>,
    order_amount: u64,
    is_bid: bool,
    self_matching_option: u8,
    client_order_id: u64,
    estimated_deep_required: u64,
    estimated_deep_required_slippage: u64,
    estimated_sui_fee: u64,
    estimated_sui_fee_slippage: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo) {
    wrapper.verify_version();

    // Verify the self matching option is self matching allowed
    assert!(
        self_matching_option == constants::self_matching_allowed(),
        ENotSupportedSelfMatchingOption,
    );

    // Calculate base quantity and DEEP required for market order
    let (base_quantity, deep_required) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    // Prepare order execution
    let (proof, protocol_fee_discount_rate) = prepare_order_execution(
        wrapper,
        trading_fee_config,
        pool,
        reference_pool,
        deep_usd_price_info,
        sui_usd_price_info,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        deep_coin,
        sui_coin,
        deep_required,
        order_amount,
        is_bid,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
        clock,
        ctx,
    );

    // Place market order
    let order_info = pool.place_market_order(
        balance_manager,
        &proof,
        client_order_id,
        self_matching_option,
        base_quantity,
        is_bid,
        true, // Using DEEP for fees
        clock,
        ctx,
    );

    // Charge protocol fees
    charge_protocol_fees(
        wrapper,
        trading_fee_config,
        pool,
        balance_manager,
        base_coin,
        quote_coin,
        &order_info,
        order_amount,
        protocol_fee_discount_rate,
        true,
        ctx,
    );

    order_info
}

/// Creates a limit order on DeepBook using coins from user's wallet for whitelisted pools
/// This function orchestrates the order creation process:
/// 1. Calculates required order amount based on price and quantity
/// 2. Prepares order execution by handling coin deposits (see `prepare_whitelisted_order_execution`)
/// 3. Places the limit order on DeepBook and returns the order info
///
/// Note: This function is optimized for whitelisted pools and doesn't require DEEP tokens
/// or additional fee handling since these are not needed for whitelisted pools.
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - price: Order price in quote tokens per base token
/// - quantity: Order quantity in base tokens
/// - is_bid: True for buy orders, false for sell orders
/// - expire_timestamp: Order expiration timestamp
/// - order_type: Type of order (e.g., GTC, IOC, FOK)
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - clock: System clock for timestamp verification
public fun create_limit_order_whitelisted<BaseToken, QuoteToken>(
    pool: &mut Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    base_coin: Coin<BaseToken>,
    quote_coin: Coin<QuoteToken>,
    price: u64,
    quantity: u64,
    is_bid: bool,
    expire_timestamp: u64,
    order_type: u8,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo) {
    // Calculate order amount based on order type
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // Prepare order execution
    let proof = prepare_whitelisted_order_execution(
        balance_manager,
        base_coin,
        quote_coin,
        order_amount,
        is_bid,
        ctx,
    );

    // Place limit order
    pool.place_limit_order(
        balance_manager,
        &proof,
        client_order_id,
        order_type,
        self_matching_option,
        price,
        quantity,
        is_bid,
        false, // pay_with_deep is false for whitelisted pools
        expire_timestamp,
        clock,
        ctx,
    )
}

/// Creates a market order on DeepBook using coins from user's wallet for whitelisted pools
/// This function orchestrates the order creation process:
/// 1. Calculates base quantity from order amount using current order book state
/// 2. Prepares order execution by handling coin deposits (see `prepare_whitelisted_order_execution`)
/// 3. Places the market order on DeepBook and returns the order info
///
/// Note: This function is optimized for whitelisted pools and doesn't require DEEP tokens
/// or additional fee handling since these are not needed for whitelisted pools.
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - clock: System clock for order book state
public fun create_market_order_whitelisted<BaseToken, QuoteToken>(
    pool: &mut Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    base_coin: Coin<BaseToken>,
    quote_coin: Coin<QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo) {
    // Calculate base quantity for market order
    let (base_quantity, _) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    // Prepare order execution
    let proof = prepare_whitelisted_order_execution(
        balance_manager,
        base_coin,
        quote_coin,
        order_amount,
        is_bid,
        ctx,
    );

    // Place market order
    pool.place_market_order(
        balance_manager,
        &proof,
        client_order_id,
        self_matching_option,
        base_quantity,
        is_bid,
        false, // pay_with_deep is false for whitelisted pools
        clock,
        ctx,
    )
}

/// Creates a limit order on DeepBook using input coins for fees
/// This function orchestrates the limit order creation process through the following steps:
/// 1. Creates plans for:
///    - Fee collection in input coins
///    - Input coin deposits from wallet to balance manager
/// 2. Executes the plans through shared preparation logic that:
///    - Collects fees according to the input coin fee plan
///    - Deposits input coins according to the input coin deposit plan
/// 3. Places the limit order on DeepBook and returns the order info
///
/// Parameters:
/// * `wrapper` - The DeepBook wrapper instance managing the order process
/// * `trading_fee_config` - Trading fee configuration object
/// * `pool` - The trading pool where the order will be placed
/// * `balance_manager` - User's balance manager for managing coin deposits
/// * `base_coin` - Base token coins from user's wallet
/// * `quote_coin` - Quote token coins from user's wallet
/// * `price` - Order price in quote tokens per base token
/// * `quantity` - Order quantity in base tokens
/// * `is_bid` - True for buy orders, false for sell orders
/// * `expire_timestamp` - Order expiration timestamp
/// * `order_type` - Type of order (e.g., GTC, IOC, FOK)
/// * `self_matching_option` - Self-matching behavior configuration
/// * `client_order_id` - Client-provided order identifier
/// * `clock` - System clock for timestamp verification
public fun create_limit_order_input_fee<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    trading_fee_config: &TradingFeeConfig,
    pool: &mut Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    price: u64,
    quantity: u64,
    is_bid: bool,
    expire_timestamp: u64,
    order_type: u8,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo) {
    wrapper.verify_version();

    // Calculate order amount based on order type
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // Prepare order execution
    let proof = prepare_input_fee_order_execution(
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        order_amount,
        is_bid,
        ctx,
    );

    // Place limit order with pay_with_deep set to false since we're using input coins for fees
    let order_info = pool.place_limit_order(
        balance_manager,
        &proof,
        client_order_id,
        order_type,
        self_matching_option,
        price,
        quantity,
        is_bid,
        false, // Using input coins for fees
        expire_timestamp,
        clock,
        ctx,
    );

    // Charge protocol fees
    charge_protocol_fees(
        wrapper,
        trading_fee_config,
        pool,
        balance_manager,
        base_coin,
        quote_coin,
        &order_info,
        order_amount,
        0, // No discount rate for input fee orders
        false,
        ctx,
    );

    order_info
}

/// Creates a market order on DeepBook using input coins for fees
/// This function orchestrates the market order creation process through the following steps:
/// 1. Creates plans for:
///    - Fee collection in input coins
///    - Input coin deposits from wallet to balance manager
/// 2. Executes the plans through shared preparation logic that:
///    - Collects fees according to the input coin fee plan
///    - Deposits input coins according to the input coin deposit plan
/// 3. Places the market order on DeepBook and returns the order info
///
/// Parameters:
/// * `wrapper` - The DeepBook wrapper instance managing the order process
/// * `trading_fee_config` - Trading fee configuration object
/// * `pool` - The trading pool where the order will be placed
/// * `balance_manager` - User's balance manager for managing coin deposits
/// * `base_coin` - Base token coins from user's wallet
/// * `quote_coin` - Quote token coins from user's wallet
/// * `order_amount` - Order amount in quote tokens (for bids) or base tokens (for asks)
/// * `is_bid` - True for buy orders, false for sell orders
/// * `self_matching_option` - Self-matching behavior configuration
/// * `client_order_id` - Client-provided order identifier
/// * `clock` - System clock for timestamp verification
public fun create_market_order_input_fee<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    trading_fee_config: &TradingFeeConfig,
    pool: &mut Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo) {
    wrapper.verify_version();

    // We use calculate_market_order_params to get base quantity, which uses `get_quantity_out` under the hood,
    // since `get_quantity_out` returns `base_quantity` without applying fees to it.
    // We do need that, since we have to apply our protocol fee & deepbook fee on top of the order amount.
    let (base_quantity, _) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    // Prepare order execution
    let proof = prepare_input_fee_order_execution(
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        order_amount,
        is_bid,
        ctx,
    );

    // Place market order with pay_with_deep set to false since we're using input coins for fees
    let order_info = pool.place_market_order(
        balance_manager,
        &proof,
        client_order_id,
        self_matching_option,
        base_quantity,
        is_bid,
        false, // Using input coins for fees
        clock,
        ctx,
    );

    // Charge protocol fees
    charge_protocol_fees(
        wrapper,
        trading_fee_config,
        pool,
        balance_manager,
        base_coin,
        quote_coin,
        &order_info,
        order_amount,
        0, // No discount rate for input fee orders
        false,
        ctx,
    );

    order_info
}

public fun cancel_order_and_settle_fees<BaseAsset, QuoteAsset, UnsettledFeeCoinType>(
    wrapper: &mut Wrapper,
    pool: &mut Pool<BaseAsset, QuoteAsset>,
    balance_manager: &mut BalanceManager,
    order_id: u128,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<UnsettledFeeCoinType> {
    // Settle the fees
    let settled_fees = wrapper.settle_user_fees<BaseAsset, QuoteAsset, UnsettledFeeCoinType>(
        pool,
        balance_manager,
        order_id,
        ctx,
    );

    // Cancel the order
    let trade_proof = balance_manager.generate_proof_as_owner(ctx);
    pool.cancel_order(balance_manager, &trade_proof, order_id, clock, ctx);

    settled_fees
}

// === Public-Package Functions ===
/// Core logic function that orchestrates the creation of both limit and market orders using coins from various sources
/// Coordinates all requirements by analyzing available resources and calculating necessary allocations
/// Creates comprehensive plans for DEEP coins sourcing, fee charging, and input coin deposits
///
/// Parameters:
/// - is_pool_whitelisted: Whether the pool is whitelisted by DeepBook
/// - deep_required: Amount of DEEP required for the order
/// - balance_manager_deep: Amount of DEEP in user's balance manager
/// - balance_manager_sui: Amount of SUI in user's balance manager
/// - balance_manager_input_coin: Amount of input coins (base/quote) in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - sui_in_wallet: Amount of SUI in user's wallet
/// - wallet_input_coin: Amount of input coins (base/quote) in user's wallet
/// - wrapper_deep_reserves: Amount of DEEP available in wrapper reserves
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - protocol_fee_rate: Protocol fee rate in billionths
/// - sui_per_deep: Current DEEP/SUI price from reference pool
///
/// Returns a tuple with three structured plans:
/// - DeepPlan: Coordinates DEEP coin sourcing from user wallet and wrapper reserves
/// - CoverageFeePlan: Specifies fee amount and sources for SUI fee payment
/// - InputCoinDepositPlan: Determines how input coins will be sourced for the order
public(package) fun create_order_core(
    is_pool_whitelisted: bool,
    deep_required: u64,
    balance_manager_deep: u64,
    balance_manager_sui: u64,
    balance_manager_input_coin: u64,
    deep_in_wallet: u64,
    sui_in_wallet: u64,
    wallet_input_coin: u64,
    wrapper_deep_reserves: u64,
    order_amount: u64,
    sui_per_deep: u64,
): (DeepPlan, CoverageFeePlan, InputCoinDepositPlan) {
    // Step 1: Determine DEEP requirements
    let deep_plan = get_deep_plan(
        is_pool_whitelisted,
        deep_required,
        balance_manager_deep,
        deep_in_wallet,
        wrapper_deep_reserves,
    );

    // Step 2: Determine coverage fee charging plan
    let coverage_fee_plan = get_coverage_fee_plan(
        deep_plan.use_wrapper_deep_reserves,
        deep_plan.from_deep_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Step 3: Determine input coin deposit plan
    let deposit_plan = get_input_coin_deposit_plan(
        order_amount,
        wallet_input_coin,
        balance_manager_input_coin,
    );

    (deep_plan, coverage_fee_plan, deposit_plan)
}

/// Analyzes DEEP coin requirements for an order and creates a sourcing plan
/// Evaluates user's available DEEP coins and determines if wrapper reserves are needed
/// Calculates optimal allocation from user wallet, balance manager, and wrapper reserves
///
/// Returns a DeepPlan structure with the following information:
/// - use_wrapper_deep_reserves: Whether DEEP from wrapper reserves will be used
/// - from_user_wallet: Amount of DEEP to take from user's wallet
/// - from_deep_reserves: Amount of DEEP to take from wrapper reserves
/// - deep_reserves_cover_order: Whether wrapper has enough DEEP to cover what's needed
public(package) fun get_deep_plan(
    is_pool_whitelisted: bool,
    deep_required: u64,
    balance_manager_deep: u64,
    deep_in_wallet: u64,
    wrapper_deep_reserves: u64,
): DeepPlan {
    // If pool is whitelisted, no DEEP is needed
    if (is_pool_whitelisted) {
        return DeepPlan {
            use_wrapper_deep_reserves: false,
            from_user_wallet: 0,
            from_deep_reserves: 0,
            deep_reserves_cover_order: true,
        }
    };

    // Calculate how much DEEP the user has available
    let user_deep_total = balance_manager_deep + deep_in_wallet;

    if (user_deep_total >= deep_required) {
        // User has enough DEEP
        // Determine how much to take from wallet based on what's available
        let from_wallet = if (balance_manager_deep >= deep_required) {
            0 // Nothing needed from wallet if balance manager has enough
        } else {
            deep_required - balance_manager_deep
        };

        DeepPlan {
            use_wrapper_deep_reserves: false,
            from_user_wallet: from_wallet,
            from_deep_reserves: 0,
            deep_reserves_cover_order: true,
        }
    } else {
        // Need wrapper DEEP since user doesn't have enough
        let from_wallet = deep_in_wallet; // Take all from wallet
        let still_needed = deep_required - user_deep_total;
        let has_enough = wrapper_deep_reserves >= still_needed;

        if (!has_enough) {
            return DeepPlan {
                use_wrapper_deep_reserves: true,
                from_user_wallet: 0,
                from_deep_reserves: 0,
                deep_reserves_cover_order: false,
            }
        };

        DeepPlan {
            use_wrapper_deep_reserves: true,
            from_user_wallet: from_wallet,
            from_deep_reserves: still_needed,
            deep_reserves_cover_order: true,
        }
    }
}

/// Creates a coverage fee plan for order execution by determining optimal sources for coverage fee payment
/// in SUI coins.
/// Returns early with zero fees for whitelisted pools or when not using wrapper DEEP.
///
/// # Arguments
/// * `use_wrapper_deep_reserves` - Whether the order requires DEEP from wrapper reserves
/// * `deep_from_reserves` - Amount of DEEP to be taken from wrapper reserves
/// * `is_pool_whitelisted` - Whether the pool is whitelisted by DeepBook
/// * `protocol_fee_rate` - Protocol fee rate in billionths
/// * `sui_per_deep` - Current DEEP/SUI price from reference pool
/// * `sui_in_wallet` - Amount of SUI available in user's wallet
/// * `balance_manager_sui` - Amount of SUI available in user's balance manager
///
/// # Returns
/// * `CoverageFeePlan` - Struct containing:
///   - Coverage fee amounts from wallet and balance manager
///   - Protocol fee amounts from wallet and balance manager
///   - Whether user has sufficient funds to cover fees
///
/// # Flow
/// 1. Returns zero fee plan if pool is whitelisted or not using wrapper DEEP
/// 2. Calculates total fee, coverage fee, and protocol fee
/// 3. Returns zero fee plan if total fee is zero
/// 4. Returns insufficient fee plan if user lacks total funds
/// 5. Plans coverage fee collection from available sources
/// 6. Plans protocol fee collection from remaining funds
public(package) fun get_coverage_fee_plan(
    use_wrapper_deep_reserves: bool,
    deep_from_reserves: u64,
    is_pool_whitelisted: bool,
    sui_per_deep: u64,
    sui_in_wallet: u64,
    balance_manager_sui: u64,
): CoverageFeePlan {
    // No fee for whitelisted pools or when not using wrapper DEEP
    if (is_pool_whitelisted || !use_wrapper_deep_reserves) {
        return zero_coverage_fee_plan()
    };

    // Calculate coverage fee based on order amount
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );

    // If no fee, return early
    if (coverage_fee == 0) {
        return zero_coverage_fee_plan()
    };

    // Check if user has enough total coins
    let total_available = sui_in_wallet + balance_manager_sui;
    if (total_available < coverage_fee) {
        return insufficient_coverage_fee_plan()
    };

    // Plan coverage fee collection
    let (from_wallet, from_balance_manager) = plan_fee_collection(
        coverage_fee,
        sui_in_wallet,
        balance_manager_sui,
    );

    CoverageFeePlan {
        from_wallet,
        from_balance_manager,
        user_covers_fee: true,
    }
}

public(package) fun get_protocol_fee_plan(
    order_info: &OrderInfo,
    taker_fee_rate: u64,
    maker_fee_rate: u64,
    coin_in_wallet: u64,
    coin_in_balance_manager: u64,
    order_amount: u64,
    discount_rate: u64,
): ProtocolFeePlan {
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        taker_fee_rate,
        maker_fee_rate,
        order_amount,
        discount_rate,
    );

    // If no fee, return early
    if (total_fee == 0) {
        return zero_protocol_fee_plan()
    };

    // Check if user has enough total coins
    let total_available = coin_in_wallet + coin_in_balance_manager;
    if (total_available < total_fee) {
        return insufficient_protocol_fee_plan()
    };

    // Plan taker fee collection
    let (taker_fee_from_wallet, taker_fee_from_balance_manager) = plan_fee_collection(
        taker_fee,
        coin_in_wallet,
        coin_in_balance_manager,
    );

    // Adjust available amounts for maker fee planning
    let remaining_in_wallet = coin_in_wallet - taker_fee_from_wallet;
    let remaining_in_bm = coin_in_balance_manager - taker_fee_from_balance_manager;

    // Plan maker fee collection
    let (maker_fee_from_wallet, maker_fee_from_balance_manager) = plan_fee_collection(
        maker_fee,
        remaining_in_wallet,
        remaining_in_bm,
    );

    ProtocolFeePlan {
        taker_fee_from_wallet,
        taker_fee_from_balance_manager,
        maker_fee_from_wallet,
        maker_fee_from_balance_manager,
        user_covers_fee: true,
    }
}

/// Creates an input coin deposit plan for order execution - core logic
/// Determines how to source required input coins from user wallet and balance manager
/// For bid orders, calculates quote coins needed; for ask orders, calculates base coins needed
///
/// Returns an InputCoinDepositPlan structure with the following information:
/// - order_amount: Total amount of input coins needed for the order
/// - from_user_wallet: Amount of input coins to take from user's wallet
/// - user_has_enough_input_coin: Whether user has enough input coins for the order
public(package) fun get_input_coin_deposit_plan(
    required_amount: u64,
    wallet_balance: u64,
    balance_manager_balance: u64,
): InputCoinDepositPlan {
    // Check if we already have enough in the balance manager
    if (balance_manager_balance >= required_amount) {
        return InputCoinDepositPlan {
            order_amount: required_amount,
            from_user_wallet: 0,
            user_has_enough_input_coin: true,
        }
    };

    // Calculate how much more is needed
    let additional_needed = required_amount - balance_manager_balance;
    let has_enough = wallet_balance >= additional_needed;

    if (!has_enough) {
        return InputCoinDepositPlan {
            order_amount: required_amount,
            from_user_wallet: 0,
            user_has_enough_input_coin: false,
        }
    };

    InputCoinDepositPlan {
        order_amount: required_amount,
        from_user_wallet: additional_needed,
        user_has_enough_input_coin: true,
    }
}

/// Plans optimal fee collection strategy from available sources, prioritizing balance manager usage.
/// Returns early with zero amounts if no fee to collect.
///
/// # Arguments
/// * `fee_amount` - Amount of fee to be collected
/// * `available_in_wallet` - Amount of coins available in user's wallet
/// * `available_in_bm` - Amount of coins available in user's balance manager
///
/// # Returns
/// * `(u64, u64)` - Tuple containing:
///   - Amount to collect from wallet
///   - Amount to collect from balance manager
///
/// # Flow
/// 1. Returns (0, 0) if fee amount is zero
/// 2. Verifies total available funds are sufficient
/// 3. Takes entire amount from balance manager if possible
/// 4. Otherwise, takes maximum from balance manager and remainder from wallet
///
/// # Aborts
/// * `EInsufficientFee` - If total available funds are less than required fee
public(package) fun plan_fee_collection(
    fee_amount: u64,
    available_in_wallet: u64,
    available_in_bm: u64,
): (u64, u64) {
    // If no fee to collect, return zeros
    if (fee_amount == 0) {
        return (0, 0)
    };

    // Verify user has enough total funds before proceeding
    assert!(available_in_wallet + available_in_bm >= fee_amount, EInsufficientFee);

    // Safely plan fee collection knowing user has enough funds
    if (available_in_bm >= fee_amount) {
        // Take all from balance manager if possible
        (0, fee_amount)
    } else {
        // Take what we can from balance manager and rest from wallet
        let from_bm = available_in_bm;
        let from_wallet = fee_amount - from_bm;
        (from_wallet, from_bm)
    }
}

/// Validates that actual fees don't exceed maximum allowed amounts with slippage
/// Checks both DEEP and SUI fees against their respective limits
///
/// Parameters:
/// - deep_required: Actual amount of DEEP required for the order
/// - deep_from_reserves: Amount of DEEP to be taken from wrapper reserves
/// - protocol_fee_rate: Protocol fee rate in billionths
/// - sui_per_deep: Current DEEP/SUI price from reference pool
/// - estimated_deep_required: Estimated DEEP requirement used to calculate maximum allowed one
/// - estimated_deep_required_slippage: Slippage in billionths applied to estimated DEEP requirement for maximum calculation
/// - estimated_sui_fee: Estimated SUI fee used to calculate maximum allowed SUI fee
/// - estimated_sui_fee_slippage: Slippage in billionths applied to estimated SUI fee for maximum calculation
public(package) fun validate_fees_against_max(
    deep_required: u64,
    deep_from_reserves: u64,
    sui_per_deep: u64,
    estimated_deep_required: u64,
    estimated_deep_required_slippage: u64,
    estimated_sui_fee: u64,
    estimated_sui_fee_slippage: u64,
) {
    // Calculate maximum allowed fees
    let max_deep_required = apply_slippage(
        estimated_deep_required,
        estimated_deep_required_slippage,
    );
    let max_sui_fee = apply_slippage(estimated_sui_fee, estimated_sui_fee_slippage);

    // Validate DEEP fee
    assert!(deep_required <= max_deep_required, EDeepRequiredExceedsMax);

    // Validate SUI fee (only applies when using wrapper DEEP reserves)
    if (deep_from_reserves > 0) {
        let actual_sui_fee = calculate_deep_reserves_coverage_order_fee(
            sui_per_deep,
            deep_from_reserves,
        );
        assert!(actual_sui_fee <= max_sui_fee, ESuiFeeExceedsMax);
    };
}

/// Charges protocol fees for a given order with input coins
public(package) fun charge_protocol_fees<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    trading_fee_config: &TradingFeeConfig,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    order_info: &OrderInfo,
    order_amount: u64,
    discount_rate: u64,
    deep_fee_type: bool,
    ctx: &mut TxContext,
) {
    // Get the protocol fee rates for the pool
    let pool_protocol_fee_config = trading_fee_config.get_fee_rates(pool);
    let (protocol_taker_fee_rate, protocol_maker_fee_rate) = if (deep_fee_type) {
        pool_protocol_fee_config.deep_fee_type_rates()
    } else {
        pool_protocol_fee_config.input_coin_fee_type_rates()
    };

    let is_bid = order_info.is_bid();

    // Get balances from balance manager
    let balance_manager_base = balance_manager.balance<BaseToken>();
    let balance_manager_quote = balance_manager.balance<QuoteToken>();
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let base_in_wallet = base_coin.value();
    let quote_in_wallet = quote_coin.value();
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    // Get fee plan
    let fee_plan = get_protocol_fee_plan(
        order_info,
        protocol_taker_fee_rate,
        protocol_maker_fee_rate,
        wallet_input_coin,
        balance_manager_input_coin,
        order_amount,
        discount_rate,
    );

    // Execute protocol fee plan
    if (is_bid) {
        execute_protocol_fee_plan(
            wrapper,
            balance_manager,
            &mut quote_coin,
            order_info,
            &fee_plan,
            ctx,
        );
    } else {
        execute_protocol_fee_plan(
            wrapper,
            balance_manager,
            &mut base_coin,
            order_info,
            &fee_plan,
            ctx,
        );
    };

    // Return unused coins to the caller
    transfer_if_nonzero(base_coin, ctx.sender());
    transfer_if_nonzero(quote_coin, ctx.sender());
}

// === Private Functions ===
/// Prepares order execution by handling all common order creation logic:
/// 1. Verifies the caller owns the balance manager
/// 2. Validates estimated fee slippage parameters and calculates maximum allowed values
/// 3. Verifies that actual DEEP required and SUI fee don't exceed maximums with slippage
/// 4. Creates plans for DEEP sourcing, fee collection, and input coin deposit
/// 5. Executes the plans in sequence:
///    - Sources DEEP coins from user wallet and wrapper reserves according to DeepPlan
///    - Collects fees in SUI coins according to CoverageFeePlan
///    - Deposits required input coins according to InputCoinDepositPlan
/// 6. Returns unused coins to the caller
/// 7. Returns the balance manager proof needed for order placement
///
/// This function contains the shared execution logic between limit and market orders,
/// processing the plans created by create_order_core.
///
/// Parameters:
/// - wrapper: The DeepBook wrapper instance managing the order process
/// - trading_fee_config: Trading fee configuration object
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool used for fallback DEEP/SUI price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - deep_coin: DEEP coins from user's wallet
/// - sui_coin: SUI coins for fee payment
/// - deep_required: Amount of DEEP required for the order
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - estimated_deep_required: Amount of DEEP tokens required for the order creation
/// - estimated_deep_required_slippage: Maximum acceptable slippage for estimated DEEP requirement in billionths (e.g., 10_000_000 = 1%)
/// - estimated_sui_fee: Estimated SUI fee which we can take as a protocol for the order creation
/// - estimated_sui_fee_slippage: Maximum acceptable slippage for estimated SUI fee in billionths (e.g., 10_000_000 = 1%)
/// - clock: System clock for timestamp verification
fun prepare_order_execution<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    wrapper: &mut Wrapper,
    trading_fee_config: &TradingFeeConfig,
    pool: &Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    mut deep_coin: Coin<DEEP>,
    mut sui_coin: Coin<SUI>,
    deep_required: u64,
    order_amount: u64,
    is_bid: bool,
    estimated_deep_required: u64,
    estimated_deep_required_slippage: u64,
    estimated_sui_fee: u64,
    estimated_sui_fee_slippage: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (TradeProof, u64) {
    wrapper.verify_version();

    // Verify the caller owns the balance manager
    assert!(balance_manager.owner() == ctx.sender(), EInvalidOwner);

    // Validate slippage parameters
    validate_slippage(estimated_deep_required_slippage);
    validate_slippage(estimated_sui_fee_slippage);

    // Get the best DEEP/SUI price
    let sui_per_deep = get_sui_per_deep(
        deep_usd_price_info,
        sui_usd_price_info,
        reference_pool,
        clock,
    );

    // Extract all the data we need from DeepBook objects
    let is_pool_whitelisted = pool.whitelisted();

    // Get balances from balance manager
    let balance_manager_deep = balance_manager.balance<DEEP>();
    let balance_manager_sui = balance_manager.balance<SUI>();
    let balance_manager_base = balance_manager.balance<BaseToken>();
    let balance_manager_quote = balance_manager.balance<QuoteToken>();
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let deep_in_wallet = deep_coin.value();
    let sui_in_wallet = sui_coin.value();
    let base_in_wallet = base_coin.value();
    let quote_in_wallet = quote_coin.value();
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    // Get wrapper deep reserves
    let wrapper_deep_reserves = deep_reserves(wrapper);

    // Get the max protocol fee discount rate
    let max_discount_rate = trading_fee_config.get_fee_rates(pool).max_deep_fee_discount_rate();

    // Get the order plans from the core logic
    let (deep_plan, coverage_fee_plan, input_coin_deposit_plan) = create_order_core(
        is_pool_whitelisted,
        deep_required,
        balance_manager_deep,
        balance_manager_sui,
        balance_manager_input_coin,
        deep_in_wallet,
        sui_in_wallet,
        wallet_input_coin,
        wrapper_deep_reserves,
        order_amount,
        sui_per_deep,
    );

    // Validate actual fees against maximum allowed ones
    validate_fees_against_max(
        deep_required,
        deep_plan.from_deep_reserves,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );

    // Calculate protocol fees discount rate
    let discount_rate = calculate_discount_rate(
        max_discount_rate,
        deep_plan.from_deep_reserves,
        deep_required,
    );

    // Step 1: Execute DEEP plan
    execute_deep_plan(wrapper, balance_manager, &mut deep_coin, &deep_plan, ctx);

    // Step 2: Execute coverage fee charging plan
    execute_coverage_fee_plan(
        wrapper,
        balance_manager,
        &mut sui_coin,
        &coverage_fee_plan,
        ctx,
    );

    // Step 3: Execute input coin deposit plan
    execute_input_coin_deposit_plan(
        balance_manager,
        base_coin,
        quote_coin,
        &input_coin_deposit_plan,
        is_bid,
        ctx,
    );

    // Return unused coins to the caller. Base and quote coins will be returned after protocol fees charging
    transfer_if_nonzero(deep_coin, ctx.sender());
    transfer_if_nonzero(sui_coin, ctx.sender());

    // Generate and return proof and protocol fee discount rate
    (balance_manager.generate_proof_as_owner(ctx), discount_rate)
}

/// Prepares order execution for whitelisted pools by handling coin deposits
/// This function contains the shared logic for both limit and market orders in whitelisted pools,
/// focusing only on input coin management without DEEP or fee handling
///
/// Steps:
/// 1. Verifies the caller owns the balance manager
/// 2. Creates and executes input coin deposit plan
/// 3. Returns unused coins to the caller
/// 4. Returns the balance manager proof needed for order placement
///
/// Parameters:
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
fun prepare_whitelisted_order_execution<BaseToken, QuoteToken>(
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    ctx: &mut TxContext,
): TradeProof {
    // Verify the caller owns the balance manager
    assert!(balance_manager.owner() == ctx.sender(), EInvalidOwner);

    // Get balances from balance manager
    let balance_manager_base = balance_manager.balance<BaseToken>();
    let balance_manager_quote = balance_manager.balance<QuoteToken>();
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let base_in_wallet = base_coin.value();
    let quote_in_wallet = quote_coin.value();
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    // Step 1: Determine input coin deposit plan
    let input_coin_deposit_plan = get_input_coin_deposit_plan(
        order_amount,
        wallet_input_coin,
        balance_manager_input_coin,
    );

    // Step 2: Execute input coin deposit plan
    execute_input_coin_deposit_plan(
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &input_coin_deposit_plan,
        is_bid,
        ctx,
    );

    // Step 3: Return unused coins to the caller
    transfer_if_nonzero(base_coin, ctx.sender());
    transfer_if_nonzero(quote_coin, ctx.sender());

    // Step 4: Generate and return proof
    balance_manager.generate_proof_as_owner(ctx)
}

/// Prepares order execution by handling input coin fee and deposit logic
/// 1. Verifies the caller owns the balance manager
/// 2. Creates plans for:
///    - Fee collection in input coins
///    - Input coin deposits from wallet to balance manager
/// 3. Executes the plans in sequence:
///    - Collects fees according to the input coin fee plan
///    - Deposits input coins according to the input coin deposit plan
/// 4. Returns unused coins to the caller
/// 5. Returns the balance manager proof needed for order placement
///
/// Parameters:
/// * `wrapper` - The DeepBook wrapper instance managing the order process
/// * `trading_fee_config` - Trading fee configuration object
/// * `pool` - The trading pool where the order will be placed
/// * `balance_manager` - User's balance manager for managing coin deposits
/// * `base_coin` - Base token coins from user's wallet
/// * `quote_coin` - Quote token coins from user's wallet
/// * `taker_fee` - DeepBook's taker fee rate in billionths
/// * `order_amount` - Order amount in quote tokens (for bids) or base tokens (for asks)
/// * `is_bid` - True for buy orders, false for sell orders
fun prepare_input_fee_order_execution<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    ctx: &mut TxContext,
): TradeProof {
    // Verify the caller owns the balance manager
    assert!(balance_manager.owner() == ctx.sender(), EInvalidOwner);

    // Get balances from balance manager
    let balance_manager_base = balance_manager.balance<BaseToken>();
    let balance_manager_quote = balance_manager.balance<QuoteToken>();
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let base_in_wallet = base_coin.value();
    let quote_in_wallet = quote_coin.value();
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    // Calculate DeepBook fee
    let (deepbook_taker_fee, _, _) = pool.pool_trade_params();
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, deepbook_taker_fee);

    // Calculate total amount needed to be on the balance manager
    let total_amount = order_amount + deepbook_fee;

    // Determine input coin deposit plan
    let input_coin_deposit_plan = get_input_coin_deposit_plan(
        total_amount,
        wallet_input_coin,
        balance_manager_input_coin,
    );

    // Execute input coin deposit plan
    execute_input_coin_deposit_plan(
        balance_manager,
        base_coin,
        quote_coin,
        &input_coin_deposit_plan,
        is_bid,
        ctx,
    );

    // Generate and return proof
    balance_manager.generate_proof_as_owner(ctx)
}

/// Executes the DEEP coin sourcing plan by acquiring coins from specified sources
/// Sources DEEP coins from user wallet and/or wrapper reserves based on the deep plan
/// Deposits all acquired DEEP coins to the user's balance manager for order placement
///
/// Steps performed:
/// 1. Verifies the wrapper has enough DEEP reserves if they will be used
/// 2. Takes DEEP coins from user wallet when specified in the plan
/// 3. Takes DEEP coins from wrapper reserves when needed
/// 4. Deposits all acquired DEEP coins to the balance manager
fun execute_deep_plan(
    wrapper: &mut Wrapper,
    balance_manager: &mut BalanceManager,
    deep_coin: &mut Coin<DEEP>,
    deep_plan: &DeepPlan,
    ctx: &mut TxContext,
) {
    wrapper.verify_version();

    // Check if there is enough DEEP in the wrapper reserves
    if (deep_plan.use_wrapper_deep_reserves) {
        assert!(deep_plan.deep_reserves_cover_order, EInsufficientDeepReserves);
    };

    // Take DEEP from wallet if needed
    if (deep_plan.from_user_wallet > 0) {
        let payment = deep_coin.split(deep_plan.from_user_wallet, ctx);
        balance_manager.deposit(payment, ctx);
    };

    // Take DEEP from wrapper reserves if needed
    if (deep_plan.from_deep_reserves > 0) {
        let reserve_payment = split_deep_reserves(wrapper, deep_plan.from_deep_reserves, ctx);

        balance_manager.deposit(reserve_payment, ctx);
    };
}

/// Executes the fee charging plan by taking SUI coins from specified sources
/// Takes fees in SUI coins from user's wallet and balance manager.
/// Splits the collection into two parts: coverage fees and protocol fees.
///
/// # Arguments
/// * `wrapper` - Main wrapper object that will receive the fees
/// * `balance_manager` - User's balance manager to withdraw fees from
/// * `sui_coin` - User's SUI coins to take fees from
/// * `fee_plan` - Plan that specifies how much to take from each source
/// * `ctx` - Transaction context
///
/// # Flow
/// 1. Checks if user can pay fees
/// 2. Collects coverage fees:
///    - Takes from wallet if needed
///    - Takes from balance manager if needed
/// 3. Collects protocol fees:
///    - Takes from wallet if needed
///    - Takes from balance manager if needed
///
/// # Aborts
/// * `EInsufficientFee` - If user cannot cover the fees
fun execute_coverage_fee_plan(
    wrapper: &mut Wrapper,
    balance_manager: &mut BalanceManager,
    sui_coin: &mut Coin<SUI>,
    fee_plan: &CoverageFeePlan,
    ctx: &mut TxContext,
) {
    wrapper.verify_version();

    // Verify user covers wrapper fee
    assert!(fee_plan.user_covers_fee, EInsufficientFee);

    // Collect coverage fee from wallet if needed
    if (fee_plan.from_wallet > 0) {
        let fee = sui_coin.balance_mut().split(fee_plan.from_wallet);
        join_deep_reserves_coverage_fee(wrapper, fee);
    };

    // Collect coverage fee from balance manager if needed
    if (fee_plan.from_balance_manager > 0) {
        let fee = balance_manager.withdraw<SUI>(
            fee_plan.from_balance_manager,
            ctx,
        );
        join_deep_reserves_coverage_fee(wrapper, fee.into_balance());
    };
}

/// Executes the fee charging plan by taking input coins from specified sources
/// Takes fees in input coins from user's wallet and balance manager
///
/// # Arguments
/// * `wrapper` - Main wrapper object that will receive the fees
/// * `balance_manager` - User's balance manager to withdraw fees from
/// * `base_coin` - User's base coin from wallet
/// * `quote_coin` - User's quote coin from wallet
/// * `fee_plan` - Plan that specifies how much to take from each source
/// * `is_bid` - True for buy orders, false for sell orders
/// * `ctx` - Transaction context
///
/// # Flow
/// 1. Checks if user can pay fees
/// 2. Collects protocol fees:
///    - Takes from wallet if needed
///    - Takes from balance manager if needed
///
/// # Aborts
/// * `EInsufficientFee` - If user cannot cover the fees
fun execute_protocol_fee_plan<CoinType>(
    wrapper: &mut Wrapper,
    balance_manager: &mut BalanceManager,
    coin: &mut Coin<CoinType>,
    order_info: &OrderInfo,
    fee_plan: &ProtocolFeePlan,
    ctx: &mut TxContext,
) {
    wrapper.verify_version();

    // Verify user covers protocol fee
    assert!(fee_plan.user_covers_fee, EInsufficientFee);

    // Collect taker fee from wallet if needed
    if (fee_plan.taker_fee_from_wallet > 0) {
        let fee = coin.balance_mut().split(fee_plan.taker_fee_from_wallet);
        join_protocol_fee(wrapper, fee);
    };

    // Collect taker fee from balance manager if needed
    if (fee_plan.taker_fee_from_balance_manager > 0) {
        let fee = balance_manager.withdraw<CoinType>(
            fee_plan.taker_fee_from_balance_manager,
            ctx,
        );
        join_protocol_fee(wrapper, fee.into_balance());
    };

    // Add maker fee from wallet to unsettled fees if needed
    if (fee_plan.maker_fee_from_wallet > 0) {
        let fee = coin.balance_mut().split(fee_plan.maker_fee_from_wallet);
        add_unsettled_fee(
            wrapper,
            fee,
            order_info,
        );
    };

    // Add maker fee from balance manager to unsettled fees if needed
    if (fee_plan.maker_fee_from_balance_manager > 0) {
        let fee = balance_manager.withdraw<CoinType>(
            fee_plan.maker_fee_from_balance_manager,
            ctx,
        );
        add_unsettled_fee(
            wrapper,
            fee.into_balance(),
            order_info,
        );
    };
}

/// Executes the input coin deposit plan by transferring coins to the balance manager
/// Deposits required input coins from user wallet to balance manager based on the plan
/// Handles different coin types based on order type: quote coins for bid orders, base coins for ask orders
///
/// Steps performed:
/// 1. Verifies the user has enough input coins to satisfy the deposit requirements
/// 2. For bid orders: transfers quote coins from user wallet to balance manager
/// 3. For ask orders: transfers base coins from user wallet to balance manager
fun execute_input_coin_deposit_plan<BaseToken, QuoteToken>(
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    deposit_plan: &InputCoinDepositPlan,
    is_bid: bool,
    ctx: &mut TxContext,
) {
    // Verify there are enough coins to satisfy the deposit requirements
    if (deposit_plan.order_amount > 0) {
        assert!(deposit_plan.user_has_enough_input_coin, EInsufficientInput);
    };

    // Deposit coins from wallet if needed
    if (deposit_plan.from_user_wallet > 0) {
        if (is_bid) {
            // Quote coins for bid
            let payment = quote_coin.split(deposit_plan.from_user_wallet, ctx);
            balance_manager.deposit(payment, ctx);
        } else {
            // Base coins for ask
            let payment = base_coin.split(deposit_plan.from_user_wallet, ctx);
            balance_manager.deposit(payment, ctx);
        };
    };
}

/// Makes a fee plan where no fees need to be collected
fun zero_coverage_fee_plan(): CoverageFeePlan {
    create_empty_coverage_fee_plan(true)
}

/// Makes a fee plan for when user doesn't have enough funds
fun insufficient_coverage_fee_plan(): CoverageFeePlan {
    create_empty_coverage_fee_plan(false)
}

/// Helper to create a fee plan with no fees and specified coverage status
/// The coverage status tells if user can pay fees (true) or not (false)
fun create_empty_coverage_fee_plan(user_covers_fee: bool): CoverageFeePlan {
    CoverageFeePlan {
        from_wallet: 0,
        from_balance_manager: 0,
        user_covers_fee: user_covers_fee,
    }
}

fun zero_protocol_fee_plan(): ProtocolFeePlan {
    create_empty_protocol_fee_plan(true)
}

fun insufficient_protocol_fee_plan(): ProtocolFeePlan {
    create_empty_protocol_fee_plan(false)
}

fun create_empty_protocol_fee_plan(user_covers_fee: bool): ProtocolFeePlan {
    ProtocolFeePlan {
        taker_fee_from_wallet: 0,
        taker_fee_from_balance_manager: 0,
        maker_fee_from_wallet: 0,
        maker_fee_from_balance_manager: 0,
        user_covers_fee,
    }
}

// === Test-Only Functions ===
#[test_only]
public fun assert_deep_plan_eq(
    actual: DeepPlan,
    expected_use_wrapper: bool,
    expected_from_wallet: u64,
    expected_from_wrapper: u64,
    expected_sufficient: bool,
) {
    use std::unit_test::assert_eq;
    assert_eq!(actual.use_wrapper_deep_reserves, expected_use_wrapper);
    assert_eq!(actual.from_user_wallet, expected_from_wallet);
    assert_eq!(actual.from_deep_reserves, expected_from_wrapper);
    assert_eq!(actual.deep_reserves_cover_order, expected_sufficient);
}

#[test_only]
public fun assert_fee_plan_eq(
    actual: CoverageFeePlan,
    expected_from_wallet: u64,
    expected_from_balance_manager: u64,
    expected_sufficient: bool,
) {
    use std::unit_test::assert_eq;
    assert_eq!(actual.from_wallet, expected_from_wallet);
    assert_eq!(actual.from_balance_manager, expected_from_balance_manager);
    assert_eq!(actual.user_covers_fee, expected_sufficient);
}

#[test_only]
public fun assert_input_coin_deposit_plan_eq(
    actual: InputCoinDepositPlan,
    expected_order_amount: u64,
    expected_from_user_wallet: u64,
    expected_sufficient: bool,
) {
    use std::unit_test::assert_eq;
    assert_eq!(actual.order_amount, expected_order_amount);
    assert_eq!(actual.from_user_wallet, expected_from_user_wallet);
    assert_eq!(actual.user_has_enough_input_coin, expected_sufficient);
}
