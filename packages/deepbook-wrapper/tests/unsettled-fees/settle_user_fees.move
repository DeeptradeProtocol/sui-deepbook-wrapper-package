#[test_only]
module deepbook_wrapper::settle_user_fees_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{
    setup_test,
    setup_pool_with_default_fees_and_reference_pool,
    place_limit_order
};
use deepbook_wrapper::unsettled_fees::{
    Self,
    add_unsettled_fee,
    has_unsettled_fee,
    get_unsettled_fee_balance,
    settle_user_fees
};
use deepbook_wrapper::wrapper::{Self, Wrapper};
use std::unit_test::assert_eq;
use sui::balance;
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario::{Scenario, begin, end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

#[test]
fun unfilled_order_returns_all_fees() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a limit order
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees to this order
        let fee_amount = 1000u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        // Verify the fee was added
        assert_eq!(
            has_unsettled_fee<SUI>(
                &wrapper,
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            true,
        );
        assert_eq!(
            get_unsettled_fee_balance<SUI>(
                &wrapper,
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            fee_amount,
        );

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Test settle_user_fees
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees - this should return fees since order is unfilled
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Since the order is completely unfilled, we should get all fees back
        assert_eq!(settled_coin.value(), 1000u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun partially_filled_order_returns_proportional_fees() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place original order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a buy order for 100 units at price 2.0
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees to this order
        let fee_amount = 1000u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Place matching order to partially fill the original order
    scenario.next_tx(ALICE);
    {
        // Place a sell order for 30 units at price 2.0 to partially fill the buy order
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price (same as buy order)
            30 * constants::float_scaling(), // quantity (smaller than buy order)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );
    };

    // Step 3: Test settle_user_fees
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees - this should return proportional fees for unfilled portion
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Original order: 100 units, filled: 30 units, unfilled: 70 units
        // Proportional fees: 1000 * (70/100) = 700
        assert_eq!(settled_coin.value(), 700u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun fully_filled_order_keeps_unsettled_fees() {
    // This test verifies the correct design behavior when an order is fully filled:
    // 1. The order is removed from the order book
    // 2. The unsettled fees remain in the wrapper
    // 3. Since the order was fully executed, all fees belong to the protocol
    // 4. Users cannot settle fees on filled orders
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place original order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a buy order for 100 units at price 2.0
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees to this order
        let fee_amount = 1000u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Place matching order to completely fill the original order
    scenario.next_tx(ALICE);
    {
        // Place a sell order for 100 units at price 2.0 to completely fill the buy order
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price (same as buy order)
            100 * constants::float_scaling(), // quantity (same as buy order)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );
    };

    // Step 3: Verify behavior with fully filled order
    scenario.next_tx(ALICE);
    {
        let wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Verify the order is no longer in open orders (fully filled orders are removed)
        let open_orders = pool.account_open_orders(&balance_manager);
        assert_eq!(open_orders.contains(&order_id), false);

        // Verify the unsettled fee still exists
        assert_eq!(
            has_unsettled_fee<SUI>(
                &wrapper,
                object::id(&pool),
                object::id(&balance_manager),
                order_id,
            ),
            true,
        );

        // Verify the unsettled fee amount is unchanged (1000u64)
        assert_eq!(
            get_unsettled_fee_balance<SUI>(
                &wrapper,
                object::id(&pool),
                object::id(&balance_manager),
                order_id,
            ),
            1000u64,
        );

        // Clean up
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = 5, location = deepbook::big_vector)]
fun settle_user_fees_fails_on_filled_order() {
    // This test verifies that users cannot settle fees on filled orders
    // because the order no longer exists in the order book (get_order fails)
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place original order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a buy order for 100 units at price 2.0
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees to this order
        let fee_amount = 1000u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Place matching order to completely fill the original order
    scenario.next_tx(ALICE);
    {
        // Place a sell order for 100 units at price 2.0 to completely fill the buy order
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price (same as buy order)
            100 * constants::float_scaling(), // quantity (same as buy order)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );
    };

    // Step 3: Attempt to settle fees on filled order - this should fail
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // This should fail because the order no longer exists in the order book
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // The code below is never reached (test aborts above), but needed for compiler
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun order_with_no_unsettled_fees_returns_zero() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order without adding any unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        // Place a limit order without any unsettled fees
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Note: NOT adding any unsettled fees here
        order_info.order_id()
    };

    // Step 2: Test settle_user_fees
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees - this should return 0 fees since no fees were added
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Since no fees were added, we should get 0 fees back
        assert_eq!(settled_coin.value(), 0u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun multiple_fee_types_settled_separately() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place three separate orders with different fee types
    scenario.next_tx(ALICE);
    let (sui_order_id, usdc_order_id, deep_order_id) = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place first order for SUI fees
        let sui_order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Place second order for USDC fees
        let usdc_order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Place third order for DEEP fees
        let deep_order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            3, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add different fee types to each order
        let sui_fee_balance = balance::create_for_testing<SUI>(1000u64);
        let usdc_fee_balance = balance::create_for_testing<USDC>(500u64);
        let deep_fee_balance = balance::create_for_testing<DEEP>(750u64);

        add_unsettled_fee(&mut wrapper, sui_fee_balance, &sui_order_info);
        add_unsettled_fee(&mut wrapper, usdc_fee_balance, &usdc_order_info);
        add_unsettled_fee(&mut wrapper, deep_fee_balance, &deep_order_info);

        let sui_order_id = sui_order_info.order_id();
        let usdc_order_id = usdc_order_info.order_id();
        let deep_order_id = deep_order_info.order_id();

        return_shared(wrapper);
        (sui_order_id, usdc_order_id, deep_order_id)
    };

    // Step 2: Test settle_user_fees for each fee type on different orders
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees for SUI fees
        let sui_settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            sui_order_id,
            scenario.ctx(),
        );
        assert_eq!(sui_settled_coin.value(), 1000u64);

        // Test settle_user_fees for USDC fees
        let usdc_settled_coin = settle_user_fees<SUI, USDC, USDC>(
            &mut wrapper,
            &pool,
            &balance_manager,
            usdc_order_id,
            scenario.ctx(),
        );
        assert_eq!(usdc_settled_coin.value(), 500u64);

        // Test settle_user_fees for DEEP fees
        let deep_settled_coin = settle_user_fees<SUI, USDC, DEEP>(
            &mut wrapper,
            &pool,
            &balance_manager,
            deep_order_id,
            scenario.ctx(),
        );
        assert_eq!(deep_settled_coin.value(), 750u64);

        // Clean up
        destroy(sui_settled_coin);
        destroy(usdc_settled_coin);
        destroy(deep_settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun settle_fees_on_invalid_order_id_returns_zero() {
    // This test verifies that settle_user_fees gracefully handles completely invalid order IDs
    // by returning zero coins (defensive design - no unsettled fees = no settlement)
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Use a completely invalid order ID that was never created
        let invalid_order_id = 999999u128;

        // This should return zero coin gracefully (no unsettled fees exist for this ID)
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            invalid_order_id,
            scenario.ctx(),
        );

        // Should return zero coin for non-existent order
        assert_eq!(settled_coin.value(), 0u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun settle_fees_on_nonexistent_order_returns_zero() {
    // This test verifies that settle_user_fees gracefully handles valid-format order IDs
    // that don't have unsettled fees by returning zero coins
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place one order to understand the ID format
    scenario.next_tx(ALICE);
    let existing_order_id = {
        // Place a limit order to see the ID format
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        order_info.order_id()
    };

    // Step 2: Try to settle fees on a non-existent order with similar ID format
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Create a non-existent order ID by modifying the existing one
        let nonexistent_order_id = existing_order_id + 12345u128;

        // This should return zero coin gracefully (no unsettled fees for this order)
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            nonexistent_order_id,
            scenario.ctx(),
        );

        // Should return zero coin for order without unsettled fees
        assert_eq!(settled_coin.value(), 0u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

// === Precision/Rounding Edge Cases ===

#[test]
fun minimal_fee_amount_precision() {
    // Tests precision with very small fee amounts (1-2 units)
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order and add minimal unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a limit order
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add minimal unsettled fees
        let fee_amount = 1u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Test settle_user_fees with minimal amount
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees - should return the minimal fee amount
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Should return exactly 1 unit
        assert_eq!(settled_coin.value(), 1u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun large_fee_amount_precision() {
    // Tests precision with very large fee amounts (near maximum values)
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order and add large unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a limit order
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add large unsettled fees (use a very large but safe value)
        let fee_amount = 999999999999u64; // Close to u64 max but safe for testing
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Test settle_user_fees with large amount
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees - should return the large fee amount
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Should return exactly the large amount
        assert_eq!(settled_coin.value(), 999999999999u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun rounding_behavior_with_odd_quantities() {
    // Tests rounding behavior when calculating proportional fees with odd numbers
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place original order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a buy order for 101 units (odd number)
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            101 * constants::float_scaling(), // quantity (odd number)
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees (odd amount)
        let fee_amount = 1001u64; // Odd fee amount
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Place matching order to partially fill with odd quantity
    scenario.next_tx(ALICE);
    {
        // Place a sell order for 37 units (odd number)
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            37 * constants::float_scaling(), // quantity (odd number)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );
    };

    // Step 3: Test settle_user_fees with odd number calculations
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees - should handle odd number rounding correctly
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Original order: 101 units, filled: 37 units, unfilled: 64 units
        // Proportional fees: 1001 * (64/101) = 634.3...
        // Expected: 634 (rounded down according to Move's integer division)
        assert_eq!(settled_coin.value(), 634u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun rounding_behavior_with_even_quantities() {
    // Tests rounding behavior when calculating proportional fees with even numbers
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place original order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a buy order for 100 units (even number)
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity (even number)
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees (even amount)
        let fee_amount = 1000u64; // Even fee amount
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Place matching order to partially fill with even quantity
    scenario.next_tx(ALICE);
    {
        // Place a sell order for 40 units (even number)
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            40 * constants::float_scaling(), // quantity (even number)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );
    };

    // Step 3: Test settle_user_fees with even number calculations
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees - should handle even number calculations perfectly
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Original order: 100 units, filled: 40 units, unfilled: 60 units
        // Proportional fees: 1000 * (60/100) = 1000 * 0.6 = 600 (exact)
        assert_eq!(settled_coin.value(), 600u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun very_small_order_quantities() {
    // Tests behavior with minimal order sizes (1-2 units)
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order with minimal quantity
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a buy order for 2 units (minimal viable quantity)
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            2 * constants::float_scaling(), // quantity (minimal)
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees
        let fee_amount = 100u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Place matching order to fill 1 unit
    scenario.next_tx(ALICE);
    {
        // Place a sell order for 1 unit
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            constants::float_scaling(), // quantity (1 unit)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );
    };

    // Step 3: Test settle_user_fees with minimal quantities
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Original order: 2 units, filled: 1 unit, unfilled: 1 unit
        // Proportional fees: 100 * (1/2) = 50
        assert_eq!(settled_coin.value(), 50u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun precise_proportional_calculations() {
    // Tests edge cases in proportional fee calculations with specific ratios
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place original order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a buy order for 1000 units
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            1000 * constants::float_scaling(), // quantity
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees
        let fee_amount = 999u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Place matching order to fill exactly 1/3 of the order
    scenario.next_tx(ALICE);
    {
        // Place a sell order for 333 units (approximately 1/3 of 1000)
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            333 * constants::float_scaling(), // quantity (1/3 of 1000)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );
    };

    // Step 3: Test settle_user_fees with precise proportional calculations
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Original order: 1000 units, filled: 333 units, unfilled: 667 units
        // Proportional fees: 999 * (667/1000) = 999 * 0.667 = 666.333 -> 666 (rounded down)
        assert_eq!(settled_coin.value(), 666u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun boundary_value_testing() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order and add large unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        // Place a limit order
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            10_000_000_000_000u64, // 10 trillion quantity - large order
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add very large unsettled fees
        let fee_amount = 10_000_000_000_000u64; // 10 trillion fee amount
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Test settle_user_fees with large values
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Test settle_user_fees with large values (tests near overflow boundary)
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Should return all fees since order is unfilled
        assert_eq!(settled_coin.value(), 10_000_000_000_000u64);

        // Clean up
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = unsettled_fees::EInvalidOwner)]
fun unauthorized_user_cannot_settle_fees() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: ALICE places order and adds unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );

        let fee_amount = 1000u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: OWNER (different user) tries to settle ALICE's fees - should fail
    scenario.next_tx(OWNER);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // This should fail with EInvalidOwner since OWNER != ALICE
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun repeated_settlement_attempts_return_zero() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );

        let fee_amount = 1000u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: First settlement - should return fees
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Should return all fees since order is unfilled
        assert_eq!(settled_coin.value(), 1000u64);

        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    // Step 3: Second settlement - should return zero
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Should return zero since fees were already settled
        assert_eq!(settled_coin.value(), 0u64);

        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun settlement_with_minimal_maker_quantity() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place very small order and add relatively large fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            constants::float_scaling(), // Very small quantity (1 unit)
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );

        // Add large fees relative to the small order
        let fee_amount = 1000000u64; // 1M fee units for 1 unit order
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Test settlement with minimal maker quantity
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Should return all fees since order is unfilled
        // Tests integer division edge case with small denominator
        assert_eq!(settled_coin.value(), 1000000u64);

        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = deepbook::big_vector::ENotFound)]
fun user_loses_fees_when_cancelling_order_directly() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );

        let fee_amount = 1000u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: User cancels order directly through DeepBook (bypassing wrapper protocol)
    // This is the "wrong" way - user should use cancel_order_and_settle_fees instead
    scenario.next_tx(ALICE);
    {
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();

        let trade_proof = balance_manager.generate_proof_as_owner(scenario.ctx());
        pool.cancel_order(&mut balance_manager, &trade_proof, order_id, &clock, scenario.ctx());

        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    // Step 3: Try to settle fees after direct cancellation
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Design: When users cancel orders directly (bypassing wrapper), they lose their fees
        // The protocol will settle these fees later via settle_protocol_fee_and_record
        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // This line should never be reached - the function should fail above
        // User cannot recover fees after direct cancellation - they are lost
        // The 1000u64 in unsettled fees remain in wrapper until protocol settles them
        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun settlement_with_different_fee_coin_type() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Test settlement with USDC fees (different from SUI)
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );

        // Add USDC fees instead of SUI
        let fee_amount = 500u64;
        let fee_balance = balance::create_for_testing<USDC>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Test settlement with USDC fee coin type
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        let settled_coin = settle_user_fees<SUI, USDC, USDC>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        assert_eq!(settled_coin.value(), 500u64);
        destroy(settled_coin);

        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
fun settlement_with_maximum_precision_amounts() {
    let (mut scenario, pool_id, balance_manager_id) = setup_test_environment();

    // Step 1: Place order with maximum precision values
    scenario.next_tx(ALICE);
    let order_id = {
        let mut wrapper = scenario.take_shared<Wrapper>();

        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            999_999_999_000u64, // Near maximum safe value (multiple of lot_size 1000)
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );

        let fee_amount = 999_999_999_000u64; // Near maximum safe value
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        add_unsettled_fee(&mut wrapper, fee_balance, &order_info);

        let order_id = order_info.order_id();
        return_shared(wrapper);
        order_id
    };

    // Step 2: Test settlement with maximum precision
    scenario.next_tx(ALICE);
    {
        let mut wrapper = scenario.take_shared<Wrapper>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        let settled_coin = settle_user_fees<SUI, USDC, SUI>(
            &mut wrapper,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Should return all fees since order is unfilled
        assert_eq!(settled_coin.value(), 999_999_999_000u64);

        destroy(settled_coin);
        return_shared(wrapper);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

// === Helper Functions ===

/// Sets up a complete test environment with wrapper and deepbook infrastructure.
/// Returns (scenario, pool_id, balance_manager_id) ready for testing.
///
/// This common setup will be reused across all settle_user_fees tests:
/// - Initializes wrapper with init_for_testing
/// - Creates deepbook registry and clock
/// - Creates funded balance manager for ALICE
/// - Creates SUI/USDC pool with reference DEEP pricing
public(package) fun setup_test_environment(): (Scenario, ID, ID) {
    let mut scenario = begin(OWNER);

    // Setup wrapper
    scenario.next_tx(OWNER);
    {
        wrapper::init_for_testing(scenario.ctx());
    };

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );
    let pool_id = setup_pool_with_default_fees_and_reference_pool<SUI, USDC, SUI, DEEP>(
        ALICE,
        registry_id,
        balance_manager_id,
        &mut scenario,
    );

    (scenario, pool_id, balance_manager_id)
}
