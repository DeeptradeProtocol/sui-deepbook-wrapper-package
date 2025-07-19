# Deepbook Wrapper

The Deepbook Wrapper is a "wrapper" package for DeepBook V3 that enables trading without requiring users to hold DEEP coins.

## Overview

This wrapper simplifies the trading experience by automatically handling DEEP coin requirements:

- **Swaps**: Covers DEEP fees from reserves in exchange for a portion of output tokens
- **Orders**: Covers DEEP fees from reserves in exchange for a portion of user's SUI

The wrapper acts as an intermediary, managing all DEEP-related fee operations.

## System Design

For detailed technical specifications and implementation details, please refer to:

- [DeepBook Wrapper Design](docs/DESIGN.md)
- [Oracle Price Calculation](docs/oracle-price-calculation.md)
- [Oracle Pricing Security](docs/oracle-pricing-security.md)
- [Unsettled Fees](docs/unsettled-fees.md)
- [Versioning](docs/versioning.md)
- [Multisig](docs/multisig.md)

### Swaps

The Deepbook Wrapper provides DEEP coins from its reserves each time user does a swap.
The wrapper collects fees in the output coin of each trade (base coin for quote→base swaps, quote coin for base→quote swaps) to cover provided DEEP coins from reserves.
These fees are stored in a `Bag` data structure, organized by `coinType`.

### Orders

The Deepbook Wrapper provides DEEP coins from its reserves only when user needs additional DEEP to cover DeepBook's native fees during order placement. When the pool is whitelisted by DeepBook, the wrapper doesn't provide any DEEP, since such pools doesn't have DEEP fees.
Also, if user has enough DEEP in their wallet or balance manager, the wrapper doesn't provide any DEEP.

## Fee Structure

### Swap Fees

The Deepbook Wrapper charges a fee on each swap in the output coin of the swap. The fee structure directly mirrors DeepBook's `taker_fee` parameter, which is set and controlled by DeepBook governance (currently 0.01% for stablecoin pools and 0.1% for other pools). The Wrapper simply adopts these rates without modification.

Initially (before 3.1 version of DeepBook) swaps require DEEP coin as a fee that was charged by DeepBook protocol.

Obviously, not all users has DEEP coins on their balance, so we've created the wrapper package, which allows users to borrow amount of DEEP that was required for particular swap, in exchange of a small fee that wrapper package charges (`taker_fee` for each market).
The fee that was charged for that determined in the output token of a swap.
For instance, if it's swap USDC to SUI, the fee would be determined in SUI coin.

As of DeepBook version 3.1, it introduce ability to charge fee in input coin for swaps.
Since that, the existing fee charging model could be described as following:
DeepBook charge fee in `input coin`, `taker fee` \* `fee penalty multiplier`, where `fee penalty multiplier` is `1.25`.

Deepbook Wrapper charge fee in `output coin`, so it remains the same as it was before and equal to the `taker_fee`.

### Order Fees

DeepBook protocol requires DEEP coins as fees for order placement, with fees calculated based on order price and size.
The Deepbook Wrapper handles these fees through a unified system:

**Protocol Fee**: Always charged, calculated dynamically based on order execution status and fee rates specified in `TradingFeeConfig`.

**DEEP Reserve Coverage Fee**: Only charged when the user needs to borrow DEEP from Wrapper reserves to cover DeepBook fees. This fee equals the required DEEP amount converted to SUI value and is paid in SUI coins.

**Protocol Fee Discounts**: When using DEEP fee type, users can receive discounts on protocol fees based on how much DeepBook fees they cover with their own DEEP tokens. The more DEEP the user provides, the higher their discount on protocol fees.

This structure incentivizes users to hold DEEP coins while ensuring trading accessibility for everyone.
For whitelisted pools, there are no DEEP fees, so no coverage fees are required. However, protocol fees are still charged, with whitelisted pools receiving the maximum protocol fee discount rate for each order. Maximum discount rates for pools are specified in `TradingFeeConfig`, with a default rate of 25% used if not specified.

For detailed information about dynamic protocol fee calculation, and the unsettled fees mechanism, see the [Unsettled Fees](docs/unsettled-fees.md) documentation.

## Economic Considerations

### DEEP Reserves Sustainability

#### Swap Fees

The Deepbook Wrapper provides DEEP tokens from its reserves for trades on non-whitelisted pools, while collecting fees in the traded tokens. This creates a potential economic risk:

- **Risk**: High volume of low-value token trades could deplete the DEEP reserves faster than the collected fees can replenish it (when converted back to DEEP)
- **Impact**: The Deepbook Wrapper could become economically unsustainable if the value of consumed DEEP exceeds the value of collected fees

Several approaches could address this economic risk:

1. **Token Whitelisting**: Limit wrapper usage to specific tokens with sufficient value and liquidity
2. **SUI-based Fees**: Collect swap fees in SUI instead of output tokens, matching the order fee model
3. **Input coin fee mode**: Restrict wrapper swaps to input coin fee type only, disabling DEEP fee type swaps and eliminating the need for DEEP wrapper reserves.

