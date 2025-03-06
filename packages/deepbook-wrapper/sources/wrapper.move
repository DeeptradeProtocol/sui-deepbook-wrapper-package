module deepbook_wrapper::wrapper {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::bag::{Self, Bag};
    use token::deep::DEEP;
    use deepbook_wrapper::admin::AdminCap;

    // === Structs ===
    /// Main router wrapper struct for DeepBook V3
    public struct DeepBookV3RouterWrapper has store, key {
        id: UID,
        deep_reserves: Balance<DEEP>,
        charged_fees: Bag,
    }
    
    /// Capability for managing funds in the router
    public struct DeepBookV3FundCap has store, key {
        id: UID,
        wrapper_id: ID,
    }

    /// Key struct for storing charged fees by coin type
    public struct ChargedFeeKey<phantom CoinType> has copy, drop, store {
        dummy_field: bool,
    }

    // === Errors ===
    /// Error when trying to use a fund capability with a different wrapper than it was created for
    #[error]
    const EInvalidFundCap: u64 = 1;
    
    // === Public-Mutative Functions ===
    /// Create a new fund capability for the router
    public fun create_fund_cap(
        _admin: &AdminCap,
        wrapper: &DeepBookV3RouterWrapper,
        ctx: &mut TxContext
    ): DeepBookV3FundCap {
        DeepBookV3FundCap {
            id: object::new(ctx),
            wrapper_id: object::uid_to_inner(&wrapper.id),
        }
    }

    /// Join DEEP coins into the router's reserves
    public fun join(wrapper: &mut DeepBookV3RouterWrapper, deep_coin: Coin<DEEP>) {
        balance::join(&mut wrapper.deep_reserves, coin::into_balance(deep_coin));
    }

    /// Withdraw collected fees for a specific coin type
    public fun withdraw_charged_fee<CoinType>(
        fund_cap: &DeepBookV3FundCap,
        wrapper: &mut DeepBookV3RouterWrapper,
        ctx: &mut TxContext
    ): Coin<CoinType> {
        assert!(fund_cap.wrapper_id == object::uid_to_inner(&wrapper.id), EInvalidFundCap);
        
        let key = ChargedFeeKey<CoinType> { dummy_field: false };
        if (bag::contains(&wrapper.charged_fees, key)) {
            coin::from_balance(
                balance::withdraw_all(
                    bag::borrow_mut(&mut wrapper.charged_fees, key)
                ),
                ctx
            )
        } else {
            coin::zero(ctx)
        }
    }

    // === Public-View Functions ===
    /// Get the value of DEEP in the reserves
    public fun get_deep_reserves_value(wrapper: &DeepBookV3RouterWrapper): u64 {
        balance::value(&wrapper.deep_reserves)
    }

    // === Public-Package Functions ===
    /// Add collected fees to the wrapper's fee storage
    public(package) fun join_fee<CoinType>(wrapper: &mut DeepBookV3RouterWrapper, fee: Balance<CoinType>) {
        if (balance::value(&fee) == 0) {
            balance::destroy_zero(fee);
            return
        };
        
        let key = ChargedFeeKey<CoinType> { dummy_field: false };
        if (bag::contains(&wrapper.charged_fees, key)) {
            balance::join(
                bag::borrow_mut(&mut wrapper.charged_fees, key),
                fee
            );
        } else {
            bag::add(&mut wrapper.charged_fees, key, fee);
        };
    }

    /// Get the splitted DEEP coin from the reserves
    public(package) fun split_deep_reserves(
      wrapper: &mut DeepBookV3RouterWrapper,
      amount: u64,
      ctx: &mut TxContext
    ): Coin<DEEP> {
        coin::from_balance(
            balance::split(&mut wrapper.deep_reserves, amount),
            ctx
        )
    }
    
    // === Private Functions ===
    /// Initialize the wrapper module
    fun init(ctx: &mut TxContext) {
        let wrapper = DeepBookV3RouterWrapper {
            id: object::new(ctx),
            deep_reserves: balance::zero(),
            charged_fees: bag::new(ctx),
        };

        // Create a fund capability for the deployer
        let fund_cap = DeepBookV3FundCap {
            id: object::new(ctx),
            wrapper_id: object::uid_to_inner(&wrapper.id),
        };

        // Share the wrapper object
        transfer::share_object(wrapper);

        // Transfer the fund capability to the transaction sender
        transfer::transfer(fund_cap, tx_context::sender(ctx));
    }
}