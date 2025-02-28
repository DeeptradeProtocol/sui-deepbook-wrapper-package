module deepbook_wrapper::wrapper {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::bag::{Self, Bag};
    use sui::clock::Clock;
    use sui::event;
    
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

    /// Event emitted when an order is created using DEEP from reserves
    public struct OrderCreatedWithDeep has copy, drop {
        order_id: u128,
        pool_id: ID,
        client_order_id: u64,
        is_bid: bool,
        owner: address,
        quantity: u64,
        price: u64,
        deep_amount: u64
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

    /// Error when the order size is too small
    #[error]
    const EOrderTooSmall: u64 = 4;

    /// Error when the lot size constraint is not met
    #[error]
    const EInvalidLotSize: u64 = 5;

    /// Error when the tick size constraint is not met
    #[error]
    const EInvalidTickSize: u64 = 6;

    /// Error when the caller is not the owner of the balance manager
    #[error]
    const EInvalidOwner: u64 = 7;
    
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
        quantity: u64,
        price: u64,
        is_bid: bool,
        input_amount: u64
    ): (bool, u64, u64) {
        // Calculate DEEP required
        let (deep_required, _deep_required_maker) = pool::get_order_deep_required(pool, quantity, price);
        
        // Check if the wrapper has enough DEEP
        let has_enough_deep = balance::value(&wrapper.deep_reserves) >= deep_required;
        
        // Calculate fee
        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        let fee_estimate = calculate_fee_amount(input_amount, fee_bps);
        
        // Validate order parameters
        let (tick_size, lot_size, min_size) = pool::pool_book_params(pool);
        
        let valid_params = 
            quantity >= min_size && 
            quantity % lot_size == 0 && 
            price % tick_size == 0;
        
        // Verify sufficient input after fee
        let sufficient_input = if (is_bid) {
            // For bid orders, check if remaining quote tokens can cover the order
            (input_amount - fee_estimate) >= math::mul(quantity, price)
        } else {
            // For ask orders, check if remaining base tokens can meet the quantity
            (input_amount - fee_estimate) >= quantity
        };
        
        (has_enough_deep && valid_params && sufficient_input, deep_required, fee_estimate)
    }

    /// Create a limit order using DEEP from the wrapper's reserves
    /// Returns the order info and remaining coins
    public fun create_limit_order<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        pool: &mut Pool<BaseToken, QuoteToken>,
        balance_manager: &mut BalanceManager,
        mut base_coin: Coin<BaseToken>,
        mut quote_coin: Coin<QuoteToken>,
        price: u64,
        quantity: u64,
        is_bid: bool,
        expire_timestamp: u64,
        client_order_id: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (deepbook::order_info::OrderInfo, Coin<BaseToken>, Coin<QuoteToken>) {
        // Verify the caller owns the balance manager
        assert!(balance_manager::owner(balance_manager) == tx_context::sender(ctx), EInvalidOwner);
        
        // Validate order parameters
        validate_order_parameters(pool, quantity, price);
        
        // Deposit DEEP tokens
        let deep_required = deposit_deep_for_order(wrapper, pool, balance_manager, quantity, price, ctx);
        
        // Handle the specific order type preparation
        if (is_bid) {
            // Handle bid-specific logic (buy BaseToken using QuoteToken)
            let order_value = math::mul(quantity, price);
            
            // Process the input coin, charging fees and preparing payment
            let fee = charge_fee(&mut quote_coin, get_fee_bps(pool));
            join_fee(wrapper, fee);
            
            let remaining_value = coin::value(&quote_coin);
            assert!(remaining_value >= order_value, EInsufficientFeeOrInput);
            
            let order_payment = coin::split(&mut quote_coin, order_value, ctx);
            balance_manager::deposit(balance_manager, order_payment, ctx);
        } else {
            // Handle ask-specific logic (sell BaseToken for QuoteToken)
            let fee = charge_fee(&mut base_coin, get_fee_bps(pool));
            join_fee(wrapper, fee);
            
            let remaining_quantity = coin::value(&base_coin);
            assert!(remaining_quantity >= quantity, EInsufficientFeeOrInput);
            
            let order_payment = coin::split(&mut base_coin, quantity, ctx);
            balance_manager::deposit(balance_manager, order_payment, ctx);
        };
        
        // Generate proof and place order
        let proof = balance_manager::generate_proof_as_owner(balance_manager, ctx);
        
        let order_info = pool::place_limit_order(
            pool,
            balance_manager,
            &proof,
            client_order_id,
            0, // default order type (limit)
            0, // default self matching option
            price,
            quantity,
            is_bid,
            true, // pay_with_deep
            expire_timestamp,
            clock,
            ctx
        );
        
        // Emit event
        emit_order_created_event(
            pool, 
            order_info.order_id(), 
            client_order_id, 
            is_bid, 
            ctx, 
            quantity, 
            price, 
            deep_required
        );
        
        // Return order info and remaining coins
        (order_info, base_coin, quote_coin)
    }
    
    /// Validate order parameters against pool constraints
    fun validate_order_parameters<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        quantity: u64,
        price: u64
    ) {
        let (tick_size, lot_size, min_size) = pool::pool_book_params(pool);
        
        assert!(quantity >= min_size, EOrderTooSmall);
        assert!(quantity % lot_size == 0, EInvalidLotSize);
        assert!(price % tick_size == 0, EInvalidTickSize);
    }
    
    /// Get fee basis points from pool parameters
    fun get_fee_bps<BaseToken, QuoteToken>(pool: &Pool<BaseToken, QuoteToken>): u64 {
        let (fee_bps, _, _) = pool::pool_trade_params(pool);
        fee_bps
    }
    
    /// Deposit DEEP tokens for an order and return amount used
    fun deposit_deep_for_order<BaseToken, QuoteToken>(
        wrapper: &mut DeepBookV3RouterWrapper,
        pool: &Pool<BaseToken, QuoteToken>,
        balance_manager: &mut BalanceManager,
        quantity: u64,
        price: u64,
        ctx: &mut TxContext
    ): u64 {
        // Calculate DEEP required
        let (deep_required, _) = pool::get_order_deep_required(pool, quantity, price);
        
        // Check if the wrapper has enough DEEP
        assert!(balance::value(&wrapper.deep_reserves) >= deep_required, EInsufficientDeepReserves);
        
        // Handle DEEP deposit
        let deep_payment = coin::from_balance(
            balance::split(&mut wrapper.deep_reserves, deep_required),
            ctx
        );
        
        // Add DEEP to balance manager - will be used to pay fees
        balance_manager::deposit(balance_manager, deep_payment, ctx);
        
        deep_required
    }
    
    /// Emit order created event
    fun emit_order_created_event<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        order_id: u128,
        client_order_id: u64,
        is_bid: bool,
        ctx: &TxContext,
        quantity: u64,
        price: u64,
        deep_amount: u64
    ) {
        event::emit(OrderCreatedWithDeep {
            order_id,
            pool_id: object::id(pool),
            client_order_id,
            is_bid,
            owner: tx_context::sender(ctx),
            quantity,
            price,
            deep_amount
        });
    }
}