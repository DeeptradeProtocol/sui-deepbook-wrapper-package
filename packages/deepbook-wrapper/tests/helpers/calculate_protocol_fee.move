#[test_only]
module deepbook_wrapper::calculate_protocol_fee_tests {
    use deepbook_wrapper::wrapper::{Self};

    #[test]
    /// Test when deep_from_reserves or total_deep_required is zero, result should be zero
    fun test_zero_values() {
        // When total_deep_required is zero, result should be zero
        let fee = wrapper::calculate_protocol_fee(1000, 500, 0);
        assert!(fee == 0, 0);
        
        // When deep_from_reserves is zero, result should be zero
        let fee = wrapper::calculate_protocol_fee(1000, 0, 500);
        assert!(fee == 0, 0);
        
        // When amount is zero, result should be zero
        let fee = wrapper::calculate_protocol_fee(0, 500, 1000);
        assert!(fee == 0, 0);
        
        // All zeros should return zero
        let fee = wrapper::calculate_protocol_fee(0, 0, 0);
        assert!(fee == 0, 0);
    }
    
    #[test]
    /// Test when all DEEP is taken from reserves (100%)
    fun test_full_deep_from_reserves() {
        let amount = 1000000;
        let deep_required = 5000;
        
        // Using all from reserves (5000/5000 = 100%)
        let fee = wrapper::calculate_protocol_fee(amount, deep_required, deep_required);
        
        // Expected fee: amount * MAX_PROTOCOL_FEE_BPS / FEE_SCALING = 1000000 * 3000000 / 1000000000 = 3000
        assert!(fee == 3000, 0); // 0.3% of 1000000
    }
    
    #[test]
    /// Test when partial DEEP is taken from reserves (different percentages)
    fun test_partial_deep_from_reserves() {
        let amount = 1000000;
        let total_deep = 10000;
        
        // Using 50% from reserves (5000/10000)
        let fee_50_percent = wrapper::calculate_protocol_fee(amount, 5000, total_deep);
        // Expected: 1000000 * (5000/10000 * 3000000) / 1000000000 = 1500
        assert!(fee_50_percent == 1500, 0); // 0.15% of 1000000
        
        // Using 25% from reserves (2500/10000)
        let fee_25_percent = wrapper::calculate_protocol_fee(amount, 2500, total_deep);
        // Expected: 1000000 * (2500/10000 * 3000000) / 1000000000 = 750
        assert!(fee_25_percent == 750, 0); // 0.075% of 1000000
        
        // Using 75% from reserves (7500/10000)
        let fee_75_percent = wrapper::calculate_protocol_fee(amount, 7500, total_deep);
        // Expected: 1000000 * (7500/10000 * 3000000) / 1000000000 = 2250
        assert!(fee_75_percent == 2250, 0); // 0.225% of 1000000
        
        // Using 10% from reserves (1000/10000)
        let fee_10_percent = wrapper::calculate_protocol_fee(amount, 1000, total_deep);
        // Expected: 1000000 * (1000/10000 * 3000000) / 1000000000 = 300
        assert!(fee_10_percent == 300, 0); // 0.03% of 1000000
    }
    
    #[test]
    /// Test with small proportions of DEEP from reserves
    fun test_small_proportions() {
        // Test with small proportions and amounts
        let small_deep_from_reserves = 1;
        let large_deep_required = 10000;
        let amount = 1000000;
        
        // 1/10000 = 0.01% of reserves used
        let fee = wrapper::calculate_protocol_fee(amount, small_deep_from_reserves, large_deep_required);
        // Expected: 1000000 * (1/10000 * 3000000) / 1000000000 = 0.3
        // Due to integer division, this should round down to 0
        assert!(fee == 0, 0);
        
        // Now with a larger amount to make sure we get a non-zero result
        let large_amount = 10000000000;
        let fee_large = wrapper::calculate_protocol_fee(large_amount, small_deep_from_reserves, large_deep_required);
        // Expected: 10000000000 * (1/10000 * 3000000) / 1000000000 = 3000
        assert!(fee_large == 3000, 0);
        
        // Very small ratio (1/100000)
        let fee_very_small = wrapper::calculate_protocol_fee(large_amount, 1, 100000);
        // Expected: 10000000000 * (1/100000 * 3000000) / 1000000000 = 300
        assert!(fee_very_small == 300, 0);
    }
    
    #[test]
    /// Test with various token amounts
    fun test_various_amounts() {
        let deep_from_reserves = 500;
        let total_deep_required = 1000;
        // 50% from reserves
        
        // Small amount
        let fee_small = wrapper::calculate_protocol_fee(100, deep_from_reserves, total_deep_required);
        // Expected: 100 * (500/1000 * 3000000) / 1000000000 = 0.15, rounds to 0
        assert!(fee_small == 0, 0);
        
        // Medium amount
        let fee_medium = wrapper::calculate_protocol_fee(10000, deep_from_reserves, total_deep_required);
        // Expected: 10000 * (500/1000 * 3000000) / 1000000000 = 15
        assert!(fee_medium == 15, 0);
        
        // Large amount
        let fee_large = wrapper::calculate_protocol_fee(1000000, deep_from_reserves, total_deep_required);
        // Expected: 1000000 * (500/1000 * 3000000) / 1000000000 = 1500
        assert!(fee_large == 1500, 0);
    }
    
