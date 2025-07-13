# Unsettled Fees System

## Overview

Our protocol charges fees for order execution, not order placement. This is achieved through dynamic fee calculation using an "unsettled fees" system.

## How Dynamic Fee Calculation Works

When a user places an order, we follow this process:

1. **Place the order** in the DeepBook
2. **Analyze the order execution**:
   - For immediately executed portions: charge protocol fees at the taker rate
   - For live/unfilled portions: calculate fees at the maker rate and add to unsettled fees
3. **Create a direct relationship** between the live order and its unsettled fees

## Protocol Fee Discounts

The system offers protocol fee discounts when using the DEEP fee type, designed to incentivize DEEP holders:

- **Discount calculation**: The more DeepBook fees you cover with your own DEEP tokens, the higher your discount
- **Maximum discount**: Achieved when the user fully covers the DeepBook fees themselves
- **Whitelisted pools**: Automatically receive the maximum protocol fee discount rate for each order
- **Configuration**: Maximum discount rates are specified for each pool in the `TradingFeeConfig`, alongside the standard fee rates

## Fee Settlement Mechanisms

### 1. User Cancellation Settlement

Users can settle fees when canceling orders using `cancel_order_and_settle_fees`:

- The system checks how much of the order was filled vs unfilled
- Unsettled fees are split proportionally:
  - **Unfilled portion**: fees returned directly to the user
  - **Filled portion**: fees remain with the wrapper (now "settled" and ready for protocol collection)

### 2. Protocol Collection Settlement

Anyone can call `settle_protocol_fee_and_record` for orders (this is a permissionless endpoint):

- The function checks if the order is still live in the DeepBook pool
- If the order is no longer live (filled or cancelled), the entire remaining unsettled fee balance moves to the protocol's main fee vault
- This ensures the protocol only claims fees from finalized orders

## Order Type Support

The system supports various order types:

- **IOC (including market orders) and FOK orders**: Charged as taker fees since they execute immediately
- **Post-only orders**: Charged as maker fees for the entire order (0 taker fee)
- **General no-restriction orders**: Dynamic fee calculation as described above

## Design Limitations

### 1. Order Expiration Time

- **Limitation**: Only orders without expiration time are supported
- **Reason**: If an order expires, there's no technical way to return unsettled fees to the user, because expired orders no longer exist in the order book and become inaccessible

### 2. Self-Matching Options

- **Limitation**: Self-matching types like "cancel maker" or "cancel taker" are not supported
- **Reason**: These options can implicitly cancel the user's own orders, blocking fee settlement since cancelled orders no longer exist in the order book and become inaccessible

### 3. Order Modifications

- **Current status**: Order modifications are not allowed
- **Future improvement**: Will require a custom function (similar to cancellation) to properly settle fees during modifications

### 4. External Order Cancellation

- **Risk**: If a user places an order through our platform but cancels it externally, they lose the unsettled fees
- **Reason**: Once an order ceases to exist in the order book, there's no way to retrieve information about it

## Key Security Feature

The protocol collection mechanism includes a crucial security check: fees can only be claimed from orders that are confirmed as finalized by the DeepBook pool. This prevents premature fee collection and ensures system correctness.
