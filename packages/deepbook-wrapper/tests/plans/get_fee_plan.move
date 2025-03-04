#[test_only]
module deepbook_wrapper::get_fee_plan_tests {
    use deepbook_wrapper::wrapper::{
        get_fee_plan,
        assert_fee_plan_eq,
        calculate_fee_amount,
    };

    // ===== Constants =====

    // Order amounts
    const ORDER_TINY: u64 = 1_000;              // 1,000
    const ORDER_SMALL: u64 = 100_000;           // 100,000
    const ORDER_MEDIUM: u64 = 10_000_000;       // 10,000,000
    const ORDER_LARGE: u64 = 1_000_000_000;     // 1,000,000,000
    const ORDER_HUGE: u64 = 1_000_000_000_000;  // 1,000,000,000,000

    // Fee rates (in billionths, matching FEE_SCALING = 1,000,000,000)
    const FEE_ZERO: u64 = 0;             // 0%
    const FEE_LOW: u64 = 100_000;        // 0.01%
    const FEE_MEDIUM: u64 = 1_000_000;   // 0.1%
    const FEE_HIGH: u64 = 5_000_000;     // 0.5%
    const FEE_MAX: u64 = 10_000_000;     // 1%
    
    // Token types
    const TOKEN_TYPE_NONE: u8 = 0;  // No fee
    const TOKEN_TYPE_BASE: u8 = 1;  // Base token (for ask orders)
    const TOKEN_TYPE_QUOTE: u8 = 2; // Quote token (for bid orders)

    // ===== No Fee Required Tests =====

