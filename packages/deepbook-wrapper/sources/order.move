module deepbook_wrapper::order;

use deepbook::balance_manager::{Self, BalanceManager, TradeProof};
use deepbook::pool::{Self, Pool};
use deepbook_wrapper::fee::{
    estimate_full_order_fee_core,
    calculate_full_order_fee,
    calculate_input_coin_protocol_fee,
    calculate_input_coin_deepbook_fee,
};
use deepbook_wrapper::helper::{
    calculate_deep_required,
    transfer_if_nonzero,
    calculate_order_amount,
    get_sui_per_deep,
    calculate_market_order_params,
};
use deepbook_wrapper::math;
use deepbook_wrapper::wrapper::{
    Wrapper,
    join_deep_reserves_coverage_fee,
    join_protocol_fee,
    get_deep_reserves_value,
    split_deep_reserves,
};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use token::deep::DEEP;

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
public struct FeePlan has copy, drop {
    /// Amount of coverage fee to take from user's wallet
    coverage_fee_from_wallet: u64,
    /// Amount of coverage fee to take from user's balance manager
    coverage_fee_from_balance_manager: u64,
    /// Amount of protocol fee to take from user's wallet
    protocol_fee_from_wallet: u64,
    /// Amount of protocol fee to take from user's balance manager
    protocol_fee_from_balance_manager: u64,
    /// Whether user has enough coins to cover both fees
    user_covers_wrapper_fee: bool,
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

/// Tracks fee charging strategy for an order when fee is paid in input coins
/// Determines amount and sources for fee payment
public struct InputCoinFeePlan has copy, drop {
    /// Amount of protocol fee to take from user's wallet
    protocol_fee_from_wallet: u64,
    /// Amount of protocol fee to take from user's balance manager
    protocol_fee_from_balance_manager: u64,
    /// Whether user has enough coins to cover the fee
    user_covers_wrapper_fee: bool,
}

// === Errors ===
/// Error when trying to use deep from reserves but there is not enough available
#[error]
const EInsufficientDeepReserves: u64 = 1;

/// Error when user doesn't have enough coins to cover the required fee
#[error]
const EInsufficientFee: u64 = 2;

/// Error when user doesn't have enough input coins to create the order
#[error]
const EInsufficientInput: u64 = 3;

/// Error when the caller is not the owner of the balance manager
#[error]
const EInvalidOwner: u64 = 4;

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
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool used for SUI/DEEP price calculation
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
/// - clock: System clock for timestamp verification
public fun create_limit_order<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    wrapper: &mut Wrapper,
    pool: &mut Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    balance_manager: &mut BalanceManager,
    base_coin: Coin<BaseToken>,
    quote_coin: Coin<QuoteToken>,
    deep_coin: Coin<DEEP>,
    sui_coin: Coin<SUI>,
    price: u64,
    quantity: u64,
    is_bid: bool,
    expire_timestamp: u64,
    order_type: u8,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (deepbook::order_info::OrderInfo) {
    // Calculate DEEP required for limit order
    let deep_required = calculate_deep_required(pool, quantity, price);

    // Calculate order amount based on order type
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // Prepare order execution
    let proof = prepare_order_execution(
        wrapper,
        pool,
        reference_pool,
        balance_manager,
        base_coin,
        quote_coin,
        deep_coin,
        sui_coin,
        deep_required,
        order_amount,
        is_bid,
        clock,
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
        true, // Using DEEP for fees
        expire_timestamp,
        clock,
        ctx,
    )
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
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool used for SUI/DEEP price calculation
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
/// - clock: System clock for timestamp verification
public fun create_market_order<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    wrapper: &mut Wrapper,
    pool: &mut Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    balance_manager: &mut BalanceManager,
    base_coin: Coin<BaseToken>,
    quote_coin: Coin<QuoteToken>,
    deep_coin: Coin<DEEP>,
    sui_coin: Coin<SUI>,
    order_amount: u64,
    is_bid: bool,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (deepbook::order_info::OrderInfo) {
    // Calculate base quantity and DEEP required for market order
    let (base_quantity, deep_required) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    // Prepare order execution
    let proof = prepare_order_execution(
        wrapper,
        pool,
        reference_pool,
        balance_manager,
        base_coin,
        quote_coin,
        deep_coin,
        sui_coin,
        deep_required,
        order_amount,
        is_bid,
        clock,
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
        true, // Using DEEP for fees
        clock,
        ctx,
    )
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
): (deepbook::order_info::OrderInfo) {
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
    pool::place_limit_order(
        pool,
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
): (deepbook::order_info::OrderInfo) {
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
): (deepbook::order_info::OrderInfo) {
    // Calculate order amount based on order type
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // Get taker fee from pool
    let (taker_fee, _, _) = pool.pool_trade_params();

    // Prepare order execution
    let proof = prepare_input_fee_order_execution(
        wrapper,
        pool,
        balance_manager,
        base_coin,
        quote_coin,
        taker_fee,
        order_amount,
        is_bid,
        ctx,
    );

    // Place limit order with pay_with_deep set to false since we're using input coins for fees
    pool::place_limit_order(
        pool,
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
    )
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
): (deepbook::order_info::OrderInfo) {
    // Calculate base quantity for market order
    let (base_quantity, _) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    // Get taker fee from pool
    let (taker_fee, _, _) = pool.pool_trade_params();

    // Prepare order execution
    let proof = prepare_input_fee_order_execution(
        wrapper,
        pool,
        balance_manager,
        base_coin,
        quote_coin,
        taker_fee,
        order_amount,
        is_bid,
        ctx,
    );

    // Place market order with pay_with_deep set to false since we're using input coins for fees
    pool::place_market_order(
        pool,
        balance_manager,
        &proof,
        client_order_id,
        self_matching_option,
        base_quantity,
        is_bid,
        false, // Using input coins for fees
        clock,
        ctx,
    )
}

// === Public-View Functions ===
/// Estimates the requirements for creating a limit order on DeepBook
/// Analyzes available resources and requirements to determine if an order can be created
/// Uses a reference pool to calculate SUI/DEEP price for fee estimation
///
/// Parameters:
/// - wrapper: The DeepBook wrapper instance
/// - whitelisted_pools_registry: Registry of pools whitelisted by our protocol
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool used for SUI/DEEP price calculation
/// - balance_manager: User's balance manager
/// - deep_in_wallet: Amount of DEEP coins in user's wallet
/// - base_in_wallet: Amount of base tokens in user's wallet
/// - quote_in_wallet: Amount of quote tokens in user's wallet
/// - quantity: Order quantity in base tokens
/// - price: Order price in quote tokens per base token
/// - is_bid: True for buy orders, false for sell orders
///
/// Returns:
/// - bool: Whether the order can be successfully created with available resources
/// - u64: Amount of DEEP coins required for the order (if non-whitelisted pool)
/// - u64: Estimated fee amount in SUI coins
public fun estimate_order_requirements<
    BaseToken,
    QuoteToken,
    ReferenceBaseAsset,
    ReferenceQuoteAsset,
>(
    wrapper: &Wrapper,
    pool: &Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    balance_manager: &BalanceManager,
    deep_in_wallet: u64,
    base_in_wallet: u64,
    quote_in_wallet: u64,
    quantity: u64,
    price: u64,
    is_bid: bool,
    clock: &Clock,
): (bool, u64, u64) {
    // Get wrapper deep reserves
    let wrapper_deep_reserves = get_deep_reserves_value(wrapper);

    // Check if pool is whitelisted by DeepBook
    let is_pool_whitelisted = pool::whitelisted(pool);

    // Get pool parameters
    let (pool_tick_size, pool_lot_size, pool_min_size) = pool::pool_book_params(pool);

    // Get SUI per DEEP price from reference pool
    let sui_per_deep = get_sui_per_deep(reference_pool, clock);

    // Get balance manager balances
    let balance_manager_deep = balance_manager::balance<DEEP>(balance_manager);
    let balance_manager_base = balance_manager::balance<BaseToken>(balance_manager);
    let balance_manager_quote = balance_manager::balance<QuoteToken>(balance_manager);

    // Calculate DEEP required
    let deep_required = calculate_deep_required(pool, quantity, price);

    // Call the core logic function
    estimate_order_requirements_core(
        wrapper_deep_reserves,
        is_pool_whitelisted,
        pool_tick_size,
        pool_lot_size,
        pool_min_size,
        balance_manager_deep,
        balance_manager_base,
        balance_manager_quote,
        deep_in_wallet,
        base_in_wallet,
        quote_in_wallet,
        quantity,
        price,
        is_bid,
        deep_required,
        sui_per_deep,
    )
}

/// Determines if wrapper DEEP reserves will be needed for placing an order
/// Analyzes user's available DEEP coins and calculates if wrapper reserves are required
///
/// Returns a tuple with two boolean values:
/// - bool: Whether wrapper DEEP reserves will be used for this order
/// - bool: Whether the wrapper has sufficient DEEP reserves to cover the order needs
public fun will_use_wrapper_deep_reserves<BaseToken, QuoteToken>(
    wrapper: &Wrapper,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    deep_in_wallet: u64,
    quantity: u64,
    price: u64,
): (bool, bool) {
    // Get wrapper deep reserves
    let wrapper_deep_reserves = get_deep_reserves_value(wrapper);

    // Check if pool is whitelisted by DeepBook
    let is_pool_whitelisted = pool::whitelisted(pool);

    // Calculate how much DEEP is required
    let deep_required = calculate_deep_required(pool, quantity, price);

    // Check DEEP from balance manager
    let balance_manager_deep = balance_manager::balance<DEEP>(balance_manager);

    // Get deep plan
    let deep_plan = get_deep_plan(
        is_pool_whitelisted,
        deep_required,
        balance_manager_deep,
        deep_in_wallet,
        wrapper_deep_reserves,
    );

    (deep_plan.use_wrapper_deep_reserves, deep_plan.deep_reserves_cover_order)
}

/// Validates that order parameters satisfy the pool's requirements
/// Checks if quantity and price comply with the pool's tick size, lot size, and minimum size constraints
///
/// Returns boolean:
/// - true: If order parameters are valid for the specified pool
/// - false: If any parameter violates the pool's constraints
public fun validate_pool_params<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    quantity: u64,
    price: u64,
): bool {
    let (tick_size, lot_size, min_size) = pool::pool_book_params(pool);

    // Call the core logic function
    validate_pool_params_core(
        quantity,
        price,
        tick_size,
        lot_size,
        min_size,
    )
}

/// Checks if the user has enough input coins for creating an order
/// Evaluates combined balances from wallet and balance manager against order requirements
/// Accounts for additional fee requirements when using wrapper DEEP reserves
///
/// Returns boolean:
/// - true: If user has enough coins to create the order with specified parameters
/// - false: If user doesn't have enough coins for the order
public fun has_enough_input_coin<BaseToken, QuoteToken>(
    balance_manager: &BalanceManager,
    base_in_wallet: u64,
    quote_in_wallet: u64,
    quantity: u64,
    price: u64,
    will_use_wrapper_deep: bool,
    fee_estimate: u64,
    is_bid: bool,
): bool {
    // Get balance manager balances
    let balance_manager_base = balance_manager::balance<BaseToken>(balance_manager);
    let balance_manager_quote = balance_manager::balance<QuoteToken>(balance_manager);

    // Call the core logic function
    has_enough_input_coin_core(
        balance_manager_base,
        balance_manager_quote,
        base_in_wallet,
        quote_in_wallet,
        quantity,
        price,
        will_use_wrapper_deep,
        fee_estimate,
        is_bid,
    )
}

// === Public-Package Functions ===
/// Core logic for estimating order requirements without using DeepBook objects
/// Takes raw parameters instead of DeepBook objects for improved testability
/// Evaluates all requirements including DEEP needs, fees, and parameter validation
///
/// Parameters:
/// - wrapper_deep_reserves: Amount of DEEP available in wrapper reserves
/// - is_pool_whitelisted: Whether the pool is whitelisted by DeepBook
/// - pool_tick_size: Minimum price increment for orders
/// - pool_lot_size: Minimum quantity increment for orders
/// - pool_min_size: Minimum order size allowed
/// - balance_manager_deep: Amount of DEEP in user's balance manager
/// - balance_manager_base: Amount of base tokens in user's balance manager
/// - balance_manager_quote: Amount of quote tokens in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - base_in_wallet: Amount of base tokens in user's wallet
/// - quote_in_wallet: Amount of quote tokens in user's wallet
/// - quantity: Order quantity in base tokens
/// - price: Order price in quote tokens per base token
/// - is_bid: True for buy orders, false for sell orders
/// - deep_required: Amount of DEEP required for the order
/// - sui_per_deep: Current SUI/DEEP price from reference pool
///
/// Returns a tuple with three values:
/// - bool: Whether the order can be created with available resources
/// - u64: Amount of DEEP coins required for the order (if non-whitelisted pool)
/// - u64: Estimated fee amount in SUI coins
public(package) fun estimate_order_requirements_core(
    wrapper_deep_reserves: u64,
    is_pool_whitelisted: bool,
    pool_tick_size: u64,
    pool_lot_size: u64,
    pool_min_size: u64,
    balance_manager_deep: u64,
    balance_manager_base: u64,
    balance_manager_quote: u64,
    deep_in_wallet: u64,
    base_in_wallet: u64,
    quote_in_wallet: u64,
    quantity: u64,
    price: u64,
    is_bid: bool,
    deep_required: u64,
    sui_per_deep: u64,
): (bool, u64, u64) {
    // Get deep plan
    let deep_plan = get_deep_plan(
        is_pool_whitelisted,
        deep_required,
        balance_manager_deep,
        deep_in_wallet,
        wrapper_deep_reserves,
    );

    // Early return if wrapper doesn't have enough DEEP
    if (deep_plan.use_wrapper_deep_reserves && !deep_plan.deep_reserves_cover_order) {
        return (false, deep_required, 0)
    };

    // Calculate fee
    let (fee_estimate, _, _) = estimate_full_order_fee_core(
        is_pool_whitelisted,
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        sui_per_deep,
    );

    // Validate order parameters
    let valid_params = validate_pool_params_core(
        quantity,
        price,
        pool_tick_size,
        pool_lot_size,
        pool_min_size,
    );

    // Check if user has enough input coins
    let enough_coins = has_enough_input_coin_core(
        balance_manager_base,
        balance_manager_quote,
        base_in_wallet,
        quote_in_wallet,
        quantity,
        price,
        deep_plan.use_wrapper_deep_reserves,
        fee_estimate,
        is_bid,
    );

    (
        valid_params && enough_coins && deep_plan.deep_reserves_cover_order,
        deep_required,
        fee_estimate,
    )
}

/// Core logic function that orchestrates the creation of a limit order using coins from various sources
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
/// - sui_per_deep: Current SUI/DEEP price from reference pool
///
/// Returns a tuple with three structured plans:
/// - DeepPlan: Coordinates DEEP coin sourcing from user wallet and wrapper reserves
/// - FeePlan: Specifies fee amount and sources for SUI fee payment
/// - InputCoinDepositPlan: Determines how input coins will be sourced for the order
public(package) fun create_limit_order_core(
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
): (DeepPlan, FeePlan, InputCoinDepositPlan) {
    // Step 1: Determine DEEP requirements
    let deep_plan = get_deep_plan(
        is_pool_whitelisted,
        deep_required,
        balance_manager_deep,
        deep_in_wallet,
        wrapper_deep_reserves,
    );

    // Step 2: Determine fee charging plan based on order type
    let fee_plan = get_fee_plan(
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

    (deep_plan, fee_plan, deposit_plan)
}

/// Core logic function that orchestrates the creation of an order using input coins for fees
/// Coordinates requirements by analyzing available resources and calculating necessary allocations
/// Creates comprehensive plans for input coin fee charging and input coin deposits
///
/// Parameters:
/// * `is_pool_whitelisted` - Whether the pool is whitelisted by DeepBook
/// * `taker_fee` - DeepBook's taker fee rate in billionths
/// * `balance_manager_input_coin` - Amount of input coins in user's balance manager
/// * `wallet_input_coin` - Amount of input coins in user's wallet
/// * `order_amount` - Order amount in quote tokens (for bids) or base tokens (for asks)
///
/// Returns a tuple with two structured plans:
/// * `InputCoinFeePlan` - Specifies fee amount and sources for input coin fee payment
/// * `InputCoinDepositPlan` - Determines how input coins will be sourced for the order
public(package) fun create_input_fee_order_core(
    is_pool_whitelisted: bool,
    taker_fee: u64,
    balance_manager_input_coin: u64,
    wallet_input_coin: u64,
    order_amount: u64,
): (InputCoinFeePlan, InputCoinDepositPlan) {
    // Step 1: Determine fee charging plan
    let fee_plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        order_amount,
        wallet_input_coin,
        balance_manager_input_coin,
    );

    // Step 2: Calculate remaining balances after fee deduction
    let remaining_in_wallet = wallet_input_coin - fee_plan.protocol_fee_from_wallet;
    let remaining_in_bm = balance_manager_input_coin - fee_plan.protocol_fee_from_balance_manager;

    // Step 3: Calculate DeepBook fee
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, taker_fee);
    
    // Step 4: Calculate total amount needed to be on the balance manager
    let total_amount = order_amount + deepbook_fee;

    // Step 5: Determine input coin deposit plan with remaining balances
    let deposit_plan = get_input_coin_deposit_plan(
        total_amount,
        remaining_in_wallet,
        remaining_in_bm,
    );

    (fee_plan, deposit_plan)
}

/// Validates that order parameters satisfy the pool's requirements - core logic implementation
/// Performs three essential checks for order parameter validity:
/// 1. Quantity meets or exceeds the pool's minimum size
/// 2. Quantity is a multiple of the pool's lot size
/// 3. Price is a multiple of the pool's tick size
///
/// Returns boolean:
/// - true: If all order parameters comply with the pool's constraints
/// - false: If any parameter violates the pool's constraints
public(package) fun validate_pool_params_core(
    quantity: u64,
    price: u64,
    tick_size: u64,
    lot_size: u64,
    min_size: u64,
): bool {
    quantity >= min_size && 
        quantity % lot_size == 0 && 
        price % tick_size == 0
}

/// Checks if the user has enough input coins for creating an order - core logic implementation
/// Evaluates available coin balances against order requirements, considering:
/// 1. For bid orders: if user has enough quote coins including fee if needed
/// 2. For ask orders: if user has enough base coins including fee if needed
///
/// Returns boolean:
/// - true: If user has enough coins for the order with specified parameters
/// - false: If user doesn't have enough coins to create the order
public(package) fun has_enough_input_coin_core(
    balance_manager_base: u64,
    balance_manager_quote: u64,
    base_in_wallet: u64,
    quote_in_wallet: u64,
    quantity: u64,
    price: u64,
    will_use_wrapper_deep: bool,
    fee_estimate: u64,
    is_bid: bool,
): bool {
    if (is_bid) {
        // For bid orders, check if user has enough quote coins
        let quote_required = math::mul(quantity, price);
        let total_quote_available = balance_manager_quote + quote_in_wallet;

        // Need to account for fee if using wrapper DEEP
        if (will_use_wrapper_deep) {
            total_quote_available >= (quote_required + fee_estimate)
        } else {
            total_quote_available >= quote_required
        }
    } else {
        // For ask orders, check if user has enough base coins
        let total_base_available = balance_manager_base + base_in_wallet;

        // Need to account for fee if using wrapper DEEP
        if (will_use_wrapper_deep) {
            total_base_available >= (quantity + fee_estimate)
        } else {
            total_base_available >= quantity
        }
    }
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

/// Creates a fee plan for order execution by determining optimal sources for fee payment in SUI coins.
/// Returns early with zero fees for whitelisted pools or when not using wrapper DEEP.
/// 
/// # Arguments
/// * `use_wrapper_deep_reserves` - Whether the order requires DEEP from wrapper reserves
/// * `deep_from_reserves` - Amount of DEEP to be taken from wrapper reserves
/// * `is_pool_whitelisted` - Whether the pool is whitelisted by DeepBook
/// * `sui_per_deep` - Current SUI/DEEP price from reference pool
/// * `sui_in_wallet` - Amount of SUI available in user's wallet
/// * `balance_manager_sui` - Amount of SUI available in user's balance manager
/// 
/// # Returns
/// * `FeePlan` - Struct containing:
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
public(package) fun get_fee_plan(
    use_wrapper_deep_reserves: bool,
    deep_from_reserves: u64,
    is_pool_whitelisted: bool,
    sui_per_deep: u64,
    sui_in_wallet: u64,
    balance_manager_sui: u64,
): FeePlan {
    // No fee for whitelisted pools or when not using wrapper DEEP
    if (is_pool_whitelisted || !use_wrapper_deep_reserves) {
        return zero_fee_plan()
    };

    // Calculate fee based on order amount, including both protocol fee and deep reserves coverage fee
    let (total_fee, coverage_fee, protocol_fee) = calculate_full_order_fee(sui_per_deep, deep_from_reserves);

    // If no fee, return early
    if (total_fee == 0) {
        return zero_fee_plan()
    };

    // Check if user has enough total SUI
    let total_available = sui_in_wallet + balance_manager_sui;
    if (total_available < total_fee) {
        return insufficient_fee_plan()
    };

    // Plan coverage fee collection
    let (coverage_from_wallet, coverage_from_bm) = plan_fee_collection(
        coverage_fee,
        sui_in_wallet,
        balance_manager_sui
    );

    // Adjust available amounts for protocol fee planning
    let remaining_in_wallet = sui_in_wallet - coverage_from_wallet;
    let remaining_in_bm = balance_manager_sui - coverage_from_bm;

    // Plan protocol fee collection
    let (protocol_from_wallet, protocol_from_bm) = plan_fee_collection(
        protocol_fee,
        remaining_in_wallet,
        remaining_in_bm
    );

    FeePlan {
        coverage_fee_from_wallet: coverage_from_wallet,
        coverage_fee_from_balance_manager: coverage_from_bm,
        protocol_fee_from_wallet: protocol_from_wallet,
        protocol_fee_from_balance_manager: protocol_from_bm,
        user_covers_wrapper_fee: true,
    }
}

/// Creates a fee plan for order execution by determining optimal sources for fee payment in input coins.
/// Returns early with zero fees for whitelisted pools.
/// 
/// # Arguments
/// * `is_pool_whitelisted` - Whether the pool is whitelisted by DeepBook
/// * `taker_fee` - DeepBook's taker fee rate in billionths
/// * `amount` - The amount to calculate fee on
/// * `coin_in_wallet` - Amount of input coins available in user's wallet
/// * `balance_manager_coin` - Amount of input coins available in user's balance manager
/// 
/// # Returns
/// * `InputCoinFeePlan` - Struct containing:
///   - Protocol fee amounts from wallet and balance manager
///   - Whether user has sufficient funds to cover fees
/// 
/// # Flow
/// 1. Returns zero fee plan if pool is whitelisted
/// 2. Calculates protocol fee based on taker fee and amount
/// 3. Returns zero fee plan if total fee is zero
/// 4. Returns insufficient fee plan if user lacks total funds
/// 5. Plans protocol fee collection from available sources
public(package) fun get_input_coin_fee_plan(
    is_pool_whitelisted: bool,
    taker_fee: u64,
    amount: u64,
    coin_in_wallet: u64,
    balance_manager_coin: u64,
): InputCoinFeePlan {
    // No fee for whitelisted pools
    if (is_pool_whitelisted) {
        return zero_input_coin_fee_plan()
    };

    // Calculate protocol fee based on order amount
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    // If no fee, return early
    if (protocol_fee == 0) {
        return zero_input_coin_fee_plan()
    };

    // Check if user has enough total coins
    let total_available = coin_in_wallet + balance_manager_coin;
    if (total_available < protocol_fee) {
        return insufficient_input_coin_fee_plan()
    };

    // Plan protocol fee collection
    let (fee_from_wallet, fee_from_bm) = plan_fee_collection(
        protocol_fee,
        coin_in_wallet,
        balance_manager_coin
    );

    InputCoinFeePlan {
        protocol_fee_from_wallet: fee_from_wallet,
        protocol_fee_from_balance_manager: fee_from_bm,
        user_covers_wrapper_fee: true,
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

// === Private Functions ===
/// Prepares order execution by handling all common order creation logic:
/// 1. Verifies the caller owns the balance manager
/// 2. Creates plans for DEEP sourcing, fee collection, and input coin deposit
/// 3. Executes the plans in sequence:
///    - Sources DEEP coins from user wallet and wrapper reserves according to DeepPlan
///    - Collects fees in SUI coins according to FeePlan
///    - Deposits required input coins according to InputCoinDepositPlan
/// 4. Returns unused coins to the caller
/// 5. Returns the balance manager proof needed for order placement
///
/// This function contains the shared execution logic between limit and market orders,
/// processing the plans created by create_limit_order_core.
///
/// Parameters:
/// - wrapper: The DeepBook wrapper instance managing the order process
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool used for SUI/DEEP price calculation
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - deep_coin: DEEP coins from user's wallet
/// - sui_coin: SUI coins for fee payment
/// - deep_required: Amount of DEEP required for the order
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - clock: System clock for timestamp verification
fun prepare_order_execution<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    wrapper: &mut Wrapper,
    pool: &Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    mut deep_coin: Coin<DEEP>,
    mut sui_coin: Coin<SUI>,
    deep_required: u64,
    order_amount: u64,
    is_bid: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): TradeProof {
    // Verify the caller owns the balance manager
    assert!(balance_manager::owner(balance_manager) == tx_context::sender(ctx), EInvalidOwner);

    // Get SUI per DEEP price from reference pool
    let sui_per_deep = get_sui_per_deep(reference_pool, clock);

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
    let wrapper_deep_reserves = get_deep_reserves_value(wrapper);

    // Get the order plans from the core logic
    let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
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

    // Step 1: Execute DEEP plan
    execute_deep_plan(wrapper, balance_manager, &mut deep_coin, &deep_plan, ctx);

    // Step 2: Execute fee charging plan
    execute_fee_plan(
        wrapper,
        balance_manager,
        &mut sui_coin,
        &fee_plan,
        ctx,
    );

    // Step 3: Execute input coin deposit plan
    execute_input_coin_deposit_plan(
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &input_coin_deposit_plan,
        is_bid,
        ctx,
    );

    // Return unused coins to the caller
    transfer_if_nonzero(base_coin, tx_context::sender(ctx));
    transfer_if_nonzero(quote_coin, tx_context::sender(ctx));
    transfer_if_nonzero(deep_coin, tx_context::sender(ctx));
    transfer_if_nonzero(sui_coin, tx_context::sender(ctx));

    // Generate and return proof
    balance_manager.generate_proof_as_owner(ctx)
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
    assert!(balance_manager::owner(balance_manager) == tx_context::sender(ctx), EInvalidOwner);

    // Get balances from balance manager
    let balance_manager_base = balance_manager::balance<BaseToken>(balance_manager);
    let balance_manager_quote = balance_manager::balance<QuoteToken>(balance_manager);
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let base_in_wallet = coin::value(&base_coin);
    let quote_in_wallet = coin::value(&quote_coin);
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
    transfer_if_nonzero(base_coin, tx_context::sender(ctx));
    transfer_if_nonzero(quote_coin, tx_context::sender(ctx));

    // Step 4: Generate and return proof
    balance_manager::generate_proof_as_owner(balance_manager, ctx)
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
/// * `pool` - The trading pool where the order will be placed
/// * `balance_manager` - User's balance manager for managing coin deposits
/// * `base_coin` - Base token coins from user's wallet
/// * `quote_coin` - Quote token coins from user's wallet
/// * `taker_fee` - DeepBook's taker fee rate in billionths
/// * `order_amount` - Order amount in quote tokens (for bids) or base tokens (for asks)
/// * `is_bid` - True for buy orders, false for sell orders
fun prepare_input_fee_order_execution<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    taker_fee: u64,
    order_amount: u64,
    is_bid: bool,
    ctx: &mut TxContext,
): TradeProof {
    // Verify the caller owns the balance manager
    assert!(balance_manager::owner(balance_manager) == tx_context::sender(ctx), EInvalidOwner);

    // Get pool whitelisted status
    let is_pool_whitelisted = pool::whitelisted(pool);

    // Get balances from balance manager
    let balance_manager_base = balance_manager::balance<BaseToken>(balance_manager);
    let balance_manager_quote = balance_manager::balance<QuoteToken>(balance_manager);
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let base_in_wallet = coin::value(&base_coin);
    let quote_in_wallet = coin::value(&quote_coin);
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    // Get the order plans from the core logic
    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        taker_fee,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    // Execute fee charging plan
    execute_input_coin_fee_plan(
        wrapper,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &fee_plan,
        is_bid,
        ctx,
    );

    // Execute input coin deposit plan
    execute_input_coin_deposit_plan(
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &input_coin_deposit_plan,
        is_bid,
        ctx,
    );

    // Return unused coins to the caller
    transfer_if_nonzero(base_coin, tx_context::sender(ctx));
    transfer_if_nonzero(quote_coin, tx_context::sender(ctx));

    // Generate and return proof
    balance_manager::generate_proof_as_owner(balance_manager, ctx)
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
    // Check if there is enough DEEP in the wrapper reserves
    if (deep_plan.use_wrapper_deep_reserves) {
        assert!(deep_plan.deep_reserves_cover_order, EInsufficientDeepReserves);
    };

    // Take DEEP from wallet if needed
    if (deep_plan.from_user_wallet > 0) {
        let payment = coin::split(deep_coin, deep_plan.from_user_wallet, ctx);
        balance_manager::deposit(balance_manager, payment, ctx);
    };

    // Take DEEP from wrapper reserves if needed
    if (deep_plan.from_deep_reserves > 0) {
        let reserve_payment = split_deep_reserves(wrapper, deep_plan.from_deep_reserves, ctx);

        balance_manager::deposit(balance_manager, reserve_payment, ctx);
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
fun execute_fee_plan(
    wrapper: &mut Wrapper,
    balance_manager: &mut BalanceManager,
    sui_coin: &mut Coin<SUI>,
    fee_plan: &FeePlan,
    ctx: &mut TxContext,
) {
    assert!(fee_plan.user_covers_wrapper_fee, EInsufficientFee);

    // Collect coverage fee
    if (fee_plan.coverage_fee_from_wallet > 0) {
        let fee = coin::split(sui_coin, fee_plan.coverage_fee_from_wallet, ctx);
        join_deep_reserves_coverage_fee(wrapper, coin::into_balance(fee));
    };
    if (fee_plan.coverage_fee_from_balance_manager > 0) {
        let fee = balance_manager::withdraw<SUI>(
            balance_manager,
            fee_plan.coverage_fee_from_balance_manager,
            ctx,
        );
        join_deep_reserves_coverage_fee(wrapper, coin::into_balance(fee));
    };

    // Collect protocol fee
    if (fee_plan.protocol_fee_from_wallet > 0) {
        let fee = coin::split(sui_coin, fee_plan.protocol_fee_from_wallet, ctx);
        join_protocol_fee(wrapper, coin::into_balance(fee));
    };
    if (fee_plan.protocol_fee_from_balance_manager > 0) {
        let fee = balance_manager::withdraw<SUI>(
            balance_manager,
            fee_plan.protocol_fee_from_balance_manager,
            ctx,
        );
        join_protocol_fee(wrapper, coin::into_balance(fee));
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
fun execute_input_coin_fee_plan<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    fee_plan: &InputCoinFeePlan,
    is_bid: bool,
    ctx: &mut TxContext,
) {
    assert!(fee_plan.user_covers_wrapper_fee, EInsufficientFee);

    // Collect protocol fee from wallet if needed
    if (fee_plan.protocol_fee_from_wallet > 0) {
        if (is_bid) {
            let fee = coin::split(quote_coin, fee_plan.protocol_fee_from_wallet, ctx);
            join_protocol_fee(wrapper, coin::into_balance(fee));
        } else {
            let fee = coin::split(base_coin, fee_plan.protocol_fee_from_wallet, ctx);
            join_protocol_fee(wrapper, coin::into_balance(fee));
        };
    };

    // Collect protocol fee from balance manager if needed
    if (fee_plan.protocol_fee_from_balance_manager > 0) {
        if (is_bid) {
            let fee = balance_manager::withdraw<QuoteToken>(
                balance_manager,
                fee_plan.protocol_fee_from_balance_manager,
                ctx,
            );
            join_protocol_fee(wrapper, coin::into_balance(fee));
        } else {
            let fee = balance_manager::withdraw<BaseToken>(
                balance_manager,
                fee_plan.protocol_fee_from_balance_manager,
                ctx,
            );
            join_protocol_fee(wrapper, coin::into_balance(fee));
        };
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
            let payment = coin::split(quote_coin, deposit_plan.from_user_wallet, ctx);
            balance_manager::deposit(balance_manager, payment, ctx);
        } else {
            // Base coins for ask
            let payment = coin::split(base_coin, deposit_plan.from_user_wallet, ctx);
            balance_manager::deposit(balance_manager, payment, ctx);
        };
    };
}

/// Makes a fee plan where no fees need to be collected
fun zero_fee_plan(): FeePlan {
    create_empty_fee_plan(true)
}

/// Makes a fee plan for when user doesn't have enough funds
fun insufficient_fee_plan(): FeePlan {
    create_empty_fee_plan(false)
}

/// Helper to create a fee plan with no fees and specified coverage status
/// The coverage status tells if user can pay fees (true) or not (false)
fun create_empty_fee_plan(user_covers_fee: bool): FeePlan {
    FeePlan {
        coverage_fee_from_wallet: 0,
        coverage_fee_from_balance_manager: 0,
        protocol_fee_from_wallet: 0,
        protocol_fee_from_balance_manager: 0,
        user_covers_wrapper_fee: user_covers_fee,
    }
}

/// Makes an input coin fee plan where no fees need to be collected
fun zero_input_coin_fee_plan(): InputCoinFeePlan {
    create_empty_input_coin_fee_plan(true)
}

/// Makes an input coin fee plan for when user doesn't have enough funds
fun insufficient_input_coin_fee_plan(): InputCoinFeePlan {
    create_empty_input_coin_fee_plan(false)
}

/// Helper to create an input coin fee plan with no fees and specified coverage status
/// The coverage status tells if user can pay fees (true) or not (false)
fun create_empty_input_coin_fee_plan(user_covers_fee: bool): InputCoinFeePlan {
    InputCoinFeePlan {
        protocol_fee_from_wallet: 0,
        protocol_fee_from_balance_manager: 0,
        user_covers_wrapper_fee: user_covers_fee,
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
    assert!(actual.use_wrapper_deep_reserves == expected_use_wrapper, 0);
    assert!(actual.from_user_wallet == expected_from_wallet, 0);
    assert!(actual.from_deep_reserves == expected_from_wrapper, 0);
    assert!(actual.deep_reserves_cover_order == expected_sufficient, 0);
}

#[test_only]
public fun assert_fee_plan_eq(
    actual: FeePlan,
    expected_coverage_from_wallet: u64,
    expected_coverage_from_bm: u64,
    expected_protocol_from_wallet: u64,
    expected_protocol_from_bm: u64,
    expected_sufficient: bool,
) {
    assert!(actual.coverage_fee_from_wallet == expected_coverage_from_wallet, 0);
    assert!(actual.coverage_fee_from_balance_manager == expected_coverage_from_bm, 0);
    assert!(actual.protocol_fee_from_wallet == expected_protocol_from_wallet, 0);
    assert!(actual.protocol_fee_from_balance_manager == expected_protocol_from_bm, 0);
    assert!(actual.user_covers_wrapper_fee == expected_sufficient, 0);
}

#[test_only]
public fun assert_input_coin_deposit_plan_eq(
    actual: InputCoinDepositPlan,
    expected_order_amount: u64,
    expected_from_user_wallet: u64,
    expected_sufficient: bool,
) {
    assert!(actual.order_amount == expected_order_amount, 0);
    assert!(actual.from_user_wallet == expected_from_user_wallet, 0);
    assert!(actual.user_has_enough_input_coin == expected_sufficient, 0);
}

#[test_only]
public fun assert_input_coin_fee_plan_eq(
    actual: InputCoinFeePlan,
    expected_protocol_from_wallet: u64,
    expected_protocol_from_bm: u64,
    expected_sufficient: bool,
) {
    assert!(actual.protocol_fee_from_wallet == expected_protocol_from_wallet, 0);
    assert!(actual.protocol_fee_from_balance_manager == expected_protocol_from_bm, 0);
    assert!(actual.user_covers_wrapper_fee == expected_sufficient, 0);
}
