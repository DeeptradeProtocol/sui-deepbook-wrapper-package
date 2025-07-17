#[test_only]
module deepbook_wrapper::add_unsettled_fee_tests;

use deepbook::constants;
use deepbook::order_info;
use deepbook_wrapper::wrapper::{Self, Wrapper};
use std::unit_test::assert_eq;
use sui::balance;
use sui::object::id_from_address;
use sui::sui::SUI;
use sui::test_scenario::{Scenario, begin, end, return_shared};
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

#[test]
fun live_order_success() {
    let mut scenario = setup_wrapper_test(OWNER);
    let pool_id = id_from_address(@0x1);
    let balance_manager_id = id_from_address(ALICE);
    let order_id = 12345u128;
    let fee_amount = 1000u64;
    let original_quantity = 100u64;
    let executed_quantity = 50u64;
    let expected_maker_quantity = original_quantity - executed_quantity;

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        let order_info = create_live_order_info(
            pool_id,
            balance_manager_id,
            order_id,
            ALICE,
            1000000, // price
            original_quantity,
            executed_quantity,
        );

        // Verify fee doesn't exist before adding
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id, balance_manager_id, order_id), false);

        // Should succeed for live order with remaining quantity
        wrapper.add_unsettled_fee(fee_balance, &order_info);

        // Verify fee was stored correctly
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            wrapper.get_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            fee_amount,
        );

        // Verify order parameters were stored correctly
        let (stored_order_quantity, stored_maker_quantity) = wrapper.get_unsettled_fee_order_params<
            SUI,
        >(pool_id, balance_manager_id, order_id);
        assert_eq!(stored_order_quantity, original_quantity);
        assert_eq!(stored_maker_quantity, expected_maker_quantity);

        return_shared(wrapper);
    };

    scenario.end();
}

#[test]
fun partially_filled_order_success() {
    let mut scenario = setup_wrapper_test(OWNER);
    let pool_id = id_from_address(@0x1);
    let balance_manager_id = id_from_address(ALICE);
    let order_id = 12345u128;
    let fee_amount = 1000u64;
    let original_quantity = 100u64;
    let executed_quantity = 30u64;
    let expected_maker_quantity = original_quantity - executed_quantity;

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        let order_info = create_partially_filled_order_info(
            pool_id,
            balance_manager_id,
            order_id,
            ALICE,
            1000000, // price
            original_quantity,
            executed_quantity,
        );

        // Verify fee doesn't exist before adding
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id, balance_manager_id, order_id), false);

        // Should succeed for partially filled order with remaining quantity
        wrapper.add_unsettled_fee(fee_balance, &order_info);

        // Verify fee was stored correctly
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            wrapper.get_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            fee_amount,
        );

        // Verify order parameters were stored correctly
        let (stored_order_quantity, stored_maker_quantity) = wrapper.get_unsettled_fee_order_params<
            SUI,
        >(pool_id, balance_manager_id, order_id);
        assert_eq!(stored_order_quantity, original_quantity);
        assert_eq!(stored_maker_quantity, expected_maker_quantity);

        return_shared(wrapper);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = wrapper::EUnsettledFeeAlreadyExists)]
fun join_existing_fee_fails() {
    let mut scenario = setup_wrapper_test(OWNER);
    let pool_id = id_from_address(@0x1);
    let balance_manager_id = id_from_address(ALICE);
    let order_id = 12345u128;
    let fee_amount_1 = 1000u64;
    let fee_amount_2 = 1500u64;
    let original_quantity = 100u64;
    let executed_quantity = 50u64;

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let order_info = create_live_order_info(
            pool_id,
            balance_manager_id,
            order_id,
            ALICE,
            1000000, // price
            original_quantity,
            executed_quantity,
        );

        // Add first fee
        let fee_balance_1 = balance::create_for_testing<SUI>(fee_amount_1);
        wrapper.add_unsettled_fee(fee_balance_1, &order_info);

        // Verify first fee was stored correctly
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            wrapper.get_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            fee_amount_1,
        );

        // Add second fee to same order - should fail
        let fee_balance_2 = balance::create_for_testing<SUI>(fee_amount_2);
        wrapper.add_unsettled_fee(fee_balance_2, &order_info);

        return_shared(wrapper);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = wrapper::EOrderNotLiveOrPartiallyFilled)]
