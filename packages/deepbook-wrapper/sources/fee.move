module deepbook_wrapper::fee {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use deepbook::pool::{Self, Pool};
    use deepbook_wrapper::helper::{get_fee_bps, calculate_order_amount};
  
    // === Errors ===
    /// Error when the amount of DEEP from reserves exceeds the total DEEP required
    #[error]
    const EInvalidDeepReservesAmount: u64 = 1;

    // === Constants ===
    /// Define a constant for the fee scaling factor
    /// This matches DeepBook's FLOAT_SCALING constant (10^9) used for fee calculations
    /// Fees are expressed in billionths, e.g., 1,000,000 = 0.1% (1,000,000/1,000,000,000)
    const FEE_SCALING: u64 = 1_000_000_000;

    /// Maximum fee rate for protocol fee in billionths (0.3%)
    const MAX_PROTOCOL_FEE_BPS: u64 = 3_000_000;

    // === Public-View Functions ===
    /// Calculates the fee estimate for an order
    /// Returns 0 for whitelisted pools or when user provides all DEEP
    public fun estimate_full_fee<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        will_use_wrapper_deep: bool,
        quantity: u64,
        price: u64,
        is_bid: bool,
        deep_from_reserves: u64,
        total_deep_required: u64
    ): u64 {
        // Check if pool is whitelisted
        let is_pool_whitelisted = pool::whitelisted(pool);
        
        // Get pool fee basis points
        let pool_fee_bps = get_fee_bps(pool);
        
        // Call the core logic function
        estimate_full_fee_core(
            is_pool_whitelisted,
            will_use_wrapper_deep,
            quantity,
            price,
            is_bid,
            pool_fee_bps,
            deep_from_reserves,
            total_deep_required
        )
    }

    // === Public-Package Functions ===
    /// Calculate fee estimate for an order - core logic
    public(package) fun estimate_full_fee_core(
        is_pool_whitelisted: bool,
        will_use_wrapper_deep: bool,
        quantity: u64,
        price: u64,
        is_bid: bool,
        pool_fee_bps: u64,
        deep_from_reserves: u64, 
        total_deep_required: u64
    ): u64 {
        if (is_pool_whitelisted || !will_use_wrapper_deep) {
            0 // No fee for whitelisted pools or when user provides all DEEP
        } else {
            // Calculate order amount
            let order_amount = calculate_order_amount(quantity, price, is_bid);
            
            // Calculate fee based on order amount, including both protocol fee and deep reserves coverage fee
            calculate_full_fee(order_amount, pool_fee_bps, deep_from_reserves, total_deep_required)
        }
    }

    /// Calculates the deep reserves coverage fee based on the token amount and fee rate from the pool
    /// @param amount - The amount of tokens to calculate fee on
    /// @param fee_bps - The fee rate in billionths (e.g., 1,000,000 = 0.1%)
    /// @return The calculated fee amount
    public(package) fun calculate_deep_reserves_coverage_fee(amount: u64, fee_bps: u64): u64 {
        ((amount as u128) * (fee_bps as u128) / (FEE_SCALING as u128)) as u64
    }

    /// Calculates the protocol fee based on the proportion of DEEP taken from reserves
    /// @param amount - The token amount to calculate fee on
    /// @param deep_from_reserves - The amount of DEEP taken from the wrapper's reserves
    /// @param total_deep_required - The total DEEP required for the order
    /// @return The calculated protocol fee amount
    public(package) fun calculate_protocol_fee(
        amount: u64, 
        deep_from_reserves: u64, 
        total_deep_required: u64
    ): u64 {
        if (total_deep_required == 0 || deep_from_reserves == 0) {
            return 0
        };

        // Verify that deep_from_reserves doesn't exceed total_deep_required
        assert!(deep_from_reserves <= total_deep_required, EInvalidDeepReservesAmount);

        // Calculate the proportion of DEEP taken from reserves (as a ratio)
        let proportion = (deep_from_reserves as u128) * (FEE_SCALING as u128) / (total_deep_required as u128);
        
        // Calculate the fee rate based on the proportion and the maximum fee rate
        let fee_rate = (proportion * (MAX_PROTOCOL_FEE_BPS as u128)) / (FEE_SCALING as u128);
        
        // Calculate the fee amount
        ((amount as u128) * fee_rate / (FEE_SCALING as u128)) as u64
    }

    /// Calculates the total fee amount including both protocol fee and deep reserves coverage fee
    /// @param amount - The token amount to calculate fee on
    /// @param fee_bps - The pool fee rate in billionths used for deep reserves coverage fee
    /// @param deep_from_reserves - The amount of DEEP taken from the wrapper's reserves
    /// @param total_deep_required - The total DEEP required for the order
    /// @return The total calculated fee amount
    public(package) fun calculate_full_fee(
        amount: u64, 
        fee_bps: u64, 
        deep_from_reserves: u64, 
        total_deep_required: u64
    ): u64 {
        let deep_reserves_coverage_fee = calculate_deep_reserves_coverage_fee(amount, fee_bps);
        let protocol_fee = calculate_protocol_fee(
            amount, 
            deep_from_reserves, 
            total_deep_required
        );
        
        deep_reserves_coverage_fee + protocol_fee
    }

    /// Charges only the deep reserves coverage fee on a coin
    /// @param coin - The coin to charge fee from
    /// @param fee_bps - The fee rate in billionths (from DeepBook pool parameters)
    /// @return The fee amount as a Balance
    public(package) fun charge_deep_reserves_coverage_fee<CoinType>(
        coin: &mut Coin<CoinType>, 
        fee_bps: u64
    ): Balance<CoinType> {
        let coin_balance = coin::balance_mut(coin);
        let value = balance::value(coin_balance);
        balance::split(coin_balance, calculate_deep_reserves_coverage_fee(value, fee_bps))
    }

    /// Charges only the protocol fee on a coin based on DEEP usage
    /// @param coin - The coin to charge fee from
    /// @param deep_from_reserves - The amount of DEEP taken from the wrapper's reserves
    /// @param total_deep_required - The total DEEP required for the order
    /// @return The fee amount as a Balance
    #[allow(unused_function)]
    public(package) fun charge_protocol_fee<CoinType>(
        coin: &mut Coin<CoinType>, 
        deep_from_reserves: u64,
        total_deep_required: u64
    ): Balance<CoinType> {
        let coin_balance = coin::balance_mut(coin);
        let value = balance::value(coin_balance);
        balance::split(coin_balance, calculate_protocol_fee(value, deep_from_reserves, total_deep_required))
    }
    
    /// Charges the full fee (both deep reserves coverage fee and protocol fee) on a coin
    /// @param coin - The coin to charge fee from
    /// @param fee_bps - The fee rate in billionths (from DeepBook pool parameters)
    /// @param deep_from_reserves - The amount of DEEP taken from the wrapper's reserves
    /// @param total_deep_required - The total DEEP required for the order
    /// @return The fee amount as a Balance
    #[allow(unused_function)]
    public(package) fun charge_full_fee<CoinType>(
        coin: &mut Coin<CoinType>, 
        fee_bps: u64,
        deep_from_reserves: u64,
        total_deep_required: u64
    ): Balance<CoinType> {
        let coin_balance = coin::balance_mut(coin);
        let value = balance::value(coin_balance);
        balance::split(coin_balance, calculate_full_fee(value, fee_bps, deep_from_reserves, total_deep_required))
    }
}