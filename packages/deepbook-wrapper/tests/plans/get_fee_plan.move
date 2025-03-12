#[test_only]
module deepbook_wrapper::get_fee_plan_tests {
    use deepbook_wrapper::order::{get_fee_plan, assert_fee_plan_eq};
    use deepbook_wrapper::fee::{calculate_protocol_fee, calculate_deep_reserves_coverage_order_fee};
    use deepbook_wrapper::helper::{calculate_order_amount};

    // ===== Constants =====
    // Quantities
    const QUANTITY_SMALL: u64 = 1_000;
    const QUANTITY_MEDIUM: u64 = 1_000_000;
    const QUANTITY_LARGE: u64 = 1_000_000_000;
    const QUANTITY_HUGE: u64 = 1_000_000_000_000;

    // Prices
    const PRICE_SMALL: u64 = 100_000;
    const PRICE_MEDIUM: u64 = 1_000_000;
    const PRICE_LARGE: u64 = 100_000_000;
    const PRICE_HUGE: u64 = 1_000_000_000;

    // DEEP per asset
    const SUI_DEEP_PER_ASSET: u64 = 29_637_955;
    const USDC_DEEP_PER_ASSET: u64 = 13_426_181_696;
    
    // Token types
    const TOKEN_TYPE_NONE: u8 = 0;  // No fee
    const TOKEN_TYPE_BASE: u8 = 1;  // Base token (for ask orders)
    const TOKEN_TYPE_QUOTE: u8 = 2; // Quote token (for bid orders)

    // ===== No Fee Required Tests =====