fun cancelled_order_fails() {
    let mut scenario = setup_wrapper_test(OWNER);
    let pool_id = id_from_address(@0x1);
    let balance_manager_id = id_from_address(ALICE);
    let order_id = 12345u128;
    let fee_amount = 1000u64;

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        let order_info = create_cancelled_order_info(
            pool_id,
            balance_manager_id,
            order_id,
            ALICE,
            1000000, // price
            100, // original_quantity
            50, // executed_quantity
        );

        // Should fail for cancelled order
        wrapper.add_unsettled_fee(fee_balance, &order_info);

        return_shared(wrapper);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = wrapper::EOrderFullyExecuted)]
fun fully_executed_order_fails() {
    let mut scenario = setup_wrapper_test(OWNER);
    let pool_id = id_from_address(@0x1);
    let balance_manager_id = id_from_address(ALICE);
    let order_id = 12345u128;
    let fee_amount = 1000u64;

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        let order_info = create_live_order_info(
            pool_id,
            balance_manager_id,
            order_id,
            ALICE,
            1000000, // price
            100, // original_quantity
            100, // executed_quantity - fully executed
        );

        // Should fail for fully executed order
        wrapper.add_unsettled_fee(fee_balance, &order_info);

        return_shared(wrapper);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = wrapper::EZeroUnsettledFee)]
fun zero_fee_fails() {
    let mut scenario = setup_wrapper_test(OWNER);
    let pool_id = id_from_address(@0x1);
    let balance_manager_id = id_from_address(ALICE);
    let order_id = 12345u128;

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let fee_balance = balance::create_for_testing<SUI>(0); // zero fee
        let order_info = create_live_order_info(
            pool_id,
            balance_manager_id,
            order_id,
            ALICE,
            1000000, // price
            100, // original_quantity
            50, // executed_quantity
        );

        // Should fail for zero fee amount
        wrapper.add_unsettled_fee(fee_balance, &order_info);

        return_shared(wrapper);
    };

    scenario.end();
}

#[test]
fun different_coin_types() {
    let mut scenario = setup_wrapper_test(OWNER);

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();

        let pool_id = id_from_address(@0x1);
        let balance_manager_id = id_from_address(@0x2);
        let sui_order_id = 12345;
        let deep_order_id = 67890;

        // Create order info for SUI fee
        let sui_order_info = create_live_order_info(
            pool_id,
            balance_manager_id,
            sui_order_id,
            @0x3, // trader
            1000, // price
            5000, // original_quantity
            2000, // executed_quantity
        );

        // Create order info for DEEP fee
        let deep_order_info = create_live_order_info(
            pool_id,
            balance_manager_id,
            deep_order_id,
            @0x3, // trader
            1500, // price
            6000, // original_quantity
            3000, // executed_quantity
        );

        // Verify no fees exist initially
        assert_eq!(
            wrapper.has_unsettled_fee<SUI>(pool_id, balance_manager_id, sui_order_id),
            false,
        );
        assert_eq!(
            wrapper.has_unsettled_fee<DEEP>(pool_id, balance_manager_id, deep_order_id),
            false,
        );

        // Add SUI fee to first order
        let sui_fee = balance::create_for_testing<SUI>(1000);
        wrapper.add_unsettled_fee(sui_fee, &sui_order_info);

        // Add DEEP fee to second order
        let deep_fee = balance::create_for_testing<DEEP>(2000);
        wrapper.add_unsettled_fee(deep_fee, &deep_order_info);

        // Verify both fees exist and are stored separately
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id, balance_manager_id, sui_order_id), true);
        assert_eq!(
            wrapper.has_unsettled_fee<DEEP>(pool_id, balance_manager_id, deep_order_id),
            true,
        );

        // Verify correct amounts
        assert_eq!(
            wrapper.get_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, sui_order_id),
            1000,
        );
        assert_eq!(
            wrapper.get_unsettled_fee_balance<DEEP>(pool_id, balance_manager_id, deep_order_id),
            2000,
        );

        // Verify order params are correct for both types
        let (order_quantity_sui, maker_quantity_sui) = wrapper.get_unsettled_fee_order_params<SUI>(
            pool_id,
            balance_manager_id,
            sui_order_id,
        );
        let (order_quantity_deep, maker_quantity_deep) = wrapper.get_unsettled_fee_order_params<
            DEEP,
        >(pool_id, balance_manager_id, deep_order_id);

        assert_eq!(order_quantity_sui, 5000);
        assert_eq!(maker_quantity_sui, 3000); // 5000 - 2000
        assert_eq!(order_quantity_deep, 6000);
        assert_eq!(maker_quantity_deep, 3000); // 6000 - 3000

        return_shared(wrapper);
    };

    scenario.end();
}

