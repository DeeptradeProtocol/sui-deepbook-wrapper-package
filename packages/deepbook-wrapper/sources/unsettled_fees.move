module deepbook_wrapper::unsettled_fees;

use deepbook::balance_manager::BalanceManager;
use deepbook::constants::{live, partially_filled};
use deepbook::order_info::OrderInfo;
use deepbook::pool::Pool;
use deepbook_wrapper::math;
use deepbook_wrapper::wrapper::{Wrapper, join_protocol_fee};
use sui::balance::Balance;
use sui::coin::{Self, Coin};
use sui::event;

// === Errors ===
/// Error when the caller is not the owner of the balance manager
const EInvalidOwner: u64 = 1;
const EOrderNotLiveOrPartiallyFilled: u64 = 2;
const EOrderFullyExecuted: u64 = 3;
/// Error when trying to add an unsettled fee with zero value
const EZeroUnsettledFee: u64 = 4;
/// Error when the order already has an unsettled fee
const EUnsettledFeeAlreadyExists: u64 = 5;
/// Error when the maker quantity is zero on settling user fees
const EZeroMakerQuantity: u64 = 6;
/// Error when the filled quantity is greater than the original order quantity on settling user fees
const EFilledQuantityGreaterThanOrderQuantity: u64 = 7;
/// Error when the unsettled fee is not empty to be destroyed
const EUnsettledFeeNotEmpty: u64 = 8;

// === Structs ===
/// Key struct for storing unsettled fees by pool, balance manager, and order id
public struct UnsettledFeeKey has copy, drop, store {
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
}

/// Unsettled fee for specific order
/// See `docs/unsettled-fees.md` for detailed explanation of the unsettled fees system.
public struct UnsettledFee<phantom CoinType> has store {
    /// Fee balance
    balance: Balance<CoinType>,
    order_quantity: u64,
    /// Maker quantity this fee balance corresponds to
    maker_quantity: u64,
}

/// A temporary receipt for aggregating batch fee settlement results
public struct FeeSettlementReceipt<phantom FeeCoinType> {
    orders_count: u64,
    total_fees_settled: u64,
}

// === Events ===
public struct UnsettledFeeAdded<phantom CoinType> has copy, drop {
    key: UnsettledFeeKey,
    fee_value: u64,
    order_quantity: u64,
    maker_quantity: u64,
}

public struct UserFeesSettled<phantom CoinType> has copy, drop {
    key: UnsettledFeeKey,
    fee_value: u64,
    order_quantity: u64,
    maker_quantity: u64,
    filled_quantity: u64,
}

public struct ProtocolFeesSettled<phantom FeeCoinType> has copy, drop {
    orders_count: u64,
    total_fees_settled: u64,
}

// === Public-Mutative Functions ===
/// Start the protocol fee settlement process for a specific coin by creating a FeeSettlementReceipt
public fun start_protocol_fee_settlement<FeeCoinType>(): FeeSettlementReceipt<FeeCoinType> {
    FeeSettlementReceipt {
        orders_count: 0,
        total_fees_settled: 0,
    }
}

/// Settles remaining unsettled fees to the protocol for orders that are no longer live
/// (i.e., cancelled or filled) and records the result in a `FeeSettlementReceipt`.
/// See `docs/unsettled-fees.md` for a detailed explanation of the unsettled fees system.
///
/// The function silently returns if:
/// - The order is still live (i.e., present in the account's open orders).
/// - No unsettled fees exist for the order.
public fun settle_protocol_fee_and_record<BaseToken, QuoteToken, FeeCoinType>(
    wrapper: &mut Wrapper,
    receipt: &mut FeeSettlementReceipt<FeeCoinType>,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
) {
    wrapper.verify_version();

    let unsettled_fees = wrapper.unsettled_fees_mut();
    let open_orders = pool.account_open_orders(balance_manager);

    // Don't settle fees to protocol while the order is live
    if (open_orders.contains(&order_id)) return;

    let unsettled_fee_key = UnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    if (!unsettled_fees.contains(unsettled_fee_key)) return;

    let mut unsettled_fee: UnsettledFee<FeeCoinType> = unsettled_fees.remove(unsettled_fee_key);
    let unsettled_fee_balance = unsettled_fee.balance.withdraw_all();

    // Update receipt with settled fee details
    let settled_amount = unsettled_fee_balance.value();
    if (settled_amount > 0) {
        receipt.orders_count = receipt.orders_count + 1;
        receipt.total_fees_settled = receipt.total_fees_settled + settled_amount;
    };

    join_protocol_fee(wrapper, unsettled_fee_balance);
    unsettled_fee.destroy_empty();
}

