#[test_only]
module deepbook_wrapper::calculate_discount_rate_tests;

use deepbook_wrapper::helper::{calculate_discount_rate, EInvalidDeepFromReserves};
use std::unit_test::assert_eq;

// Common discount rates for testing
const MAX_DISCOUNT_10_PERCENT: u64 = 100_000_000; // 10% in billionths
const MAX_DISCOUNT_30_PERCENT: u64 = 300_000_000; // 30% in billionths
const MAX_DISCOUNT_50_PERCENT: u64 = 500_000_000; // 50% in billionths
const MAX_DISCOUNT_100_PERCENT: u64 = 1_000_000_000; // 100% in billionths

// Common DEEP amounts for testing
const DEEP_SMALL: u64 = 100; // 0.0001 DEEP (6 decimals)
const DEEP_MEDIUM: u64 = 1_000_000; // 1 DEEP
const DEEP_MASSIVE: u64 = 1_000_000_000; // 1,000 DEEP

// ===== Edge Cases =====

#[test]
/// Test when deep_required is zero - should return max_discount_rate
fun deep_required_zero() {
    // When deep_required is 0, user gets maximum discount regardless of deep_from_reserves
    let result = calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        0, // deep_from_reserves
        0, // deep_required
    );
    assert_eq!(result, MAX_DISCOUNT_50_PERCENT);

    // Test with different max discount rates
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        0, // deep_from_reserves
        0, // deep_required
    );
    assert_eq!(result, MAX_DISCOUNT_100_PERCENT);

    // Test with different max discount rates
    let result = calculate_discount_rate(
        MAX_DISCOUNT_30_PERCENT,
        0, // deep_from_reserves
        0, // deep_required
    );
    assert_eq!(result, MAX_DISCOUNT_30_PERCENT);
}

#[test]
/// Test when deep_from_reserves equals deep_required - should return 0 discount
fun deep_from_reserves_equals_required() {
    // When user pays nothing themselves, they get no discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        DEEP_SMALL, // deep_from_reserves
        DEEP_SMALL, // deep_required (equal)
    );
    assert_eq!(result, 0);

    // Test with different amounts
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        DEEP_MASSIVE, // deep_from_reserves
        DEEP_MASSIVE, // deep_required (equal)
    );
    assert_eq!(result, 0);
}

#[test]
/// Test when deep_from_reserves is zero - should return max_discount_rate
fun deep_from_reserves_zero() {
    // When user pays all fees themselves, they get maximum discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        0, // deep_from_reserves
        DEEP_SMALL, // deep_required
    );
    assert_eq!(result, MAX_DISCOUNT_50_PERCENT);

    // Test with different amounts
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        0, // deep_from_reserves
        DEEP_MASSIVE, // deep_required
    );
    assert_eq!(result, MAX_DISCOUNT_100_PERCENT);
}

#[test]
/// Test when max_discount_rate is zero - should always return 0
fun max_discount_rate_zero() {
    // When max discount is 0, result should always be 0
    let result = calculate_discount_rate(
        0, // max_discount_rate
        0, // deep_from_reserves
        DEEP_SMALL, // deep_required
    );
    assert_eq!(result, 0);

    // Test with different coverage ratios
    let result = calculate_discount_rate(
        0, // max_discount_rate
        DEEP_SMALL / 2, // deep_from_reserves (50% coverage)
        DEEP_SMALL, // deep_required
    );
    assert_eq!(result, 0);
}

// ===== Boundary Conditions =====

#[test, expected_failure(abort_code = EInvalidDeepFromReserves)]
/// Test when deep_from_reserves exceeds deep_required - should abort
fun deep_from_reserves_exceeds_required() {
    calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        DEEP_SMALL + 1, // deep_from_reserves (exceeds required)
        DEEP_SMALL, // deep_required
    );
}

#[test, expected_failure(abort_code = EInvalidDeepFromReserves)]
/// Test when deep_from_reserves is non-zero but deep_required is zero - should abort
fun deep_from_reserves_nonzero_with_zero_required() {
    calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        DEEP_SMALL, // deep_from_reserves (non-zero)
        0, // deep_required (zero)
    );
}

#[test]
/// Test with maximum discount rate (100%)
fun max_discount_rate_100_percent() {
    // Test 50% coverage with 100% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        DEEP_SMALL / 2, // deep_from_reserves (50% coverage)
        DEEP_SMALL, // deep_required
    );
    // Expected: 100% * (1 - 50%) = 50%
    assert_eq!(result, 500_000_000); // 50% in billionths

    // Test 25% coverage with 100% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        DEEP_SMALL * 3 / 4, // deep_from_reserves (75% coverage)
        DEEP_SMALL, // deep_required
    );
    // Expected: 100% * (1 - 75%) = 25%
    assert_eq!(result, 250_000_000); // 25% in billionths
}

// ===== Normal Cases =====

#[test]
/// Test 50% coverage scenarios with various max discount rates
fun fifty_percent_coverage() {
    let deep_from_reserves = DEEP_MEDIUM / 2; // 50 DEEP
    let deep_required = DEEP_MEDIUM; // 100 DEEP
    // User pays 50% of fees themselves, gets 50% of max discount

    // Test with 10% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_10_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 10% * 50% = 5%
    assert_eq!(result, 50_000_000); // 5% in billionths

    // Test with 30% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_30_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 30% * 50% = 15%
    assert_eq!(result, 150_000_000); // 15% in billionths

    // Test with 50% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 50% * 50% = 25%
    assert_eq!(result, 250_000_000); // 25% in billionths
}

