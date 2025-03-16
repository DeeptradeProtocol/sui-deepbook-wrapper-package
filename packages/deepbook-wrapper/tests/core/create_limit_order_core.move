#[test_only]
module deepbook_wrapper::create_limit_order_core_tests {
    use deepbook_wrapper::order::{
        create_limit_order_core,
        assert_deep_plan_eq,
        assert_fee_plan_eq,
        assert_input_coin_deposit_plan_eq,
        DeepPlan,
        FeePlan,
        InputCoinDepositPlan
    };
    use deepbook_wrapper::helper::{calculate_order_amount};
    use deepbook_wrapper::fee::{calculate_full_order_fee};

    // ===== Constants =====
    // Token amounts
    const AMOUNT_SMALL: u64 = 1_000;               // 1,000
    const AMOUNT_MEDIUM: u64 = 1_000_000;          // 1 million
    const AMOUNT_LARGE: u64 = 1_000_000_000;       // 1 billion
    const AMOUNT_HUGE: u64 = 1_000_000_000_000;   // 1 trillion

    // SUI per DEEP
    const SUI_PER_DEEP: u64 = 37_815_000_000;
    
    // ===== Helper Function for Testing =====
    
    /// Helper function to assert all three plans match expected values
    public fun assert_order_plans_eq(
        deep_plan: DeepPlan,
        fee_plan: FeePlan,
        input_coin_deposit_plan: InputCoinDepositPlan,
        // Expected values for DeepPlan
        expected_use_wrapper_deep: bool,
        expected_deep_from_wallet: u64,
        expected_deep_from_reserves: u64,
        expected_deep_sufficient: bool,
        // Expected values for FeePlan (now all in SUI)
        expected_fee_amount: u64,
        expected_fee_from_wallet: u64,
        expected_fee_from_balance_manager: u64,
        expected_fee_sufficient: bool,
        // Expected values for InputCoinDepositPlan
        expected_order_amount: u64,
        expected_deposit_from_wallet: u64,
        expected_deposit_sufficient: bool
    ) {
        // Assert DeepPlan
        assert_deep_plan_eq(
            deep_plan,
            expected_use_wrapper_deep,
            expected_deep_from_wallet,
            expected_deep_from_reserves,
            expected_deep_sufficient
        );
        
        // Assert FeePlan
        assert_fee_plan_eq(
            fee_plan,
            expected_fee_amount,
            expected_fee_from_wallet,
            expected_fee_from_balance_manager,
            expected_fee_sufficient
        );
        
        // Assert InputCoinDepositPlan
        assert_input_coin_deposit_plan_eq(
            input_coin_deposit_plan,
            expected_order_amount,
            expected_deposit_from_wallet,
            expected_deposit_sufficient
        );
    }

    // ===== Bid Order Tests =====

    #[test]
    public fun test_bid_order_sufficient_resources() {
        // Order parameters
        let quantity = 1_000_000_000_000;
        let price = 2_000_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;  // Added SUI_PER_DEEP constant
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = AMOUNT_LARGE;
        
        let deep_in_wallet = AMOUNT_SMALL / 2;
        let sui_in_wallet = AMOUNT_LARGE;
        let wallet_input_coin = AMOUNT_LARGE;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid); // 2_000_000_000
        
        // For this test case we expect:
        // 1. DEEP: Half from wallet, half from balance manager
        // 2. Fees: None because no wrapper DEEP used
        // 3. Token deposit: Remaining from wallet
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,              // expected_use_wrapper_deep
            deep_in_wallet,     // expected_deep_from_wallet
            0,                  // expected_deep_from_reserves
            true,              // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                  // expected_fee_amount
            0,                  // expected_fee_from_wallet
            0,                  // expected_fee_from_balance_manager
            true,              // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            order_amount,       // expected_order_amount
            wallet_input_coin,  // expected_deposit_from_wallet
            true               // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_with_wrapper_deep() {
        // Order parameters
        let quantity = 100_000_000_000;
        let price = 1_500_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - not enough DEEP in wallet or balance manager
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let balance_manager_sui = 75_000_000;
        let balance_manager_input_coin = 75_000_000;
        
        let deep_in_wallet = AMOUNT_SMALL;
        let sui_in_wallet = 80_000_000;
        let wallet_input_coin = 80_000_000;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;

        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let (fee_amount, _, _) = calculate_full_order_fee(sui_per_deep, deep_from_wrapper);
        
        // For this test case we expect:
        // 1. DEEP: All from wallet and balance manager + some from wrapper
        // 2. Fees: All from wallet (in SUI)
        // 3. Token deposit: Remaining from wallet
        
