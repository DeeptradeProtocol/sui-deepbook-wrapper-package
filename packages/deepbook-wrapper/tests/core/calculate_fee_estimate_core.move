#[test_only]
module deepbook_wrapper::calculate_fee_estimate_core_tests {
    use sui::test_utils::assert_eq;
    
    use deepbook_wrapper::wrapper;
    
    // Test constants
    const PRICE: u64 = 2_000_000;
    const QUANTITY: u64 = 10_000_000_000;
    const FEE_BPS: u64 = 1_000_000; // 0.1% fee (1_000_000 / 1,000,000,000)
    
    // Test calculate_fee_estimate_core
    #[test]
    fun test_calculate_fee_estimate_core() {
        // Matrix-based testing approach for complete coverage

        // 1. No fee cases (returns 0)
        // ----------------------------
        
        // 1.1 Whitelisted pool, using wrapper DEEP (whitelisted takes precedence)
        let fee = wrapper::calculate_fee_estimate_core(
            true,  // whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            true,  // is_bid
            FEE_BPS
        );
        assert_eq(fee, 0);
        
        // 1.2 Whitelisted pool, not using wrapper DEEP
        let fee = wrapper::calculate_fee_estimate_core(
            true,  // whitelisted
            false, // not using wrapper DEEP
            QUANTITY,
            PRICE,
            true,  // is_bid
            FEE_BPS
        );
        assert_eq(fee, 0);
        
        // 1.3 Not whitelisted pool, but user provides all DEEP (not using wrapper)
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            false, // not using wrapper DEEP
            QUANTITY,
            PRICE,
            true,  // is_bid
            FEE_BPS
        );
        assert_eq(fee, 0);
        
        // 1.4 Zero fee basis points
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            true,  // is_bid
            0      // zero fee bps
        );
        assert_eq(fee, 0);
        
        // 2. Bid order with fee (returns fee on quote tokens)
        // --------------------------------------------------
        
        // 2.1 Standard bid order with fee
        // For bid order, fee = (quantity * price) * fee_bps / FEE_SCALING
        // Direct calculation: 10_000_000_000 * 2_000_000 / 1_000_000_000 * 1_000_000 / 1_000_000_000
        // = 20_000_000 * 0.001 = 20_000
        let expected_bid_fee = 20_000;
        
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            true,  // is_bid
            FEE_BPS
        );
        
        assert_eq(fee, expected_bid_fee);
        assert_eq(fee > 0, true); // Fee should be non-zero
        
        // 2.2 Minimal bid order (smallest possible quantity and price)
        let min_quantity = 1;
        let min_price = 1;
        
        // Direct calculation: 1 * 1 * 0.001 = 0.001, which rounds to 0 with integer math
        let expected_min_bid_fee = 0; 
        
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            min_quantity,
            min_price,
            true,  // is_bid
            FEE_BPS
        );
        
        assert_eq(fee, expected_min_bid_fee);
        
        // 2.3 High fee rate bid order
        let high_fee_bps = 100_000_000; // 10% fee (100,000,000 / 1,000,000,000)
        
        // Direct calculation: 10_000_000_000 * 2_000_000 / 1_000_000_000 * 0.1 = 20_000_000 * 0.1 = 2_000_000
        let expected_high_bid_fee = 2_000_000;
        
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            true,  // is_bid
            high_fee_bps
        );
        
        assert_eq(fee, expected_high_bid_fee);
        assert_eq(fee > expected_bid_fee, true); // Should be higher than standard fee
        
        // 3. Ask order with fee (returns fee on base tokens)
        // --------------------------------------------------
        
        // 3.1 Standard ask order with fee
        // For ask order, fee = quantity * fee_bps / FEE_SCALING
        // Direct calculation: 10_000_000_000 * 0.001 = 10_000_000
        let expected_ask_fee = 10_000_000;
        
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            false, // is_ask
            FEE_BPS
        );
        
        assert_eq(fee, expected_ask_fee);
        assert_eq(fee > 0, true); // Fee should be non-zero
        
        // 3.2 Minimal ask order (smallest possible quantity)
        let min_quantity = 1;
        
        // Direct calculation: 1 * 0.001 = 0.001, which rounds to 0 with integer math
        let expected_min_ask_fee = 0; 
        
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            min_quantity,
            PRICE, // Price doesn't matter for ask order amount
            false, // is_ask
            FEE_BPS
        );
        
        assert_eq(fee, expected_min_ask_fee);
        
        // 3.3 High fee rate ask order
        let high_fee_bps = 100_000_000; // 10% fee
        
        // Direct calculation: 10_000_000_000 * 0.1 = 1_000_000_000
        let expected_high_ask_fee = 1_000_000_000;
        
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            false, // is_ask
            high_fee_bps
        );
        
        assert_eq(fee, expected_high_ask_fee);
        
        // 4. Comparative tests
        // --------------------
        
        // 4.1 Bid vs Ask fee comparison
        // For same quantity and price, bid fee should be higher than ask fee
        // since bid fee is on quote tokens (quantity * price) and ask fee is on base tokens (quantity)
        let bid_fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            true,  // is_bid
            FEE_BPS
        );
        
        let ask_fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            false, // is_ask
            FEE_BPS
        );
        
        // Verify expected relationship: bid_fee < ask_fee for these specific values
        // This is because bid_fee is 20_000 (as calculated above)
        // and ask_fee is 10_000_000 (as calculated above)
        assert_eq(bid_fee < ask_fee, true);
        
        // 5. Edge cases and boundary values
        // ---------------------------------
        
        // 5.1 Very large values (check for overflow safety)
        let large_quantity = 10000000000; // 10^10
        let large_price = 1000000; // 10^6
        
        // Direct calculation: 10^10 * 10^6 / 10^9 * 10^6 / 10^9 = 10^7 * 10^-3 = 10^4 = 10,000
        let expected_large_fee = 10000;
        
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            large_quantity,
            large_price,
            true,  // is_bid
            FEE_BPS
        );
        
        // Verify calculated fee matches expected value and doesn't overflow
        assert_eq(fee, expected_large_fee);
        
        // 5.2 Maximum fee rate
        let max_fee_bps = 1_000_000_000; // 100% fee (1,000,000,000 / 1,000,000,000)
        
        // For 100% fee on bid order:
        // quantity * price / FEE_SCALING * FEE_SCALING / FEE_SCALING = quantity * price / FEE_SCALING
        // 10_000_000_000 * 2_000_000 / 1_000_000_000 = 20_000_000
        let expected_max_fee = 20_000_000;
        
        let fee = wrapper::calculate_fee_estimate_core(
            false, // not whitelisted
            true,  // using wrapper DEEP
            QUANTITY,
            PRICE,
            true,  // is_bid
            max_fee_bps
        );
        
        assert_eq(fee, expected_max_fee);
    }
} 