#[test]
fun cross_pool_scenarios() {
    let mut scenario = setup_wrapper_test(OWNER);

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();

        let pool_id_1 = id_from_address(@0x1);
        let pool_id_2 = id_from_address(@0x2);
        let balance_manager_id = id_from_address(@0x3);
        let order_id = 12345;

        // Create order info for first pool
        let order_info_1 = create_live_order_info(
            pool_id_1,
            balance_manager_id,
            order_id,
            @0x4, // trader
            1000, // price
            5000, // original_quantity
            2000, // executed_quantity
        );

        // Create order info for second pool (same balance_manager_id and order_id)
        let order_info_2 = create_partially_filled_order_info(
            pool_id_2,
            balance_manager_id,
            order_id,
            @0x4, // same trader
            1500, // different price
            6000, // different original_quantity
            3000, // different executed_quantity
        );

        // Verify no fees exist initially
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id_1, balance_manager_id, order_id), false);
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id_2, balance_manager_id, order_id), false);

        // Add fee to first pool
        let fee_1 = balance::create_for_testing<SUI>(1000);
        wrapper.add_unsettled_fee(fee_1, &order_info_1);

        // Add fee to second pool
        let fee_2 = balance::create_for_testing<SUI>(1500);
        wrapper.add_unsettled_fee(fee_2, &order_info_2);

        // Verify both fees exist and are stored separately
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id_1, balance_manager_id, order_id), true);
        assert_eq!(wrapper.has_unsettled_fee<SUI>(pool_id_2, balance_manager_id, order_id), true);

        // Verify correct amounts for each pool
        assert_eq!(
            wrapper.get_unsettled_fee_balance<SUI>(pool_id_1, balance_manager_id, order_id),
            1000,
        );
        assert_eq!(
            wrapper.get_unsettled_fee_balance<SUI>(pool_id_2, balance_manager_id, order_id),
            1500,
        );

        // Verify order params are different for each pool
        let (order_quantity_1, maker_quantity_1) = wrapper.get_unsettled_fee_order_params<SUI>(
            pool_id_1,
            balance_manager_id,
            order_id,
        );
        let (order_quantity_2, maker_quantity_2) = wrapper.get_unsettled_fee_order_params<SUI>(
            pool_id_2,
            balance_manager_id,
            order_id,
        );

        // Pool 1 params
        assert_eq!(order_quantity_1, 5000);
        assert_eq!(maker_quantity_1, 3000); // 5000 - 2000

        // Pool 2 params
        assert_eq!(order_quantity_2, 6000);
        assert_eq!(maker_quantity_2, 3000); // 6000 - 3000

        // Verify fees remain unchanged
        assert_eq!(
            wrapper.get_unsettled_fee_balance<SUI>(pool_id_1, balance_manager_id, order_id),
            1000,
        );
        assert_eq!(
            wrapper.get_unsettled_fee_balance<SUI>(pool_id_2, balance_manager_id, order_id),
            1500,
        );

        return_shared(wrapper);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = wrapper::EOrderNotLiveOrPartiallyFilled)]
