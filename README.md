# sui-deepbook-wrapper-contract

DeepBook V3 wrapper that manages DEEP coin fees and collects trading fees from swaps and orders.

## System Design

### Overview

The DeepBook wrapper provides two main functionalities:

1. Swap facilitation with fee collection in native coins
2. Order creation support with DEEP coin provision and SUI-based fee collection

### Swap System

The wrapper collects fees in the native coin of each trade (base coin for quote→base swaps, quote coin for base→quote swaps).
These fees are stored in a `Bag` data structure, organized by coin type.

### Order System

The wrapper provides DEEP coins from its reserves when users need additional DEEP to cover DeepBook's native fees. This service is only needed when:

- The pool is not whitelisted by DeepBook (whitelisted pools don't require DEEP)
- The user doesn't have enough DEEP in their wallet or balance manager

## Fee Structure

### Order Fees

The wrapper implements a two-tier fee structure for orders:

1. **Deep Reserves Coverage Fee**

   - Only applies when users borrow DEEP from wrapper reserves
   - Charged in SUI coins
   - Amount equals the value of borrowed DEEP coins
   - Not charged if user has sufficient DEEP or uses whitelisted pools

2. **Protocol Fee**
   - 1% of the Deep Reserves Coverage Fee
   - Only applies when Deep Reserves Coverage Fee is charged
   - Collected in SUI coins

### Fee Exemptions

No fees are charged when:

- User has sufficient DEEP in their wallet or balance manager
- Trading on pools whitelisted by DeepBook (which don't require DEEP)

### Design Considerations

- **Fee Collection**: Swap fees are collected in native coins of the trade, while order fees are collected in SUI coins
- **DEEP Usage**: The wrapper provides DEEP only when necessary, optimizing for user convenience and system efficiency
- **Whitelisted Pools**: Zero-fee operations for whitelisted pools encourage liquidity provision on strategic venues

## Economic Considerations

### DEEP Treasury Sustainability

The wrapper maintains a DEEP coin treasury to support both order creation and swaps on non-whitelisted pools. Key economic factors:

- **Revenue Streams**:
  - Swap fees in native traded coins
  - Order fees in SUI coins
- **Cost Coverage**: Deep Reserves Coverage Fee ensures the wrapper can replenish its DEEP treasury
- **Protocol Growth**: Protocol Fee – 1% of Deep Reserves Coverage Fee – supports ongoing development and maintenance

### Risk Management

Several mechanisms ensure economic sustainability:

1. **Value-Equivalent Fees**: Deep Reserves Coverage Fee matches the value of provided DEEP
2. **Selective DEEP Provision**: DEEP only provided when necessary
3. **Whitelisted Pool Optimization**: Zero-fee operations for strategically important pools
4. **Multi-Coin Treasury**: Diversified fee collection in both native coins (swaps) and SUI coins (orders)

### Future Optimizations

Potential future enhancements could include:

1. **Dynamic Fee Structure**: Adjust fees based on market conditions and DEEP availability
2. **Advanced Treasury Management**: Automated DEEP replenishment strategies
3. **Enhanced Pool Whitelisting**: Strategic pool selection for zero-fee trading
4. **Monitoring Systems**: Real-time tracking of DEEP usage and fee collection

The current implementation provides a solid foundation for sustainable operations while maintaining flexibility for future improvements.
