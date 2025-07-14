module deepbook_wrapper::wrapper;

use deepbook_wrapper::admin::AdminCap;
use deepbook_wrapper::helper::current_version;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;
use sui::vec_set::{Self, VecSet};
use token::deep::DEEP;

// === Errors ===
/// Error when trying to use a fund capability with a different wrapper than it was created for
const EInvalidFundCap: u64 = 1;

/// Error when trying to use deep from reserves but there is not enough available
const EInsufficientDeepReserves: u64 = 2;

/// Allowed versions management errors
const EVersionAlreadyEnabled: u64 = 3;
const ECannotDisableCurrentVersion: u64 = 4;
const EVersionNotEnabled: u64 = 5;

/// Error when trying to use shared object in a package whose version is not enabled
const EPackageVersionNotEnabled: u64 = 6;

/// Error when trying to enable a version that has been permanently disabled
const EVersionPermanentlyDisabled: u64 = 7;

/// A generic error code for any function that is no longer supported.
/// The value 1000 is used by convention across modules for this purpose.
#[allow(unused_const)]
const EFunctionDeprecated: u64 = 1000;

// === Structs ===
/// Wrapper struct for DeepBook V3
/// - allowed_versions: Versions that are allowed to interact with the wrapper
/// - disabled_versions: Versions that have been permanently disabled
/// - deep_reserves: The DEEP reserves in the wrapper
/// - deep_reserves_coverage_fees: The DEEP reserves coverage fees collected by the wrapper
/// - protocol_fees: The protocol fees collected by the wrapper
public struct Wrapper has key, store {
    id: UID,
    allowed_versions: VecSet<u16>,
    disabled_versions: VecSet<u16>,
    deep_reserves: Balance<DEEP>,
    deep_reserves_coverage_fees: Bag,
    protocol_fees: Bag,
}

/// Capability for managing funds in the wrapper
public struct FundCap has key, store {
    id: UID,
    wrapper_id: ID,
}

/// Key struct for storing charged fees by coin type
public struct ChargedFeeKey<phantom CoinType> has copy, drop, store {}

// === Events ===
/// Event emitted when DEEP coins are withdrawn from the wrapper's reserves
public struct DeepReservesWithdrawn has copy, drop {
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

// === Public-Mutative Functions ===
/// Create a new fund capability for the wrapper
public fun create_fund_cap(wrapper: &Wrapper, _admin: &AdminCap, ctx: &mut TxContext): FundCap {
    FundCap {
        id: object::new(ctx),
        wrapper_id: wrapper.id.to_inner(),
    }
}

/// Join DEEP coins into the wrapper's reserves
public fun join(wrapper: &mut Wrapper, deep_coin: Coin<DEEP>) {
    wrapper.verify_version();
    wrapper.deep_reserves.join(deep_coin.into_balance());
}

/// Withdraw collected deep reserves coverage fees for a specific coin type using fund capability
public fun withdraw_deep_reserves_coverage_fee<CoinType>(
    wrapper: &mut Wrapper,
    fund_cap: &FundCap,
    ctx: &mut TxContext,
): Coin<CoinType> {
    wrapper.verify_version();
    assert!(fund_cap.wrapper_id == wrapper.id.to_inner(), EInvalidFundCap);
    withdraw_deep_reserves_coverage_fee_internal(wrapper, ctx)
}

/// Withdraw collected deep reserves coverage fees for a specific coin type using admin capability
public fun admin_withdraw_deep_reserves_coverage_fee<CoinType>(
    wrapper: &mut Wrapper,
    _admin: &AdminCap,
    ctx: &mut TxContext,
): Coin<CoinType> {
    wrapper.verify_version();
    withdraw_deep_reserves_coverage_fee_internal(wrapper, ctx)
}

/// Withdraw collected protocol fees for a specific coin type using admin capability
public fun admin_withdraw_protocol_fee<CoinType>(
    wrapper: &mut Wrapper,
    _admin: &AdminCap,
    ctx: &mut TxContext,
): Coin<CoinType> {
    wrapper.verify_version();

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

/// Withdraw DEEP coins from the wrapper's reserves
public fun withdraw_deep_reserves(
    wrapper: &mut Wrapper,
    _admin: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEEP> {
    wrapper.verify_version();

    let coin = split_deep_reserves(wrapper, amount, ctx);

    event::emit(DeepReservesWithdrawn {
        wrapper_id: wrapper.id.to_inner(),
        amount,
    });

    coin
}

/// Enable the specified package version for the wrapper
public fun enable_version(wrapper: &mut Wrapper, _admin: &AdminCap, version: u16) {
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
public fun disable_version(wrapper: &mut Wrapper, _admin: &AdminCap, version: u16) {
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

// === Private Functions ===
/// Initialize the wrapper module
fun init(ctx: &mut TxContext) {
    let wrapper = Wrapper {
        id: object::new(ctx),
        allowed_versions: vec_set::singleton(current_version()),
        disabled_versions: vec_set::empty(),
        deep_reserves: balance::zero(),
        deep_reserves_coverage_fees: bag::new(ctx),
        protocol_fees: bag::new(ctx),
    };

    // Create a fund capability for the deployer
    let fund_cap = FundCap {
        id: object::new(ctx),
        wrapper_id: wrapper.id.to_inner(),
    };

    // Share the wrapper object
    transfer::share_object(wrapper);

    // Transfer the fund capability to the transaction sender
    transfer::transfer(fund_cap, ctx.sender());
}

/// Internal helper function to handle the common withdrawal logic
fun withdraw_deep_reserves_coverage_fee_internal<CoinType>(
    wrapper: &mut Wrapper,
    ctx: &mut TxContext,
): Coin<CoinType> {
    wrapper.verify_version();

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
