#[test_only]
module deepbook_wrapper::create_limit_order_core_tests {
    use deepbook_wrapper::wrapper::{
        create_limit_order_core,
        calculate_order_amount,
        assert_deep_plan_eq,
        assert_fee_plan_eq,
        assert_input_coin_deposit_plan_eq,
        calculate_full_fee,
        DeepPlan,
        FeePlan,
        InputCoinDepositPlan
    };

    // ===== Constants =====

    // Token amounts
    const AMOUNT_SMALL: u64 = 1_000;               // 1,000
    const AMOUNT_MEDIUM: u64 = 1_000_000;          // 1 million
    const AMOUNT_LARGE: u64 = 1_000_000_000;       // 1 billion
    
    // Fee rates (in billionths, matching FEE_SCALING = 1,000,000,000)
    const FEE_ZERO: u64 = 0;             // 0%
    const FEE_MEDIUM: u64 = 1_000_000;   // 0.1%
    
    // Token types
    const FEE_COIN_TYPE_NONE: u8 = 0;  // No fee
    const FEE_COIN_TYPE_BASE: u8 = 1;  // Base coin (for ask orders)
    const FEE_COIN_TYPE_QUOTE: u8 = 2; // Quote coin (for bid orders)

    // ===== Helper Function for Testing =====
    
    /// Helper function to assert all three plans match expected values
    public fun assert_order_plans_eq(
        deep_plan: DeepPlan,
        fee_plan: FeePlan,
        input_coin_deposit_plan: InputCoinDepositPlan,
        // Expected values for DeepRequirementPlan
        expected_use_wrapper_deep: bool,
        expected_take_from_wallet: u64,
        expected_take_from_wrapper: u64,
        expected_deep_sufficient: bool,
        // Expected values for FeeCollectionPlan
        expected_fee_coin_type: u8,
        expected_fee_amount: u64,
        expected_fee_from_wallet: u64,
        expected_fee_from_balance_manager: u64,
        expected_fee_sufficient: bool,
        // Expected values for TokenDepositPlan
        expected_amount_needed: u64,
        expected_deposit_from_wallet: u64,
        expected_deposit_sufficient: bool
    ) {
        // Assert DeepRequirementPlan
        assert_deep_plan_eq(
            deep_plan,
            expected_use_wrapper_deep,
            expected_take_from_wallet,
            expected_take_from_wrapper,
            expected_deep_sufficient
        );
        
        // Assert FeeCollectionPlan
        assert_fee_plan_eq(
            fee_plan,
            expected_fee_coin_type,
            expected_fee_amount,
            expected_fee_from_wallet,
            expected_fee_from_balance_manager,
            expected_fee_sufficient
        );
        
        // Assert TokenDepositPlan
        assert_input_coin_deposit_plan_eq(
            input_coin_deposit_plan,
            expected_amount_needed,
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let deep_in_wallet = AMOUNT_SMALL / 2;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let balance_manager_input_coin = AMOUNT_LARGE;
        let wallet_input_coin = AMOUNT_LARGE;
        
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
            balance_manager_input_coin,
            deep_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
            wallet_input_coin,      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_with_wrapper_deep() {
        // Order parameters
        let quantity = 100_000_000_000;
        let price = 1_500_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - not enough DEEP in wallet or balance manager
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;

        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid); // 150_000_000
        let fee_amount = calculate_full_fee(order_amount, pool_fee_bps, deep_from_wrapper, deep_required); // 150_000
        
        let balance_manager_input_coin = 75_000_000;
        let wallet_input_coin = 80_000_000;
        
        // For this test case we expect:
        // 1. DEEP: All from wallet and balance manager + some from wrapper
        // 2. Fees: All from wallet
        // 3. Token deposit: Remaining from wallet (after fees)
        
        let deep_from_wallet = deep_in_wallet;
        let fee_from_wallet = fee_amount;
        let fee_from_balance_manager = 0;
        let deposit_from_wallet = order_amount - balance_manager_input_coin;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            deep_from_wallet,       // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_QUOTE,       // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = 0;
        let deep_in_wallet = 0;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
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
            balance_manager_input_coin,
            deep_in_wallet,
            wallet_input_coin,
            wrapper_deep_reserves,
            quantity,
            price,
            is_bid,
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            0,                      // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_fee_from_both_sources() {
        // Order parameters
        let quantity = 1_000_000_000_000;
        let price = 2_000_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_LARGE;

        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Set up a scenario where fees need to come from both sources
        let order_amount = calculate_order_amount(quantity, price, is_bid); // 2_000_000_000
        let fee_amount = calculate_full_fee(order_amount, pool_fee_bps, deep_from_wrapper, deep_required); // 2_000_000
        let fee_from_wallet = fee_amount / 2;
        let fee_from_balance_manager = fee_amount - fee_from_wallet;
        
        let wallet_input_coin = fee_from_wallet;  // Half of fees
        let balance_manager_input_coin = fee_from_balance_manager + order_amount;  // Half of order amount + half of fees
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_QUOTE,       // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_insufficient_quote_after_fees() {
        // Order parameters
        let quantity = 10_000_000;
        let price = 1_000_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - enough for DEEP, but not enough for coins after fees
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_LARGE;

        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid); // 10_000
        let fee_amount = calculate_full_fee(order_amount, pool_fee_bps, deep_from_wrapper, deep_required); // 10
        
        // Set up a scenario where there's not enough for the order and fees
        let wallet_input_coin = order_amount / 2;
        let balance_manager_input_coin = order_amount / 2;

        let fee_from_wallet = fee_amount;
        let fee_from_balance_manager = 0;
        
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
            pool_fee_bps
        );
        
