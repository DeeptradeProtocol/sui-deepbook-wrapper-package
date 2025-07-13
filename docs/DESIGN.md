# DeepBook Wrapper Design

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
3. Get the best current DEEP/SUI price either from oracle or from the reference pool
4. Calculate the SUI equivalent of the borrowed DEEP
5. Charge this amount from the user as a **DEEP Reserve Coverage Fee**

### Input Coin Fees

DeepBook v3.1 introduced an alternative fee mechanism based on the input coin rather than DEEP tokens. Under this model, users pay fees in the same token they're using to create the order.

For example, when creating an order to exchange SUI for USDC, the fee is paid in additional SUI. The fee amount is calculated as:

- DeepBook fee = Input Amount × Taker Fee Rate × FEE_PENALTY_MULTIPLIER

The contract provides dedicated functions in the order module for handling input coin fees:

- `create_limit_order_input_fee`
- `create_market_order_input_fee`

These functions handle the fee calculation and ensure the user's balance manager has sufficient input coins to cover both the order amount and the DeepBook fee. If needed, they automatically source additional input coins from the user's wallet.

## Protocol Fee System

The wrapper uses a unified protocol fee calculation system regardless of the fee type (DEEP-based or Input coin):

### Dynamic Fee Calculation

Protocol fees are calculated dynamically based on order execution status:

- **Immediately executed portions**: Charged at the taker fee rate
- **Live/unfilled portions**: Charged at the maker fee rate and added to unsettled fees

### Fee Configuration

- Fee rates (both taker and maker for both fee types) are specified per pool in the `TradingFeeConfig`
- Maximum discount rates for DEEP fee type are also configured in `TradingFeeConfig`

### Protocol Fee Discounts

When using DEEP fee type, users can receive protocol fee discounts:

- The more DeepBook fees you cover with your own DEEP tokens, the higher your discount
- Maximum discount is achieved when the user fully covers the DeepBook fees themselves

### Unsettled Fees

For orders that remain live in the order book, the wrapper uses an "unsettled fees" system to handle the maker portion of protocol fees. This ensures fees are only charged for actual execution, not just order placement.

For detailed information about the unsettled fees mechanism, see the [unsettled-fees.md](./unsettled-fees.md) documentation.

## Separate Functions for Different Pool Types

We have two functions for creating limit orders:

- `order::create_limit_order` - requires a reference pool argument
- `order::create_limit_order_whitelisted` - doesn't require a reference pool

Why we need separate functions: In the Move language, the `pool` argument (target pool) is a mutable reference, while the `reference_pool` argument is a regular reference. Move doesn't allow these to be the same object (for example, when creating a limit order on the DEEP/SUI pool while using that same pool as the reference pool).

We created `create_limit_order_whitelisted` to handle this limitation. Since whitelisted pools (by DeepBook's design) don't charge DEEP fees, our wrapper doesn't need to charge wrapper fees for them. Therefore, no reference pool is needed when working with whitelisted pools.
