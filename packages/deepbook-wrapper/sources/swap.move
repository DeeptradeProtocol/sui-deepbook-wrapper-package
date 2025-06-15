module deepbook_wrapper::swap;

use deepbook::pool::{Self, Pool};
use deepbook_wrapper::fee::{calculate_fee_by_rate, charge_swap_fee};
use deepbook_wrapper::helper::get_fee_bps;
use deepbook_wrapper::wrapper::{
    Wrapper,
    join_deep_reserves_coverage_fee,
    join,
    split_deep_reserves
};
use sui::clock::Clock;
use sui::coin::{Self, Coin};

// === Errors ===
/// Error when the final output amount is below the user's specified minimum
const EInsufficientOutputAmount: u64 = 1;

// === Public-Mutative Functions ===
/// Swaps a specific amount of base tokens for quote tokens.
///
/// # Arguments
/// * `wrapper` - The Wrapper object holding protocol state and DEEP reserves
/// * `pool` - The DeepBook liquidity pool for this trading pair
/// * `base_in` - The base tokens being provided for the swap
/// * `min_quote_out` - Minimum amount of quote tokens to receive (slippage protection)
/// * `clock` - Clock object for timestamp information
/// * `ctx` - Transaction context
///
/// # Returns
/// * `(Coin<BaseToken>, Coin<QuoteToken>)` - Any unused base tokens and the received quote tokens
///
/// # Flow
/// 1. Handles DEEP payment for non-whitelisted pools
/// 2. Executes swap through DeepBook
/// 3. Processes wrapper fees
/// 4. Validates minimum output amount meets user requirements
/// 5. Returns remaining base and received quote tokens
public fun swap_exact_base_for_quote<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    pool: &mut Pool<BaseToken, QuoteToken>,
    base_in: Coin<BaseToken>,
    min_quote_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<BaseToken>, Coin<QuoteToken>) {
    // Determine if DEEP payment is needed based on pool whitelist status
    let deep_payment = if (pool::whitelisted(pool)) {
        coin::zero(ctx)
    } else {
        let base_quantity = base_in.value();
        let (_, _, deep_required) = pool.get_quote_quantity_out(base_quantity, clock);
        split_deep_reserves(wrapper, deep_required, ctx)
    };

    // Execute swap through DeepBook's native swap function
    let (base_remainder, quote_out, deep_remainder) = pool::swap_exact_quantity(
        pool,
        base_in,
        coin::zero(ctx),
        deep_payment,
        min_quote_out,
        clock,
        ctx,
    );

    // Apply wrapper protocol fees to the output
    let mut result_quote = quote_out;
    join(wrapper, deep_remainder);

    let fee_bps = get_fee_bps(pool);
    join_deep_reserves_coverage_fee(wrapper, charge_swap_fee(&mut result_quote, fee_bps));

    // Verify that the final output after wrapper fees still meets the user's minimum requirement
    validate_minimum_output(&result_quote, min_quote_out);

    (base_remainder, result_quote)
}

/// Swaps a specific amount of quote tokens for base tokens.
///
/// # Arguments
/// * `wrapper` - The Wrapper object holding protocol state and DEEP reserves
/// * `pool` - The DeepBook liquidity pool for this trading pair
/// * `quote_in` - The quote tokens being provided for the swap
/// * `min_base_out` - Minimum amount of base tokens to receive (slippage protection)
/// * `clock` - Clock object for timestamp information
/// * `ctx` - Transaction context
///
/// # Returns
/// * `(Coin<BaseToken>, Coin<QuoteToken>)` - The received base tokens and any unused quote tokens
///
/// # Flow
/// 1. Handles DEEP payment for non-whitelisted pools
/// 2. Executes swap through DeepBook
/// 3. Processes wrapper fees
/// 4. Validates minimum output amount meets user requirements
/// 5. Returns received base and remaining quote tokens
public fun swap_exact_quote_for_base<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    pool: &mut Pool<BaseToken, QuoteToken>,
    quote_in: Coin<QuoteToken>,
    min_base_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<BaseToken>, Coin<QuoteToken>) {
    // Determine if DEEP payment is needed based on pool whitelist status
    let deep_payment = if (pool::whitelisted(pool)) {
        coin::zero(ctx)
    } else {
        let quote_quantity = quote_in.value();
        let (_, _, deep_required) = pool.get_base_quantity_out(quote_quantity, clock);
        split_deep_reserves(wrapper, deep_required, ctx)
    };

    // Execute swap through DeepBook's native swap function
    let (base_out, quote_remainder, deep_remainder) = pool::swap_exact_quantity(
        pool,
        coin::zero(ctx),
        quote_in,
        deep_payment,
        min_base_out,
        clock,
        ctx,
    );

    // Apply wrapper protocol fees to the output
    let mut result_base = base_out;
    join(wrapper, deep_remainder);

    let fee_bps = get_fee_bps(pool);
    join_deep_reserves_coverage_fee(wrapper, charge_swap_fee(&mut result_base, fee_bps));

    // Verify that the final output after wrapper fees still meets the user's minimum requirement
    validate_minimum_output(&result_base, min_base_out);

    (result_base, quote_remainder)
}

