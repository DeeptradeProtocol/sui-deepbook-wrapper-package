# DeepBook Wrapper Design

## Fees Calculation

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

## Separate Functions for Different Pool Types

We have two functions for creating limit orders:

- `order::create_limit_order` - requires a reference pool argument
- `order::create_limit_order_whitelisted` - doesn't require a reference pool

Why we need separate functions: In the Move language, the `pool` argument (target pool) is a mutable reference, while the `reference_pool` argument is a regular reference. Move doesn't allow these to be the same object (for example, when creating a limit order on the DEEP/SUI pool while using that same pool as the reference pool).

We created `create_limit_order_whitelisted` to handle this limitation. Since whitelisted pools (by DeepBook's design) don't charge DEEP fees, our wrapper doesn't need to charge wrapper fees for them. Therefore, no reference pool is needed when working with whitelisted pools.
