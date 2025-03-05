module deepbook_wrapper::swap {
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use deepbook::pool::{Self, Pool};
    use deepbook_wrapper::wrapper::{
      DeepBookV3RouterWrapper,
      join_fee, join,
      get_deep_reserves_value,
      split_deep_reserves
    };
    use deepbook_wrapper::helper::{get_fee_bps};
    use deepbook_wrapper::fee::{calculate_deep_reserves_coverage_fee, charge_deep_reserves_coverage_fee};

    // === Public-Mutative Functions ===
    /// Swap exact base token amount for quote tokens
    public fun swap_exact_base_for_quote<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        pool: &mut Pool<BaseToken, QuoteToken>,
        base_in: Coin<BaseToken>,
        min_quote_out: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<BaseToken>, Coin<QuoteToken>) {
        let deep_payment = if (pool::whitelisted(pool)) {
            coin::zero(ctx)
        } else {
            let deep_reserves_value = get_deep_reserves_value(wrapper);
            split_deep_reserves(wrapper, deep_reserves_value, ctx)
        };

        let (base_remainder, quote_out, deep_remainder) = pool::swap_exact_quantity(
            pool,
            base_in,
            coin::zero(ctx),
            deep_payment,
            min_quote_out,
            clock,
            ctx
        );

        let mut result_quote = quote_out;
        join(wrapper, deep_remainder);

        let fee_bps = get_fee_bps(pool);
        join_fee(wrapper, charge_deep_reserves_coverage_fee(&mut result_quote, fee_bps));
        
        (base_remainder, result_quote)
    }
    
    /// Swap exact quote token amount for base tokens
    public fun swap_exact_quote_for_base<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        pool: &mut Pool<BaseToken, QuoteToken>,
        quote_in: Coin<QuoteToken>,
        min_base_out: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<BaseToken>, Coin<QuoteToken>) {  
        let deep_payment = if (pool::whitelisted(pool)) {
            coin::zero(ctx)
        } else {
            let deep_reserves_value = get_deep_reserves_value(wrapper);
            split_deep_reserves(wrapper, deep_reserves_value, ctx)
        };

        let (base_out, quote_remainder, deep_remainder) = pool::swap_exact_quantity(
            pool,
            coin::zero(ctx),
            quote_in,
            deep_payment,
            min_base_out,
            clock,
            ctx
        );

        let mut result_base = base_out;
        join(wrapper, deep_remainder);

        let fee_bps = get_fee_bps(pool);
        join_fee(wrapper, charge_deep_reserves_coverage_fee(&mut result_base, fee_bps));
        
        (result_base, quote_remainder)
    }

    // === Public-View Functions ===
    /// Calculate the expected output quantity accounting for both DeepBook fees and wrapper fees
    public fun get_quantity_out<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        base_quantity: u64,
        quote_quantity: u64,
        clock: &Clock,
    ): (u64, u64, u64) {
        // Get the raw output quantities from DeepBook
        // This method can return zero values in case input quantities don't meet the minimum lot size
        let (mut base_out, mut quote_out, deep_required) = pool::get_quantity_out(
            pool,
            base_quantity,
            quote_quantity,
            clock
        );
        
        // Get the fee basis points from the pool
        let fee_bps = get_fee_bps(pool);
        
        // Apply our fee to the output quantities
        // If base_quantity > 0, we're swapping base for quote, so apply fee to quote_out
        // If quote_quantity > 0, we're swapping quote for base, so apply fee to base_out
        if (base_quantity > 0) {
            // Swapping base for quote, apply fee to quote_out
            let fee_amount = calculate_deep_reserves_coverage_fee(quote_out, fee_bps);
            quote_out = quote_out - fee_amount;
        } else if (quote_quantity > 0) {
            // Swapping quote for base, apply fee to base_out
            let fee_amount = calculate_deep_reserves_coverage_fee(base_out, fee_bps);
            base_out = base_out - fee_amount;
        };
        
        (base_out, quote_out, deep_required)
    }
}