fun filled_order_fails() {
    let mut scenario = setup_wrapper_test(OWNER);
    let pool_id = id_from_address(@0x1);
    let balance_manager_id = id_from_address(ALICE);
    let order_id = 12345u128;
    let fee_amount = 1000u64;

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        let order_info = create_filled_order_info(
            pool_id,
            balance_manager_id,
            order_id,
            ALICE,
            1000000, // price
            100, // original_quantity
            100, // executed_quantity - fully filled
        );

        // Should fail for filled order
        wrapper.add_unsettled_fee(fee_balance, &order_info);

        return_shared(wrapper);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = wrapper::EOrderNotLiveOrPartiallyFilled)]
fun expired_order_fails() {
    let mut scenario = setup_wrapper_test(OWNER);
    let pool_id = id_from_address(@0x1);
    let balance_manager_id = id_from_address(ALICE);
    let order_id = 12345u128;
    let fee_amount = 1000u64;

    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        let order_info = create_expired_order_info(
            pool_id,
            balance_manager_id,
            order_id,
            ALICE,
            1000000, // price
            100, // original_quantity
            50, // executed_quantity
        );

        // Should fail for expired order
        wrapper.add_unsettled_fee(fee_balance, &order_info);

        return_shared(wrapper);
    };

    scenario.end();
}

/// Setup a test scenario with an initialized wrapper
public(package) fun setup_wrapper_test(owner: address): Scenario {
    let mut scenario = begin(owner);
    {
        let ctx = scenario.ctx();
        wrapper::init_for_testing(ctx);
    };
    scenario
}

/// Create a live OrderInfo for testing
public(package) fun create_live_order_info(
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
    trader: address,
    price: u64,
    original_quantity: u64,
    executed_quantity: u64,
): order_info::OrderInfo {
    order_info::create_order_info_for_tests(
        pool_id,
        balance_manager_id,
        order_id,
        trader,
        price,
        original_quantity,
        executed_quantity,
        constants::live(),
    )
}

/// Create a partially filled OrderInfo for testing
public(package) fun create_partially_filled_order_info(
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
    trader: address,
    price: u64,
    original_quantity: u64,
    executed_quantity: u64,
): order_info::OrderInfo {
    order_info::create_order_info_for_tests(
        pool_id,
        balance_manager_id,
        order_id,
        trader,
        price,
        original_quantity,
        executed_quantity,
        constants::partially_filled(),
    )
}

/// Create a cancelled OrderInfo for testing
public(package) fun create_cancelled_order_info(
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
    trader: address,
    price: u64,
    original_quantity: u64,
    executed_quantity: u64,
): order_info::OrderInfo {
    order_info::create_order_info_for_tests(
        pool_id,
        balance_manager_id,
        order_id,
        trader,
        price,
        original_quantity,
        executed_quantity,
        constants::canceled(),
    )
}

/// Create a filled OrderInfo for testing
public(package) fun create_filled_order_info(
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
    trader: address,
    price: u64,
    original_quantity: u64,
    executed_quantity: u64,
): order_info::OrderInfo {
    order_info::create_order_info_for_tests(
        pool_id,
        balance_manager_id,
        order_id,
        trader,
        price,
        original_quantity,
        executed_quantity,
        constants::filled(),
    )
}

/// Create an expired OrderInfo for testing
public(package) fun create_expired_order_info(
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
    trader: address,
    price: u64,
    original_quantity: u64,
    executed_quantity: u64,
): order_info::OrderInfo {
    order_info::create_order_info_for_tests(
        pool_id,
        balance_manager_id,
        order_id,
        trader,
        price,
        original_quantity,
        executed_quantity,
        constants::expired(),
    )
}
