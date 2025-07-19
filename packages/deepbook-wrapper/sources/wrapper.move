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
const ESenderIsNotMultisig: u64 = 6;

/// Error when trying to enable a version that has been permanently disabled
const EVersionPermanentlyDisabled: u64 = 7;

// === Structs ===
/// Wrapper struct for DeepBook V3
public struct Wrapper has key, store {
    id: UID,
    allowed_versions: VecSet<u16>,
    // Permanently disabled package versions
    disabled_versions: VecSet<u16>,
    deep_reserves: Balance<DEEP>,
    deep_reserves_coverage_fees: Bag,
    protocol_fees: Bag,
    unsettled_fees: Bag,
}

/// Key struct for storing charged fees by coin type
public struct ChargedFeeKey<phantom CoinType> has copy, drop, store {}

// === Events ===
/// Event emitted when DEEP coins are withdrawn from the wrapper's reserves
public struct DeepReservesWithdrawn<phantom DEEP> has copy, drop {
    wrapper_id: ID,
    amount: u64,
}

/// Event emitted when deep reserves coverage fees are withdrawn for a specific coin type
public struct CoverageFeeWithdrawn<phantom CoinType> has copy, drop {
    wrapper_id: ID,
    amount: u64,
}

/// Event emitted when protocol fees are withdrawn for a specific coin type
public struct ProtocolFeeWithdrawn<phantom CoinType> has copy, drop {
    wrapper_id: ID,
    amount: u64,
}

/// Event emitted when DEEP coins are deposited into the wrapper's reserves
public struct DeepReservesDeposited has copy, drop {
    wrapper_id: ID,
    amount: u64,
}

/// Event emitted when a new version is enabled for the wrapper
public struct VersionEnabled has copy, drop {
    wrapper_id: ID,
    version: u16,
}

/// Event emitted when a version is permanently disabled for the wrapper
public struct VersionDisabled has copy, drop {
    wrapper_id: ID,
    version: u16,
}

fun init(ctx: &mut TxContext) {
    let wrapper = Wrapper {
        id: object::new(ctx),
        allowed_versions: vec_set::singleton(current_version()),
        disabled_versions: vec_set::empty(),
        deep_reserves: balance::zero(),
        deep_reserves_coverage_fees: bag::new(ctx),
        protocol_fees: bag::new(ctx),
        unsettled_fees: bag::new(ctx),
    };

    transfer::share_object(wrapper);
}

// === Public-Mutative Functions ===
/// Deposit DEEP coins into the wrapper's reserves
public fun deposit_into_reserves(wrapper: &mut Wrapper, deep_coin: Coin<DEEP>) {
    wrapper.verify_version();

    event::emit(DeepReservesDeposited {
        wrapper_id: wrapper.id.to_inner(),
        amount: deep_coin.value(),
    });

    wrapper.deep_reserves.join(deep_coin.into_balance());
}