However, this would only become necessary if DeepBook's ecosystem grows to support thousands of token types with active trading.

#### Order Fees

The Deepbook Wrapper's order fee structure has minimal economic risk. By collecting fees in SUI, we maintain a stable and liquid asset for reserves management. Since reserve coverage fees directly match the DEEP amount needed, there's a fair value exchange. The additional protocol fees (calculated dynamically based on order execution) help cover operational costs and reserves maintenance.

## Deployment

1. Go to `packages/deepbook-wrapper` directory
2. Uncomment `0x0` address in Move.toml before deploying contract
3. Run command:
   `sui client publish --gas-budget 220000000 --skip-dependency-verification`
4. Use new `address` of deployed package in Move.toml
5. Update `examples/constants.ts` with new addresses of `WRAPPER_PACKAGE_ID`, `ADMIN_CAP_OBJECT_ID`, `WRAPPER_OBJECT_ID`.
6. Add DEEP coins to reserves by `examples/wrapper/deposit-into-reserves.ts`

## Upgrade

1. Go to `packages/deepbook-wrapper` directory (`cd packages/deepbook-wrapper/`)
2. Set `address` to `0x0` in `Move.toml`
3. Verify compability:
   `sui-local sui client upgrade --dry-run --verify-compatibility --upgrade-capability 0xae8c80532528977c531c7ee477d55d9e8618320e03c0ce923740ee8635cab01b --gas-budget 1000000000`
4. Dry run upgrade:
   `sui client upgrade --dry-run --upgrade-capability 0xae8c80532528977c531c7ee477d55d9e8618320e03c0ce923740ee8635cab01b --gas-budget 1000000000`
5. Upgrade:
   `sui client upgrade --upgrade-capability 0xae8c80532528977c531c7ee477d55d9e8618320e03c0ce923740ee8635cab01b --gas-budget 1000000000`
6. (optional) Update `examples/constants.ts` with new addresses of `WRAPPER_PACKAGE_ID`, `ADMIN_CAP_OBJECT_ID`, `WRAPPER_OBJECT_ID`.
7. Set `address` to new `address` of deployed package in `Move.toml`
8. Build contract with new address: `sui move build`

## Wrapper Package Ids:

```
0x1271ca74fee31ee2ffb4d6373eafb9ada44cdef0700ca34ec650b21de60cc80b
0xd7ca30ad715278a28f01c572ac7be3168e9800321f1b3f96eb9d13dfc856419c
0xc6fa96e203d7858e1925563bdc2c75d1c2ff57af90cad46a7ad3364573e20fb0
0x90cffe4f0670e0c4d3413c124c364301fc0e73c709ada13ba86f2398c44a135a
0x55febc53366b6ced945b1adf5ebd3f8628d940664782e51937cc93513ad83339
0x4af08dd22015fdabeae5f2b883dca9fca4f7de88434dae7cea712d247658b68d
0x208d664e59ad391212a11ad8658d0e9d7510c6cd1785bd0d477d73505d5c89b1
0xc49f720f4e8427cbd3955846ca9231441dab8ccda6c3da6e9d44ed6f9dcf865c
0x2356885eae212599c0c7a42d648cc2100dedfa4698f8fc58fc6b9f67806f2bfc
0x03aafc54af513d592bcb91136d61b94ea40b0f9b50477f24a3a9a38fca625174
```

## Fee & Reserves Withdrawal (Admin Only)

1. Run `examples/wrapper/get-charged-fee-info.ts` to get the list of coins with charged fees (coverage fees and protocol fees).
2. Run `examples/wrapper/admin-withdraw-all-coins-coverage-fee.ts` to withdraw all coins coverage fees (coverage fees charged in output coin of each swap and for limit/market orders in SUI).
3. Run `examples/wrapper/admin-withdraw-protocol-fee.ts` to withdraw all protocol fees (protocol fees charged in SUI, pool creation fees charged in DEEP).
4. Run `examples/wrapper/withdraw-all-deep-reserves.ts` to withdraw all DEEP coins from reserves.

## Pool Creation Fees

When creating a new trading pool, there are two separate fees:

DeepBook protocol requires 500 DEEP coins as a fee for each new pool creation. Additionally, the Wrapper charges a configurable protocol fee (currently set to 100 DEEP coins) stored in the `PoolCreationConfig` object.

## Development Tools

### Lines of Code Analysis

Analyze and count lines of code across all DeepBook Wrapper modules:

```bash
node scripts/count-loc.js [--help for options]
```

The script provides a detailed breakdown by module and calculates effective lines of code. It analyzes both source files and test files separately.

Example: `🎯 Effective LoC (sources only): 1,234 lines`

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.

This tool uses several dependencies from [Mysten Labs](https://github.com/MystenLabs/sui), which are licensed under Apache-2.0.
