#[test_only]
module deepbook_wrapper::get_protocol_fee_plan_tests;

use deepbook::constants;
use deepbook::order_info::{Self, OrderInfo};
use deepbook_wrapper::fee::calculate_protocol_fees;
use deepbook_wrapper::helper::calculate_order_taker_maker_ratio;
use deepbook_wrapper::order::{get_protocol_fee_plan, assert_protocol_fee_plan_eq};
use std::unit_test::assert_eq;
use sui::object::id_from_address;

// ===== Constants =====
const TAKER_FEE_RATE: u64 = 2_500_000; // 0.25% in billionths
const MAKER_FEE_RATE: u64 = 1_000_000; // 0.1% in billionths
const ORDER_AMOUNT: u64 = 1_000_000; // 1M units
const DISCOUNT_RATE: u64 = 0; // No discount by default

// Test addresses
const ALICE: address = @0xA;
const POOL_ID: address = @0x1;
const BALANCE_MANAGER_ID: address = @0x2;

// ===== Fee Distribution Tests =====

#[test]
public fun fee_from_wallet_only_fully_executed() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = total_fee * 2; // Plenty in wallet
    let coin_in_balance_manager = 0; // Nothing in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // All fees should be taken from wallet since BM is empty
    assert_protocol_fee_plan_eq(
        plan,
        taker_fee, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        maker_fee, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

#[test]
public fun fee_from_balance_manager_only_fully_executed() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = 0; // Nothing in wallet
    let coin_in_balance_manager = total_fee * 2; // Plenty in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // All fees should be taken from balance manager since wallet is empty
    assert_protocol_fee_plan_eq(
        plan,
        0, // taker_fee_from_wallet
        taker_fee, // taker_fee_from_balance_manager
        0, // maker_fee_from_wallet
        maker_fee, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

#[test]
public fun fee_split_between_wallet_and_balance_manager() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Put 2/3 in BM, 1/3 in wallet
    let coin_in_balance_manager = (total_fee * 2) / 3;
    let coin_in_wallet = total_fee - coin_in_balance_manager;

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Taker fee is taken first from BM
    let taker_from_bm = if (coin_in_balance_manager >= taker_fee) {
        taker_fee
    } else {
        coin_in_balance_manager
    };
    let taker_from_wallet = taker_fee - taker_from_bm;

    // Maker fee is taken from remaining BM funds, then wallet
    let remaining_bm = coin_in_balance_manager - taker_from_bm;
    let maker_from_bm = if (remaining_bm >= maker_fee) {
        maker_fee
    } else {
        remaining_bm
    };
    let maker_from_wallet = maker_fee - maker_from_bm;

    // Verify fee distribution
    assert_protocol_fee_plan_eq(
        plan,
        taker_from_wallet, // taker_fee_from_wallet
        taker_from_bm, // taker_fee_from_balance_manager
        maker_from_wallet, // maker_fee_from_wallet
        maker_from_bm, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

#[test]
public fun partially_executed_order_fees() {
    let order_info = create_partially_executed_order();

    // Calculate expected fees for partially executed order
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = total_fee * 2; // Plenty in wallet
    let coin_in_balance_manager = 0; // Nothing in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // All fees should be taken from wallet since BM is empty
    assert_protocol_fee_plan_eq(
        plan,
        taker_fee, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        maker_fee, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

#[test]
public fun cancelled_order_with_partial_execution() {
    let order_info = create_cancelled_order();

    // Calculate expected fees for cancelled order (should have taker fees for executed portion)
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = total_fee / 2; // Half of the fee in wallet
    let coin_in_balance_manager = total_fee / 2; // Half of the fee in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Cancelled order should have taker fees for the executed portion
    assert!(taker_fee > 0);
    assert_eq!(maker_fee, 0); // No maker fees for cancelled orders

    assert_protocol_fee_plan_eq(
        plan,
        coin_in_wallet, // taker_fee_from_wallet
        coin_in_balance_manager, // taker_fee_from_balance_manager
        0, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

// ===== Insufficient Resources Tests =====

#[test]
public fun insufficient_fee_resources() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, _taker_fee, _maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Total available is 50% of required fee
    let coin_in_wallet = total_fee / 4; // 25% in wallet
    let coin_in_balance_manager = total_fee / 4; // 25% in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_protocol_fee_plan_eq(
        plan,
        0, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        0, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        false, // user_covers_fee
    );
}

#[test]
public fun almost_sufficient_fee_resources() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, _taker_fee, _maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Total available is 1 less than required fee
    let coin_in_wallet = total_fee / 2; // 50% in wallet
    let coin_in_balance_manager = (total_fee / 2) - 1; // Almost 50% in balance manager (1 short)

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_protocol_fee_plan_eq(
        plan,
        0, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        0, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        false, // user_covers_fee
    );
}

// ===== Boundary Tests =====

#[test]
public fun exact_fee_match_with_wallet() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = total_fee; // Exact match
    let coin_in_balance_manager = 0; // Nothing in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // All fees should be taken from wallet since BM is empty
    assert_protocol_fee_plan_eq(
        plan,
        taker_fee, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        maker_fee, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

#[test]
public fun exact_fee_match_with_balance_manager() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = 0; // Nothing in wallet
    let coin_in_balance_manager = total_fee; // Exact match

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // All fees should be taken from balance manager since wallet is empty
    assert_protocol_fee_plan_eq(
        plan,
        0, // taker_fee_from_wallet
        taker_fee, // taker_fee_from_balance_manager
        0, // maker_fee_from_wallet
        maker_fee, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

#[test]
public fun exact_fee_match_combined() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Put half in each source
    let coin_in_balance_manager = total_fee / 2;
    let coin_in_wallet = total_fee - coin_in_balance_manager;

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Taker fee should be taken from BM first
    let taker_from_bm = if (coin_in_balance_manager >= taker_fee) {
        taker_fee
    } else {
        coin_in_balance_manager
    };
    let taker_from_wallet = taker_fee - taker_from_bm;

    // Maker fee should be taken from remaining BM funds, then wallet
    let remaining_bm = coin_in_balance_manager - taker_from_bm;
    let maker_from_bm = if (remaining_bm >= maker_fee) {
        maker_fee
    } else {
        remaining_bm
    };
    let maker_from_wallet = maker_fee - maker_from_bm;

    // Verify fee distribution
    assert_protocol_fee_plan_eq(
        plan,
        taker_from_wallet, // taker_fee_from_wallet
        taker_from_bm, // taker_fee_from_balance_manager
        maker_from_wallet, // maker_fee_from_wallet
        maker_from_bm, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

// ===== Discount Rate Tests =====

#[test]
public fun fee_with_discount_rate() {
    let order_info = create_fully_executed_order();
    let discount_rate = 100_000_000; // 10% discount

    // Calculate expected fees with discount
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        discount_rate,
    );

    // Calculate fees without discount for comparison
    let (
        total_fee_no_discount,
        _taker_fee_no_discount,
        _maker_fee_no_discount,
    ) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        0,
    );

    // Verify discount is applied
    assert!(total_fee < total_fee_no_discount);

    let coin_in_wallet = total_fee * 2; // Plenty in wallet
    let coin_in_balance_manager = 0; // Nothing in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        discount_rate,
    );

    // All fees should be taken from wallet since BM is empty
    assert_protocol_fee_plan_eq(
        plan,
        taker_fee, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        maker_fee, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

// ===== Edge Cases =====

#[test]
public fun wallet_exactly_one_token_short() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, _taker_fee, _maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = total_fee - 1; // 1 token short
    let coin_in_balance_manager = 0; // Nothing in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_protocol_fee_plan_eq(
        plan,
        0, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        0, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        false, // user_covers_fee
    );
}

#[test]
public fun balance_manager_exactly_one_token_short_with_empty_wallet() {
    let order_info = create_fully_executed_order();

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, _taker_fee, _maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = 0; // Empty wallet
    let coin_in_balance_manager = total_fee - 1; // 1 token short

    let plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Should indicate insufficient resources with all fees set to 0
    assert_protocol_fee_plan_eq(
        plan,
        0, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        0, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        false, // user_covers_fee
    );
}

// ===== Fee Rate Variations =====

#[test]
public fun different_taker_maker_rates() {
    let order_info = create_partially_executed_order();

    let high_taker_rate = 5_000_000; // 0.5%
    let low_maker_rate = 500_000; // 0.05%

    // Calculate expected fees with different rates
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        high_taker_rate,
        low_maker_rate,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = total_fee * 2; // Plenty in wallet
    let coin_in_balance_manager = 0; // Nothing in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        high_taker_rate,
        low_maker_rate,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // For partially executed order, we should have both taker and maker fees
    assert!(taker_fee > 0);
    assert!(maker_fee > 0);

    // All fees should be taken from wallet since BM is empty
    assert_protocol_fee_plan_eq(
        plan,
        taker_fee, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        maker_fee, // maker_fee_from_wallet
        0, // maker_fee_from_balance_manager
        true, // user_covers_fee
    );
}

#[test]
public fun fully_executed_order_only_taker_fees() {
    let order_info = create_fully_executed_order();

    let taker_rate = 2_500_000; // 0.25%
    let maker_rate = 1_000_000; // 0.1%

    // Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        taker_rate,
        maker_rate,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    let coin_in_wallet = total_fee * 2; // Plenty in wallet
    let coin_in_balance_manager = 0; // Nothing in balance manager

    let plan = get_protocol_fee_plan(
        &order_info,
        taker_rate,
        maker_rate,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // For fully executed order, only taker fees should apply
    assert!(taker_fee > 0);
    assert!(maker_fee == 0); // No maker fee for fully executed orders
    assert!(total_fee == taker_fee); // Total should equal taker fee only

    // All fees should be taken from wallet since BM is empty
    assert_protocol_fee_plan_eq(
        plan,
        taker_fee, // taker_fee_from_wallet
        0, // taker_fee_from_balance_manager
        0, // maker_fee_from_wallet (should be 0)
        0, // maker_fee_from_balance_manager (should be 0)
        true, // user_covers_fee
    );
}

// ===== Helper Functions =====

/// Creates a fully executed order for testing
fun create_fully_executed_order(): OrderInfo {
    let original_quantity = 1_000_000;
    let executed_quantity = 1_000_000;
    let status = constants::filled(); // Fully executed status

    create_mock_order_info(original_quantity, executed_quantity, status)
}

/// Creates a partially executed order for testing
fun create_partially_executed_order(): OrderInfo {
    let original_quantity = 1_000_000;
    let executed_quantity = 500_000; // 50% executed
    let status = constants::partially_filled(); // Partially executed status

    create_mock_order_info(original_quantity, executed_quantity, status)
}

/// Creates a cancelled order for testing (with partial execution)
fun create_cancelled_order(): OrderInfo {
    let original_quantity = 1_000_000;
    let executed_quantity = 300_000; // 30% executed before cancellation
    let status = constants::canceled(); // Cancelled status

    create_mock_order_info(original_quantity, executed_quantity, status)
}

/// Helper to create mock OrderInfo using the test function from deepbook
fun create_mock_order_info(original_quantity: u64, executed_quantity: u64, status: u8): OrderInfo {
    order_info::create_order_info_for_tests(
        id_from_address(POOL_ID),
        id_from_address(BALANCE_MANAGER_ID),
        1, // order_id
        ALICE,
        1_000_000, // price
        original_quantity,
        executed_quantity,
        status,
    )
}