        let deep_from_wallet = deep_in_wallet;
        let fee_from_wallet = fee_amount;
        let fee_from_balance_manager = 0;
        let deposit_from_wallet = order_amount - balance_manager_input_coin;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            deep_from_wallet,       // expected_deep_from_wallet
            deep_from_wrapper,      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            order_amount,           // expected_order_amount
            deposit_from_wallet,    // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_whitelisted_pool() {
        // Order parameters
        let quantity = 100_000;
        let price = 1_000_000;
        let is_bid = true;
        let is_pool_whitelisted = true;  // Whitelisted pool!
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = 0;
        let balance_manager_sui = AMOUNT_MEDIUM;
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        
        let deep_in_wallet = 0;
        let sui_in_wallet = AMOUNT_MEDIUM;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        
        // For this test case we expect:
        // 1. DEEP: None needed (whitelisted pool)
        // 2. Fees: None (whitelisted pool)
        // 3. Token deposit: All from balance manager
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,              // expected_use_wrapper_deep
            0,                  // expected_deep_from_wallet
            0,                  // expected_deep_from_reserves
            true,              // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                  // expected_fee_amount
            0,                  // expected_fee_from_wallet
            0,                  // expected_fee_from_balance_manager
            true,              // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            order_amount,       // expected_order_amount
            0,                  // expected_deposit_from_wallet
            true               // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_fee_from_both_sources() {
        // Order parameters
        let quantity = 1_000_000_000_000;
        let price = 2_000_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_LARGE;

        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let (fee_amount, _, _) = calculate_full_order_fee(sui_per_deep, deep_from_wrapper);
        
        // Set up a scenario where fees need to come from both sources
        let fee_from_wallet = fee_amount / 2;
        let fee_from_balance_manager = fee_amount - fee_from_wallet;
        
        // Set up SUI balances to match fee distribution
        let balance_manager_sui = fee_from_balance_manager;
        let sui_in_wallet = fee_from_wallet;
        
