#[test_only]
module deepbook_wrapper::get_fee_plan_tests;

use deepbook_wrapper::fee::{calculate_protocol_fee, calculate_deep_reserves_coverage_order_fee};
use deepbook_wrapper::order::{get_fee_plan, assert_fee_plan_eq};

// ===== Constants =====
// SUI per DEEP
const SUI_PER_DEEP: u64 = 37_815_000_000;

// ===== No Fee Required Tests =====

#[test]
public fun test_whitelisted_pool_requires_no_fee() {
    let is_pool_whitelisted = true;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 100;
    let sui_per_deep = SUI_PER_DEEP;
    let sui_in_wallet = 1000;
    let balance_manager_sui = 1000;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Whitelisted pools should have no fee regardless of other factors
    assert_fee_plan_eq(
        plan,
        0, // fee_amount = 0
        0, // from_user_wallet = 0
        0, // from_user_balance_manager = 0
        true, // user_covers_wrapper_fee = true
    );
}

#[test]
public fun test_not_using_wrapper_deep_requires_no_fee() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = false; // Not using wrapper DEEP
    let deep_from_reserves = 0;
    let sui_per_deep = SUI_PER_DEEP;
    let sui_in_wallet = 1000;
    let balance_manager_sui = 1000;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Not using wrapper DEEP should have no fee
    assert_fee_plan_eq(
        plan,
        0, // fee_amount = 0
        0, // from_user_wallet = 0
        0, // from_user_balance_manager = 0
        true, // user_covers_wrapper_fee = true
    );
}

// ===== Fee Distribution Tests =====

#[test]
public fun test_fee_from_wallet_only() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 25_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let sui_in_wallet = expected_fee * 2; // Plenty in wallet
    let balance_manager_sui = 0; // Nothing in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Fee should be entirely taken from wallet
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = deep coverage fee + protocol fee
        expected_fee, // from_user_wallet = all fee
        0, // from_user_balance_manager = 0
        true, // user_covers_wrapper_fee = true
    );
}

#[test]
public fun test_fee_from_balance_manager_only() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 75_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let sui_in_wallet = 0; // Nothing in wallet
    let balance_manager_sui = expected_fee * 2; // Plenty in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Fee should be entirely taken from balance manager
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = deep coverage fee + protocol fee
        0, // from_user_wallet = 0
        expected_fee, // from_user_balance_manager = all fee
        true, // user_covers_wrapper_fee = true
    );
}

#[test]
public fun test_fee_split_between_wallet_and_balance_manager() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 40_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let wallet_part = expected_fee / 3; // 1/3 in wallet
    let balance_manager_part = expected_fee - wallet_part; // 2/3 in balance manager

    let sui_in_wallet = wallet_part;
    let balance_manager_sui = balance_manager_part;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Fee should be split between wallet and balance manager
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = deep coverage fee + protocol fee
        wallet_part, // from_user_wallet = wallet_part
        balance_manager_part, // from_user_balance_manager = balance_manager_part
        true, // user_covers_wrapper_fee = true
    );
}

// ===== Insufficient Resources Tests =====

#[test]
public fun test_insufficient_fee_resources() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 60_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let sui_in_wallet = expected_fee / 4; // 25% in wallet
    let balance_manager_sui = expected_fee / 4; // 25% in balance manager
    // Total available is 50% of required fee

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Should indicate insufficient resources
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total calculated fee
        0, // from_user_wallet = 0 (insufficient resources)
        0, // from_user_balance_manager = 0 (insufficient resources)
        false, // user_covers_wrapper_fee = false
    );
}

#[test]
public fun test_almost_sufficient_fee_resources() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 35_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let sui_in_wallet = expected_fee / 2; // 50% in wallet
    let balance_manager_sui = (expected_fee / 2) - 1; // Almost 50% in balance manager (1 short)
    // Total available is 1 less than required fee

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Should indicate insufficient resources
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total calculated fee
        0, // from_user_wallet = 0 (insufficient resources)
        0, // from_user_balance_manager = 0 (insufficient resources)
        false, // user_covers_wrapper_fee = false
    );
}

// ===== Boundary Tests =====

#[test]
public fun test_exact_fee_match_with_wallet() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 50_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let sui_in_wallet = expected_fee; // Exact match
    let balance_manager_sui = 0; // Nothing in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Fee should be exactly covered by wallet
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total fee in SUI
        expected_fee, // from_user_wallet = exact fee
        0, // from_user_balance_manager = 0
        true, // user_covers_wrapper_fee = true
    );
}