    #[test]
    public fun test_whitelisted_pool_requires_no_fee() {
        let is_pool_whitelisted = true;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = true;
        let wallet_balance = 1000;
        let balance_manager_balance = 1000;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Whitelisted pools should have no fee regardless of other factors
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_NONE,   // token_type = 0 (no fee)
            0,                  // fee_amount = 0
            0,                  // take_from_wallet = 0
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_not_using_wrapper_deep_requires_no_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = false;  // Not using wrapper DEEP
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = true;
        let wallet_balance = 1000;
        let balance_manager_balance = 1000;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Not using wrapper DEEP should have no fee
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_NONE,   // token_type = 0 (no fee)
            0,                  // fee_amount = 0
            0,                  // take_from_wallet = 0
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_zero_order_amount_has_zero_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = 0;  // Zero order amount
        let is_bid = true;
        let wallet_balance = 1000;
        let balance_manager_balance = 1000;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Expected token type is quote (2) for bid orders
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            0,                  // fee_amount = 0
            0,                  // take_from_wallet = 0
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_zero_fee_rate_has_zero_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_ZERO;  // Zero fee rate
        let order_amount = ORDER_MEDIUM;
        let is_bid = false;
        let wallet_balance = 1000;
        let balance_manager_balance = 1000;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Expected token type is base (1) for ask orders
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,   // token_type = 1 (base)
            0,                  // fee_amount = 0
            0,                  // take_from_wallet = 0
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    // ===== Token Type Tests =====

    #[test]
    public fun test_bid_order_uses_quote_token_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = true;  // Bid order
        let wallet_balance = 1000000;
        let balance_manager_balance = 1000000;

        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        
        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Bid orders should use quote tokens (type 2)
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            fee_amount,         // fee_amount = calculated fee
            fee_amount,         // take_from_wallet = fee_amount (wallet has enough)
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_ask_order_uses_base_token_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = false;  // Ask order
        let wallet_balance = 1000000;
        let balance_manager_balance = 1000000;

        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        
        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Ask orders should use base tokens (type 1)
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,    // token_type = 1 (base)
            fee_amount,         // fee_amount = calculated fee
            fee_amount,         // take_from_wallet = fee_amount (wallet has enough)
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    // ===== Fee Distribution Tests =====

    #[test]
    public fun test_fee_from_wallet_only() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = true;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = fee_amount * 2;  // Plenty in wallet
        let balance_manager_balance = 0;      // Nothing in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be entirely taken from wallet
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            fee_amount,         // fee_amount
            fee_amount,         // take_from_wallet = all fee
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_fee_from_balance_manager_only() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = true;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = 0;                    // Nothing in wallet
        let balance_manager_balance = fee_amount * 2;  // Plenty in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be entirely taken from balance manager
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            fee_amount,         // fee_amount
            0,                  // take_from_wallet = 0
            fee_amount,         // take_from_balance_manager = all fee
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_fee_split_between_wallet_and_balance_manager() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = true;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_part = fee_amount / 3;           // 1/3 in wallet
        let wallet_balance = wallet_part;
        let balance_manager_part = fee_amount - wallet_part;  // 2/3 in balance manager
        let balance_manager_balance = balance_manager_part;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be split between wallet and balance manager
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,       // token_type = 2 (quote)
            fee_amount,             // fee_amount
            wallet_part,            // take_from_wallet = wallet_part
            balance_manager_part,   // take_from_balance_manager = balance_manager_part
            true                    // has_sufficient_resources = true
        );
    }

    // ===== Insufficient Resources Tests =====

    #[test]
    public fun test_insufficient_fee_resources() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_LARGE;
        let is_bid = true;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = fee_amount / 4;  // 25% in wallet
        let balance_manager_balance = fee_amount / 4;  // 25% in balance manager
        // Total available is 50% of required fee

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Should indicate insufficient resources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,           // token_type = 2 (quote)
            fee_amount,                 // fee_amount
            0,                          // take_from_wallet = 0 (insufficient resources)
            0,                          // take_from_balance_manager = 0 (insufficient resources)
            false                       // has_sufficient_resources = false
        );
    }

    #[test]
    public fun test_almost_sufficient_fee_resources() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = false;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = fee_amount / 2;  // 50% in wallet
        let balance_manager_balance = (fee_amount / 2) - 1;  // Almost 50% in balance manager (1 short)
        // Total available is 1 less than required fee

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Should indicate insufficient resources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,            // token_type = 1 (base)
            fee_amount,                 // fee_amount
            0,                          // take_from_wallet = 0 (insufficient resources)
            0,                          // take_from_balance_manager = 0 (insufficient resources)
            false                       // has_sufficient_resources = false
        );
    }

    // ===== Boundary Tests =====

    #[test]
    public fun test_exact_fee_match_with_wallet() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = true;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = fee_amount;  // Exact match
        let balance_manager_balance = 0;  // Nothing in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be exactly covered by wallet
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            fee_amount,         // fee_amount
            fee_amount,         // take_from_wallet = exact fee
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_exact_fee_match_with_balance_manager() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_MEDIUM;
        let is_bid = false;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = 0;                 // Nothing in wallet
        let balance_manager_balance = fee_amount;  // Exact match

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be exactly covered by balance manager
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,    // token_type = 1 (base)
            fee_amount,         // fee_amount
            0,                  // take_from_wallet = 0
            fee_amount,         // take_from_balance_manager = exact fee
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_exact_fee_match_combined() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_HIGH;
        let order_amount = ORDER_LARGE;
        let is_bid = true;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = fee_amount / 2;  // Half in wallet
        let balance_manager_balance = fee_amount - wallet_balance;  // Rest in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be exactly covered by combined sources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,               // token_type = 2 (quote)
            fee_amount,                     // fee_amount
            wallet_balance,                 // take_from_wallet = wallet part
            balance_manager_balance,        // take_from_balance_manager = balance manager part
            true                            // has_sufficient_resources = true
        );
    }

    // ===== Edge Cases =====

    #[test]
    public fun test_huge_order_with_high_fee_rate() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MAX;
        let order_amount = ORDER_HUGE;
        let is_bid = true;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = fee_amount / 4;  // 25% in wallet
        let balance_manager_balance = fee_amount - wallet_balance;  // 75% in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be covered by combined sources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,               // token_type = 2 (quote)
            fee_amount,                     // fee_amount
            wallet_balance,                 // take_from_wallet = wallet part
            balance_manager_balance,        // take_from_balance_manager = balance manager part
            true                            // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_tiny_order_with_low_fee_rate() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_LOW;
        let order_amount = ORDER_TINY;
        let is_bid = false;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        // The fee might be 0 due to rounding
        
        let wallet_balance = 100;
        let balance_manager_balance = 100;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        if (fee_amount == 0) {
            // If fee is 0, it's handled differently
            assert_fee_plan_eq(
                plan,
                TOKEN_TYPE_BASE,    // token_type = 1 (base)
                0,                  // fee_amount = 0
                0,                  // take_from_wallet = 0
                0,                  // take_from_balance_manager = 0
                true                // has_sufficient_resources = true
            );
        } else {
            // Fee is non-zero but very small
            assert_fee_plan_eq(
                plan,
                TOKEN_TYPE_BASE,    // token_type = 1 (base)
                fee_amount,         // fee_amount = very small
                fee_amount,         // take_from_wallet = all fee (since wallet has enough)
                0,                  // take_from_balance_manager = 0
                true                // has_sufficient_resources = true
            );
        }
    }

    #[test]
    public fun test_wallet_exactly_one_token_short() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_SMALL;
        let is_bid = true;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = fee_amount - 1;  // 1 token short
        let balance_manager_balance = 0;  // Nothing in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Not enough resources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,       // token_type = 2 (quote)
            fee_amount,             // fee_amount
            0,                      // take_from_wallet = 0 (insufficient resources)
            0,                      // take_from_balance_manager = 0 (insufficient resources)
            false                   // has_sufficient_resources = false
        );
    }

    #[test]
    public fun test_balance_manager_exactly_one_token_short_with_empty_wallet() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let pool_fee_bps = FEE_MEDIUM;
        let order_amount = ORDER_SMALL;
        let is_bid = false;
        
        let fee_amount = calculate_fee_amount(order_amount, pool_fee_bps);
        let wallet_balance = 0;  // Empty wallet
        let balance_manager_balance = fee_amount - 1;  // 1 token short

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            is_pool_whitelisted,
            pool_fee_bps,
            order_amount,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Not enough resources
        // Per implementation, when balance_manager doesn't have enough, take_from_balance_manager is set to 0
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,               // token_type = 1 (base)
            fee_amount,                    // fee_amount
            0,                             // take_from_wallet = 0
            0,                             // take_from_balance_manager = 0 (not enough in balance manager)
            false                          // has_sufficient_resources = false
        );
    }
} 