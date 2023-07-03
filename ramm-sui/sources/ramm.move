module ramm_sui::ramm {
    use std::option::{Self, Option};

    use sui::bag::{Self, Bag};
    use sui::balance::{Self, Balance, Supply};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use std::type_name::{Self, TypeName};

    use switchboard::aggregator::{Self, Aggregator};

    use ramm_sui::math as ramm_math;

    friend ramm_sui::interface2;
    friend ramm_sui::interface3;

    // Because of the below declarations, use the `test` flag when building or
    // creating test coverage maps: `sui move test coverage --test`.
    friend ramm_sui::interface2_tests;
    friend ramm_sui::interface3_safety_tests;
    friend ramm_sui::interface3_tests;
    friend ramm_sui::math_tests;
    friend ramm_sui::ramm_tests;
    friend ramm_sui::test_util;

    const ERAMMInvalidInitState: u64 = 0;
    const EInvalidAggregator: u64 = 1;
    const ENotAdmin: u64 = 2;
    const ENoAssetsInRAMM: u64 = 3;
    const ERAMMNewAssetFailure: u64 = 4;
    const ENotInitialized: u64 = 5;
    const EWrongNewAssetCap: u64 = 6;
    const EBrokenRAMMInvariants: u64 = 7;

    /// --------------
    /// RAMM Constants
    /// --------------

    const TWO: u8 = 2;
    const THREE: u8 = 3;

    /// Number of decimal places of precision.
    const PRECISION_DECIMAL_PLACES: u8 = 12;
    /// Maximum permissible places of precision, may yet be subject to change
    const MAX_PRECISION_DECIMAL_PLACES: u8 = 25;
    /// Decimal places that LP tokens will be using; may yet change.
    const LP_TOKENS_DECIMAL_PLACES: u8 = 9;

    /// Value of `1` using `PRECISION_DECIMAL_PLACES`; useful to scale other values to
    /// the baseline precision.
    ///
    /// Sui Move does not permit using constants in other constants' definitions, so
    /// `ONE` will need to be hardcoded.
    const ONE: u256 = 1_000_000_000_000;

    /// Base fee in basis points:
    ///
    /// A value of 10 means 0.001 or 0.1%
    const BASE_FEE: u256 = 10 * 1_000_000_000_000 / 10000; // _BASE_FEE * 10**(PRECISION_DECIMAL_PLACES-4)

    // BASE_LEVERAGE = _BASE_LEVERAGE * ONE
    const BASE_LEVERAGE: u256 = 100 * 1_000_000_000_000;

    /// 50% of collected base fees go to the RAMM.
    const PROTOCOL_FEE: u256 = 50 * 1_000_000_000_000 / 100; // PROTOCOL_FEE = _PROTOCOL_FEE*10**(PRECISION_DECIMAL_PLACES-2)

    /// Miguel's note:
    /// Maximum permitted deviation of the imbalance ratios from 1.0.
    /// 2 decimal places are considered.
    ///
    /// Hence DELTA=25 is interpreted as 0.25
    const DELTA: u256 = 25 * 1_000_000_000_000 / 100; // DELTA = _DELTA * 10**(PRECISION_DECIMAL_PLACES-2)

    // FACTOR_LPT = 10**(PRECISION_DECIMAL_PLACES-LP_TOKENS_DECIMAL_PLACES)
    const FACTOR_LPT: u256 = 1_000_000_000_000 / 1_000_000_000;

    /// ---------------------
    /// End of math constants
    /// ---------------------

    /// A "Liquidity Pool" token that will be used to mark the pool share
    /// of a liquidity provider.
    ///
    /// The parameter `Asset` is for the coin held in the pool.
    struct LP<phantom Asset> has drop, store {}

    /// Admin capability to circumvent restricted actions on the RAMM pool:
    /// * transfer RAMM protocol fees out of the pool,
    /// * enable/disable deposits for a certain asset
    /// * etc.
    struct RAMMAdminCap has key { id: UID }

    /// Capability to add assets to the RAMM pool.
    ///
    /// When the pool is initialized, it must be deleted.
    struct RAMMNewAssetCap has key { id: UID }

    /// RAMM data structure, allows
    /// * adding/removing liquidity for one of its assets
    /// * trading of one of its tokens for another
    ///
    /// The structure is shared, so that any address is be able to submit requests.
    /// It is, therefore, publicly available for reads and writes.
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
        // Map from asset indexes `u8` to fees collected over that asset, `Balance<T>`
        collected_protocol_fees: Bag,

        // map from `u8` -> `switchboard::Aggregator::address`; this address is derived
        // from the aggregator's UID.
        aggregator_addrs: VecMap<u8, address>,

        // Map from asset indexes, `u8`, to untyped balances, `u256`.
        // Both typed and untyped balances are required due to limitations with Sui Move.
        balances: VecMap<u8, u256>,
        // Map from asset indexes `u8` to their respective balances, `Balance<T>`
        typed_balances: Bag,
        // minimum trading amounts for each token.
        minimum_trade_amounts: VecMap<u8, u64>,

        // Map from asset indexes, `u8`, to untyped counts of issued LP tokens for that
        // asset, in `u256`.
        lp_tokens_issued: VecMap<u8, u256>,
        // Map from asset indices, `u8`, to LP token supply data - `Supply<T>`.
        // From `Supply<T>` it is possible to mint, burn and query issued tokens.
        typed_lp_tokens_issued: Bag,

        // per-asset flag marking whether deposits are enabled.
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
        // Scaling factor for each of the assets, used to bring their values to the baseline
        // order of magnitude, using `PRECISION_DECIMAL_PLACES`.
        //
        // Every coin has its decimal place count specified in its `CoinMetadata` structure.
        // This value is used upon asset insertion to calculate the right factor.
        //
        // Cannot be changed.
        factors_for_balances: VecMap<u8, u256>,
        // Total number of assets in the RAMM pool. `N` in the whitepaper.
        asset_count: u8,
    }

    /// Result of an asset deposit/withdrawal operation by a trader.
    /// If `execute_trade` is `true`, then:
    /// * in the case of an asset deposit, the amount of the outbound asset is specified,
    ///   as well as the fee to be levied on the inbound asset
    /// * in the case of an asset withdrawal, the amount of the inbound asset is specified,
    ///   as well as the fee to be levied on the inbound asset
    struct TradeOutput has drop {
        amount: u256,
        protocol_fee: u256,
        execute_trade: bool
    }

    public(friend) fun amount(to: &TradeOutput): u256 {
        to.amount
    }

    public(friend) fun protocol_fee(to: &TradeOutput): u256 {
        to.protocol_fee
    }

    public(friend) fun execute(to: &TradeOutput): bool {
        to.execute_trade
    }

    /// Result of a liquidity withdrawal by a trader that had previously deposited
    /// liquidity into the pool.
    ///
    /// Contains:
    /// * the amount of each of the pool's assets the trader will receive for his LP tokens
    /// * the total value of the redeemed tokens
    /// * the remaining value
    struct WithdrawalOutput has drop {
        amounts: VecMap<u8, u256>,
        value: u256,
        remaining: u256
    }

    /// Return a `WithdrawalOutput's` mapping of assets to liquidity withdrawal values
    /// in that asset.
    public(friend) fun amounts(wo: &WithdrawalOutput): VecMap<u8, u256> {
        wo.amounts
    }

    /// Return the value given to the liquidity provider in terms of token `o`, which the provider
    /// wants.
    public(friend) fun value(wo: &WithdrawalOutput): u256 {
        wo.value
    }

    /// Return the remaining amount of token `o` to be given to the liquidity provider (if any)
    /// in case the process could not be completed.
    public(friend) fun remaining(wo: &WithdrawalOutput): u256 {
        wo.remaining
    }

    /// --------------
    /// Math functions
    /// --------------

    /*
    The functions below are wrappers of functions from `ramm_sui::math`, with appropriate
    constants from this module provided as arguments.

    See `ramm_math` for details.
    */

    public(friend) fun mul(x: u256, y: u256): u256 {
        ramm_math::mul(x, y, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public(friend) fun mul3(x: u256, y: u256, z: u256): u256 {
        ramm_math::mul3(x, y, z, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public(friend) fun div(x: u256, y: u256): u256 {
        ramm_math::div(x, y, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public(friend) fun pow_n(x: u256, n: u256): u256 {
        ramm_math::pow_n(x, n, ONE, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public(friend) fun pow_d(x: u256, a: u256): u256 {
        ramm_math::pow_d(x, a, ONE, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public(friend) fun power(x: u256, a: u256): u256 {
        ramm_math::power(x, a, ONE, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public(friend) fun adjust(x: u256): u256 {
        ramm_math::adjust(x, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    /// ---------------------
    /// End of math functions
    /// ---------------------

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
                factors_for_balances: vec_map::empty<u8, u256>(),
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
        assert!(vec_map::is_empty<u8, u256>(&ramm.factors_for_balances), ERAMMInvalidInitState);

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
        asset_decimal_places: u8,
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
        let factor_balance: u256 = ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - asset_decimal_places);
        vec_map::insert(&mut self.factors_for_balances, type_index, factor_balance);

        let n = (self.asset_count as u64);
        assert!(n == vec_map::size(&self.aggregator_addrs), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.balances), ERAMMNewAssetFailure);
        assert!(n == bag::length(&self.typed_balances), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.lp_tokens_issued), ERAMMNewAssetFailure);
        assert!(n == bag::length(&self.typed_lp_tokens_issued), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.deposits_enabled), ERAMMNewAssetFailure);
        assert!(n == bag::length(&self.collected_protocol_fees), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.types_to_indexes), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.factors_for_balances), ERAMMNewAssetFailure);
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

    /// -------------------------
    /// RAMM structure invariants
    /// -------------------------

    /// Given a 2-asset RAMM, check that its internal invariants hold.
    ///
    /// This function should be used before and after operations that modify the RAMM's internal
    /// state such as trading or liquidity deposits/withdrawals, because
    /// * if the invariant does not hold at the start, the operation should not be performed
    /// * if it did hold, but then failed to, the operation should be rolled back
    public(friend) fun check_ramm_invariants_2<Asset1, Asset2>(self: &RAMM) {
        // This invariant checking function must only be used on RAMMs with 2 assets.
        assert!(get_asset_count(self) == TWO, EBrokenRAMMInvariants);

        // First, the typed and untyped balances must never go out of sync, for any reason.
        assert!(get_balance<Asset1>(self) == get_typed_balance<Asset1>(self), EBrokenRAMMInvariants);
        assert!(get_balance<Asset2>(self) == get_typed_balance<Asset2>(self), EBrokenRAMMInvariants);

        // Secondly, the typed and untyped counts of issued LP tokens must always match.
        assert!(get_lptokens_issued<Asset1>(self) == get_typed_lptokens_issued<Asset1>(self), EBrokenRAMMInvariants);
        assert!(get_lptokens_issued<Asset2>(self) == get_typed_lptokens_issued<Asset2>(self), EBrokenRAMMInvariants);
    }

    /// Given a 3-asset RAMM, check that its internal invariants hold.
    ///
    /// This function should be used before and after operations that modify the RAMM's internal
    /// state such as trading or liquidity deposits/withdrawals, because
    /// * if the invariant does not hold at the start, the operation should not be performed
    /// * if it did hold, but then failed to, the operation should be rolled back
    public(friend) fun check_ramm_invariants_3<Asset1, Asset2, Asset3>(self: &RAMM) {
        // This invariant checking function must only be used on RAMMs with 3 assets.
        assert!(get_asset_count(self) == THREE, EBrokenRAMMInvariants);

        // First, the typed and untyped balances must never go out of sync, for any reason.
        assert!(get_balance<Asset1>(self) == get_typed_balance<Asset1>(self), EBrokenRAMMInvariants);
        assert!(get_balance<Asset2>(self) == get_typed_balance<Asset2>(self), EBrokenRAMMInvariants);
        assert!(get_balance<Asset3>(self) == get_typed_balance<Asset3>(self), EBrokenRAMMInvariants);

        // Secondly, the typed and untyped counts of issued LP tokens must always match.
        assert!(get_lptokens_issued<Asset1>(self) == get_typed_lptokens_issued<Asset1>(self), EBrokenRAMMInvariants);
        assert!(get_lptokens_issued<Asset2>(self) == get_typed_lptokens_issued<Asset2>(self), EBrokenRAMMInvariants);
        assert!(get_lptokens_issued<Asset3>(self) == get_typed_lptokens_issued<Asset3>(self), EBrokenRAMMInvariants);
    }

    /// --------------------------
    /// Getters/setters, accessors
    /// --------------------------

    /// Admin cap
    
    /// Return the ID of the RAMM's admin capability.
    public(friend) fun get_admin_cap_id(self: &RAMM): ID {
        self.admin_cap_id
    }

    /// Fee collector address

    /// Return the `address` to which this RAMM will send collected protocol operation fees.
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

    /// Return the Switchboard aggregator address for a given asset.
    public(friend) fun get_aggregator_address<Asset>(self: &RAMM): address {
        let ix = get_asset_index<Asset>(self);
        get_aggr_addr(self, ix)
    }

    /// Balances

    /// Get an asset's typed balance, meaning the untyped, pure scalar value (`u256`) used
    /// internally by the RAMM to represent an asset's balance.
    public(friend) fun get_bal(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.balances, &index)
    }

    /// Getter for an asset's untyped balance.
    /// The asset index is not passed in, but instead obtained through the type parameter for safety.
    public(friend) fun get_balance<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_bal(self, ix)
    }

    /// Getter to mutable reference to an asset's untyped balance.
    fun get_mut_bal(self: &mut RAMM, index: u8): &mut u256 {
        vec_map::get_mut(&mut self.balances, &index)
    }

    /// Increment an asset's untyped balance by a given amount.
    ///
    /// It is the caller's responsibility to ensure this change is also
    /// reflected in, or is a reflection of, equivalent changes in the asset's typed
    /// balance.
    public(friend) fun join_bal(self: &mut RAMM, index: u8, bal: u256) {
        let asset_bal: &mut u256 = get_mut_bal(self, index);
        *asset_bal = *asset_bal + bal;
    }

    /// Decrement an asset's untyped balance by a given amount.
    ///
    /// It is the caller's responsibility to ensure this change is also
    /// reflected in, or is a reflection of, equivalent changes in the asset's typed
    /// balance.
    public(friend) fun split_bal(self: &mut RAMM, index: u8, val: u256) {
        let asset_bal: &mut u256 = get_mut_bal(self, index);
        *asset_bal = *asset_bal - val;
    }

    /// Typed Balances

    /// Internal getter for an asset's typed balance, with the asset index passed in
    /// and not calculated.
    fun get_typed_bal<Asset>(self: &RAMM, index: u8): u256 {
        (balance::value(bag::borrow<u8, Balance<Asset>>(&self.typed_balances, index)) as u256)
    }

    /// Getter for an asset's typed balance.
    /// The asset index is not passed in, but instead obtained through the type parameter for safety.
    public(friend) fun get_typed_balance<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_typed_bal<Asset>(self, ix)
    }

    fun get_mut_typed_bal<Asset>(self: &mut RAMM, index: u8): &mut Balance<Asset> {
        bag::borrow_mut<u8, Balance<Asset>>(&mut self.typed_balances, index)
    }

    /// Increment an asset's typed balance by a given amount.
    ///
    /// It is the caller's responsibility to ensure this change is also
    /// reflected in, or is a reflection of, equivalent changes in the asset's untyped
    /// balance.
    public(friend) fun join_typed_bal<Asset>(self: &mut RAMM, index: u8, bal: Balance<Asset>) {
        let asset_bal: &mut Balance<Asset> = get_mut_typed_bal(self, index);
        balance::join(asset_bal, bal);
    }

    /// Decrement an asset's typed balance by a given amount, returning the deducted
    /// `Balance`.
    ///
    /// It is the caller's responsibility to ensure this change is also
    /// reflected in, or is a reflection of, equivalent changes in the asset's untyped
    /// balance.
    public(friend) fun split_typed_bal<Asset>(self: &mut RAMM, index: u8, val: u64): Balance<Asset> {
        let asset_bal: &mut Balance<Asset> = get_mut_typed_bal(self, index);
        balance::split(asset_bal, val)
    }

    /// LP Tokens Issued

    fun get_lptok_issued(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.lp_tokens_issued, &index)
    }

    public(friend) fun get_lptokens_issued<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_lptok_issued(self, ix)
    }

    /// Update untyped count of issued LP tokens for a given asset.
    ///
    /// It's is the user's responsibility to ensure that there is also an
    /// update to the typed count for this token.
    public(friend) fun incr_lptokens_issued<Asset>(self: &mut RAMM, minted: u64) {
        let ix = get_asset_index<Asset>(self);
        let lptoks = vec_map::get_mut(&mut self.lp_tokens_issued, &ix);
        *lptoks = *lptoks + (minted as u256);
    }

    /// Update untyped count of issued LP tokens for a given asset.
    ///
    /// It's is the user's responsibility to ensure that there is also an
    /// update to the typed count for this token.
    public(friend) fun decr_lptokens_issued<Asset>(self: &mut RAMM, burned: u64) {
        let ix = get_asset_index<Asset>(self);
        let lptoks = vec_map::get_mut(&mut self.lp_tokens_issued, &ix);
        *lptoks = *lptoks - (burned as u256);
    }

    /// Typed LP Tokens Issued

    fun get_lptoken_supply<Asset>(self: &mut RAMM): &mut Supply<LP<Asset>> {
        let ix = get_asset_index<Asset>(self);
        bag::borrow_mut<u8, Supply<LP<Asset>>>(&mut self.typed_lp_tokens_issued, ix)
    }

    fun get_typed_lptok_issued<Asset>(self: &RAMM, index: u8): u256 {
        let supply = bag::borrow<u8, Supply<LP<Asset>>>(&self.typed_lp_tokens_issued, index);
        (balance::supply_value(supply) as u256)
    }

    public(friend) fun get_typed_lptokens_issued<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_typed_lptok_issued<Asset>(self, ix)
    }

    /// Mint LP tokens for a given asset, in a given amount.
    ///
    /// It's is the user's responsibility to ensure that there is also an
    /// update to the untyped LP token count for this token.
    public(friend) fun mint_lp_tokens<Asset>(self: &mut RAMM, amount: u64): Balance<LP<Asset>> {
        let supply = get_lptoken_supply<Asset>(self);
        balance::increase_supply(supply, amount)
    }

    /// Burn a given amount of LP tokens for a given asset.
    ///
    /// It's is the user's responsibility to ensure that there is also an
    /// update to the untyped LP token count for this token.
    public(friend) fun burn_lp_tokens<Asset>(self: &mut RAMM, lp_tokens: Balance<LP<Asset>>): u64 {
        let supply = get_lptoken_supply<Asset>(self);
        balance::decrease_supply(supply, lp_tokens)
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

    fun get_fee_balance<Asset>(self: &RAMM, index: u8): &Balance<Asset> {
        bag::borrow<u8, Balance<Asset>>(&self.collected_protocol_fees, index)
    }

    fun get_fees<Asset>(self: &RAMM, index: u8): u64 {
        balance::value(get_fee_balance<Asset>(self, index))
    }

    public(friend) fun get_collected_protocol_fees<Asset>(self: &RAMM): u64 {
        let ix = get_asset_index<Asset>(self);
        get_fees<Asset>(self, ix)
    }

    public(friend) fun join_protocol_fees<Asset>(self: &mut RAMM, index: u8, fee: Balance<Asset>) {
        let fee_bal = bag::borrow_mut<u8, Balance<Asset>>(&mut self.collected_protocol_fees, index);
        balance::join(fee_bal, fee);
    }

    /// Type indexes
    
    public(friend) fun get_type_index<Asset>(self: &RAMM): u8 {
        *vec_map::get(&self.types_to_indexes, &type_name::get<Asset>())
    }

    /// Asset decimal places

    public(friend) fun get_fact_for_bal(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.factors_for_balances, &index)
    }

    public(friend) fun get_factor_for_balance<Asset>(self: &RAMM): u256{
        let ix = get_asset_index<Asset>(self);
        get_fact_for_bal(self, ix)
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
        let supply: &Supply<LP<Asset>> = bag::borrow(&self.typed_lp_tokens_issued, index);
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
    /// Returns a tuple with the `u256` price, and the appropriate scaling
    /// factor to use when working with `PRECISION_DECIMAL_PLACES`.
    ///
    /// This function is not public, as it is NOT safe to call this *without*
    /// first checking that the aggregator's address matches the RAMM's records
    /// for the given asset.
    public(friend) fun get_price_from_oracle(feed: &Aggregator): (u256, u256) {
        // the timestamp can be used in the future to check for price staleness
        let (latest_result, _latest_timestamp) = aggregator::latest_value(feed);
        // do something with the below, most likely scale it to our needs
        ramm_math::sbd_to_price_info(latest_result, PRECISION_DECIMAL_PLACES)
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
        prices: &mut VecMap<u8, u256>,
        factors_for_prices: &mut VecMap<u8, u256>,
    ) {
        assert!(check_feed_address(self, ix, feed), EInvalidAggregator);
        let (price, factor_for_price) = get_price_from_oracle(feed);
        vec_map::insert(prices, ix, price);
        vec_map::insert(factors_for_prices, ix, factor_for_price);
    }

    /// ----------------------------------
    /// Mathematical functions for trading
    /// ----------------------------------

    /// Given a RAMM, current prices and their scaling factors relative to
    /// `PRECISION_DECIMAL_PLACES`, calculate the weights of each of the pool's assets.
    fun weights(
        self: &RAMM,
        prices: &VecMap<u8, u256>,
        factors_for_prices: &VecMap<u8, u256>
    ): VecMap<u8, u256> {
        ramm_math::weights(
            &self.balances,
            prices,
            &self.factors_for_balances,
            factors_for_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES
        )
    }

    /// Returns a tuple with the values of B and L. This functions wraps
    /// a version from `ramm_math` with parameters instead of fixed `const`s.
    ///
    /// The result is given in uint256 with PRECISION_DECIMAL_PLACES decimal places.
    fun compute_B_and_L(
        self: &RAMM,
        prices: &VecMap<u8, u256>,
        factors_for_prices: &VecMap<u8, u256>,
    ): (u256, u256) {
        ramm_math::compute_B_and_L(
            &self.balances,
            &self.lp_tokens_issued,
            prices,
            &self.factors_for_balances,
            FACTOR_LPT,
            factors_for_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        )
    }

    /// For a given RAMM and pricing information, return a list with the imbalance ratios of
    /// the tokens.
    ///
    /// The result is given in `u256` with `PRECISION_DECIMAL_PLACES` decimal places.
    fun imbalance_ratios(
        self: &RAMM,
        prices: &VecMap<u8, u256>,
        factors_for_prices: &VecMap<u8, u256>,
    ): VecMap<u8, u256> {
        ramm_math::imbalance_ratios(
            &self.balances,
            &self.lp_tokens_issued,
            prices,
            &self.factors_for_balances,
            FACTOR_LPT,
            factors_for_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        )
    }

    /// For a given RAMM, checks if the imbalance ratios after a trade belong to the permissible range,
    /// or if they would be closer to the range than before the trade.
    fun check_imbalance_ratios(
        self: &RAMM,
        prices: &VecMap<u8, u256>,
        i: u8,
        o: u8,
        ai: u256,
        ao: u256,
        pr_fee: u256,
        factors_for_prices: &VecMap<u8, u256>,
    ): bool {
        ramm_math::check_imbalance_ratios(
            &self.balances,
            &self.lp_tokens_issued,
            prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &self.factors_for_balances,
            FACTOR_LPT,
            factors_for_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA
        )
    }

    /// Returns the scaled base fee and leverage parameter for a trade where token `i` goes into the
    /// pool and token `o` goes out of the pool.
    fun scaled_fee_and_leverage(
        self: &RAMM,
        prices: &VecMap<u8, u256>,
        i: u8,
        o: u8,
        factors_for_prices: &VecMap<u8, u256>,
    ): (u256, u256) {
        ramm_math::scaled_fee_and_leverage(
            &self.balances,
            &self.lp_tokens_issued,
            prices,
            i,
            o,
            &self.factors_for_balances,
            FACTOR_LPT,
            factors_for_prices,
            BASE_FEE,
            BASE_LEVERAGE,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        )
    }

    /// ------------------
    /// end of `impl RAMM`
    /// ------------------

    /// --------------------------
    /// Internal trading functions
    /// --------------------------

    /// Internal function, used by the public trading API e.g. `trade_amount_in_3`.
    /// Contains business logic, and assumes checks have already been made by client-facing
    /// functions.
    ///
    /// This function can be used on a RAMM of any size.
    public(friend) fun trade_i<AssetIn, AssetOut>(
        self: &RAMM,
        // index of incoming token
        i: u8,
        // index of outgoing token
        o: u8,
        ai: u256,
        prices: VecMap<u8, u256>,
        factors_for_prices: VecMap<u8, u256>
    ): TradeOutput {
        let factor_for_price_i: u256 = *vec_map::get(&factors_for_prices, &i);
        let factor_for_price_o: u256 = *vec_map::get(&factors_for_prices, &o);

        let factor_i: u256 = get_fact_for_bal(self, i);
        let factor_o: u256 = get_fact_for_bal(self, o);
        if (get_typed_bal<AssetIn>(self, i) == 0) {
            let num: u256 = mul3(ONE - BASE_FEE, ai * factor_i, *vec_map::get(&prices, &i) * factor_for_price_i);
            let ao: u256 = div(num, *vec_map::get(&prices, &i) * factor_for_price_o) / factor_o;
            let pr_fee: u256 = mul3(PROTOCOL_FEE, BASE_FEE, ai * factor_i) / factor_i;
            let execute: bool = check_imbalance_ratios(self, &prices, i, o, ai, ao, pr_fee, &factors_for_prices);
            return TradeOutput {amount: ao, protocol_fee: pr_fee, execute_trade: execute}
        };

        let _W: VecMap<u8, u256> = weights(self, &prices, &factors_for_prices);
        let wi: u256 = *vec_map::get(&_W, &i);
        let wo: u256 = *vec_map::get(&_W, &o);
        let leverage: &mut u256 = &mut BASE_LEVERAGE;
        let trading_fee: &mut u256 = &mut BASE_FEE;

        if (get_typed_lptok_issued<AssetOut>(self, o) != 0 && get_typed_bal<AssetIn>(self, i) != 0) {
            let imbs = imbalance_ratios(self, &prices, &factors_for_prices);
            let imb_ratios_initial_o: u256 = *vec_map::get(&imbs, &o);
            if (imb_ratios_initial_o < ONE - DELTA) {
                return TradeOutput {amount: 0, protocol_fee: 0, execute_trade: false}
            };
            let (tf, l) = scaled_fee_and_leverage(self, &prices, i, o, &factors_for_prices);
            *trading_fee = tf;
            *leverage = l;
        };

        let bi: u256 = mul(get_typed_bal<AssetIn>(self, i) * factor_i, *leverage);
        let bo: u256 = mul(get_typed_bal<AssetOut>(self, o) * factor_o, *leverage);

        let base_denom: u256 = bi + mul(ONE - *trading_fee, ai * factor_i);
        let power: u256 = power(div(bi, base_denom), div(wi, wo));
        let ao: u256 = mul(bo, ONE - power) / factor_o;
        let pr_fee: u256 = mul3(PROTOCOL_FEE, *trading_fee, ai * factor_i) / factor_i;
        if (ao > get_typed_bal<AssetOut>(self, o) ||
            (ao == get_typed_bal<AssetOut>(self, o) && get_typed_lptok_issued<AssetOut>(self, o) != 0)
        ) {
            return TradeOutput {amount: 0, protocol_fee:0, execute_trade: false}
        };
        let execute: bool = check_imbalance_ratios(self, &prices, i, o, ai, ao, pr_fee, &factors_for_prices);

        TradeOutput {amount: ao, protocol_fee: pr_fee, execute_trade: execute}
    }

    /// Internal function, used by the public trading API e.g. `trade_amount_out_3`.
    /// Contains business logic, and assumes checks have already been made by client-facing
    /// functions.
    ///
    /// This function can be used on a RAMM of any size.
    public(friend) fun trade_o<AssetIn, AssetOut>(
        self: &mut RAMM,
        // index of incoming token
        i: u8,
        // index of outgoing token
        o: u8,
        ao: u64,
        prices: VecMap<u8, u256>,
        factors_for_prices: VecMap<u8, u256>
    ): TradeOutput {
        let factor_for_price_i: u256 = *vec_map::get(&factors_for_prices, &i);
        let factor_for_price_o: u256 = *vec_map::get(&factors_for_prices, &o);

        let factor_i: u256 = get_fact_for_bal(self, i);
        let factor_o: u256 = get_fact_for_bal(self, o);

        let price_i: u256 = *vec_map::get(&prices, &i);
        let price_o: u256 = *vec_map::get(&prices, &o);

        let ao = (ao as u256);
        if (get_typed_bal<AssetIn>(self, i) == 0) {
            let num: u256 = mul(ao * factor_o, price_o * factor_for_price_o);
            let denom: u256 = mul(price_i * factor_for_price_i, ONE-BASE_FEE);
            let ai: u256 = div(num, denom) / factor_i;
            let pr_fee: u256 = mul3(PROTOCOL_FEE, BASE_FEE, ai * factor_i) / factor_i;
            let execute: bool = check_imbalance_ratios(self, &prices, i, o, ai, ao, pr_fee, &factors_for_prices);
            return TradeOutput {amount: ai, protocol_fee: pr_fee, execute_trade: execute}
        };

        let _W: VecMap<u8, u256> = weights(self, &prices, &factors_for_prices);
        let wi: u256 = *vec_map::get(&_W, &i);
        let wo: u256 = *vec_map::get(&_W, &o);
        let leverage: &mut u256 = &mut BASE_LEVERAGE;
        let trading_fee: &mut u256 = &mut BASE_FEE;

        if (get_typed_lptok_issued<AssetOut>(self, o) != 0 && get_typed_bal<AssetIn>(self, i) != 0) {
            let imbs = imbalance_ratios(self, &prices, &factors_for_prices);
            let imb_ratios_initial_o: u256 = *vec_map::get(&imbs, &o);
            if (imb_ratios_initial_o < ONE - DELTA) {
                return TradeOutput {amount: 0, protocol_fee: 0, execute_trade: false}
            };
            let (tf, l) = scaled_fee_and_leverage(self, &prices, i, o, &factors_for_prices);
            *trading_fee = tf;
            *leverage = l;
        };

        let bi: u256 = mul(get_typed_bal<AssetIn>(self, i) * factor_i, *leverage);
        let bo: u256 = mul(get_typed_bal<AssetOut>(self, o) * factor_o, *leverage);

        let power: u256 = power(div(bo, bo - ao * factor_o), div(wo, wi));
        let ai: u256 = div(mul(bi, power - ONE), ONE - *trading_fee) / factor_i;
        let pr_fee: u256 = mul3(PROTOCOL_FEE, *trading_fee, ai * factor_i) / factor_i;

        let execute: bool = check_imbalance_ratios(self, &prices, i, o, ai, ao, pr_fee, &factors_for_prices);
        TradeOutput {amount: ai, protocol_fee: pr_fee, execute_trade: execute}
    }

    /// ----------------------------
    /// Liquidity deposit/withdrawal
    /// ----------------------------

    /// Internal function used by liquidity deposit API e.g. `liquidity_deposit_3`.
    /// Only contains business logic for the RAMM, assumes all safety checks have been made by
    /// the caller.
    ///
    /// Unlike the client-facing API, this function can be used on a RAMM of any size.
    public(friend) fun single_asset_deposit<AssetIn>(
        self: &mut RAMM,
        i: u8,
        ai: u64,
        prices: VecMap<u8, u256>,
        factors_for_prices: VecMap<u8, u256>
    ): u64 {

        let factor_i = get_fact_for_bal(self, i);

        if (get_typed_lptok_issued<AssetIn>(self, i) == 0 ||
            (get_typed_lptok_issued<AssetIn>(self, i) != 0 && get_typed_bal<AssetIn>(self, i) == 0)
        ) {
            let (_B, _L) = compute_B_and_L(self, &prices, &factors_for_prices);
            if (_B == 0) {
                let lpt: u64 = ai;
                return lpt
            } else {
                let lpt: u256 = div(mul((ai as u256) * factor_i, _L), _B) / FACTOR_LPT;
                return (lpt as u64)
            }
        };

        if ((get_typed_lptok_issued<AssetIn>(self, i) != 0 && get_typed_bal<AssetIn>(self, i) != 0)) {
            let imb_ratios: VecMap<u8, u256> = imbalance_ratios(self, &prices, &factors_for_prices);
            let bi: u256 = get_typed_bal<AssetIn>(self, i) * factor_i;
            let ri: u256 = *vec_map::get(&imb_ratios, &i);

            let lpt: u256 =
                div(
                    mul3(
                        (ai as u256) * factor_i,
                        ri,
                        get_typed_lptok_issued<AssetIn>(self, i) * FACTOR_LPT
                        ),
                    bi
                ) / FACTOR_LPT;
            return (lpt as u64)
        } else {
            return 0
        }
    }

    /// Given an amount of LP tokens and their type `o`, return
    /// * the amounts of each of the pool's tokens to be given to the liquidity provider,
    /// * the value given to the LP in terms of token `o`, and
    /// * the remaining amount of token `o` to be given to the provider (if any) in case the
    ///   process could not be completed.
    ///
    /// This function is internal to the RAMM, and it can/should only be used indirectly.
    /// In other words, by being called in the client facing modules of the package, e.g.
    /// `interface3` for 3-asset RAMMs.
    public(friend) fun single_asset_withdrawal<AssetOut>(
        self: &mut RAMM,
        o: u8,
        lpt: u64,
        prices: VecMap<u8, u256>,
        factors_for_prices: VecMap<u8, u256>,
    ): WithdrawalOutput {
        let lpt: u256 = (lpt as u256);

        let amounts_out = vec_map::empty<u8, u256>();
        // Required to initialize this `VecMap` to zeroes, or `liquidity_withdrawal`
        // will fail.
        let t: u8 = 0;
        while (t < get_asset_count(self)) {
            vec_map::insert(&mut amounts_out, t, 0);
            t = t + 1;
        };

        let a_remaining: &mut u256 = &mut 0;
        let factor_o: u256 = get_fact_for_bal(self, o);
        let bo: u256 = get_typed_bal<AssetOut>(self, o) * factor_o;
        let imb_ratios: VecMap<u8, u256> = imbalance_ratios(self, &prices, &factors_for_prices);
        let ao: &mut u256 = &mut 0;
        let (_B, _L): (u256, u256) = compute_B_and_L(self, &prices, &factors_for_prices);

        // Miguel's notes:
        // The liquidity provider receives `0` token o.
        // We continue the withdrawal with another token.

        // This corresponds to Case 2 in the whitepaper's "Liquidity Withdrawal" section
        if (get_bal(self, o) == 0) {
            *ao = div(mul(lpt * FACTOR_LPT, _B), _L) / factor_o;
            *a_remaining = *ao;
        };

        // Case 1
        if (get_bal(self, o) != 0) {
            let ro: u256 = *vec_map::get(&imb_ratios, &o);
            let _Lo: u256 = get_typed_lptok_issued<AssetOut>(self, o) * factor_o;

            // Case 1.1
            if (lpt < get_typed_lptok_issued<AssetOut>(self, o)) {
                *ao = div(mul(lpt * FACTOR_LPT, bo), mul(_Lo, ro)) / factor_o;
                let max_token_o: &mut u256 = &mut 0;

                if (ONE - DELTA < ro) {
                    let min_token_o: u256 = div(mul3(_B, (get_lptok_issued(self, o) - lpt) * FACTOR_LPT, ONE - DELTA), _L) / factor_o;
                    *max_token_o = get_bal(self, o) - min_token_o;
                } else {
                    *max_token_o = div(mul(lpt * FACTOR_LPT, bo), _Lo) / factor_o;
                };

                let amounts_out_o: &mut u256 = vec_map::get_mut(&mut amounts_out, &o);
                // Case 1.1.1
                if (*ao <= *max_token_o) {
                    *amounts_out_o = *amounts_out_o + *ao;
                    return WithdrawalOutput { amounts: amounts_out, value: *ao, remaining: 0}
                };
                // Case 1.1.2
                if (*ao > *max_token_o) {
                    *amounts_out_o = *amounts_out_o + *max_token_o;
                    *a_remaining = *ao - *max_token_o;
                    let imb_ratio_o = vec_map::get_mut(&mut imb_ratios, &o);
                    // to avoid choosing token o again in the next steps
                    *imb_ratio_o = 0;
                    // Withdrawal continued with different token
                };
            } else {
                *ao = div(bo, ro) / factor_o;
                let amount_out_o = vec_map::get_mut(&mut amounts_out, &o);
                if (*ao <= get_bal(self, o)) {
                    *amount_out_o = *amount_out_o + *ao;
                    return WithdrawalOutput { amounts: amounts_out, value: *ao, remaining: 0}
                };
                if (*ao > get_bal(self, o)) {
                    *amount_out_o = *amount_out_o + get_bal(self, o);
                    *a_remaining = *ao - get_bal(self, o);
                    let imb_ratio_o = vec_map::get_mut(&mut imb_ratios, &o);
                    // to avoid choosing token o again in the next steps
                    *imb_ratio_o = 0;
                    // Withdrawal continued with different token
                };
            };
        };

        *vec_map::get_mut(&mut imb_ratios, &o) = 0;

        let j: u8 = 0;
        while (j < get_asset_count(self)) {
            let max_imb_ratio: &mut u256 = &mut 0;
            let index: &mut u8 = &mut copy o;

            let l: u8 = 0;
            while (l < get_asset_count(self)) {
                if (*max_imb_ratio < *vec_map::get(&imb_ratios, &l)) {
                    *index = l;
                    *max_imb_ratio = *vec_map::get(&imb_ratios, &l);
                };

                let k: u8 = *index;
                // We set imb_ratios[k] = 0 to avoid choosing index k again.
                *vec_map::get_mut(&mut imb_ratios, &k) = 0;

                if (*a_remaining != 0 && *max_imb_ratio != 0) {
                    let factor_k: u256 = get_fact_for_bal(self, k);
                    let ak: u256 =
                        div(
                            mul(
                                *a_remaining * factor_o,
                                *vec_map::get(&prices, &o) * *vec_map::get(&factors_for_prices, &o)
                            ),
                            *vec_map::get(&prices, &k) * *vec_map::get(&factors_for_prices, &k)
                        ) / factor_k;
                    let _Lk: u256 = get_lptok_issued(self, k) * FACTOR_LPT;
                    // Mk = bk-(1.0-DELTA)*Lk*B/L
                    let min_token_k: u256 = div(mul3(_B, _Lk, ONE - DELTA), _L) / factor_k;
                    let max_token_k: u256 = get_bal(self, k) - min_token_k;
                    let amount_out_k: &mut u256 = vec_map::get_mut(&mut amounts_out, &k);

                    if (ak <= max_token_k) {
                        *amount_out_k = *amount_out_k + ak;
                        // The liquidity provider receives `ak` units of token `k`.
                        *a_remaining = 0;
                    };
                    if (ak > max_token_k) {
                        *amount_out_k = *amount_out_k + max_token_k;
                        // The liquidity provider receives `max_token_k` token `k`.
                        // The value of `max_token_k` in terms of token `o` is `max_token_k*prices[k]/prices[o]`
                        let value_max_token_k: u256 =
                            div(
                                mul(
                                    max_token_k * factor_k,
                                    *vec_map::get(&prices, &k) * *vec_map::get(&factors_for_prices, &k)
                                ),
                                *vec_map::get(&prices, &o) * *vec_map::get(&factors_for_prices, &o)
                            ) / factor_o;
                            *a_remaining = *a_remaining - value_max_token_k;
                    };
                };

                l = l + 1;
            };

            j = j + 1;
        };

        WithdrawalOutput {amounts: amounts_out, value: *ao, remaining: *a_remaining}
    }
}