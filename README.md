# sui-deepbook-wrapper-contract
DeepBook V3 wrapper that manages DEEP token fees and collects trading fees from swaps.

## Fee Collection Design

### Overview
The DeepBook wrapper collects fees in the native token of each trade (base token for quote→base swaps, quote token for base→quote swaps).
These fees are stored in a `Bag` data structure, organized by token type.

### Design Considerations

- **Efficiency**: The implementation uses O(1) lookups by token type, avoiding expensive iterations.
- **Scalability**: The system can handle a large number of token types without performance degradation for regular users.
- **Admin Operations**: Only the admin (when withdrawing fees) might experience slightly higher gas costs as the number of token types grows significantly.

### Future Optimizations

While the current implementation is sufficient for current use cases, potential future optimizations could include:

- Periodic consolidation of small fee balances (e.g., bot which would run the withdraw function for small balances, swap to DEEP, and top up wrapper using join method)

These optimizations would only become necessary if DeepBook transitions to permissionless pool creation AND the ecosystem grows to support thousands of token types with active trading. Given that DeepBook pools are currently permissioned, this is not an immediate concern.
