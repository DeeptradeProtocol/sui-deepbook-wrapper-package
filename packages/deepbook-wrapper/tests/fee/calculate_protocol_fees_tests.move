#[test_only]
module deepbook_wrapper::calculate_protocol_fees_tests;

use deepbook_wrapper::fee::calculate_protocol_fees;
use std::unit_test::assert_eq;

// === Test Constants ===
const SCALE: u64 = 1_000_000_000; // 100% in billionths

// Order amounts for testing
const ORDER_AMOUNT_SMALL: u64 = 1_000_000; // 0.001 tokens
const ORDER_AMOUNT_MEDIUM: u64 = 1_000_000_000_000; // 1,000 tokens
const ORDER_AMOUNT_LARGE: u64 = 1_000_000_000_000_000; // 1,000,000 tokens

// Fee rates for testing (in billionths)
const FEE_RATE_LOW: u64 = 100_000; // 0.01%
const FEE_RATE_MEDIUM: u64 = 1_000_000; // 0.1%
const FEE_RATE_HIGH: u64 = 10_000_000; // 1%

// Discount rates for testing (in billionths)
const DISCOUNT_RATE_NONE: u64 = 0; // 0%
const DISCOUNT_RATE_LOW: u64 = 100_000_000; // 10%
const DISCOUNT_RATE_MEDIUM: u64 = 250_000_000; // 25%
const DISCOUNT_RATE_HIGH: u64 = 500_000_000; // 50%
const DISCOUNT_RATE_MAX: u64 = 1_000_000_000; // 100%

// === Valid Scenarios ===

#[test]
fun pure_taker_order() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee (not used)
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected: order_amount * taker_ratio * taker_fee_rate = 1_000_000_000_000 * 1 * 0.001 = 1_000_000_000
    assert_eq!(taker_fee, 1_000_000_000);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 1_000_000_000);
}

#[test]
fun pure_maker_order() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        0, // 0% taker
        SCALE, // 100% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee (not used)
        FEE_RATE_LOW, // 0.01% maker fee
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected: order_amount * maker_ratio * maker_fee_rate = 1_000_000_000_000 * 1 * 0.0001 = 100_000_000
    assert_eq!(taker_fee, 0);
    assert_eq!(maker_fee, 100_000_000);
    assert_eq!(total_fee, 100_000_000);
}

#[test]
fun fifty_fifty_split() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        500_000_000, // 50% taker
        500_000_000, // 50% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected taker: 1_000_000_000_000 * 0.5 * 0.001 = 500_000_000
    // Expected maker: 1_000_000_000_000 * 0.5 * 0.0001 = 50_000_000
    assert_eq!(taker_fee, 500_000_000);
    assert_eq!(maker_fee, 50_000_000);
    assert_eq!(total_fee, 550_000_000);
}

#[test]
fun seventy_thirty_split() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        700_000_000, // 70% taker
        300_000_000, // 30% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected taker: 1_000_000_000_000 * 0.7 * 0.001 = 700_000_000
    // Expected maker: 1_000_000_000_000 * 0.3 * 0.0001 = 30_000_000
    assert_eq!(taker_fee, 700_000_000);
    assert_eq!(maker_fee, 30_000_000);
    assert_eq!(total_fee, 730_000_000);
}

#[test]
fun partial_execution_market_order() {
    // Simulates a market order that was 60% filled, then canceled
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        600_000_000, // 60% taker (executed portion)
        0, // 0% maker (market order, canceled remainder)
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee (not used)
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected: only charge fee on executed 60%
    // Expected taker: 1_000_000_000_000 * 0.6 * 0.001 = 600_000_000
    assert_eq!(taker_fee, 600_000_000);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 600_000_000);
}

#[test]
fun partial_execution_limit_order() {
    // Simulates a limit order that was 30% filled, then canceled
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        300_000_000, // 30% taker (executed portion)
        0, // 0% maker (canceled, so no maker portion)
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee (not used)
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected: only charge fee on executed 30%
    // Expected taker: 1_000_000_000_000 * 0.3 * 0.001 = 300_000_000
    assert_eq!(taker_fee, 300_000_000);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 300_000_000);
}