/// Finalize the protocol fee settlement process, emitting an event with the total settled amount
public fun finish_protocol_fee_settlement<FeeCoinType>(receipt: FeeSettlementReceipt<FeeCoinType>) {
    if (receipt.total_fees_settled > 0) {
        event::emit(ProtocolFeesSettled<FeeCoinType> {
            orders_count: receipt.orders_count,
            total_fees_settled: receipt.total_fees_settled,
        });
    };

    // Destroy the receipt object
    let FeeSettlementReceipt { .. } = receipt;
}

// === Public-Package Functions ===
/// Add unsettled fee for a specific order
///
/// This function stores fees that will be settled later based on order execution outcome.
/// It validates the order state and creates a new unsettled fee for the order.
///
/// Key validations:
/// - Order must be live or partially filled (not cancelled/filled/expired)
/// - Order must not be fully executed (must have remaining maker quantity)
/// - Fee amount must be greater than zero
/// - Order must not already have an unsettled fee (one-time addition only)
///
/// See `docs/unsettled-fees.md` for detailed explanation of the unsettled fees system.
public(package) fun add_unsettled_fee<CoinType>(
    wrapper: &mut Wrapper,
    fee: Balance<CoinType>,
    order_info: &OrderInfo,
) {
    wrapper.verify_version();

    // Order must be live or partially filled to have unsettled fee
    let order_status = order_info.status();
    assert!(
        order_status == live() || order_status == partially_filled(),
        EOrderNotLiveOrPartiallyFilled,
    );

    // Sanity check: order must not be fully executed to have an unsettled fee. If the order is
    // fully executed but still has live or partially filled status, there's an error in DeepBook logic.
    let order_quantity = order_info.original_quantity();
    let executed_quantity = order_info.executed_quantity();
    assert!(executed_quantity < order_quantity, EOrderFullyExecuted);

    // Fee must be not zero to be added
    let fee_value = fee.value();
    assert!(fee_value > 0, EZeroUnsettledFee);

    let unsettled_fees = wrapper.unsettled_fees_mut();
    let unsettled_fee_key = UnsettledFeeKey {
        pool_id: order_info.pool_id(),
        balance_manager_id: order_info.balance_manager_id(),
        order_id: order_info.order_id(),
    };
    let maker_quantity = order_quantity - executed_quantity;

    // Verify the order doesn't have an unsettled fee yet
    assert!(!unsettled_fees.contains(unsettled_fee_key), EUnsettledFeeAlreadyExists);

    // Create the unsettled fee
    let unsettled_fee = UnsettledFee<CoinType> {
        balance: fee,
        order_quantity,
        maker_quantity,
    };
    unsettled_fees.add(unsettled_fee_key, unsettled_fee);

    event::emit(UnsettledFeeAdded<CoinType> {
        key: unsettled_fee_key,
        fee_value,
        order_quantity,
        maker_quantity,
    });
}

