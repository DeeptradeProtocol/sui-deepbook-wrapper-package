module deepbook_wrapper::wrapper {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::bag::{Self, Bag};
    use sui::clock::Clock;
    
    // Import from other packages
    use token::deep::DEEP;
    use deepbook_wrapper::admin::AdminCap;
    use deepbook::pool::{Self, Pool};

    /// Main router wrapper struct for DeepBook V3
    public struct DeepBookV3RouterWrapper has store, key {
        id: UID,
        deep_reserves: Balance<DEEP>,
        charged_fees: Bag,
    }
    
    /// Key struct for storing charged fees by coin type
    public struct ChargedFeeKey<phantom CoinType> has copy, drop, store {
        dummy_field: bool,
    }
    
    /// Capability for managing funds in the router
    public struct DeepBookV3FundCap has store, key {
        id: UID,
        wrapper_id: ID,
    }
    
    // === Errors ===
    #[error]
    const EInvalidFundCap: u64 = 1; // or whatever number isn't used yet
    
    /// Join DEEP coins into the router's reserves
    public fun join(wrapper: &mut DeepBookV3RouterWrapper, deep_coin: Coin<DEEP>) {
        balance::join(&mut wrapper.deep_reserves, coin::into_balance(deep_coin));
    }
    /// Calculate and charge fee from a coin
    fun charge_fee<CoinType>(coin: &mut Coin<CoinType>, fee_bps: u64): Balance<CoinType> {
        let coin_balance = coin::balance_mut(coin);
        let value = balance::value(coin_balance);
        balance::split(coin_balance, mul(value, fee_bps))
    }
    
    /// Create a new fund capability for the router
    public fun create_fund_cap(
        _admin: &AdminCap,
        wrapper: &DeepBookV3RouterWrapper,
        ctx: &mut TxContext
    ): DeepBookV3FundCap {
        DeepBookV3FundCap {
            id: object::new(ctx),
            wrapper_id: object::uid_to_inner(&wrapper.id),
        }
    }
    
    /// Initialize the router module
    fun init(ctx: &mut TxContext) {
        let wrapper = DeepBookV3RouterWrapper {
            id: object::new(ctx),
            deep_reserves: balance::zero(),
            charged_fees: bag::new(ctx),
        };
        transfer::share_object(wrapper);
    }
    
    /// Add collected fees to the router's fee storage
    fun join_fee<CoinType>(wrapper: &mut DeepBookV3RouterWrapper, fee: Balance<CoinType>) {
        if (balance::value(&fee) == 0) {
            balance::destroy_zero(fee);
            return
        };
        
        let key = ChargedFeeKey<CoinType> { dummy_field: false };
        if (bag::contains(&wrapper.charged_fees, key)) {
            balance::join(
                bag::borrow_mut(&mut wrapper.charged_fees, key),
                fee
            );
        } else {
            bag::add(&mut wrapper.charged_fees, key, fee);
        };
    }
    
    /// Helper function to calculate fee amount (with 9 decimal places)
    fun mul(a: u64, b: u64): u64 {
        ((a as u128) * (b as u128) / 1000000000) as u64
    }
    
    /// Swap exact base token amount for quote tokens
    public fun swap_exact_base_for_quote<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        pool: &mut Pool<BaseToken, QuoteToken>,
        base_in: Coin<BaseToken>,
        min_quote_out: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<QuoteToken> {
        
        let deep_payment = if (pool::whitelisted(pool)) {
            coin::zero(ctx)
        } else {
            let reserve_value = balance::value(&wrapper.deep_reserves);
            coin::from_balance(
                balance::split(&mut wrapper.deep_reserves, reserve_value),
                ctx
            )
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
        transfer_if_nonzero(base_remainder, tx_context::sender(ctx));

        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        join_fee(wrapper, charge_fee(&mut result_quote, fee_bps));
        
        result_quote
    }
    
    /// Swap exact quote token amount for base tokens
    public fun swap_exact_quote_for_base<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        pool: &mut Pool<BaseToken, QuoteToken>,
        quote_in: Coin<QuoteToken>,
        min_base_out: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<BaseToken> {        
        let deep_payment = if (pool::whitelisted(pool)) {
            coin::zero(ctx)
        } else {
            let reserve_value = balance::value(&wrapper.deep_reserves);
            coin::from_balance(
                balance::split(&mut wrapper.deep_reserves, reserve_value),
                ctx
            )
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
        transfer_if_nonzero(quote_remainder, tx_context::sender(ctx));

        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        join_fee(wrapper, charge_fee(&mut result_base, fee_bps));
        
        result_base
    }
    
    /// Helper function to transfer non-zero coins or destroy zero coins
    fun transfer_if_nonzero<CoinType>(coins: Coin<CoinType>, recipient: address) {
        if (coin::value(&coins) > 0) {
            transfer::public_transfer(coins, recipient);
        } else {
            coin::destroy_zero(coins);
        };
    }
    
    /// Withdraw collected fees for a specific coin type
    public fun withdraw_charged_fee<CoinType>(
        fund_cap: &DeepBookV3FundCap,
        wrapper: &mut DeepBookV3RouterWrapper,
        ctx: &mut TxContext
    ): Coin<CoinType> {
        assert!(fund_cap.wrapper_id == object::uid_to_inner(&wrapper.id), EInvalidFundCap);
        
        let key = ChargedFeeKey<CoinType> { dummy_field: false };
        if (bag::contains(&wrapper.charged_fees, key)) {
            coin::from_balance(
                balance::withdraw_all(
                    bag::borrow_mut(&mut wrapper.charged_fees, key)
                ),
                ctx
            )
        } else {
            coin::zero(ctx)
        }
    }
    
    /// Calculate the expected output quantity accounting for both DeepBook fees and wrapper fees
    public fun get_quantity_out<BaseToken, QuoteToken>(
        wrapper: &DeepBookV3RouterWrapper,
        pool: &Pool<BaseToken, QuoteToken>,
        base_quantity: u64,
        quote_quantity: u64,
        clock: &Clock,
    ): (u64, u64, u64) {
        // Get the raw output quantities from DeepBook
        let (base_out, quote_out, deep_required) = pool::get_quantity_out(
            pool,
            base_quantity,
            quote_quantity,
            clock
        );
        
        // Get the fee basis points from the pool
        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        
        // Apply our fee to the output quantities
        // If base_quantity > 0, we're swapping base for quote, so apply fee to quote_out
        // If quote_quantity > 0, we're swapping quote for base, so apply fee to base_out
        if (base_quantity > 0) {
            // Swapping base for quote, apply fee to quote_out
            let fee_amount = mul(quote_out, fee_bps);
            quote_out = quote_out - fee_amount;
        } else if (quote_quantity > 0) {
            // Swapping quote for base, apply fee to base_out
            let fee_amount = mul(base_out, fee_bps);
            base_out = base_out - fee_amount;
        };
        
        (base_out, quote_out, deep_required)
    }
}