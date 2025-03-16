/// Module that manages administrative capabilities for the DeepBook wrapper.
/// The AdminCap is created once during module initialization and is given to the
/// package publisher. It can be transferred between addresses and is used to
/// authorize privileged operations in the wrapper module.
module deepbook_wrapper::admin;

/// Capability that marks the holder as an admin of the DeepBook wrapper
public struct AdminCap has key, store {
    id: UID,
}

/// Create and transfer AdminCap to the publisher during module initialization
fun init(ctx: &mut TxContext) {
    transfer::transfer(
        AdminCap { id: object::new(ctx) },
        tx_context::sender(ctx),
    )
}

// === Test-Only Functions ===
#[test_only]
public fun create_for_testing(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}

#[test_only]
#[allow(lint(custom_state_change))]
public fun transfer_for_testing(admin_cap: AdminCap, recipient: address) {
    transfer::transfer(admin_cap, recipient)
}
