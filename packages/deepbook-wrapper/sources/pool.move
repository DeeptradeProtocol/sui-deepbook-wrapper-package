module deepbook_wrapper::pool;

use deepbook::constants;
use deepbook::pool;
use deepbook::registry::Registry;
use deepbook_wrapper::helper::transfer_if_nonzero;
use deepbook_wrapper::ticket::{
    AdminTicket,
    update_pool_creation_protocol_fee_ticket_type,
    validate_ticket,
    destroy_ticket
};
use deepbook_wrapper::wrapper::{Wrapper, join_protocol_fee};
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event;
use token::deep::DEEP;

// === Errors ===
/// Error when the user has not enough DEEP to cover the deepbook and protocol fees
const ENotEnoughFee: u64 = 1;

// === Constants ===
// Default protocol fee for creating a pool
const DEFAULT_POOL_CREATION_PROTOCOL_FEE: u64 = 100 * 1_000_000; // 100 DEEP

// === Structs ===
/// Pool creation configuration object that stores the protocol fee
public struct PoolCreationConfig has key, store {
    id: UID,
    // Protocol fee can be updated by the admin
    protocol_fee: u64,
}

/// Pool created event emitted when a pool is created with help of the wrapper
public struct PoolCreated<phantom BaseAsset, phantom QuoteAsset> has copy, drop {
    pool_id: ID,
    tick_size: u64,
    lot_size: u64,
    min_size: u64,
}

/// Initialize the pool creation config object
fun init(ctx: &mut TxContext) {
    let config = PoolCreationConfig {
        id: object::new(ctx),
        protocol_fee: DEFAULT_POOL_CREATION_PROTOCOL_FEE,
    };

    transfer::share_object(config);
}

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
    config: &PoolCreationConfig,
    registry: &mut Registry,
    mut creation_fee: Coin<DEEP>,
    tick_size: u64,
    lot_size: u64,
    min_size: u64,
    ctx: &mut TxContext,
): ID {
    wrapper.verify_version();

    let deepbook_fee = constants::pool_creation_fee();
    let protocol_fee = config.protocol_fee;
    let total_fee = deepbook_fee + protocol_fee;
    assert!(creation_fee.value() >= total_fee, ENotEnoughFee);

    // Take the fee coins from the creation fee
    let deepbook_fee_coin = creation_fee.split(deepbook_fee, ctx);
    let protocol_fee_coin = creation_fee.split(protocol_fee, ctx);

    // Move protocol fee to the wrapper
    join_protocol_fee(wrapper, protocol_fee_coin.into_balance());

    // Return unused DEEP coins to the caller
    transfer_if_nonzero(creation_fee, ctx.sender());

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

/// Update the protocol fee for the pool creation config. Performs timelock validation using an admin ticket.
///
/// Parameters:
/// - config: Pool creation configuration object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - protocol_fee: The new protocol fee
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for sender verification
///
/// Aborts:
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun update_pool_creation_protocol_fee(
    config: &mut PoolCreationConfig,
    ticket: AdminTicket,
    protocol_fee: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    validate_ticket(&ticket, update_pool_creation_protocol_fee_ticket_type(), clock, ctx);

    // Consume ticket after successful validation
    destroy_ticket(ticket);

    config.protocol_fee = protocol_fee;
}

// === Public-View Functions ===
/// Get the current protocol fee for creating a pool
public fun pool_creation_protocol_fee(config: &PoolCreationConfig): u64 {
    config.protocol_fee
}
