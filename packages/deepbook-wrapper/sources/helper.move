module deepbook_wrapper::helper {
    use sui::coin::{Self, Coin};
    use deepbook::pool::{Self, Pool};
    use deepbook_wrapper::math;

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
            deep_req
        }
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