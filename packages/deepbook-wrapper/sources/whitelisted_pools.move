module deepbook_wrapper::whitelisted_pools {
    use deepbook::pool::Pool;

    /// Vector containing IDs of all whitelisted pools
    const WHITELISTED_POOL_IDS: vector<vector<u8>> = vector[
        x"b663828d6217467c8a1838a03793da896cbe745b150ebd57d82f814ca579fc22", // DEEP/SUI
        x"f948981b806057580f91622417534f491da5f61aeaf33d0ed8e69fd5691c95ce", // DEEP/USDC
        x"e05dafb5133bcffb8d59f4e12465dc0e9faeaa05e3e342a08fe135800e3e4407", // SUI/USDC
        x"1109352b9112717bd2a7c3eb9a416fff1ba6951760f5bdd5424cf5e4e5b3e65c", // BETH/USDC
        x"a0b9ebefb38c963fd115f52d71fa64501b79d1adcb5270563f92ce0442376545", // WUSDC/USDC
        x"27c4fdb3b846aa3ae4a65ef5127a309aa3c1f466671471a806d8912a18b253e8", // NS/SUI
        x"0c0fdd4008740d81a8a7d4281322aee71a1b62c449eb5b142656753d89ebc060", // NS/USDC
        x"4e2ca3988246e1d50b9bf209abb9c1cbfec65bd95afdacc620a36c67bdb8452f", // WUSDT/USDC
        x"e8e56f377ab5a261449b92ac42c8ddaacd5671e9fec2179d7933dd1a91200eec", // TYPUS/SUI
        x"5661fc7f88fbeb8cb881150a810758cf13700bb4e1f31274a244581b37c303c3", // AUSD/USDC
        x"183df694ebc852a5f90a959f0f563b82ac9691e42357e9a9fe961d71a1b809c8", // SUI/AUSD
        x"126865a0197d6ab44bfd15fd052da6db92fd2eb831ff9663451bbfa1219e2af2", // DRF/SUI
        x"2646dee5c4ad2d1ea9ce94a3c862dfd843a94753088c2507fea9223fd7e32a8f"  // GIGA/SUI
    ];

    /// Checks if a pool is whitelisted by our protocol
    public fun is_pool_whitelisted<BaseCoin, QuoteCoin>(pool: &Pool<BaseCoin, QuoteCoin>): bool {
        let pool_id = object::id(pool);
        is_id_whitelisted(&pool_id)
    }

    /// Checks if a pool ID is in the whitelist
    public(package) fun is_id_whitelisted(pool_id: &ID): bool {
        let id_bytes = object::id_to_bytes(pool_id);
        let mut i = 0;
        // Make an explicit copy of the constant
        let whitelisted_pools = WHITELISTED_POOL_IDS;
        let len = vector::length(&whitelisted_pools);
        
        while (i < len) {
            if (id_bytes == *vector::borrow(&whitelisted_pools, i)) {
                return true
            };
            i = i + 1;
        };
        
        false
    }
}