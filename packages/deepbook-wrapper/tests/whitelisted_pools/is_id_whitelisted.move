#[test_only]
module deepbook_wrapper::test_whitelisted_pools {
    use deepbook_wrapper::whitelisted_pools;

    // Known whitelisted pool IDs
    const DEEP_SUI_POOL_ID: vector<u8> = x"b663828d6217467c8a1838a03793da896cbe745b150ebd57d82f814ca579fc22";
    const DEEP_USDC_POOL_ID: vector<u8> = x"f948981b806057580f91622417534f491da5f61aeaf33d0ed8e69fd5691c95ce";
    const SUI_USDC_POOL_ID: vector<u8> = x"e05dafb5133bcffb8d59f4e12465dc0e9faeaa05e3e342a08fe135800e3e4407";
    
    // Some non-whitelisted pool ID for testing
    const NON_WHITELISTED_POOL_ID_1: vector<u8> = x"1111111111111111111111111111111111111111111111111111111111111111";
    const NON_WHITELISTED_POOL_ID_2: vector<u8> = x"2222222222222222222222222222222222222222222222222222222222222222";

    // Test that whitelisted pool IDs are correctly identified
    #[test]
    fun test_whitelisted_ids_are_identified() {
        // Create pool IDs from the known whitelisted IDs
        let deep_sui_id = object::id_from_bytes(DEEP_SUI_POOL_ID);
        let deep_usdc_id = object::id_from_bytes(DEEP_USDC_POOL_ID);
        let sui_usdc_id = object::id_from_bytes(SUI_USDC_POOL_ID);
        
        // Check that these IDs are identified as whitelisted
        assert!(whitelisted_pools::is_id_whitelisted(&deep_sui_id), 0);
        assert!(whitelisted_pools::is_id_whitelisted(&deep_usdc_id), 1);
        assert!(whitelisted_pools::is_id_whitelisted(&sui_usdc_id), 2);
    }
    
    // Test that non-whitelisted pool IDs are correctly rejected
    #[test]
    fun test_non_whitelisted_ids_are_rejected() {
        // Create pool IDs that aren't in the whitelist
        let non_whitelisted_id_1 = object::id_from_bytes(NON_WHITELISTED_POOL_ID_1);
        let non_whitelisted_id_2 = object::id_from_bytes(NON_WHITELISTED_POOL_ID_2);
        
        // Check that these IDs are identified as NOT whitelisted
        assert!(!whitelisted_pools::is_id_whitelisted(&non_whitelisted_id_1), 3);
        assert!(!whitelisted_pools::is_id_whitelisted(&non_whitelisted_id_2), 4);
    }
    
    // Test all whitelisted IDs are properly recognized
    #[test]
    fun test_all_whitelisted_ids() {
        // Check all whitelisted pool IDs
        let ids = vector[
            // DEEP/SUI
            x"b663828d6217467c8a1838a03793da896cbe745b150ebd57d82f814ca579fc22", 
            // DEEP/USDC
            x"f948981b806057580f91622417534f491da5f61aeaf33d0ed8e69fd5691c95ce", 
            // SUI/USDC
            x"e05dafb5133bcffb8d59f4e12465dc0e9faeaa05e3e342a08fe135800e3e4407", 
            // BETH/USDC
            x"1109352b9112717bd2a7c3eb9a416fff1ba6951760f5bdd5424cf5e4e5b3e65c", 
            // WUSDC/USDC
            x"a0b9ebefb38c963fd115f52d71fa64501b79d1adcb5270563f92ce0442376545", 
            // NS/SUI
            x"27c4fdb3b846aa3ae4a65ef5127a309aa3c1f466671471a806d8912a18b253e8", 
            // NS/USDC
            x"0c0fdd4008740d81a8a7d4281322aee71a1b62c449eb5b142656753d89ebc060", 
            // WUSDT/USDC
            x"4e2ca3988246e1d50b9bf209abb9c1cbfec65bd95afdacc620a36c67bdb8452f", 
            // TYPUS/SUI
            x"e8e56f377ab5a261449b92ac42c8ddaacd5671e9fec2179d7933dd1a91200eec", 
            // AUSD/USDC
            x"5661fc7f88fbeb8cb881150a810758cf13700bb4e1f31274a244581b37c303c3", 
            // SUI/AUSD
            x"183df694ebc852a5f90a959f0f563b82ac9691e42357e9a9fe961d71a1b809c8", 
            // DRF/SUI
            x"126865a0197d6ab44bfd15fd052da6db92fd2eb831ff9663451bbfa1219e2af2", 
            // GIGA/SUI
            x"2646dee5c4ad2d1ea9ce94a3c862dfd843a94753088c2507fea9223fd7e32a8f"
        ];
        
        let mut i = 0;
        let len = vector::length(&ids);
        
        while (i < len) {
            let id = object::id_from_bytes(*vector::borrow(&ids, i));
            assert!(whitelisted_pools::is_id_whitelisted(&id), 100 + i);
            i = i + 1;
        };
    }
    
    // Test edge cases with modified versions of valid IDs
    #[test]
    fun test_edge_cases() {
        // Take a valid ID and modify one byte to create a similar but invalid ID
        let modified_id = DEEP_SUI_POOL_ID;
        // Make sure to modify the ID to be different (flip the last byte)
        let last_index = vector::length(&modified_id) - 1;
        let last_byte = *vector::borrow(&modified_id, last_index);
        let new_byte = if (last_byte == 0) { 1 } else { last_byte - 1 };
        
        // Create a copy we can modify
        let mut modified_id_copy = vector::empty<u8>();
        let mut i = 0;
        while (i < vector::length(&modified_id)) {
            if (i == last_index) {
                vector::push_back(&mut modified_id_copy, new_byte);
            } else {
                vector::push_back(&mut modified_id_copy, *vector::borrow(&modified_id, i));
            };
            i = i + 1;
        };
        
        // This modified ID should not be whitelisted
        let id = object::id_from_bytes(modified_id_copy);
        assert!(!whitelisted_pools::is_id_whitelisted(&id), 5);
    }
}