/// Swaps a specific amount of base tokens for quote tokens using input fee model.
/// Similar to swap_exact_base_for_quote but uses input coin fees instead of DEEP.
///
/// # Arguments
/// * `wrapper` - The Wrapper object holding protocol state and DEEP reserves
/// * `pool` - The DeepBook liquidity pool for this trading pair
/// * `base_in` - The base tokens being provided for the swap
/// * `min_quote_out` - Minimum amount of quote tokens to receive (slippage protection)
/// * `clock` - Clock object for timestamp information
/// * `ctx` - Transaction context
///
/// # Returns
/// * `(Coin<BaseToken>, Coin<QuoteToken>)` - Any unused base tokens and the received quote tokens
///
/// # Flow
/// 1. Executes swap through DeepBook
/// 2. Processes wrapper fees
/// 3. Validates minimum output amount meets user requirements
/// 4. Returns remaining base and received quote tokens
public fun swap_exact_base_for_quote_input_fee<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    pool: &mut Pool<BaseToken, QuoteToken>,
    base_in: Coin<BaseToken>,
    min_quote_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<BaseToken>, Coin<QuoteToken>) {
    // Execute swap through DeepBook's native swap function with input fee model
    let (base_remainder, quote_out, deep_remainder) = pool::swap_exact_quantity(
        pool,
        base_in,
        coin::zero(ctx),
        coin::zero(ctx), // No DEEP payment needed for input fee model
        min_quote_out,
        clock,
        ctx,
    );

    // Apply wrapper protocol fees to the output
    let mut result_quote = quote_out;
    // The `deep_remainder` is just an empty coin, so it could be either destroyed or joined to the wrapper reserves
    join(wrapper, deep_remainder);

    let fee_bps = get_fee_bps(pool);
    join_deep_reserves_coverage_fee(wrapper, charge_swap_fee(&mut result_quote, fee_bps));

    // Verify that the final output after wrapper fees still meets the user's minimum requirement
    validate_minimum_output(&result_quote, min_quote_out);

    (base_remainder, result_quote)
}

/// Swaps a specific amount of quote tokens for base tokens using input fee model.
/// Similar to swap_exact_quote_for_base but uses input coin fees instead of DEEP.
///
/// # Arguments
/// * `wrapper` - The Wrapper object holding protocol state and DEEP reserves
/// * `pool` - The DeepBook liquidity pool for this trading pair
/// * `quote_in` - The quote tokens being provided for the swap
/// * `min_base_out` - Minimum amount of base tokens to receive (slippage protection)
/// * `clock` - Clock object for timestamp information
/// * `ctx` - Transaction context
///
/// # Returns
/// * `(Coin<BaseToken>, Coin<QuoteToken>)` - The received base tokens and any unused quote tokens
///
/// # Flow
/// 1. Executes swap through DeepBook
/// 2. Processes wrapper fees
/// 3. Validates minimum output amount meets user requirements
/// 4. Returns received base and remaining quote tokens
public fun swap_exact_quote_for_base_input_fee<BaseToken, QuoteToken>(
    wrapper: &mut Wrapper,
    pool: &mut Pool<BaseToken, QuoteToken>,
    quote_in: Coin<QuoteToken>,
    min_base_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<BaseToken>, Coin<QuoteToken>) {
    // Execute swap through DeepBook's native swap function with input fee model
    let (base_out, quote_remainder, deep_remainder) = pool::swap_exact_quantity(
        pool,
        coin::zero(ctx),
        quote_in,
        coin::zero(ctx), // No DEEP payment needed for input fee model
        min_base_out,
        clock,
        ctx,
    );

    // Apply wrapper protocol fees to the output
    let mut result_base = base_out;
    // The `deep_remainder` is just an empty coin, so it could be either destroyed or joined to the wrapper reserves
    join(wrapper, deep_remainder);

    let fee_bps = get_fee_bps(pool);
    join_deep_reserves_coverage_fee(wrapper, charge_swap_fee(&mut result_base, fee_bps));

    // Verify that the final output after wrapper fees still meets the user's minimum requirement
    validate_minimum_output(&result_base, min_base_out);

    (result_base, quote_remainder)
}

