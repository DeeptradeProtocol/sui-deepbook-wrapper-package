#[test_only]
module deepbook_wrapper::create_input_fee_order_core_tests;

use deepbook_wrapper::fee::{calculate_input_coin_deepbook_fee, calculate_input_coin_protocol_fee};
use deepbook_wrapper::helper::calculate_order_amount;
use deepbook_wrapper::order::{
    create_input_fee_order_core,
    assert_input_coin_fee_plan_eq,
    assert_input_coin_deposit_plan_eq,
    InputCoinFeePlan,
    InputCoinDepositPlan
};

// ===== Constants =====
// Token amounts - using more realistic values
const PRICE_SMALL: u64 = 2_500_000_000_000; // 2.5 (normalized)
const PRICE_MEDIUM: u64 = 15_750_000_000_000; // 15.75 (normalized)
const PRICE_LARGE: u64 = 123_450_000_000_000; // 123.45 (normalized)

const QUANTITY_SMALL: u64 = 500_000_000; // 0.5 tokens
const QUANTITY_MEDIUM: u64 = 2_500_000_000; // 2.5 tokens
const QUANTITY_LARGE: u64 = 10_000_000_000; // 10 tokens

// DeepBook fee rate in billionths
const DEEPBOOK_FEE_RATE: u64 = 1_000_000; // 0.1% DeepBook fee

// ===== Helper Function for Testing =====

/// Helper function to assert both plans match expected values
public fun assert_order_plans_eq(
    fee_plan: InputCoinFeePlan,
    input_coin_deposit_plan: InputCoinDepositPlan,
    // Expected values for InputCoinFeePlan
    expected_protocol_fee_from_wallet: u64,
    expected_protocol_fee_from_balance_manager: u64,
    expected_user_covers_wrapper_fee: bool,
    // Expected values for InputCoinDepositPlan
    expected_order_amount: u64,
    expected_deposit_from_wallet: u64,
    expected_deposit_sufficient: bool,
) {
    // Assert InputCoinFeePlan
    assert_input_coin_fee_plan_eq(
        fee_plan,
        expected_protocol_fee_from_wallet,
        expected_protocol_fee_from_balance_manager,
        expected_user_covers_wrapper_fee,
    );

    // Assert InputCoinDepositPlan
    assert_input_coin_deposit_plan_eq(
        input_coin_deposit_plan,
        expected_order_amount,
        expected_deposit_from_wallet,
        expected_deposit_sufficient,
    );
}

// ===== Tests =====

#[test]
/// Tests successful order creation when:
/// 1. Protocol fee is taken from balance manager
/// 2. After protocol fee deduction, balance manager still has enough for order + DeepBook fee
/// 3. No wallet funds needed
public fun all_from_balance_manager() {
    let quantity = QUANTITY_MEDIUM;
    let price = PRICE_MEDIUM;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balance manager with enough for everything
    let balance_manager_input_coin = total_required_in_bm + protocol_fee;
    let wallet_input_coin = 0;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // protocol fee from wallet
        protocol_fee, // protocol fee from balance manager
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm, // total amount needed in BM
        0, // nothing needed from wallet
        true, // sufficient funds
    );
}

#[test]
/// Tests successful order creation when:
/// 1. Protocol fee is split between wallet and balance manager
/// 2. Remaining balance manager funds aren't enough for order + DeepBook fee
/// 3. Additional funds from wallet are needed to complete the order
public fun split_between_sources() {
    let quantity = QUANTITY_LARGE;
    let price = PRICE_LARGE;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances where both sources are needed
    let balance_manager_input_coin = protocol_fee / 2; // Half of protocol fee
    let wallet_input_coin = total_required_in_bm + (protocol_fee - balance_manager_input_coin);

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    // Protocol fee is split
    let protocol_fee_from_bm = balance_manager_input_coin;
    let protocol_fee_from_wallet = protocol_fee - protocol_fee_from_bm;

    // After protocol fee, everything must come from wallet
    let deposit_from_wallet = total_required_in_bm;

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        protocol_fee_from_wallet,
        protocol_fee_from_bm,
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        deposit_from_wallet,
        true, // sufficient funds
    );
}

#[test]
/// Tests case when:
/// 1. Protocol fee can be paid (from either source)
/// 2. But remaining funds are insufficient for order + DeepBook fee
public fun insufficient_after_protocol_fee() {
    let quantity = QUANTITY_MEDIUM;
    let price = PRICE_LARGE;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances: enough for protocol fee but not for order
    let balance_manager_input_coin = protocol_fee;
    let wallet_input_coin = total_required_in_bm / 2; // Not enough for full order

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // protocol fee from wallet
        protocol_fee, // all protocol fee from balance manager
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        0, // when insufficient, from_user_wallet should be 0
        false, // insufficient funds for order
    );
}