#[test]
fun minimal_execution() {
    // Order that was barely executed (0.1%) then canceled/expired
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        1_000_000, // 0.1% taker
        0, // 0% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee (not used)
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected: 1_000_000_000_000 * 0.001 * 0.001 = 1_000_000
    assert_eq!(taker_fee, 1_000_000);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 1_000_000);
}

#[test]
fun discount_application() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee (not used)
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_MEDIUM, // 25% discount
    );

    // Expected before discount: 1_000_000_000_000 * 1 * 0.001 = 1_000_000_000
    // Expected after 25% discount: 1_000_000_000 * 0.75 = 750_000_000
    assert_eq!(taker_fee, 750_000_000);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 750_000_000);
}

#[test]
fun maximum_discount() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee (not used)
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_MAX, // 100% discount
    );

    // Expected: 100% discount should result in zero fees
    assert_eq!(taker_fee, 0);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 0);
}

#[test]
fun mixed_order_with_discount() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        600_000_000, // 60% taker
        400_000_000, // 40% maker
        FEE_RATE_HIGH, // 1% taker fee
        FEE_RATE_MEDIUM, // 0.1% maker fee
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_LOW, // 10% discount
    );

    // Expected taker before discount: 1_000_000_000_000 * 0.6 * 0.01 = 6_000_000_000
    // Expected maker before discount: 1_000_000_000_000 * 0.4 * 0.001 = 400_000_000
    // Expected taker after 10% discount: 6_000_000_000 * 0.9 = 5_400_000_000
    // Expected maker after 10% discount: 400_000_000 * 0.9 = 360_000_000
    assert_eq!(taker_fee, 5_400_000_000);
    assert_eq!(maker_fee, 360_000_000);
    assert_eq!(total_fee, 5_760_000_000);
}

#[test]
fun small_order_amount() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee (not used)
        ORDER_AMOUNT_SMALL,
        DISCOUNT_RATE_NONE,
    );

    // Expected: 1_000_000 * 1 * 0.001 = 1_000
    assert_eq!(taker_fee, 1_000);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 1_000);
}

#[test]
fun large_order_amount() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee (not used)
        ORDER_AMOUNT_LARGE,
        DISCOUNT_RATE_NONE,
    );

    // Expected: 1_000_000_000_000_000 * 1 * 0.001 = 1_000_000_000_000
    assert_eq!(taker_fee, 1_000_000_000_000);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 1_000_000_000_000);
}

#[test]
fun zero_fee_rates() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        500_000_000, // 50% taker
        500_000_000, // 50% maker
        0, // 0% taker fee
        0, // 0% maker fee
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected: zero fees
    assert_eq!(taker_fee, 0);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 0);
}

#[test]
fun one_zero_fee_rate() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        500_000_000, // 50% taker
        500_000_000, // 50% maker
        FEE_RATE_MEDIUM, // 0.1% taker fee
        0, // 0% maker fee
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected taker: 1_000_000_000_000 * 0.5 * 0.001 = 500_000_000
    // Expected maker: 0
    assert_eq!(taker_fee, 500_000_000);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 500_000_000);
}

#[test]
fun minimum_values() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        1, // Minimum taker ratio
        999_999_999, // Maximum maker ratio (sum = 1_000_000_000)
        1, // Minimum taker fee rate
        1, // Minimum maker fee rate
        1, // Minimum order amount
        DISCOUNT_RATE_NONE,
    );

    // All calculations should result in 0 due to rounding down
    assert_eq!(taker_fee, 0);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 0);
}

#[test]
fun no_execution() {
    // Order that was placed but never executed (0% filled)
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        0, // 0% taker (no execution)
        0, // 0% maker (no execution)
        FEE_RATE_MEDIUM, // 0.1% taker fee
        FEE_RATE_LOW, // 0.01% maker fee
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    // Expected: no fees since no execution occurred
    assert_eq!(taker_fee, 0);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 0);
}

// === Invalid Scenarios ===

