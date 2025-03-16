# Deepbook Wrapper

The Deepbook Wrapper is a "wrapper" package for DeepBook V3 that enables trading without requiring users to hold DEEP coins.

## Overview

This wrapper simplifies the trading experience by automatically handling DEEP coin requirements:

- **Swaps**: Covers DEEP fees from reserves in exchange for a portion of output tokens
- **Orders**: Covers DEEP fees from reserves in exchange for a portion of user's SUI

The wrapper acts as an intermediary, managing all DEEP-related fee operations.


## System Design

### Swaps

The wrapper provides DEEP coins from its reserves each time user does a swap.
The wrapper collects fees in the output coin of each trade (base coin for quote→base swaps, quote coin for base→quote swaps) to cover provided DEEP coins from reserves.
These fees are stored in a `Bag` data structure, organized by `coinType`.

### Orders

The wrapper provides DEEP coins from its reserves only when user needs additional DEEP to cover DeepBook's native fees during order placement. When the pool is whitelisted by DeepBook, the wrapper doesn't provide any DEEP, since such pools doesn't have DEEP fees.
Also, if user has enough DEEP in their wallet or balance manager, the wrapper doesn't provide any DEEP.

## Fee Structure

### Swap Fees

The Deepbook Wrapper charges a fee on each swap in the output coin of the swap. The fee structure directly mirrors DeepBook's `taker_fee` parameter, which is set and controlled by DeepBook governance (currently 0.01% for stablecoin pools and 0.1% for other pools). The Wrapper simply adopts these rates without modification.

### Order Fees

DeepBook protocol requires DEEP coins as a fees for order placement, the fees calculated based on order price and size. 
The Wrapper handles these fees in two ways:

1. **If user has enough DEEP to cover the order fees**: No additional fees are charged. DEEP coins are provided from the user's wallet balance.

2. **If user needs DEEP to cover the order fees**: Two fees apply when borrowing DEEP from Wrapper reserves:
   - **DEEP Reserve Coverage Fee**: Equal to the required DEEP amount converted to SUI value; paid in SUI coins;
   - **Protocol Fee**: 1% of the reserve coverage fee; paid in SUI coin.

**Fee Scaling**: The more DEEP a user has in their wallet, the lower the fees:
- When user has all DEEP required for order: 0% reserve coverage fee + 0% protocol fee
- When user has partial DEEP required: reserve coverage fee + 1% protocol fee
- When user has no DEEP: reserve coverage fee + 1% protocol fee

This structure incentivizes users to hold DEEP coins while ensuring trading accessibility for everyone.
For whitelisted pools, there is no DEEP fees, so no fees are charged.

## Economic Considerations

### DEEP Treasury Sustainability

#### Swap Fees
The wrapper provides DEEP tokens from its treasury for trades on non-whitelisted pools, while collecting fees in the traded tokens. This creates a potential economic risk:

- **Risk**: High volume of low-value token trades could deplete the DEEP treasury faster than the collected fees can replenish it (when converted back to DEEP)
- **Impact**: The wrapper could become economically unsustainable if the value of consumed DEEP exceeds the value of collected fees

Several approaches could address this economic risk:
1. **Token Whitelisting**: Limit wrapper usage to specific tokens with sufficient value and liquidity
2. **SUI-based Fees**: Collect swap fees in SUI instead of output tokens, matching the order fee model

However, this would only become necessary if DeepBook transitions to permissionless pool creation AND the ecosystem grows to support thousands of token types with active trading. Given that DeepBook pools are currently permissioned, this is not an immediate concern.

#### Order Fees
The wrapper's order fee structure has minimal economic risk. By collecting fees in SUI, we maintain a stable and liquid asset for treasury management. Since reserve coverage fees directly match the DEEP amount needed, there's a fair value exchange. The additional 1% protocol fee helps cover operational costs and treasury maintenance.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.

This tool uses several dependencies from [Mysten Labs](https://github.com/MystenLabs/sui), which are licensed under Apache-2.0.