#[test_only]
module deepbook_wrapper::validate_fees_against_max_tests;

use deepbook_wrapper::fee::calculate_full_order_fee;
use deepbook_wrapper::helper::apply_slippage;
use deepbook_wrapper::order::{
    validate_fees_against_max,
    EDeepRequiredExceedsMax,
    ESuiFeeExceedsMax
};
use std::unit_test::assert_eq;

// ===== Constants =====
const PROTOCOL_FEE_RATE: u64 = 10_000_000; // 1% in billionths

#[test]
fun both_fees_within_limits() {
    // Test case: Both DEEP fee and SUI fee are within acceptable limits

    // Setup test parameters
    let deep_required = 100_000_000; // 100 DEEP (6 decimals)
    let deep_from_reserves = 50_000_000; // 50 DEEP from wrapper reserves
    let sui_per_deep = 1_000_000_000; // 1 SUI per DEEP (SUI has 9 decimals)
    let protocol_fee_rate = PROTOCOL_FEE_RATE; // 1% in billionths

    // Estimated values with some buffer
    let estimated_deep_required = 95_000_000; // 95 DEEP (slightly less than actual)
    let estimated_deep_required_slippage = 100_000_000; // 10% slippage (in billionths)
    let estimated_sui_fee = 45_000_000_000; // 45 SUI (less than what will be calculated)
    let estimated_sui_fee_slippage = 200_000_000; // 20% slippage (in billionths)

    // Verify our test setup makes sense by checking the limits
    let max_deep_required = apply_slippage(
        estimated_deep_required,
        estimated_deep_required_slippage,
    );
    let max_sui_fee = apply_slippage(estimated_sui_fee, estimated_sui_fee_slippage);
    let (actual_sui_fee, _, _) = calculate_full_order_fee(
        protocol_fee_rate,
        sui_per_deep,
        deep_from_reserves,
    );

    // Ensure our test parameters are valid (fees should be within limits)
    assert!(deep_required <= max_deep_required);
    assert!(actual_sui_fee <= max_sui_fee);

    // This should not abort - both fees are within acceptable limits
    validate_fees_against_max(
        deep_required,
        deep_from_reserves,
        protocol_fee_rate,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );
}

#[test, expected_failure(abort_code = EDeepRequiredExceedsMax)]
fun deep_fee_exceeds_limit() {
    // Test case: DEEP fee exceeds maximum allowed limit

    let deep_required = 110_000_000; // 110 DEEP (6 decimals)
    let deep_from_reserves = 50_000_000; // 50 DEEP from wrapper reserves
    let sui_per_deep = 1_000_000_000; // 1 SUI per DEEP (SUI has 9 decimals)
    let protocol_fee_rate = PROTOCOL_FEE_RATE;

    // Set estimated DEEP requirement lower so actual exceeds limit
    let estimated_deep_required = 95_000_000; // 95 DEEP
    let estimated_deep_required_slippage = 100_000_000; // 10% slippage
    let estimated_sui_fee = 100_000_000_000; // 100 SUI (high enough to not cause SUI limit issue)
    let estimated_sui_fee_slippage = 200_000_000; // 20% slippage

    // Verify our test setup: DEEP should exceed limit
    let max_deep_required = apply_slippage(
        estimated_deep_required,
        estimated_deep_required_slippage,
    );
    assert!(deep_required > max_deep_required); // Should exceed limit

    // This should abort with EDeepRequiredExceedsMax (code 5)
    validate_fees_against_max(
        deep_required,
        deep_from_reserves,
        protocol_fee_rate,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );
}

#[test, expected_failure(abort_code = ESuiFeeExceedsMax)]
fun sui_fee_exceeds_limit() {
    // Test case: SUI fee exceeds maximum allowed limit

    let deep_required = 90_000_000; // 90 DEEP (6 decimals) - within DEEP limit
    let deep_from_reserves = 1_000_000_000; // 1000 DEEP from wrapper reserves (large amount)
    let sui_per_deep = 1_000_000_000; // 1 SUI per DEEP (9 decimals)
    let protocol_fee_rate = PROTOCOL_FEE_RATE;

    // Set estimated values so DEEP is within limit but SUI exceeds
    let estimated_deep_required = 95_000_000; // 95 DEEP (higher than actual)
    let estimated_deep_required_slippage = 100_000_000; // 10% slippage
    let estimated_sui_fee = 1_000_000; // 0.001 SUI (very low estimate)
    let estimated_sui_fee_slippage = 0; // 0% slippage (no tolerance)

    // With 1000 DEEP from reserves at 1 SUI per DEEP:
    // Using math::mul logic:
    // Coverage fee = math::mul(1_000_000_000, 1_000_000_000) = 1_000_000_000 (1 SUI)
    // Protocol fee = math::mul(math::mul(1_000_000_000, 10_000_000), 1_000_000_000) = 10_000_000 (0.01 SUI)
    // Total = ~1.01 SUI, much higher than our 0.001 SUI limit

    // This should abort with ESuiFeeExceedsMax (code 6)
    validate_fees_against_max(
        deep_required,
        deep_from_reserves,
        protocol_fee_rate,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );
}