// === Public-View Functions ===
/// Calculate the expected output quantity accounting for both DeepBook fees and wrapper fees
///
/// # Arguments
/// * `pool` - The DeepBook liquidity pool for this trading pair
/// * `base_quantity` - Amount of base tokens to swap (set to 0 if swapping quote)
/// * `quote_quantity` - Amount of quote tokens to swap (set to 0 if swapping base)
/// * `clock` - Clock object for timestamp information
///
/// # Returns
/// * `(u64, u64, u64)` - Tuple containing:
///   - Expected base token output
///   - Expected quote token output
///   - Required DEEP amount for transaction
///
/// # Flow
/// 1. Gets raw output quantities from DeepBook
/// 2. Applies wrapper protocol fees to the appropriate output amount based on swap direction
/// 3. Returns final expected output quantities and required DEEP
public fun get_quantity_out<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    base_quantity: u64,
    quote_quantity: u64,
    clock: &Clock,
): (u64, u64, u64) {
    // Get the raw output quantities from DeepBook
    // This method can return zero values in case input quantities don't meet the minimum lot size
    let (base_out, quote_out, deep_required) = pool::get_quantity_out(
        pool,
        base_quantity,
        quote_quantity,
        clock,
    );

    let (base_out, quote_out) = apply_wrapper_fees(
        pool,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    (base_out, quote_out, deep_required)
}

/// Calculate the expected output quantity accounting for both DeepBook fees and wrapper fees
/// Uses input coin fee model instead of DEEP
///
/// # Arguments
/// * `pool` - The DeepBook liquidity pool for this trading pair
/// * `base_quantity` - Amount of base tokens to swap (set to 0 if swapping quote)
/// * `quote_quantity` - Amount of quote tokens to swap (set to 0 if swapping base)
/// * `clock` - Clock object for timestamp information
///
/// # Returns
/// * `(u64, u64, u64)` - Tuple containing:
///   - Expected base token output
///   - Expected quote token output
///   - Required DEEP amount for transaction
///
/// # Flow
/// 1. Gets raw output quantities from DeepBook using input fee model
/// 2. Applies wrapper protocol fees to the appropriate output amount based on swap direction
/// 3. Returns final expected output quantities
public fun get_quantity_out_input_fee<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    base_quantity: u64,
    quote_quantity: u64,
    clock: &Clock,
): (u64, u64, u64) {
    // Get the raw output quantities from DeepBook using input fee model
    // This method can return zero values in case input quantities don't meet the minimum lot size
    let (base_out, quote_out, deep_required) = pool::get_quantity_out_input_fee(
        pool,
        base_quantity,
        quote_quantity,
        clock,
    );

    let (base_out, quote_out) = apply_wrapper_fees(
        pool,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    (base_out, quote_out, deep_required)
}

// === Private Functions ===
/// Validates that a coin's value meets the minimum required amount
/// Aborts with EInsufficientOutputAmount if the check fails
///
/// # Arguments
/// * `coin` - The coin to validate
/// * `minimum` - The minimum required value
fun validate_minimum_output<CoinType>(coin: &Coin<CoinType>, minimum: u64) {
    assert!(coin.value() >= minimum, EInsufficientOutputAmount);
}

/// Applies wrapper protocol fees to the output quantities from a DeepBook swap operation.
/// This function handles fee calculations for both base-to-quote and quote-to-base swaps.
///
/// # Type Parameters
/// * `BaseToken` - The type of the base token in the trading pair
/// * `QuoteToken` - The type of the quote token in the trading pair
///
/// # Arguments
/// * `pool` - Reference to the DeepBook liquidity pool for the trading pair
/// * `base_out` - Mutable base token output quantity before fees
/// * `quote_out` - Mutable quote token output quantity before fees
/// * `base_quantity` - Input quantity of base tokens (0 if swapping quote)
/// * `quote_quantity` - Input quantity of quote tokens (0 if swapping base)
///
/// # Returns
/// * `(u64, u64)` - Tuple containing:
///   - Final base token output after fees
///   - Final quote token output after fees
///
/// # Fee Application Logic
/// * For base-to-quote swaps (base_quantity > 0): Fees are deducted from quote_out
/// * For quote-to-base swaps (quote_quantity > 0): Fees are deducted from base_out
/// * Fee amount is calculated using the pool's fee basis points
fun apply_wrapper_fees<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    mut base_out: u64,
    mut quote_out: u64,
    base_quantity: u64,
    quote_quantity: u64,
): (u64, u64) {
    // Get the fee basis points from the pool
    let fee_bps = get_fee_bps(pool);

    // Apply our fee to the output quantities
    // If base_quantity > 0, we're swapping base for quote, so apply fee to quote_out
    // If quote_quantity > 0, we're swapping quote for base, so apply fee to base_out
    if (base_quantity > 0) {
        // Swapping base for quote, apply fee to quote_out
        let fee_amount = calculate_fee_by_rate(quote_out, fee_bps);
        quote_out = quote_out - fee_amount;
    } else if (quote_quantity > 0) {
        // Swapping quote for base, apply fee to base_out
        let fee_amount = calculate_fee_by_rate(base_out, fee_bps);
        base_out = base_out - fee_amount;
    };

    (base_out, quote_out)
}
