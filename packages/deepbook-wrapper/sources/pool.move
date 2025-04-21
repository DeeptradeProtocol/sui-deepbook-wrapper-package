module deepbook_wrapper::pool;

use sui::event;
use sui::coin::{Self, Coin};
use deepbook::pool::{Self};
use deepbook::constants::{Self};
use deepbook::registry::{Registry};
use deepbook_wrapper::admin::{AdminCap};
use deepbook_wrapper::wrapper::{Wrapper, join_protocol_fee};
use deepbook_wrapper::helper::{transfer_if_nonzero};
use token::deep::DEEP;

// === Constants ===
// Default protocol fee for creating a pool
const DEFAULT_CREATE_POOL_PROTOCOL_FEE: u64 = 100 * 1_000_000; // 100 DEEP

// === Structs ===
/// Create pool configuration object that stores the protocol fee
public struct CreatePoolConfig has key, store {
    id: UID,
    // Protocol fee can be updated by the admin
    protocol_fee: u64,
}

/// Pool created event emitted when a pool is created with help of the wrapper
public struct PoolCreated<phantom BaseAsset, phantom QuoteAsset> has copy, drop, store {
    pool_id: ID,
    tick_size: u64,
    lot_size: u64,
    min_size: u64,
}

// === Errors ===
/// Error when the user has not enough DEEP to cover the deepbook and protocol fees
#[error]
const ENotEnoughFee: u64 = 1;

// === Public-Mutative Functions ===
/// Creates a new permissionless pool for trading between BaseAsset and QuoteAsset
/// Collects both DeepBook creation fee and protocol fee in DEEP coins
/// 
/// # Arguments
/// * `wrapper` - Main wrapper object that will receive the protocol fee
/// * `config` - Configuration object containing protocol fee information
/// * `registry` - DeepBook registry to create the pool in
/// * `tick_size` - Minimum price increment in the pool
/// * `lot_size` - Minimum quantity increment in the pool
/// * `min_size` - Minimum quantity of base asset required to create an order
/// * `creation_fee` - DEEP coins to pay for pool creation (both DeepBook and protocol fees)
/// * `ctx` - Transaction context
/// 
/// # Flow
/// 1. Calculates required fees (DeepBook fee + protocol fee)
/// 2. Verifies user has enough DEEP to cover all fees
/// 3. Splits the payment into DeepBook fee and protocol fee
/// 4. Adds protocol fee to the wrapper
/// 5. Returns any unused DEEP coins to caller
/// 6. Creates the permissionless pool in DeepBook
/// 
/// # Returns
/// * ID of the newly created pool
/// 
/// # Aborts
/// * `ENotEnoughFee` - If user doesn't provide enough DEEP to cover all fees
public fun create_permissionless_pool<BaseAsset, QuoteAsset>(
    wrapper: &mut Wrapper,
    config: &CreatePoolConfig,
    registry: &mut Registry,
    tick_size: u64,
    lot_size: u64,
    min_size: u64,
    mut creation_fee: Coin<DEEP>,
    ctx: &mut TxContext,
): ID {
    let deepbook_fee = constants::pool_creation_fee();
    let protocol_fee = config.protocol_fee;
    let total_fee = deepbook_fee + protocol_fee;
    assert!(creation_fee.value() >= total_fee, ENotEnoughFee);

    // Take the fee coins from the creation fee
    let deepbook_fee_coin = creation_fee.split(deepbook_fee, ctx);
    let protocol_fee_coin = creation_fee.split(protocol_fee, ctx);

    // Move protocol fee to the wrapper
    join_protocol_fee(wrapper, coin::into_balance(protocol_fee_coin));

    // Return unused DEEP coins to the caller
    transfer_if_nonzero(creation_fee, tx_context::sender(ctx));

    // Create the permissionless pool
    let pool_id = pool::create_permissionless_pool<BaseAsset, QuoteAsset>(
        registry, 
        tick_size, 
        lot_size, 
        min_size, 
        deepbook_fee_coin, 
        ctx,
    );

    // Emit event for the newly created pool
    event::emit(PoolCreated<BaseAsset, QuoteAsset> {
        pool_id,
        tick_size,
        lot_size,
        min_size,
    });

    pool_id
}

/// Update the protocol fee for creating a pool
public fun update_create_pool_protocol_fee(
    _admin: &AdminCap,
    config: &mut CreatePoolConfig,
    new_fee: u64,
) {
    config.protocol_fee = new_fee;
}

// === Public-View Functions ===
/// Get the current protocol fee for creating a pool
public fun get_create_pool_protocol_fee(config: &CreatePoolConfig): u64 {
    config.protocol_fee
}

// === Private Functions ===
/// Initialize the pool module
fun init(ctx: &mut TxContext) {
    let config = CreatePoolConfig {
        id: object::new(ctx),
        protocol_fee: DEFAULT_CREATE_POOL_PROTOCOL_FEE,
    };

    transfer::share_object(config);
}