    #[test]
    public fun test_whitelisted_pool_requires_no_fee() {
        let is_pool_whitelisted = true;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 100;
        let total_deep_required = 200;
        let asset_is_base = true;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_LARGE;
        let price = PRICE_MEDIUM;
        let is_bid = true;
        let wallet_balance = 1000;
        let balance_manager_balance = 1000;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Whitelisted pools should have no fee regardless of other factors
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_NONE,    // token_type = 0 (no fee)
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
        let deep_from_reserves = 0;
        let total_deep_required = 100_000;
        let asset_is_base = false;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_LARGE;
        let price = PRICE_MEDIUM;
        let is_bid = true;
        let wallet_balance = 1000;
        let balance_manager_balance = 1000;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
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
    public fun test_zero_order_amount_has_only_deep_coverage_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 200_000;
        let total_deep_required = 250_000;
        let asset_is_base = true;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = 0;
        let price = PRICE_SMALL;
        let is_bid = true;
        let wallet_balance = 1000;
        let balance_manager_balance = 1000;

        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            deep_coverage_fee,  // fee_amount = deep coverage fee
            deep_coverage_fee,  // take_from_wallet = deep coverage fee
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    // ===== Token Type Tests =====

    #[test]
    public fun test_bid_order_uses_quote_token_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 50_000;
        let total_deep_required = 100_000;
        let asset_is_base = true;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = QUANTITY_LARGE;
        let price = PRICE_LARGE;
        let is_bid = true;  // Bid order
        let wallet_balance = 1000000;
        let balance_manager_balance = 1000000;

        let order_amount = calculate_order_amount(quantity, price, is_bid);

        // Calculate the expected deep coverage fee and protocol fee separately
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        
        // Total fee should be the sum of both
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Bid orders should use quote tokens (type 2)
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            total_fee,          // fee_amount = combined pool + protocol fee
            total_fee,          // take_from_wallet = all fee (wallet has enough)
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_ask_order_uses_base_token_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 50_000;
        let total_deep_required = 100_000;
        let asset_is_base = true;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_HUGE;
        let price = PRICE_LARGE;
        let is_bid = false;  // Ask order
        let wallet_balance = QUANTITY_HUGE;
        let balance_manager_balance = QUANTITY_HUGE;

        let order_amount = calculate_order_amount(quantity, price, is_bid);

        // Calculate the expected deep coverage fee and protocol fee separately
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        
        // Total fee should be the sum of both
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Ask orders should use base tokens (type 1)
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,    // token_type = 1 (base)
            total_fee,          // fee_amount = combined pool + protocol fee
            total_fee,          // take_from_wallet = all fee (wallet has enough)
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    // ===== Fee Distribution Tests =====

    #[test]
    public fun test_fee_from_wallet_only() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 25_000;
        let total_deep_required = 100_000;
        let asset_is_base = false;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_MEDIUM;
        let price = PRICE_MEDIUM;
        let is_bid = true;
        
        // Calculate the expected total fee with both pool fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = total_fee * 2;  // Plenty in wallet
        let balance_manager_balance = 0;      // Nothing in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be entirely taken from wallet
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            total_fee,          // fee_amount = total fee
            total_fee,          // take_from_wallet = all fee
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_fee_from_balance_manager_only() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 75_000;
        let total_deep_required = 100_000;
        let asset_is_base = false;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = QUANTITY_MEDIUM;
        let price = PRICE_MEDIUM;
        let is_bid = true;
        
        // Calculate the expected total fee with both pool fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = 0;                    // Nothing in wallet
        let balance_manager_balance = total_fee * 2;  // Plenty in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be entirely taken from balance manager
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            total_fee,          // fee_amount = total fee
            0,                  // take_from_wallet = 0
            total_fee,          // take_from_balance_manager = all fee
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_fee_split_between_wallet_and_balance_manager() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 40_000;
        let total_deep_required = 100_000;
        let asset_is_base = true;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = QUANTITY_LARGE;
        let price = PRICE_MEDIUM;
        let is_bid = true;
        
        // Calculate the expected total fee with both pool fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_part = total_fee / 3;           // 1/3 in wallet
        let wallet_balance = wallet_part;
        let balance_manager_part = total_fee - wallet_part;  // 2/3 in balance manager
        let balance_manager_balance = balance_manager_part;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be split between wallet and balance manager
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,       // token_type = 2 (quote)
            total_fee,              // fee_amount = total fee
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
        let deep_from_reserves = 60_000;
        let total_deep_required = 100_000;
        let asset_is_base = true;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_LARGE;
        let price = PRICE_LARGE;
        let is_bid = true;
        
        // Calculate the expected total fee with both pool fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = total_fee / 4;          // 25% in wallet
        let balance_manager_balance = total_fee / 4;  // 25% in balance manager
        // Total available is 50% of required fee

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Should indicate insufficient resources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,           // token_type = 2 (quote)
            total_fee,                  // fee_amount = total calculated fee
            0,                          // take_from_wallet = 0 (insufficient resources)
            0,                          // take_from_balance_manager = 0 (insufficient resources)
            false                       // has_sufficient_resources = false
        );
    }

    #[test]
    public fun test_almost_sufficient_fee_resources() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 35_000;
        let total_deep_required = 100_000;
        let asset_is_base = false;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_MEDIUM;
        let price = PRICE_MEDIUM;
        let is_bid = false;
        
        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = total_fee / 2;  // 50% in wallet
        let balance_manager_balance = (total_fee / 2) - 1;  // Almost 50% in balance manager (1 short)
        // Total available is 1 less than required fee

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Should indicate insufficient resources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,            // token_type = 1 (base)
            total_fee,                  // fee_amount = total calculated fee
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
        let deep_from_reserves = 50_000;
        let total_deep_required = 100_000;
        let asset_is_base = true;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = QUANTITY_HUGE;
        let price = PRICE_MEDIUM;
        let is_bid = true;
        
        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = total_fee;  // Exact match
        let balance_manager_balance = 0;  // Nothing in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be exactly covered by wallet
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            total_fee,          // fee_amount = total fee
            total_fee,          // take_from_wallet = exact fee
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_exact_fee_match_with_balance_manager() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 20_000;
        let total_deep_required = 100_000;
        let asset_is_base = false;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = QUANTITY_MEDIUM;
        let price = PRICE_SMALL;
        let is_bid = false;
        
        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = 0;                 // Nothing in wallet
        let balance_manager_balance = total_fee;  // Exact match

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be exactly covered by balance manager
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,    // token_type = 1 (base)
            total_fee,          // fee_amount = total fee
            0,                  // take_from_wallet = 0
            total_fee,          // take_from_balance_manager = exact fee
            true                // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_exact_fee_match_combined() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 80_000;
        let total_deep_required = 100_000;
        let asset_is_base = true;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = QUANTITY_LARGE;
        let price = PRICE_HUGE;
        let is_bid = true;
        
        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = total_fee / 2;  // Half in wallet
        let balance_manager_balance = total_fee - wallet_balance;  // Rest in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be exactly covered by combined sources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,               // token_type = 2 (quote)
            total_fee,                      // fee_amount = total fee
            wallet_balance,                 // take_from_wallet = wallet part
            balance_manager_balance,        // take_from_balance_manager = balance manager part
            true                            // has_sufficient_resources = true
        );
    }

    // ===== Edge Cases =====

    #[test]
    public fun test_huge_order_with_high_fees() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 1_000_000_000;
        let total_deep_required = 1_000_000_000;
        let asset_is_base = true;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_HUGE;
        let price = PRICE_HUGE;
        let is_bid = true;
        
        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = total_fee / 4;  // 25% in wallet
        let balance_manager_balance = total_fee - wallet_balance;  // 75% in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Fee should be covered by combined sources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,               // token_type = 2 (quote)
            total_fee,                      // fee_amount = total fee
            wallet_balance,                 // take_from_wallet = wallet part
            balance_manager_balance,        // take_from_balance_manager = balance manager part
            true                            // has_sufficient_resources = true
        );
    }

    #[test]
    public fun test_tiny_order_with_low_fee_rate() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 100;
        let total_deep_required = 100;
        let asset_is_base = false;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = QUANTITY_SMALL;
        let price = PRICE_SMALL;
        let is_bid = false;
        
        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = 100;
        let balance_manager_balance = 100;

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        if (total_fee == 0) {
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
            // Check if we have sufficient resources
            let has_sufficient = wallet_balance + balance_manager_balance >= total_fee;
            
            if (has_sufficient) {
                // Fee is non-zero but very small and we have enough resources
                let from_wallet = if (wallet_balance >= total_fee) {
                    total_fee
                } else {
                    wallet_balance
                };
                
                let from_balance_manager = if (from_wallet < total_fee) {
                    total_fee - from_wallet
                } else {
                    0
                };
                
                assert_fee_plan_eq(
                    plan,
                    TOKEN_TYPE_BASE,        // token_type = 1 (base)
                    total_fee,              // fee_amount = total fee
                    from_wallet,            // take_from_wallet = what wallet can afford
                    from_balance_manager,   // take_from_balance_manager = remainder
                    true                    // has_sufficient_resources = true
                );
            } else {
                // Not enough resources for even the tiny fee
                assert_fee_plan_eq(
                    plan,
                    TOKEN_TYPE_BASE,        // token_type = 1 (base)
                    total_fee,              // fee_amount = total fee
                    0,                      // take_from_wallet = 0 (insufficient)
                    0,                      // take_from_balance_manager = 0 (insufficient)
                    false                   // has_sufficient_resources = false
                );
            }
        }
    }

    #[test]
    public fun test_wallet_exactly_one_token_short() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 15_000;
        let total_deep_required = 100_000;
        let asset_is_base = true;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_SMALL;
        let price = PRICE_SMALL;
        let is_bid = true;
        
        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = total_fee - 1;  // 1 token short
        let balance_manager_balance = 0;     // Nothing in balance manager

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Not enough resources
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,       // token_type = 2 (quote)
            total_fee,              // fee_amount = total fee
            0,                      // take_from_wallet = 0 (insufficient resources)
            0,                      // take_from_balance_manager = 0 (insufficient resources)
            false                   // has_sufficient_resources = false
        );
    }

    #[test]
    public fun test_balance_manager_exactly_one_token_short_with_empty_wallet() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 45_000;
        let total_deep_required = 100_000;
        let asset_is_base = false;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_MEDIUM;
        let price = PRICE_MEDIUM;
        let is_bid = false;
        
        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let wallet_balance = 0;              // Empty wallet
        let balance_manager_balance = total_fee - 1;  // 1 token short

        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Not enough resources
        // Per implementation, when balance_manager doesn't have enough, take_from_balance_manager is set to 0
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_BASE,               // token_type = 1 (base)
            total_fee,                     // fee_amount = total fee
            0,                             // take_from_wallet = 0
            0,                             // take_from_balance_manager = 0 (not enough in balance manager)
            false                          // has_sufficient_resources = false
        );
    }
    
    // ===== Protocol Fee Specific Tests =====
    
    #[test]
    public fun test_zero_deep_from_reserves_has_only_pool_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 0;  // No DEEP from reserves
        let total_deep_required = 100_000;
        let asset_is_base = true;
        let deep_per_asset = SUI_DEEP_PER_ASSET;
        let quantity = QUANTITY_MEDIUM;
        let price = PRICE_MEDIUM;
        let is_bid = true;
        let wallet_balance = 1000000;
        let balance_manager_balance = 1000000;

        // Only pool fee should be charged since deep_from_reserves is 0
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        
        // Protocol fee should be 0 when no DEEP is taken from reserves
        assert!(protocol_fee == 0, 0);
        
        let total_fee = deep_coverage_fee; // Only pool fee, no protocol fee
        
        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Only pool fee should apply
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            total_fee,          // fee_amount = pool fee only
            total_fee,          // take_from_wallet = all fee (wallet has enough)
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }
    
    #[test]
    public fun test_full_deep_from_reserves_has_maximum_protocol_fee() {
        let is_pool_whitelisted = false;
        let use_wrapper_deep_reserves = true;
        let deep_from_reserves = 100_000;    // All DEEP from reserves
        let total_deep_required = 100_000;   // All DEEP required
        let asset_is_base = true;
        let deep_per_asset = USDC_DEEP_PER_ASSET;
        let quantity = QUANTITY_MEDIUM;
        let price = PRICE_MEDIUM;
        let is_bid = true;
        let wallet_balance = 10000000;
        let balance_manager_balance = 10000000;

        // Calculate the expected total fee with both deep coverage fee and protocol fee
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let deep_coverage_fee = calculate_deep_reserves_coverage_order_fee(deep_from_reserves, asset_is_base, deep_per_asset, price, is_bid);
        let protocol_fee = calculate_protocol_fee(order_amount, deep_from_reserves, total_deep_required);
        
        // Protocol fee should be at maximum when all DEEP is from reserves
        let total_fee = deep_coverage_fee + protocol_fee;
        
        let plan = get_fee_plan(
            use_wrapper_deep_reserves,
            deep_from_reserves,
            total_deep_required,
            is_pool_whitelisted,
            asset_is_base,
            deep_per_asset,
            quantity,
            price,
            is_bid,
            wallet_balance,
            balance_manager_balance
        );

        // Maximum protocol fee should apply
        assert_fee_plan_eq(
            plan,
            TOKEN_TYPE_QUOTE,   // token_type = 2 (quote)
            total_fee,          // fee_amount = deep coverage fee + max protocol fee
            total_fee,          // take_from_wallet = all fee (wallet has enough)
            0,                  // take_from_balance_manager = 0
            true                // has_sufficient_resources = true
        );
    }
    
    #[test]
    public fun test_protocol_fee_scaling_with_deep_ratio() {
        let order_amount = 1_000_000_000;
        let total_deep_required = 100_000;
        
        // Test with 0% from reserves
        let deep_from_reserves_0 = 0;
        let protocol_fee_0 = calculate_protocol_fee(order_amount, deep_from_reserves_0, total_deep_required);
        assert!(protocol_fee_0 == 0, 0); // No protocol fee with 0%
        
        // Test with 25% from reserves
        let deep_from_reserves_25 = 25_000;
        let protocol_fee_25 = calculate_protocol_fee(order_amount, deep_from_reserves_25, total_deep_required);
        assert!(protocol_fee_25 > 0, 0); // Should have some protocol fee
        
        // Test with 50% from reserves
        let deep_from_reserves_50 = 50_000;
        let protocol_fee_50 = calculate_protocol_fee(order_amount, deep_from_reserves_50, total_deep_required);
        assert!(protocol_fee_50 > protocol_fee_25, 0); // Should be higher than 25%
        
        // Test with 75% from reserves
        let deep_from_reserves_75 = 75_000;
        let protocol_fee_75 = calculate_protocol_fee(order_amount, deep_from_reserves_75, total_deep_required);
        assert!(protocol_fee_75 > protocol_fee_50, 0); // Should be higher than 50%
        
        // Test with 100% from reserves
        let deep_from_reserves_100 = 100_000;
        let protocol_fee_100 = calculate_protocol_fee(order_amount, deep_from_reserves_100, total_deep_required);
        assert!(protocol_fee_100 > protocol_fee_75, 0); // Should be higher than 75%
        
        // Verify that protocol fees scale approximately linearly with the deep ratio
        let ratio_50_25 = (protocol_fee_50 as u128) * 100 / (protocol_fee_25 as u128);
        let ratio_75_25 = (protocol_fee_75 as u128) * 100 / (protocol_fee_25 as u128);
        let ratio_100_25 = (protocol_fee_100 as u128) * 100 / (protocol_fee_25 as u128);
        
        // The ratio should be approximately proportional (with some rounding differences)
        assert!(ratio_50_25 >= 195 && ratio_50_25 <= 205, 0); // ~200%
        assert!(ratio_75_25 >= 295 && ratio_75_25 <= 305, 0); // ~300%
        assert!(ratio_100_25 >= 395 && ratio_100_25 <= 405, 0); // ~400%
    }
} 