#[test_only]
module deepbook_wrapper::will_use_wrapper_deep_reserves_core_tests {
    use sui::test_utils::assert_eq;
    
    use deepbook_wrapper::wrapper;
    
    // Test will_use_wrapper_deep_reserves_core
    #[test]
    fun test_will_use_wrapper_deep_reserves_core() {
        // Matrix-based testing approach for complete coverage

        // 1. Pool is whitelisted cases (always returns false, true)
        // ---------------------------------------------------
        
        // 1.1 Whitelisted pool, user has 0 DEEP
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            0,     // wrapper reserves
            true,  // whitelisted
            0,     // balance manager DEEP
            0,     // wallet DEEP
            100    // required DEEP (doesn't matter since whitelisted)
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
        
        // 1.2 Whitelisted pool, wrapper has plenty, user has nothing (still doesn't matter)
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            1000,  // wrapper reserves
            true,  // whitelisted
            0,     // balance manager DEEP
            0,     // wallet DEEP
            500    // required DEEP (doesn't matter since whitelisted)
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
                
        // 2. User has enough DEEP cases (returns false, true)
        // --------------------------------------------------
        
        // 2.1 User has exactly required DEEP in wallet only
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            1000,  // wrapper reserves
            false, // not whitelisted
            0,     // balance manager DEEP
            100,   // wallet DEEP
            100    // required DEEP - exactly what user has
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
        
        // 2.2 User has more than required DEEP in wallet
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            1000,  // wrapper reserves
            false, // not whitelisted
            0,     // balance manager DEEP
            200,   // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
        
        // 2.3 User has exactly required DEEP in balance manager only
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            1000,  // wrapper reserves
            false, // not whitelisted
            100,   // balance manager DEEP
            0,     // wallet DEEP
            100    // required DEEP - exactly what user has
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
        
        // 2.4 User has more than required DEEP in balance manager
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            1000,  // wrapper reserves
            false, // not whitelisted
            200,   // balance manager DEEP
            0,     // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
        
        // 2.5 User has exactly required DEEP combined from both sources
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            1000,  // wrapper reserves
            false, // not whitelisted
            50,    // balance manager DEEP
            50,    // wallet DEEP
            100    // required DEEP - exactly what user has combined
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
        
        // 2.6 User has more than required DEEP combined from both sources
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            1000,  // wrapper reserves
            false, // not whitelisted
            75,    // balance manager DEEP
            75,    // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
        
        // 3. User doesn't have enough, but wrapper does (returns true, true)
        // -----------------------------------------------------------------
        
        // 3.1 User has none, wrapper has exactly what's needed
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            100,   // wrapper reserves - exactly what's needed
            false, // not whitelisted
            0,     // balance manager DEEP
            0,     // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, true);
        assert_eq(has_enough, true);
        
        // 3.2 User has some, wrapper has exactly what's additionally needed
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            50,    // wrapper reserves - exactly what's needed extra
            false, // not whitelisted
            25,    // balance manager DEEP
            25,    // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, true);
        assert_eq(has_enough, true);
        
        // 3.3 User has some, wrapper has more than needed
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            1000,  // wrapper reserves - more than needed
            false, // not whitelisted
            25,    // balance manager DEEP
            25,    // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, true);
        assert_eq(has_enough, true);
        
        // 4. Neither user nor wrapper has enough (returns true, false)
        // -----------------------------------------------------------
        
        // 4.1 User has none, wrapper has some but not enough
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            50,    // wrapper reserves - not enough
            false, // not whitelisted
            0,     // balance manager DEEP
            0,     // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, true);
        assert_eq(has_enough, false);
        
        // 4.2 User has some, wrapper has some, but combined not enough
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            25,    // wrapper reserves - not enough with user's balance
            false, // not whitelisted
            25,    // balance manager DEEP
            25,    // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, true);
        assert_eq(has_enough, false);
        
        // 4.3 User has none, wrapper has none
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            0,     // wrapper reserves - none
            false, // not whitelisted
            0,     // balance manager DEEP
            0,     // wallet DEEP
            100    // required DEEP
        );
        assert_eq(will_use, true);
        assert_eq(has_enough, false);
        
        // 5. Special value cases
        // ---------------------
        
        // 5.1 Zero DEEP required (non-whitelisted pool)
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            0,     // wrapper reserves
            false, // not whitelisted
            0,     // balance manager DEEP
            0,     // wallet DEEP
            0      // required DEEP - nothing needed
        );
        assert_eq(will_use, false);
        assert_eq(has_enough, true);
        
        // 5.2 Very large values within u64 range (check for overflow safety)
        let large_value = 10000000000000000000; // 10^19, below max u64
        let (will_use, has_enough) = wrapper::will_use_wrapper_deep_reserves_core(
            large_value, // wrapper reserves
            false,       // not whitelisted
            0,           // balance manager DEEP
            0,           // wallet DEEP
            large_value  // required DEEP
        );
        assert_eq(will_use, true);
        assert_eq(has_enough, true);
    }
} 