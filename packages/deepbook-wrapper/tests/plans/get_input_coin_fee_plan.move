#[test_only]
module deepbook_wrapper::get_input_coin_fee_plan_tests;

use deepbook_wrapper::fee::calculate_input_coin_protocol_fee;
use deepbook_wrapper::order::{get_input_coin_fee_plan, assert_input_coin_fee_plan_eq};

// ===== Constants =====
const TAKER_FEE_RATE: u64 = 1_000_000; // 0.1% in billionths

// ===== No Fee Required Tests =====

#[test]
public fun test_whitelisted_pool_requires_no_fee() {
    let is_pool_whitelisted = true;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 1_000_000;
    let coin_in_wallet = 1000;
    let balance_manager_coin = 1000;

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // Whitelisted pools should have no fees regardless of other parameters
    assert_input_coin_fee_plan_eq(
        plan,
        0, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        true // user_covers_wrapper_fee
    );
}

// ===== Fee Distribution Tests =====

#[test]
public fun test_fee_from_wallet_only() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 1_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    let coin_in_wallet = protocol_fee * 2; // Plenty in wallet
    let balance_manager_coin = 0; // Nothing in balance manager

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // All fees should be taken from wallet since BM is empty
    assert_input_coin_fee_plan_eq(
        plan,
        protocol_fee, // protocol_fee_from_wallet
        0,           // protocol_fee_from_balance_manager
        true         // user_covers_wrapper_fee
    );
}

#[test]
public fun test_fee_from_balance_manager_only() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 2_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    let coin_in_wallet = 0; // Nothing in wallet
    let balance_manager_coin = protocol_fee * 2; // Plenty in balance manager

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // All fees should be taken from balance manager since wallet is empty
    assert_input_coin_fee_plan_eq(
        plan,
        0,            // protocol_fee_from_wallet
        protocol_fee, // protocol_fee_from_balance_manager
        true         // user_covers_wrapper_fee
    );
}

#[test]
public fun test_fee_split_between_wallet_and_balance_manager() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 3_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    // Put 2/3 in BM, 1/3 in wallet
    let balance_manager_coin = (protocol_fee * 2) / 3;
    let coin_in_wallet = protocol_fee - balance_manager_coin;

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // Protocol fee should be taken from BM first, then wallet
    let fee_from_bm = balance_manager_coin;
    let fee_from_wallet = protocol_fee - fee_from_bm;

    // Verify fee distribution
    assert_input_coin_fee_plan_eq(
        plan,
        fee_from_wallet, // protocol_fee_from_wallet
        fee_from_bm,    // protocol_fee_from_balance_manager
        true           // user_covers_wrapper_fee
    );
}

// ===== Insufficient Resources Tests =====

#[test]
public fun test_insufficient_fee_resources() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 1_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    // Total available is 50% of required fee
    let coin_in_wallet = protocol_fee / 4;      // 25% in wallet
    let balance_manager_coin = protocol_fee / 4; // 25% in balance manager

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_input_coin_fee_plan_eq(
        plan,
        0,     // protocol_fee_from_wallet
        0,     // protocol_fee_from_balance_manager
        false  // user_covers_wrapper_fee
    );
}

#[test]
public fun test_almost_sufficient_fee_resources() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 2_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    // Total available is 1 less than required fee
    let coin_in_wallet = protocol_fee / 2;                  // 50% in wallet
    let balance_manager_coin = (protocol_fee / 2) - 1;      // Almost 50% in balance manager (1 short)

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_input_coin_fee_plan_eq(
        plan,
        0,     // protocol_fee_from_wallet
        0,     // protocol_fee_from_balance_manager
        false  // user_covers_wrapper_fee
    );
}

// ===== Boundary Tests =====

#[test]
public fun test_exact_fee_match_with_wallet() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 1_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    let coin_in_wallet = protocol_fee; // Exact match
    let balance_manager_coin = 0;      // Nothing in balance manager

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // All fees should be taken from wallet since BM is empty
    assert_input_coin_fee_plan_eq(
        plan,
        protocol_fee, // protocol_fee_from_wallet
        0,           // protocol_fee_from_balance_manager
        true         // user_covers_wrapper_fee
    );
}

#[test]
public fun test_exact_fee_match_with_balance_manager() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 2_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    let coin_in_wallet = 0;              // Nothing in wallet
    let balance_manager_coin = protocol_fee; // Exact match

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // All fees should be taken from balance manager since wallet is empty
    assert_input_coin_fee_plan_eq(
        plan,
        0,            // protocol_fee_from_wallet
        protocol_fee, // protocol_fee_from_balance_manager
        true         // user_covers_wrapper_fee
    );
}

#[test]
public fun test_exact_fee_match_combined() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 3_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    // Put half in each source
    let balance_manager_coin = protocol_fee / 2;
    let coin_in_wallet = protocol_fee - balance_manager_coin;

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // Protocol fee should be taken from BM first, then wallet
    let fee_from_bm = balance_manager_coin;
    let fee_from_wallet = protocol_fee - fee_from_bm;

    // Verify fee distribution
    assert_input_coin_fee_plan_eq(
        plan,
        fee_from_wallet, // protocol_fee_from_wallet
        fee_from_bm,    // protocol_fee_from_balance_manager
        true           // user_covers_wrapper_fee
    );
}

// ===== Edge Cases =====

