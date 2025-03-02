#[test_only]
module deepbook_wrapper::determine_deep_requirements_core_tests {
    use deepbook_wrapper::wrapper::{Self, assert_deep_plan_eq};

    // -------------------------------------
    // Constants for realistic DEEP amounts
    // -------------------------------------
    const DEEP_SMALL: u64 = 1_000_000;           // 1 DEEP 
    const DEEP_MEDIUM: u64 = 100_000_000;        // 100 DEEP
    const DEEP_LARGE: u64 = 10_000_000_000;      // 10,000 DEEP
    const DEEP_HUGE: u64 = 1_000_000_000_000;    // 1,000,000 DEEP
    
    // -------------------------------------
    // Test Category 1: Whitelisted Pools
    // -------------------------------------
    
    #[test]
    fun test_whitelisted_pools() {
        // Test 1: Whitelisted pool with zero requirements
        let plan = wrapper::determine_deep_requirements_core(
            true, // is whitelisted
            0,    // deep required
            0,    // manager balance
            0,    // wallet balance
            0     // wrapper reserves
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
        
        // Test 2: Whitelisted pool with non-zero requirements (should still return zeros)
        let plan = wrapper::determine_deep_requirements_core(
            true,        // is whitelisted  
            DEEP_LARGE,  // deep required
            0,           // manager balance
            0,           // wallet balance
            0            // wrapper reserves
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
        
        // Test 3: Whitelisted pool with available DEEP (should ignore available DEEP)
        let plan = wrapper::determine_deep_requirements_core(
            true,        // is whitelisted  
            DEEP_LARGE,  // deep required
            DEEP_SMALL,  // some in manager
            DEEP_SMALL,  // some in wallet
            DEEP_HUGE    // large wrapper reserves
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
    }
    
    // -------------------------------------
    // Test Category 2: User Has Sufficient DEEP
    // -------------------------------------
    
    #[test]
    fun test_user_has_sufficient_deep_all_in_manager() {
        // All DEEP in manager, nothing in wallet
        let required = DEEP_MEDIUM;
        let plan = wrapper::determine_deep_requirements_core(
            false,       // not whitelisted
            required,    // deep required
            required,    // exact amount in manager
            0,           // nothing in wallet
            0            // wrapper reserves (unused)
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
        
        // Excess DEEP in manager
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            required * 2,    // excess in manager
            0,               // nothing in wallet
            0                // wrapper reserves (unused)
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
    }
    
    #[test]
    fun test_user_has_sufficient_deep_all_in_wallet() {
        // All DEEP in wallet, nothing in manager
        let required = DEEP_MEDIUM;
        let plan = wrapper::determine_deep_requirements_core(
            false,       // not whitelisted
            required,    // deep required
            0,           // nothing in manager
            required,    // exact amount in wallet
            0            // wrapper reserves (unused)
        );
        assert_deep_plan_eq(plan, false, required, 0, true);
        
        // Excess DEEP in wallet
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            0,               // nothing in manager
            required * 2,    // excess in wallet
            0                // wrapper reserves (unused)
        );
        assert_deep_plan_eq(plan, false, required, 0, true);
    }
    
    #[test]
    fun test_user_has_sufficient_deep_split() {
        // DEEP split between manager and wallet
        let required = DEEP_MEDIUM;
        let manager_amount = required / 3;
        let wallet_amount = required - manager_amount;
        
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            manager_amount,  // some in manager
            wallet_amount,   // rest in wallet
            0                // wrapper reserves (unused)
        );
        assert_deep_plan_eq(plan, false, wallet_amount, 0, true);
        
        // DEEP split with excess in both
        let plan = wrapper::determine_deep_requirements_core(
            false,               // not whitelisted
            required,            // deep required
            manager_amount * 2,  // excess in manager
            wallet_amount * 2,   // excess in wallet
            0                    // wrapper reserves (unused)
        );
        // Should only take what's needed from wallet
        assert_deep_plan_eq(plan, false, required - manager_amount * 2, 0, true);
    }

    #[test]
    fun test_user_has_more_deep_in_manager_than_required() {
        // Manager has more DEEP than required
        let required = DEEP_MEDIUM;
        let plan = wrapper::determine_deep_requirements_core(
            false,          // not whitelisted
            required,       // deep required
            required * 2,   // double required in manager
            DEEP_SMALL,     // small amount in wallet
            0               // wrapper reserves (unused)
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
    }
    
    // -------------------------------------
    // Test Category 3: User Needs Wrapper DEEP
    // -------------------------------------
    
    #[test]
    fun test_user_needs_partial_wrapper_deep() {
        // User has some DEEP, needs wrapper for the rest
        let required = DEEP_MEDIUM;
        let user_deep = required / 2;
        let wrapper_needed = required - user_deep;
        
        let plan = wrapper::determine_deep_requirements_core(
            false,       // not whitelisted
            required,    // deep required
            0,           // nothing in manager
            user_deep,   // some in wallet
            required     // sufficient wrapper reserves
        );
        assert_deep_plan_eq(plan, true, user_deep, wrapper_needed, true);
        
        // Split user DEEP between manager and wallet
        let manager_deep = user_deep / 2;
        let wallet_deep = user_deep - manager_deep;
        
        let plan = wrapper::determine_deep_requirements_core(
            false,          // not whitelisted
            required,       // deep required
            manager_deep,   // some in manager
            wallet_deep,    // some in wallet
            required        // sufficient wrapper reserves
        );
        assert_deep_plan_eq(plan, true, wallet_deep, wrapper_needed, true);
    }
    
    #[test]
    fun test_user_needs_all_wrapper_deep() {
        // No user DEEP, all from wrapper
        let required = DEEP_MEDIUM;
        
        let plan = wrapper::determine_deep_requirements_core(
            false,       // not whitelisted
            required,    // deep required
            0,           // nothing in manager
            0,           // nothing in wallet
            required     // exact wrapper reserves
        );
        assert_deep_plan_eq(plan, true, 0, required, true);
        
        // No user DEEP, wrapper has excess
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            0,               // nothing in manager
            0,               // nothing in wallet
            required * 2     // excess wrapper reserves
        );
        assert_deep_plan_eq(plan, true, 0, required, true);
    }
    
    #[test]
    fun test_wrapper_exact_remainder() {
        // Wrapper has exact amount needed for remainder
        let required = DEEP_MEDIUM;
        let user_deep = required / 3;
        let wrapper_needed = required - user_deep;
        
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            0,               // nothing in manager
            user_deep,       // some in wallet
            wrapper_needed   // exact wrapper reserves needed
        );
        assert_deep_plan_eq(plan, true, user_deep, wrapper_needed, true);
    }
    
    // -------------------------------------
    // Test Category 4: Insufficient Resources
    // -------------------------------------
    
    #[test]
    fun test_insufficient_wrapper_reserves() {
        // Wrapper doesn't have enough to fulfill
        let required = DEEP_MEDIUM;
        let user_deep = required / 2;
        let wrapper_needed = required - user_deep;
        let insufficient_reserves = wrapper_needed - 1; // One token short
        
        let plan = wrapper::determine_deep_requirements_core(
            false,                 // not whitelisted
            required,              // deep required
            0,                     // nothing in manager
            user_deep,             // some in wallet
            insufficient_reserves  // insufficient wrapper reserves
        );
        assert_deep_plan_eq(plan, true, user_deep, 0, false);
        
        // Almost nothing in wrapper
        let plan = wrapper::determine_deep_requirements_core(
            false,         // not whitelisted
            required,      // deep required
            0,             // nothing in manager
            user_deep,     // some in wallet
            1              // just 1 token in wrapper
        );
        assert_deep_plan_eq(plan, true, user_deep, 0, false);
    }
    
    #[test]
    fun test_no_deep_anywhere() {
        // No DEEP anywhere, but some required
        let required = DEEP_MEDIUM;
        
        let plan = wrapper::determine_deep_requirements_core(
            false,       // not whitelisted
            required,    // deep required
            0,           // nothing in manager
            0,           // nothing in wallet
            0            // no wrapper reserves
        );
        assert_deep_plan_eq(plan, true, 0, 0, false);
        
        // Small amount in user, none in wrapper
        let small_amount = required / 10;
        let plan = wrapper::determine_deep_requirements_core(
            false,          // not whitelisted
            required,       // deep required
            small_amount,   // small amount in manager
            0,              // nothing in wallet
            0               // no wrapper reserves
        );
        assert_deep_plan_eq(plan, true, 0, 0, false);
    }
    
    // -------------------------------------
    // Test Category 5: Edge Cases
    // -------------------------------------
    
    #[test]
    fun test_zero_deep_required() {
        // Zero DEEP required (non-whitelisted)
        let plan = wrapper::determine_deep_requirements_core(
            false, // not whitelisted
            0,     // zero deep required
            0,     // manager balance
            0,     // wallet balance
            0      // wrapper reserves
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
        
        // Zero DEEP required but DEEP available
        let plan = wrapper::determine_deep_requirements_core(
            false,       // not whitelisted
            0,           // zero deep required
            DEEP_SMALL,  // some in manager
            DEEP_SMALL,  // some in wallet
            DEEP_SMALL   // some in wrapper
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
    }
    
    #[test]
    fun test_large_values() {
        // Large values (near u64 limits)
        let large_value = 9_223_372_036_854_775_000; // Just under u64::MAX
        
        // Large requirement with matching manager balance
        let plan = wrapper::determine_deep_requirements_core(
            false,         // not whitelisted
            large_value,   // large deep required
            large_value,   // matching manager balance
            0,             // wallet balance
            0              // wrapper reserves
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
        
        // Large requirement with matching wallet balance
        let plan = wrapper::determine_deep_requirements_core(
            false,         // not whitelisted
            large_value,   // large deep required
            0,             // manager balance
            large_value,   // matching wallet balance
            0              // wrapper reserves
        );
        assert_deep_plan_eq(plan, false, large_value, 0, true);
        
        // Large requirement with matching wrapper reserves
        let plan = wrapper::determine_deep_requirements_core(
            false,         // not whitelisted
            large_value,   // large deep required
            0,             // manager balance
            0,             // wallet balance
            large_value    // matching wrapper reserves
        );
        assert_deep_plan_eq(plan, true, 0, large_value, true);
    }
    
    // -------------------------------------
    // Test Category 6: Boundary Conditions
    // -------------------------------------
    
    #[test]
    fun test_exact_balance_boundaries() {
        // Test all combinations of exact required amounts
        let required = DEEP_MEDIUM;
        
        // Manager exactly matches required
        let plan = wrapper::determine_deep_requirements_core(
            false,       // not whitelisted
            required,    // deep required
            required,    // exact amount in manager
            0,           // nothing in wallet
            0            // no wrapper reserves
        );
        assert_deep_plan_eq(plan, false, 0, 0, true);
        
        // Wallet exactly matches required
        let plan = wrapper::determine_deep_requirements_core(
            false,       // not whitelisted
            required,    // deep required
            0,           // nothing in manager
            required,    // exact amount in wallet
            0            // no wrapper reserves
        );
        assert_deep_plan_eq(plan, false, required, 0, true);
        
        // Combined user balance equals exactly required
        let manager_amount = required / 2;
        let wallet_amount = required - manager_amount;
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            manager_amount,  // some in manager
            wallet_amount,   // rest in wallet
            0                // no wrapper reserves
        );
        assert_deep_plan_eq(plan, false, wallet_amount, 0, true);
        
        // Wrapper exactly matches what's needed
        let user_amount = required / 2;
        let wrapper_needed = required - user_amount;
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            0,               // nothing in manager
            user_amount,     // some in wallet
            wrapper_needed   // exact wrapper reserves needed
        );
        assert_deep_plan_eq(plan, true, user_amount, wrapper_needed, true);
    }
    
    #[test]
    fun test_one_token_boundaries() {
        // Tests with just one token difference
        let required = DEEP_MEDIUM;
        
        // Manager has one token less than required
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            required - 1,    // one token less in manager
            0,               // nothing in wallet
            0                // no wrapper reserves
        );
        assert_deep_plan_eq(plan, true, 0, 0, false);
        
        // One token in wallet completes the requirement
        let plan = wrapper::determine_deep_requirements_core(
            false,           // not whitelisted
            required,        // deep required
            required - 1,    // one token less in manager
            1,               // one token in wallet
            0                // no wrapper reserves
        );
        assert_deep_plan_eq(plan, false, 1, 0, true);
        
        // One token short with wrapper
        let user_amount = required / 2;
        let wrapper_needed = required - user_amount;
        let plan = wrapper::determine_deep_requirements_core(
            false,               // not whitelisted
            required,            // deep required
            0,                   // nothing in manager
            user_amount,         // some in wallet
            wrapper_needed - 1   // one token short in wrapper
        );
        assert_deep_plan_eq(plan, true, user_amount, 0, false);
        
        // One extra token in wrapper
        let plan = wrapper::determine_deep_requirements_core(
            false,               // not whitelisted
            required,            // deep required
            0,                   // nothing in manager
            user_amount,         // some in wallet
            wrapper_needed + 1   // one token extra in wrapper
        );
        assert_deep_plan_eq(plan, true, user_amount, wrapper_needed, true);
    }
} 