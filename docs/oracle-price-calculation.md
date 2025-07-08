# Oracle Price Calculation Details

## DEEP/SUI Price Calculation

The `get_sui_per_deep_from_oracle` function calculates the DEEP/SUI price using oracle price feeds. This document explains the technical details of how this calculation works.

### Price Format Requirements

- DeepBook's DEEP/SUI price format requires 12 decimal places
- Oracle prices come with their own decimal places (exponents)
- All calculations must use Move's integer arithmetic

### Mathematical Derivation

To calculate DEEP/SUI price from DEEP/USD and SUI/USD oracle prices:

1. **Input Prices**:

   - DEEP/USD price = `deep_magnitude` with `deep_expo` decimal places
   - SUI/USD price = `sui_magnitude` with `sui_expo` decimal places

2. **Basic Formula**:

   ```
   DEEP/SUI = DEEP/USD ÷ SUI/USD
   ```

3. **Decimal Place Handling**:

   - `math::div` function adds 9 decimal places to division results
   - We need 12 decimal places in the final result
   - Need to account for different exponents from oracle prices

4. **Decimal Place Equation**:

   ```
   deep_expo + 9 - sui_expo + x = 12
   ```

   where `x` is our required adjustment

5. **Solving for Adjustment**:
   ```
   x = sui_expo + 3 - deep_expo
   ```

### Implementation Considerations

1. **Move Language Constraints**:

   - No negative number support
   - Integer arithmetic only
   - Aborts on overflow

2. **Precision Handling**:

   - Multiplier is applied to either numerator or denominator
   - This avoids early division and maintains precision
   - The position (numerator vs denominator) depends on whether the adjustment would be positive or negative

3. **Safety Guarantees**:
   - Price magnitudes must be positive (enforced by `get_magnitude_if_positive`)
   - Exponents must be negative (enforced by `get_magnitude_if_negative`)
   - Overflow protection is provided by Move's arithmetic checks
