module deepbook_wrapper::wrapper;

use deepbook::balance_manager::BalanceManager;
use deepbook::constants::{live, partially_filled};
use deepbook::order_info::OrderInfo;
use deepbook::pool::Pool;
use deepbook_wrapper::admin::AdminCap;
use deepbook_wrapper::helper::current_version;
use deepbook_wrapper::math;
use deepbook_wrapper::ticket::{
    AdminTicket,
    validate_ticket,
    destroy_ticket,
    withdraw_coverage_fee_ticket_type,
    withdraw_protocol_fee_ticket_type,
    withdraw_deep_reserves_ticket_type
};
use multisig::multisig;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use sui::vec_set::{Self, VecSet};
use token::deep::DEEP;

// === Errors ===
/// Error when trying to use deep from reserves but there is not enough available
const EInsufficientDeepReserves: u64 = 1;

/// Allowed versions management errors
const EVersionAlreadyEnabled: u64 = 2;
const ECannotDisableCurrentVersion: u64 = 3;
const EVersionNotEnabled: u64 = 4;

/// Error when trying to use shared object in a package whose version is not enabled
const EPackageVersionNotEnabled: u64 = 5;

/// Error when the sender is not a multisig address
const ESenderIsNotMultisig: u64 = 6;

/// Error when the caller is not the owner of the balance manager
const EInvalidOwner: u64 = 7;

/// Error when the order status is not live or partially filled when joining unsettled fee
const EOrderNotLiveOrPartiallyFilled: u64 = 8;

/// Error when the order is fully executed when joining unsettled fee
const EOrderFullyExecuted: u64 = 9;

/// Error when trying to add an unsettled fee with zero value
const EZeroUnsettledFee: u64 = 10;

/// Error when the order params mismatch on joining unsettled fee
const EOrderParamsMismatch: u64 = 11;

/// Error when the maker quantity is zero on claiming an unsettled fee
const EZeroMakerQuantity: u64 = 12;

/// Error when the filled quantity is greater than the original order quantity on claiming an unsettled fee
const EFilledQuantityGreaterThanOrderQuantity: u64 = 13;

/// Error when the unsettled fee is not empty to be destroyed
const EUnsettledFeeNotEmpty: u64 = 14;

// === Structs ===
/// Wrapper struct for DeepBook V3
public struct Wrapper has key, store {
    id: UID,
    allowed_versions: VecSet<u16>,
    deep_reserves: Balance<DEEP>,
    deep_reserves_coverage_fees: Bag,
    protocol_fees: Bag,
    unsettled_fees: Bag,
}

/// Key struct for storing unsettled fees by pool, balance manager, and order id
public struct UnsettledFeeKey has copy, drop, store {
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
}

// === Events ===
public struct UnsettledFeeAdded has copy, drop {
    key: UnsettledFeeKey,
    fee_value: u64,
    order_quantity: u64,
    maker_quantity: u64,
}

