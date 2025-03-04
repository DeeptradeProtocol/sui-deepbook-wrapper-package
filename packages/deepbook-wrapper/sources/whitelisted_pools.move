module deepbook_wrapper::whitelisted_pools {
    use sui::table::{Self, Table};
    use deepbook::pool::Pool;
    use deepbook_wrapper::admin::AdminCap;

    /// Capability that stores the list of whitelisted pools
    public struct WhitelistRegistry has key {
        id: UID,
        pools: Table<ID, bool>
    }

    /// Error when a pool is already whitelisted
    #[error]
    const EPoolAlreadyWhitelisted: u64 = 1;

    /// Error when a pool is not in the whitelist
    #[error]
    const EPoolNotWhitelisted: u64 = 2;

    /// Initialize the whitelist registry
    fun init(ctx: &mut TxContext) {
        let registry = WhitelistRegistry {
            id: object::new(ctx),
            pools: table::new(ctx)
        };
        
        transfer::share_object(registry);
    }

    /// Add a pool to the whitelist, requires admin capability
    public entry fun add_pool_to_whitelist(
        _admin: &AdminCap,
        registry: &mut WhitelistRegistry,
        pool_id: ID
    ) {
        assert!(!table::contains(&registry.pools, pool_id), EPoolAlreadyWhitelisted);
        table::add(&mut registry.pools, pool_id, true);
    }

    /// Remove a pool from the whitelist, requires admin capability
    public entry fun remove_pool_from_whitelist(
        _admin: &AdminCap,
        registry: &mut WhitelistRegistry,
        pool_id: ID
    ) {
        assert!(table::contains(&registry.pools, pool_id), EPoolNotWhitelisted);
        table::remove(&mut registry.pools, pool_id);
    }

    /// Checks if a pool is whitelisted by our protocol
    public fun is_pool_whitelisted<BaseCoin, QuoteCoin>(
        registry: &WhitelistRegistry,
        pool: &Pool<BaseCoin, QuoteCoin>
    ): bool {
        let pool_id = object::id(pool);
        is_id_whitelisted(registry, &pool_id)
    }

    /// Checks if a pool ID is in the whitelist
    public fun is_id_whitelisted(
        registry: &WhitelistRegistry,
        pool_id: &ID
    ): bool {
        table::contains(&registry.pools, *pool_id)
    }

    #[test_only]
    /// Create a whitelist registry for testing
    public fun create_for_testing(ctx: &mut TxContext): WhitelistRegistry {
        WhitelistRegistry {
            id: object::new(ctx),
            pools: table::new(ctx)
        }
    }

    #[test_only]
    /// Add a pool to the test whitelist without admin cap check
    public fun add_pool_for_testing(
        registry: &mut WhitelistRegistry,
        pool_id: ID
    ) {
        if (!table::contains(&registry.pools, pool_id)) {
            table::add(&mut registry.pools, pool_id, true);
        }
    }

    #[test_only]
    /// Share the registry for testing
    public fun share_for_testing(registry: WhitelistRegistry) {
        transfer::share_object(registry);
    }
}