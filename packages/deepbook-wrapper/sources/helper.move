module deepbook_wrapper::helper {
    use sui::coin::{Self, Coin};
    use deepbook::pool::{Self, Pool};
    use deepbook_wrapper::math;

    // === Constants ===
    const DEEP_REQUIRED_SLIPPAGE: u64 = 100_000_000; // 10% in billionths

    // === Public-Package Functions ===
    /// Get fee basis points from pool parameters
    public(package) fun get_fee_bps<BaseToken, QuoteToken>(pool: &Pool<BaseToken, QuoteToken>): u64 {
        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        fee_bps
    }

    /// Helper function to transfer non-zero coins or destroy zero coins
    public(package) fun transfer_if_nonzero<CoinType>(coins: Coin<CoinType>, recipient: address) {
        if (coin::value(&coins) > 0) {
            transfer::public_transfer(coins, recipient);
        } else {
            coin::destroy_zero(coins);
        };
    }

    /// Determines if a pool is whitelisted
    /// Whitelisted pools don't require DEEP tokens and don't charge fees
    public(package) fun is_pool_whitelisted<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>
    ): bool {
        pool::whitelisted(pool)
    }
    
    /// Calculates the total amount of DEEP required for an order
    /// Returns 0 for whitelisted pools
    public(package) fun calculate_deep_required<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        quantity: u64,
        price: u64
    ): u64 {
        if (is_pool_whitelisted(pool)) {
            0
        } else {
            let (deep_req, _) = pool::get_order_deep_required(pool, quantity, price);

            // We need to apply slippage to the deep required because the VIEW deep required from
            // `pool::get_order_deep_required` can be different from the ACTUAL deep required`
            // when placing an order.
            //
            // For example, this can be potentially observed when setting a SELL order with a price
            // lower than the current market price.
            let deep_req_with_slippage = apply_slippage(deep_req, DEEP_REQUIRED_SLIPPAGE);

            deep_req_with_slippage
        }
    }

    /// Applies slippage to a value and returns the result
    /// The slippage is in billionths format (e.g., 5_000_000 = 0.5%)
    /// For small values, the slippage might be rounded down to zero due to integer division
    public(package) fun apply_slippage(value: u64, slippage: u64): u64 {
        // Handle special case: if value is 0, no slippage is needed
        if (value == 0) {
            return 0
        };
        
        // Calculate slippage amount
        let slippage_amount = math::mul(value, slippage);
        
        // Add slippage to original value
        value + slippage_amount
    }

    /// Calculates the order amount in tokens (quote for bid, base for ask)
    public(package) fun calculate_order_amount(
        quantity: u64,
        price: u64,
        is_bid: bool
    ): u64 {
        if (is_bid) {
            math::mul(quantity, price) // Quote tokens for bid
        } else {
            quantity // Base tokens for ask
        }
    }
}