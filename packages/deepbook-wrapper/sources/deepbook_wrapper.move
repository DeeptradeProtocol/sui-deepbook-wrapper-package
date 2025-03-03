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

    /// Data structure to represent DEEP token requirements for an order
    public struct DeepRequirementPlan has copy, drop {
        use_wrapper_deep: bool,
        take_from_wallet: u64,
        take_from_wrapper: u64,
        has_sufficient_resources: bool
    }
    
    /// Data structure to represent fee collection plan
    public struct FeeCollectionPlan has copy, drop {
        token_type: u8,     // 0 for no fee, 1 for base token, 2 for quote token
        fee_amount: u64,
        take_from_wallet: u64,
        take_from_balance_manager: u64,
        has_sufficient_resources: bool
    }
    
    /// Data structure to represent token deposit requirements
    public struct TokenDepositPlan has copy, drop {
        amount_needed: u64,
        take_from_wallet: u64,
        has_sufficient_resources: bool
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
    public fun calculate_fee_amount(amount: u64, fee_bps: u64): u64 {
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
        // Get wrapper deep reserves
        let wrapper_deep_reserves = balance::value(&wrapper.deep_reserves);
        
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
        
        // Extract all the data we need from DeepBook objects
        let is_pool_whitelisted = pool::whitelisted(pool);
        let deep_required = calculate_deep_required(pool, quantity, price);
        let fee_bps = get_fee_bps(pool);
        
        // Get balances from balance manager
        let balance_manager_deep = balance_manager::balance<DEEP>(balance_manager);
        let balance_manager_base = balance_manager::balance<BaseToken>(balance_manager);
        let balance_manager_quote = balance_manager::balance<QuoteToken>(balance_manager);
        
        // Get balances from wallet coins
        let deep_in_wallet = coin::value(&deep_coin);
        let base_in_wallet = coin::value(&base_coin);
        let quote_in_wallet = coin::value(&quote_coin);
        
        // Get wrapper deep reserves
        let wrapper_deep_reserves = balance::value(&wrapper.deep_reserves);
        
        // Get the order plans from the core logic
        let (deep_plan, fee_plan, token_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_base,
            balance_manager_quote,
            deep_in_wallet,
            base_in_wallet,
            quote_in_wallet,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            fee_bps
        );
        
        // Step 1: Execute DEEP token plan
        execute_deep_collection(wrapper, balance_manager, &mut deep_coin, &deep_plan, ctx);
        
        // Step 2: Execute fee collection plan
        execute_fee_collection(
            wrapper,
            balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &fee_plan,
            ctx
        );
        
        // Step 3: Execute token deposit plan
        execute_token_deposit(
            balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &token_plan,
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

    /// Helper function to collect fees based on token type
    fun execute_fee_collection<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        balance_manager: &mut BalanceManager, 
        base_coin: &mut Coin<BaseToken>,
        quote_coin: &mut Coin<QuoteToken>,
        fee_plan: &FeeCollectionPlan,
        ctx: &mut TxContext
    ) {
        // Verify there are enough tokens to cover the fee
        if (fee_plan.fee_amount > 0) {
            assert!(
                fee_plan.has_sufficient_resources, 
                EInsufficientFeeOrInput
            );
        };
        
        // Collect fee from wallet if needed
        if (fee_plan.take_from_wallet > 0) {
            if (fee_plan.token_type == 1) { // Base token
                let fee_coin = coin::split(base_coin, fee_plan.take_from_wallet, ctx);
                join_fee(wrapper, coin::into_balance(fee_coin));
            } else if (fee_plan.token_type == 2) { // Quote token
                let fee_coin = coin::split(quote_coin, fee_plan.take_from_wallet, ctx);
                join_fee(wrapper, coin::into_balance(fee_coin));
            };
        };
        
        // Collect fee from balance manager if needed
        if (fee_plan.take_from_balance_manager > 0) {
            if (fee_plan.token_type == 1) { // Base token
                let fee_coin = balance_manager::withdraw<BaseToken>(
                    balance_manager,
                    fee_plan.take_from_balance_manager,
                    ctx
                );
                join_fee(wrapper, coin::into_balance(fee_coin));
            } else if (fee_plan.token_type == 2) { // Quote token
                let fee_coin = balance_manager::withdraw<QuoteToken>(
                    balance_manager,
                    fee_plan.take_from_balance_manager,
                    ctx
                );
                join_fee(wrapper, coin::into_balance(fee_coin));
            };
        };
    }
    
    /// Helper function to collect DEEP tokens from wallet and wrapper according to the plan
    fun execute_deep_collection(
        wrapper: &mut DeepBookV3RouterWrapper,
        balance_manager: &mut BalanceManager,
        deep_coin: &mut Coin<DEEP>,
        deep_plan: &DeepRequirementPlan,
        ctx: &mut TxContext
    ) {
        // Check if there are sufficient resources
        if (deep_plan.use_wrapper_deep) {
            assert!(deep_plan.has_sufficient_resources, EInsufficientDeepReserves);
        };
        
        // Take DEEP from wallet if needed
        if (deep_plan.take_from_wallet > 0) {
            let payment = coin::split(deep_coin, deep_plan.take_from_wallet, ctx);
            balance_manager::deposit(balance_manager, payment, ctx);
        };
        
        // Take DEEP from wrapper reserves if needed
        if (deep_plan.take_from_wrapper > 0) {
            let reserve_payment = coin::from_balance(
                balance::split(&mut wrapper.deep_reserves, deep_plan.take_from_wrapper),
                ctx
            );
            
            balance_manager::deposit(balance_manager, reserve_payment, ctx);
        };
    }

    /// Helper function to deposit tokens according to the token plan
    fun execute_token_deposit<BaseToken, QuoteToken>(
        balance_manager: &mut BalanceManager,
        base_coin: &mut Coin<BaseToken>,
        quote_coin: &mut Coin<QuoteToken>,
        token_plan: &TokenDepositPlan,
        is_bid: bool,
        ctx: &mut TxContext
    ) {
        // Verify there are enough tokens to satisfy the deposit requirements
        if (token_plan.amount_needed > 0) {
            assert!(
                token_plan.has_sufficient_resources,
                EInsufficientFeeOrInput
            );
        };
        
        // Deposit tokens from wallet if needed
        if (token_plan.take_from_wallet > 0) {
            if (is_bid) { // Quote tokens for bid
                let payment = coin::split(quote_coin, token_plan.take_from_wallet, ctx);
                balance_manager::deposit(balance_manager, payment, ctx);
            } else { // Base tokens for ask
                let payment = coin::split(base_coin, token_plan.take_from_wallet, ctx);
                balance_manager::deposit(balance_manager, payment, ctx);
            };
        };
    }

    /// Calculates the fee estimate for an order
    /// Returns 0 for whitelisted pools or when user provides all DEEP
    public fun calculate_fee_estimate<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        will_use_wrapper_deep: bool,
        quantity: u64,
        price: u64,
        is_bid: bool
    ): u64 {
        // Check if pool is whitelisted
        let is_pool_whitelisted = pool::whitelisted(pool);
        
        // Get pool fee basis points
        let (pool_fee_bps, _, _) = pool::pool_trade_params(pool);
        
        // Call the core logic function
        calculate_fee_estimate_core(
            is_pool_whitelisted,
            will_use_wrapper_deep,
            quantity,
            price,
            is_bid,
            pool_fee_bps
        )
    }
    
    /// Checks if the user has sufficient tokens for the order
    public fun has_sufficient_tokens<BaseToken, QuoteToken>(
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
        has_sufficient_tokens_core(
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

    /// Determines if wrapper DEEP will be needed for this order
    /// Also checks if the wrapper has enough DEEP to cover the needs
    /// Returns (will_use_wrapper_deep, has_enough_deep)
    public fun will_use_wrapper_deep<BaseToken, QuoteToken>(
        wrapper: &DeepBookV3RouterWrapper,
        pool: &Pool<BaseToken, QuoteToken>,
        balance_manager: &BalanceManager,
        deep_in_wallet: u64,
        quantity: u64,
        price: u64
    ): (bool, bool) {
        // Get wrapper deep reserves
        let wrapper_deep_reserves = balance::value(&wrapper.deep_reserves);
        
        // Check if pool is whitelisted
        let is_pool_whitelisted = pool::whitelisted(pool);
        
        // Calculate how much DEEP is required
        let deep_required = calculate_deep_required(pool, quantity, price);
        
        // Check DEEP from balance manager
        let balance_manager_deep = balance_manager::balance<DEEP>(balance_manager);
        
        // Call the core logic function
        will_use_wrapper_deep_core(
            wrapper_deep_reserves,
            is_pool_whitelisted,
            balance_manager_deep,
            deep_in_wallet,
            deep_required
        )
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
    
    /// Estimate order requirements for a limit order - core logic function that doesn't require DeepBook objects
    /// Takes raw data instead of DeepBook objects to improve testability
    /// Returns whether the order can be created, DEEP required, and estimated fee
    public fun estimate_order_requirements_core(
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
        // Check if we'll need to use wrapper DEEP
        let (will_use_wrapper_deep, has_enough_deep) = will_use_wrapper_deep_core(
            wrapper_deep_reserves,
            is_pool_whitelisted,
            balance_manager_deep,
            deep_in_wallet,
            deep_required
        );
        
        // Early return if wrapper doesn't have enough DEEP
        if (will_use_wrapper_deep && !has_enough_deep) {
            return (false, deep_required, 0)
        };
        
        // Calculate fee
        let fee_estimate = calculate_fee_estimate_core(
            is_pool_whitelisted,
            will_use_wrapper_deep,
            quantity,
            price,
            is_bid,
            pool_fee_bps
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
        let sufficient_tokens = has_sufficient_tokens_core(
            balance_manager_base,
            balance_manager_quote,
            base_in_wallet,
            quote_in_wallet,
            quantity,
            price,
            will_use_wrapper_deep,
            fee_estimate,
            is_bid
        );
        
        (valid_params && sufficient_tokens && has_enough_deep, deep_required, fee_estimate)
    }

    /// Helper function to determine if wrapper DEEP will be needed - core logic
    public fun will_use_wrapper_deep_core(
        wrapper_deep_reserves: u64,
        is_pool_whitelisted: bool,
        balance_manager_deep: u64,
        deep_in_wallet: u64,
        deep_required: u64
    ): (bool, bool) {
        // If pool is whitelisted, we don't need any DEEP
        if (is_pool_whitelisted) {
            return (false, true)
        };
        
        // Total DEEP from user's sources
        let user_deep_total = balance_manager_deep + deep_in_wallet;
        
        // If user has enough DEEP, we don't need wrapper DEEP
        if (user_deep_total >= deep_required) {
            return (false, true)
        };
        
        // Need to use wrapper DEEP
        let additional_deep_needed = deep_required - user_deep_total;
        let wrapper_has_enough = wrapper_deep_reserves >= additional_deep_needed;
        
        (true, wrapper_has_enough)
    }

    /// Calculate fee estimate for an order - core logic
    public fun calculate_fee_estimate_core(
        is_pool_whitelisted: bool,
        will_use_wrapper_deep: bool,
        quantity: u64,
        price: u64,
        is_bid: bool,
        pool_fee_bps: u64
    ): u64 {
        if (is_pool_whitelisted || !will_use_wrapper_deep) {
            0 // No fee for whitelisted pools or when user provides all DEEP
        } else {
            // Calculate order amount
            let order_amount = calculate_order_amount(quantity, price, is_bid);
            
            // Calculate fee based on order amount
            calculate_fee_amount(order_amount, pool_fee_bps)
        }
    }

    /// Helper function to validate pool parameters - core logic
    public fun validate_pool_params_core(
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
    public fun has_sufficient_tokens_core(
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
    public fun determine_deep_requirements_core(
        is_pool_whitelisted: bool,
        deep_required: u64,
        balance_manager_deep: u64,
        deep_in_wallet: u64,
        wrapper_deep_reserves: u64
    ): DeepRequirementPlan {
        // If pool is whitelisted, no DEEP is needed
        if (is_pool_whitelisted) {
            return DeepRequirementPlan {
                use_wrapper_deep: false,
                take_from_wallet: 0,
                take_from_wrapper: 0,
                has_sufficient_resources: true
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
            
            return DeepRequirementPlan {
                use_wrapper_deep: false,
                take_from_wallet: from_wallet,
                take_from_wrapper: 0,
                has_sufficient_resources: true
            }
        } else {
            // Need wrapper DEEP since user doesn't have enough
            let from_wallet = deep_in_wallet;  // Take all from wallet
            let still_needed = deep_required - user_deep_total;
            let has_sufficient = wrapper_deep_reserves >= still_needed;

            if (!has_sufficient) {
                return DeepRequirementPlan {
                    use_wrapper_deep: true,
                    take_from_wallet: 0,
                    take_from_wrapper: 0,
                    has_sufficient_resources: false
                }
            };

            return DeepRequirementPlan {
                use_wrapper_deep: true,
                take_from_wallet: from_wallet,
                take_from_wrapper: still_needed,
                has_sufficient_resources: true
            }
        }
    }
    
    /// Determine fee collection requirements - core logic
    /// For bid orders, fees are collected in quote tokens
    /// For ask orders, fees are collected in base tokens
    /// Returns a plan for fee collection
    public fun determine_fee_collection_core(
        use_wrapper_deep: bool,
        is_pool_whitelisted: bool,
        pool_fee_bps: u64,
        order_amount: u64,
        is_bid: bool,
        wallet_balance: u64,
        balance_manager_balance: u64
    ): FeeCollectionPlan {
        // No fee for whitelisted pools or when not using wrapper DEEP
        if (is_pool_whitelisted || !use_wrapper_deep) {
            return FeeCollectionPlan {
                token_type: 0,  // No fee
                fee_amount: 0,
                take_from_wallet: 0,
                take_from_balance_manager: 0,
                has_sufficient_resources: true
            }
        };
        
        // Calculate fee based on order amount
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        
        // If no fee, return early
        if (fee_amount == 0) {
            return FeeCollectionPlan {
                token_type: if (is_bid) 2 else 1,  // 1 for base, 2 for quote
                fee_amount: 0,
                take_from_wallet: 0,
                take_from_balance_manager: 0,
                has_sufficient_resources: true
            }
        };

        // Check if we have sufficient resources
        let has_sufficient = wallet_balance + balance_manager_balance >= fee_amount;

        if (!has_sufficient) {
            return FeeCollectionPlan {
                token_type: if (is_bid) 2 else 1,  // 1 for base, 2 for quote
                fee_amount,
                take_from_wallet: 0,
                take_from_balance_manager: 0,
                has_sufficient_resources: false
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
        
        FeeCollectionPlan {
            token_type: if (is_bid) 2 else 1,  // 1 for base, 2 for quote
            fee_amount,
            take_from_wallet: from_wallet,
            take_from_balance_manager: from_balance_manager,
            has_sufficient_resources: has_sufficient
        }
    }
    
    /// Determine token deposit requirements - core logic
    /// For bid orders, calculate how many quote tokens are needed
    /// For ask orders, calculate how many base tokens are needed
    public fun determine_token_deposit_core(
        required_amount: u64,
        wallet_balance: u64,
        balance_manager_balance: u64
    ): TokenDepositPlan {
        // Check if we already have enough in the balance manager
        if (balance_manager_balance >= required_amount) {
            return TokenDepositPlan {
                amount_needed: required_amount,
                take_from_wallet: 0,
                has_sufficient_resources: true
            }
        };
        
        // Calculate how much more is needed
        let additional_needed = required_amount - balance_manager_balance;
        let has_sufficient = wallet_balance >= additional_needed;

        if (!has_sufficient) {
            return TokenDepositPlan {
                amount_needed: required_amount,
                take_from_wallet: 0,
                has_sufficient_resources: false
            }
        };
        
        TokenDepositPlan {
            amount_needed: required_amount,
            take_from_wallet: additional_needed,
            has_sufficient_resources: true
        }
    }
    
    /// Create a limit order using tokens from various sources - core logic function
    /// This is a skeleton that orchestrates the process
    public fun create_limit_order_core(
        is_pool_whitelisted: bool,
        deep_required: u64,
        balance_manager_deep: u64,
        balance_manager_base: u64,
        balance_manager_quote: u64,
        deep_in_wallet: u64,
        base_in_wallet: u64,
        quote_in_wallet: u64,
        wrapper_deep_reserves: u64,
        quantity: u64,
        price: u64,
        is_bid: bool,
        pool_fee_bps: u64
    ): (DeepRequirementPlan, FeeCollectionPlan, TokenDepositPlan) {
        // Step 1: Determine DEEP requirements
        let deep_plan = determine_deep_requirements_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            deep_in_wallet,
            wrapper_deep_reserves
        );
        
        // Step 2: Calculate order amount based on order type
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        
        // Step 3: Determine fee collection based on order type
        let fee_plan = if (is_bid) {
            // For bid orders, fees are in quote tokens
            determine_fee_collection_core(
                deep_plan.use_wrapper_deep,
                is_pool_whitelisted,
                pool_fee_bps,
                order_amount,
                is_bid,
                quote_in_wallet,
                balance_manager_quote
            )
        } else {
            // For ask orders, fees are in base tokens
            determine_fee_collection_core(
                deep_plan.use_wrapper_deep,
                is_pool_whitelisted,
                pool_fee_bps,
                order_amount,
                is_bid,
                base_in_wallet,
                balance_manager_base
            )
        };
        
        // Step 4: Determine token deposit requirements
        let token_plan = if (is_bid) {
            // For bid orders, we need quote tokens
            determine_token_deposit_core(
                order_amount,
                quote_in_wallet - fee_plan.take_from_wallet,  // Account for fees already taken
                balance_manager_quote - fee_plan.take_from_balance_manager
            )
        } else {
            // For ask orders, we need base tokens
            determine_token_deposit_core(
                quantity,
                base_in_wallet - fee_plan.take_from_wallet,  // Account for fees already taken
                balance_manager_base - fee_plan.take_from_balance_manager
            )
        };
        
        (deep_plan, fee_plan, token_plan)
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

    /// Determines if a pool is whitelisted
    /// Whitelisted pools don't require DEEP tokens and don't charge fees
    public fun is_pool_whitelisted<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>
    ): bool {
        pool::whitelisted(pool)
    }
    
    /// Calculates the total amount of DEEP required for an order
    /// Returns 0 for whitelisted pools
    public fun calculate_deep_required<BaseToken, QuoteToken>(
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
    public fun calculate_order_amount(
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

    #[test_only]
    public fun assert_deep_plan_eq(
        actual: DeepRequirementPlan,
        expected_use_wrapper: bool,
        expected_from_wallet: u64,
        expected_from_wrapper: u64,
        expected_sufficient: bool
    ) {
        assert!(actual.use_wrapper_deep == expected_use_wrapper, 0);
        assert!(actual.take_from_wallet == expected_from_wallet, 0);
        assert!(actual.take_from_wrapper == expected_from_wrapper, 0);
        assert!(actual.has_sufficient_resources == expected_sufficient, 0);
    }

    #[test_only]
    public fun assert_fee_plan_eq(
        actual: FeeCollectionPlan,
        expected_token_type: u8,
        expected_fee_amount: u64,
        expected_take_from_wallet: u64,
        expected_take_from_balance_manager: u64,
        expected_sufficient: bool
    ) {
        assert!(actual.token_type == expected_token_type, 0);
        assert!(actual.fee_amount == expected_fee_amount, 0);
        assert!(actual.take_from_wallet == expected_take_from_wallet, 0);
        assert!(actual.take_from_balance_manager == expected_take_from_balance_manager, 0);
        assert!(actual.has_sufficient_resources == expected_sufficient, 0);
    }

    #[test_only]
    public fun assert_token_plan_eq(
        actual: TokenDepositPlan,
        expected_amount_needed: u64,
        expected_take_from_wallet: u64,
        expected_sufficient: bool
    ) {
        assert!(actual.amount_needed == expected_amount_needed, 0);
        assert!(actual.take_from_wallet == expected_take_from_wallet, 0);
        assert!(actual.has_sufficient_resources == expected_sufficient, 0);
    }
}