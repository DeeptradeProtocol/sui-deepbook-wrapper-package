#[test_only]
module deepbook_wrapper::calculate_deep_reserves_coverage_order_fee_tests;

use deepbook_wrapper::fee::calculate_deep_reserves_coverage_order_fee;

const SUI_PER_DEEP: u64 = 37_815_000_000;

#[test]
fun test_zero_deep_from_reserves() {
    let result = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        0, // No DEEP from reserves
    );
    assert!(result == 0, 0);
}

#[test]
fun test_minimum_values() {
    let result = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        1, // Minimum non-zero DEEP
    );
    assert!(result > 0, 0); // Should result in some SUI fee
    assert!(result == 37, 1); // Expected SUI amount (rounded)
}

#[test]
fun test_large_values() {
    let result = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        1_000_000_000_000, // Large DEEP amount
    );
    // Verify no overflow and correct calculation
    assert!(result == 37_815_000_000_000, 0);
}

#[test]
fun test_standard_case() {
    let deep_from_reserves = 100_000;
    let expected_sui =
        (deep_from_reserves as u128) * 
            (SUI_PER_DEEP as u128) / 1_000_000_000;

    let result = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        deep_from_reserves,
    );
    assert!(result == (expected_sui as u64), 0);
}
