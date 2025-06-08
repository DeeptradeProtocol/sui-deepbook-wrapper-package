module deepbook_wrapper::wrapper;

use deepbook_wrapper::admin::AdminCap;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use token::deep::DEEP;

// === Structs ===
/// Wrapper struct for DeepBook V3
public struct Wrapper has key, store {
    id: UID,
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
public struct ChargedFeeKey<phantom CoinType> has copy, drop, store {
    dummy_field: bool,
}

// === Errors ===
/// Error when trying to use a fund capability with a different wrapper than it was created for
#[error]
const EInvalidFundCap: u64 = 1;

/// A generic error code for any function that is no longer supported.
/// The value 1000 is used by convention across modules for this purpose.
#[error]
const EFunctionDeprecated: u64 = 1000;

// === Public-Mutative Functions ===
/// Create a new fund capability for the wrapper
public fun create_fund_cap_v2(wrapper: &Wrapper, _admin: &AdminCap, ctx: &mut TxContext): FundCap {
    FundCap {
        id: object::new(ctx),
        wrapper_id: object::uid_to_inner(&wrapper.id),
    }
}

/// Join DEEP coins into the wrapper's reserves
public fun join(wrapper: &mut Wrapper, deep_coin: Coin<DEEP>) {
    balance::join(&mut wrapper.deep_reserves, deep_coin.into_balance());
}

/// Withdraw collected deep reserves coverage fees for a specific coin type using fund capability
public fun withdraw_deep_reserves_coverage_fee_v2<CoinType>(
    wrapper: &mut Wrapper,
    fund_cap: &FundCap,
    ctx: &mut TxContext,
): Coin<CoinType> {
    assert!(fund_cap.wrapper_id == object::uid_to_inner(&wrapper.id), EInvalidFundCap);
    withdraw_deep_reserves_coverage_fee_internal(wrapper, ctx)
}

/// Withdraw collected deep reserves coverage fees for a specific coin type using admin capability
public fun admin_withdraw_deep_reserves_coverage_fee_v2<CoinType>(
    wrapper: &mut Wrapper,
    _admin: &AdminCap,
    ctx: &mut TxContext,
): Coin<CoinType> {
    withdraw_deep_reserves_coverage_fee_internal(wrapper, ctx)
}

/// Withdraw collected protocol fees for a specific coin type using admin capability
public fun admin_withdraw_protocol_fee_v2<CoinType>(
    wrapper: &mut Wrapper,
    _admin: &AdminCap,
    ctx: &mut TxContext,
): Coin<CoinType> {
    let key = ChargedFeeKey<CoinType> { dummy_field: false };

    if (bag::contains(&wrapper.protocol_fees, key)) {
        coin::from_balance(
            balance::withdraw_all(wrapper.protocol_fees.borrow_mut(key)),
            ctx,
        )
    } else {
        coin::zero(ctx)
    }
}

/// Withdraw DEEP coins from the wrapper's reserves
public fun withdraw_deep_reserves_v2(
    wrapper: &mut Wrapper,
    _admin: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEEP> {
    coin::from_balance(
        balance::split(&mut wrapper.deep_reserves, amount),
        ctx,
    )
}

// === Public-View Functions ===
/// Get the value of DEEP in the reserves
public fun get_deep_reserves_value(wrapper: &Wrapper): u64 {
    balance::value(&wrapper.deep_reserves)
}

// === Public-Package Functions ===
/// Add collected deep reserves coverage fees to the wrapper's fee storage
public(package) fun join_deep_reserves_coverage_fee<CoinType>(
    wrapper: &mut Wrapper,
    fee: Balance<CoinType>,
) {
    if (balance::value(&fee) == 0) {
        balance::destroy_zero(fee);
        return
    };

    let key = ChargedFeeKey<CoinType> { dummy_field: false };
    if (bag::contains(&wrapper.deep_reserves_coverage_fees, key)) {
        balance::join(
            bag::borrow_mut(&mut wrapper.deep_reserves_coverage_fees, key),
            fee,
        );
    } else {
        bag::add(&mut wrapper.deep_reserves_coverage_fees, key, fee);
    };
}

/// Add collected protocol fees to the wrapper's fee storage
public(package) fun join_protocol_fee<CoinType>(wrapper: &mut Wrapper, fee: Balance<CoinType>) {
    if (balance::value(&fee) == 0) {
        balance::destroy_zero(fee);
        return
    };

    let key = ChargedFeeKey<CoinType> { dummy_field: false };
    if (bag::contains(&wrapper.protocol_fees, key)) {
        balance::join(
            bag::borrow_mut(&mut wrapper.protocol_fees, key),
            fee,
        );
    } else {
        bag::add(&mut wrapper.protocol_fees, key, fee);
    };
}

/// Get the splitted DEEP coin from the reserves
public(package) fun split_deep_reserves(
    wrapper: &mut Wrapper,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEEP> {
    coin::from_balance(
        balance::split(&mut wrapper.deep_reserves, amount),
        ctx,
    )
}

// === Private Functions ===
/// Initialize the wrapper module
fun init(ctx: &mut TxContext) {
    let wrapper = Wrapper {
        id: object::new(ctx),
        deep_reserves: balance::zero(),
        deep_reserves_coverage_fees: bag::new(ctx),
        protocol_fees: bag::new(ctx),
    };

    // Create a fund capability for the deployer
    let fund_cap = FundCap {
        id: object::new(ctx),
        wrapper_id: object::uid_to_inner(&wrapper.id),
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
    let key = ChargedFeeKey<CoinType> { dummy_field: false };

    if (bag::contains(&wrapper.deep_reserves_coverage_fees, key)) {
        coin::from_balance(
            balance::withdraw_all(wrapper.deep_reserves_coverage_fees.borrow_mut(key)),
            ctx,
        )
    } else {
        coin::zero(ctx)
    }
}

// === Deprecated Functions ===
#[deprecated(note = b"This function is deprecated. Please use `create_fund_cap_v2` instead.")]
public fun create_fund_cap(_admin: &AdminCap, _wrapper: &Wrapper, _ctx: &mut TxContext): FundCap {
    abort EFunctionDeprecated
}

#[
    deprecated(
        note = b"This function is deprecated. Please use `withdraw_deep_reserves_coverage_fee_v2` instead.",
    ),
    allow(
        unused_type_parameter,
    ),
]
public fun withdraw_deep_reserves_coverage_fee<CoinType>(
    _fund_cap: &FundCap,
    _wrapper: &mut Wrapper,
    _ctx: &mut TxContext,
): Coin<CoinType> {
    abort EFunctionDeprecated
}

#[
    deprecated(
        note = b"This function is deprecated. Please use `admin_withdraw_deep_reserves_coverage_fee_v2` instead.",
    ),
    allow(
        unused_type_parameter,
    ),
]
public fun admin_withdraw_deep_reserves_coverage_fee<CoinType>(
    _admin: &AdminCap,
    _wrapper: &mut Wrapper,
    _ctx: &mut TxContext,
): Coin<CoinType> {
    abort EFunctionDeprecated
}

#[
    deprecated(
        note = b"This function is deprecated. Please use `admin_withdraw_protocol_fee_v2` instead.",
    ),
    allow(
        unused_type_parameter,
    ),
]
public fun admin_withdraw_protocol_fee<CoinType>(
    _admin: &AdminCap,
    _wrapper: &mut Wrapper,
    _ctx: &mut TxContext,
): Coin<CoinType> {
    abort EFunctionDeprecated
}

#[
    deprecated(
        note = b"This function is deprecated. Please use `withdraw_deep_reserves_v2` instead.",
    ),
]
public fun withdraw_deep_reserves(
    _admin: &AdminCap,
    _wrapper: &mut Wrapper,
    _amount: u64,
    _ctx: &mut TxContext,
): Coin<DEEP> {
    abort EFunctionDeprecated
}
