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
      transfer_if_nonzero,
      calculate_order_amount,
      get_order_deep_price_params
    };
    use deepbook_wrapper::fee::{estimate_full_order_fee_core, calculate_full_order_fee};

    // === Structs ===
    /// Tracks how DEEP will be sourced for an order
    /// Used to coordinate token sourcing from user wallet and wrapper reserves
    public struct DeepPlan has copy, drop {
        /// Whether DEEP from wrapper reserves is needed for this order
        use_wrapper_deep_reserves: bool,
        /// Amount of DEEP to take from user's wallet
        from_user_wallet: u64,
        /// Amount of DEEP to take from wrapper reserves
        from_deep_reserves: u64,
        /// Whether wrapper DEEP reserves has enough DEEP to cover the order
        deep_reserves_cover_order: bool
    }
    
    /// Tracks fee charging strategy for an order
    /// Determines fee coin type, amount, and sources for fee payment
    public struct FeePlan has copy, drop {
        /// Coin type for fee charging: 0 = no fee, 1 = base coin, 2 = quote coin
        fee_coin_type: u8,
        /// Total fee amount to be collected
        fee_amount: u64,
        /// Amount of fee to take from user's wallet
        from_user_wallet: u64,
        /// Amount of fee to take from user's balance manager
        from_user_balance_manager: u64,
        /// Whether user has enough coins on his wallet and balance manager to cover the required fee
        user_covers_wrapper_fee: bool
    }
    
    /// Tracks input coin requirements for an order
    /// Plans how input coins will be sourced from user wallet and balance manager
    public struct InputCoinDepositPlan has copy, drop {
        /// Total amount of input coins needed for the order
        order_amount: u64,
        /// Amount of input coins to take from user's wallet
        from_user_wallet: u64,
        /// Whether user has enough input coins for the order
        user_has_enough_input_coin: bool
    }

    // === Errors ===
    /// Error when trying to use deep from reserves but there is not enough available
    #[error]
    const EInsufficientDeepReserves: u64 = 1;

    /// Error when user doesn't have enough coins on his wallet and balance manager
    /// to cover the required fee and(or) create the order with desired amount
    #[error]
    const EInsufficientFeeOrInput: u64 = 2;

    /// Error when the caller is not the owner of the balance manager
    #[error]
    const EInvalidOwner: u64 = 3;

    /// Error when the pool is not whitelisted by our protocol
    #[error]
    const ENotWhitelistedPool: u64 = 4;

    // === Public-Mutative Functions ===
    /// Creates a limit order on DeepBook using coins from various sources
    /// This function orchestrates the entire order creation process:
    /// 1. Sources DEEP coins from user wallet and wrapper reserves if needed
    /// 2. Collects fees in input coins
    /// 3. Deposits required input coins from the wallet to the balance manager
    /// 4. Places the order on DeepBook and returns the order info
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
        order_type: u8,
        self_matching_option: u8,
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
        let (asset_is_base, deep_per_asset) = get_order_deep_price_params(pool);
        
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
            asset_is_base,
            deep_per_asset
        );
        
        // Step 1: Execute DEEP plan
        execute_deep_plan(wrapper, balance_manager, &mut deep_coin, &deep_plan, ctx);
        
        // Step 2: Execute fee charging plan
        execute_fee_plan(
            wrapper,
            balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &fee_plan,
            ctx
        );
        
        // Step 3: Execute input coin deposit plan
        execute_input_coin_deposit_plan(
            balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &input_coin_deposit_plan,
            is_bid,
            ctx
        );
        
        // Return unused coins to the caller
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
            order_type,
            self_matching_option,
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
    /// Estimates the requirements for creating a limit order on DeepBook
    /// Analyzes available resources and requirements to determine if an order can be created
    /// 
    /// Returns a tuple with three values:
    /// - bool: Whether the order can be successfully created with available resources
    /// - u64: Amount of DEEP coins required for the order (if non-whitelisted pool)
    /// - u64: Estimated fee amount in input coins (base for ask orders, quote for bid orders)
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
        
        // Check if pool is whitelisted by DeepBook
        let is_pool_whitelisted = pool::whitelisted(pool);
        
        // Get pool parameters
        let (pool_tick_size, pool_lot_size, pool_min_size) = pool::pool_book_params(pool);

        // Get the order deep price for the pool
        let (asset_is_base, deep_per_asset) = get_order_deep_price_params(pool);
        
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
            asset_is_base,
            deep_per_asset,
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

    /// Determines if wrapper DEEP reserves will be needed for placing an order
    /// Analyzes user's available DEEP coins and calculates if wrapper reserves are required
    /// 
    /// Returns a tuple with two boolean values:
    /// - bool: Whether wrapper DEEP reserves will be used for this order
    /// - bool: Whether the wrapper has sufficient DEEP reserves to cover the order needs
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
        
        // Check if pool is whitelisted by DeepBook
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

        (deep_plan.use_wrapper_deep_reserves, deep_plan.deep_reserves_cover_order)
    }

    /// Validates that order parameters satisfy the pool's requirements
    /// Checks if quantity and price comply with the pool's tick size, lot size, and minimum size constraints
    /// 
    /// Returns boolean:
    /// - true: If order parameters are valid for the specified pool
    /// - false: If any parameter violates the pool's constraints
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

    /// Checks if the user has enough input coins for creating an order
    /// Evaluates combined balances from wallet and balance manager against order requirements
    /// Accounts for additional fee requirements when using wrapper DEEP reserves
    /// 
    /// Returns boolean:
    /// - true: If user has enough coins to create the order with specified parameters
    /// - false: If user doesn't have enough coins for the order
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
    /// Core logic for estimating order requirements without using DeepBook objects
    /// Takes raw parameters instead of DeepBook objects for improved testability
    /// Evaluates all requirements including DEEP needs, fees, and parameter validation
    /// 
    /// Returns a tuple with three values:
    /// - bool: Whether the order can be created with available resources
    /// - u64: Amount of DEEP coins required for the order (if non-whitelisted pool)
    /// - u64: Estimated fee amount in input coins
    public(package) fun estimate_order_requirements_core(
        wrapper_deep_reserves: u64,
        is_pool_whitelisted: bool,
        asset_is_base: bool,
        deep_per_asset: u64,
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
        let fee_estimate = estimate_full_order_fee_core(
            is_pool_whitelisted,
            balance_manager_deep,
            deep_in_wallet,
            quantity,
            price,
            is_bid,
            asset_is_base,
            deep_per_asset,
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
        
        // Check if user has enough input coins
        let enough_coins = has_enough_input_coin_core(
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
        
        (valid_params && enough_coins && deep_plan.deep_reserves_cover_order, deep_required, fee_estimate)
    }

    /// Core logic function that orchestrates the creation of a limit order using coins from various sources
    /// Coordinates all requirements by analyzing available resources and calculating necessary allocations
    /// Creates comprehensive plans for DEEP coins sourcing, fee charging, and input coin deposits
    /// 
    /// Returns a tuple with three structured plans:
    /// - DeepPlan: Coordinates DEEP coin sourcing from user wallet and wrapper reserves
    /// - FeePlan: Specifies fee coin type, amount, and sources for fee payment
    /// - InputCoinDepositPlan: Determines how input coins will be sourced for the order
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
        asset_is_base: bool,
        deep_per_asset: u64
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

        // Step 3: Determine fee charging plan based on order type
        let fee_plan = get_fee_plan(
            deep_plan.use_wrapper_deep_reserves,
            deep_plan.from_deep_reserves,
            deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_input_coin,
            balance_manager_input_coin
        );

        // Step 4: Determine input coin deposit plan
        let deposit_plan = get_input_coin_deposit_plan(
            order_amount,
            wallet_input_coin - fee_plan.from_user_wallet,
            balance_manager_input_coin - fee_plan.from_user_balance_manager
        );
        
        (deep_plan, fee_plan, deposit_plan)
    }

    /// Validates that order parameters satisfy the pool's requirements - core logic implementation
    /// Performs three essential checks for order parameter validity:
    /// 1. Quantity meets or exceeds the pool's minimum size
    /// 2. Quantity is a multiple of the pool's lot size
    /// 3. Price is a multiple of the pool's tick size
    /// 
    /// Returns boolean:
    /// - true: If all order parameters comply with the pool's constraints
    /// - false: If any parameter violates the pool's constraints
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

    /// Checks if the user has enough input coins for creating an order - core logic implementation
    /// Evaluates available coin balances against order requirements, considering:
    /// 1. For bid orders: if user has enough quote coins including fee if needed
    /// 2. For ask orders: if user has enough base coins including fee if needed
    /// 
    /// Returns boolean:
    /// - true: If user has enough coins for the order with specified parameters
    /// - false: If user doesn't have enough coins to create the order
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
            // For bid orders, check if user has enough quote coins
            let quote_required = math::mul(quantity, price);
            let total_quote_available = balance_manager_quote + quote_in_wallet;
            
            // Need to account for fee if using wrapper DEEP
            if (will_use_wrapper_deep) {
                total_quote_available >= (quote_required + fee_estimate)
            } else {
                total_quote_available >= quote_required
            }
        } else {
            // For ask orders, check if user has enough base coins
            let total_base_available = balance_manager_base + base_in_wallet;
            
            // Need to account for fee if using wrapper DEEP
            if (will_use_wrapper_deep) {
                total_base_available >= (quantity + fee_estimate)
            } else {
                total_base_available >= quantity
            }
        }
    }

    /// Analyzes DEEP coin requirements for an order and creates a sourcing plan
    /// Evaluates user's available DEEP coins and determines if wrapper reserves are needed
    /// Calculates optimal allocation from user wallet, balance manager, and wrapper reserves
    /// 
    /// Returns a DeepPlan structure with the following information:
    /// - use_wrapper_deep_reserves: Whether DEEP from wrapper reserves will be used
    /// - from_user_wallet: Amount of DEEP to take from user's wallet
    /// - from_deep_reserves: Amount of DEEP to take from wrapper reserves
    /// - deep_reserves_cover_order: Whether wrapper has enough DEEP to cover what's needed
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
            
            DeepPlan {
                use_wrapper_deep_reserves: false,
                from_user_wallet: from_wallet,
                from_deep_reserves: 0,
                deep_reserves_cover_order: true
            }
        } else {
            // Need wrapper DEEP since user doesn't have enough
            let from_wallet = deep_in_wallet;  // Take all from wallet
            let still_needed = deep_required - user_deep_total;
            let has_enough = wrapper_deep_reserves >= still_needed;

            if (!has_enough) {
                return DeepPlan {
                    use_wrapper_deep_reserves: true,
                    from_user_wallet: 0,
                    from_deep_reserves: 0,
                    deep_reserves_cover_order: false
                }
            };

            DeepPlan {
                use_wrapper_deep_reserves: true,
                from_user_wallet: from_wallet,
                from_deep_reserves: still_needed,
                deep_reserves_cover_order: true
            }
        }
    }
    
    /// Creates a fee charging plan for order execution - core logic
    /// Determines fee coin type, amount, and optimal sources for fee payment
    /// For bid orders, fees are charged in quote coins; for ask orders, in base coins
    /// 
    /// Returns a FeePlan structure with the following information:
    /// - fee_coin_type: Coin type for fee charging (0 = no fee, 1 = base coin, 2 = quote coin)
    /// - fee_amount: Total fee amount to be charged
    /// - from_user_wallet: Amount of fee to take from user's wallet
    /// - from_user_balance_manager: Amount of fee to take from user's balance manager
    /// - user_covers_wrapper_fee: Whether user has enough coins to cover the required fee
    public(package) fun get_fee_plan(
        use_wrapper_deep_reserves: bool,
        deep_from_reserves: u64,
        total_deep_required: u64,
        is_pool_whitelisted: bool,
        asset_is_base: bool,
        deep_per_asset: u64,
        quantity: u64,
        price: u64,
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
        let fee_amount = calculate_full_order_fee(quantity, price, is_bid, asset_is_base, deep_per_asset, deep_from_reserves, total_deep_required);
        
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

        // Check if user has enough coins to cover the fee
        let has_enough = wallet_balance + balance_manager_balance >= fee_amount;

        if (!has_enough) {
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
            user_covers_wrapper_fee: has_enough
        }
    }
    
    /// Creates an input coin deposit plan for order execution - core logic
    /// Determines how to source required input coins from user wallet and balance manager
    /// For bid orders, calculates quote coins needed; for ask orders, calculates base coins needed
    /// 
    /// Returns an InputCoinDepositPlan structure with the following information:
    /// - order_amount: Total amount of input coins needed for the order
    /// - from_user_wallet: Amount of input coins to take from user's wallet
    /// - user_has_enough_input_coin: Whether user has enough input coins for the order
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
        let has_enough = wallet_balance >= additional_needed;

        if (!has_enough) {
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
    /// Executes the DEEP coin sourcing plan by acquiring coins from specified sources
    /// Sources DEEP coins from user wallet and/or wrapper reserves based on the deep plan
    /// Deposits all acquired DEEP coins to the user's balance manager for order placement
    /// 
    /// Steps performed:
    /// 1. Verifies the wrapper has enough DEEP reserves if they will be used
    /// 2. Takes DEEP coins from user wallet when specified in the plan
    /// 3. Takes DEEP coins from wrapper reserves when needed
    /// 4. Deposits all acquired DEEP coins to the balance manager
    fun execute_deep_plan(
        wrapper: &mut DeepBookV3RouterWrapper,
        balance_manager: &mut BalanceManager,
        deep_coin: &mut Coin<DEEP>,
        deep_plan: &DeepPlan,
        ctx: &mut TxContext
    ) {
        // Check if there is enough DEEP in the wrapper reserves
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
    
    /// Executes the fee charging plan by taking coins from specified sources
    /// Takes fee coins from user wallet and/or balance manager based on the fee plan
    /// Supports both base and quote coins depending on the order type (ask/bid)
    /// 
    /// Steps performed:
    /// 1. Verifies the user has enough coins to cover required fees
    /// 2. Takes fee coins from user wallet when specified in the plan
    /// 3. Takes fee coins from balance manager when needed
    /// 4. Joins all collected fees to the wrapper's fee balance
    fun execute_fee_plan<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        balance_manager: &mut BalanceManager, 
        base_coin: &mut Coin<BaseToken>,
        quote_coin: &mut Coin<QuoteToken>,
        fee_plan: &FeePlan,
        ctx: &mut TxContext
    ) {
        // Verify there are enough coins to cover the fee
        if (fee_plan.fee_amount > 0) {
            assert!(
                fee_plan.user_covers_wrapper_fee,
                EInsufficientFeeOrInput
            );
        };
        
        // Charge fee from wallet if needed
        if (fee_plan.from_user_wallet > 0) {
            if (fee_plan.fee_coin_type == 1) { // Base coin
                let fee_coin = coin::split(base_coin, fee_plan.from_user_wallet, ctx);
                join_fee(wrapper, coin::into_balance(fee_coin));
            } else if (fee_plan.fee_coin_type == 2) { // Quote coin
                let fee_coin = coin::split(quote_coin, fee_plan.from_user_wallet, ctx);
                join_fee(wrapper, coin::into_balance(fee_coin));
            };
        };
        
        // Charge fee from balance manager if needed
        if (fee_plan.from_user_balance_manager > 0) {
            if (fee_plan.fee_coin_type == 1) { // Base coin
                let fee_coin = balance_manager::withdraw<BaseToken>(
                    balance_manager,
                    fee_plan.from_user_balance_manager,
                    ctx
                );
                join_fee(wrapper, coin::into_balance(fee_coin));
            } else if (fee_plan.fee_coin_type == 2) { // Quote coin
                let fee_coin = balance_manager::withdraw<QuoteToken>(
                    balance_manager,
                    fee_plan.from_user_balance_manager,
                    ctx
                );
                join_fee(wrapper, coin::into_balance(fee_coin));
            };
        };
    }

    /// Executes the input coin deposit plan by transferring coins to the balance manager
    /// Deposits required input coins from user wallet to balance manager based on the plan
    /// Handles different coin types based on order type: quote coins for bid orders, base coins for ask orders
    /// 
    /// Steps performed:
    /// 1. Verifies the user has enough input coins to satisfy the deposit requirements
    /// 2. For bid orders: transfers quote coins from user wallet to balance manager
    /// 3. For ask orders: transfers base coins from user wallet to balance manager
    fun execute_input_coin_deposit_plan<BaseToken, QuoteToken>(
        balance_manager: &mut BalanceManager,
        base_coin: &mut Coin<BaseToken>,
        quote_coin: &mut Coin<QuoteToken>,
        deposit_plan: &InputCoinDepositPlan,
        is_bid: bool,
        ctx: &mut TxContext
    ) {
        // Verify there are enough coins to satisfy the deposit requirements
        if (deposit_plan.order_amount > 0) {
            assert!(
                deposit_plan.user_has_enough_input_coin,
                EInsufficientFeeOrInput
            );
        };
        
        // Deposit coins from wallet if needed
        if (deposit_plan.from_user_wallet > 0) {
            if (is_bid) { // Quote coins for bid
                let payment = coin::split(quote_coin, deposit_plan.from_user_wallet, ctx);
                balance_manager::deposit(balance_manager, payment, ctx);
            } else { // Base coins for ask
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