#[test]
/// Tests whitelisted pool scenario where:
/// 1. Pool is whitelisted (DeepBook fee rate is 0)
/// 2. No DeepBook fees are required
/// 3. No protocol fees are required (since they're based on DeepBook fees)
/// 4. Only pure order amount needs to be covered
public fun whitelisted_pool_no_fees() {
    let quantity = QUANTITY_SMALL;
    let price = PRICE_SMALL;
    let is_pool_whitelisted = true;

    // For whitelisted pools, fee rate is 0
    let whitelisted_fee_rate = 0;

    // Calculate order requirements - only order amount is needed
    let order_amount = calculate_order_amount(quantity, price, true);
    let total_required_in_bm = order_amount; // No additional fees needed

    // Set up balances with exact order amount in BM
    let balance_manager_input_coin = order_amount;
    let wallet_input_coin = 0;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        whitelisted_fee_rate,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // no protocol fee from wallet
        0, // no protocol fee from balance manager
        true, // user can cover protocol fee (which is 0)
        // InputCoinDepositPlan expectations
        total_required_in_bm, // just the order amount
        0, // nothing needed from wallet
        true, // sufficient funds
    );
}

#[test]
/// Tests scenario where:
/// 1. Combined funds from both sources are insufficient to cover protocol fee
/// 2. Order creation should be rejected at protocol fee stage
/// 3. No funds should be requested from wallet for deposit
/// 4. Both fee amounts should be set to 0 in the insufficient fee plan
public fun insufficient_protocol_fee() {
    let quantity = QUANTITY_MEDIUM;
    let price = PRICE_LARGE;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances: not enough even for protocol fee
    let balance_manager_input_coin = protocol_fee / 4; // 25% of required protocol fee
    let wallet_input_coin = protocol_fee / 4; // Another 25% of required protocol fee

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // insufficient funds -> no fee from wallet
        0, // insufficient funds -> no fee from balance manager
        false, // user cannot cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        0, // when insufficient protocol fee, no wallet deposit requested
        false, // insufficient funds for order
    );
}

#[test]
/// Tests edge case with minimum amounts where:
/// 1. Very small quantity and price are used
/// 2. Resulting fees are minimal but non-zero
/// 3. Verifies no rounding issues occur with small amounts
/// 4. Verifies balance manager is prioritized for protocol fees
public fun minimum_amounts() {
    let quantity = 10_000;
    let price = 345_000_000;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances with exact amounts needed
    // Balance manager has enough for protocol fee and part of the order
    let balance_manager_input_coin = protocol_fee + (total_required_in_bm / 2);
    // Wallet needs to cover the rest of the order
    let wallet_input_coin = total_required_in_bm - (balance_manager_input_coin - protocol_fee);

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // no protocol fee from wallet (BM prioritized)
        protocol_fee, // all protocol fee from balance manager
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        wallet_input_coin, // deposit remaining needed amount from wallet
        true, // sufficient funds
    );
}

#[test]
/// Tests scenario where:
/// 1. Balance manager has just enough for protocol fee plus tiny extra
/// 2. Tiny extra from BM will be used for order amount
/// 3. Wallet must cover the remaining order amount and DeepBook fee
/// 4. Verifies correct fee source prioritization
public fun bm_only_protocol_fee() {
    let quantity = QUANTITY_MEDIUM;
    let price = PRICE_MEDIUM;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances:
    let bm_extra = 100;
    // BM has exactly protocol fee + tiny extra
    let balance_manager_input_coin = protocol_fee + bm_extra;
    // Wallet needs to cover (total required - remaining BM after protocol fee)
    let wallet_input_coin = total_required_in_bm;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    // After protocol fee is taken from BM, the remaining amount (bm_extra)
    // will be used for the order, reducing what's needed from wallet
    let remaining_bm_after_fee = balance_manager_input_coin - protocol_fee;
    let needed_from_wallet = total_required_in_bm - remaining_bm_after_fee;

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // no protocol fee from wallet (BM has enough)
        protocol_fee, // all protocol fee from balance manager
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        needed_from_wallet, // reduced by the amount remaining in BM after protocol fee
        true, // sufficient funds
    );
}