public struct UserFeesSettled has copy, drop {
    key: UnsettledFeeKey,
    fee_value: u64,
    order_quantity: u64,
    maker_quantity: u64,
    filled_quantity: u64,
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

/// Key struct for storing charged fees by coin type
public struct ChargedFeeKey<phantom CoinType> has copy, drop, store {
    dummy_field: bool,
}

// === Public-Mutative Functions ===
/// Join DEEP coins into the wrapper's reserves
public fun join(wrapper: &mut Wrapper, deep_coin: Coin<DEEP>) {
    wrapper.verify_version();
    wrapper.deep_reserves.join(deep_coin.into_balance());
}

/// Withdraw deep reserves coverage fees for a specific coin type while verifying that the sender is the expected
/// multi-sig address. Performs timelock validation using an admin ticket.
///
/// Parameters:
/// - wrapper: Wrapper object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - _admin: Admin capability
/// - pks: Vector of public keys of the signers
/// - weights: Vector of weights for each corresponding signer (must match pks length)
/// - threshold: Minimum sum of weights required to authorize transactions
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<CoinType>: All coverage fees of the specified type, or zero coin if none exist
///
/// Aborts:
/// - With ESenderIsNotMultisig if the transaction sender is not the expected multi-signature address
///   derived from the provided pks, weights, and threshold parameters
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_deep_reserves_coverage_fee<CoinType>(
    wrapper: &mut Wrapper,
    ticket: AdminTicket,
    _admin: &AdminCap,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<CoinType> {
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );
    wrapper.verify_version();
    validate_ticket(&ticket, withdraw_coverage_fee_ticket_type(), clock, ctx);

    // Consume ticket after successful validation
    destroy_ticket(ticket);

    let key = ChargedFeeKey<CoinType> { dummy_field: false };

    if (wrapper.deep_reserves_coverage_fees.contains(key)) {
        let balance = wrapper.deep_reserves_coverage_fees.borrow_mut(key);
        balance::withdraw_all(balance).into_coin(ctx)
    } else {
        coin::zero(ctx)
    }
}

/// Withdraw protocol fees for a specific coin type while verifying that the sender is the expected
/// multi-sig address. Performs timelock validation using an admin ticket.
///
/// Parameters:
/// - wrapper: Wrapper object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - _admin: Admin capability
/// - pks: Vector of public keys of the multi-sig signers
/// - weights: Vector of weights for each corresponding signer (must match pks length)
/// - threshold: Minimum sum of weights required to authorize transactions
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<CoinType>: All protocol fees of the specified type, or zero coin if none exist
///
/// Aborts:
/// - With ESenderIsNotMultisig if the transaction sender is not the expected multi-signature address
///   derived from the provided pks, weights, and threshold parameters
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_protocol_fee<CoinType>(
    wrapper: &mut Wrapper,
    ticket: AdminTicket,
    _admin: &AdminCap,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<CoinType> {
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );
    wrapper.verify_version();
    validate_ticket(&ticket, withdraw_protocol_fee_ticket_type(), clock, ctx);

    // Consume ticket after successful validation
    destroy_ticket(ticket);

    let key = ChargedFeeKey<CoinType> { dummy_field: false };

    if (wrapper.protocol_fees.contains(key)) {
        let balance = wrapper.protocol_fees.borrow_mut(key);
        balance::withdraw_all(balance).into_coin(ctx)
    } else {
        coin::zero(ctx)
    }
}

/// Withdraw a specified amount of DEEP coins from the wrapper's reserves while verifying that the sender
/// is the expected multi-sig address. Performs timelock validation using an admin ticket
///
/// Parameters:
/// - wrapper: Wrapper object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - _admin: Admin capability
/// - amount: Amount of DEEP tokens to withdraw
/// - pks: Vector of public keys of the multi-sig signers
/// - weights: Vector of weights for each corresponding signer (must match pks length)
/// - threshold: Minimum sum of weights required to authorize transactions
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<DEEP>: The requested amount of DEEP tokens withdrawn from reserves
///
/// Aborts:
/// - With ESenderIsNotMultisig if the transaction sender is not the expected multi-signature address
///   derived from the provided pks, weights, and threshold parameters
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_deep_reserves(
    wrapper: &mut Wrapper,
    ticket: AdminTicket,
    _admin: &AdminCap,
    amount: u64,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<DEEP> {
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );
    wrapper.verify_version();
    validate_ticket(&ticket, withdraw_deep_reserves_ticket_type(), clock, ctx);

    // Consume ticket after successful validation
    destroy_ticket(ticket);

    wrapper.deep_reserves.split(amount).into_coin(ctx)
}

/// Settle remaining unsettled fees to the protocol for orders that are no longer live
///
/// This method transfers any remaining unsettled fees to the protocol when an order becomes
/// ineligible for user fee settlement. See `docs/unsettled-fees.md` for detailed explanation
/// of the unsettled fees system.
///
/// The method silently returns if:
/// - The order is still live (in open orders)
/// - No unsettled fees exist for the order
public fun settle_protocol_fees<BaseToken, QuoteToken, FeeCoinType>(
    wrapper: &mut Wrapper,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
) {
    let open_orders = pool.account_open_orders(balance_manager);

    // Don't settle fees to protocol while the order is live
    if (open_orders.contains(&order_id)) return;

    // We settle the fees to protocol if the order is not live, meaning it's cancelled/filled
    let unsettled_fee_key = UnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    if (!wrapper.unsettled_fees.contains(unsettled_fee_key)) return;

    let mut unsettled_fee: UnsettledFee<FeeCoinType> = wrapper
        .unsettled_fees
        .remove(unsettled_fee_key);
    let unsettled_fee_balance = unsettled_fee.balance.withdraw_all();
    join_protocol_fee(wrapper, unsettled_fee_balance);
    unsettled_fee.destroy_empty();
}

/// Enable the specified package version for the wrapper verifying that the sender is the expected multi-sig address
///
/// Parameters:
/// - wrapper: Wrapper object
/// - _admin: Admin capability
/// - version: Package version to enable
/// - pks: Vector of public keys of the multi-sig signers
/// - weights: Vector of weights for each corresponding signer (must match pks length)
/// - threshold: Minimum sum of weights required to authorize transactions
/// - ctx: Mutable transaction context for sender verification
///
/// Aborts:
/// - With ESenderIsNotMultisig if the transaction sender is not the expected multi-signature address
///   derived from the provided pks, weights, and threshold parameters
/// - With EVersionAlreadyEnabled if the version is already enabled
public fun enable_version(
    wrapper: &mut Wrapper,
    _admin: &AdminCap,
    version: u16,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );
    assert!(!wrapper.allowed_versions.contains(&version), EVersionAlreadyEnabled);
    wrapper.allowed_versions.insert(version);
}

