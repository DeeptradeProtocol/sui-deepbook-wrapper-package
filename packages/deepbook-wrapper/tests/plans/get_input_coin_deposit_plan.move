#[test_only]
module deepbook_wrapper::get_input_coin_deposit_plan_tests;

use deepbook_wrapper::order::{get_input_coin_deposit_plan, assert_input_coin_deposit_plan_eq};

// ===== Constants =====

// Token amounts
const AMOUNT_TINY: u64 = 10; // 10
const AMOUNT_SMALL: u64 = 1_000; // 1,000
const AMOUNT_MEDIUM: u64 = 1_000_000; // 1 million
const AMOUNT_HUGE: u64 = 1_000_000_000_000; // 1 trillion

// ===== Sufficient Balance Manager Tests =====

#[test]
public fun test_balance_manager_has_exact_required_amount() {
    let required_amount = AMOUNT_MEDIUM;
    let wallet_balance = AMOUNT_SMALL;
    let balance_manager_balance = required_amount; // Exact required amount

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Balance manager has exact amount needed, no need for wallet
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        0, // take_from_wallet (nothing needed)
        true, // has_sufficient_resources
    );
}

#[test]
public fun test_balance_manager_has_more_than_required() {
    let required_amount = AMOUNT_MEDIUM;
    let wallet_balance = AMOUNT_SMALL;
    let balance_manager_balance = required_amount * 2; // Double the required amount

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Balance manager has more than enough, no need for wallet
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        0, // take_from_wallet (nothing needed)
        true, // has_sufficient_resources
    );
}

#[test]
public fun test_balance_manager_has_enough_empty_wallet() {
    let required_amount = AMOUNT_MEDIUM;
    let wallet_balance = 0; // Empty wallet
    let balance_manager_balance = required_amount + 100; // More than required

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Balance manager is sufficient even with empty wallet
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        0, // take_from_wallet (nothing needed)
        true, // has_sufficient_resources
    );
}

// ===== Partial Balance Manager Tests =====

#[test]
public fun test_balance_manager_partial_wallet_sufficient() {
    let required_amount = AMOUNT_MEDIUM;
    let balance_manager_balance = required_amount / 2; // Half of required
    let additional_needed = required_amount - balance_manager_balance;
    let wallet_balance = additional_needed * 2; // More than enough in wallet

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Should take the additional needed amount from wallet
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        additional_needed, // take_from_wallet
        true, // has_sufficient_resources
    );
}

#[test]
public fun test_balance_manager_partial_wallet_exact_match() {
    let required_amount = AMOUNT_MEDIUM;
    let balance_manager_balance = required_amount / 4; // 25% of required
    let additional_needed = required_amount - balance_manager_balance;
    let wallet_balance = additional_needed; // Exact match for additional needed

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Should take exactly what's needed from wallet
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        additional_needed, // take_from_wallet
        true, // has_sufficient_resources
    );
}

#[test]
public fun test_balance_manager_almost_sufficient() {
    let required_amount = AMOUNT_MEDIUM;
    let balance_manager_balance = required_amount - 1; // Just 1 token short
    let additional_needed = 1; // Need just 1 more token
    let wallet_balance = 10; // More than enough in wallet

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Should take just 1 token from wallet
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        additional_needed, // take_from_wallet
        true, // has_sufficient_resources
    );
}

// ===== Insufficient Resources Tests =====

#[test]
public fun test_balance_manager_partial_wallet_insufficient() {
    let required_amount = AMOUNT_MEDIUM;
    let balance_manager_balance = required_amount / 2; // Half of required
    let additional_needed = required_amount - balance_manager_balance;
    let wallet_balance = additional_needed / 2; // Only half of additional needed

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Not enough in wallet to cover the difference, so take_from_wallet should be 0
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        0, // take_from_wallet (not enough, so 0)
        false, // has_sufficient_resources
    );
}

#[test]
public fun test_balance_manager_empty_wallet_insufficient() {
    let required_amount = AMOUNT_MEDIUM;
    let balance_manager_balance = required_amount / 2; // Half of required
    let wallet_balance = 0; // Empty wallet

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Empty wallet can't cover the difference
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        0, // take_from_wallet (nothing available)
        false, // has_sufficient_resources
    );
}

#[test]
public fun test_wallet_one_token_short() {
    let required_amount = AMOUNT_MEDIUM;
    let balance_manager_balance = required_amount / 2; // Half of required
    let additional_needed = required_amount - balance_manager_balance;
    let wallet_balance = additional_needed - 1; // One token short

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // One token short in wallet, so take_from_wallet should be 0
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        0, // take_from_wallet (not enough, so 0)
        false, // has_sufficient_resources
    );
}

#[test]
public fun test_both_sources_empty() {
    let required_amount = AMOUNT_MEDIUM;
    let balance_manager_balance = 0; // Empty balance manager
    let wallet_balance = 0; // Empty wallet

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Nothing available from either source
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        0, // take_from_wallet
        false, // has_sufficient_resources
    );
}

// ===== Edge Cases =====

#[test]
public fun test_zero_required_amount() {
    let required_amount = 0; // Zero required
    let balance_manager_balance = 0; // Empty balance manager
    let wallet_balance = 0; // Empty wallet

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Zero required amount should be sufficient regardless of balances
    assert_input_coin_deposit_plan_eq(
        plan,
        0, // amount_needed (zero)
        0, // take_from_wallet (nothing needed)
        true, // has_sufficient_resources
    );
}

#[test]
public fun test_huge_required_amount() {
    let required_amount = AMOUNT_HUGE; // Very large amount
    let balance_manager_balance = AMOUNT_HUGE / 2; // Half of huge amount
    let wallet_balance = AMOUNT_HUGE - balance_manager_balance; // Exactly what's needed

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Large values should work correctly
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        required_amount - balance_manager_balance, // take_from_wallet
        true, // has_sufficient_resources
    );
}

#[test]
public fun test_huge_required_amount_insufficient() {
    let required_amount = AMOUNT_HUGE; // Very large amount
    let balance_manager_balance = AMOUNT_HUGE / 2; // Half of huge amount
    let wallet_balance = (AMOUNT_HUGE / 2) - 1; // Just 1 token short

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Just 1 token short for a huge amount
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        0, // take_from_wallet (not enough, so 0)
        false, // has_sufficient_resources
    );
}

#[test]
public fun test_balance_manager_empty_wallet_just_enough() {
    let required_amount = AMOUNT_MEDIUM;
    let balance_manager_balance = 0; // Empty balance manager
    let wallet_balance = required_amount; // Exact amount in wallet

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Wallet has exactly what's needed
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        required_amount, // take_from_wallet (all from wallet)
        true, // has_sufficient_resources
    );
}

#[test]
public fun test_small_values() {
    let required_amount = AMOUNT_TINY; // Small amount
    let balance_manager_balance = AMOUNT_TINY / 2; // Half of tiny amount
    let wallet_balance = AMOUNT_TINY / 2; // Other half in wallet

    let plan = get_input_coin_deposit_plan(
        required_amount,
        wallet_balance,
        balance_manager_balance,
    );

    // Small values should work correctly
    assert_input_coin_deposit_plan_eq(
        plan,
        required_amount, // amount_needed
        required_amount - balance_manager_balance, // take_from_wallet
        true, // has_sufficient_resources
    );
}