/// Withdraw deep reserves coverage fees for a specific coin type
/// Performs timelock validation using an admin ticket
///
/// Parameters:
/// - wrapper: Wrapper object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<CoinType>: All coverage fees of the specified type, or zero coin if none exist
///
/// Aborts:
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_deep_reserves_coverage_fee<CoinType>(
    wrapper: &mut Wrapper,
    ticket: AdminTicket,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<CoinType> {
    wrapper.verify_version();
    validate_ticket(&ticket, withdraw_coverage_fee_ticket_type(), clock, ctx);
    destroy_ticket(ticket, clock);

    let key = ChargedFeeKey<CoinType> {};

    if (wrapper.deep_reserves_coverage_fees.contains(key)) {
        let balance = wrapper.deep_reserves_coverage_fees.borrow_mut(key);
        let coin = balance::withdraw_all(balance).into_coin(ctx);

        event::emit(CoverageFeeWithdrawn<CoinType> {
            wrapper_id: wrapper.id.to_inner(),
            amount: coin.value(),
        });

        coin
    } else {
        coin::zero(ctx)
    }
}

/// Withdraw protocol fees for a specific coin type
/// Performs timelock validation using an admin ticket
///
/// Parameters:
/// - wrapper: Wrapper object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<CoinType>: All protocol fees of the specified type, or zero coin if none exist
///
/// Aborts:
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_protocol_fee<CoinType>(
    wrapper: &mut Wrapper,
    ticket: AdminTicket,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<CoinType> {
    wrapper.verify_version();
    validate_ticket(&ticket, withdraw_protocol_fee_ticket_type(), clock, ctx);
    destroy_ticket(ticket, clock);

    let key = ChargedFeeKey<CoinType> {};

    if (wrapper.protocol_fees.contains(key)) {
        let balance = wrapper.protocol_fees.borrow_mut(key);
        let coin = balance::withdraw_all(balance).into_coin(ctx);

        event::emit(ProtocolFeeWithdrawn<CoinType> {
            wrapper_id: wrapper.id.to_inner(),
            amount: coin.value(),
        });

        coin
    } else {
        coin::zero(ctx)
    }
}

/// Withdraw a specified amount of DEEP coins from the wrapper's reserves
/// Performs timelock validation using an admin ticket
///
/// Parameters:
/// - wrapper: Wrapper object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - amount: Amount of DEEP tokens to withdraw
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<DEEP>: The requested amount of DEEP tokens withdrawn from reserves
///
/// Aborts:
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_deep_reserves(
    wrapper: &mut Wrapper,
    ticket: AdminTicket,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<DEEP> {
    wrapper.verify_version();
    validate_ticket(&ticket, withdraw_deep_reserves_ticket_type(), clock, ctx);
    destroy_ticket(ticket, clock);

    let coin = split_deep_reserves(wrapper, amount, ctx);

    event::emit(DeepReservesWithdrawn<DEEP> {
        wrapper_id: wrapper.id.to_inner(),
        amount,
    });

    coin
}

/// Enable the specified package version for the wrapper
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

    // Check if the version has been permanently disabled
    assert!(!wrapper.disabled_versions.contains(&version), EVersionPermanentlyDisabled);

    // Check if the version is already enabled
    assert!(!wrapper.allowed_versions.contains(&version), EVersionAlreadyEnabled);

    wrapper.allowed_versions.insert(version);

    event::emit(VersionEnabled {
        wrapper_id: wrapper.id.to_inner(),
        version,
    });
}

/// Permanently disable the specified package version for the wrapper
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

    // Remove from allowed and add to disabled
    wrapper.allowed_versions.remove(&version);
    wrapper.disabled_versions.insert(version);

    event::emit(VersionDisabled {
        wrapper_id: wrapper.id.to_inner(),
        version,
    });
}

// === Public-View Functions ===
/// Get the value of DEEP in the reserves
public fun deep_reserves(wrapper: &Wrapper): u64 { wrapper.deep_reserves.value() }

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

    let key = ChargedFeeKey<CoinType> {};
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

    let key = ChargedFeeKey<CoinType> {};
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

public(package) fun unsettled_fees(wrapper: &Wrapper): &Bag { &wrapper.unsettled_fees }

public(package) fun unsettled_fees_mut(wrapper: &mut Wrapper): &mut Bag {
    wrapper.verify_version();
    &mut wrapper.unsettled_fees
}

// === Test Functions ===
/// Get the protocol fee balance for a specific coin type.
#[test_only]
public fun get_protocol_fee_balance<CoinType>(wrapper: &Wrapper): u64 {
    let key = ChargedFeeKey<CoinType> {};
    if (wrapper.protocol_fees.contains(key)) {
        let balance: &Balance<CoinType> = wrapper.protocol_fees.borrow(key);
        balance.value()
    } else {
        0
    }
}

/// Initialize the wrapper module for testing
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
