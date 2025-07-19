# Admin Control Philosophy: On-Chain Multi-Signature Enforcement

A critical aspect of this protocol's design is the guarantee that administrative functions are always under the control of a multi-signature wallet. We have implemented a novel on-chain pattern to enforce this, which differs from the standard approach. This document explains our rationale.

### The Goal: A Permanent, On-Chain Guarantee

Our primary goal is to provide a permanent, on-chain guarantee that the `AdminCap` can never be controlled by a single key. We want any external observer to be able to verify, at any time, that all administrative actions are subject to a multi-signature policy.

### The Problem with Standard Multi-Sig

The most common method for securing an `AdminCap` is to transfer it to a standard Sui multi-sig address.

- **The Weakness:** This approach carries a significant risk. The multi-sig wallet holding the `AdminCap` could, at any point, execute a transaction to transfer the `AdminCap` back to a regular, single-key address. This would silently remove the multi-sig protection and centralize control, defeating the original purpose.

### Our Solution: On-Chain Verification

To eliminate this weakness, we have hardcoded a multi-sig check directly into every sensitive administrative function within our smart contracts.

Instead of just checking if the sender has the `AdminCap`, our functions require the transaction to also include the full multi-sig configuration (`pks`, `weights`, `threshold`). The contract then performs an on-chain verification to assert that the sender's address matches the address derived from the provided multi-sig parameters.

```move
// Example from the `update_pool_creation_protocol_fee` function
public fun update_pool_creation_protocol_fee(
    config: &mut PoolCreationConfig,
    _admin: &AdminCap,
    new_fee: u64,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    // This assertion guarantees the sender is the expected multi-sig wallet.
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );

    config.protocol_fee = new_fee;
}
```

### Rationale and Benefits

1.  **Immutability:** The multi-sig policy is enforced by the contract code itself. It cannot be bypassed or disabled without a full contract upgrade. The `AdminCap` is, by this design, permanently locked to a multi-sig governance model.
2.  **Transparency & Verifiability:** This is the most significant benefit. Any external party can audit any administrative transaction on the blockchain. By inspecting the transaction's inputs, they can see the public keys, weights, and threshold used, and cryptographically verify that the action was authorized by the declared multi-sig policy.

### Acknowledged Trade-offs

We recognize that this approach comes with a primary trade-off:

- **Operational Security Exposure:** The full list of public keys participating in the multi-sig is made public with every administrative transaction. We believe this is an acceptable trade-off for the absolute on-chain transparency and security it provides.
- **Not a Silver Bullet:** This on-chain mechanism does not, and cannot, replace the need for robust internal key management processes. The ultimate security of the system still relies on the signers protecting their individual keys and verifying the transactions they sign.
