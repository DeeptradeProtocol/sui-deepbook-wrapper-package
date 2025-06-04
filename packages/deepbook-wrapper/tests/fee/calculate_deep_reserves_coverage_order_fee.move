#[test_only]
module deepbook_wrapper::calculate_deep_reserves_coverage_order_fee_tests;

use deepbook_wrapper::fee::calculate_deep_reserves_coverage_order_fee;
use std::unit_test::assert_eq;

const SUI_PER_DEEP: u64 = 37_815_000_000;

#[test]
fun zero_deep_from_reserves() {
    let result = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        0, // No DEEP from reserves
    );
    assert_eq!(result, 0);
}

#[test]
fun minimum_values() {
    let result = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        1, // Minimum non-zero DEEP
    );
    assert!(result > 0); // Should result in some SUI fee
    assert_eq!(result, 37); // Expected SUI amount (rounded)
}

#[test]
fun large_values() {
    let result = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        1_000_000_000_000, // Large DEEP amount
    );
    // Verify no overflow and correct calculation
    assert_eq!(result, 37_815_000_000_000);
}

#[test]
fun standard_case() {
    let deep_from_reserves = 100_000;
    let expected_sui =
        (deep_from_reserves as u128) * 
            (SUI_PER_DEEP as u128) / 1_000_000_000;

    let result = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        deep_from_reserves,
    );
    assert_eq!(result, (expected_sui as u64));
}
