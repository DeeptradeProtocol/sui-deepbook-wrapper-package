module deepbook_wrapper::order {
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use token::deep::DEEP;
    use deepbook_wrapper::math;
    use deepbook::pool::{Self, Pool};
    use deepbook::balance_manager::{Self, BalanceManager};
    use deepbook_wrapper::whitelisted_pools::{Self, WhitelistRegistry};
    use deepbook_wrapper::wrapper::{
      DeepBookV3RouterWrapper,
      join_fee,
      get_deep_reserves_value,
      split_deep_reserves
    };
    use deepbook_wrapper::helper::{
      calculate_deep_required,
      get_fee_bps,
      transfer_if_nonzero,
      calculate_order_amount
    };
    use deepbook_wrapper::fee::{estimate_full_fee_core, calculate_full_fee};

    // === Structs ===
    /// Data structure to represent DEEP requirements for an order
    public struct DeepPlan has copy, drop {
        use_wrapper_deep_reserves: bool,
        from_user_wallet: u64,
        from_deep_reserves: u64,
        deep_reserves_cover_order: bool
    }
    
    /// Data structure to represent fee collection plan
    public struct FeePlan has copy, drop {
        fee_coin_type: u8,     // 0 for no fee, 1 for base token, 2 for quote token
        fee_amount: u64,
        from_user_wallet: u64,
        from_user_balance_manager: u64,
        user_covers_wrapper_fee: bool
    }
    
    /// Data structure to represent token deposit requirements
    public struct InputCoinDepositPlan has copy, drop {
        order_amount: u64,
        from_user_wallet: u64,
        user_has_enough_input_coin: bool
    }

    // === Errors ===
    /// Error when trying to use deep from reserves but there is not enough available
    #[error]
    const EInsufficientDeepReserves: u64 = 1;

    /// Error when the input amount is insufficient after fees
    #[error]
    const EInsufficientFeeOrInput: u64 = 2;

    /// Error when the caller is not the owner of the balance manager
    #[error]
    const EInvalidOwner: u64 = 3;

    /// Error when the pool is not whitelisted by our protocol
    #[error]
    const ENotWhitelistedPool: u64 = 4;

    // === Public-Mutative Functions ===
    /// Create a limit order using tokens from various sources
    /// Returns the order info
    public fun create_limit_order<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        whitelisted_pools_registry: &WhitelistRegistry,
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

        // Verify the pool is whitelisted by our protocol
        assert!(whitelisted_pools::is_pool_whitelisted(whitelisted_pools_registry, pool), ENotWhitelistedPool);
        
        // Extract all the data we need from DeepBook objects
        let is_pool_whitelisted = pool::whitelisted(pool);
        let deep_required = calculate_deep_required(pool, quantity, price);
        let fee_bps = get_fee_bps(pool);
        
        // Get balances from balance manager
        let balance_manager_deep = balance_manager::balance<DEEP>(balance_manager);
        let balance_manager_base = balance_manager::balance<BaseToken>(balance_manager);
        let balance_manager_quote = balance_manager::balance<QuoteToken>(balance_manager);
        let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;
        
        // Get balances from wallet coins
        let deep_in_wallet = coin::value(&deep_coin);
        let base_in_wallet = coin::value(&base_coin);
        let quote_in_wallet = coin::value(&quote_coin);
        let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;
        
        // Get wrapper deep reserves
        let wrapper_deep_reserves = get_deep_reserves_value(wrapper);
        
        // Get the order plans from the core logic
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_input_coin,
            deep_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            fee_bps
        );
        
        // Step 1: Execute DEEP token plan
        execute_deep_plan(wrapper, balance_manager, &mut deep_coin, &deep_plan, ctx);
        
        // Step 2: Execute fee collection plan
        execute_fee_plan(
            wrapper,
            balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &fee_plan,
            ctx
        );
        
        // Step 3: Execute token deposit plan
        execute_input_coin_deposit_plan(
            balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &input_coin_deposit_plan,
            is_bid,
            ctx
        );
        
        // Return unused tokens to the caller
        transfer_if_nonzero(base_coin, tx_context::sender(ctx));
        transfer_if_nonzero(quote_coin, tx_context::sender(ctx));
        transfer_if_nonzero(deep_coin, tx_context::sender(ctx));
        
        // Step 4: Generate proof and place order
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
            !is_pool_whitelisted, // pay_with_deep is true only if not whitelisted
            expire_timestamp,
            clock,
            ctx
        )
    }

    // === Public-View Functions ===
    /// Estimate order requirements for a limit order
    /// Returns whether the order can be created, DEEP required, and estimated fee
    public fun estimate_order_requirements<BaseToken, QuoteToken>(
        wrapper: &DeepBookV3RouterWrapper,
        whitelisted_pools_registry: &WhitelistRegistry,
        pool: &Pool<BaseToken, QuoteToken>,
        balance_manager: &BalanceManager,
        deep_in_wallet: u64,
        base_in_wallet: u64,
        quote_in_wallet: u64,
        quantity: u64,
        price: u64,
        is_bid: bool
    ): (bool, u64, u64) {
        // Verify the pool is whitelisted by our protocol. If not, the order can't be created
        if (!whitelisted_pools::is_pool_whitelisted(whitelisted_pools_registry, pool)) {
            return (false, 0, 0)
        };

        // Get wrapper deep reserves
        let wrapper_deep_reserves = get_deep_reserves_value(wrapper);
        
        // Check if pool is whitelisted
        let is_pool_whitelisted = pool::whitelisted(pool);
        
        // Get pool parameters
        let (pool_fee_bps, _, _) = pool::pool_trade_params(pool);
        let (pool_tick_size, pool_lot_size, pool_min_size) = pool::pool_book_params(pool);
        
        // Get balance manager balances
        let balance_manager_deep = balance_manager::balance<DEEP>(balance_manager);
        let balance_manager_base = balance_manager::balance<BaseToken>(balance_manager);
        let balance_manager_quote = balance_manager::balance<QuoteToken>(balance_manager);
        
        // Calculate DEEP required
        let deep_required = calculate_deep_required(pool, quantity, price);
        
        // Call the core logic function
        estimate_order_requirements_core(
            wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            pool_tick_size,
            pool_lot_size,
            pool_min_size,
            balance_manager_deep,
            balance_manager_base,
            balance_manager_quote,
            deep_in_wallet,
            base_in_wallet,
            quote_in_wallet,
            quantity,
            price,
            is_bid,
            deep_required
        )
    }

    /// Determines if wrapper DEEP will be needed for this order
    /// Also checks if the wrapper has enough DEEP to cover the needs
    /// Returns (will_use_wrapper_deep, wrapper_has_enough_deep)
    public fun will_use_wrapper_deep_reserves<BaseToken, QuoteToken>(
        wrapper: &DeepBookV3RouterWrapper,
        pool: &Pool<BaseToken, QuoteToken>,
        balance_manager: &BalanceManager,
        deep_in_wallet: u64,
        quantity: u64,
        price: u64
    ): (bool, bool) {
        // Get wrapper deep reserves
        let wrapper_deep_reserves = get_deep_reserves_value(wrapper);
        
        // Check if pool is whitelisted
        let is_pool_whitelisted = pool::whitelisted(pool);
        
        // Calculate how much DEEP is required
        let deep_required = calculate_deep_required(pool, quantity, price);
        
        // Check DEEP from balance manager
        let balance_manager_deep = balance_manager::balance<DEEP>(balance_manager);

        // Get deep plan
        let deep_plan = get_deep_plan(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            deep_in_wallet,
            wrapper_deep_reserves
        );

        return (deep_plan.use_wrapper_deep_reserves, deep_plan.deep_reserves_cover_order)
    }

    /// Helper function to validate pool parameters
    public fun validate_pool_params<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        quantity: u64,
        price: u64
    ): bool {
        let (tick_size, lot_size, min_size) = pool::pool_book_params(pool);
        
        // Call the core logic function
        validate_pool_params_core(
            quantity,
            price,
            tick_size,
            lot_size,
            min_size
        )
    }

    /// Checks if the user has sufficient tokens for the order
    public fun has_enough_input_coin<BaseToken, QuoteToken>(
        balance_manager: &BalanceManager,
        base_in_wallet: u64,
        quote_in_wallet: u64,
        quantity: u64,
        price: u64,
        will_use_wrapper_deep: bool,
        fee_estimate: u64,
        is_bid: bool
    ): bool {
        // Get balance manager balances
        let balance_manager_base = balance_manager::balance<BaseToken>(balance_manager);
        let balance_manager_quote = balance_manager::balance<QuoteToken>(balance_manager);
        
        // Call the core logic function
        has_enough_input_coin_core(
            balance_manager_base,
            balance_manager_quote,
            base_in_wallet,
            quote_in_wallet,
            quantity,
            price,
            will_use_wrapper_deep,
            fee_estimate,
            is_bid
        )
    }

    // === Public-Package Functions ===
    /// Estimate order requirements for a limit order - core logic function that doesn't require DeepBook objects
    /// Takes raw data instead of DeepBook objects to improve testability
    /// Returns whether the order can be created, DEEP required, and estimated fee
    public(package) fun estimate_order_requirements_core(
        wrapper_deep_reserves: u64,
        is_pool_whitelisted: bool,
        pool_fee_bps: u64,
        pool_tick_size: u64,
        pool_lot_size: u64,
        pool_min_size: u64,
        balance_manager_deep: u64,
        balance_manager_base: u64,
        balance_manager_quote: u64,
        deep_in_wallet: u64,
        base_in_wallet: u64,
        quote_in_wallet: u64,
        quantity: u64,
        price: u64,
        is_bid: bool,
        deep_required: u64
    ): (bool, u64, u64) {
        // Get deep plan
        let deep_plan = get_deep_plan(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            deep_in_wallet,
            wrapper_deep_reserves
        );
        
        // Early return if wrapper doesn't have enough DEEP
        if (deep_plan.use_wrapper_deep_reserves && !deep_plan.deep_reserves_cover_order) {
            return (false, deep_required, 0)
        };
        
        // Calculate fee
        let fee_estimate = estimate_full_fee_core(
            is_pool_whitelisted,
            deep_plan.use_wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            pool_fee_bps,
            deep_plan.from_deep_reserves,
            deep_required
        );
        
        // Validate order parameters
        let valid_params = validate_pool_params_core(
            quantity,
            price,
            pool_tick_size,
            pool_lot_size,
            pool_min_size
        );
        
        // Check if user has sufficient tokens
        let sufficient_tokens = has_enough_input_coin_core(
            balance_manager_base,
            balance_manager_quote,
            base_in_wallet,
            quote_in_wallet,
            quantity,
            price,
            deep_plan.use_wrapper_deep_reserves,
            fee_estimate,
            is_bid
        );
        
        (valid_params && sufficient_tokens && deep_plan.deep_reserves_cover_order, deep_required, fee_estimate)
    }

    /// Create a limit order using tokens from various sources - core logic function
    /// This is a skeleton that orchestrates the process
    public(package) fun create_limit_order_core(
        is_pool_whitelisted: bool,
        deep_required: u64,
        balance_manager_deep: u64,
        balance_manager_input_coin: u64,
        deep_in_wallet: u64,
        wallet_input_coin: u64,
        wrapper_deep_reserves: u64,
        quantity: u64,
        price: u64,
        is_bid: bool,
        pool_fee_bps: u64
    ): (DeepPlan, FeePlan, InputCoinDepositPlan) {
        // Step 1: Determine DEEP requirements
        let deep_plan = get_deep_plan(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            deep_in_wallet,
            wrapper_deep_reserves
        );
        
        // Step 2: Calculate order amount based on order type
        let order_amount = calculate_order_amount(quantity, price, is_bid);

        // Step 3: Determine fee collection based on order type
        let fee_plan = get_fee_plan(
            deep_plan.use_wrapper_deep_reserves,
            deep_plan.from_deep_reserves,
            deep_required,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_input_coin,
            balance_manager_input_coin
        );

        // Step 4: Determine token deposit requirements
        let deposit_plan = get_input_coin_deposit_plan(
            order_amount,
            wallet_input_coin - fee_plan.from_user_wallet,
            balance_manager_input_coin - fee_plan.from_user_balance_manager
        );
        
        (deep_plan, fee_plan, deposit_plan)
    }

    /// Helper function to validate pool parameters - core logic
    public(package) fun validate_pool_params_core(
        quantity: u64,
        price: u64,
        tick_size: u64,
        lot_size: u64,
        min_size: u64
    ): bool {
        quantity >= min_size && 
        quantity % lot_size == 0 && 
        price % tick_size == 0
    }

    /// Checks if the user has sufficient tokens for the order - core logic
    public(package) fun has_enough_input_coin_core(
        balance_manager_base: u64,
        balance_manager_quote: u64,
        base_in_wallet: u64,
        quote_in_wallet: u64,
        quantity: u64,
        price: u64,
        will_use_wrapper_deep: bool,
        fee_estimate: u64,
        is_bid: bool
    ): bool {
        if (is_bid) {
            // For bid orders, check if user has enough quote tokens
            let quote_required = math::mul(quantity, price);
            let total_quote_available = balance_manager_quote + quote_in_wallet;
            
            // Need to account for fee if using wrapper DEEP
            if (will_use_wrapper_deep) {
                total_quote_available >= (quote_required + fee_estimate)
            } else {
                total_quote_available >= quote_required
            }
        } else {
            // For ask orders, check if user has enough base tokens
            let total_base_available = balance_manager_base + base_in_wallet;
            
            // Need to account for fee if using wrapper DEEP
            if (will_use_wrapper_deep) {
                total_base_available >= (quantity + fee_estimate)
            } else {
                total_base_available >= quantity
            }
        }
    }

    /// Determine the DEEP token requirements for an order - core logic
    public(package) fun get_deep_plan(
        is_pool_whitelisted: bool,
        deep_required: u64,
        balance_manager_deep: u64,
        deep_in_wallet: u64,
        wrapper_deep_reserves: u64
    ): DeepPlan {
        // If pool is whitelisted, no DEEP is needed
        if (is_pool_whitelisted) {
            return DeepPlan {
                use_wrapper_deep_reserves: false,
                from_user_wallet: 0,
                from_deep_reserves: 0,
                deep_reserves_cover_order: true
            }
        };
        
        // Calculate how much DEEP the user has available
        let user_deep_total = balance_manager_deep + deep_in_wallet;
        
        if (user_deep_total >= deep_required) {
            // User has enough DEEP
            // Determine how much to take from wallet based on what's available
            let from_wallet = if (balance_manager_deep >= deep_required) {
                0 // Nothing needed from wallet if balance manager has enough
            } else {
                deep_required - balance_manager_deep
            };
            
            return DeepPlan {
                use_wrapper_deep_reserves: false,
                from_user_wallet: from_wallet,
                from_deep_reserves: 0,
                deep_reserves_cover_order: true
            }
        } else {
            // Need wrapper DEEP since user doesn't have enough
            let from_wallet = deep_in_wallet;  // Take all from wallet
            let still_needed = deep_required - user_deep_total;
            let has_sufficient = wrapper_deep_reserves >= still_needed;

            if (!has_sufficient) {
                return DeepPlan {
                    use_wrapper_deep_reserves: true,
                    from_user_wallet: 0,
                    from_deep_reserves: 0,
                    deep_reserves_cover_order: false
                }
            };

            return DeepPlan {
                use_wrapper_deep_reserves: true,
                from_user_wallet: from_wallet,
                from_deep_reserves: still_needed,
                deep_reserves_cover_order: true
            }
        }
    }
    
    /// Determine fee collection requirements - core logic
    /// For bid orders, fees are collected in quote tokens
    /// For ask orders, fees are collected in base tokens
    /// Returns a plan for fee collection
    public(package) fun get_fee_plan(
        use_wrapper_deep_reserves: bool,
        deep_from_reserves: u64,
        total_deep_required: u64,
        is_pool_whitelisted: bool,
        pool_fee_bps: u64,
        order_amount: u64,
        is_bid: bool,
        wallet_balance: u64,
        balance_manager_balance: u64
    ): FeePlan {
        // No fee for whitelisted pools or when not using wrapper DEEP
        if (is_pool_whitelisted || !use_wrapper_deep_reserves) {
            return FeePlan {
                fee_coin_type: 0,  // No fee
                fee_amount: 0,
                from_user_wallet: 0,
                from_user_balance_manager: 0,
                user_covers_wrapper_fee: true
            }
        };
        
        // Calculate fee based on order amount, including both protocol fee and deep reserves coverage fee
        let fee_amount = calculate_full_fee(order_amount, pool_fee_bps, deep_from_reserves, total_deep_required);
        
        // If no fee, return early
        if (fee_amount == 0) {
            return FeePlan {
                fee_coin_type: if (is_bid) 2 else 1,  // 1 for base, 2 for quote
                fee_amount: 0,
                from_user_wallet: 0,
                from_user_balance_manager: 0,
                user_covers_wrapper_fee: true
            }
        };

        // Check if we have sufficient resources
        let has_sufficient = wallet_balance + balance_manager_balance >= fee_amount;

        if (!has_sufficient) {
            return FeePlan {
                fee_coin_type: if (is_bid) 2 else 1,  // 1 for base, 2 for quote
                fee_amount,
                from_user_wallet: 0,
                from_user_balance_manager: 0,
                user_covers_wrapper_fee: false
            }
        };
        
        // Determine how much to take from wallet vs balance manager
        let from_wallet = if (wallet_balance >= fee_amount) {
            fee_amount
        } else {
            wallet_balance
        };
        
        let from_balance_manager = if (from_wallet < fee_amount) {
            let remaining = fee_amount - from_wallet;
            remaining
        } else {
            0 // Wallet has covered the fee, no need to take from balance manager
        };
        
        FeePlan {
            fee_coin_type: if (is_bid) 2 else 1,  // 1 for base, 2 for quote
            fee_amount,
            from_user_wallet: from_wallet,
            from_user_balance_manager: from_balance_manager,
            user_covers_wrapper_fee: has_sufficient
        }
    }
    
    /// Determine token deposit requirements - core logic
    /// For bid orders, calculate how many quote tokens are needed
    /// For ask orders, calculate how many base tokens are needed
    public(package) fun get_input_coin_deposit_plan(
        required_amount: u64,
        wallet_balance: u64,
        balance_manager_balance: u64
    ): InputCoinDepositPlan {
        // Check if we already have enough in the balance manager
        if (balance_manager_balance >= required_amount) {
            return InputCoinDepositPlan {
                order_amount: required_amount,
                from_user_wallet: 0,
                user_has_enough_input_coin: true
            }
        };
        
        // Calculate how much more is needed
        let additional_needed = required_amount - balance_manager_balance;
        let has_sufficient = wallet_balance >= additional_needed;

        if (!has_sufficient) {
            return InputCoinDepositPlan {
                order_amount: required_amount,
                from_user_wallet: 0,
                user_has_enough_input_coin: false
            }
        };
        
        InputCoinDepositPlan {
            order_amount: required_amount,
            from_user_wallet: additional_needed,
            user_has_enough_input_coin: true
        }
    }

    // === Private Functions ===
    /// Helper function to collect fees based on token type
    fun execute_fee_plan<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        balance_manager: &mut BalanceManager, 
        base_coin: &mut Coin<BaseToken>,
        quote_coin: &mut Coin<QuoteToken>,
        fee_plan: &FeePlan,
        ctx: &mut TxContext
    ) {
        // Verify there are enough tokens to cover the fee
        if (fee_plan.fee_amount > 0) {
            assert!(
                fee_plan.user_covers_wrapper_fee,
                EInsufficientFeeOrInput
            );
        };
        
        // Collect fee from wallet if needed
        if (fee_plan.from_user_wallet > 0) {
            if (fee_plan.fee_coin_type == 1) { // Base token
                let fee_coin = coin::split(base_coin, fee_plan.from_user_wallet, ctx);
                join_fee(wrapper, coin::into_balance(fee_coin));
            } else if (fee_plan.fee_coin_type == 2) { // Quote token
                let fee_coin = coin::split(quote_coin, fee_plan.from_user_wallet, ctx);
                join_fee(wrapper, coin::into_balance(fee_coin));
            };
        };
        
        // Collect fee from balance manager if needed
        if (fee_plan.from_user_balance_manager > 0) {
            if (fee_plan.fee_coin_type == 1) { // Base token
                let fee_coin = balance_manager::withdraw<BaseToken>(
                    balance_manager,
                    fee_plan.from_user_balance_manager,
                    ctx
                );
                join_fee(wrapper, coin::into_balance(fee_coin));
            } else if (fee_plan.fee_coin_type == 2) { // Quote token
                let fee_coin = balance_manager::withdraw<QuoteToken>(
                    balance_manager,
                    fee_plan.from_user_balance_manager,
                    ctx
                );
                join_fee(wrapper, coin::into_balance(fee_coin));
            };
        };
    }
    
    /// Helper function to collect DEEP tokens from wallet and wrapper according to the plan
    fun execute_deep_plan(
        wrapper: &mut DeepBookV3RouterWrapper,
        balance_manager: &mut BalanceManager,
        deep_coin: &mut Coin<DEEP>,
        deep_plan: &DeepPlan,
        ctx: &mut TxContext
    ) {
        // Check if there are sufficient resources
        if (deep_plan.use_wrapper_deep_reserves) {
            assert!(deep_plan.deep_reserves_cover_order, EInsufficientDeepReserves);
        };
        
        // Take DEEP from wallet if needed
        if (deep_plan.from_user_wallet > 0) {
            let payment = coin::split(deep_coin, deep_plan.from_user_wallet, ctx);
            balance_manager::deposit(balance_manager, payment, ctx);
        };
        
        // Take DEEP from wrapper reserves if needed
        if (deep_plan.from_deep_reserves > 0) {
            let reserve_payment = split_deep_reserves(wrapper, deep_plan.from_deep_reserves, ctx);
            
            balance_manager::deposit(balance_manager, reserve_payment, ctx);
        };
    }

    /// Helper function to deposit tokens according to the token plan
    fun execute_input_coin_deposit_plan<BaseToken, QuoteToken>(
        balance_manager: &mut BalanceManager,
        base_coin: &mut Coin<BaseToken>,
        quote_coin: &mut Coin<QuoteToken>,
        deposit_plan: &InputCoinDepositPlan,
        is_bid: bool,
        ctx: &mut TxContext
    ) {
        // Verify there are enough tokens to satisfy the deposit requirements
        if (deposit_plan.order_amount > 0) {
            assert!(
                deposit_plan.user_has_enough_input_coin,
                EInsufficientFeeOrInput
            );
        };
        
        // Deposit tokens from wallet if needed
        if (deposit_plan.from_user_wallet > 0) {
            if (is_bid) { // Quote tokens for bid
                let payment = coin::split(quote_coin, deposit_plan.from_user_wallet, ctx);
                balance_manager::deposit(balance_manager, payment, ctx);
            } else { // Base tokens for ask
                let payment = coin::split(base_coin, deposit_plan.from_user_wallet, ctx);
                balance_manager::deposit(balance_manager, payment, ctx);
            };
        };
    }

    // === Test-Only Functions ===
    #[test_only]
    public fun assert_deep_plan_eq(
        actual: DeepPlan,
        expected_use_wrapper: bool,
        expected_from_wallet: u64,
        expected_from_wrapper: u64,
        expected_sufficient: bool
    ) {
        assert!(actual.use_wrapper_deep_reserves == expected_use_wrapper, 0);
        assert!(actual.from_user_wallet == expected_from_wallet, 0);
        assert!(actual.from_deep_reserves == expected_from_wrapper, 0);
        assert!(actual.deep_reserves_cover_order == expected_sufficient, 0);
    }

    #[test_only]
    public fun assert_fee_plan_eq(
        actual: FeePlan,
        expected_fee_coin_type: u8,
        expected_fee_amount: u64,
        expected_from_user_wallet: u64,
        expected_from_user_balance_manager: u64,
        expected_sufficient: bool
    ) {
        assert!(actual.fee_coin_type == expected_fee_coin_type, 0);
        assert!(actual.fee_amount == expected_fee_amount, 0);
        assert!(actual.from_user_wallet == expected_from_user_wallet, 0);
        assert!(actual.from_user_balance_manager == expected_from_user_balance_manager, 0);
        assert!(actual.user_covers_wrapper_fee == expected_sufficient, 0);
    }

    #[test_only]
    public fun assert_input_coin_deposit_plan_eq(
        actual: InputCoinDepositPlan,
        expected_order_amount: u64,
        expected_from_user_wallet: u64,
        expected_sufficient: bool
    ) {
        assert!(actual.order_amount == expected_order_amount, 0);
        assert!(actual.from_user_wallet == expected_from_user_wallet, 0);
        assert!(actual.user_has_enough_input_coin == expected_sufficient, 0);
    }
}