/// Disable the specified package version for the wrapper verifying that the sender is the expected multi-sig address
///
/// Parameters:
/// - wrapper: Wrapper object
/// - _admin: Admin capability
/// - version: Package version to disable
/// - pks: Vector of public keys of the multi-sig signers
/// - weights: Vector of weights for each corresponding signer (must match pks length)
/// - threshold: Minimum sum of weights required to authorize transactions
/// - ctx: Mutable transaction context for sender verification
///
/// Aborts:
/// - With ESenderIsNotMultisig if the transaction sender is not the expected multi-signature address
///   derived from the provided pks, weights, and threshold parameters
/// - With ECannotDisableCurrentVersion if trying to disable the current version
/// - With EVersionNotEnabled if the version is not currently enabled
public fun disable_version(
    wrapper: &mut Wrapper,
    _admin: &AdminCap,
    version: u16,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );
    assert!(version != current_version(), ECannotDisableCurrentVersion);
    assert!(wrapper.allowed_versions.contains(&version), EVersionNotEnabled);
    wrapper.allowed_versions.remove(&version);
}

// === Public-View Functions ===
/// Get the value of DEEP in the reserves
public fun deep_reserves(wrapper: &Wrapper): u64 {
    wrapper.deep_reserves.value()
}

// === Public-Package Functions ===
/// Add collected deep reserves coverage fees to the wrapper's fee storage
public(package) fun join_deep_reserves_coverage_fee<CoinType>(
    wrapper: &mut Wrapper,
    fee: Balance<CoinType>,
) {
    wrapper.verify_version();

    if (fee.value() == 0) {
        fee.destroy_zero();
        return
    };

    let key = ChargedFeeKey<CoinType> { dummy_field: false };
    if (wrapper.deep_reserves_coverage_fees.contains(key)) {
        let balance = wrapper.deep_reserves_coverage_fees.borrow_mut(key);
        balance::join(balance, fee);
    } else {
        wrapper.deep_reserves_coverage_fees.add(key, fee);
    };
}

/// Add collected protocol fees to the wrapper's fee storage
public(package) fun join_protocol_fee<CoinType>(wrapper: &mut Wrapper, fee: Balance<CoinType>) {
    wrapper.verify_version();

    if (fee.value() == 0) {
        fee.destroy_zero();
        return
    };

    let key = ChargedFeeKey<CoinType> { dummy_field: false };
    if (wrapper.protocol_fees.contains(key)) {
        let balance = wrapper.protocol_fees.borrow_mut(key);
        balance::join(balance, fee);
    } else {
        wrapper.protocol_fees.add(key, fee);
    };
}