#[test]
/// Tests scenario where:
/// 1. Balance manager has exactly enough for protocol fee (no extra)
/// 2. Entire order amount must come from wallet
/// 3. Verifies behavior with exact amounts
public fun exact_protocol_fee_balance() {
    let quantity = QUANTITY_MEDIUM;
    let price = PRICE_MEDIUM;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances:
    // BM has exactly protocol fee, not a coin more
    let balance_manager_input_coin = protocol_fee;
    // Wallet needs to cover the entire order amount and DeepBook fee
    let wallet_input_coin = total_required_in_bm;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // no protocol fee from wallet
        protocol_fee, // exact protocol fee from balance manager
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        total_required_in_bm, // need entire amount from wallet as BM is empty after fee
        true, // sufficient funds
    );
}

#[test]
/// Tests scenario with maximum possible values:
/// 1. Uses very large quantity and price values
/// 2. Verifies no overflow in fee calculations
/// 3. Checks handling of large amounts in both BM and wallet
public fun maximum_values() {
    let quantity = QUANTITY_LARGE * 1000;
    let price = PRICE_LARGE;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances with large amounts split between BM and wallet
    let balance_manager_input_coin = total_required_in_bm / 2;
    let wallet_input_coin = total_required_in_bm + protocol_fee;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    // After protocol fee is taken from BM, calculate remaining needed from wallet
    let remaining_bm_after_fee = balance_manager_input_coin - protocol_fee;
    let needed_from_wallet = total_required_in_bm - remaining_bm_after_fee;

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // no protocol fee from wallet
        protocol_fee, // protocol fee from balance manager
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        needed_from_wallet, // remaining amount needed from wallet
        true, // sufficient funds
    );
}

#[test]
/// Tests fee rounding behavior where:
/// 1. Order amount leads to non-integer fee calculations
/// 2. Verifies consistent rounding behavior
/// 3. Checks that rounding doesn't affect plan correctness
public fun fee_rounding() {
    // Using prime numbers to force non-integer divisions
    let quantity = 17_777;
    let price = 13_131_000_000;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Split available funds to test rounding in both sources
    let balance_manager_input_coin = protocol_fee / 3; // Non-integer division
    let wallet_input_coin = total_required_in_bm + protocol_fee;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    let protocol_fee_from_bm = balance_manager_input_coin;
    let protocol_fee_from_wallet = protocol_fee - protocol_fee_from_bm;
    let needed_from_wallet = total_required_in_bm;

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        protocol_fee_from_wallet, // remaining protocol fee after BM portion
        protocol_fee_from_bm, // what we could take from BM
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        needed_from_wallet, // entire order amount needed from wallet
        true, // sufficient funds
    );
}

#[test]
/// Tests zero balance scenarios where:
/// 1. Balance manager has zero balance
/// 2. Wallet has enough for everything
/// 3. Verifies correct handling of zero amounts
public fun zero_balance_manager() {
    let quantity = QUANTITY_MEDIUM;
    let price = PRICE_MEDIUM;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances with zero in BM
    let balance_manager_input_coin = 0;
    let wallet_input_coin = total_required_in_bm + protocol_fee;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        protocol_fee, // all protocol fee from wallet
        0, // no protocol fee from BM (zero balance)
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        total_required_in_bm, // entire amount from wallet
        true, // sufficient funds
    );
}

#[test]
/// Tests zero balance scenarios where:
/// 1. Wallet has zero balance
/// 2. Balance manager has enough for everything
/// 3. Verifies correct handling of zero amounts
public fun zero_wallet() {
    let quantity = QUANTITY_MEDIUM;
    let price = PRICE_MEDIUM;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances with zero in wallet
    let balance_manager_input_coin = total_required_in_bm + protocol_fee;
    let wallet_input_coin = 0;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        0, // no protocol fee from wallet (zero balance)
        protocol_fee, // all protocol fee from BM
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        0, // nothing needed from wallet
        true, // sufficient funds
    );
}

#[test]
/// Tests boundary conditions where:
/// 1. Balance manager has exactly one coin less than needed for protocol fee
/// 2. Wallet has exactly required amount
/// 3. Verifies behavior with off-by-one scenarios
public fun boundary_conditions() {
    let quantity = QUANTITY_MEDIUM;
    let price = PRICE_MEDIUM;
    let is_pool_whitelisted = false;

    // Calculate order requirements
    let order_amount = calculate_order_amount(quantity, price, true);
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, DEEPBOOK_FEE_RATE);
    let protocol_fee = calculate_input_coin_protocol_fee(order_amount, DEEPBOOK_FEE_RATE);
    let total_required_in_bm = order_amount + deepbook_fee;

    // Set up balances:
    // BM has one coin less than protocol fee
    let balance_manager_input_coin = protocol_fee - 1;
    // Wallet has exact amount needed (protocol fee remainder + order amount)
    let wallet_input_coin = total_required_in_bm + 1;

    let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
        is_pool_whitelisted,
        DEEPBOOK_FEE_RATE,
        balance_manager_input_coin,
        wallet_input_coin,
        order_amount,
    );

    assert_order_plans_eq(
        fee_plan,
        input_coin_deposit_plan,
        // InputCoinFeePlan expectations
        1, // one coin of protocol fee from wallet
        balance_manager_input_coin, // rest of protocol fee from BM
        true, // user can cover protocol fee
        // InputCoinDepositPlan expectations
        total_required_in_bm,
        total_required_in_bm, // need entire amount from wallet as BM used for fee
        true, // sufficient funds
    );
}

