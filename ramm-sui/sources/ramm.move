module ramm_sui::ramm {
    use std::option::{Self, Option};

    use sui::bag::{Self, Bag};
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use std::type_name::{Self, TypeName};

    use switchboard::aggregator::{Self, Aggregator};

    use ramm_sui::math as ramm_math;

    friend ramm_sui::interface3;

    // Because of the below declarations, use the `test` flag when building or
    // creating test coverage maps: `sui move test coverage --test`.
    friend ramm_sui::interface3_tests;
    friend ramm_sui::ramm_tests;
    friend ramm_sui::test_utils;

    const THREE: u8 = 3;

    const ERAMMInvalidInitState: u64 = 0;
    const EInvalidAggregator: u64 = 1;
    const ENotAdmin: u64 = 2;
    const ENoAssetsInRAMM: u64 = 3;
    const ERAMMNewAssetFailure: u64 = 4;
    const ENotInitialized: u64 = 5;
    const EWrongNewAssetCap: u64 = 6;

    /// A "Liquidity Pool" token that will be used to mark the pool share
    /// of a liquidity provider.
    /// The parameter `Asset` is for the coin held in the pool.
    struct LP<phantom Asset> has drop, store {}

    /// Admin capability to circumvent restricted actions on the RAMM pool:
    /// * transfer RAMM protocol fees out of the pool,
    /// * enable/disable deposits for a certain asset
    /// * etc.
    struct RAMMAdminCap has key { id: UID }

    /// Capability to add assets to the RAMM pool. On its initialization,
    /// it must be deleted.
    struct RAMMNewAssetCap has key { id: UID }

    /// RAMM data structure, allows
    /// * adding/removing liquidity for one of its assets
    /// * trading of a token for another
    ///
    /// For any address to be able to submit requests, the structure must
    /// be shared, publicly available for reads and writes.
    /// As such, it must have the `key` ability, becoming a Sui
    /// Move object, and thus allowing use of `sui::transfer::share_object`.
    ///
    /// Some limitations:
    ///
    /// # Ownership of this structure
    ///
    /// In order for orders to be sent to the RAMM and affect its internal
    /// state, it must be shared, and thus cannot have an owner.
    /// Some operations e.g. transfer of protocol fees, must be gated behind
    /// a capability.
    ///
    /// # Storing Switchboard Aggregators
    ///
    /// Switchboard `Aggregator`s cannot be stored in this structure.
    /// This is because if `RAMM` `has key`, then
    /// * all its fields must have `store`
    /// * in particular, `vector<Aggregator>` must have store
    ///   - so `Aggregator` must have `store`
    /// * Which it does not, so RAMM cannot have `key`
    /// * Meaning it cannot be used be turned into a shared object with 
    ///   `sui::transfer::share_object`
    /// * which it *must* be, to be readable and writable by all
    struct RAMM has key {
        id: UID,

        // ID of the `AdminCap` required to perform sensitive operations.
        // Not storing this field means any admin of any RAMM can affect any
        // other - not good.
        admin_cap_id: ID,
        // `Option` with the ID of the cap used to add new assets.
        // Used to flag whether a RAMM has been initialized or not:
        // * Before initialization, deposits cannot be made, and cannot be enabled.
        //   - the field must be `Some` before initialization
        // * After initialization, no more assets can be added.
        //   - thenceforth and until the RAMM object is deleted, the field will be `None`
        new_asset_cap_id: Option<ID>,
    
        // Address of the fee to which `Coin<T>` objects representing collected
        // fees will be sent.
        fee_collector: address,
        // The specific content of this field is still TODO.
        // map from `u8` -> `Balance<T>`
        collected_protocol_fees: Bag,

        // map from `u8` -> `switchboard::Aggregator::address`; this address is derived
        // from the aggregator's UID.
        aggregator_addrs: VecMap<u8, address>,

        // map from asset indexes, `u8`, to untyped balances, `u256`.
        // The semantic significance of values is still TODO as the decimal places
        // are being decided.
        balances: VecMap<u8, u256>,
        // map from `u8` -> `Balance<T>`
        typed_balances: Bag,
        // minimum trading amounts for each token.
        minimum_trade_amounts: VecMap<u8, u64>,

        // Same here, still TODO
        lp_tokens_issued: VecMap<u8, u256>,
        // map from `u8` -> `Supply<T>`.
        // Recall that `Supply` is needed to mint/burn tokens - in this case, LP tokens.
        typed_lp_tokens_issued: Bag,

        // per-asset flag marking whether deposits are enabled
        deposits_enabled: VecMap<u8, bool>,

        // Mapping between the type names of this pool's assets, and their indexes;
        // used to index other maps in the `RAMM` structure.
        //
        // Each `TypeName` will be of the form `<package-id>::<module>::<type-name>`.
        // E.g. `SUI`'s `TypeName` is `0x2::sui::SUI`.
        // Because Sui packages are treated as immutable objects with unique IDs,
        // the function `type_name::get<T>: () -> TypeName` is a bijection between
        // types and their `TypeName`s (which internally are `String`s).
        //
        // Done for storage considerations: storing type names in every single
        // map/bag as keys is unwieldy.
        types_to_indexes: VecMap<TypeName, u8>,
        // This would be `N`, in the whitepaper - the total number of assets
        // being held by a pool.
        asset_count: u8,
    }

    /// -----------
    /// `impl RAMM`
    /// -----------

    /// Create a new RAMM structure, without any asset.
    ///
    /// This RAMM needs to have assets added to it before it can be initialized,
    /// after which it can be used.
    public(friend) entry fun new_ramm(
        fee_collector: address,
        ctx: &mut TxContext
    ) {
        let admin_cap = RAMMAdminCap { id: object::new(ctx) };
        let admin_cap_id = object::id(&admin_cap);
        let new_asset_cap = RAMMNewAssetCap { id: object::new(ctx) };
        let new_asset_cap_id = option::some(object::id(&new_asset_cap));

        let ramm_init = RAMM {
                id: object::new(ctx),
                admin_cap_id,
                new_asset_cap_id,
                fee_collector,

                aggregator_addrs: vec_map::empty<u8, address>(),
                balances: vec_map::empty<u8, u256>(),
                typed_balances: bag::new(ctx),

                lp_tokens_issued: vec_map::empty<u8, u256>(),
                typed_lp_tokens_issued: bag::new(ctx),

                minimum_trade_amounts: vec_map::empty<u8, u64>(),
                deposits_enabled: vec_map::empty<u8, bool>(),
                collected_protocol_fees: bag::new(ctx),

                types_to_indexes: vec_map::empty<TypeName, u8>(),
                asset_count: 0
            };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::transfer(new_asset_cap, tx_context::sender(ctx));
        transfer::share_object(ramm_init);
    }

    #[test]
    /// Some basic sanity checks, better safe than sorry.
    ///
    /// This test lives here, and not in the `tests` directory, because there is
    /// no point in exporting functions to check whether internal fields are empty.
    fun new_ramm_checks() {
        use sui::test_scenario;

        let admin = @0xA1;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            new_ramm(admin, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, admin);

        assert!(test_scenario::has_most_recent_for_address<RAMMAdminCap>(admin), ERAMMInvalidInitState);
        let ramm = test_scenario::take_shared<RAMM>(scenario);
        let a = test_scenario::take_from_address<RAMMAdminCap>(scenario, admin);
        let na = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, admin);

        assert!(ramm.admin_cap_id == object::id(&a), ERAMMInvalidInitState);
        assert!(ramm.new_asset_cap_id == option::some(object::id(&na)), ERAMMInvalidInitState);
        assert!(ramm.fee_collector == admin, ERAMMInvalidInitState);
        assert!(bag::is_empty(&ramm.collected_protocol_fees), ERAMMInvalidInitState);

        assert!(vec_map::is_empty<u8, address>(&ramm.aggregator_addrs), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, u256>(&ramm.balances), ERAMMInvalidInitState);
        assert!(bag::is_empty(&ramm.typed_balances), ERAMMInvalidInitState);

        assert!(vec_map::is_empty<u8, u256>(&ramm.lp_tokens_issued), ERAMMInvalidInitState);
        assert!(bag::is_empty(&ramm.typed_lp_tokens_issued), ERAMMInvalidInitState);

        assert!(vec_map::is_empty<u8, u64>(&ramm.minimum_trade_amounts), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, bool>(&ramm.deposits_enabled), ERAMMInvalidInitState);
        assert!(bag::is_empty(&ramm.collected_protocol_fees), ERAMMInvalidInitState);

        assert!(vec_map::is_empty<TypeName, u8>(&ramm.types_to_indexes), ERAMMInvalidInitState);

        assert!(ramm.asset_count == 0, ERAMMInvalidInitState);

        test_scenario::return_to_address<RAMMAdminCap>(admin, a);
        test_scenario::return_to_address<RAMMNewAssetCap>(admin, na);
        test_scenario::return_shared<RAMM>(ramm);

        test_scenario::end(scenario_val);
    }

    /// This function introduces an asset to the RAMM, and initializes its
    /// corresponding state, including:
    /// * balances to 0
    /// * creates a minter for that asset's LP token, and sets the LP balance to 0
    /// * deposits are enabled by default
    /// * collected fees for that asset are also 0
    /// * the name of the asset's type, `<package-id>::<module>::<type-name>`, will be indexed
    ///
    /// For every asset meant to be included in the RAMM, this function will need to be called.
    ///
    /// # Aborts
    ///
    /// * If called with the wrong admin or new asset capability objects
    /// * If an asset that already exists is added twice, the function will abort.
    /// * If more than `u8::MAX` assets are added to the pool
    public(friend) fun add_asset_to_ramm<Asset>(
        self: &mut RAMM,
        feed: &Aggregator,
        min_trade_amnt: u64,
        a: &RAMMAdminCap,
        na: &RAMMNewAssetCap,
    ) {
        assert!(self.admin_cap_id == object::id(a), ENotAdmin);
        assert!(self.new_asset_cap_id == option::some(object::id(na)), EWrongNewAssetCap);

        let type_name = type_name::get<Asset>();
        let type_index = self.asset_count;
        self.asset_count = self.asset_count + 1;

        vec_map::insert(
            &mut self.aggregator_addrs,
            type_index,
            aggregator::aggregator_address(feed)
        );

        vec_map::insert(&mut self.balances, type_index, 0);
        bag::add(&mut self.typed_balances, type_index, balance::zero<Asset>());
        vec_map::insert(&mut self.minimum_trade_amounts, type_index, min_trade_amnt);

        vec_map::insert(&mut self.lp_tokens_issued, type_index, 0);
        bag::add(&mut self.typed_lp_tokens_issued, type_index, balance::create_supply(LP<Asset> {}));

        vec_map::insert(&mut self.deposits_enabled, type_index, false);
        bag::add(&mut self.collected_protocol_fees, type_index, balance::zero<Asset>());

        vec_map::insert(&mut self.types_to_indexes, type_name, type_index);

        let n = (self.asset_count as u64);
        assert!(n == vec_map::size(&self.aggregator_addrs), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.balances), ERAMMNewAssetFailure);
        assert!(n == bag::length(&self.typed_balances), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.lp_tokens_issued), ERAMMNewAssetFailure);
        assert!(n == bag::length(&self.typed_lp_tokens_issued), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.deposits_enabled), ERAMMNewAssetFailure);
        assert!(n == bag::length(&self.collected_protocol_fees), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.types_to_indexes), ERAMMNewAssetFailure);
    }

    /// Initialize a RAMM pool.
    ///
    /// Its `RAMMNewAssetCap`ability must be passed in by value so that it is destroyed,
    /// preventing new assets from being added to the pool.
    ///
    /// # Aborts
    ///
    /// This function will abort if the wrong admin or new asset capabilities are provided.
    ///
    /// This function will also abort if its internal data is inconsistent e.g.
    /// there are no assets, or the number of held assets differs from the number
    /// of LP token issuers.
    public(friend) entry fun initialize_ramm(
        self: &mut RAMM,
        a: &RAMMAdminCap,
        cap: RAMMNewAssetCap,
    ) {
        assert!(self.admin_cap_id == object::id(a), ENotAdmin);
        assert!(self.new_asset_cap_id == option::some(object::id(&cap)), EWrongNewAssetCap);
        assert!(self.asset_count > 0, ENoAssetsInRAMM);

        let index_map_size = vec_map::size(&self.types_to_indexes);
        assert!(
            index_map_size > 0 &&
            index_map_size == vec_map::size(&self.balances) &&
            index_map_size == bag::length(&self.typed_balances) &&
            index_map_size == vec_map::size(&self.lp_tokens_issued) &&
            index_map_size == bag::length(&self.typed_lp_tokens_issued) &&
            index_map_size == vec_map::size(&self.deposits_enabled),
            ERAMMInvalidInitState
        );

        let ix = 0;
        while (ix < self.asset_count) {
            set_deposit_status(self, ix, true); 
            ix = ix + 1;
        };

        let RAMMNewAssetCap { id: uid } = cap;
        object::delete(uid);

        let _ = option::extract(&mut self.new_asset_cap_id);
    }

    /// --------------------------
    /// Getters/setters, accessors
    /// --------------------------

    /// Admin cap
    
    public(friend) fun get_admin_cap_id(self: &RAMM): ID {
        self.admin_cap_id
    }

    /// Fee collector address

    public(friend) fun get_fee_collector(self: &RAMM): address {
        self.fee_collector
    }

    /// Change a RAMM's fee collection address.
    ///
    /// Callable on RAMMs of arbitrary size.
    ///
    /// # Aborts
    ///
    /// If called with the wrong admin capability object.
    public(friend) fun set_fee_collector(self: &mut RAMM, a: &RAMMAdminCap, new_fee_addr: address) {
        assert!(self.admin_cap_id == object::id(a), ENotAdmin);
        self.fee_collector = new_fee_addr;
    }

    /// Aggregator addresses

    fun get_aggr_addr(self: &RAMM, index: u8): address {
        *vec_map::get(&self.aggregator_addrs, &index)
    }

    public(friend) fun get_aggregator_address<Asset>(self: &RAMM): address {
        let ix = get_asset_index<Asset>(self);
        get_aggr_addr(self, ix)
    }

    /// Balances

    /// Get an asset's scaled balance, meaning a `u256` with the RAMM's specified decimal
    /// places, instead of `u64/Balance<T>`.
    public(friend) fun get_bal(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.balances, &index)
    }

    public(friend) fun get_balance<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_bal(self, ix)
    }

    /// Typed Balances

    public(friend) fun get_typed_balance<Asset>(self: &RAMM): u64 {
        let ix = get_asset_index<Asset>(self);
        balance::value(bag::borrow<u8, Balance<Asset>>(&self.typed_balances, ix))
    }

    /// LP Tokens Issued

    fun get_lptok_issued(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.lp_tokens_issued, &index)
    }

    public(friend) fun get_lptokens_issued<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_lptok_issued(self, ix)
    }

    /// Typed LP Tokens Issued

    fun get_typed_lptokens_issued<Asset>(self: &mut RAMM): &mut Supply<LP<Asset>> {
        let ix = get_asset_index<Asset>(self);
        bag::borrow_mut<u8, Supply<LP<Asset>>>(&mut self.typed_lp_tokens_issued, ix)
    }

    public(friend) fun get_typed_lptokens_issued_u64<Asset>(self: &RAMM): u64 {
        let ix = get_asset_index<Asset>(self);
        balance::supply_value(bag::borrow<u8, Supply<LP<Asset>>>(&self.typed_lp_tokens_issued, ix))
    }

    /// Minimum trading amounts

    /// Get an asset's minimum trading amount, in `u64`.
    public(friend) fun get_min_trade_amount(self: &RAMM, index: u8): u64 {
        *vec_map::get(&self.minimum_trade_amounts, &index)
    }

    /// Get the current minimum trade amount for an asset in the RAMM.
    ///
    /// # Aborts
    ///
    /// * If the RAMM does not have an asset with the provided type.
    public fun get_minimum_trade_amount<Asset>(self: &RAMM): u64 {
        let ix = get_asset_index<Asset>(self);
        get_min_trade_amount(self, ix)
    }

    /// For an asset in the RAMM, change its minimum trading amount.
    /// Can only be called by the RAMM's administrator.
    ///
    /// # Aborts
    ///
    /// * If called with the wrong admin capability object
    /// * If the RAMM does not have an asset with the provided type.
    public(friend) fun set_minimum_trade_amount<Asset>(
        self: &mut RAMM,
        a: &RAMMAdminCap,
        new_min: u64
    ) {
        assert!(self.admin_cap_id == object::id(a), ENotAdmin);

        let ix = get_asset_index<Asset>(self);
        *vec_map::get_mut(&mut self.minimum_trade_amounts, &ix) = new_min
    }

    /// Deposit status

    /// Change deposit permission status for a single asset in the RAMM.
    ///
    /// Private visibility, since
    /// * this action should not be performed without a `RAMMAdminCap`
    /// * users are not allowed to provide asset indexes themselves:
    ///   they provide a type to the public function (below), which safely calculates
    ///   the index and then calls this function.
    fun set_deposit_status(self: &mut RAMM, index: u8, deposit_enabled: bool) {
        *vec_map::get_mut(&mut self.deposits_enabled, &index) = deposit_enabled
    }

    /// For a given asset, returns true iff its deposits are enabled.
    public(friend) fun can_deposit_asset(self: &RAMM, index: u8): bool {
        *vec_map::get(&self.deposits_enabled, &index)
    }

    /// Function that allows a RAMM's admin to enable deposits for an asset.
    ///
    /// # Aborts
    /// * If called with the wrong admin capability object
    /// * If the RAMM has not been initialized
    /// * If the RAMM does not have an asset with the provided type
    public fun enable_deposits<Asset>(self: &mut RAMM, a: &RAMMAdminCap) {
        assert!(self.admin_cap_id == object::id(a), ENotAdmin);
        assert!(is_initialized(self), ENotInitialized);

        let ix = get_asset_index<Asset>(self);
        set_deposit_status(self, ix, true)
    }

    /// Function that allows a RAMM's admin to disable deposits for an asset.
    ///
    /// # Aborts
    /// * If called with the wrong admin capability object
    /// * If the RAMM has not been initialized
    /// * If the RAMM does not have an asset with the provided type
    public fun disable_deposits<Asset>(self: &mut RAMM, a: &RAMMAdminCap) {
        assert!(self.admin_cap_id == object::id(a), ENotAdmin);
        assert!(is_initialized(self), ENotInitialized);

        let ix = get_asset_index<Asset>(self);
        set_deposit_status(self, ix, false)
    }

    public fun get_deposit_status<Asset>(self: &RAMM): bool {
        let ix = get_asset_index<Asset>(self);
        can_deposit_asset(self, ix)
    }

    /// Collected protocol fees

    fun get_fees<Asset>(self: &RAMM, index: u8): u64 {
        balance::value(bag::borrow<u8, Balance<Asset>>(&self.collected_protocol_fees, index))
    }

    public(friend) fun get_collected_protocol_fees<Asset>(self: &RAMM): u64 {
        let ix = get_asset_index<Asset>(self);
        get_fees<Asset>(self, ix)
    }

    /// Type indexes
    
    public(friend) fun get_type_index<Asset>(self: &RAMM): u8 {
        *vec_map::get(&self.types_to_indexes, &type_name::get<Asset>())
    }

    /// Asset count

    /// Return the number of assets in the RAMM
    public(friend) fun get_asset_count(self: &RAMM): u8 {
        self.asset_count
    }

    /// -----------------
    /// Utility functions
    /// -----------------

    /// Returns true iff the RAMM has been initialized.
    ///
    /// Before initialization, deposits are mandatorily disabled, but assets can be
    /// added.
    ///
    /// After it, assets can no longer be added and deposits can be enabled/disabled at
    /// will by the admin.
    public fun is_initialized(self: &RAMM): bool {
        option::is_none(&self.new_asset_cap_id)
    }

    /// Given the type of asset in the RAMM, return the index used internally
    /// to represent it.
    ///
    /// # Aborts
    ///
    /// This function will abort if the RAMM has no assets with the given type.
    public(friend) fun get_asset_index<Asset>(self: &RAMM): u8 {
        let type_name = type_name::get<Asset>();
        let n: &u8 = vec_map::get(&self.types_to_indexes, &type_name);
        *n
    }

    /// For a given `Asset` in the RAMM, return how many LP tokens are in circulation.
    public(friend) fun lptok_in_circulation<Asset>(self: &RAMM, index: u8): u64 {
        let supply: &Supply<Asset> = bag::borrow(&self.typed_lp_tokens_issued, index);
        balance::supply_value(supply)
    }

    /// Internal function to retrieve fees for an asset.
    ///
    /// Since the size of the bag with collected fees should always be equal
    /// to the number of assets in the RAMM, instead of removing the `Balance` struct,
    /// it is mutably borrowed, and then `balance::split` in such a way that `balance::zero<Asset>`
    /// is left in the bag, for the desired asset.
    public(friend) fun get_fees_for_asset<Asset>(self: &mut RAMM, ix: u8): Balance<Asset> {
        let mut_bal: &mut Balance<Asset> =
            bag::borrow_mut<u8, Balance<Asset>>(&mut self.collected_protocol_fees, ix);
        let curr_fee = balance::value(mut_bal);
        balance::split(mut_bal, curr_fee)
    }

    /// ------------------------
    /// Oracle related functions
    /// ------------------------

    /// Check that the address provided for an asset's pricing oracle
    /// is the same as the one in the RAMM's state.
    ///
    /// If provided with an aggregator for an asset that does not exist in the
    /// pool, it will abort.
    public(friend) fun check_feed_address(self: &RAMM, index: u8, feed: &Aggregator): bool {
        let addr = vec_map::get(&self.aggregator_addrs, &index);
        *addr == aggregator::aggregator_address(feed)
    }

    /// Given a Switchboard aggregator, fetch the price data within it.
    ///
    /// This function is not public, as it is NOT safe to call this *without*
    /// first checking that the aggregator's address matches the RAMM's records
    /// for the given asset.
    ///
    /// TODO: *actually* use all the fields from `aggregator::latest_value`
    public(friend) fun get_price_from_oracle(feed: &Aggregator): u256 {
        // the timestamp can be used in the future to check for price staleness
        let (latest_result, _latest_timestamp) = aggregator::latest_value(feed);
        // do something with the below, most likely scale it to our needs
        ramm_math::sbd_to_u256(latest_result)
    }

    /// Verify that the address of the pricing feed for a certain asset matches the
    /// one supplied when the asset was initialized in the RAMM.
    ///
    /// If it is, fetch its price, and add it to the mapping from asset
    /// indexes to their prices provided as argument.
    public(friend) fun check_feed_and_get_price(
        self: &RAMM,
        ix: u8,
        feed: &Aggregator,
        prices: &mut VecMap<u8, u256>
    ) {
        assert!(check_feed_address(self, ix, feed), EInvalidAggregator);
        vec_map::insert(prices, ix, get_price_from_oracle(feed));
    }

    /// --------------------------
    /// Internal trading functions
    /// --------------------------

    /// Internal function, used by the public trading API e.g. `trade_amount_in_3`.
    /// Contains business logic, and assumes checks have already been made by client-facing
    /// functions.
    ///
    /// This function can be used on a RAMM of any size.
    public(friend) fun trade_i<AssetIn, AssetOut>(
        _self: &mut RAMM,
        // index of incoming token
        _i: u8,
        // index of outgoing token
        _o: u8,
        ai: Coin<AssetIn>,
        _prices: VecMap<u8, u256>
    ): Coin<AssetIn> {
        // TODO
        ai
    }

    /// Internal function, used by the public trading API e.g. `trade_amount_out_3`.
    /// Contains business logic, and assumes checks have already been made by client-facing
    /// functions.
    ///
    /// This function can be used on a RAMM of any size.
    public(friend) fun trade_o<AssetIn, AssetOut>(
        _self: &mut RAMM,
        // index of incoming token
        _i: u8,
        // index of outgoing token
        _o: u8,
        _ao: u64,
        _prices: VecMap<u8, u256>
    ) {
        // TODO
    }

    /// ----------------------------
    /// Liquidity deposit/withdrawal
    /// ----------------------------

    /// 
    public(friend) fun single_asset_deposit<AssetIn>(
        self: &mut RAMM,
        i: u8,
        ai: Coin<AssetIn>,
        _prices: VecMap<u8, u256>,
        ctx: &mut TxContext
        ): Coin<LP<AssetIn>> {
        // TODO
        let amount_in = coin::into_balance(ai);
        let amount_in_u64 = balance::value(&amount_in);
        let curr_bal = vec_map::get_mut(&mut self.balances, &i);
        let curr_typed_bal = bag::borrow_mut<u8, Balance<AssetIn>>(&mut self.typed_balances, i);
        let new_bal = balance::join(curr_typed_bal, amount_in);
        *curr_bal = (new_bal as u256);

        let lptoken_supply = get_typed_lptokens_issued<AssetIn>(self);
        let lptoken_balance = balance::increase_supply(lptoken_supply, amount_in_u64);

        coin::from_balance(lptoken_balance, ctx)
    }

    public(friend) fun single_asset_withdrawal<Asset1, Asset2, Asset3, AssetOut>(
        self: &mut RAMM,
        o: u8,
        lp_token: Coin<LP<AssetOut>>,
        _prices: VecMap<u8, u256>,
        ctx: &mut TxContext
    ): (Coin<Asset1>, Coin<Asset2>, Coin<Asset3>) {
        // TODO

        let lp_token = coin::into_balance(lp_token);
        let lp_token_value = balance::value(&lp_token);
        let curr_lpt_bal = vec_map::get_mut(&mut self.lp_tokens_issued, &o);
        let curr_typed_lpt_bal = bag::borrow_mut<u8, Supply<LP<AssetOut>>>(&mut self.typed_lp_tokens_issued, o);
        balance::decrease_supply(curr_typed_lpt_bal, lp_token);
        *curr_lpt_bal = *curr_lpt_bal - (lp_token_value as u256);

        (coin::zero<Asset1>(ctx), coin::zero<Asset2>(ctx), coin::zero<Asset3>(ctx))
    }

}