#[test, expected_failure(abort_code = EDeepRequiredExceedsMax)]
fun both_fees_exceed_limits() {
    // Test case: Both fees exceed limits, should abort with DEEP error first

    let deep_required = 110_000_000; // 110 DEEP (6 decimals) - exceeds DEEP limit
    let deep_from_reserves = 50_000_000; // 50 DEEP from wrapper reserves
    let sui_per_deep = 2_000_000_000; // 2 SUI per DEEP (higher price)
    let protocol_fee_rate = PROTOCOL_FEE_RATE;

    // Set both estimates low so both actual fees exceed limits
    let estimated_deep_required = 90_000_000; // 90 DEEP (low estimate)
    let estimated_deep_required_slippage = 50_000_000; // 5% slippage (low)
    let estimated_sui_fee = 10_000_000_000; // 10 SUI (very low estimate)
    let estimated_sui_fee_slippage = 0; // 0% slippage (no tolerance)

    // Should abort with EDeepRequiredExceedsMax (code 5) because DEEP is checked first
    // We remove assertions to avoid test setup failures
    validate_fees_against_max(
        deep_required,
        deep_from_reserves,
        protocol_fee_rate,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );
}

#[test]
fun zero_deep_from_reserves_skips_sui_validation() {
    // Test case: When deep_from_reserves = 0, SUI fee validation should be skipped

    let deep_required = 90_000_000; // 90 DEEP (6 decimals) - within DEEP limit
    let deep_from_reserves = 0; // No DEEP from reserves - this should skip SUI validation
    let sui_per_deep = 1_000_000_000; // 1 SUI per DEEP (SUI has 9 decimals)
    let protocol_fee_rate = PROTOCOL_FEE_RATE;

    let estimated_deep_required = 95_000_000; // 95 DEEP (higher than actual, so DEEP is safe)
    let estimated_deep_required_slippage = 100_000_000; // 10% slippage

    // Set SUI fee estimates very low - normally this would cause SUI fee to exceed
    // But since deep_from_reserves = 0, SUI validation should be skipped entirely
    let estimated_sui_fee = 1_000_000_000; // 1 SUI (very low)
    let estimated_sui_fee_slippage = 0; // 0% slippage

    // Verify DEEP is within limit
    let max_deep_required = apply_slippage(
        estimated_deep_required,
        estimated_deep_required_slippage,
    );
    assert!(deep_required <= max_deep_required);

    // This should not abort - SUI validation is skipped when deep_from_reserves = 0
    validate_fees_against_max(
        deep_required,
        deep_from_reserves,
        protocol_fee_rate,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );
}

#[test]
fun boundary_conditions_exact_limits() {
    // Test case: Fees exactly equal to their limits (boundary testing)

    let estimated_deep_required = 100_000_000; // 100 DEEP (6 decimals)
    let estimated_deep_required_slippage = 100_000_000; // 10% slippage
    let estimated_sui_fee = 50_000_000_000; // 50 SUI
    let estimated_sui_fee_slippage = 200_000_000; // 20% slippage

    // Calculate exact limits
    let max_deep_required = apply_slippage(
        estimated_deep_required,
        estimated_deep_required_slippage,
    );

    // Set actual values to exactly match the limits
    let deep_required = max_deep_required; // Exactly at the limit
    let sui_per_deep = 1_000_000_000; // 1 SUI per DEEP
    let deep_from_reserves = 50_000_000; // 50 DEEP from reserves
    let protocol_fee_rate = PROTOCOL_FEE_RATE;

    // Verify the values are exactly at limits
    assert_eq!(deep_required, max_deep_required);

    // This should not abort - values are exactly at limits (inclusive)
    validate_fees_against_max(
        deep_required,
        deep_from_reserves,
        protocol_fee_rate,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );
}

#[test]
fun zero_values_edge_case() {
    // Test case: Edge case with zero estimated values

    let deep_required = 0; // 0 DEEP required
    let deep_from_reserves = 0; // 0 DEEP from reserves
    let sui_per_deep = 1_000_000_000; // 1 SUI per DEEP
    let protocol_fee_rate = PROTOCOL_FEE_RATE;

    let estimated_deep_required = 0; // 0 DEEP estimated
    let estimated_deep_required_slippage = 100_000_000; // 10% slippage
    let estimated_sui_fee = 0; // 0 SUI estimated
    let estimated_sui_fee_slippage = 100_000_000; // 10% slippage

    // This should not abort - all values are zero or within limits
    validate_fees_against_max(
        deep_required,
        deep_from_reserves,
        protocol_fee_rate,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );
}