        // Set up input coin balances
        let wallet_input_coin = AMOUNT_LARGE;
        let balance_manager_input_coin = AMOUNT_LARGE;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_deep_from_wallet
            deep_from_wrapper,      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            order_amount,           // expected_order_amount
            wallet_input_coin,      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_insufficient_deep_no_wrapper() {
        // Order parameters
        let quantity = 100_000_000_000;
        let price = 1_500_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - not enough DEEP anywhere
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = AMOUNT_LARGE;
        
        let deep_in_wallet = AMOUNT_SMALL;
        let sui_in_wallet = AMOUNT_LARGE;
        let wallet_input_coin = AMOUNT_LARGE;
        
        let wrapper_deep_reserves = AMOUNT_SMALL;  // Not enough DEEP in wrapper

        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            0,                      // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            false,                  // expected_deep_sufficient (not enough DEEP)
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            order_amount,           // expected_order_amount
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_quote_only_in_balance_manager() {
        // Order parameters
        let quantity = 1_000_000_000_000;
        let price = 2_000_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - all resources in balance manager
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = AMOUNT_HUGE;
        
        let deep_in_wallet = 0;
        let sui_in_wallet = 0;
        let wallet_input_coin = 0;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,                  // expected_use_wrapper_deep
            0,                      // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount (no fee since not using wrapper DEEP)
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            order_amount,           // expected_order_amount
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_large_values() {
        // Order parameters with very large values
        let quantity = 1_000_000_000_000_000;
        let price = 1_000_000_000_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Make sure we have enough resources for this large order
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_LARGE;

        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;

        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let (fee_amount, _, _) = calculate_full_order_fee(sui_per_deep, deep_from_wrapper);
        
        // Set up SUI balances to cover fees
        let balance_manager_sui = 0;
        let sui_in_wallet = fee_amount;
        
        // Set up input coin balances
        let balance_manager_input_coin = 0;
        let wallet_input_coin = order_amount;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_deep_from_wallet
            deep_from_wrapper,      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            fee_amount,             // expected_fee_amount
            fee_amount,             // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            order_amount,           // expected_order_amount
            order_amount,           // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_exact_resources() {
        // Order parameters
        let quantity = 10_000_000_000;
        let price = 1_000_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - exactly what's needed
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = 0;
        let balance_manager_sui = 0;
        let balance_manager_input_coin = 0;
        
        let deep_in_wallet = deep_required;  // Exact amount in wallet
        let sui_in_wallet = 0;  // No SUI needed since not using wrapper DEEP
        let wallet_input_coin = calculate_order_amount(quantity, price, is_bid);
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,                  // expected_use_wrapper_deep
            deep_required,          // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount (no fee since not using wrapper DEEP)
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            order_amount,           // expected_order_amount
            order_amount,           // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    // ===== Ask Order Tests =====

    #[test]
    public fun test_ask_order_sufficient_resources() {
        // Order parameters
        let quantity = 10_000_000_000;
        let price = 10_000_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = 100_000_000_000;
        
        let deep_in_wallet = AMOUNT_SMALL;
        let sui_in_wallet = AMOUNT_LARGE;
        let wallet_input_coin = 100_000_000_000;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;

        let deep_from_wallet = deep_required - balance_manager_deep;
        
        // For this test case we expect:
        // 1. DEEP: Half from wallet, half from balance manager
        // 2. No fees since user doesn't use wrapper DEEP
        // 3. Token deposit: Full amount from wallet
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,                  // expected_use_wrapper_deep
            deep_from_wallet,       // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            0,                      // expected_deposit_from_wallet (balance manager has enough)
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_whitelisted_pool() {
        // Order parameters
        let quantity = 10_000;
        let price = 1_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = true;  // Whitelisted pool!
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = 0;
        let balance_manager_sui = AMOUNT_MEDIUM;
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        
        let deep_in_wallet = 0;
        let sui_in_wallet = AMOUNT_MEDIUM;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        // For this test case we expect:
        // 1. DEEP: None needed (whitelisted pool)
        // 2. Fees: None (whitelisted pool)
        // 3. Token deposit: All from balance manager
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,                  // expected_use_wrapper_deep
            0,                      // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_insufficient_deep_and_base() {
        // Order parameters
        let quantity = 20_564_999_999;
        let price = 40_000_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - not enough DEEP anywhere
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        
        let deep_in_wallet = AMOUNT_SMALL / 2;
        let sui_in_wallet = AMOUNT_LARGE;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
        let wrapper_deep_reserves = AMOUNT_SMALL;  // Not enough DEEP in wrapper

        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            0,                      // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            false,                  // expected_deep_sufficient (not enough DEEP)
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            0,                      // expected_deposit_from_wallet
            false                   // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_base_only_in_balance_manager() {
        // Order parameters
        let quantity = 10_000_000_000;
        let price = 1_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - base coins only in balance manager
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL - 50;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = quantity;  // All base coins in balance manager
        
        let deep_in_wallet = 0;
        let sui_in_wallet = 0;
        let wallet_input_coin = 0;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;

        let deep_from_wrapper = deep_required - balance_manager_deep;
        
        // Calculate fee for wrapper DEEP usage
        let (fee_amount, _, _) = calculate_full_order_fee(sui_per_deep, deep_from_wrapper);
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            0,                      // expected_deep_from_wallet
            deep_from_wrapper,      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            fee_amount,             // expected_fee_amount
            0,                      // expected_fee_from_wallet
            fee_amount,             // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_large_values() {
        // Order parameters with very large values
        let quantity = 1_000_000_000_000_000;
        let price = 1_000_000_000_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Make sure we have enough resources for this large order
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = 0;
        let balance_manager_sui = 0;
        let balance_manager_input_coin = 0;
        
        let deep_in_wallet = AMOUNT_MEDIUM - 100;
        let wrapper_deep_reserves = AMOUNT_LARGE;

        let deep_from_wrapper = deep_required - deep_in_wallet;

        // Calculate fee for wrapper DEEP usage
        let (fee_amount, _, _) = calculate_full_order_fee(sui_per_deep, deep_from_wrapper);
        
        // All resources from wallet
        let sui_in_wallet = fee_amount;
        let wallet_input_coin = quantity;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_deep_from_wallet
            deep_from_wrapper,      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            fee_amount,             // expected_fee_amount
            fee_amount,             // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            quantity,               // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_exact_resources() {
        // Order parameters
        let quantity = 2_000_000;
        let price = 40_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Set up resources to exactly match what's needed
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = 0;
        let balance_manager_sui = 0;
        let balance_manager_input_coin = 0;
        
        let deep_in_wallet = deep_required; // Exactly what's needed
        let sui_in_wallet = 0;  // No SUI needed since not using wrapper DEEP
        let wallet_input_coin = quantity; // Exactly what's needed
        
        let wrapper_deep_reserves = 0;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,                  // expected_use_wrapper_deep
            deep_required,          // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount (no fee since not using wrapper DEEP)
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            quantity,               // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_complex_distribution() {
        // Order parameters
        let quantity = 2_000_000;
        let price = 40_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - split between wallet and balance manager
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = deep_required / 2;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = 1_300_000;
        
        let deep_in_wallet = deep_required / 2;
        let sui_in_wallet = AMOUNT_LARGE;
        let wallet_input_coin = 700_000;
        
        let wrapper_deep_reserves = deep_required;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,                  // expected_use_wrapper_deep
            deep_in_wallet,         // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount (no fee since not using wrapper DEEP)
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            wallet_input_coin,      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_insufficient_base() {
        // Order parameters
        let quantity = 70_000_000;
        let price = 1_000_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - not enough DEEP to force using wrapper DEEP
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = quantity - AMOUNT_SMALL - 1;  // Not enough base coins
        
        let deep_in_wallet = AMOUNT_SMALL / 2;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Calculate fee for wrapper DEEP usage
        let (fee_amount, _, _) = calculate_full_order_fee(sui_per_deep, deep_from_wrapper);
        
        // Wallet has enough for fees but not enough for the deposit
        let sui_in_wallet = fee_amount;
        let wallet_input_coin = AMOUNT_SMALL;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_deep_from_wallet
            deep_from_wrapper,      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            fee_amount,             // expected_fee_amount
            fee_amount,             // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            0,                      // expected_deposit_from_wallet
            false                   // expected_deposit_sufficient (not enough base coins)
        );
    }

    #[test]
    public fun test_ask_order_with_wrapper_deep() {
        // Order parameters
        let quantity = 70_000;
        let price = 54_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - not enough DEEP in wallet or balance manager
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = 15_000;
        
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Calculate fee for wrapper DEEP usage
        let (fee_amount, _, _) = calculate_full_order_fee(sui_per_deep, deep_from_wrapper);
        
        // Set up SUI and input coin balances
        let sui_in_wallet = fee_amount;
        let wallet_input_coin = quantity - balance_manager_input_coin;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_deep_from_wallet
            deep_from_wrapper,      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            fee_amount,             // expected_fee_amount
            fee_amount,             // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            wallet_input_coin,      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_fee_from_both_sources() {
        // Order parameters
        let quantity = 35_123_821;
        let price = 474_576_743;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances - not enough DEEP to avoid using wrapper
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let balance_manager_input_coin = quantity;  // All base coins in balance manager
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;

        // Calculate fee for wrapper DEEP usage
        let (fee_amount, _, _) = calculate_full_order_fee(sui_per_deep, deep_from_wrapper);
        
        // Important: Make sure wallet doesn't have enough to cover all fees
        // We'll put 1/3 of the fee in wallet, 2/3 in balance manager
        let fee_from_wallet = fee_amount / 3;  // 1/3 of fee in wallet 
        let fee_from_balance_manager = fee_amount - fee_from_wallet;  // 2/3 of fee in balance manager
        
        // Set up SUI balances to match fee distribution
        let balance_manager_sui = fee_from_balance_manager;
        let sui_in_wallet = fee_from_wallet;
        
        // Set up input coin balances - all base coins in balance manager
        let wallet_input_coin = 0;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_deep_from_wallet
            deep_from_wrapper,      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            quantity,               // expected_order_amount
            0,                      // expected_deposit_from_wallet (all from balance manager)
            true                    // expected_deposit_sufficient
        );
    }

    // ===== Edge Cases =====

    #[test]
    public fun test_zero_quantity_order() {
        // Order parameters
        let quantity = 0;  // Zero quantity
        let price = 1_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        
        let deep_in_wallet = 0;
        let sui_in_wallet = AMOUNT_LARGE;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        // For this test case, order amount should be zero
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,                  // expected_use_wrapper_deep
            0,                      // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            0,                      // expected_order_amount
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_zero_price_order() {
        // Order parameters
        let quantity = 10_000;
        let price = 0;  // Zero price
        let is_bid = true;
        let is_pool_whitelisted = false;
        let sui_per_deep = SUI_PER_DEEP;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL;
        let balance_manager_sui = AMOUNT_LARGE;
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        
        let deep_in_wallet = 0;
        let sui_in_wallet = AMOUNT_LARGE;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let (deep_plan, fee_plan, input_coin_deposit_plan) = create_limit_order_core(
            is_pool_whitelisted,
            deep_required,
            balance_manager_deep,
            balance_manager_sui,
            balance_manager_input_coin,
            deep_in_wallet,
            sui_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            sui_per_deep
        );
        
        // For bid orders with zero price, order amount should be zero
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        assert!(order_amount == 0, 0);
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepPlan expectations
            false,                  // expected_use_wrapper_deep
            0,                      // expected_deep_from_wallet
            0,                      // expected_deep_from_reserves
            true,                   // expected_deep_sufficient
            // FeePlan expectations (all in SUI)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // InputCoinDepositPlan expectations
            0,                      // expected_order_amount
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }
} 