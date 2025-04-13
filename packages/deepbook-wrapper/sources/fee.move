module deepbook_wrapper::fee;

use deepbook::pool::{Self, Pool};
use deepbook_wrapper::helper::{calculate_deep_required, get_sui_per_deep, calculate_market_order_params};
use deepbook_wrapper::math;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};

// === Constants ===
/// Fee rate for protocol fee in billionths (1%)
const PROTOCOL_FEE_BPS: u64 = 10_000_000;

// === Public-View Functions ===
/// Calculates the total fee estimate for a limit order in SUI coins
/// Uses a reference pool to get SUI/DEEP price for fee calculation
/// Fee is only charged when using DEEP from wrapper reserves for non-whitelisted pools
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool used for SUI/DEEP price calculation
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
///   Returns (0, 0, 0) for whitelisted pools or when user provides all required DEEP
public fun estimate_full_fee_limit<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    pool: &Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_in_balance_manager: u64,
    deep_in_wallet: u64,
    quantity: u64,
    price: u64,
    clock: &Clock,
): (u64, u64, u64) {
    // Check if pool is whitelisted
    let is_pool_whitelisted = pool::whitelisted(pool);

    // Get SUI per DEEP price from reference pool
    let sui_per_deep = get_sui_per_deep(reference_pool, clock);

    // Get DEEP required for the order
    let deep_required = calculate_deep_required(pool, quantity, price);

    // Call the core logic function
    estimate_full_order_fee_core(
        is_pool_whitelisted,
        deep_in_balance_manager,
        deep_in_wallet,
        deep_required,
        sui_per_deep,
    )
}

/// Calculates the total fee estimate for a market order in SUI coins
/// Uses a reference pool to get SUI/DEEP price for fee calculation
/// Fee is only charged when using DEEP from wrapper reserves for non-whitelisted pools
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool used for SUI/DEEP price calculation
/// - deep_in_balance_manager: Amount of DEEP available in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - clock: System clock for order book state
///
/// Returns:
/// - u64: The estimated total fee in SUI coins
/// - u64: Deep reserves coverage fee
/// - u64: Protocol fee
///   Returns (0, 0, 0) for whitelisted pools or when user provides all required DEEP
public fun estimate_full_fee_market<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    pool: &Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_in_balance_manager: u64,
    deep_in_wallet: u64,
    order_amount: u64,
    is_bid: bool,
    clock: &Clock,
): (u64, u64, u64) {
    // Check if pool is whitelisted
    let is_pool_whitelisted = pool::whitelisted(pool);

    // Get SUI per DEEP price from reference pool
    let sui_per_deep = get_sui_per_deep(reference_pool, clock);

    // Get DEEP required for the order
    let (_, deep_required) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    // Call the core logic function
    estimate_full_order_fee_core(
        is_pool_whitelisted,
        deep_in_balance_manager,
        deep_in_wallet,
        deep_required,
        sui_per_deep,
    )
}

// === Public-Package Functions ===
/// Core logic for calculating the total fee for an order in SUI coins
/// Determines if user needs to use wrapper DEEP reserves and calculates
/// the appropriate fee based on the SUI/DEEP price
///
/// Parameters:
/// - is_pool_whitelisted: Whether the pool is whitelisted by DeepBook
/// - balance_manager_deep: Amount of DEEP in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - deep_required: Total amount of DEEP required for the order
/// - sui_per_deep: Current SUI/DEEP price from reference pool
///
/// Returns:
/// - u64: The total fee in SUI coins
/// - u64: Deep reserves coverage fee
/// - u64: Protocol fee
///   Returns (0, 0, 0) for whitelisted pools or when user provides all required DEEP
///
/// Fee consists of two components when using wrapper DEEP reserves:
/// 1. Deep reserves coverage fee: Cost of DEEP being borrowed
/// 2. Protocol fee: Additional fee based on PROTOCOL_FEE_BPS
public(package) fun estimate_full_order_fee_core(
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
        calculate_full_order_fee(sui_per_deep, deep_from_reserves)
    }
}

/// Calculates the total fee amount in SUI coins for an order using DEEP from reserves
/// Combines both the deep reserves coverage fee and protocol fee
///
/// Parameters:
/// - sui_per_deep: Current SUI/DEEP price from reference pool
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
/// - sui_per_deep: Current SUI/DEEP price from reference pool
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
/// Fee is calculated as a percentage (PROTOCOL_FEE_BPS) of the borrowed DEEP value in SUI
///
/// Parameters:
/// - sui_per_deep: Current SUI/DEEP price from reference pool
/// - deep_from_reserves: Amount of DEEP taken from wrapper reserves
///
/// Returns:
/// - u64: Protocol fee amount in SUI coins
///
/// The calculation is done in two steps:
/// 1. Calculate fee amount in DEEP using PROTOCOL_FEE_BPS
/// 2. Convert DEEP fee to SUI using current price
public(package) fun calculate_protocol_fee(sui_per_deep: u64, deep_from_reserves: u64): u64 {
    let protocol_fee_in_deep = math::mul(deep_from_reserves, PROTOCOL_FEE_BPS);
    let protocol_fee_in_sui = math::mul(protocol_fee_in_deep, sui_per_deep);

    protocol_fee_in_sui
}

/// Calculates a basic swap fee based on an amount and a fee rate.
/// Used primarily for calculating fees in traditional DEX swaps.
///
/// # Returns
/// * `u64` - The calculated fee amount
///
/// # Parameters
/// * `amount` - The amount of tokens to calculate fee on
/// * `fee_bps` - The fee rate in billionths (e.g., 1,000,000 = 0.1%)
public(package) fun calculate_swap_fee(amount: u64, fee_bps: u64): u64 {
    math::mul(amount, fee_bps)
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
    let coin_balance = coin::balance_mut(coin);
    let value = balance::value(coin_balance);
    balance::split(coin_balance, calculate_swap_fee(value, fee_bps))
}
