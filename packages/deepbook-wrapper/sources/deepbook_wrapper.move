module deepbook_wrapper::wrapper {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::bag::{Self, Bag};
    use sui::clock::Clock;
    
    // Import from other packages
    use token::deep::DEEP;
    use deepbook_wrapper::admin::AdminCap;
    use deepbook_wrapper::math;
    use deepbook::pool::{Self, Pool};
    use deepbook::balance_manager::{Self, BalanceManager};

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

    /// Error when trying to use a fund capability with a different wrapper than it was created for
    #[error]
    const EInvalidFundCap: u64 = 1;
    
    /// Error when trying to use deep from reserves but there is not enough available
    #[error]
    const EInsufficientDeepReserves: u64 = 2;

    /// Error when the input amount is insufficient after fees
    #[error]
    const EInsufficientFeeOrInput: u64 = 3;

    /// Error when the caller is not the owner of the balance manager
    #[error]
    const EInvalidOwner: u64 = 4;
    
    /// Define a constant for the fee scaling factor
    /// This matches DeepBook's FLOAT_SCALING constant (10^9) used for fee calculations
    /// Fees are expressed in billionths, e.g., 1,000,000 = 0.1% (1,000,000/1,000,000,000)
    const FEE_SCALING: u64 = 1_000_000_000;

    /// Calculates the fee amount based on the token amount and fee rate
    /// @param amount - The amount of tokens to calculate fee on
    /// @param fee_bps - The fee rate in billionths (e.g., 1,000,000 = 0.1%)
    /// @return The calculated fee amount
    fun calculate_fee_amount(amount: u64, fee_bps: u64): u64 {
        ((amount as u128) * (fee_bps as u128) / (FEE_SCALING as u128)) as u64
    }
    
    /// Charges a fee on a coin by splitting off a portion based on the fee rate
    /// @param coin - The coin to charge fee from
    /// @param fee_bps - The fee rate in billionths (from DeepBook pool parameters)
    /// @return The fee amount as a Balance
    fun charge_fee<CoinType>(coin: &mut Coin<CoinType>, fee_bps: u64): Balance<CoinType> {
        let coin_balance = coin::balance_mut(coin);
        let value = balance::value(coin_balance);
        balance::split(coin_balance, calculate_fee_amount(value, fee_bps))
    }

    /// Join DEEP coins into the router's reserves
    public fun join(wrapper: &mut DeepBookV3RouterWrapper, deep_coin: Coin<DEEP>) {
        balance::join(&mut wrapper.deep_reserves, coin::into_balance(deep_coin));
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

        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        join_fee(wrapper, charge_fee(&mut result_quote, fee_bps));
        
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

        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        join_fee(wrapper, charge_fee(&mut result_base, fee_bps));
        
        (result_base, quote_remainder)
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
        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        
        // Apply our fee to the output quantities
        // If base_quantity > 0, we're swapping base for quote, so apply fee to quote_out
        // If quote_quantity > 0, we're swapping quote for base, so apply fee to base_out
        if (base_quantity > 0) {
            // Swapping base for quote, apply fee to quote_out
            let fee_amount = calculate_fee_amount(quote_out, fee_bps);
            quote_out = quote_out - fee_amount;
        } else if (quote_quantity > 0) {
            // Swapping quote for base, apply fee to base_out
            let fee_amount = calculate_fee_amount(base_out, fee_bps);
            base_out = base_out - fee_amount;
        };
        
        (base_out, quote_out, deep_required)
    }

    /// Estimate order requirements for a limit order
    /// Returns whether the order can be created, DEEP required, and estimated fee
    public fun estimate_order_requirements<BaseToken, QuoteToken>(
        wrapper: &DeepBookV3RouterWrapper,
        pool: &Pool<BaseToken, QuoteToken>,
        balance_manager: &BalanceManager,
        deep_in_wallet: u64,
        base_in_wallet: u64,
        quote_in_wallet: u64,
        quantity: u64,
        price: u64,
        is_bid: bool
    ): (bool, u64, u64) {
        // Check if pool is whitelisted
        let is_whitelisted = pool::whitelisted(pool);
        
        // Calculate required DEEP (0 for whitelisted pools)
        let deep_required = if (is_whitelisted) {
            0
        } else {
            let (deep_req, _) = pool::get_order_deep_required(pool, quantity, price);
            deep_req
        };
        
        // For non-whitelisted pools, check if there's enough DEEP across all sources
        let mut will_use_wrapper_deep = false;
        
        if (!is_whitelisted) {
            // Check DEEP from balance manager
            let deep_in_manager = balance_manager::balance<DEEP>(balance_manager);
            
            // Total DEEP from user's sources
            let user_deep_total = deep_in_manager + deep_in_wallet;
            
            if (user_deep_total < deep_required) {
                // Need to use wrapper DEEP
                let additional_deep_needed = deep_required - user_deep_total;
                will_use_wrapper_deep = true;
                
                // Check if wrapper has enough DEEP
                if (balance::value(&wrapper.deep_reserves) < additional_deep_needed) {
                    return (false, deep_required, 0) // Not enough DEEP, can't place order
                }
            }
        };
        
        // Calculate fee, but only if we're using wrapper DEEP
        let fee_bps = get_fee_bps(pool);
        let fee_estimate = if (is_whitelisted || !will_use_wrapper_deep) {
            0 // No fee for whitelisted pools or when user provides all DEEP
        } else {
            // Calculate fee based on the order amount
            let order_amount = if (is_bid) {
                math::mul(quantity, price) // Quote tokens for bid
            } else {
                quantity // Base tokens for ask
            };
            
            calculate_fee_amount(order_amount, fee_bps)
        };
        
        // Validate order parameters - always required regardless of whitelist status
        let valid_params = validate_pool_params(pool, quantity, price);
        
        // Verify sufficient tokens from all sources
        let sufficient_tokens = if (is_bid) {
            // For bid orders, check if user has enough quote tokens
            let quote_required = math::mul(quantity, price);
            let quote_in_manager = balance_manager::balance<QuoteToken>(balance_manager);
            let total_quote_available = quote_in_manager + quote_in_wallet;
            
            // Need to account for fee if using wrapper DEEP
            if (will_use_wrapper_deep) {
                total_quote_available >= (quote_required + fee_estimate)
            } else {
                total_quote_available >= quote_required
            }
        } else {
            // For ask orders, check if user has enough base tokens
            let base_in_manager = balance_manager::balance<BaseToken>(balance_manager);
            let total_base_available = base_in_manager + base_in_wallet;
            
            // Need to account for fee if using wrapper DEEP
            if (will_use_wrapper_deep) {
                total_base_available >= (quantity + fee_estimate)
            } else {
                total_base_available >= quantity
            }
        };
        
        (valid_params && sufficient_tokens, deep_required, fee_estimate)
    }
    
    /// Helper function to validate pool parameters
    fun validate_pool_params<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        quantity: u64,
        price: u64
    ): bool {
        let (tick_size, lot_size, min_size) = pool::pool_book_params(pool);
        
        quantity >= min_size && 
        quantity % lot_size == 0 && 
        price % tick_size == 0
    }

    /// Create a limit order using tokens from various sources
    /// Returns the order info
    public fun create_limit_order<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        pool: &mut Pool<BaseToken, QuoteToken>,
        balance_manager: &mut BalanceManager,
        mut base_coin: Coin<BaseToken>,
        mut quote_coin: Coin<QuoteToken>,
        mut deep_coin: Coin<DEEP>,
        price: u64,
        quantity: u64,
        is_bid: bool,
        expire_timestamp: u64,
        client_order_id: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (deepbook::order_info::OrderInfo) {
        // Verify the caller owns the balance manager
        assert!(balance_manager::owner(balance_manager) == tx_context::sender(ctx), EInvalidOwner);
        
        // Check if pool is whitelisted
        let is_whitelisted = pool::whitelisted(pool);
        
        // Handle DEEP requirements (only if not whitelisted)
        // This returns whether wrapper DEEP was used
        let used_wrapper_deep = if (!is_whitelisted) {
            ensure_deep_for_order(wrapper, pool, balance_manager, &mut deep_coin, quantity, price, ctx)
        } else {
            false
        };
        
        let fee_bps = get_fee_bps(pool);
        
        // Handle input coin requirements and fees based on order type
        if (is_bid) {
            // For bid orders, calculate the quote token amount needed
            let order_value = math::mul(quantity, price);
            
            // First collect fees if wrapper DEEP was used (do this before any deposits)
            if (used_wrapper_deep) {
                // For bids, fee is based on the quote tokens being spent (order_value)
                collect_fee_for_amount<QuoteToken>(
                    wrapper,
                    balance_manager,
                    &mut quote_coin,
                    order_value,
                    fee_bps,
                    ctx
                );
            };
            
            // Then ensure enough tokens for the order
            ensure_quote_for_order<QuoteToken>(
                balance_manager,
                &mut quote_coin,
                order_value,
                ctx
            );
        } else {
            // For ask orders, we need to ensure base tokens and potentially charge fees
            // First collect fees if wrapper DEEP was used (do this before any deposits)
            if (used_wrapper_deep) {
                // For asks, fee is based on the base tokens being spent (quantity)
                collect_fee_for_amount<BaseToken>(
                    wrapper, 
                    balance_manager,
                    &mut base_coin,
                    quantity,
                    fee_bps,
                    ctx
                );
            };
            
            // Then ensure enough tokens for the order
            ensure_base_for_order<BaseToken>(
                balance_manager,
                &mut base_coin,
                quantity,
                ctx
            );
        };
        
        // Return unused tokens to the caller
        transfer_if_nonzero(base_coin, tx_context::sender(ctx));
        transfer_if_nonzero(quote_coin, tx_context::sender(ctx));
        transfer_if_nonzero(deep_coin, tx_context::sender(ctx));
        
        // Generate proof and place order
        let proof = balance_manager::generate_proof_as_owner(balance_manager, ctx);
        
        pool::place_limit_order(
            pool,
            balance_manager,
            &proof,
            client_order_id,
            0, // default order type (limit)
            0, // default self matching option
            price,
            quantity,
            is_bid,
            !is_whitelisted, // pay_with_deep is true only if not whitelisted
            expire_timestamp,
            clock,
            ctx
        )
    }
    
    /// Collect fee for a specific amount rather than the entire balance
    /// This ensures fees are calculated only on the amount used in the order
    fun collect_fee_for_amount<TokenType>(
        wrapper: &mut DeepBookV3RouterWrapper,
        balance_manager: &mut BalanceManager,
        input_coin: &mut Coin<TokenType>,
        order_value: u64,
        fee_bps: u64,
        ctx: &mut TxContext
    ) {
        // Calculate fee based on the specific amount, not the entire balance
        let fee_amount = calculate_fee_amount(order_value, fee_bps);
        
        if (fee_amount == 0) {
            return // No fee to collect
        };
        
        // Check wallet first
        let wallet_balance = coin::value(input_coin);
        
        if (wallet_balance >= fee_amount) {
            // Wallet has enough to cover the fee
            let wallet_fee = coin::split(input_coin, fee_amount, ctx);
            join_fee(wrapper, coin::into_balance(wallet_fee));
            return
        };
        
        // Use whatever we can from wallet
        let from_wallet = if (wallet_balance > 0) {
            let wallet_fee = coin::split(input_coin, wallet_balance, ctx);
            join_fee(wrapper, coin::into_balance(wallet_fee));
            wallet_balance
        } else {
            0
        };
        
        // If we still need more fee, try to get it from balance manager
        if (from_wallet < fee_amount) {
            let remaining_fee = fee_amount - from_wallet;
            let manager_balance = balance_manager::balance<TokenType>(balance_manager);
            
            assert!(manager_balance >= remaining_fee, EInsufficientFeeOrInput);
            
            // Withdraw from balance manager to collect the rest of the fee
            let manager_fee = balance_manager::withdraw<TokenType>(
                balance_manager,
                remaining_fee,
                ctx
            );
            join_fee(wrapper, coin::into_balance(manager_fee));
        };
    }

    /// Ensure sufficient quote tokens for an order, depositing from wallet if needed
    fun ensure_quote_for_order<QuoteToken>(
        balance_manager: &mut BalanceManager,
        quote_coin: &mut Coin<QuoteToken>,
        required_amount: u64,
        ctx: &mut TxContext
    ) {
        // Check balance manager for quote tokens
        let quote_in_manager = balance_manager::balance<QuoteToken>(balance_manager);
        
        if (quote_in_manager < required_amount) {
            // Calculate how much more is needed
            let additional_quote_needed = required_amount - quote_in_manager;
            
            // Check wallet for quote tokens
            let quote_in_wallet = coin::value(quote_coin);
            assert!(quote_in_wallet >= additional_quote_needed, EInsufficientFeeOrInput);
            
            // Split required tokens from wallet and deposit to balance manager
            let order_payment = coin::split(quote_coin, additional_quote_needed, ctx);
            balance_manager::deposit(balance_manager, order_payment, ctx);
        };
    }

    /// Ensure sufficient base tokens for an order, depositing from wallet if needed
    fun ensure_base_for_order<BaseToken>(
        balance_manager: &mut BalanceManager,
        base_coin: &mut Coin<BaseToken>,
        required_amount: u64,
        ctx: &mut TxContext
    ) {
        // Check balance manager for base tokens
        let base_in_manager = balance_manager::balance<BaseToken>(balance_manager);
        
        if (base_in_manager < required_amount) {
            // Calculate how much more is needed
            let additional_base_needed = required_amount - base_in_manager;
            
            // Check wallet for base tokens
            let base_in_wallet = coin::value(base_coin);
            assert!(base_in_wallet >= additional_base_needed, EInsufficientFeeOrInput);
            
            // Split required tokens from wallet and deposit to balance manager
            let order_payment = coin::split(base_coin, additional_base_needed, ctx);
            balance_manager::deposit(balance_manager, order_payment, ctx);
        };
    }

    /// Ensure sufficient DEEP for the order, using multiple sources
    /// Returns whether wrapper DEEP was used
    fun ensure_deep_for_order<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        pool: &Pool<BaseToken, QuoteToken>,
        balance_manager: &mut BalanceManager,
        deep_coin: &mut Coin<DEEP>,
        quantity: u64,
        price: u64,
        ctx: &mut TxContext
    ): bool {
        // Calculate DEEP required
        let (deep_required, _) = pool::get_order_deep_required(pool, quantity, price);
        
        // First, check balance manager for DEEP
        let deep_in_manager = balance_manager::balance<DEEP>(balance_manager);
        
        if (deep_in_manager >= deep_required) {
            // Balance manager already has enough DEEP
            return false // Didn't use wrapper DEEP
        };
        
        // Need additional DEEP - calculate how much
        let additional_deep_needed = deep_required - deep_in_manager;
        
        // Check if user's wallet has enough DEEP
        let deep_in_wallet = coin::value(deep_coin);
        
        if (deep_in_wallet >= additional_deep_needed) {
            // User has enough DEEP in wallet, deposit the needed amount
            let payment = coin::split(deep_coin, additional_deep_needed, ctx);
            balance_manager::deposit(balance_manager, payment, ctx);
            return false // Didn't use wrapper DEEP
        };
        
        // User doesn't have enough DEEP combined, use wrapper reserves and charge fees
        let deep_from_user = if (deep_in_wallet > 0) {
            // Take whatever DEEP user has in wallet
            let payment = coin::split(deep_coin, deep_in_wallet, ctx);
            balance_manager::deposit(balance_manager, payment, ctx);
            deep_in_wallet
        } else {
            0
        };
        
        // Use wrapper reserves for the remaining DEEP
        let still_needed = deep_required - deep_in_manager - deep_from_user;
        
        assert!(balance::value(&wrapper.deep_reserves) >= still_needed, EInsufficientDeepReserves);
        
        let reserve_payment = coin::from_balance(
            balance::split(&mut wrapper.deep_reserves, still_needed),
            ctx
        );
        
        balance_manager::deposit(balance_manager, reserve_payment, ctx);
        
        // Used wrapper DEEP
        true
    }

    /// Get fee basis points from pool parameters
    fun get_fee_bps<BaseToken, QuoteToken>(pool: &Pool<BaseToken, QuoteToken>): u64 {
        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        fee_bps
    }
    
    /// Helper function to transfer non-zero coins or destroy zero coins
    fun transfer_if_nonzero<CoinType>(coins: Coin<CoinType>, recipient: address) {
        if (coin::value(&coins) > 0) {
            transfer::public_transfer(coins, recipient);
        } else {
            coin::destroy_zero(coins);
        };
    }
}