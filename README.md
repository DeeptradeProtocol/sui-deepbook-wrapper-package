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

## Economic Considerations

### DEEP Treasury Sustainability

The wrapper provides DEEP tokens from its treasury for trades on non-whitelisted pools, while collecting fees in the traded tokens. This creates a potential economic risk:

- **Risk**: High volume of low-value token trades could deplete the DEEP treasury faster than the collected fees can replenish it (when converted back to DEEP)
- **Impact**: The wrapper could become economically unsustainable if the value of consumed DEEP exceeds the value of collected fees

### Potential Mitigations

Several approaches could address this economic risk:

1. **Token Whitelisting**: Limit wrapper usage to specific tokens with sufficient value and liquidity
2. **Dynamic Fee Structure**: Implement variable fees based on token liquidity, value, or historical usage patterns
3. **DEEP Usage Limits**: Set caps on DEEP consumption per token type or per time period
4. **Value-Based Fee Model**: Use oracles to charge fees based on the USD value of trades rather than token quantity
5. **Monitoring & Governance**: Implement monitoring systems and governance mechanisms to adjust parameters or pause support for problematic tokens

The initial deployment will focus on supporting established tokens while monitoring economic patterns to ensure long-term sustainability.
