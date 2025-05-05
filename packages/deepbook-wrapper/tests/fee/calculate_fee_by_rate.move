#[test_only]
module deepbook_wrapper::calculate_fee_by_rate_tests;

use deepbook_wrapper::fee::calculate_fee_by_rate;

/// Constants for common test values
const FEE_SCALING: u64 = 1_000_000_000; // 10^9

#[test]
/// Test when amount or fee_bps is zero, result should be zero
fun test_zero_values() {
    // When amount is zero, result should be zero regardless of fee_bps
    let fee = calculate_fee_by_rate(0, 1000000);
    assert!(fee == 0, 0);

    // When fee_bps is zero, result should be zero regardless of amount
    let fee = calculate_fee_by_rate(1000, 0);
    assert!(fee == 0, 0);

    // When both are zero, result should be zero
    let fee = calculate_fee_by_rate(0, 0);
    assert!(fee == 0, 0);
}

#[test]
/// Test with standard fee rates (0.1%, 0.3%, 0.5%, 1%)
fun test_standard_fee_rates() {
    let amount = 1000000; // 1 million tokens

    // 0.1% fee (1,000,000 bps)
    let fee_01_percent = calculate_fee_by_rate(amount, 1000000);
    // Expected: 1000000 * 1000000 / 1000000000 = 1000
    assert!(fee_01_percent == 1000, 0); // 0.1% of 1,000,000

    // 0.3% fee (3,000,000 bps)
    let fee_03_percent = calculate_fee_by_rate(amount, 3000000);
    // Expected: 1000000 * 3000000 / 1000000000 = 3000
    assert!(fee_03_percent == 3000, 0); // 0.3% of 1,000,000

    // 0.5% fee (5,000,000 bps)
    let fee_05_percent = calculate_fee_by_rate(amount, 5000000);
    // Expected: 1000000 * 5000000 / 1000000000 = 5000
    assert!(fee_05_percent == 5000, 0); // 0.5% of 1,000,000

    // 1% fee (10,000,000 bps)
    let fee_1_percent = calculate_fee_by_rate(amount, 10000000);
    // Expected: 1000000 * 10000000 / 1000000000 = 10000
    assert!(fee_1_percent == 10000, 0); // 1% of 1,000,000
}

#[test]
/// Test with various token amounts
fun test_various_amounts() {
    let fee_bps = 2000000; // 0.2%

    // Small amount
    let fee_small = calculate_fee_by_rate(100, fee_bps);
    // Expected: 100 * 2000000 / 1000000000 = 0.2, rounds to 0
    assert!(fee_small == 0, 0);

    // Medium amount
    let fee_medium = calculate_fee_by_rate(10000, fee_bps);
    // Expected: 10000 * 2000000 / 1000000000 = 20
    assert!(fee_medium == 20, 0);

    // Large amount
    let fee_large = calculate_fee_by_rate(1000000, fee_bps);
    // Expected: 1000000 * 2000000 / 1000000000 = 2000
    assert!(fee_large == 2000, 0);

    // Very large amount
    let fee_very_large = calculate_fee_by_rate(1000000000, fee_bps);
    // Expected: 1000000000 * 2000000 / 1000000000 = 2000000
    assert!(fee_very_large == 2000000, 0);
}

#[test]
/// Test with extremely small fee rates
fun test_small_fee_rates() {
    let amount = 1000000000; // 1 billion tokens

    // 0.0001% fee (1,000 bps)
    let fee_0001_percent = calculate_fee_by_rate(amount, 1000);
    // Expected: 1000000000 * 1000 / 1000000000 = 1000
    assert!(fee_0001_percent == 1000, 0);

    // 0.00001% fee (100 bps)
    let fee_00001_percent = calculate_fee_by_rate(amount, 100);
    // Expected: 1000000000 * 100 / 1000000000 = 100
    assert!(fee_00001_percent == 100, 0);

    // 0.000001% fee (10 bps)
    let fee_000001_percent = calculate_fee_by_rate(amount, 10);
    // Expected: 1000000000 * 10 / 1000000000 = 10
    assert!(fee_000001_percent == 10, 0);

    // 0.0000001% fee (1 bps)
    let fee_0000001_percent = calculate_fee_by_rate(amount, 1);
    // Expected: 1000000000 * 1 / 1000000000 = 1
    assert!(fee_0000001_percent == 1, 0);
}

#[test]
/// Test rounding behavior with integer division
fun test_rounding() {
    // Tests where the division should round to zero
    let fee_bps = 1000000; // 0.1%

    // 499 * 0.1% = 0.499, should round to 0
    let fee1 = calculate_fee_by_rate(499, fee_bps);
    assert!(fee1 == 0, 0);

    // 500 * 0.1% = 0.5, would be 0 with integer division
    let fee2 = calculate_fee_by_rate(500, fee_bps);
    assert!(fee2 == 0, 0);

    // 999 * 0.1% = 0.999, should round to 0
    let fee3 = calculate_fee_by_rate(999, fee_bps);
    assert!(fee3 == 0, 0);

    // 1000 * 0.1% = 1, should be exactly 1
    let fee4 = calculate_fee_by_rate(1000, fee_bps);
    assert!(fee4 == 1, 0);

    // 1001 * 0.1% = 1.001, should round to 1
    let fee5 = calculate_fee_by_rate(1001, fee_bps);
    assert!(fee5 == 1, 0);
}

#[test]
/// Test with large values close to u64 max
fun test_large_values() {
    // Using large values to test for overflow handling
    let large_amount = 18446744073709551000; // close to max u64
    let fee_bps = 1000000; // 0.1%

    // This should not overflow due to u128 casting
    let fee = calculate_fee_by_rate(large_amount, fee_bps);

    // Expected: large_amount * fee_bps / FEE_SCALING
    // = 18446744073709551000 * 1000000 / 1000000000
    // = 18446744073709551000 / 1000
    // = 18446744073709551
    assert!(fee > 0, 0);

    // Verify exact expected value
    let expected = 18446744073709551;
    assert!(fee == expected, 0);
}

#[test]
/// Test with maximum possible fee rate (100%)
fun test_max_fee_rate() {
    let amount = 1000000;
    let max_fee_bps = FEE_SCALING; // 100%

    let fee = calculate_fee_by_rate(amount, max_fee_bps);
    // Expected: 1000000 * 1000000000 / 1000000000 = 1000000
    assert!(fee == amount, 0); // 100% of amount
}

#[test]
/// Test when amount is equal to fee_bps
fun test_equal_values() {
    let value = 5000000;

    let fee = calculate_fee_by_rate(value, value);
    // Expected: 5000000 * 5000000 / 1000000000 = 25000
    assert!(fee == 25000, 0);
}

#[test]
/// Test with different combinations of amounts and fee rates
fun test_combinations() {
    // Test various combinations to ensure formula works correctly

    // Small amount, large fee
    let fee1 = calculate_fee_by_rate(100, 100000000); // 100 tokens, 10% fee
    // Expected: 100 * 100000000 / 1000000000 = 10
    assert!(fee1 == 10, 0);

    // Large amount, small fee
    let fee2 = calculate_fee_by_rate(100000000, 100); // 100M tokens, 0.00001% fee
    // Expected: 100000000 * 100 / 1000000000 = 10
    assert!(fee2 == 10, 0);

    // Medium values
    let fee3 = calculate_fee_by_rate(50000, 5000000); // 50K tokens, 0.5% fee
    // Expected: 50000 * 5000000 / 1000000000 = 250
    assert!(fee3 == 250, 0);
}