/// Settle unsettled fees back to the user for unfilled portions of their order
///
/// Returns fees proportional to the unfilled portion of the user's order.
/// Only the balance manager owner can claim fees for their orders.
///
/// Returns zero coin if no unsettled fees exist or balance is zero.
///
/// See `docs/unsettled-fees.md` for detailed explanation of the unsettled fees system.
public(package) fun settle_user_fees<BaseToken, QuoteToken, FeeCoinType>(
    wrapper: &mut Wrapper,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
    ctx: &mut TxContext,
): Coin<FeeCoinType> {
    wrapper.verify_version();

    // Verify the caller owns the balance manager
    assert!(balance_manager.owner() == ctx.sender(), EInvalidOwner);

    let unsettled_fees = wrapper.unsettled_fees_mut();
    let unsettled_fee_key = UnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    if (!unsettled_fees.contains(unsettled_fee_key)) return coin::zero(ctx);

    let unsettled_fee: &mut UnsettledFee<FeeCoinType> = unsettled_fees.borrow_mut(
        unsettled_fee_key,
    );
    let order = pool.get_order(order_id);
    let unsettled_fee_value = unsettled_fee.balance.value();
    let order_quantity = unsettled_fee.order_quantity;
    let maker_quantity = unsettled_fee.maker_quantity;
    let filled_quantity = order.filled_quantity();

    // Clean up unsettled fee if it has zero value. This should never happen because we don't
    // add zero-value fees and we clean them up when they are fully settled.
    if (unsettled_fee_value == 0) {
        let unsettled_fee: UnsettledFee<FeeCoinType> = unsettled_fees.remove(unsettled_fee_key);
        unsettled_fee.destroy_empty();
        return coin::zero(ctx)
    };

    // Sanity check: maker quantity must be greater than zero. If it's zero, the unsettled fee
    // should not have been added. We validate this during fee addition, so this should never occur.
    assert!(maker_quantity > 0, EZeroMakerQuantity);
    // Sanity check: filled quantity must be less than total order quantity. If they are equal,
    // the order is fully executed and the `pool.get_order` call above should abort. If filled
    // quantity exceeds total order quantity, there's an error in either the unsettled fees
    // mechanism or DeepBook's order filling logic.
    assert!(filled_quantity < order_quantity, EFilledQuantityGreaterThanOrderQuantity);

    let amount_to_settle = if (filled_quantity == 0) {
        // If the order is completely unfilled, return all fees
        unsettled_fee_value
    } else {
        let not_executed_quantity = order_quantity - filled_quantity;
        math::div(
            math::mul(unsettled_fee_value, not_executed_quantity),
            maker_quantity,
        )
    };

    let fee_to_settle = unsettled_fee.balance.split(amount_to_settle);

    if (unsettled_fee.balance.value() == 0) {
        let unsettled_fee: UnsettledFee<FeeCoinType> = unsettled_fees.remove(unsettled_fee_key);
        unsettled_fee.destroy_empty();
    };

    event::emit(UserFeesSettled<FeeCoinType> {
        key: unsettled_fee_key,
        fee_value: amount_to_settle,
        order_quantity,
        maker_quantity,
        filled_quantity,
    });

    fee_to_settle.into_coin(ctx)
}

// === Private Functions ===
/// Destroy the empty unsettled fee
fun destroy_empty<CoinType>(unsettled_fee: UnsettledFee<CoinType>) {
    assert!(unsettled_fee.balance.value() == 0, EUnsettledFeeNotEmpty);

    let UnsettledFee { balance, .. } = unsettled_fee;
    balance.destroy_zero();
}

// === Test Functions ===
/// Check if an unsettled fee exists for a specific order
#[test_only]
public fun has_unsettled_fee<CoinType>(
    wrapper: &Wrapper,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): bool {
    let unsettled_fees = wrapper.unsettled_fees();
    let key = UnsettledFeeKey { pool_id, balance_manager_id, order_id };
    unsettled_fees.contains_with_type<UnsettledFeeKey, UnsettledFee<CoinType>>(key)
}

/// Get the unsettled fee balance for a specific order
#[test_only]
public fun get_unsettled_fee_balance<CoinType>(
    wrapper: &Wrapper,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): u64 {
    let unsettled_fees = wrapper.unsettled_fees();
    let key = UnsettledFeeKey { pool_id, balance_manager_id, order_id };
    let unsettled_fee: &UnsettledFee<CoinType> = unsettled_fees.borrow(key);
    unsettled_fee.balance.value()
}

/// Get the order parameters stored in an unsettled fee
#[test_only]
public fun get_unsettled_fee_order_params<CoinType>(
    wrapper: &Wrapper,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): (u64, u64) {
    let unsettled_fees = wrapper.unsettled_fees();
    let key = UnsettledFeeKey { pool_id, balance_manager_id, order_id };
    let unsettled_fee: &UnsettledFee<CoinType> = unsettled_fees.borrow(key);
    (unsettled_fee.order_quantity, unsettled_fee.maker_quantity)
}

/// Finalize the protocol fee settlement process and return the result for testing
#[test_only]
public fun finish_protocol_fee_settlement_for_testing<FeeCoinType>(
    receipt: FeeSettlementReceipt<FeeCoinType>,
): (u64, u64) {
    let count = receipt.orders_count;
    let total = receipt.total_fees_settled;
    finish_protocol_fee_settlement(receipt);
    (count, total)
}
