# Oracle Pricing Security

## The Problem

The wrapper maintains DEEP reserves to help users who don't have enough DEEP for DeepBook trading fees. When users need DEEP from our reserves, we must calculate how much SUI to charge them as coverage fee and protocol fee.

Previously, the wrapper used only a reference pool (DEEP/SUI market on DeepBook) to get the DEEP/SUI price for this calculation.

This created a critical vulnerability:

**An attacker could:**

1. Drop the DEEP/SUI price in the reference pool within one transaction
2. Place a large limit order requiring DEEP from our reserves at the artificially low price
3. Immediately cancel the order to receive the settled in the order DEEP
4. Sell the acquired DEEP at normal market price in the same transaction
5. Repeat to drain our reserves while paying very little SUI

This attack was dangerous because it was atomic (single transaction) and could systematically drain our reserves.

## The Solution

We implemented **dual-price oracle security** that requires both oracle prices and reference pool prices to be healthy before users can take DEEP from reserves.

### How It Works

1. **Get Oracle Price**: Calculate DEEP/SUI from Pyth Network's DEEP/USD and SUI/USD feeds
2. **Get Reference Pool Price**: Extract price from DeepBook's DEEP/SUI pool
3. **Select Maximum**: Choose the higher price (users pay more SUI for DEEP) - reasoning explained below

### Oracle Validation

Oracle prices must pass strict checks:

- **Confidence**: Maximum 5% uncertainty
- **Freshness**: No older than 60 seconds
- **Valid feeds**: Correct DEEP/USD and SUI/USD identifiers

## Security Benefits

1. **Manipulation Resistance**: Oracle prices aggregate from multiple exchanges and cannot be manipulated by single DeepBook transactions
2. **Arbitrage Prevention**: Maximum price selection prevents users from exploiting price differences at our expense
3. **Dual Validation**: Both price sources must be healthy, forcing legitimate pricing or complete failure

## Fallback Mechanism

When oracle prices are unavailable, our client automatically switches users to **input coin fees** instead of using DEEP reserves. This maintains service availability without compromising security.

## Result

Oracle pricing transforms a critical vulnerability into robust security. Users get fair market rates while our DEEP reserves are protected from price manipulation attacks. The system maintains service availability through graceful fallbacks when oracles are unavailable.
