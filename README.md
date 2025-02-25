# sui-deepbook-wrapper-contract
DeepBook V3 wrapper that manages DEEP token fees and collects trading fees from swaps.

## Fee Collection Design

### Overview
The DeepBook wrapper collects fees in the native token of each trade (base token for quote→base swaps, quote token for base→quote swaps).
These fees are stored in a `Bag` data structure, organized by token type.

### Design Considerations

- **Fee Storage**: Fees are stored by token type in a Bag data structure
- **Access Pattern**: Direct access by token type when withdrawing fees
- **Admin Operations**: Only the admin (when withdrawing fees) might experience slightly higher gas costs as the number of token types grows significantly
- **DEEP Token Usage**: The wrapper withdraws all available DEEP tokens for each trade, returning unused tokens afterward.


### Future Optimizations

While the current implementation is sufficient for current use cases, potential future optimizations could include:

- Periodic consolidation of small fee balances (e.g., bot which would run the withdraw function for small balances, swap to DEEP, and top up wrapper using join method)
- Selective DEEP withdrawal - only taking the estimated amount needed for each trade instead of the entire wrapper's DEEP reserve

The first optimization would only become necessary if DeepBook transitions to permissionless pool creation AND the ecosystem grows to support thousands of token types with active trading. Given that DeepBook pools are currently permissioned, this is not an immediate concern.
