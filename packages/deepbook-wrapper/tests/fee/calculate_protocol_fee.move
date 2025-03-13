#[test_only]
module deepbook_wrapper::calculate_protocol_fee_tests {
    use deepbook_wrapper::fee::calculate_protocol_fee;

    const SUI_PER_DEEP: u64 = 37_815_000_000;

    #[test]
    /// Test when deep_from_reserves is zero, result should be zero
    fun test_zero_values() {
        let fee = calculate_protocol_fee(SUI_PER_DEEP, 0);
        assert!(fee == 0, 0);
    }
    
    #[test]
    /// Test with minimum non-zero DEEP amount
    fun test_minimum_deep() {
        let fee = calculate_protocol_fee(SUI_PER_DEEP, 1);
        // Step 1: 1 * 10_000_000 = 10_000_000
        // After first scaling: 10_000_000 / 1_000_000_000 = 0 DEEP (rounds down!)
        // Step 2: 0 * 37_815_000_000 = 0
        // After second scaling: 0 / 1_000_000_000 = 0 SUI
        assert!(fee == 0, 0); // Will be 0 due to integer division in first scaling
    }
    
    #[test]
    /// Test with standard DEEP amounts
    fun test_standard_amounts() {
        // Test with 1000 DEEP
        let fee_1k = calculate_protocol_fee(SUI_PER_DEEP, 1_000);
        // Step 1: 1_000 * 10_000_000 = 10_000_000_000
        // After first scaling: 10_000_000_000 / 1_000_000_000 = 10 DEEP
        // Step 2: 10 * 37_815_000_000 = 378_150_000_000
        // After second scaling: 378_150_000_000 / 1_000_000_000 = 378 SUI
        assert!(fee_1k == 378, 0);
        
        // Test with 10000 DEEP
        let fee_10k = calculate_protocol_fee(SUI_PER_DEEP, 10_000);
        // Step 1: 10_000 * 10_000_000 = 100_000_000_000
        // After first scaling: 100_000_000_000 / 1_000_000_000 = 100 DEEP
        // Step 2: 100 * 37_815_000_000 = 3_781_500_000_000
        // After second scaling: 3_781_500_000_000 / 1_000_000_000 = 3_781 SUI
        assert!(fee_10k == 3_781, 1);
        
        // Note: Not exactly linear due to rounding at each scaling step
        // fee_10k (3_781) ≠ fee_1k * 10 (3_780)
    }
    
    #[test]
    /// Test with large DEEP amounts to verify no overflow
    fun test_large_values() {
        // Test with 1 million DEEP
        let fee = calculate_protocol_fee(SUI_PER_DEEP, 1_000_000);
        // Step 1: 1_000_000 * 10_000_000 = 10_000_000_000_000
        // After first scaling: 10_000_000_000_000 / 1_000_000_000 = 10_000 DEEP
        // Step 2: 10_000 * 37_815_000_000 = 378_150_000_000_000
        // After second scaling: 378_150_000_000_000 / 1_000_000_000 = 378_150 SUI
        assert!(fee == 378_150, 0);
        
        // Test with maximum safe DEEP amount
        let max_safe_deep = 1_000_000_000; // 1 billion DEEP
        let fee_max = calculate_protocol_fee(SUI_PER_DEEP, max_safe_deep);
        // Step 1: 1_000_000_000 * 10_000_000 = 10_000_000_000_000_000
        // After first scaling: 10_000_000_000_000_000 / 1_000_000_000 = 10_000_000 DEEP
        // Step 2: 10_000_000 * 37_815_000_000 = 378_150_000_000_000_000
        // After second scaling: 378_150_000_000_000_000 / 1_000_000_000 = 378_150_000 SUI
        assert!(fee_max > 0, 1); // Should not overflow
        assert!(fee_max == 378_150_000, 2);
    }
    
    #[test]
    /// Test fee calculation precision and rounding
    fun test_fee_precision() {
        // Test with amounts that could cause rounding issues
        let deep_amount = 333;
        let fee = calculate_protocol_fee(SUI_PER_DEEP, deep_amount);
        
        // Correct calculation with integer arithmetic:
        // Step 1: deep_amount * PROTOCOL_FEE_BPS = 333 * 10_000_000 = 3_330_000_000
        // After first scaling: 3_330_000_000 / 1_000_000_000 = 3 DEEP
        // Step 2: 3 * 37_815_000_000 = 113_445_000_000
        // After second scaling: 113_445_000_000 / 1_000_000_000 = 113 SUI
        assert!(fee == 113, 0);
    }
    
    #[test]
    /// Test fee scaling is linear with DEEP amount
    fun test_fee_scaling() {
        let base_deep = 1_000;
        let base_fee = calculate_protocol_fee(SUI_PER_DEEP, base_deep);
        
        // Test 2x, 3x, 4x scaling
        let fee_2x = calculate_protocol_fee(SUI_PER_DEEP, base_deep * 2);
        let fee_3x = calculate_protocol_fee(SUI_PER_DEEP, base_deep * 3);
        let fee_4x = calculate_protocol_fee(SUI_PER_DEEP, base_deep * 4);
        
        // Verify linear scaling
        assert!(fee_2x == base_fee * 2, 0);
        assert!(fee_3x == base_fee * 3, 1);
        assert!(fee_4x == base_fee * 4, 2);
    }
    
    #[test]
    /// Test with different SUI/DEEP prices
    fun test_different_sui_deep_prices() {
        let deep_amount = 1_000;
        
        // Test with half the standard price
        let fee_half_price = calculate_protocol_fee(SUI_PER_DEEP / 2, deep_amount);
        
        // Test with double the standard price
        let fee_double_price = calculate_protocol_fee(SUI_PER_DEEP * 2, deep_amount);
        
        // Verify fee scales with price
        let standard_fee = calculate_protocol_fee(SUI_PER_DEEP, deep_amount);
        assert!(fee_half_price == standard_fee / 2, 0);
        assert!(fee_double_price == standard_fee * 2, 1);
    }
} 