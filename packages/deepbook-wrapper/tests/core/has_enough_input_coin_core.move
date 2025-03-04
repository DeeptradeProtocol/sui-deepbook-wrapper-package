#[test_only]
module deepbook_wrapper::has_enough_input_coin_core_tests {
    use sui::test_utils::assert_eq;
    
    use deepbook_wrapper::wrapper;
    
    // Test has_enough_input_coin_core
    #[test]
    fun test_has_enough_input_coin_core() {
        // Matrix-based testing approach for complete coverage

        // 1. Bid order cases (checking quote coins)
        // ----------------------------------------
        
        // 1.1 Exactly enough quote coins in wallet, no fees
        // price = 100_000_000_000 (100 * 10^9)
        // quantity = 10
        // required = (10 * 100_000_000_000) / 10^9 = 1000
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base (not used for bid)
            0,                  // balance_manager_quote
            0,                  // base_in_wallet (not used for bid)
            1000,              // quote_in_wallet
            10,                // quantity
            100_000_000_000,   // price (scaled by 10^9)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            true               // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 1.2 More than enough quote coins in wallet, no fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            0,                  // base_in_wallet
            2000,              // quote_in_wallet
            10,                // quantity
            100_000_000_000,   // price (scaled by 10^9)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            true               // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 1.3 Not enough quote coins in wallet, no fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            0,                  // base_in_wallet
            500,               // quote_in_wallet (need 1000)
            10,                // quantity
            100_000_000_000,   // price (scaled by 10^9)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            true               // is_bid
        );
        assert_eq(has_sufficient, false);
        
        // 1.4 Exactly enough quote coins split between wallet and balance manager
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            500,               // balance_manager_quote
            0,                  // base_in_wallet
            500,               // quote_in_wallet
            10,                // quantity
            100_000_000_000,   // price (scaled by 10^9)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            true               // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 1.5 Exactly enough including fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            0,                  // base_in_wallet
            1100,              // quote_in_wallet
            10,                // quantity
            100_000_000_000,   // price (scaled by 10^9)
            true,              // will_use_wrapper_deep
            100,               // fee_estimate
            true               // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 1.6 Not enough when including fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            0,                  // base_in_wallet
            1000,              // quote_in_wallet
            10,                // quantity
            100_000_000_000,   // price (scaled by 10^9)
            true,              // will_use_wrapper_deep
            100,               // fee_estimate
            true               // is_bid
        );
        assert_eq(has_sufficient, false);

        // 2. Ask order cases (checking base coins)
        // ----------------------------------------
        
        // 2.1 Exactly enough base coins in wallet, no fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            100,               // base_in_wallet
            0,                  // quote_in_wallet (not used for ask)
            100,               // quantity
            10_000_000_000,    // price (scaled by 10^9, not used for base calculation)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            false              // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 2.2 More than enough base coins in wallet, no fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            200,               // base_in_wallet
            0,                  // quote_in_wallet
            100,               // quantity
            10_000_000_000,    // price (not used for base calculation)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            false              // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 2.3 Not enough base coins in wallet, no fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            50,                // base_in_wallet
            0,                  // quote_in_wallet
            100,               // quantity
            10_000_000_000,    // price (not used for base calculation)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            false              // is_bid
        );
        assert_eq(has_sufficient, false);
        
        // 2.4 Exactly enough base coins split between wallet and balance manager
        let has_sufficient = wrapper::has_enough_input_coin_core(
            50,                // balance_manager_base
            0,                  // balance_manager_quote
            50,                // base_in_wallet
            0,                  // quote_in_wallet
            100,               // quantity
            10_000_000_000,    // price (not used for base calculation)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            false              // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 2.5 Exactly enough including fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            110,               // base_in_wallet
            0,                  // quote_in_wallet
            100,               // quantity (100 + 10 fee = 110 needed)
            10_000_000_000,    // price (not used for base calculation)
            true,              // will_use_wrapper_deep
            10,                // fee_estimate
            false              // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 2.6 Not enough when including fees
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            100,               // base_in_wallet
            0,                  // quote_in_wallet
            100,               // quantity (100 + 10 fee = 110 needed)
            10_000_000_000,    // price (not used for base calculation)
            true,              // will_use_wrapper_deep
            10,                // fee_estimate
            false              // is_bid
        );
        assert_eq(has_sufficient, false);

        // 3. Special cases
        // ---------------
        
        // 3.1 Zero quantity bid
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            0,                  // base_in_wallet
            0,                  // quote_in_wallet
            0,                  // quantity
            100_000_000_000,   // price (scaled by 10^9)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            true               // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 3.2 Zero quantity ask
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            0,                  // base_in_wallet
            0,                  // quote_in_wallet
            0,                  // quantity
            100_000_000_000,   // price (scaled by 10^9)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            false              // is_bid
        );
        assert_eq(has_sufficient, true);
        
        // 3.3 Very large values within u64 range (check for overflow safety)
        let large_value = 10_000_000_000; // 10^10, below max u64 when multiplied by price scaling
        let has_sufficient = wrapper::has_enough_input_coin_core(
            0,                  // balance_manager_base
            0,                  // balance_manager_quote
            large_value,        // base_in_wallet
            0,                  // quote_in_wallet
            large_value,        // quantity
            1_000_000_000,     // price (1 * 10^9)
            false,             // will_use_wrapper_deep
            0,                 // fee_estimate
            false              // is_bid
        );
        assert_eq(has_sufficient, true);
    }
}