/// Module that manages administrative capabilities for the DeepBook wrapper.
/// The AdminCap is created once during module initialization and is given to the
/// package publisher. It cannot be transferred between addresses and is used to
/// authorize privileged operations in the wrapper module.
module deepbook_wrapper::admin;

/// Capability that marks the holder as an admin of the DeepBook wrapper
public struct AdminCap has key {
    id: UID,
}

/// Create and transfer AdminCap to the publisher during module initialization
fun init(ctx: &mut TxContext) {
    transfer::transfer(
        AdminCap { id: object::new(ctx) },
        tx_context::sender(ctx),
    )
}
