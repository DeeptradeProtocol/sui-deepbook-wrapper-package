module deepbook_wrapper::wrapper;

use deepbook_wrapper::admin::AdminCap;
use deepbook_wrapper::helper::current_version;
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

// === Structs ===
/// Wrapper struct for DeepBook V3
public struct Wrapper has key, store {
    id: UID,
    allowed_versions: VecSet<u16>,
    deep_reserves: Balance<DEEP>,
    deep_reserves_coverage_fees: Bag,
    protocol_fees: Bag,
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
    };

    // Share the wrapper object
    transfer::share_object(wrapper);
}