    #[test]
    /// Test rounding behavior with integer division
    fun test_rounding() {
        let amount = 1001;
        let deep_from_reserves = 1;
        
        // With total_deep_required = 3, proportion = 1/3
        let fee1 = wrapper::calculate_protocol_fee(amount, deep_from_reserves, 3);
        // Expected: 1000 * (1/3 * 3000000) / 1000000000 ~= 1
        assert!(fee1 == 1, 0);
        
        // With total_deep_required = 4, proportion = 1/4
        let fee2 = wrapper::calculate_protocol_fee(amount, deep_from_reserves, 4);
        // Expected: 1000 * (1/4 * 3000000) / 1000000000 ~= 0.75, rounds to 0
        assert!(fee2 == 0, 0);
        
        // Use a larger amount to see the rounding effect more clearly
        let larger_amount = 4000;
        let fee3 = wrapper::calculate_protocol_fee(larger_amount, deep_from_reserves, 4);
        // Expected: 4000 * (1/4 * 3000000) / 1000000000 = 3
        assert!(fee3 == 3, 0);
    }
    
    #[test]
    /// Test with large values close to u64 max
    fun test_large_values() {
        // Using large but not maximum values to avoid overflow
        let large_amount = 18446744073709551000; // close to max u64
        let deep_from_reserves = 1000000;
        let total_deep = 10000000;
        
        // This should not overflow due to u128 casting in the function
        let fee = wrapper::calculate_protocol_fee(large_amount, deep_from_reserves, total_deep);
        
        // Expected: large_amount * (1000000/10000000 * 3000000) / 1000000000
        // = large_amount * 0.3 / 1000 = large_amount * 0.0003
        // = 18446744073709551000 * 0.0003 = 5534023222112865
        assert!(fee > 0, 0);
        
        // Specifically, it should be approximately 3% of large_amount / 10
        // Let's calculate the exact expected value
        let expected = 5534023222112865;
        assert!(fee == expected, 0);
    }
    
    #[test]
    /// Test with equal values for deep_from_reserves and total_deep_required
    fun test_equal_values() {
        // When deep_from_reserves = total_deep_required (100% from reserves)
        let amount = 100000;
        let deep = 5000;
        
        let fee = wrapper::calculate_protocol_fee(amount, deep, deep);
        // Expected: 100000 * (5000/5000 * 3000000) / 1000000000 = 100000 * 0.003 = 300
        assert!(fee == 300, 0);
        
        // When deep_from_reserves = total_deep_required = amount (just a sanity check)
        let equal = 10000;
        let fee_equal = wrapper::calculate_protocol_fee(equal, equal, equal);
        // Expected: 10000 * (10000/10000 * 3000000) / 1000000000 = 10000 * 0.003 = 30
        assert!(fee_equal == 30, 0);
    }
    
    #[test]
    /// Test gradual fee increases with increasing proportion
    fun test_fee_scaling() {
        let amount = 1000000;
        let total_deep = 1000;
        
        // Test fee at 10% increments to verify linear scaling
        let fee_10 = wrapper::calculate_protocol_fee(amount, 100, total_deep);  // 10%
        let fee_20 = wrapper::calculate_protocol_fee(amount, 200, total_deep);  // 20%
        let fee_30 = wrapper::calculate_protocol_fee(amount, 300, total_deep);  // 30%
        let fee_40 = wrapper::calculate_protocol_fee(amount, 400, total_deep);  // 40%
        let fee_50 = wrapper::calculate_protocol_fee(amount, 500, total_deep);  // 50%
        let fee_60 = wrapper::calculate_protocol_fee(amount, 600, total_deep);  // 60%
        let fee_70 = wrapper::calculate_protocol_fee(amount, 700, total_deep);  // 70%
        let fee_80 = wrapper::calculate_protocol_fee(amount, 800, total_deep);  // 80%
        let fee_90 = wrapper::calculate_protocol_fee(amount, 900, total_deep);  // 90%
        let fee_100 = wrapper::calculate_protocol_fee(amount, 1000, total_deep); // 100%
        
        // Verify fee increases linearly with proportion
        assert!(fee_10 == 300, 0);   // 0.03% of 1000000
        assert!(fee_20 == 600, 0);   // 0.06% of 1000000
        assert!(fee_30 == 900, 0);   // 0.09% of 1000000
        assert!(fee_40 == 1200, 0);  // 0.12% of 1000000
        assert!(fee_50 == 1500, 0);  // 0.15% of 1000000
        assert!(fee_60 == 1800, 0);  // 0.18% of 1000000
        assert!(fee_70 == 2100, 0);  // 0.21% of 1000000
        assert!(fee_80 == 2400, 0);  // 0.24% of 1000000
        assert!(fee_90 == 2700, 0);  // 0.27% of 1000000
        assert!(fee_100 == 3000, 0); // 0.30% of 1000000
    }
    
    #[test]
    /// Verify max fee does not exceed MAX_PROTOCOL_FEE_BPS
    fun test_max_fee_limit() {
        let amount = 1000000;
        let deep = 1000;
        
        // 100% from reserves should apply maximum fee
        let max_fee = wrapper::calculate_protocol_fee(amount, deep, deep);
        
        // Manual calculation: 1000000 * 3000000 / 1000000000 = 3000
        let expected_max_fee = 3000; // 0.3% of 1000000
        
        assert!(max_fee == expected_max_fee, 0);
    }
    
    #[test]
    #[expected_failure]
    /// Test that an error is thrown when deep_from_reserves exceeds total_deep_required
    fun test_deep_reserves_exceeds_total() {
        let amount = 1000000;
        let total_deep_required = 1000;
        let deep_from_reserves = 1001; // Exceeds total_deep_required
        
        // This should abort with EInvalidDeepReservesAmount
        wrapper::calculate_protocol_fee(amount, deep_from_reserves, total_deep_required);
    }
} 