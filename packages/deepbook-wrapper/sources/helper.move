module deepbook_wrapper::helper;

use deepbook::constants::{live, partially_filled};
use deepbook::pool::Pool;
use deepbook_wrapper::math;
use deepbook_wrapper::oracle;
use pyth::price_info::PriceInfoObject;
use std::type_name;
use std::u64;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::sui::SUI;
use token::deep::DEEP;

// === Errors ===
/// Error when the reference pool is not eligible for the order
const EIneligibleReferencePool: u64 = 1;
/// Error when the slippage is invalid (greater than 100% in billionths)
const EInvalidSlippage: u64 = 2;
/// Error when the provided price feed identifier doesn't match the expected one
const EInvalidPriceFeedIdentifier: u64 = 3;
/// Error when there are no ask prices available in the order book
const ENoAskPrice: u64 = 4;
/// Error when the price feed returned positive exponent, indicating significant Pyth format change requiring manual review
const EUnexpectedPositiveExponent: u64 = 5;
/// Error when the decimal adjustment exceeds maximum safe power of 10 for u64
const EDecimalAdjustmentTooLarge: u64 = 6;
/// Error when the discount rate is greater than 100%
const EInvalidDiscountRate: u64 = 7;
/// Error when the deep from reserves is greater than the total deep required
const EInvalidDeepFromReserves: u64 = 8;
/// Error when the original quantity is zero
const EZeroOriginalQuantity: u64 = 9;
/// Error when the executed quantity exceeds the original quantity
const EExecutedQuantityExceedsOriginal: u64 = 10;

// === Constants ===
/// Current version of the package. Update during upgrades
const CURRENT_VERSION: u16 = 1;
/// The maximum power of 10 that doesn't overflow u64. 10^20 overflows u64
const MAX_SAFE_U64_POWER_OF_TEN: u64 = 19;
/// 100% in billionths format
const HUNDRED_PERCENT: u64 = 1_000_000_000;

// === Public-View Functions ===
public fun current_version(): u16 { CURRENT_VERSION }

public fun hundred_percent(): u64 { HUNDRED_PERCENT }

