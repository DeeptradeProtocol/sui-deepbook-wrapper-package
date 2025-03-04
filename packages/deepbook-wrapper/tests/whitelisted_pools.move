#[test_only]
module deepbook_wrapper::test_whitelisted_pools {
    use deepbook_wrapper::whitelisted_pools::{Self, WhitelistRegistry};
    use deepbook_wrapper::admin;
    use sui::test_scenario::{Self as ts, Scenario};

    // Known whitelisted pool IDs
    const DEEP_SUI_POOL_ID: vector<u8> = x"b663828d6217467c8a1838a03793da896cbe745b150ebd57d82f814ca579fc22";
    const DEEP_USDC_POOL_ID: vector<u8> = x"f948981b806057580f91622417534f491da5f61aeaf33d0ed8e69fd5691c95ce";
    const SUI_USDC_POOL_ID: vector<u8> = x"e05dafb5133bcffb8d59f4e12465dc0e9faeaa05e3e342a08fe135800e3e4407";
    
    // Some non-whitelisted pool ID for testing
    const NON_WHITELISTED_POOL_ID_1: vector<u8> = x"1111111111111111111111111111111111111111111111111111111111111111";
    const NON_WHITELISTED_POOL_ID_2: vector<u8> = x"2222222222222222222222222222222222222222222222222222222222222222";

    // Test admin address
    const ADMIN: address = @0xA11CE;

    // Setup a test with a whitelist registry populated with test IDs
    fun setup_test(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let ctx = ts::ctx(scenario);
            
            // Create whitelist registry for testing
            let mut registry = whitelisted_pools::create_for_testing(ctx);
            
            // Add some test pool IDs to the whitelist
            whitelisted_pools::add_pool_for_testing(
                &mut registry,
                object::id_from_bytes(DEEP_SUI_POOL_ID)
            );
            
            whitelisted_pools::add_pool_for_testing(
                &mut registry,
                object::id_from_bytes(DEEP_USDC_POOL_ID)
            );
            
            whitelisted_pools::add_pool_for_testing(
                &mut registry,
                object::id_from_bytes(SUI_USDC_POOL_ID)
            );
            
            whitelisted_pools::share_for_testing(registry);
        };
    }

    // Test that whitelisted pool IDs are correctly identified
    #[test]
    fun test_whitelisted_ids_are_identified() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = ts::take_shared<WhitelistRegistry>(&scenario);
            
            // Create pool IDs from the known whitelisted IDs
            let deep_sui_id = object::id_from_bytes(DEEP_SUI_POOL_ID);
            let deep_usdc_id = object::id_from_bytes(DEEP_USDC_POOL_ID);
            let sui_usdc_id = object::id_from_bytes(SUI_USDC_POOL_ID);
            
            // Check that these IDs are identified as whitelisted
            assert!(whitelisted_pools::is_id_whitelisted(&registry, &deep_sui_id), 0);
            assert!(whitelisted_pools::is_id_whitelisted(&registry, &deep_usdc_id), 1);
            assert!(whitelisted_pools::is_id_whitelisted(&registry, &sui_usdc_id), 2);
            
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
    
    // Test that non-whitelisted pool IDs are correctly rejected
    #[test]
    fun test_non_whitelisted_ids_are_rejected() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = ts::take_shared<WhitelistRegistry>(&scenario);
            
            // Create pool IDs that aren't in the whitelist
            let non_whitelisted_id_1 = object::id_from_bytes(NON_WHITELISTED_POOL_ID_1);
            let non_whitelisted_id_2 = object::id_from_bytes(NON_WHITELISTED_POOL_ID_2);
            
            // Check that these IDs are identified as NOT whitelisted
            assert!(!whitelisted_pools::is_id_whitelisted(&registry, &non_whitelisted_id_1), 3);
            assert!(!whitelisted_pools::is_id_whitelisted(&registry, &non_whitelisted_id_2), 4);
            
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
    
    // Test admin capabilities to add and remove pools
    #[test]
    fun test_admin_capabilities() {
        let mut scenario = ts::begin(ADMIN);
        
        // Create a clean registry and admin cap
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            let registry = whitelisted_pools::create_for_testing(ctx);
            let admin_cap = admin::create_for_testing(ctx);
            
            whitelisted_pools::share_for_testing(registry);
            admin::transfer_for_testing(admin_cap, ADMIN);
        };
        
        // Admin adds a pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = ts::take_shared<WhitelistRegistry>(&scenario);
            let admin_cap = ts::take_from_address<admin::AdminCap>(&scenario, ADMIN);
            let new_pool_id = object::id_from_bytes(DEEP_SUI_POOL_ID);
            
            // Add a pool using admin capabilities
            whitelisted_pools::add_pool_to_whitelist(&admin_cap, &mut registry, new_pool_id);
            
            // Verify it was added
            assert!(whitelisted_pools::is_id_whitelisted(&registry, &new_pool_id), 5);
            
            ts::return_shared(registry);
            ts::return_to_address(ADMIN, admin_cap);
        };
        
        // Admin removes a pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = ts::take_shared<WhitelistRegistry>(&scenario);
            let admin_cap = ts::take_from_address<admin::AdminCap>(&scenario, ADMIN);
            let pool_id = object::id_from_bytes(DEEP_SUI_POOL_ID);
            
            // Remove the pool using admin capabilities
            whitelisted_pools::remove_pool_from_whitelist(&admin_cap, &mut registry, pool_id);
            
            // Verify it was removed
            assert!(!whitelisted_pools::is_id_whitelisted(&registry, &pool_id), 6);
            
            ts::return_shared(registry);
            ts::return_to_address(ADMIN, admin_cap);
        };
        
        ts::end(scenario);
    }
}