#[test]
#[expected_failure(abort_code = deepbook_wrapper::fee::EInvalidRatioSum)]
fun ratios_sum_greater_than_100_percent() {
    let (_, _, _) = calculate_protocol_fees(
        600_000_000, // 60% taker
        500_000_000, // 50% maker (sum = 110%)
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );
}

#[test]
#[expected_failure(abort_code = deepbook_wrapper::fee::EInvalidRatioSum)]
fun both_ratios_maximum() {
    let (_, _, _) = calculate_protocol_fees(
        SCALE, // 100% taker
        SCALE, // 100% maker (sum = 200%)
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );
}

#[test]
#[expected_failure(abort_code = deepbook_wrapper::fee::EZeroOrderAmount)]
fun zero_order_amount() {
    let (_, _, _) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        0, // Zero order amount
        DISCOUNT_RATE_NONE,
    );
}

#[test]
#[expected_failure(abort_code = deepbook_wrapper::fee::EInvalidRatioSum)]
fun invalid_ratios_and_zero_order_amount() {
    // Test that ratio validation happens first
    let (_, _, _) = calculate_protocol_fees(
        600_000_000, // 60% taker
        500_000_000, // 50% maker (sum = 110%)
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        0, // Zero order amount
        DISCOUNT_RATE_NONE,
    );
}

#[test]
#[expected_failure(abort_code = deepbook_wrapper::fee::EInvalidRatioSum)]
fun ratios_sum_off_by_one_over() {
    let (_, _, _) = calculate_protocol_fees(
        500_000_000, // 50% taker
        500_000_001, // 50% maker + 1 (sum = 1_000_000_001)
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );
}

#[test]
#[expected_failure(abort_code = deepbook_wrapper::fee::EInvalidRatioSum)]
fun single_ratio_over_100_percent() {
    let (_, _, _) = calculate_protocol_fees(
        1_000_000_001, // 100% + 1 taker (invalid)
        0, // 0% maker
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );
}

// === Edge Cases ===

#[test]
fun precision_with_tiny_amounts() {
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        333_333_333, // ≈33.33% taker
        666_666_667, // ≈66.67% maker (sum = 1_000_000_000)
        FEE_RATE_LOW, // 0.01% taker fee
        FEE_RATE_LOW, // 0.01% maker fee
        100, // Very small order amount
        DISCOUNT_RATE_NONE,
    );

    // All calculations should result in 0 due to rounding down
    assert_eq!(taker_fee, 0);
    assert_eq!(maker_fee, 0);
    assert_eq!(total_fee, 0);
}

#[test]
fun formula_verification() {
    // Test that total_fee = taker_fee + maker_fee always holds
    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        750_000_000, // 75% taker
        250_000_000, // 25% maker
        FEE_RATE_HIGH, // 1% taker fee
        FEE_RATE_MEDIUM, // 0.1% maker fee
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_MEDIUM, // 25% discount
    );

    assert_eq!(total_fee, taker_fee + maker_fee);
    assert!(total_fee > 0); // Should have non-zero fees
}

#[test]
fun scaling_linearity() {
    // Test that doubling order amount doubles fees
    let (total_fee_1x, taker_fee_1x, maker_fee_1x) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    let (total_fee_2x, taker_fee_2x, maker_fee_2x) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        ORDER_AMOUNT_MEDIUM * 2,
        DISCOUNT_RATE_NONE,
    );

    assert_eq!(total_fee_2x, total_fee_1x * 2);
    assert_eq!(taker_fee_2x, taker_fee_1x * 2);
    assert_eq!(maker_fee_2x, maker_fee_1x * 2);
}

#[test]
fun discount_linearity() {
    // Test discount application with different discount rates
    let (total_fee_no_discount, _, _) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_NONE,
    );

    let (total_fee_half_discount, _, _) = calculate_protocol_fees(
        SCALE, // 100% taker
        0, // 0% maker
        FEE_RATE_MEDIUM,
        FEE_RATE_LOW,
        ORDER_AMOUNT_MEDIUM,
        DISCOUNT_RATE_HIGH, // 50% discount
    );

    // 50% discount should result in 50% of original fee
    assert_eq!(total_fee_half_discount, total_fee_no_discount / 2);
}