// === Public-Package Functions ===
/// Get fee basis points from pool parameters
public(package) fun get_fee_bps<BaseToken, QuoteToken>(pool: &Pool<BaseToken, QuoteToken>): u64 {
    let (fee_bps, _, _) = pool.pool_trade_params();
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

/// Calculates the total amount of DEEP required for an order using the taker fee rate
/// Returns 0 for whitelisted pools
public(package) fun calculate_deep_required<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    quantity: u64,
    price: u64,
): u64 {
    if (pool.whitelisted()) {
        0
    } else {
        let (deep_req, _) = pool.get_order_deep_required(quantity, price);

        deep_req
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

/// Applies a discount to a value and returns the discounted result
/// The discount rate is in billionths format (e.g., 50_000_000 = 5%)
public(package) fun apply_discount(value: u64, discount_rate: u64): u64 {
    // Verify that the discount is not greater than 100%
    assert!(discount_rate <= HUNDRED_PERCENT, EInvalidDiscountRate);

    let discount_multiplier = HUNDRED_PERCENT - discount_rate;
    math::mul(value, discount_multiplier)
}

/// Calculates discount rate based on how much of the DEEP fees the user pays themselves
/// The more user covers DeepBook fees on their own, the higher the discount rate
/// If no DEEP fees are required, user gets maximum discount
public(package) fun calculate_discount_rate(
    max_discount_rate: u64,
    deep_from_reserves: u64,
    deep_required: u64,
): u64 {
    // Sanity check: amount of DEEP to be taken from reserves must not exceed the total
    // amount of DEEP required for the order creation. If it fails, the DEEP planning
    // mechanism is flawed.
    assert!(deep_from_reserves <= deep_required, EInvalidDeepFromReserves);

    // If deep_required is 0, give maximum discount
    if (deep_required == 0) return max_discount_rate;

    let deep_covered_by_user = deep_required - deep_from_reserves;

    // If user covers 0 DEEP, they get 0 discount
    if (deep_covered_by_user == 0) return 0;

    math::div(math::mul(max_discount_rate, deep_covered_by_user), deep_required)
}

/// Calculate the taker and maker ratios for an order based on execution status.
/// Returns (taker_ratio, maker_ratio) in billionths.
public(package) fun calculate_order_taker_maker_ratio(
    original_quantity: u64,
    executed_quantity: u64,
    order_status: u8,
): (u64, u64) {
    // Sanity checks: order quantity must be greater than 0, and executed quantity must not exceed
    // the total order quantity. This should be guaranteed by DeepBook. If it fails, the order
    // creation mechanism is flawed.
    assert!(original_quantity > 0, EZeroOriginalQuantity);
    assert!(executed_quantity <= original_quantity, EExecutedQuantityExceedsOriginal);

    // An order has maker part only if it's not fully executed and is live or partially filled
    let order_has_maker_part =
        executed_quantity < original_quantity &&
        (order_status == live() || order_status == partially_filled());

    let taker_ratio = math::div(executed_quantity, original_quantity);
    let maker_ratio = if (order_has_maker_part) HUNDRED_PERCENT - taker_ratio else 0;

    (taker_ratio, maker_ratio)
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
    let order_deep_price = pool.get_order_deep_price();
    (order_deep_price.asset_is_base(), order_deep_price.deep_per_asset())
}

/// Gets the DEEP/SUI price by comparing oracle and reference pool prices and selecting the best rate for the wrapper
///
/// This function implements a dual-price strategy to prevent arbitrage:
/// 1. Gets price from both oracle feeds and reference pool (both must be healthy)
/// 2. Returns the MAXIMUM price (users pay more SUI for DEEP)
///
/// The reference pool must be either DEEP/SUI or SUI/DEEP trading pair and must be
/// whitelisted and registered.
///
/// Parameters:
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - reference_pool: Pool containing DEEP/SUI or SUI/DEEP trading pair
/// - clock: System clock for price staleness verification
///
/// Returns:
/// - u64: DEEP/SUI price with 12 decimal places (maximum of oracle and reference pool)
///
/// Aborts if:
/// - Oracle price feeds are invalid, stale, or unavailable
/// - Reference pool is not whitelisted/registered
/// - Reference pool doesn't contain DEEP and SUI tokens
/// - Reference pool price calculation fails
public(package) fun get_sui_per_deep<ReferenceBaseAsset, ReferenceQuoteAsset>(
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    clock: &Clock,
): u64 {
    // Get prices from both sources
    let oracle_sui_per_deep = get_sui_per_deep_from_oracle(
        deep_usd_price_info,
        sui_usd_price_info,
        clock,
    );
    let reference_sui_per_deep = get_sui_per_deep_from_reference_pool(reference_pool, clock);

    // Choose maximum (best for wrapper - users pay more SUI for DEEP)
    if (oracle_sui_per_deep > reference_sui_per_deep) {
        oracle_sui_per_deep
    } else {
        reference_sui_per_deep
    }
}

/// Gets the SUI per DEEP price from a reference pool, normalizing the price regardless of token order
/// Uses the first ask price from the reference pool
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
/// Aborts with ENoAskPrice if there are no ask prices available in the reference pool
public(package) fun get_sui_per_deep_from_reference_pool<ReferenceBaseAsset, ReferenceQuoteAsset>(
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    clock: &Clock,
): u64 {
    assert!(
        reference_pool.whitelisted() && reference_pool.registered_pool(),
        EIneligibleReferencePool,
    );
    let reference_pool_price = get_pool_first_ask_price(reference_pool, clock);

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

/// Calculates the SUI per DEEP price using oracle price feeds for DEEP/USD and SUI/USD
/// This function performs the following steps:
/// 1. Retrieves and validates prices for both DEEP/USD and SUI/USD
/// 2. Verifies price feed identifiers match expected feeds
/// 3. Calculates DEEP/SUI price by dividing DEEP/USD by SUI/USD prices
/// 4. Adjusts decimal places to match DeepBook's DEEP/SUI price format (12 decimals)
///
/// Parameters:
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - clock: System clock for price staleness verification
///
/// Returns:
/// - u64: The calculated SUI per DEEP price with 12 decimal places
///
/// Aborts if:
/// - Either price feed is unavailable
/// - Price feed identifiers don't match expected DEEP/USD and SUI/USD feeds
/// - Price validation fails (staleness, confidence interval)
///
/// Technical details of the price calculation can be found in docs/oracle-price-calculation.md
public(package) fun get_sui_per_deep_from_oracle(
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    clock: &Clock,
): u64 {
    // Get DEEP/USD and SUI/USD prices
    let (deep_usd_price, deep_usd_price_identifier) = oracle::get_pyth_price(
        deep_usd_price_info,
        clock,
    );
    let (sui_usd_price, sui_usd_price_identifier) = oracle::get_pyth_price(
        sui_usd_price_info,
        clock,
    );

    // Validate price feed identifiers
    let deep_price_id = deep_usd_price_identifier.get_bytes();
    let sui_price_id = sui_usd_price_identifier.get_bytes();
    assert!(
        deep_price_id == oracle::deep_price_feed_id() && sui_price_id == oracle::sui_price_feed_id(),
        EInvalidPriceFeedIdentifier,
    );

    // Get magnitudes and exponents of the prices
    let deep_expo_i64 = deep_usd_price.get_expo();
    let sui_expo_i64 = sui_usd_price.get_expo();

    // Explicit checks for negative exponents - fail fast if Pyth changes format
    assert!(deep_expo_i64.get_is_negative(), EUnexpectedPositiveExponent);
    assert!(sui_expo_i64.get_is_negative(), EUnexpectedPositiveExponent);

    let deep_expo = deep_expo_i64.get_magnitude_if_negative();
    let sui_expo = sui_expo_i64.get_magnitude_if_negative();

    let deep_price_mag = deep_usd_price.get_price().get_magnitude_if_positive();
    let sui_price_mag = sui_usd_price.get_price().get_magnitude_if_positive();

    // Since Move doesn't support negative numbers, we calculate a positive adjustment
    // that can be applied either to numerator or denominator to achieve the same result
    let should_multiply_numerator = sui_expo + 3 >= deep_expo;
    let decimal_adjustment = if (should_multiply_numerator) {
        sui_expo + 3 - deep_expo
    } else {
        deep_expo - 3 - sui_expo
    };

    // Verify that the decimal adjustment is within the safe range
    assert!(decimal_adjustment <= MAX_SAFE_U64_POWER_OF_TEN, EDecimalAdjustmentTooLarge);
    let multiplier = u64::pow(10, decimal_adjustment as u8);

    // Calculate SUI per DEEP price
    // The multiplier position (numerator vs denominator) depends on the exponent delta
    // to ensure the result has exactly 12 decimal places to match DeepBook's DEEP/SUI price format
    let sui_per_deep = if (should_multiply_numerator) {
        math::div(deep_price_mag * multiplier, sui_price_mag)
    } else {
        math::div(deep_price_mag, sui_price_mag * multiplier)
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

/// Validates that the provided slippage value is within acceptable bounds
///
/// Parameters:
/// - slippage: The slippage value in billionths format (e.g., 10_000_000 = 1%)
///
/// Aborts with EInvalidSlippage if:
/// - Slippage value is greater than 100%
public(package) fun validate_slippage(slippage: u64) {
    assert!(slippage <= HUNDRED_PERCENT, EInvalidSlippage);
}

/// Gets the first (best) ask price from the order book
///
/// Parameters:
/// - pool: The trading pool to query for ask prices
/// - clock: System clock for current timestamp verification
///
/// Returns:
/// - u64: The first ask price in the order book
///
/// Aborts with ENoAskPrice if there are no ask prices available
public(package) fun get_pool_first_ask_price<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    clock: &Clock,
): u64 {
    let ticks = 1;
    let (_, _, ask_prices, _) = pool.get_level2_ticks_from_mid(ticks, clock);

    assert!(!ask_prices.is_empty(), ENoAskPrice);
    ask_prices[0]
}
