# DeepBook Wrapper Design

## Fee Structure

### DEEP-based Fees

The `order::create_limit_order` function creates a limit order. It requires two pools as arguments:

1. Target pool - where the order will be placed
2. Reference pool (DEEP/SUI or SUI/DEEP) - used to get the DEEP/SUI price

The reference pool helps calculate how much SUI equals the DEEP a user borrows from our wrapper's DEEP reserves. We take the DEEP/SUI price from the reference pool and calculate the SUI equivalent of the borrowed DEEP.

The process works like this:

1. Calculate how much DEEP the user needs
2. Provide this DEEP from our reserves
3. Get the current DEEP/SUI price from the reference pool
4. Calculate the SUI equivalent of the borrowed DEEP
5. Charge this amount from the user as a **DEEP Reserve Coverage Fee**
6. Calculate 1% of the coverage fee
7. Charge this 1% as a **Protocol Fee**

### Input Coin Fees

DeepBook v3.1 introduced an alternative fee mechanism based on the input coin rather than DEEP tokens. Under this model, users pay fees in the same token they're using to create the order.

For example, when creating an order to exchange SUI for USDC, the fee is paid in additional SUI. The fee amount is calculated as:

- DeepBook fee = Input Amount × Taker Fee Rate × FEE_PENALTY_MULTIPLIER
- Protocol fee = Input Amount × Taker Fee Rate × INPUT_COIN_PROTOCOL_FEE_MULTIPLIER

For instance, with:

- Taker fee rate: 0.1%
- Fee penalty multiplier: 1.25
- Input coin protocol fee multiplier: 0.75
- Input amount: 5 SUI

The DeepBook fee would be 5 × 0.1% × 1.25 = 0.00625 SUI
The protocol fee would be 5 × 0.1% × 0.75 = 0.00375 SUI
The total fee paid by the user would be 0.00625 + 0.00375 = 0.01 SUI

The contract provides dedicated functions in the order module for handling input coin fees:

- `create_limit_order_input_fee`
- `create_market_order_input_fee`

These functions handle the protocol fee calculation and ensure the user's balance manager has sufficient input coins to cover both the order amount and the DeepBook fee. If needed, they automatically source additional input coins from the user's wallet.

## Separate Functions for Different Pool Types

We have two functions for creating limit orders:

- `order::create_limit_order` - requires a reference pool argument
- `order::create_limit_order_whitelisted` - doesn't require a reference pool

Why we need separate functions: In the Move language, the `pool` argument (target pool) is a mutable reference, while the `reference_pool` argument is a regular reference. Move doesn't allow these to be the same object (for example, when creating a limit order on the DEEP/SUI pool while using that same pool as the reference pool).

We created `create_limit_order_whitelisted` to handle this limitation. Since whitelisted pools (by DeepBook's design) don't charge DEEP fees, our wrapper doesn't need to charge wrapper fees for them. Therefore, no reference pool is needed when working with whitelisted pools.