#[test]
/// Tests combined edge cases where:
/// 1. Pool is whitelisted (no fees)
/// 2. One source has zero balance
/// 3. Other source has exact amount needed
public fun whitelisted_zero_balance() {
    let quantity = QUANTITY_LARGE;
    let price = PRICE_LARGE;
    let is_pool_whitelisted = true;

    // Calculate order requirements - no fees for whitelisted pool
    let order_amount = calculate_order_amount(quantity, price, true);
    let total_required_in_bm = order_amount;

    // Test both zero BM and zero wallet scenarios
    let mut bm_balances = vector::empty();
    let mut wallet_balances = vector::empty();
    let mut expected_from_wallets = vector::empty();

    vector::push_back(&mut bm_balances, 0);
    vector::push_back(&mut bm_balances, order_amount);

    vector::push_back(&mut wallet_balances, order_amount);
    vector::push_back(&mut wallet_balances, 0);

    vector::push_back(&mut expected_from_wallets, order_amount);
    vector::push_back(&mut expected_from_wallets, 0);

    let mut i = 0;
    while (i < 2) {
        let bm_balance = *vector::borrow(&bm_balances, i);
        let wallet_balance = *vector::borrow(&wallet_balances, i);
        let expected_from_wallet = *vector::borrow(&expected_from_wallets, i);

        let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
            is_pool_whitelisted,
            0, // whitelisted fee rate
            bm_balance,
            wallet_balance,
            order_amount,
        );

        assert_order_plans_eq(
            fee_plan,
            input_coin_deposit_plan,
            // InputCoinFeePlan expectations
            0, // no protocol fee from wallet
            0, // no protocol fee from BM
            true, // user can cover protocol fee (which is 0)
            // InputCoinDepositPlan expectations
            total_required_in_bm,
            expected_from_wallet,
            true, // sufficient funds
        );

        i = i + 1;
    };
}

#[test]
/// Tests whitelisted pool with maximum values where:
/// 1. Pool is whitelisted (no fees)
/// 2. Uses maximum possible quantity and price
/// 3. Verifies no overflow in calculations
/// 4. Tests both BM and wallet as primary source
public fun whitelisted_maximum_values() {
    let quantity = QUANTITY_LARGE * 1000;
    let price = PRICE_LARGE;
    let is_pool_whitelisted = true;

    // Calculate order requirements - no fees for whitelisted pool
    let order_amount = calculate_order_amount(quantity, price, true);
    let total_required_in_bm = order_amount;

    // Test both BM-primary and wallet-primary scenarios
    let mut bm_balances = vector::empty();
    let mut wallet_balances = vector::empty();
    let mut expected_from_wallets = vector::empty();

    // Scenario 1: BM has all required funds
    vector::push_back(&mut bm_balances, total_required_in_bm);
    vector::push_back(&mut wallet_balances, 0);
    vector::push_back(&mut expected_from_wallets, 0);

    // Scenario 2: Wallet has all required funds
    vector::push_back(&mut bm_balances, 0);
    vector::push_back(&mut wallet_balances, total_required_in_bm);
    vector::push_back(&mut expected_from_wallets, total_required_in_bm);

    let mut i = 0;
    while (i < 2) {
        let bm_balance = *vector::borrow(&bm_balances, i);
        let wallet_balance = *vector::borrow(&wallet_balances, i);
        let expected_from_wallet = *vector::borrow(&expected_from_wallets, i);

        let (fee_plan, input_coin_deposit_plan) = create_input_fee_order_core(
            is_pool_whitelisted,
            0, // whitelisted fee rate
            bm_balance,
            wallet_balance,
            order_amount,
        );

        assert_order_plans_eq(
            fee_plan,
            input_coin_deposit_plan,
            // InputCoinFeePlan expectations
            0, // no protocol fee from wallet
            0, // no protocol fee from BM
            true, // user can cover protocol fee (which is 0)
            // InputCoinDepositPlan expectations
            total_required_in_bm,
            expected_from_wallet,
            true, // sufficient funds
        );

        i = i + 1;
    };
}
