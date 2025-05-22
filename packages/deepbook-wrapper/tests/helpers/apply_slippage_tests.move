#[test_only]
module deepbook_wrapper::apply_slippage_tests;

use deepbook_wrapper::helper;
use deepbook_wrapper::math;

/// Test that applying slippage to zero value returns zero
#[test]
fun test_zero_value() {
    let result = helper::apply_slippage(0, 10_000_000); // 1% slippage
    assert!(result == 0, 0);
}

/// Test that applying zero slippage returns the original value
#[test]
fun test_zero_slippage() {
    let value = 1000;
    let result = helper::apply_slippage(value, 0);
    assert!(result == value, 0);
}

/// Test slippage on tiny values (1)
/// Due to integer division, this should return the original value
#[test]
fun test_tiny_value() {
    let value = 1;
    let slippage = 5_000_000; // 0.5%
    let result = helper::apply_slippage(value, slippage);

    // Formula: value + (value * slippage / 1_000_000_000)
    // 1 + (1 * 5_000_000 / 1_000_000_000) = 1 + 0 = 1
    assert!(result == value, 0);

    // Confirm mathematically why it remains unchanged
    let slippage_amount = math::mul(value, slippage);
    assert!(slippage_amount == 0, 1); // Confirm it rounds to zero
}

/// Test slippage on small values (100)
/// This tests the threshold where integer division causes no effect
#[test]
fun test_small_value() {
    let value = 100;
    let slippage = 5_000_000; // 0.5%
    let result = helper::apply_slippage(value, slippage);

    // 100 + (100 * 5_000_000 / 1_000_000_000) = 100 + 0 = 100
    assert!(result == value, 0);
}

/// Test to find threshold where slippage starts having effect with 0.1% slippage
#[test]
fun test_threshold_small_slippage() {
    let slippage = 1_000_000; // 0.1%

    // For 0.1% slippage, effect starts at value = 1_000_000_000 / 1_000_000 = 1000
    let below_threshold = 999;
    let at_threshold = 1000;

    // Below threshold - no effect
    assert!(helper::apply_slippage(below_threshold, slippage) == below_threshold, 0);

    // At threshold - should add 1
    let result = helper::apply_slippage(at_threshold, slippage);
    assert!(result == at_threshold + 1, 1);
}

/// Test to find threshold where 10% slippage starts having effect
#[test]
fun test_threshold_default_slippage() {
    let slippage = 100_000_000; // 10%

    // For 10% slippage, effect starts at value = 1_000_000_000 / 100_000_000 = 10

    // Values below threshold - no effect
    let values_below = vector[1, 5, 9];

    let mut i = 0;
    while (i < vector::length(&values_below)) {
        let value = *vector::borrow(&values_below, i);
        assert!(helper::apply_slippage(value, slippage) == value, 0);
        i = i + 1;
    };

    // At threshold - should add 1
    let at_threshold = 10;
    let result = helper::apply_slippage(at_threshold, slippage);
    assert!(result == at_threshold + 1, 1); // 10 + 1 = 11

    // Just above threshold
    let just_above = 20;
    let result = helper::apply_slippage(just_above, slippage);
    assert!(result == just_above + 2, 2); // 20 + 2 = 22
}

/// Test with more typical values and common slippage percentages
#[test]
fun test_normal_cases() {
    // Test with 1_000_000 value and various slippages
    let value = 1_000_000;

    // 0.1% slippage
    let result = helper::apply_slippage(value, 1_000_000);
    assert!(result == 1_001_000, 0); // 1_000_000 + 1_000

    // 0.5% slippage
    let result = helper::apply_slippage(value, 5_000_000);
    assert!(result == 1_005_000, 1); // 1_000_000 + 5_000

    // 1% slippage
    let result = helper::apply_slippage(value, 10_000_000);
    assert!(result == 1_010_000, 2); // 1_000_000 + 10_000

    // 5% slippage
    let result = helper::apply_slippage(value, 50_000_000);
    assert!(result == 1_050_000, 3); // 1_000_000 + 50_000

    // 10% slippage
    let result = helper::apply_slippage(value, 100_000_000);
    assert!(result == 1_100_000, 4); // 1_000_000 + 100_000
}

/// Test 10% slippage with various values
#[test]
fun test_default_slippage_cases() {
    let slippage = 100_000_000; // 10%

    // Test with different powers of 10
    let values = vector[100, 1_000, 10_000, 100_000, 1_000_000];
    let expected = vector[110, 1_100, 11_000, 110_000, 1_100_000];

    let mut i = 0;
    while (i < vector::length(&values)) {
        let value = *vector::borrow(&values, i);
        let expected_result = *vector::borrow(&expected, i);
        let result = helper::apply_slippage(value, slippage);

        assert!(result == expected_result, i);
        i = i + 1;
    };
}