        // For this test case, there's not enough for the order
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_QUOTE,       // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
            0,                      // expected_deposit_from_wallet (not enough, so 0)
            false                   // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_bid_order_insufficient_deep_no_wrapper() {
        // Order parameters
        let quantity = 100_000_000_000;
        let price = 1_500_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - not enough DEEP anywhere
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_SMALL;  // Not enough DEEP in wrapper
        
        let balance_manager_input_coin = AMOUNT_LARGE;
        let wallet_input_coin = AMOUNT_LARGE;

        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid); // 150_000_000
        let fee_amount = calculate_full_fee(order_amount, pool_fee_bps, 0, deep_required); // 150_000

        let fee_from_wallet = fee_amount;
        let fee_from_balance_manager = 0;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            0,                      // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            false,                  // expected_deep_sufficient (not enough DEEP)
            // FeeCollectionPlan
            FEE_COIN_TYPE_QUOTE,       // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - quote coins only in balance manager
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = 0;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let order_amount = calculate_order_amount(quantity, price, is_bid); // 2_000_000_000
        
        // All quote coins in balance manager, none in wallet
        let balance_manager_input_coin = order_amount; // No need to add fee_amount since there are no fees
        let wallet_input_coin = 0;
        
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
            pool_fee_bps
        );
        
        // For this test case, there should be no fees since the user doesn't use wrapper DEEP
        // (balance_manager_deep is sufficient to cover deep_required)
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            0,                      // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type (no fee since not using wrapper DEEP)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Make sure we have enough resources for this large order
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_LARGE;

        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;

        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        let fee_amount = calculate_full_fee(order_amount, pool_fee_bps, deep_from_wrapper, deep_required);
        
        let balance_manager_input_coin = 0;
        let wallet_input_coin = order_amount + fee_amount;

        let fee_from_wallet = fee_amount;
        let fee_from_balance_manager = 0;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_QUOTE,       // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
            order_amount,           // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    // TODO: Need to fix after fee calculation formula is updated
    #[test]
    public fun test_bid_order_zero_fee() {
        // Order parameters
        let quantity = 10_000_000_000;
        let price = 1_000_000;
        let is_bid = true;
        let is_pool_whitelisted = false;
        let pool_fee_bps = FEE_ZERO;  // Zero fee
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let deep_in_wallet = AMOUNT_SMALL / 2;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        
        // Split order amount between wallet and balance manager
        let balance_manager_input_coin = order_amount / 2;
        let wallet_input_coin = order_amount / 2;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
            wallet_input_coin,      // expected_deposit_from_wallet
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - exactly what's needed
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = 0;
        let deep_in_wallet = deep_required;  // Exact amount in wallet
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        // Calculate expected values
        let order_amount = calculate_order_amount(quantity, price, is_bid); // 10_000_000
        
        // Exact resources in wallet for coin deposit
        let wallet_input_coin = order_amount;
        let balance_manager_input_coin = 0;
        
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
            pool_fee_bps
        );
        
        // For this test case, resources are exactly what's needed
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            deep_required,          // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type (no fee since not using wrapper DEEP)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            order_amount,           // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;

        let deep_from_wallet = deep_required - balance_manager_deep;
        
        let balance_manager_input_coin = 100_000_000_000;
        let wallet_input_coin = 100_000_000_000;
        
        // For this test case we expect:
        // 1. DEEP: Half from wallet, half from balance manager
        // 2. No fees since user doesn't use wrapper DEEP
        // 3. Token deposit: Full amount from wallet
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            deep_from_wallet,       // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type (no fee since not using wrapper DEEP)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = 0;
        let deep_in_wallet = 0;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
        // For this test case we expect:
        // 1. DEEP: None needed (whitelisted pool)
        // 2. Fees: None (whitelisted pool)
        // 3. Token deposit: All from balance manager
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            0,                      // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - not enough DEEP
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let deep_in_wallet = AMOUNT_SMALL / 2;
        let wrapper_deep_reserves = AMOUNT_SMALL;  // Not enough in wrapper either

        // For ask orders, we need base coins (the coin being sold)
        let fee_amount = calculate_full_fee(quantity, pool_fee_bps, 0, deep_required);
        
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            0,                      // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            false,                  // expected_deep_sufficient (not enough DEEP)
            // FeeCollectionPlan
            FEE_COIN_TYPE_BASE,        // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            false,                  // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - base coins only in balance manager
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL - 50;
        let deep_in_wallet = 0;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;

        let deep_from_wrapper = deep_required - balance_manager_deep;
        
        // For ask orders, we need base coins (the coin being sold)
        let fee_amount = calculate_full_fee(quantity, pool_fee_bps, deep_from_wrapper, deep_required);
        
        // All base coins in balance manager, none in wallet
        let wallet_input_coin = 0;
        let balance_manager_input_coin = quantity + fee_amount;
        
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
            pool_fee_bps
        );
        
        // For this test case, there should be no fees since the user doesn't use wrapper DEEP
        // (balance_manager_deep is sufficient to cover deep_required)
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            0,                      // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_BASE,        // expected_fee_coin_type (no fee since not using wrapper DEEP)
            fee_amount,             // expected_fee_amount
            0,                      // expected_fee_from_wallet
            fee_amount,             // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Make sure we have enough resources for this large order
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = 0;
        let deep_in_wallet = AMOUNT_MEDIUM - 100;
        let wrapper_deep_reserves = AMOUNT_LARGE;

        let deep_from_wrapper = deep_required - deep_in_wallet;

        // Calculate fee for this large order
        let fee_amount = calculate_full_fee(quantity, pool_fee_bps, deep_from_wrapper, deep_required);
        
        let balance_manager_input_coin = 0;
        let wallet_input_coin = quantity + fee_amount;  // Exact amount needed
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_BASE,        // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_amount,             // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
            quantity,               // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }

    // TODO: Need to fix after fee calculation formula is updated
    #[test]
    public fun test_ask_order_zero_fee() {
        // Order parameters
        let quantity = 10_000;
        let price = 1_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let pool_fee_bps = FEE_ZERO;  // Zero fee
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let deep_in_wallet = AMOUNT_SMALL / 2;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        // Split base coins between wallet and balance manager
        let balance_manager_input_coin = quantity / 2;
        let wallet_input_coin = quantity / 2;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type (no fee since not using wrapper DEEP)
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
            wallet_input_coin,      // expected_deposit_from_wallet
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Set up resources to exactly match what's needed
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = 0;
        let deep_in_wallet = deep_required; // Exactly what's needed
        let wrapper_deep_reserves = 0;
        
        // For ask orders, we need exact base coins
        let balance_manager_input_coin = 0;
        let wallet_input_coin = quantity; // Exactly what's needed
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            deep_required,          // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = deep_required / 2;
        let deep_in_wallet = deep_required / 2;
        let wrapper_deep_reserves = deep_required;
        
        let wallet_input_coin = 700_000;
        let balance_manager_input_coin = 1_300_000;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - not enough DEEP to force using wrapper DEEP
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL / 2;
        let deep_in_wallet = AMOUNT_SMALL / 2;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Calculate fee
        let fee_amount = calculate_full_fee(quantity, pool_fee_bps, deep_from_wrapper, deep_required); // 70_000
        
        // Not enough base coins after accounting for fees
        // Wallet has enough for fees but not enough for the deposit
        let wallet_input_coin = fee_amount + AMOUNT_SMALL;
        let balance_manager_input_coin = quantity - AMOUNT_SMALL - 1;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_BASE,        // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_amount,             // expected_fee_from_wallet - all from wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
            0,                      // expected_deposit_from_wallet (used for fees)
            false                   // expected_deposit_sufficient
        );
    }

    #[test]
    public fun test_ask_order_with_wrapper_deep() {
        // Order parameters
        let quantity = 70_000;
        let price = 1_000_000;
        let is_bid = false;  // Ask order
        let is_pool_whitelisted = false;
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - not enough DEEP in wallet or balance manager
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;
        
        // Calculate expected values
        let fee_amount = calculate_full_fee(quantity, pool_fee_bps, deep_from_wrapper, deep_required);

        let balance_manager_input_coin = 15_000;
        let wallet_input_coin = 100_000;
        
        // For this test case we expect:
        // 1. DEEP: All from wallet and balance manager + some from wrapper
        // 2. Fees: All from wallet
        // 3. Token deposit: Remaining from wallet (after fees)
        
        let deep_from_wallet = deep_in_wallet;
        let fee_from_wallet = fee_amount;
        let fee_from_balance_manager = 0;
        let deposit_from_wallet = quantity - balance_manager_input_coin;
        
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
            pool_fee_bps
        );
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            deep_from_wallet,       // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_BASE,        // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
            deposit_from_wallet,    // expected_deposit_from_wallet (balance manager has enough)
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances - not enough DEEP to avoid using wrapper
        let deep_required = AMOUNT_MEDIUM;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = AMOUNT_SMALL;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        let deep_from_wrapper = deep_required - balance_manager_deep - deep_in_wallet;

        // Calculate fee for this order
        let fee_amount = calculate_full_fee(quantity, pool_fee_bps, deep_from_wrapper, deep_required);
        
        // Important: Make sure wallet doesn't have enough to cover all fees
        // We'll put 1/3 of the fee in wallet, 2/3 in balance manager
        let fee_from_wallet = fee_amount / 3;  // 1/3 of fee in wallet 
        let fee_from_balance_manager = fee_amount - fee_from_wallet;  // 2/3 of fee in balance manager
        
        let wallet_input_coin = fee_from_wallet;
        let balance_manager_input_coin = fee_from_balance_manager + quantity;
        
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
            pool_fee_bps
        );
        
        // Since wallet only has fee_from_wallet, it should have 0 left for deposit
        let deposit_from_wallet = 0;
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            true,                   // expected_use_wrapper_deep
            deep_in_wallet,         // expected_take_from_wallet
            deep_from_wrapper,      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_BASE,        // expected_fee_coin_type
            fee_amount,             // expected_fee_amount
            fee_from_wallet,        // expected_fee_from_wallet
            fee_from_balance_manager, // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            quantity,               // expected_amount_needed
            deposit_from_wallet,    // expected_deposit_from_wallet
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = 0;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
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
            pool_fee_bps
        );
        
        // For this test case, order amount should be zero
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            0,                      // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            0,                      // expected_amount_needed
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
        let pool_fee_bps = FEE_MEDIUM;
        
        // Resource balances
        let deep_required = AMOUNT_SMALL;
        let balance_manager_deep = AMOUNT_SMALL;
        let deep_in_wallet = 0;
        let wrapper_deep_reserves = AMOUNT_MEDIUM;
        
        let balance_manager_input_coin = AMOUNT_MEDIUM;
        let wallet_input_coin = AMOUNT_MEDIUM;
        
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
            pool_fee_bps
        );
        
        // For bid orders with zero price, order amount should be zero
        let order_amount = calculate_order_amount(quantity, price, is_bid);
        assert!(order_amount == 0, 0);
        
        assert_order_plans_eq(
            deep_plan,
            fee_plan,
            input_coin_deposit_plan,
            // DeepRequirementPlan
            false,                  // expected_use_wrapper_deep
            0,                      // expected_take_from_wallet
            0,                      // expected_take_from_wrapper
            true,                   // expected_deep_sufficient
            // FeeCollectionPlan
            FEE_COIN_TYPE_NONE,        // expected_fee_coin_type
            0,                      // expected_fee_amount
            0,                      // expected_fee_from_wallet
            0,                      // expected_fee_from_balance_manager
            true,                   // expected_fee_sufficient
            // TokenDepositPlan
            0,                      // expected_amount_needed
            0,                      // expected_deposit_from_wallet
            true                    // expected_deposit_sufficient
        );
    }
} 