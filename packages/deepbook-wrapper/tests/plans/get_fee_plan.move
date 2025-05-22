#[test_only]
module deepbook_wrapper::get_fee_plan_tests;

use deepbook_wrapper::fee::{calculate_protocol_fee, calculate_deep_reserves_coverage_order_fee};
use deepbook_wrapper::order::{get_fee_plan, assert_fee_plan_eq};
use std::unit_test::assert_eq;

// ===== Constants =====
// SUI per DEEP
const SUI_PER_DEEP: u64 = 37_815_000_000;

// ===== No Fee Required Tests =====

#[test]
public fun whitelisted_pool_requires_no_fee() {
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

    // Whitelisted pools should have no fees regardless of other parameters
    assert_fee_plan_eq(
        plan,
        0, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        0, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

#[test]
public fun not_using_wrapper_deep_requires_no_fee() {
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

    // Not using wrapper DEEP should have no fees regardless of other parameters
    assert_fee_plan_eq(
        plan,
        0, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        0, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

// ===== Fee Distribution Tests =====

#[test]
public fun fee_from_wallet_only() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 25_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    let sui_in_wallet = total_fee * 2; // Plenty in wallet
    let balance_manager_sui = 0; // Nothing in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // All fees should be taken from wallet since BM is empty
    assert_fee_plan_eq(
        plan,
        coverage_fee, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        protocol_fee, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

#[test]
public fun fee_from_balance_manager_only() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 75_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    let sui_in_wallet = 0; // Nothing in wallet
    let balance_manager_sui = total_fee * 2; // Plenty in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // All fees should be taken from balance manager since wallet is empty
    assert_fee_plan_eq(
        plan,
        0, // coverage_fee_from_wallet
        coverage_fee, // coverage_fee_from_balance_manager
        0, // protocol_fee_from_wallet
        protocol_fee, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

#[test]
public fun fee_split_between_wallet_and_balance_manager() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 40_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    // Put 2/3 in BM, 1/3 in wallet
    let balance_manager_sui = (total_fee * 2) / 3;
    let sui_in_wallet = total_fee - balance_manager_sui;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Coverage fee is taken first from BM
    let coverage_from_bm = if (balance_manager_sui >= coverage_fee) {
        coverage_fee
    } else {
        balance_manager_sui
    };
    let coverage_from_wallet = coverage_fee - coverage_from_bm;

    // Protocol fee is taken from remaining BM funds, then wallet
    let remaining_bm = balance_manager_sui - coverage_from_bm;
    let protocol_from_bm = if (remaining_bm >= protocol_fee) {
        protocol_fee
    } else {
        remaining_bm
    };
    let protocol_from_wallet = protocol_fee - protocol_from_bm;

    // Verify fee distribution
    assert_fee_plan_eq(
        plan,
        coverage_from_wallet, // coverage_fee_from_wallet
        coverage_from_bm, // coverage_fee_from_balance_manager
        protocol_from_wallet, // protocol_fee_from_wallet
        protocol_from_bm, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

// ===== Insufficient Resources Tests =====

#[test]
public fun insufficient_fee_resources() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 60_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    // Total available is 50% of required fee
    let sui_in_wallet = total_fee / 4; // 25% in wallet
    let balance_manager_sui = total_fee / 4; // 25% in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_fee_plan_eq(
        plan,
        0, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        0, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        false, // user_covers_wrapper_fee
    );
}

#[test]
public fun almost_sufficient_fee_resources() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 35_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    // Total available is 1 less than required fee
    let sui_in_wallet = total_fee / 2; // 50% in wallet
    let balance_manager_sui = (total_fee / 2) - 1; // Almost 50% in balance manager (1 short)

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_fee_plan_eq(
        plan,
        0, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        0, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        false, // user_covers_wrapper_fee
    );
}

// ===== Boundary Tests =====

#[test]
public fun exact_fee_match_with_wallet() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 50_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    let sui_in_wallet = total_fee; // Exact match
    let balance_manager_sui = 0; // Nothing in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // All fees should be taken from wallet since BM is empty
    assert_fee_plan_eq(
        plan,
        coverage_fee, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        protocol_fee, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

#[test]
public fun exact_fee_match_with_balance_manager() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 20_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    let sui_in_wallet = 0; // Nothing in wallet
    let balance_manager_sui = total_fee; // Exact match

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // All fees should be taken from balance manager since wallet is empty
    assert_fee_plan_eq(
        plan,
        0, // coverage_fee_from_wallet
        coverage_fee, // coverage_fee_from_balance_manager
        0, // protocol_fee_from_wallet
        protocol_fee, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

#[test]
public fun exact_fee_match_combined() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 80_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    // Put half in each source
    let balance_manager_sui = total_fee / 2;
    let sui_in_wallet = total_fee - balance_manager_sui;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Coverage fee should be taken from BM first
    let coverage_from_bm = if (balance_manager_sui >= coverage_fee) {
        coverage_fee
    } else {
        balance_manager_sui
    };
    let coverage_from_wallet = coverage_fee - coverage_from_bm;

    // Protocol fee should be taken from remaining BM funds, then wallet
    let remaining_bm = balance_manager_sui - coverage_from_bm;
    let protocol_from_bm = if (remaining_bm >= protocol_fee) {
        protocol_fee
    } else {
        remaining_bm
    };
    let protocol_from_wallet = protocol_fee - protocol_from_bm;

    // Verify fee distribution
    assert_fee_plan_eq(
        plan,
        coverage_from_wallet, // coverage_fee_from_wallet
        coverage_from_bm, // coverage_fee_from_balance_manager
        protocol_from_wallet, // protocol_fee_from_wallet
        protocol_from_bm, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

// ===== Edge Cases =====

#[test]
public fun large_deep_reserves_fee() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 1_000_000_000; // Large amount of DEEP
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    // Put 75% in BM, 25% in wallet
    let balance_manager_sui = (total_fee * 3) / 4;
    let sui_in_wallet = total_fee - balance_manager_sui;

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Coverage fee should be taken from BM first
    let coverage_from_bm = if (balance_manager_sui >= coverage_fee) {
        coverage_fee
    } else {
        balance_manager_sui
    };
    let coverage_from_wallet = coverage_fee - coverage_from_bm;

    // Protocol fee should be taken from remaining BM funds, then wallet
    let remaining_bm = balance_manager_sui - coverage_from_bm;
    let protocol_from_bm = if (remaining_bm >= protocol_fee) {
        protocol_fee
    } else {
        remaining_bm
    };
    let protocol_from_wallet = protocol_fee - protocol_from_bm;

    // Verify fee distribution
    assert_fee_plan_eq(
        plan,
        coverage_from_wallet, // coverage_fee_from_wallet
        coverage_from_bm, // coverage_fee_from_balance_manager
        protocol_from_wallet, // protocol_fee_from_wallet
        protocol_from_bm, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

#[test]
public fun minimal_deep_reserves_fee() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 1; // Minimal amount of DEEP
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    // Ensure we have enough balance to cover even minimal fee
    let sui_in_wallet = total_fee;
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
    assert!(total_fee > 0);

    // All fees should be taken from wallet since BM is empty
    assert_fee_plan_eq(
        plan,
        coverage_fee, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        protocol_fee, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        true, // user_covers_wrapper_fee
    );
}

#[test]
public fun wallet_exactly_one_token_short() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 15_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    let sui_in_wallet = total_fee - 1; // 1 SUI short
    let balance_manager_sui = 0; // Nothing in balance manager

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_fee_plan_eq(
        plan,
        0, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        0, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        false, // user_covers_wrapper_fee
    );
}

#[test]
public fun balance_manager_exactly_one_token_short_with_empty_wallet() {
    let is_pool_whitelisted = false;
    let use_wrapper_deep_reserves = true;
    let deep_from_reserves = 45_000;
    let sui_per_deep = SUI_PER_DEEP;

    // Calculate both fees in SUI
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );
    let protocol_fee = calculate_protocol_fee(sui_per_deep, deep_from_reserves);
    let total_fee = coverage_fee + protocol_fee;

    let sui_in_wallet = 0; // Empty wallet
    let balance_manager_sui = total_fee - 1; // 1 SUI short

    let plan = get_fee_plan(
        use_wrapper_deep_reserves,
        deep_from_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_fee_plan_eq(
        plan,
        0, // coverage_fee_from_wallet
        0, // coverage_fee_from_balance_manager
        0, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        false, // user_covers_wrapper_fee
    );
}

// ===== Protocol Fee Specific Tests =====

#[test]
public fun fee_scaling_with_deep_amount() {
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
    assert_eq!(fee_0, 0); // No fee with 0 DEEP
    assert!(fee_25k > 0); // Some fee with 25k DEEP
    assert!(fee_50k > fee_25k); // Higher fee with 50k DEEP
    assert!(fee_75k > fee_50k); // Higher fee with 75k DEEP

    // Verify approximately linear scaling
    let ratio_50_25 = (fee_50k as u128) * 100 / (fee_25k as u128);
    let ratio_75_25 = (fee_75k as u128) * 100 / (fee_25k as u128);

    assert!(ratio_50_25 >= 195 && ratio_50_25 <= 205); // ~200%
    assert!(ratio_75_25 >= 295 && ratio_75_25 <= 305); // ~300%
}
