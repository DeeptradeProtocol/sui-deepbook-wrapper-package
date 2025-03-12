module deepbook_wrapper::fee {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use deepbook::pool::{Self, Pool};
    use deepbook_wrapper::helper::{calculate_order_amount, calculate_deep_required, get_order_deep_price_params};
    use deepbook_wrapper::math;
  
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
    /// Calculates the total fee estimate for a DeepBook order, including both protocol fee
    /// and DEEP reserves coverage fee if applicable.
    /// 
    /// # Returns
    /// * `u64` - The estimated total fee in base or quote asset units.
    ///   Returns 0 for whitelisted pools or when user provides all required DEEP.
    /// 
    /// # Parameters
    /// * `pool` - Reference to the DeepBook pool
    /// * `deep_in_balance_manager` - Amount of DEEP available in the balance manager
    /// * `deep_in_wallet` - Amount of DEEP in the user's wallet
    /// * `quantity` - Order quantity in base asset units
    /// * `price` - Order price in quote asset units
    /// * `is_bid` - Whether this is a bid (buy) order
    public fun estimate_full_fee<BaseToken, QuoteToken>(
        pool: &Pool<BaseToken, QuoteToken>,
        deep_in_balance_manager: u64,
        deep_in_wallet: u64,
        quantity: u64,
        price: u64,
        is_bid: bool
    ): u64 {
        // Check if pool is whitelisted
        let is_pool_whitelisted = pool::whitelisted(pool);

        // Get the order deep price for the pool
        let (asset_is_base, deep_per_asset) = get_order_deep_price_params(pool);

        // Get DEEP required for the order
        let deep_required = calculate_deep_required(pool, quantity, price);

        // Call the core logic function
        estimate_full_order_fee_core(
            is_pool_whitelisted,
            deep_in_balance_manager,
            deep_in_wallet,
            quantity,
            price,
            is_bid,
            asset_is_base,
            deep_per_asset,
            deep_required
        )
    }

    // === Public-Package Functions ===
    /// Core logic for calculating the total fee for an order.
    /// Determines if user needs to use wrapper DEEP reserves and calculates
    /// the appropriate fee if needed.
    /// 
    /// # Returns
    /// * `u64` - The estimated total fee in base or quote asset units.
    ///   Returns 0 for whitelisted pools or when user provides all required DEEP.
    /// 
    /// # Parameters
    /// * `is_pool_whitelisted` - Whether the pool is whitelisted (exempt from fees)
    /// * `balance_manager_deep` - Amount of DEEP available in the balance manager
    /// * `deep_in_wallet` - Amount of DEEP in the user's wallet
    /// * `quantity` - Order quantity in base asset units
    /// * `price` - Order price in quote asset units
    /// * `is_bid` - Whether this is a bid (buy) order
    /// * `asset_is_base` - Whether the asset used for DEEP conversion is the base token
    /// * `deep_per_asset` - The amount of DEEP units per 1 asset coin
    /// * `deep_required` - The total amount of DEEP required for the order
    public(package) fun estimate_full_order_fee_core(
        is_pool_whitelisted: bool,
        balance_manager_deep: u64,
        deep_in_wallet: u64,
        quantity: u64,
        price: u64,
        is_bid: bool,
        asset_is_base: bool,
        deep_per_asset: u64,
        deep_required: u64
    ): u64 {
        // Determine if user needs to use wrapper DEEP reserves
        let will_use_wrapper_deep = balance_manager_deep + deep_in_wallet < deep_required;

        if (is_pool_whitelisted || !will_use_wrapper_deep) {
            0 // No fee for whitelisted pools or when user provides all DEEP
        } else {
            // Calculate the amount of DEEP to take from reserves
            let deep_from_reserves = deep_required - balance_manager_deep - deep_in_wallet;
            
            // Calculate fee based on order amount, including both protocol fee and deep reserves coverage fee
            calculate_full_order_fee(quantity, price, is_bid, asset_is_base, deep_per_asset, deep_from_reserves, deep_required)
        }
    }

    /// Calculates the total fee amount including both protocol fee and deep reserves 
    /// coverage fee for an order that uses DEEP from reserves.
    /// 
    /// # Returns
    /// * `u64` - The total fee amount in base or quote asset units
    /// 
    /// # Parameters
    /// * `quantity` - Order quantity in base asset units
    /// * `price` - Order price in quote asset units
    /// * `is_bid` - Whether this is a bid (buy) order
    /// * `asset_is_base` - Whether the asset used for DEEP conversion is the base token
    /// * `deep_per_asset` - The amount of DEEP units per 1 asset coin
    /// * `deep_from_reserves` - The amount of DEEP taken from the wrapper's reserves
    /// * `total_deep_required` - The total DEEP required for the order
    public(package) fun calculate_full_order_fee(
        quantity: u64, 
        price: u64, 
        is_bid: bool,
        asset_is_base: bool,
        deep_per_asset: u64,
        deep_from_reserves: u64, 
        total_deep_required: u64
    ): u64 {
        // Calculate the deep reserves coverage fee
        let deep_reserves_coverage_fee = calculate_deep_reserves_coverage_order_fee(
            deep_from_reserves,
            asset_is_base,
            deep_per_asset,
            price,
            is_bid
        );

        // Calculate order amount
        let amount = calculate_order_amount(quantity, price, is_bid);

        // Calculate the protocol fee
        let protocol_fee = calculate_protocol_fee(
            amount,
            deep_from_reserves, 
            total_deep_required
        );
        
        deep_reserves_coverage_fee + protocol_fee
    }

    /// Calculates the fee to cover the cost of DEEP taken from reserves for an order.
    /// Converts DEEP to the appropriate asset (base or quote) based on the order type
    /// and the reference asset configuration.
    ///
    /// The calculation follows four different paths based on combinations of:
    /// 1. Whether the order is a buy or sell (`is_bid`)
    /// 2. Whether the reference asset for DEEP is the base or quote token (`asset_is_base`)
    ///
    /// For buy orders (is_bid = true):
    /// - If asset_is_base = true: DEEP → base asset → quote asset (using price)
    /// - If asset_is_base = false: DEEP → quote asset (direct)
    ///
    /// For sell orders (is_bid = false):
    /// - If asset_is_base = true: DEEP → base asset (direct)
    /// - If asset_is_base = false: DEEP → quote asset → base asset (using price)
    ///
    /// # Returns
    /// * `u64` - The calculated fee amount in base or quote asset units
    ///
    /// # Parameters
    /// * `deep_from_reserves` - Amount of DEEP taken from reserves for the order
    /// * `asset_is_base` - Whether the reference asset for DEEP conversion is the base token
    /// * `deep_per_asset` - The amount of DEEP units per 1 asset coin
    /// * `price` - Order price in quote asset units
    /// * `is_bid` - Whether this is a bid (buy) order
    public(package) fun calculate_deep_reserves_coverage_order_fee(
      deep_from_reserves: u64,
      asset_is_base: bool,
      deep_per_asset: u64,
      price: u64,
      is_bid: bool,
    ): u64 {
        // Skip calculation if no DEEP is required from reserves
        if (deep_from_reserves == 0) return 0;
    
        // Calculate DEEP equivalent in the reference asset (either base or quote)
        let asset_equivalent = math::div(deep_from_reserves, deep_per_asset);
    
        // Determine the fee amount based on order type and asset_is_base value
        if (is_bid) { // Buy order (user providing quote)
            if (asset_is_base) {
                // Reference is base token
                // Convert base equivalent to quote using price
                math::mul(asset_equivalent, price)
            } else {
                // Reference is quote token
                // User is already paying in quote, so return directly
                asset_equivalent
            }
        } else { // Sell order (user providing base)
            if (asset_is_base) {
                // Reference is base token
                // User is already paying in base, so return directly
                asset_equivalent
            } else {
                // Reference is quote token
                // Convert quote equivalent to base using price
                math::div(asset_equivalent, price)
            }
        }
    }

    /// Calculates the protocol fee based on the proportion of DEEP taken from reserves.
    /// The fee scales linearly with the proportion of DEEP used from reserves,
    /// up to the maximum fee rate (MAX_PROTOCOL_FEE_BPS).
    /// 
    /// # Returns
    /// * `u64` - The calculated protocol fee amount in the order's asset units
    /// 
    /// # Parameters
    /// * `amount` - The total order amount in asset units
    /// * `deep_from_reserves` - The amount of DEEP taken from the wrapper's reserves
    /// * `total_deep_required` - The total DEEP required for the order
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

    /// Calculates a basic swap fee based on an amount and a fee rate.
    /// Used primarily for calculating fees in traditional DEX swaps.
    /// 
    /// # Returns
    /// * `u64` - The calculated fee amount
    /// 
    /// # Parameters
    /// * `amount` - The amount of tokens to calculate fee on
    /// * `fee_bps` - The fee rate in billionths (e.g., 1,000,000 = 0.1%)
    public(package) fun calculate_swap_fee(amount: u64, fee_bps: u64): u64 {
        ((amount as u128) * (fee_bps as u128) / (FEE_SCALING as u128)) as u64
    }

    /// Charges a swap fee on a coin and returns the fee amount as a Balance.
    /// Allows collecting fees directly from a coin during swap operations.
    /// 
    /// # Returns
    /// * `Balance<CoinType>` - The fee amount as a Balance object
    /// 
    /// # Parameters
    /// * `coin` - The coin to charge fee from
    /// * `fee_bps` - The fee rate in billionths
    public(package) fun charge_swap_fee<CoinType>(
        coin: &mut Coin<CoinType>, 
        fee_bps: u64
    ): Balance<CoinType> {
        let coin_balance = coin::balance_mut(coin);
        let value = balance::value(coin_balance);
        balance::split(coin_balance, calculate_swap_fee(value, fee_bps))
    }
}