#[test]
/// Test 25% coverage scenarios
fun twenty_five_percent_coverage() {
    let deep_from_reserves = DEEP_MEDIUM * 3 / 4; // 75 DEEP (75% from reserves)
    let deep_required = DEEP_MEDIUM; // 100 DEEP
    // User pays 25% of fees themselves, gets 25% of max discount

    // Test with 50% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 50% * 25% = 12.5%
    assert_eq!(result, 125_000_000); // 12.5% in billionths

    // Test with 100% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 100% * 25% = 25%
    assert_eq!(result, 250_000_000); // 25% in billionths
}

#[test]
/// Test 75% coverage scenarios
fun seventy_five_percent_coverage() {
    let deep_from_reserves = DEEP_MEDIUM / 4; // 25 DEEP (25% from reserves)
    let deep_required = DEEP_MEDIUM; // 100 DEEP
    // User pays 75% of fees themselves, gets 75% of max discount

    // Test with 50% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 50% * 75% = 37.5%
    assert_eq!(result, 375_000_000); // 37.5% in billionths

    // Test with 100% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 100% * 75% = 75%
    assert_eq!(result, 750_000_000); // 75% in billionths
}

#[test]
/// Test 90% coverage scenarios (high user contribution)
fun ninety_percent_coverage() {
    let deep_from_reserves = DEEP_MEDIUM / 10; // 10 DEEP (10% from reserves)
    let deep_required = DEEP_MEDIUM; // 100 DEEP
    // User pays 90% of fees themselves, gets 90% of max discount

    // Test with 50% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_50_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 50% * 90% = 45%
    assert_eq!(result, 450_000_000); // 45% in billionths

    // Test with 100% max discount
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        deep_from_reserves,
        deep_required,
    );
    // Expected: 100% * 90% = 90%
    assert_eq!(result, 900_000_000); // 90% in billionths
}

// ===== Math Precision Tests =====

#[test]
/// Test with small amounts to verify integer division precision
fun small_amounts_precision() {
    // Test with amounts that could cause precision issues
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        1, // deep_from_reserves
        3, // deep_required
    );
    // Expected: 100% * (3-1)/3 = 100% * 2/3 = 66.666...%
    // Due to integer division, this should round down
    assert_eq!(result, 666_666_666); // Rounded down from 666.666...%

    // Test with very small values
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        2, // deep_from_reserves
        3, // deep_required
    );
    // Expected: 100% * (3-2)/3 = 100% * 1/3 = 33.333...%
    assert_eq!(result, 333_333_333); // Rounded down from 333.333...%
}

#[test]
/// Test with large values to ensure no overflow
fun large_values() {
    // Test with large values close to u64 limits
    let large_deep = 18_000_000_000_000_000_000; // Close to max u64
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT,
        large_deep / 2, // deep_from_reserves (50% coverage)
        large_deep, // deep_required
    );
    // Expected: 100% * 50% = 50%
    assert_eq!(result, 500_000_000); // 50% in billionths

    // Test with maximum possible max_discount_rate
    let result = calculate_discount_rate(
        MAX_DISCOUNT_100_PERCENT, // 100% max discount
        large_deep / 4, // deep_from_reserves (25% coverage)
        large_deep, // deep_required
    );
    // Expected: 100% * 75% = 75%
    assert_eq!(result, 750_000_000); // 75% in billionths
}

// ===== Formula Verification =====

#[test]
/// Test linear scaling behavior
fun linear_scaling() {
    let max_discount = MAX_DISCOUNT_100_PERCENT;
    let deep_required = 1000;

    // Test different coverage percentages
    let coverages = vector[0, 10, 25, 50, 75, 90, 100];
    let mut i = 0;
    while (i < vector::length(&coverages)) {
        let coverage_percent = *vector::borrow(&coverages, i);
        let deep_from_reserves = deep_required * coverage_percent / 100;
        let expected_discount = max_discount * (100 - coverage_percent) / 100;

        let result = calculate_discount_rate(
            max_discount,
            deep_from_reserves,
            deep_required,
        );

        assert_eq!(result, expected_discount);
        i = i + 1;
    };
}

#[test]
/// Test various max discount rates with fixed coverage
fun various_max_discounts() {
    let deep_from_reserves = DEEP_MEDIUM / 2; // 50% coverage
    let deep_required = DEEP_MEDIUM;

    // Test with different max discount rates
    let max_discounts = vector[
        0, // 0%
        50_000_000, // 5%
        100_000_000, // 10%
        250_000_000, // 25%
        500_000_000, // 50%
        750_000_000, // 75%
        1_000_000_000, // 100%
    ];

    let mut i = 0;
    while (i < vector::length(&max_discounts)) {
        let max_discount = *vector::borrow(&max_discounts, i);
        let expected_discount = max_discount / 2; // 50% of max discount

        let result = calculate_discount_rate(
            max_discount,
            deep_from_reserves,
            deep_required,
        );

        assert_eq!(result, expected_discount);
        i = i + 1;
    };
}

// ===== Edge Transitions =====

#[test]
/// Test values just above and below key thresholds
fun threshold_transitions() {
    let max_discount = MAX_DISCOUNT_100_PERCENT;
    let deep_required = 1000;

    // Test just above 0% coverage
    let result = calculate_discount_rate(
        max_discount,
        deep_required - 1, // 99.9% coverage
        deep_required,
    );
    // Expected: 100% * 0.1% = 0.1%
    assert_eq!(result, 1_000_000); // 0.1% in billionths

    // Test just below 100% coverage
    let result = calculate_discount_rate(
        max_discount,
        1, // 0.1% coverage
        deep_required,
    );
    // Expected: 100% * 99.9% = 99.9%
    assert_eq!(result, 999_000_000); // 99.9% in billionths
}