/// Add unsettled fee for a specific order
///
/// This function stores fees that will be settled later based on order execution outcome.
/// It validates the order state and either creates a new unsettled fee or joins to an existing one.
///
/// Key validations:
/// - Order must be live or partially filled (not cancelled/filled/expired)
/// - Order must not be fully executed (must have remaining maker quantity)
/// - Fee amount must be greater than zero
/// - For existing unsettled fees: order parameters must match (prevents tampering)
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

    // Order must be not fully executed to have unsettled fee
    let order_quantity = order_info.original_quantity();
    let executed_quantity = order_info.executed_quantity();
    assert!(executed_quantity < order_quantity, EOrderFullyExecuted);

    // Fee must be not zero to be added
    let fee_value = fee.value();
    assert!(fee_value > 0, EZeroUnsettledFee);

    let unsettled_fee_key = UnsettledFeeKey {
        pool_id: order_info.pool_id(),
        balance_manager_id: order_info.balance_manager_id(),
        order_id: order_info.order_id(),
    };
    let maker_quantity = order_quantity - executed_quantity;

    if (wrapper.unsettled_fees.contains(unsettled_fee_key)) {
        // If the order already has an unsettled fee
        let existing_unsettled_fee: &mut UnsettledFee<CoinType> = wrapper
            .unsettled_fees
            .borrow_mut(unsettled_fee_key);

        // Verify order has the same params. Since we join the unsettled fees only on order creation,
        // the order params should not change
        let existing_order_quantity = existing_unsettled_fee.order_quantity;
        let existing_maker_quantity = existing_unsettled_fee.maker_quantity;
        assert!(
            existing_order_quantity == order_quantity && existing_maker_quantity == maker_quantity,
            EOrderParamsMismatch,
        );

        // Add the balance to the existing unsettled fee
        existing_unsettled_fee.balance.join(fee);
    } else {
        // If the order doesn't have an unsettled fee, create the new one
        let new_unsettled_fee = UnsettledFee<CoinType> {
            balance: fee,
            order_quantity,
            maker_quantity,
        };
        wrapper.unsettled_fees.add(unsettled_fee_key, new_unsettled_fee);
    };

    event::emit(UnsettledFeeAdded {
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
    // Verify the caller owns the balance manager
    assert!(balance_manager.owner() == ctx.sender(), EInvalidOwner);

    let unsettled_fee_key = UnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    if (!wrapper.unsettled_fees.contains(unsettled_fee_key)) {
        return coin::zero(ctx)
    };

    let unsettled_fee: &mut UnsettledFee<FeeCoinType> = wrapper
        .unsettled_fees
        .borrow_mut(unsettled_fee_key);
    let order = pool.get_order(order_id);
    let unsettled_fee_value = unsettled_fee.balance.value();
    let order_quantity = unsettled_fee.order_quantity;
    let maker_quantity = unsettled_fee.maker_quantity;
    let filled_quantity = order.filled_quantity();

    // Clean up unsettled fee if it doesn't have any value
    if (unsettled_fee_value == 0) {
        let unsettled_fee: UnsettledFee<FeeCoinType> = wrapper
            .unsettled_fees
            .remove(unsettled_fee_key);
        unsettled_fee.destroy_empty();
        return coin::zero(ctx)
    };

    assert!(maker_quantity > 0, EZeroMakerQuantity);
    assert!(filled_quantity <= order_quantity, EFilledQuantityGreaterThanOrderQuantity);

    let not_executed_quantity = order_quantity - filled_quantity;
    let amount_to_settle = math::div(
        math::mul(unsettled_fee_value, not_executed_quantity),
        maker_quantity,
    );

    let fee_to_settle = unsettled_fee.balance.split(amount_to_settle);
    let fee_value = fee_to_settle.value();

    if (unsettled_fee.balance.value() == 0) {
        let unsettled_fee: UnsettledFee<FeeCoinType> = wrapper
            .unsettled_fees
            .remove(unsettled_fee_key);
        unsettled_fee.destroy_empty();
    };

    if (fee_value > 0) {
        event::emit(UserFeesSettled {
            key: unsettled_fee_key,
            fee_value,
            order_quantity,
            maker_quantity,
            filled_quantity,
        });
    };

    fee_to_settle.into_coin(ctx)
}

/// Get the splitted DEEP coin from the reserves
public(package) fun split_deep_reserves(
    wrapper: &mut Wrapper,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEEP> {
    wrapper.verify_version();

    let available_deep_reserves = wrapper.deep_reserves.value();
    assert!(amount <= available_deep_reserves, EInsufficientDeepReserves);

    wrapper.deep_reserves.split(amount).into_coin(ctx)
}

/// Verify that the current package version is enabled in the wrapper
public(package) fun verify_version(wrapper: &Wrapper) {
    let package_version = current_version();
    assert!(wrapper.allowed_versions.contains(&package_version), EPackageVersionNotEnabled);
}

// === Private Functions ===
/// Initialize the wrapper module
fun init(ctx: &mut TxContext) {
    let wrapper = Wrapper {
        id: object::new(ctx),
        allowed_versions: vec_set::singleton(current_version()),
        deep_reserves: balance::zero(),
        deep_reserves_coverage_fees: bag::new(ctx),
        protocol_fees: bag::new(ctx),
        unsettled_fees: bag::new(ctx),
    };

    // Share the wrapper object
    transfer::share_object(wrapper);
}

/// Destroy the empty unsettled fee
fun destroy_empty<CoinType>(unsettled_fee: UnsettledFee<CoinType>) {
    assert!(unsettled_fee.balance.value() == 0, EUnsettledFeeNotEmpty);

    let UnsettledFee { balance, .. } = unsettled_fee;
    balance::destroy_zero(balance);
}
