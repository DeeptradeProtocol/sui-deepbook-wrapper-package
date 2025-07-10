module deepbook_wrapper::ticket;

use deepbook_wrapper::admin::AdminCap;
use multisig::multisig;
use sui::clock::Clock;
use sui::event;

// === Errors ===
/// Ticket-related errors
const ETicketOwnerMismatch: u64 = 1;
const ETicketTypeMismatch: u64 = 2;
const ETicketExpired: u64 = 3;
const ETicketNotReady: u64 = 4;

/// Error when the sender is not a multisig address
const ESenderIsNotMultisig: u64 = 5;
/// Error when the ticket is not expired
const ETicketNotExpired: u64 = 6;

// === Constants ===
const SECONDS_PER_DAY: u64 = 86400;
const TICKET_DELAY_DURATION: u64 = SECONDS_PER_DAY * 2; // 2 days
const TICKET_ACTIVE_DURATION: u64 = SECONDS_PER_DAY * 3; // 3 days

/// Ticket types
const WITHDRAW_DEEP_RESERVES: u8 = 0;
const WITHDRAW_PROTOCOL_FEE: u8 = 1;
const WITHDRAW_COVERAGE_FEE: u8 = 2;
const UPDATE_POOL_CREATION_PROTOCOL_FEE: u8 = 3;
const UPDATE_DEFAULT_FEES: u8 = 4;
const UPDATE_POOL_SPECIFIC_FEES: u8 = 5;

// === Structs ===
/// Admin ticket for timelock mechanism
public struct AdminTicket has key {
    id: UID,
    owner: address,
    created_at: u64,
    ticket_type: u8,
}

// === Events ===
/// Event emitted when an admin ticket is created
public struct TicketCreated has copy, drop {
    ticket_id: ID,
    ticket_type: u8,
}

/// Event emitted when a ticket is destroyed (consumed)
public struct TicketDestroyed has copy, drop {
    ticket_id: ID,
    ticket_type: u8,
}

// === Public Functions ===
/// Create an admin ticket for timelock mechanism with multi-signature verification
/// Verifies sender matches the multi-sig address, then creates a ticket for future execution
///
/// Parameters:
/// - _admin: Admin capability
/// - ticket_type: Type of operation this ticket authorizes
/// - pks: Vector of public keys of the multi-sig signers
/// - weights: Vector of weights for each corresponding signer (must match pks length)
/// - threshold: Minimum sum of weights required to authorize transactions (must be > 0 and <= sum of weights)
/// - clock: Clock for timestamp recording
/// - ctx: Mutable transaction context for ticket creation and sender verification
///
/// Returns:
/// - AdminTicket: The created ticket bound to the sender address
///
/// Aborts:
/// - With ESenderIsNotMultisig if the transaction sender is not the expected multi-signature address
///   derived from the provided pks, weights, and threshold parameters
public fun create_ticket(
    _admin: &AdminCap,
    ticket_type: u8,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );

    let ticket_id = object::new(ctx);
    let created_at = clock.timestamp_ms() / 1000;

    let ticket = AdminTicket {
        id: ticket_id,
        owner: ctx.sender(),
        created_at,
        ticket_type,
    };

    event::emit(TicketCreated {
        ticket_id: ticket.id.to_inner(),
        ticket_type,
    });

    transfer::share_object(ticket)
}

/// Cleans up an expired admin ticket
/// Any user can call this function to remove an expired ticket from the system
public fun cleanup_expired_ticket(ticket: AdminTicket, clock: &Clock) {
    assert!(is_ticket_expired(&ticket, clock), ETicketNotExpired);

    destroy_ticket(ticket);
}

// === Public-View Functions ===
/// Check if ticket is ready for execution (past delay period)
public fun is_ticket_ready(ticket: &AdminTicket, clock: &Clock): bool {
    let current_time = clock.timestamp_ms() / 1000;
    current_time >= ticket.created_at + TICKET_DELAY_DURATION
}

/// Check if ticket is expired (past active period)
public fun is_ticket_expired(ticket: &AdminTicket, clock: &Clock): bool {
    let current_time = clock.timestamp_ms() / 1000;
    current_time >= ticket.created_at + TICKET_DELAY_DURATION + TICKET_ACTIVE_DURATION
}

public fun withdraw_deep_reserves_ticket_type(): u8 { WITHDRAW_DEEP_RESERVES }

public fun withdraw_protocol_fee_ticket_type(): u8 { WITHDRAW_PROTOCOL_FEE }

public fun withdraw_coverage_fee_ticket_type(): u8 { WITHDRAW_COVERAGE_FEE }

public fun update_pool_creation_protocol_fee_ticket_type(): u8 { UPDATE_POOL_CREATION_PROTOCOL_FEE }

public fun update_default_fees_ticket_type(): u8 { UPDATE_DEFAULT_FEES }

public fun update_pool_specific_fees_ticket_type(): u8 { UPDATE_POOL_SPECIFIC_FEES }

// === Package Functions ===
/// Consumes the ticket, should be called after validation.
public(package) fun destroy_ticket(ticket: AdminTicket) {
    let AdminTicket { id, ticket_type, .. } = ticket;

    event::emit(TicketDestroyed {
        ticket_id: id.to_inner(),
        ticket_type,
    });

    id.delete();
}

/// Validate ticket for execution
public(package) fun validate_ticket(
    ticket: &AdminTicket,
    expected_type: u8,
    clock: &Clock,
    ctx: &TxContext,
) {
    // Check ownership
    assert!(ticket.owner == ctx.sender(), ETicketOwnerMismatch);
    // Check type
    assert!(ticket.ticket_type == expected_type, ETicketTypeMismatch);
    // Check if expired
    assert!(!is_ticket_expired(ticket, clock), ETicketExpired);
    // Check if ready
    assert!(is_ticket_ready(ticket, clock), ETicketNotReady);
}