#[test]
public fun test_large_order_amount() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 1_000_000_000_000; // Very large order amount

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    // Put 75% in BM, 25% in wallet
    let balance_manager_coin = (protocol_fee * 3) / 4;
    let coin_in_wallet = protocol_fee - balance_manager_coin;

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // Protocol fee should be taken from BM first, then wallet
    let fee_from_bm = balance_manager_coin;
    let fee_from_wallet = protocol_fee - fee_from_bm;

    // Verify fee distribution
    assert_input_coin_fee_plan_eq(
        plan,
        fee_from_wallet, // protocol_fee_from_wallet
        fee_from_bm,    // protocol_fee_from_balance_manager
        true           // user_covers_wrapper_fee
    );
}

#[test]
public fun test_minimal_order_amount() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 1; // Minimal order amount

    // Calculate protocol fee
    // For minimal amounts, fee might be 0 due to integer division
    // (e.g., 1 * 0.1% = 0.001 which rounds to 0)
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    // With minimal amount, protocol fee should be 0
    assert!(protocol_fee == 0, 0);

    // Even with zero fee, we should get a valid plan
    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        0, // No coins needed since fee is 0
        0, // No coins needed since fee is 0
    );

    // Plan should indicate success since no fee is needed
    assert_input_coin_fee_plan_eq(
        plan,
        0, // protocol_fee_from_wallet
        0, // protocol_fee_from_balance_manager
        true // user_covers_wrapper_fee (true because no fee needed)
    );
}

#[test]
public fun test_wallet_exactly_one_token_short() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 1_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    let coin_in_wallet = protocol_fee - 1; // 1 token short
    let balance_manager_coin = 0;          // Nothing in balance manager

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_input_coin_fee_plan_eq(
        plan,
        0,     // protocol_fee_from_wallet
        0,     // protocol_fee_from_balance_manager
        false  // user_covers_wrapper_fee
    );
}

#[test]
public fun test_balance_manager_exactly_one_token_short_with_empty_wallet() {
    let is_pool_whitelisted = false;
    let taker_fee = TAKER_FEE_RATE;
    let amount = 2_000_000;

    // Calculate protocol fee
    let protocol_fee = calculate_input_coin_protocol_fee(amount, taker_fee);

    let coin_in_wallet = 0;                 // Empty wallet
    let balance_manager_coin = protocol_fee - 1; // 1 token short

    let plan = get_input_coin_fee_plan(
        is_pool_whitelisted,
        taker_fee,
        amount,
        coin_in_wallet,
        balance_manager_coin,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_input_coin_fee_plan_eq(
        plan,
        0,     // protocol_fee_from_wallet
        0,     // protocol_fee_from_balance_manager
        false  // user_covers_wrapper_fee
    );
}

// ===== Fee Scaling Tests =====

#[test]
public fun test_fee_scaling_with_amount() {
    let taker_fee = TAKER_FEE_RATE;

    // Test with increasing amounts
    let fee_0 = calculate_input_coin_protocol_fee(0, taker_fee);
    let fee_1m = calculate_input_coin_protocol_fee(1_000_000, taker_fee);
    let fee_2m = calculate_input_coin_protocol_fee(2_000_000, taker_fee);
    let fee_3m = calculate_input_coin_protocol_fee(3_000_000, taker_fee);

    // Verify fee scaling
    assert!(fee_0 == 0, 0); // No fee with 0 amount
    assert!(fee_1m > 0, 0); // Some fee with 1M amount
    assert!(fee_2m > fee_1m, 0); // Higher fee with 2M amount
    assert!(fee_3m > fee_2m, 0); // Higher fee with 3M amount

    // Verify approximately linear scaling
    let ratio_2m_1m = (fee_2m as u128) * 100 / (fee_1m as u128);
    let ratio_3m_1m = (fee_3m as u128) * 100 / (fee_1m as u128);

    assert!(ratio_2m_1m >= 195 && ratio_2m_1m <= 205, 0); // ~200%
    assert!(ratio_3m_1m >= 295 && ratio_3m_1m <= 305, 0); // ~300%
}

#[test]
public fun test_fee_scaling_with_taker_fee_rate() {
    let amount = 1_000_000;

    // Test with increasing taker fee rates
    let fee_0 = calculate_input_coin_protocol_fee(amount, 0);
    let fee_1m = calculate_input_coin_protocol_fee(amount, 1_000_000);   // 0.1%
    let fee_2m = calculate_input_coin_protocol_fee(amount, 2_000_000);   // 0.2%
    let fee_3m = calculate_input_coin_protocol_fee(amount, 3_000_000);   // 0.3%

    // Verify fee scaling
    assert!(fee_0 == 0, 0); // No fee with 0 rate
    assert!(fee_1m > 0, 0); // Some fee with 0.1% rate
    assert!(fee_2m > fee_1m, 0); // Higher fee with 0.2% rate
    assert!(fee_3m > fee_2m, 0); // Higher fee with 0.3% rate

    // Verify approximately linear scaling
    let ratio_2m_1m = (fee_2m as u128) * 100 / (fee_1m as u128);
    let ratio_3m_1m = (fee_3m as u128) * 100 / (fee_1m as u128);

    assert!(ratio_2m_1m >= 195 && ratio_2m_1m <= 205, 0); // ~200%
    assert!(ratio_3m_1m >= 295 && ratio_3m_1m <= 305, 0); // ~300%
} 