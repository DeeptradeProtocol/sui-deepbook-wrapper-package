# DeepBook Wrapper Design

## Overview

The DeepBook Wrapper charges additional fees on top of the standard DeepBook fees. These wrapper fees are calculated using protocol fee configuration system and are applied regardless of which fee type is used for the underlying DeepBook order.

## Fee Configuration

The wrapper uses a unified protocol fee calculation system with configurable rates and discounts. Fee rates and discount configurations are specified per pool in the `TradingFeeConfig`:

- Taker and maker fee rates for both fee types
- Maximum discount rates for DEEP fee type

### Protocol Fee Discounts

The system incentivizes DEEP holders by offering protocol fee discounts based on how much DeepBook fees users cover with their own DEEP tokens. Whitelisted pools automatically receive the maximum discount rate.

### Dynamic Fee Calculation and Fee Estimation Strategy

When estimating fees for users, the wrapper calculates the protocol fee assuming the order will be fully executed as a taker order, then applies the user's discount rate to this estimated amount. This approach provides users with a fee upper limit, preventing scenarios where they would have to pay more than the displayed amount. The actual fee charged is then adjusted based on the actual execution status of their order.

For detailed information about dynamic fee calculation based on order execution status and the unsettled fees mechanism, see the [unsettled-fees.md](./unsettled-fees.md) documentation.

## Fee Structure

The wrapper supports two fee types for order creation, with a unified protocol fee calculation system for both:

### DEEP-based Fees

The `order::create_limit_order` function creates a limit order using DEEP tokens for DeepBook fees. It requires two pools as arguments:

1. Target pool - where the order will be placed
2. Reference pool (DEEP/SUI or SUI/DEEP) - used to get the DEEP/SUI price

The reference pool helps calculate how much SUI equals the DEEP a user borrows from our wrapper's DEEP reserves. We take the DEEP/SUI price from the reference pool and calculate the SUI equivalent of the borrowed DEEP.

The process works like this:

1. Calculate how much DEEP the user needs for DeepBook fees
2. Provide this DEEP from our reserves
3. Get the best DEEP/SUI price for the wrapper either from oracle or from the reference pool (read more in [Oracle Pricing Security](docs/oracle-pricing-security.md) documentation)
4. Calculate the SUI equivalent of the borrowed DEEP
5. Charge this amount from the user as a **DEEP Reserve Coverage Fee**

#### Slippage Validation System

The DEEP fee type includes a **protective slippage validation system** to handle the inherent volatility of its fee calculation parameters. This system is necessary because DEEP-based fees depend on two unstable market conditions:

1. **DeepBook's DEEP price points** - The DEEP required for an order is calculated based on DeepBook's internal DEEP price points, which **change constantly over time**. This makes the exact DEEP requirement unpredictable between fee estimation and order execution.

2. **DEEP/SUI price for coverage fee calculation** - This affects the SUI equivalent charged when the wrapper borrows DEEP from its reserves

**How the validation works:**

Users provide estimated fees and slippage tolerances when creating orders:

- `estimated_deep_required` - User's estimate of DEEP tokens needed for an order creation
- `estimated_deep_required_slippage` - Maximum acceptable slippage (e.g., 10% = `100_000_000` in billionths)
- `estimated_sui_fee` - User's estimate of SUI coverage fee
- `estimated_sui_fee_slippage` - Maximum acceptable slippage for the coverage fee

The system validates two components:

1. **DEEP Fee Validation**: Ensures actual DEEP required doesn't exceed `estimated_deep_required + slippage`
2. **Coverage Fee Validation**: Ensures actual SUI coverage fee doesn't exceed `estimated_sui_fee + slippage`

**Benefits:**

- **User Protection**: Users get predictable fee upper bounds, preventing unexpected charges
- **Market Volatility Handling**: Protects against rapid price movements between estimation and execution

**Why Input Coin Fee Type Doesn't Need This:**

Input coin fees are stable and predictable because:

- Fees are calculated as a fixed percentage of the input amount
- No external price dependencies (like DEEP/SUI price)
- The calculation is deterministic and doesn't vary with market conditions

### Input Coin Fees

DeepBook v3.1 introduced an alternative fee mechanism based on the input coin rather than DEEP tokens. Under this model, users pay fees in the same token they're using to create the order.

For example, when creating an order to exchange SUI for USDC, the fee is paid in additional SUI. The fee amount is calculated as:

- DeepBook fee = Input Amount × Taker Fee Rate × FEE_PENALTY_MULTIPLIER

The contract provides dedicated functions in the order module for handling input coin fees:

- `create_limit_order_input_fee`
- `create_market_order_input_fee`

These functions handle the fee calculation and ensure the user's balance manager has sufficient input coins to cover both the order amount and the DeepBook fee. If needed, they automatically source additional input coins from the user's wallet.

## Separate Functions for Different Pool Types

We have two functions for creating limit orders:

- `order::create_limit_order` - requires a reference pool argument
- `order::create_limit_order_whitelisted` - doesn't require a reference pool

Why we need separate functions: In the Move language, the `pool` argument (target pool) is a mutable reference, while the `reference_pool` argument is a regular reference. Move doesn't allow these to be the same object (for example, when creating a limit order on the DEEP/SUI pool while using that same pool as the reference pool).

We created `create_limit_order_whitelisted` to handle this limitation. Since whitelisted pools (by DeepBook's design) don't charge DEEP fees, our wrapper doesn't need to charge wrapper fees for them. Therefore, no reference pool is needed when working with whitelisted pools.