#[test]
public fun test_exact_fee_match_with_balance_manager() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 20_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let sui_in_wallet = 0; // Nothing in wallet
    let balance_manager_sui = expected_fee; // Exact match

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Fee should be exactly covered by balance manager
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total fee in SUI
        0, // from_user_wallet = 0
        expected_fee, // from_user_balance_manager = exact fee
        true, // user_covers_wrapper_fee = true
    );
}

#[test]
public fun test_exact_fee_match_combined() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 80_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let wallet_part = expected_fee / 2; // Half in wallet
    let balance_manager_part = expected_fee - wallet_part; // Rest in balance manager

    let sui_in_wallet = wallet_part;
    let balance_manager_sui = balance_manager_part;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Fee should be exactly covered by combined sources
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total fee in SUI
        wallet_part, // from_user_wallet = wallet part
        balance_manager_part, // from_user_balance_manager = balance manager part
        true, // user_covers_wrapper_fee = true
    );
}

// ===== Edge Cases =====

#[test]
public fun test_large_deep_reserves_fee() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 1_000_000_000; // Large amount of DEEP
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let wallet_part = expected_fee / 4; // 25% in wallet
    let balance_manager_part = expected_fee - wallet_part; // 75% in balance manager

    let sui_in_wallet = wallet_part;
    let balance_manager_sui = balance_manager_part;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Fee should be covered by combined sources
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total fee in SUI
        wallet_part, // from_user_wallet = wallet part
        balance_manager_part, // from_user_balance_manager = balance manager part
        true, // user_covers_wrapper_fee = true
    );
}

#[test]
public fun test_minimal_deep_reserves_fee() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 1; // Minimal amount of DEEP
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    // Ensure we have enough balance to cover even minimal fee
    let sui_in_wallet = expected_fee;
    let balance_manager_sui = 0;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Even minimal DEEP amount should result in some fee
    assert!(expected_fee > 0, 0);

    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total fee in SUI
        expected_fee, // from_user_wallet = all fee
        0, // from_user_balance_manager = 0
        true, // user_covers_wrapper_fee = true
    );
}

#[test]
public fun test_wallet_exactly_one_token_short() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 15_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let sui_in_wallet = expected_fee - 1; // 1 SUI short
    let balance_manager_sui = 0; // Nothing in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Not enough resources
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total calculated fee
        0, // from_user_wallet = 0 (insufficient resources)
        0, // from_user_balance_manager = 0 (insufficient resources)
        false, // user_covers_wrapper_fee = false
    );
}

#[test]
public fun test_balance_manager_exactly_one_token_short_with_empty_wallet() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 45_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let expected_fee = deep_coverage_fee + protocol_fee;

    let sui_in_wallet = 0; // Empty wallet
    let balance_manager_sui = expected_fee - 1; // 1 SUI short

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Not enough resources
    assert_fee_plan_eq(
        plan,
        expected_fee, // fee_amount = total calculated fee
        0, // from_user_wallet = 0
        0, // from_user_balance_manager = 0 (not enough in balance manager)
        false, // user_covers_wrapper_fee = false
    );
}

// ===== Protocol Fee Specific Tests =====

#[test]
public fun test_fee_scaling_with_deep_amount() {
    let sui_per_deep = SUI_PER_DEEP;

    // Test with increasing amounts of DEEP from reserves
    let fee_0 =
        calculate_deep_reserves_coverage_order_fee(sui_per_deep, 0) + 
                    calculate_protocol_fee(sui_per_deep, 0);

    let fee_25k =
        calculate_deep_reserves_coverage_order_fee(sui_per_deep, 25_000) + 
                      calculate_protocol_fee(sui_per_deep, 25_000);

    let fee_50k =
        calculate_deep_reserves_coverage_order_fee(sui_per_deep, 50_000) + 
                      calculate_protocol_fee(sui_per_deep, 50_000);

    let fee_75k =
        calculate_deep_reserves_coverage_order_fee(sui_per_deep, 75_000) + 
                      calculate_protocol_fee(sui_per_deep, 75_000);

    // Verify fee scaling
    assert!(fee_0 == 0, 0); // No fee with 0 DEEP
    assert!(fee_25k > 0, 0); // Some fee with 25k DEEP
    assert!(fee_50k > fee_25k, 0); // Higher fee with 50k DEEP
    assert!(fee_75k > fee_50k, 0); // Higher fee with 75k DEEP

    // Verify approximately linear scaling
    let ratio_50_25 = (fee_50k as u128) * 100 / (fee_25k as u128);
    let ratio_75_25 = (fee_75k as u128) * 100 / (fee_25k as u128);

    assert!(ratio_50_25 >= 195 && ratio_50_25 <= 205, 0); // ~200%
    assert!(ratio_75_25 >= 295 && ratio_75_25 <= 305, 0); // ~300%
}
