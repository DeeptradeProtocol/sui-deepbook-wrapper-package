module deepbook_wrapper::helper;

use deepbook::pool::{Self, Pool};
use deepbook_wrapper::math;
use std::type_name;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::sui::SUI;
use token::deep::DEEP;

// === Constants ===
const DEEP_REQUIRED_SLIPPAGE: u64 = 100_000_000; // 10% in billionths

// === Errors ===
/// Error when the reference pool is not eligible for the order
#[error]
const EIneligibleReferencePool: u64 = 1;

// === Public-Package Functions ===
/// Get fee basis points from pool parameters
public(package) fun get_fee_bps<BaseToken, QuoteToken>(pool: &Pool<BaseToken, QuoteToken>): u64 {
    let (fee_bps, _, _) = pool::pool_trade_params(pool);
    fee_bps
}

/// Helper function to transfer non-zero coins or destroy zero coins
public(package) fun transfer_if_nonzero<CoinType>(coins: Coin<CoinType>, recipient: address) {
    if (coins.value() > 0) {
        transfer::public_transfer(coins, recipient);
    } else {
        coins.destroy_zero();
    };
}

/// Determines if a pool is whitelisted
/// Whitelisted pools don't require DEEP tokens and don't charge fees
public(package) fun is_pool_whitelisted<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
): bool {
    pool::whitelisted(pool)
}

/// Calculates the total amount of DEEP required for an order
/// Returns 0 for whitelisted pools
public(package) fun calculate_deep_required<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    quantity: u64,
    price: u64,
): u64 {
    if (is_pool_whitelisted(pool)) {
        0
    } else {
        let (deep_req, _) = pool::get_order_deep_required(pool, quantity, price);

        // We need to apply slippage to the deep required because the VIEW deep required from
        // `pool::get_order_deep_required` can be different from the ACTUAL deep required`
        // when placing an order.
        //
        // For example, this can be potentially observed when setting a SELL order with a price
        // lower than the current market price.
        let deep_req_with_slippage = apply_slippage(deep_req, DEEP_REQUIRED_SLIPPAGE);

        deep_req_with_slippage
    }
}

/// Applies slippage to a value and returns the result
/// The slippage is in billionths format (e.g., 5_000_000 = 0.5%)
/// For small values, the slippage might be rounded down to zero due to integer division
public(package) fun apply_slippage(value: u64, slippage: u64): u64 {
    // Handle special case: if value is 0, no slippage is needed
    if (value == 0) {
        return 0
    };

    // Calculate slippage amount
    let slippage_amount = math::mul(value, slippage);

    // Add slippage to original value
    value + slippage_amount
}

/// Calculates the order amount in tokens (quote for bid, base for ask)
public(package) fun calculate_order_amount(quantity: u64, price: u64, is_bid: bool): u64 {
    if (is_bid) {
        math::mul(quantity, price) // Quote tokens for bid
    } else {
        quantity // Base tokens for ask
    }
}

/// Gets the order deep price parameters for given pool
public(package) fun get_order_deep_price_params<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
): (bool, u64) {
    let order_deep_price = pool::get_order_deep_price(pool);
    (order_deep_price.asset_is_base(), order_deep_price.deep_per_asset())
}

/// Gets the SUI per DEEP price from a reference pool, normalizing the price regardless of token order
///
/// Parameters:
/// - reference_pool: Pool containing SUI/DEEP or DEEP/SUI trading pair
/// - clock: System clock for current timestamp
///
/// Returns:
/// - u64: Price of 1 DEEP in SUI (normalized to handle both SUI/DEEP and DEEP/SUI pools)
///
/// Requirements:
/// - Pool must be whitelisted and registered
/// - Pool must be either SUI/DEEP or DEEP/SUI trading pair
///
/// Price normalization:
/// - For DEEP/SUI pool: returns price directly
/// - For SUI/DEEP pool: returns 1_000_000_000/price
///
/// Aborts with EIneligibleReferencePool if:
/// - Pool is not whitelisted/registered
/// - Pool does not contain SUI and DEEP tokens
public(package) fun get_sui_per_deep<ReferenceBaseAsset, ReferenceQuoteAsset>(
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    clock: &Clock,
): u64 {
    assert!(
        reference_pool.whitelisted() && reference_pool.registered_pool(),
        EIneligibleReferencePool,
    );
    let reference_pool_price = reference_pool.mid_price(clock);

    let reference_base_type = type_name::get<ReferenceBaseAsset>();
    let reference_quote_type = type_name::get<ReferenceQuoteAsset>();
    let deep_type = type_name::get<DEEP>();
    let sui_type = type_name::get<SUI>();

    assert!(
        (reference_base_type == deep_type && reference_quote_type == sui_type) ||
            (reference_base_type == sui_type && reference_quote_type == deep_type),
        EIneligibleReferencePool,
    );

    let reference_deep_is_base = reference_base_type == deep_type;

    // For DEEP/SUI pool, reference_deep_is_base is true, SUI per DEEP is
    // reference_pool_price
    // For SUI/DEEP pool, reference_deep_is_base is false, DEEP per SUI is
    // reference_pool_price
    let sui_per_deep = if (reference_deep_is_base) {
        reference_pool_price
    } else {
        math::div(1_000_000_000, reference_pool_price)
    };

    sui_per_deep
}

/// Calculates base quantity and DEEP requirements for a market order based on order type
/// For bids, converts quote quantity into base quantity and floors to lot size
/// For asks, uses base quantity directly
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - clock: System clock for timestamp verification
///
/// Returns:
/// - u64: Base quantity to use in place_market_order
/// - u64: Amount of DEEP required for the order
public(package) fun calculate_market_order_params<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    clock: &Clock,
): (u64, u64) {
    // Calculate base quantity and DEEP requirements:
    // - For bids: Convert quote quantity to base quantity via `get_quantity_out`, floor to lot size.
    //             Since `get_quantity_out` goes through order book same way as actual order placement,
    //             we can use its `deep_req` value
    // - For asks: Use order_amount directly as base quantity. Since `get_quantity_out` goes through
    //             order book same way as actual order placement, we can use its `deep_req` value
    if (is_bid) {
        let (base_out, _, deep_req) = pool.get_quantity_out(0, order_amount, clock);
        let (_, lot_size, _) = pool.pool_book_params();
        let floored_base_out = base_out - base_out % lot_size;
        (floored_base_out, deep_req)
    } else {
        let (_, _, deep_req) = pool.get_quantity_out(order_amount, 0, clock);
        (order_amount, deep_req)
    }
}