/// Test 10% slippage with non-round numbers and varied values
/// This tests more realistic scenarios with arbitrary values
#[test]
fun test_varied_values_with_default_slippage() {
    let slippage = 100_000_000; // 10%

    // Test with varied values (prime numbers, mixed digits, non-decimal friendly)
    // Using two separate vectors instead of tuples since Move doesn't support vector of tuples
    let values = vector[
        17, // Prime number (17 + 1.7 = 18.7, rounds to 18)
        23, // Prime number (23 + 2.3 = 25.3, rounds to 25)
        97, // Prime number (97 + 9.7 = 106.7, rounds to 106)
        123, // Mixed digits (123 + 12.3 = 135.3, rounds to 135)
        456, // Mixed digits (456 + 45.6 = 501.6, rounds to 501)
        789, // Mixed digits (789 + 78.9 = 867.9, rounds to 867)
        33, // Non-decimal friendly (33 + 3.3 = 36.3, rounds to 36)
        67, // Non-decimal friendly (67 + 6.7 = 73.7, rounds to 73)
        999, // Near thousand (999 + 99.9 = 1098.9, rounds to 1098)
    ];

    let expected_results = vector[
        18, // 17 + 1.7 = 18.7, rounds to 18
        25, // 23 + 2.3 = 25.3, rounds to 25
        106, // 97 + 9.7 = 106.7, rounds to 106
        135, // 123 + 12.3 = 135.3, rounds to 135
        501, // 456 + 45.6 = 501.6, rounds to 501
        867, // 789 + 78.9 = 867.9, rounds to 867
        36, // 33 + 3.3 = 36.3, rounds to 36
        73, // 67 + 6.7 = 73.7, rounds to 73
        1098, // 999 + 99.9 = 1098.9, rounds to 1098
    ];

    let mut i = 0;
    while (i < vector::length(&values)) {
        let value = *vector::borrow(&values, i);
        let expected = *vector::borrow(&expected_results, i);
        let result = helper::apply_slippage(value, slippage);

        // Check the result matches our manual calculation
        assert!(result == expected, i);

        // Also verify it's approximately 10% more (allowing for rounding)
        // For small values, the difference might not be exactly 10% due to integer division
        let min_expected = value + (value / 10); // At least value + 10% with integer division
        assert!(result >= min_expected, 100 + i);

        i = i + 1;
    };
}

/// Test that the function properly handles large values without overflow
#[test]
fun test_large_values() {
    // Test with a large value but small slippage
    let large_value = 18_000_000_000_000_000_000; // Close to max u64
    let small_slippage = 1_000_000; // 0.1%

    // Calculate expected: large_value + (large_value * small_slippage / 1_000_000_000)
    // We expect an 0.1% increase
    let expected = large_value + 18_000_000_000_000_000; // 0.1% of large_value
    let result = helper::apply_slippage(large_value, small_slippage);

    assert!(result == expected, 0);
}

/// Test slippage at values that could cause overflow when calculating the slippage amount
/// This shows the safe internal handling using u128
#[test]
fun test_overflow_risk_in_calculation() {
    // Value that would overflow if multiplied directly as u64
    // We'll use a value that when multiplied by 10% would exceed u64 max
    let high_value = 18_446_744_073_709_551_615 / 10; // u64 max / 10
    let slippage = 100_000_000; // 10%

    // This would overflow if done naively, but our implementation prevents this
    let result = helper::apply_slippage(high_value, slippage);

    // Expected = high_value + high_value/10
    let expected = high_value + (high_value / 10);
    assert!(result == expected, 0);
}

/// Test for potential overflow in the final addition step
/// This is a theoretical edge case that will cause the function to fail due to overflow
///
/// This test is expected to fail because:
/// 1. When we take max_value (u64 max) and apply even the smallest slippage (1 = 0.0000001%),
///    the math::mul function will produce a non-zero slippage amount (18 in this case)
/// 2. When we try to add this amount to max_value, it will exceed u64 max and cause an arithmetic overflow
/// 3. Move's arithmetic operations fail with an error when they would overflow (unlike some languages
///    that silently wrap around)
///
/// We keep this test as an expected failure to:
/// - Document this limitation in the function
/// - Demonstrate that values very close to u64 max can cause overflow with even small slippage
/// - Alert developers to handle extremely large token amounts appropriately
///
/// In real-world use, this should not be an issue since token values approaching u64 max are extremely rare.
#[test, expected_failure]
fun test_addition_overflow_protection() {
    // Taking max u64 value and applying a tiny slippage
    let max_value = 18_446_744_073_709_551_615; // u64 max
    let tiny_slippage = 1; // 0.0000001%

    // This line will cause overflow in the function when it tries to add the slippage amount
    // to the already maximum u64 value
    let result = helper::apply_slippage(max_value, tiny_slippage);

    // We never reach this point due to the overflow error
    assert!(result >= max_value, 0);
}

/// Verify invariant: result is always >= input value (since we only allow positive slippage)
#[test]
fun test_invariant_result_not_smaller() {
    // Test various value/slippage combinations
    let test_values = vector[0, 1, 100, 1000, 1_000_000, 1_000_000_000];
    let test_slippages = vector[0, 1, 1_000_000, 10_000_000, 100_000_000];

    let mut i = 0;
    while (i < vector::length(&test_values)) {
        let value = *vector::borrow(&test_values, i);

        let mut j = 0;
        while (j < vector::length(&test_slippages)) {
            let slippage = *vector::borrow(&test_slippages, j);
            let result = helper::apply_slippage(value, slippage);

            // Verify invariant: result >= value
            assert!(result >= value, 0);

            j = j + 1;
        };

        i = i + 1;
    };
}
