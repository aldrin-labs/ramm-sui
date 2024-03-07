module ramm_sui::ramm {
    use std::type_name::{Self, TypeName};
    use std::vector;

    use sui::bag::{Self, Bag};
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, ID, UID};
    // Sui Move Prover is being sunset: https://github.com/MystenLabs/sui/pull/15480
    //use sui::prover::{OWNED, SHARED};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use switchboard::aggregator::{Self, Aggregator};

    use ramm_sui::events;
    use ramm_sui::oracles;
    use ramm_sui::math as ramm_math;

    friend ramm_sui::interface2;
    friend ramm_sui::interface3;

    const ERAMMInvalidInitState: u64 = 0;
    const EInvalidAggregator: u64 = 1;
    const ENotAdmin: u64 = 2;
    const ENoAssetsInRAMM: u64 = 3;
    const ERAMMNewAssetFailure: u64 = 4;
    const ENotInitialized: u64 = 5;
    const EWrongNewAssetCap: u64 = 6;
    const EBrokenRAMMInvariants: u64 = 7;
    /// A trade's inbound amount exceeded the set maximum (MU).
    const ETradeExcessAmountIn: u64 = 8;
    /// A trade's outbound amount exceeded the set maximum (MU).
    const ETradeExcessAmountOut: u64 = 9;

    const ERAMMAlreadyInitialized: u64 = 10;

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
    //const LP_TOKENS_DECIMAL_PLACES: u8 = 9;

    /// Factor to apply to LP token amounts during calculations.
    const FACTOR_LPT: u256 = 1_000_000_000_000 / 1_000_000_000; // FACTOR_LPT = 10**(PRECISION_DECIMAL_PLACES-LP_TOKENS_DECIMAL_PLACES)
    /// Value of `1` using `PRECISION_DECIMAL_PLACES`; useful to scale other values to
    /// the baseline precision.
    ///
    /// Sui Move does not permit using constants in other constants' definitions, so
    /// `ONE` will need to be hardcoded.
    const ONE: u256 = 1_000_000_000_000;

    /// Miguel's note:
    ///
    /// * Maximum permitted deviation of the imbalance ratios from 1.0.
    /// * 2 decimal places are considered.
    ///
    /// Hence, DELTA=25 is interpreted as 0.25
    const DELTA: u256 = 25 * 1_000_000_000_000 / 100; // DELTA = _DELTA * 10**(PRECISION_DECIMAL_PLACES-2)
    /// Value mu \in ]0, 1[ that dictates the maximum size a trade can have.
    /// Here, mu = 0.05, meaning trades cannot use more than 5% of the RAMM's balances at once.
    const MU: u256 = 5 * 1_000_000_000_000 / 100; // _MU * 10**(PRECISION_DECIMAL_PLACES-2)
    /// Value, in seconds, of the maximum permitted difference between oracle price information
    /// that will trigger a volatility parameter update.
    const TAU: u64 = 300;
    /// Leverage in the RAMM serves to offer better prices to trade(r)s that help rebalance the
    /// pool's balances than to those that further unbalance it.
    ///
    /// A value of `100` for the base leverage means 100% of the theoretically expected liquidity
    /// for a given trade will be used - this is then used to calculate the trade's dynamic leverage.
    const BASE_LEVERAGE: u256 = 100 * 1_000_000_000_000; // BASE_LEVERAGE = _BASE_LEVERAGE * ONE

    /// Base fee in basis points: a value of 10 means 0.001 or 0.1%
    const BASE_FEE: u256 = 10 * 1_000_000_000_000 / 10000; // _BASE_FEE * 10**(PRECISION_DECIMAL_PLACES-4)
    /// Base liquidity withdrawal fee; a value of 40 means 0.004, or 0.4%.
    ///
    /// This will be a protocol fee, meaning that the amount charged will not go to the pool, but 
    /// instead will be kept aside for the protocol owners.
    const BASE_WITHDRAWAL_FEE: u256 = 40 * 1_000_000_000_000 / 10000; // _BASE_WITHDRAWAL_FEE * 10**(PRECISION_DECIMAL_PLACES-4)
    /// 30% of collected base fees go to the RAMM.
    const PROTOCOL_FEE: u256 = 30 * 1_000_000_000_000 / 100; // PROTOCOL_FEE = _PROTOCOL_FEE*10**(PRECISION_DECIMAL_PLACES-2)

    /// Maximum age, in miliseconds, that an asset's pricing data can have - relative to a timestamp
    /// obtained from Sui's global `sui::Clock`, residing at address `0x6`.
    const PRICE_TIMESTAMP_STALENESS_THRESHOLD: u64 = 60 * 60 * 1000;

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

    /// Transfer a RAMM's admin capability to another address.
    ///
    /// This function is required for an admin to transfer the admin cap of a RAMM they control
    /// to another of their addresses. If this function were not exposed, because `RAMMAdminCap`
    /// does not (and should not) have the `store` ability, then it would be impossible to use
    /// `sui::transfer::{public_transfer, transfer}` to transfer the admin cap.
    ///
    /// For more information, see the official Sui docs: https://docs.sui.io/concepts/transfers/custom-rules
    ///
    /// Note that because the admin cap is passed in by value, only an address with prior ownership
    /// of an admin cap can transfer it to another address.
    public fun transfer_admin_cap(admin_cap: RAMMAdminCap, recipient: address) {
        transfer::transfer(admin_cap, recipient);
    }

    /// Capability to add assets to the RAMM pool.
    ///
    /// When the pool is initialized, it must be deleted.
    ///
    /// This cap cannot be transferred between addresses - it lacks a custom transfer
    /// function like `transfer_admin_cap`, and it does not have `store` either.
    /// This is by design, as it is not intended for a RAMM to be created and remain without assets
    /// for long, and disallowing transfer of this cap disincentivizes delays.
    struct RAMMNewAssetCap has key { id: UID }

    /// RAMM data structure, allows
    /// * adding/removing liquidity for one of its assets
    /// * buying an amount of one of its assets in exchange for another
    /// * selling an amount of one of its assets in exchange for another
    ///
    /// The structure is shared, so that any address is be able to submit requests.
    /// It is, therefore, publicly available for reads and writes.
    /// As such, it must have the `key` ability, becoming a Sui
    /// Move object, and thus allowing use of `sui::transfer::share_object`.
    ///
    /// # Invariants
    ///
    /// It should be possible to create a RAMM with any amount of assets, and
    /// to abstract over the assets themselves.
    ///
    /// Because of limitations with Sui Move's type system, in order to do this
    /// and still have a degree of generality in the code, it is necessary to
    /// store certain information twice, in an untyped, scalar format e.g. `u256`,
    /// and in a typed format, e.g. `Balance<Asset>`.
    ///
    /// This information is:
    /// * per-asset balance information
    /// * per-asset LP token `Supply` structures
    ///
    /// It is *critical* that these mirrored fields move in lockstep; if this
    /// invariant is broken, the RAMM has been compromised and should not process
    /// any further operations.
    ///
    /// See this repository's README for more information.
    struct RAMM has key {
        // UID of a `RAMM` object. Required for `RAMM` to have the `key` ability,
        // and ergo become a shared object.
        id: UID,

        /*
        -----------------------------
        Administration `Cap`abilities
        -----------------------------
        */

        // ID of the `AdminCap` required to perform sensitive operations.
        // Not storing this field means any admin of any RAMM can affect any
        // other - not good.
        admin_cap_id: ID,
        // ID of the cap used to add new assets.
        // Used to flag whether a RAMM has been initialized or not.
        new_asset_cap_id: ID,
        // * Before initialization, deposits cannot be made, and cannot be enabled.
        //   - the field must be `false` before initialization
        // * After initialization, no more assets can be added.
        //   - thenceforth and until the RAMM object is deleted, the field will be `true`
        is_initialized: bool,

        /*
        --------------
        Fee collection
        --------------
        */

        // Map from asset indexes `u8` to fees collected over that asset, `Balance<T>`
        collected_protocol_fees: Bag,
        // Address of the fee to which `Coin<T>` objects representing collected
        // fees will be sent.
        fee_collector: address,

        /*
        --------------
        Asset metadata
        --------------
        */

        // Total number of assets in the RAMM pool. `N` in the whitepaper.
        asset_count: u8,
        // per-asset flag marking whether deposits are enabled.
        deposits_enabled: VecMap<u8, bool>,
        // Scaling factor for each of the assets, used to bring their values to the baseline
        // order of magnitude, using `PRECISION_DECIMAL_PLACES`.
        //
        // Every coin has its decimal place count specified in its `CoinMetadata` structure.
        // This value is used upon asset insertion to calculate the right factor.
        //
        // Cannot be changed.
        factors_for_balances: VecMap<u8, u256>,
        // minimum trading amounts for each token.
        minimum_trade_amounts: VecMap<u8, u64>,
        // Mapping between the type names of this pool's assets, and their indexes;
        // used to index other maps in the `RAMM` structure.
        //
        // Each `TypeName` will be of the form `<package-id>::<module>::<type-name>`.
        // E.g. `SUI`'s `TypeName` is `0x2::sui::SUI`.
        // Because Sui packages are treated as immutable objects with unique IDs,
        // the function `type_name::get<T>: () -> TypeName` is a bijection between
        // types `T` and their `TypeName`s (which internally are `String`s).
        //
        // Done for storage considerations: storing type names in every single
        // map/bag as keys is unwieldy.
        types_to_indexes: VecMap<TypeName, u8>,

        /*
        -----------------------------------
        Oracle data and Pricing Information
        -----------------------------------
        */

        // map from `u8` -> `switchboard::Aggregator::address`; this address is derived
        // from the aggregator's UID.
        aggregator_addrs: VecMap<u8, address>,
        // map between each asset's index and its most recently queried price, obtained
        // from the asset's `Aggregator`, whose address is in `aggregator_addrs`
        previous_prices: VecMap<u8, u256>,
        // map between each asset's index and the timestamp of its most recently queried price,
        previous_price_timestamps: VecMap<u8, u64>,
        // map between each asset's index and the highest recorded volatility index in
        // the last `TAU` seconds.
        volatility_indices: VecMap<u8, u256>,
        // map between each asset's index and the timestamp of its highest recorded
        // volatility in the last `TAU` seconds.
        volatility_timestamps: VecMap<u8, u64>,

        /*
        ------------------
        Asset balance data
        ------------------
        */

        // Map from asset indexes, `u8`, to untyped balances, `u256`.
        // Both typed and untyped balances are required due to limitations with Sui Move.
        //
        // These balances are not scaled - they are `u256` representations of the `balance::value`
        // of each asset's `Balance<T>`.
        balances: VecMap<u8, u256>,
        // Map from asset indexes `u8` to their respective balances, `Balance<T>`
        typed_balances: Bag,

        /*
        -----------------
        LP Token issuance
        -----------------
        */

        // Map from asset indexes, `u8`, to untyped counts of issued LP tokens for that
        // asset, in `u256`.
        //
        // These balances do not have any scale applied to them, like what happens with `balances`.
        lp_tokens_issued: VecMap<u8, u256>,
        // Map from asset indices, `u8`, to LP token supply data - `Supply<T>`.
        // From `Supply<T>` it is possible to mint, burn and query issued tokens.
        typed_lp_tokens_issued: Bag,
    }

    /*
    ------------------
    Trading operations
    ------------------
    */

    const SUCCESS: u8 = 0;
    const FAILED_POOL_IMBALANCE: u8 = 1;
    const FAILED_INSUFFICIENT_OUT_TOKEN_BALANCE: u8 = 2;
    const FAILED_LOW_OUT_TOKEN_IMB_RATIO: u8 = 3;

    /// Code for a successful trade i.e. one which the RAMM can execute.
    public(friend) fun success(): u8 {
        SUCCESS
    }

    public(friend) fun failed_pool_imbalance(): u8 {
        FAILED_POOL_IMBALANCE
    }

    public(friend) fun failed_insufficient_out_token_balance(): u8 {
        FAILED_INSUFFICIENT_OUT_TOKEN_BALANCE
    }

    public(friend) fun failed_low_out_token_imb_ratio(): u8 {
        FAILED_LOW_OUT_TOKEN_IMB_RATIO
    }

    /// Returns `true` if a trade has been greenlit by the protocol's checks, and `false` if not.
    ///
    /// `false` can be returned for various reasons, such as:
    /// 1. not enough pool balances to execute the trade
    /// 2. it may fail due to imbalance ratio checks
    ///
    /// Note that even if the trade is classified "successful", it is possible the trade is not
    /// executed - because the `TradeOutput`'s `amount` does not conform to the trader's slippage
    /// tolerance, for example.
    public(friend) fun is_successful(to: &TradeOutput): bool {
        to.trade_outcome == success()
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
        trade_outcome: u8,
    }

    /// Return a `TradeOutput`'s calculated amount - might be `0`, depending on the `execute`
    /// flag.
    public(friend) fun amount(to: &TradeOutput): u256 {
        to.amount
    }

    /// Return a trade's calculated protocol fees.
    public(friend) fun protocol_fee(to: &TradeOutput): u256 {
        to.protocol_fee
    }

    /// Return a `TradeOutput`'s trade outcome, represented as a `u8`:
    /// * `0` for success
    /// * `1, 2, ...` for different types of failure.
    public(friend) fun trade_outcome(to: &TradeOutput): u8 {
        to.trade_outcome
    }

    /// Result of a liquidity withdrawal by a trader that had previously deposited
    /// liquidity into the pool.
    ///
    /// Contains:
    /// * the amount of each of the pool's assets the trader will receive for his LP tokens
    /// * the value of liquidity withdrawal fee applied to each asset, 0.4% of the amount
    /// * the total value of the redeemed tokens
    /// * the remaining value
    struct WithdrawalOutput has drop {
        amounts: VecMap<u8, u256>,
        fees: VecMap<u8, u256>,
        value: u256,
        remaining: u256
    }

    /// Return a `WithdrawalOutput's` mapping of assets to liquidity withdrawal values
    /// for that asset.
    public(friend) fun amounts(wo: &WithdrawalOutput): VecMap<u8, u256> {
        wo.amounts
    }

    /// Return a `WithdrawalOutput's` mapping of assets to liquidity withdrawal fees
    /// for that asset.
    public(friend) fun fees(wo: &WithdrawalOutput): VecMap<u8, u256> {
        wo.fees
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

    public fun mul(x: u256, y: u256): u256 {
        ramm_math::mul(x, y, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public fun mul3(x: u256, y: u256, z: u256): u256 {
        ramm_math::mul3(x, y, z, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public fun div(x: u256, y: u256): u256 {
        ramm_math::div(x, y, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public fun pow_n(x: u256, n: u256): u256 {
        ramm_math::pow_n(x, n, ONE, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public fun pow_d(x: u256, a: u256): u256 {
        ramm_math::pow_d(x, a, ONE, PRECISION_DECIMAL_PLACES, MAX_PRECISION_DECIMAL_PLACES)
    }

    public fun power(x: u256, a: u256): u256 {
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
    /// A RAMM needs to have assets added to it before it can be initialized,
    /// after which it can be used.
    ///
    /// # Return value:
    ///
    /// This function returns nothing.
    /// If the transaction block in which it is called is successful, a shared RAMM object will
    /// have been created, and the required capabilities will have been transferred to the caller's
    /// address.
    public fun new_ramm(
        fee_collector: address,
        ctx: &mut TxContext
    ) {
        let admin_cap_uid: UID = object::new(ctx);
        let admin_cap_id: ID = object::uid_to_inner(&admin_cap_uid);
        let admin_cap: RAMMAdminCap = RAMMAdminCap { id: admin_cap_uid };

        let new_asset_cap_uid: UID = object::new(ctx);
        let new_asset_cap_id: ID = object::uid_to_inner(&new_asset_cap_uid);
        let new_asset_cap: RAMMNewAssetCap = RAMMNewAssetCap { id: new_asset_cap_uid };

        let ramm_uid: UID = object::new(ctx);
        let ramm_init = RAMM {
                id: ramm_uid,

                admin_cap_id,
                new_asset_cap_id,
                is_initialized: false,

                collected_protocol_fees: bag::new(ctx),
                fee_collector,

                asset_count: 0,
                deposits_enabled: vec_map::empty<u8, bool>(),
                factors_for_balances: vec_map::empty<u8, u256>(),
                minimum_trade_amounts: vec_map::empty<u8, u64>(),
                types_to_indexes: vec_map::empty<TypeName, u8>(),

                aggregator_addrs: vec_map::empty<u8, address>(),
                previous_prices: vec_map::empty<u8, u256>(),
                previous_price_timestamps: vec_map::empty<u8, u64>(),
                volatility_indices: vec_map::empty<u8, u256>(),
                volatility_timestamps: vec_map::empty<u8, u64>(),

                balances: vec_map::empty<u8, u256>(),
                typed_balances: bag::new(ctx),

                lp_tokens_issued: vec_map::empty<u8, u256>(),
                typed_lp_tokens_issued: bag::new(ctx),
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
        let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, admin);
        let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, admin);

        assert!(ramm.admin_cap_id == object::id(&admin_cap), ERAMMInvalidInitState);
        assert!(ramm.new_asset_cap_id == object::id(&new_asset_cap), ERAMMInvalidInitState);
        assert!(!ramm.is_initialized, ERAMMInvalidInitState);

        assert!(ramm.fee_collector == admin, ERAMMInvalidInitState);
        assert!(bag::is_empty(&ramm.collected_protocol_fees), ERAMMInvalidInitState);

        assert!(ramm.asset_count == 0, ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, bool>(&ramm.deposits_enabled), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, u256>(&ramm.factors_for_balances), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, u64>(&ramm.minimum_trade_amounts), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<TypeName, u8>(&ramm.types_to_indexes), ERAMMInvalidInitState);

        assert!(vec_map::is_empty<u8, address>(&ramm.aggregator_addrs), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, u256>(&ramm.previous_prices), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, u64>(&ramm.previous_price_timestamps), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, u256>(&ramm.volatility_indices), ERAMMInvalidInitState);
        assert!(vec_map::is_empty<u8, u64>(&ramm.volatility_timestamps), ERAMMInvalidInitState);

        assert!(vec_map::is_empty<u8, u256>(&ramm.balances), ERAMMInvalidInitState);
        assert!(bag::is_empty(&ramm.typed_balances), ERAMMInvalidInitState);

        assert!(vec_map::is_empty<u8, u256>(&ramm.lp_tokens_issued), ERAMMInvalidInitState);
        assert!(bag::is_empty(&ramm.typed_lp_tokens_issued), ERAMMInvalidInitState);

        test_scenario::return_to_address<RAMMAdminCap>(admin, admin_cap);
        test_scenario::return_to_address<RAMMNewAssetCap>(admin, new_asset_cap);
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
    public fun add_asset_to_ramm<Asset>(
        self: &mut RAMM,
        feed: &Aggregator,
        min_trade_amnt: u64,
        asset_decimal_places: u8,
        admin_cap: &RAMMAdminCap,
        new_asset_cap: &RAMMNewAssetCap,
    ) {
        assert!(self.admin_cap_id == object::id(admin_cap), ENotAdmin);
        assert!(self.new_asset_cap_id == object::id(new_asset_cap), EWrongNewAssetCap);
        assert!(!self.is_initialized, ERAMMAlreadyInitialized);

        let type_name = type_name::get<Asset>();
        let type_index = self.asset_count;

        bag::add(&mut self.collected_protocol_fees, type_index, balance::zero<Asset>());

        self.asset_count = self.asset_count + 1;
        vec_map::insert(&mut self.deposits_enabled, type_index, false);
        let factor_balance: u256 = ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - asset_decimal_places);
        vec_map::insert(&mut self.factors_for_balances, type_index, factor_balance);
        vec_map::insert(&mut self.minimum_trade_amounts, type_index, min_trade_amnt);
        vec_map::insert(&mut self.types_to_indexes, type_name, type_index);

        vec_map::insert(&mut self.aggregator_addrs, type_index, aggregator::aggregator_address(feed));
        vec_map::insert(&mut self.previous_prices, type_index, 0);
        vec_map::insert(&mut self.previous_price_timestamps, type_index, 0);
        vec_map::insert(&mut self.volatility_indices, type_index, 0);
        vec_map::insert(&mut self.volatility_timestamps, type_index, 0);

        vec_map::insert(&mut self.balances, type_index, 0);
        bag::add(&mut self.typed_balances, type_index, balance::zero<Asset>());

        vec_map::insert(&mut self.lp_tokens_issued, type_index, 0);
        bag::add(&mut self.typed_lp_tokens_issued, type_index, balance::create_supply(LP<Asset> {}));

        let n = (self.asset_count as u64);

        assert!(n == bag::length(&self.collected_protocol_fees), ERAMMNewAssetFailure);

        assert!(n == vec_map::size(&self.deposits_enabled), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.factors_for_balances), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.types_to_indexes), ERAMMNewAssetFailure);

        assert!(n == vec_map::size(&self.aggregator_addrs), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.previous_prices), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.previous_price_timestamps), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.volatility_indices), ERAMMNewAssetFailure);
        assert!(n == vec_map::size(&self.volatility_timestamps), ERAMMNewAssetFailure);

        assert!(n == vec_map::size(&self.balances), ERAMMNewAssetFailure);
        assert!(n == bag::length(&self.typed_balances), ERAMMNewAssetFailure);

        assert!(n == vec_map::size(&self.lp_tokens_issued), ERAMMNewAssetFailure);
        assert!(n == bag::length(&self.typed_lp_tokens_issued), ERAMMNewAssetFailure);
    }

    /// Initialize a RAMM pool.
    ///
    /// Its `RAMMNewAssetCap`ability must be passed in by value so that it is destroyed,
    /// preventing new assets from being added to the pool.
    ///
    /// # Aborts
    ///
    /// * If the wrong admin or new asset capabilities are provided.
    /// * if its internal data is inconsistent e.g.
    ///   - there are no assets, or
    ///   - the number of held assets differs from the number of LP token issuers.
    public fun initialize_ramm(
        self: &mut RAMM,
        admin_cap: &RAMMAdminCap,
        new_asset_cap: RAMMNewAssetCap,
    ) {
        assert!(self.admin_cap_id == object::id(admin_cap), ENotAdmin);
        assert!(self.new_asset_cap_id == object::id(&new_asset_cap), EWrongNewAssetCap);
        assert!(self.asset_count > 0, ENoAssetsInRAMM);
        assert!(!self.is_initialized, ERAMMAlreadyInitialized);

        let index_map_size = vec_map::size(&self.types_to_indexes);
        assert!(
            index_map_size > 0 &&
            self.asset_count == (index_map_size as u8) &&
            index_map_size == bag::length(&self.collected_protocol_fees) &&

            index_map_size == vec_map::size(&self.deposits_enabled) &&
            index_map_size == vec_map::size(&self.factors_for_balances) &&
            index_map_size == vec_map::size(&self.minimum_trade_amounts) &&

            index_map_size == vec_map::size(&self.aggregator_addrs) &&
            index_map_size == vec_map::size(&self.previous_prices) &&
            index_map_size == vec_map::size(&self.previous_price_timestamps) &&
            index_map_size == vec_map::size(&self.volatility_indices) &&
            index_map_size == vec_map::size(&self.volatility_timestamps) &&

            index_map_size == vec_map::size(&self.balances) &&
            index_map_size == bag::length(&self.typed_balances) &&

            index_map_size == vec_map::size(&self.lp_tokens_issued) &&
            index_map_size == bag::length(&self.typed_lp_tokens_issued),
            ERAMMInvalidInitState
        );

        let ix = 0;
        while (ix < self.asset_count) {
            set_deposit_status(self, ix, true);
            ix = ix + 1;
        };

        let RAMMNewAssetCap { id: uid } = new_asset_cap;
        object::delete(uid);

        self.is_initialized = true;
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

    /*
    IMPORTANT NOTE

    About getters/setters
    */

    /// The RAMM object uses `u8` indexes to identify each of its assets, which are
    /// then used to index information about that asset: balances, collected fees, etc.
    ///
    /// Sui's type system can be used to safely calculate asset indexes, instead of
    /// relying on end-users/library users to provide them to functions which need them.
    ///
    /// As such, getter/setter functions below come in two kinds:
    ///
    /// * private functions used only internally that receive asset indexes by argument
    /// * public (or `public(friend)`) functions that do not allow asset index arguments,
    ///   and instead accept type arguments which are then used to safely obtain the asset's
    ///   corresponding index, aborting on error
    ///
    /// The latter kind can then rely on the former, while only exposing a type-level API
    /// to consumers of this module, and avoiding error-prone manual asset indexing.

    /// RAMM ID

    /// Return a RAMM's `ID`.
    public(friend) fun get_id(self: &RAMM): ID {
        object::id(self)
    }

    /*
    -----------------------------
    Administration `Cap`abilities
    -----------------------------
    */

    /// Admin cap
    
    /// Return the ID of the RAMM's admin capability.
    public fun get_admin_cap_id(self: &RAMM): ID {
        self.admin_cap_id
    }

    /// New asset cap
    
    /// Returns:
    ///
    /// * `option::some(id)`, where `id: ID` is the ID of the RAMM's new asset capability, *if*
    ///    the RAMM has already been initialized
    /// * `option::none()` if the RAMM has already been initialized.
    public fun get_new_asset_cap_id(self: &RAMM): ID {
        self.new_asset_cap_id
    }

    /*
    --------------
    Fee collection
    --------------
    */

    /// Fee collector address

    /// Return the `address` to which this RAMM will send collected protocol operation fees.
    public fun get_fee_collector(self: &RAMM): address {
        self.fee_collector
    }

    /// Change a RAMM's fee collection address.
    ///
    /// Callable on RAMMs of arbitrary size.
    ///
    /// # Aborts
    ///
    /// If called with the wrong admin capability object.
    public fun set_fee_collector(self: &mut RAMM, admin_cap: &RAMMAdminCap, new_fee_addr: address) {
        assert!(self.admin_cap_id == object::id(admin_cap), ENotAdmin);
        self.fee_collector = new_fee_addr;
    }

    /// Obtain the untyped (`u64`) value of fees collected by the RAMM for a certain asset.
    ///
    /// To be used only by other functions in this module.
    fun get_fees<Asset>(self: &RAMM, index: u8): u64 {
        let fee_balance: &Balance<Asset> = bag::borrow<u8, Balance<Asset>>(&self.collected_protocol_fees, index);
        balance::value(fee_balance)
    }

    /// Returns the untyped (`u64`) value of fees collected by the RAMM for a given asset.
    public fun get_collected_protocol_fees<Asset>(self: &RAMM): u64 {
        let ix = get_asset_index<Asset>(self);
        get_fees<Asset>(self, ix)
    }

    /// Internal function to retrieve fees for an asset.
    ///
    /// It returns a `Balance<Asset>` with the RAMM's fees, and leaves behind a zero `Balance`
    /// in the `Bag` the RAMM uses to store fees.
    ///
    /// The reason it does this:
    ///
    /// * The size of the bag with collected fees should always be equal to the number of assets
    ///   in the RAMM;
    /// * as such, instead of removing the `Balance` struct, it is mutably borrowed, and then
    ///   `balance::split` in such a way that
    ///   - `balance::zero<Asset>` is left in the bag
    ///   - the original balance is returned
    public(friend) fun get_fees_for_asset<Asset>(self: &mut RAMM, ix: u8): Balance<Asset> {
        let mut_bal: &mut Balance<Asset> =
            bag::borrow_mut<u8, Balance<Asset>>(&mut self.collected_protocol_fees, ix);
        let curr_fee = balance::value(mut_bal);
        balance::split(mut_bal, curr_fee)
    }

    /// Increase the RAMM's collected fees for a certain asset given a `Balance` of it.
    public(friend) fun join_protocol_fees<Asset>(self: &mut RAMM, index: u8, fee: Balance<Asset>) {
        let fee_bal = bag::borrow_mut<u8, Balance<Asset>>(&mut self.collected_protocol_fees, index);
        balance::join(fee_bal, fee);
    }

    /*
    --------------
    Asset metadata
    --------------
    */

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
    public fun set_minimum_trade_amount<Asset>(
        self: &mut RAMM,
        admin_cap: &RAMMAdminCap,
        new_min: u64
    ) {
        assert!(self.admin_cap_id == object::id(admin_cap), ENotAdmin);

        let ix = get_asset_index<Asset>(self);
        *vec_map::get_mut(&mut self.minimum_trade_amounts, &ix) = new_min
    }

    /// Deposit status

    /// Change deposit permission status for a single asset in the RAMM.
    ///
    /// Private visibility, since this action should not be performed without a
    /// `RAMMAdminCap`
    fun set_deposit_status(self: &mut RAMM, index: u8, deposit_enabled: bool) {
        *vec_map::get_mut(&mut self.deposits_enabled, &index) = deposit_enabled
    }

    /// For a given asset, returns true iff its deposits are enabled.
    ///
    /// # Aborts
    ///
    /// * If no asset has the provided index
    public(friend) fun can_deposit_asset(self: &RAMM, index: u8): bool {
        *vec_map::get(&self.deposits_enabled, &index)
    }

    /// Function that allows a RAMM's admin to enable deposits for an asset.
    ///
    /// # Aborts
    /// * If called with the wrong admin capability object
    /// * If the RAMM has not been initialized
    /// * If the RAMM does not have an asset with the provided type
    public fun enable_deposits<Asset>(self: &mut RAMM, admin_cap: &RAMMAdminCap) {
        assert!(self.admin_cap_id == object::id(admin_cap), ENotAdmin);
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
    public fun disable_deposits<Asset>(self: &mut RAMM, admin_cap: &RAMMAdminCap) {
        assert!(self.admin_cap_id == object::id(admin_cap), ENotAdmin);
        assert!(is_initialized(self), ENotInitialized);

        let ix = get_asset_index<Asset>(self);
        set_deposit_status(self, ix, false)
    }

    /// Given an asset, return a `bool` representing the RAMM's deposit status for that
    /// asset: `true` for enabled, `false` for disabled.
    ///
    /// # Aborts
    ///
    /// If the RAMM does not contain an asset with the provided type.
    public fun get_deposit_status<Asset>(self: &RAMM): bool {
        let ix = get_asset_index<Asset>(self);
        can_deposit_asset(self, ix)
    }

    /*
    -----------------------------------
    Oracle data and Pricing Information
    -----------------------------------
    */

    /// Aggregator addresses

    /// Given a RAMM and the index of one of its assets, return the `address` of
    /// the `Aggregator` used for pricing information for that asset.
    ///
    /// # Aborts
    ///
    /// If the provided index does not match any existing asset's.
    fun get_aggr_addr(self: &RAMM, index: u8): address {
        *vec_map::get(&self.aggregator_addrs, &index)
    }

    /// Return the Switchboard aggregator address for a given asset.
    public fun get_aggregator_address<Asset>(self: &RAMM): address {
        let ix = get_asset_index<Asset>(self);
        get_aggr_addr(self, ix)
    }

    /// Given a RAMM, the index of one of its assets and a new `Aggregator` address,
    /// update the address of that asset's aggregator in the RAMM with the provided one.
    ///
    /// # Aborts
    ///
    /// If the provided index does not match any existing asset's.
    fun set_aggr_addr(self: &mut RAMM, index: u8, new_addr: address) {
        *vec_map::get_mut(&mut self.aggregator_addrs, &index) = new_addr;
    }

    /// Update the address of an asset's aggregator in the RAMM with the provided one.
    public fun set_aggregator_address<Asset>(self: &mut RAMM, admin_cap: &RAMMAdminCap, new_addr: address) {
        assert!(self.admin_cap_id == object::id(admin_cap), ENotAdmin);

        let ix = get_asset_index<Asset>(self);
        set_aggr_addr(self, ix, new_addr);
    }

    /// Given a RAMM and the index of one of its assets, return the last previously recorded
    /// price of the asset.
    ///
    /// # Aborts
    ///
    /// If the provided index does not match any existing asset's.
    public(friend) fun get_prev_prc(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.previous_prices, &index)
    }

    /// Given a RAMM, return the last previously recorded price of an asset.
    public fun get_previous_price<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_prev_prc(self, ix)
    }

    /// Given a RAMM, the index of one of its assets, and its new price queried from an aggregator,
    /// update the RAMM's internal state.
    ///
    /// # Aborts
    ///
    /// If the provided index does not match any existing asset's.
    fun set_prev_prc(self: &mut RAMM, ix: u8, new_price: u256) {
        *vec_map::get_mut(&mut self.previous_prices, &ix) = new_price;
    }

    /// Given a RAMM, an asset and its new price queried from an aggregator, update the RAMM's
    /// internal state.
    public(friend) fun set_previous_price<Asset>(self: &mut RAMM, new_price: u256) {
        let ix = get_asset_index<Asset>(self);
        set_prev_prc(self, ix, new_price)
    }

    /// Given a RAMM and the index of one of its assets, return the timestamp of the last
    /// price obtained for the asset from its `Aggregator`.
    ///
    /// # Aborts
    ///
    /// If the provided index does not match any existing asset's.
    public(friend) fun get_prev_prc_tmstmp(self: &RAMM, index: u8): u64 {
        *vec_map::get(&self.previous_price_timestamps, &index)
    }

    /// Given a RAMM, return the timestamp of the last price obtained for an asset from its
    /// `Aggregator`.
    public fun get_previous_price_timestamp<Asset>(self: &RAMM): u64 {
        let ix = get_asset_index<Asset>(self);
        get_prev_prc_tmstmp(self, ix)
    }

    /// Given a RAMM, the index of one of its assets and a timestamp for its most recently
    /// queried price data, update the RAMM's internal state.
    ///
    /// # Aborts
    ///
    /// If the provided index does not match any existing asset's.
    fun set_prev_prc_tmstmp(
        self: &mut RAMM,
        ix: u8,
        new_price_timestamp: u64
    ) {
        *vec_map::get_mut(&mut self.previous_price_timestamps, &ix) = new_price_timestamp;
    }

    /// Given a RAMM, one of its assets and a timestamp for its most recently queried price data,
    /// update the RAMM's internal state.
    public(friend) fun set_previous_price_timestamp<Asset>(
        self: &mut RAMM,
        new_price_timestamp: u64
    ) {
        let ix = get_asset_index<Asset>(self);
        set_prev_prc_tmstmp(self, ix, new_price_timestamp);
    }

    /// Volatility indices

    /// Given a RAMM and the index of one of its assets, return its latest calculated volatility
    /// index.
    ///
    /// The result is a percentage encoded with `PRECISION_DECIMAL_PLACES`.
    ///
    /// If none has yet been calculated, it'll be 0.
    ///
    /// # Aborts
    ///
    /// If the provided index does not match any existing asset's.
    fun get_vol_ix(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.volatility_indices, &index)
    }

    /// Return an asset's most recent volatility index (0 if none has yet been calculated).
    ///
    /// The result is a percentage encoded with `PRECISION_DECIMAL_PLACES`.
    public fun get_volatility_index<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_vol_ix(self, ix)
    }

    /// Volatility index timestamps

    /// Given a RAMM and the index of one of its assets, return the timestamp of its
    /// latest volatility index. If none has yet been calculated, it'll be 0.
    ///
    /// # Aborts
    ///
    /// If the provided index does not match any existing asset's.
    fun get_vol_tmstmp(self: &RAMM, index: u8): u64 {
        *vec_map::get(&self.volatility_timestamps, &index)
    }

    /// Return the timestamp of an asset's most recent volatility index (0 if none yet exists).
    public fun get_volatility_timestamp<Asset>(self: &RAMM): u64 {
        let ix = get_asset_index<Asset>(self);
        get_vol_tmstmp(self, ix)
    }

    /*
    ------------------
    Asset balance data
    ------------------
    */

    /// Untyped balances

    /// Get an asset's typed balance, meaning the untyped, pure scalar value (`u256`) used
    /// internally by the RAMM to represent an asset's balance.
    public(friend) fun get_bal(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.balances, &index)
    }

    /// Getter for an asset's untyped balance.
    /// The asset index is not passed in, but instead obtained through the type parameter for safety.
    public fun get_balance<Asset>(self: &RAMM): u256 {
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
    public fun get_typed_balance<Asset>(self: &RAMM): u256 {
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

    /*
    -----------------
    LP Token issuance
    -----------------
    */

    /// LP Tokens Issued

    /// Given an asset's index, return how many LP tokens for that asset are currently
    /// in circulation.
    ///
    /// # Aborts
    ///
    /// * If the provided index matches no asset
    fun get_lptok_issued(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.lp_tokens_issued, &index)
    }

    /// Given an asset, return how many LP tokens for that asset are currently
    /// in circulation.
    ///
    /// # Aborts
    ///
    /// * If the provided asset does not exist in the RAMM.
    public fun get_lptokens_issued<Asset>(self: &RAMM): u256 {
        let ix = get_asset_index<Asset>(self);
        get_lptok_issued(self, ix)
    }

    /// Update untyped count of issued LP tokens for a given asset.
    ///
    /// It is the user's responsibility to ensure that there is also an
    /// update to the typed count for this token.
    public(friend) fun incr_lptokens_issued<Asset>(self: &mut RAMM, minted: u64) {
        let ix = get_asset_index<Asset>(self);
        let lptoks = vec_map::get_mut(&mut self.lp_tokens_issued, &ix);
        *lptoks = *lptoks + (minted as u256);
    }

    /// Update untyped count of issued LP tokens for a given asset.
    ///
    /// It is the user's responsibility to ensure that there is also an
    /// update to the typed count for this token.
    public(friend) fun decr_lptokens_issued<Asset>(self: &mut RAMM, burned: u64) {
        let ix = get_asset_index<Asset>(self);
        let lptoks = vec_map::get_mut(&mut self.lp_tokens_issued, &ix);
        *lptoks = *lptoks - (burned as u256);
    }

    /// Typed LP Tokens Issued

    /// Given an asset, return a *mutable* reference to the `Supply` used to
    /// tally/mint/burn the RAMM's LP tokens for that asset.
    ///
    /// Internal use only!
    fun get_lptoken_supply<Asset>(self: &mut RAMM): &mut Supply<LP<Asset>> {
        let ix = get_asset_index<Asset>(self);
        bag::borrow_mut<u8, Supply<LP<Asset>>>(&mut self.typed_lp_tokens_issued, ix)
    }

    /// Given an asset's index, return the untyped count of issued LP tokens for that asset.
    ///
    /// # Aborts
    ///
    /// * If the index does not index any asset.
    fun get_typed_lptok_issued<Asset>(self: &RAMM, index: u8): u256 {
        let supply = bag::borrow<u8, Supply<LP<Asset>>>(&self.typed_lp_tokens_issued, index);
        (balance::supply_value(supply) as u256)
    }

    /// Given an asset, return the untyped count of issued LP tokens for that asset.
    ///
    /// # Aborts
    ///
    /// * If the RAMM does not contain the provided asset
    public fun get_typed_lptokens_issued<Asset>(self: &RAMM): u256 {
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

    /// Type indexes

    /// Given an asset, return its unique index used internally by the RAMM.
    ///
    /// # Aborts
    ///
    /// * If the RAMM does not have an asset with the provided type.
    public fun get_type_index<Asset>(self: &RAMM): u8 {
        *vec_map::get(&self.types_to_indexes, &type_name::get<Asset>())
    }

    /// Asset decimal places

    /// Given an asset's index, return the scaling factor necessary when working with
    /// amounts of that asset to bring it to `PRECISION_DECIMAL_PLACES`.
    ///
    /// # Aborts
    ///
    /// * If the index doesn't many any asset
    public(friend) fun get_fact_for_bal(self: &RAMM, index: u8): u256 {
        *vec_map::get(&self.factors_for_balances, &index)
    }

    /// Given an asset, return the scaling factor necessary when working with
    /// amounts of that asset to bring it to `PRECISION_DECIMAL_PLACES`.
    ///
    /// # Aborts
    ///
    /// * If the RAMM does not contain the provided asset.
    public fun get_factor_for_balance<Asset>(self: &RAMM): u256{
        let ix = get_asset_index<Asset>(self);
        get_fact_for_bal(self, ix)
    }

    /// Asset count

    /// Return the number of assets in the RAMM.
    public fun get_asset_count(self: &RAMM): u8 {
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
        self.is_initialized
    }

    /// Given a RAMM, emit an event to the network with the information:
    /// 1. the types of the RAMM's assets
    /// 2. the balances for each asset
    /// 3. the number of issued LP tokens for each asset
    public fun get_pool_state(
        self: &RAMM,
        ctx: &TxContext
    ) {
        let asset_types: vector<TypeName> = vec_map::keys(&self.types_to_indexes);

        // The vectors can't be `copy`ed, `vec_map::values` does not exist, and
        // `vec_map::into_keys_values` shouldn't be used, as by traversing the balance vectors, it
        // is certain the balances will be in the correct order.
        let i = 0;
        let asset_balances: vector<u256> = vector::empty();
        let asset_lpt_issued: vector<u256> = vector::empty();
        while (i < self.asset_count) {
            vector::push_back(&mut asset_balances, get_bal(self, i));
            vector::push_back(&mut asset_lpt_issued, get_lptok_issued(self, i));
            i = i + 1;
        };

        events::pool_state_event(
            object::uid_to_inner(&self.id),
            tx_context::sender(ctx),
            asset_types,
            asset_balances,
            asset_lpt_issued
        )
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

    /// Check if the amount of a trade's inbound asset does not exceed `MU` (as a percentage)
    /// of the RAMM's balance for that asset.
    ///
    /// The value of `MU` is to be taken as a percentage.
    public(friend) fun check_trade_amount_in<Asset>(self: &RAMM, amount_in: u256) {
        let cmp: u256 = mul(div(MU, ONE - MU), get_typed_balance<Asset>(self));
        assert!(amount_in <= cmp, ETradeExcessAmountIn);
    }

    /// Check if the amount of a trade's outbound asset does not exceed `MU` (as a percentage)
    /// of the RAMM's balance for that asset.
    ///
    /// The value of `MU` is to be taken as a percentage.
    public(friend) fun check_trade_amount_out<Asset>(self: &RAMM, amount_out: u256) {
        let cmp: u256 = mul(get_typed_balance<Asset>(self), MU);
        assert!(amount_out <= cmp, ETradeExcessAmountOut);
    }

    /// Helper function used in liquidity withdrawal public interfaces. Reduces boilerplate.
    ///
    /// After the amounts/fees are calculated for each asset in a `WithdrawalOutput`, they are
    /// iterated over, with this function responsible for doing, for each asset:
    /// 1. Deducting the calculated fee (`f`) from the calculated withdrawal amount (`a`)
    /// 2. Deducting `a` from the RAMM's reserves, and creating a `Coin` object from it (`c`)
    /// 3. Incrementing the RAMM's collected fees with `f`
    /// 4. Returning `c` to be transferred by the calling function
    public(friend) fun liq_withdraw_helper<Asset>(
        // RAMM
        self: &mut RAMM,
        ix: u8,
        amount_out: u256,
        liq_withdrawal_fee: u256,
        ctx: &mut TxContext): Coin<Asset>
    {
        // First, deduct the untyped balance to be withdrawn to the provider
        split_bal(self, ix, amount_out);
        // Next, deduct the liquidity withdrawal protocol fee for the RAMM
        split_bal(self, ix, liq_withdrawal_fee);

        // Next, deduct the typed `Balance`, and turn it into a `Coin`
        let amount_out: Balance<Asset> = split_typed_bal(self, ix, (amount_out as u64));
        let amount_out: Coin<Asset> = coin::from_balance(amount_out, ctx);

        // Transform the withdrawal fee into a `Balance`, and award it to the RAMM
        let protocol_fee: Balance<Asset> = split_typed_bal(self, ix, (liq_withdrawal_fee as u64));
        join_protocol_fees(self, ix, protocol_fee);

        amount_out
    }

    /// Given a RAMM, an asset, and new pricing data, namely:
    /// * a new price queried from its `Aggregator`, and
    /// * its timestamp,
    ///
    /// update that asset's data in the RAMM's internal state.
    public(friend) fun update_pricing_data<Asset>(
        self: &mut RAMM,
        new_price: u256,
        new_price_timestamp: u64
    ) {
        let ix: u8 = get_asset_index<Asset>(self);
        set_prev_prc(self, ix, new_price);
        set_prev_prc_tmstmp(self, ix, new_price_timestamp);
    }

    /// ------------------------
    /// Oracle related functions
    /// ------------------------

    /// Check that the address provided for an asset's pricing oracle
    /// is the same as the one in the RAMM's state.
    ///
    /// If provided with an aggregator for an asset that does not exist in the
    /// pool, it will abort.
    fun check_feed_address(self: &RAMM, index: u8, feed: &Aggregator): bool {
        let addr = vec_map::get(&self.aggregator_addrs, &index);
        *addr == aggregator::aggregator_address(feed)
    }

    /// Verify that the address of the pricing feed for a certain asset matches the
    /// one supplied when the asset was initialized in the RAMM.
    /// It takes a timestamp from the network's global clock to check the staleness of the
    /// pricing data - if the data are too old, the function will abort.
    ///
    /// If it is, fetch its price and that price's timestamp, and add them to the mappings
    /// * from asset indices to their prices
    /// * from asset indices to their prices' timestamps
    /// * from asset indices to their prices' scaling factors
    ///
    /// These maps are passed into the function as mutable arguments.
    public(friend) fun check_feed_and_get_price_data(
        self: &RAMM,
        current_timestamp: u64,
        ix: u8,
        feed: &Aggregator,
        prices: &mut VecMap<u8, u256>,
        factors_for_prices: &mut VecMap<u8, u256>,
        price_timestamps: &mut VecMap<u8, u64>,
    ) {
        assert!(check_feed_address(self, ix, feed), EInvalidAggregator);
        let (price, factor_for_price, price_timestamp) = oracles::get_price_from_oracle(
            feed,
            current_timestamp,
            PRICE_TIMESTAMP_STALENESS_THRESHOLD,
            PRECISION_DECIMAL_PLACES
        );
        vec_map::insert(prices, ix, price);
        vec_map::insert(price_timestamps, ix, price_timestamp);
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

    /// Returns a status code (with Move 2024, an enum) explaining whether the trade succeeded, or
    /// failed due to pool imbalances.
    fun check_imbalance_ratios_status(execute_trade: bool): u8 {
        if (execute_trade) {
            success()
        } else {
            failed_pool_imbalance()
        }
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

    /// Returns the volatility fee as a `u256` with `PRECISION_DECIMAL_PLACES` decimal places.
    ///
    /// The value will represent a percentage i.e. a value between `0` and `ONE`, where
    /// `ONE` is the value `1` with `PRECISION_DECIMAL_PLACES` decimal places.
    public(friend) fun compute_volatility_fee(
        self: &RAMM,
        asset_index: u8,
        new_price: u256,
        new_price_timestamp: u64
    ): u256 {
        ramm_math::compute_volatility_fee(
            get_prev_prc(self, asset_index),
            get_prev_prc_tmstmp(self, asset_index),
            new_price,
            new_price_timestamp,
            *vec_map::get(&self.volatility_indices, &asset_index),
            *vec_map::get(&self.volatility_timestamps, &asset_index),
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        )
    }

    /// Update a given asset's volatility index/timestamp.
    public(friend) fun update_volatility_data(
        self: &mut RAMM,
        asset_index: u8,
        previous_price: u256,
        previous_price_timestamp: u64,
        new_price: u256,
        new_price_timestamp: u64,
        calculated_volatility_fee: u256
    )  {
        ramm_math::update_volatility_data(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            vec_map::get_mut(&mut self.volatility_indices, &asset_index),
            vec_map::get_mut(&mut self.volatility_timestamps, &asset_index),
            calculated_volatility_fee,
            ONE,
            TAU
        )
    }

    /// Given
    /// 1. a mutable reference to a liquidity withdrawal amount
    /// 2. a mutable reference to an initially empty variable,
    /// calculate the fee, deduct it from the withdrawal amount, and place it into the appropriate
    /// variable.
    ///
    /// In a liquidity withdrawal, the fee to be applied is the sum of
    /// 1. a base withdrawal fee set in `const BASE_WITHDRAWAL_FEE`
    /// 2. that specific asset's volatility fee, passed to this function (a percentage encoded as
    ///    a `u256`)
    fun split_withdrawal_fee(amount_out: &mut u256, fee_val: &mut u256, volatility_fee: u256) {
        // this value represents the percentage of a value to be levied as a fee, so it *must* be
        // clamped to `ONE`.
        let total_withdrawal_fee: u256 = ramm_math::clamp(BASE_WITHDRAWAL_FEE + volatility_fee, ONE);
        *fee_val = mul(*amount_out, total_withdrawal_fee);
        *amount_out = *amount_out - *fee_val;
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
        new_prices: VecMap<u8, u256>,
        factors_for_prices: VecMap<u8, u256>,
        // sum of volatility fees levied on input and output assets, calculated in the
        // calling function
        volatility_fee: u256,
    ): TradeOutput {
        let factor_for_price_i: u256 = *vec_map::get(&factors_for_prices, &i);
        let factor_for_price_o: u256 = *vec_map::get(&factors_for_prices, &o);

        let factor_i: u256 = get_fact_for_bal(self, i);
        let factor_o: u256 = get_fact_for_bal(self, o);

        if (get_typed_bal<AssetIn>(self, i) == 0) {
            let num: u256 = mul3(ONE - BASE_FEE, ai * factor_i, *vec_map::get(&new_prices, &i) * factor_for_price_i);
            let ao: u256 = div(num, *vec_map::get(&new_prices, &i) * factor_for_price_o) / factor_o;
            // don't forget the volatility fee
            let pr_fee: u256 = mul3(PROTOCOL_FEE, BASE_FEE + volatility_fee, ai * factor_i) / factor_i;
            let execute: bool = check_imbalance_ratios(self, &new_prices, i, o, ai, ao, pr_fee, &factors_for_prices);
            let trade_outcome: u8 = check_imbalance_ratios_status(execute);
            return TradeOutput {amount: ao, protocol_fee: pr_fee, trade_outcome}
        };

        let _W: VecMap<u8, u256> = weights(self, &new_prices, &factors_for_prices);
        let wi: u256 = *vec_map::get(&_W, &i);
        let wo: u256 = *vec_map::get(&_W, &o);
        let leverage: &mut u256 = &mut 0;
        *leverage = BASE_LEVERAGE;
        let trading_fee: &mut u256 = &mut 0;
        *trading_fee = BASE_FEE;

        if (get_typed_lptok_issued<AssetOut>(self, o) != 0 && get_typed_bal<AssetIn>(self, i) != 0) {
            let imbs = imbalance_ratios(self, &new_prices, &factors_for_prices);
            let imb_ratios_initial_o: u256 = *vec_map::get(&imbs, &o);
            if (imb_ratios_initial_o < ONE - DELTA) {
                return TradeOutput {
                    amount: 0,
                    protocol_fee: 0,
                    trade_outcome: failed_low_out_token_imb_ratio()
                }
            };
            let (tf, l) = scaled_fee_and_leverage(self, &new_prices, i, o, &factors_for_prices);
            *trading_fee = tf;
            *leverage = l;
        };

        let bi: u256 = mul(get_typed_bal<AssetIn>(self, i) * factor_i, *leverage);
        let bo: u256 = mul(get_typed_bal<AssetOut>(self, o) * factor_o, *leverage);

        // The volatility fee must be added to the calculated trading fee percentage
        *trading_fee = ramm_math::clamp(*trading_fee + volatility_fee, ONE);

        let base_denom: u256 = bi + mul(ONE - *trading_fee, ai * factor_i);
        let power: u256 = power(div(bi, base_denom), div(wi, wo));
        let ao: u256 = mul(bo, ONE - power) / factor_o;
        let pr_fee: u256 = mul3(PROTOCOL_FEE, *trading_fee, ai * factor_i) / factor_i;
        if (ao > get_typed_bal<AssetOut>(self, o) ||
            (ao == get_typed_bal<AssetOut>(self, o) && get_typed_lptok_issued<AssetOut>(self, o) != 0)
        ) {
            return TradeOutput {
                amount: 0,
                protocol_fee:0,
                trade_outcome: failed_insufficient_out_token_balance()
            }
        };
        let imb_ratios_check: bool = check_imbalance_ratios(self, &new_prices, i, o, ai, ao, pr_fee, &factors_for_prices);
        let trade_outcome = check_imbalance_ratios_status(imb_ratios_check);
        TradeOutput {amount: ao, protocol_fee: pr_fee, trade_outcome}
    }

    /// Internal function, used by the public trading API e.g. `trade_amount_out_3`.
    /// Contains business logic, and assumes checks have already been made by client-facing
    /// functions.
    ///
    /// This function can be used on a RAMM of any size.
    public(friend) fun trade_o<AssetIn, AssetOut>(
        self: &RAMM,
        // index of incoming token
        i: u8,
        // index of outgoing token
        o: u8,
        ao: u64,
        prices: VecMap<u8, u256>,
        factors_for_prices: VecMap<u8, u256>,
        // sum of volatility fees levied on input and output assets, calculated in the
        // calling function
        volatility_fee: u256
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
            let pr_fee: u256 = mul3(PROTOCOL_FEE, BASE_FEE + volatility_fee, ai * factor_i) / factor_i;
            let imb_ratios_check: bool = check_imbalance_ratios(self, &prices, i, o, ai, ao, pr_fee, &factors_for_prices);
            let trade_outcome = check_imbalance_ratios_status(imb_ratios_check);
            return TradeOutput {amount: ai, protocol_fee: pr_fee, trade_outcome}
        };

        let _W: VecMap<u8, u256> = weights(self, &prices, &factors_for_prices);
        let wi: u256 = *vec_map::get(&_W, &i);
        let wo: u256 = *vec_map::get(&_W, &o);
        let leverage: &mut u256 = &mut 0;
        *leverage = BASE_LEVERAGE;
        let trading_fee: &mut u256 = &mut 0;
        *trading_fee = BASE_FEE;

        if (get_typed_lptok_issued<AssetOut>(self, o) != 0 && get_typed_bal<AssetIn>(self, i) != 0) {
            let imbs = imbalance_ratios(self, &prices, &factors_for_prices);
            let imb_ratios_initial_o: u256 = *vec_map::get(&imbs, &o);
            if (imb_ratios_initial_o < ONE - DELTA) {
                return TradeOutput {
                    amount: 0,
                    protocol_fee: 0,
                    trade_outcome: failed_low_out_token_imb_ratio()
                }
            };
            let (tf, l) = scaled_fee_and_leverage(self, &prices, i, o, &factors_for_prices);
            *trading_fee = tf;
            *leverage = l;
        };

        let bi: u256 = mul(get_typed_bal<AssetIn>(self, i) * factor_i, *leverage);
        let bo: u256 = mul(get_typed_bal<AssetOut>(self, o) * factor_o, *leverage);

        // The volatility fee must be added to the calculated trading fee percentage
        *trading_fee = ramm_math::clamp(*trading_fee + volatility_fee, ONE);

        let power: u256 = power(div(bo, bo - ao * factor_o), div(wo, wi));
        let ai: u256 = div(mul(bi, power - ONE), ONE - *trading_fee) / factor_i;
        let pr_fee: u256 = mul3(PROTOCOL_FEE, *trading_fee, ai * factor_i) / factor_i;

        let imb_ratios_check: bool = check_imbalance_ratios(self, &prices, i, o, ai, ao, pr_fee, &factors_for_prices);
        let trade_outcome = check_imbalance_ratios_status(imb_ratios_check);
        TradeOutput {amount: ai, protocol_fee: pr_fee, trade_outcome}
    }

    /// ----------------------------
    /// Liquidity deposit/withdrawal
    /// ----------------------------

    /// Internal function used by liquidity deposit API e.g. `liquidity_deposit_3`.
    /// Only contains business logic for the RAMM, assumes all safety checks have been made by
    /// the caller.
    ///
    /// Unlike the client-facing API, this function can be used on a RAMM of any size.
    public(friend) fun liq_dep<AssetIn>(
        self: &RAMM,
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
    public(friend) fun liq_wthdrw<AssetOut>(
        self: &RAMM,
        o: u8,
        lpt: u64,
        prices: VecMap<u8, u256>,
        factors_for_prices: VecMap<u8, u256>,
        volatility_fees: VecMap<u8, u256>
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
        let fees: VecMap<u8, u256> = copy amounts_out;

        let a_remaining: &mut u256 = &mut 0;
        let factor_o: u256 = get_fact_for_bal(self, o);
        let bo: u256 = get_typed_bal<AssetOut>(self, o) * factor_o;
        let imb_ratios: VecMap<u8, u256> = imbalance_ratios(self, &prices, &factors_for_prices);
        let ao: &mut u256 = &mut 0;
        let (_B, _L): (u256, u256) = compute_B_and_L(self, &prices, &factors_for_prices);

        // The liquidity provider receives `0` of token `o`.
        // In the whitepaper's "Liquidity Withdrawal" section, this would be
        // Case 2
        // Recall that in this case, the "Case 1" step below is skipped, and the withdrawal
        // continues with different tokens - see below.
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

                let amount_out_o: &mut u256 = vec_map::get_mut(&mut amounts_out, &o);
                let fee_o: &mut u256 = vec_map::get_mut(&mut fees, &o);
                let vol_fee_o: u256 = *vec_map::get(&volatility_fees, &o);
                // Case 1.1.1
                if (*ao <= *max_token_o) {
                    *amount_out_o = *amount_out_o + *ao;
                    split_withdrawal_fee(amount_out_o, fee_o, vol_fee_o);
                    return WithdrawalOutput { amounts: amounts_out, fees, value: *ao, remaining: 0}
                };
                // Case 1.1.2
                if (*ao > *max_token_o) {
                    *amount_out_o = *amount_out_o + *max_token_o;
                    split_withdrawal_fee(amount_out_o, fee_o, vol_fee_o);
                    *a_remaining = *ao - *max_token_o;
                    let imb_ratio_o = vec_map::get_mut(&mut imb_ratios, &o);
                    // to avoid choosing token o again in the next steps
                    *imb_ratio_o = 0;
                    // Withdrawal continued with different token, see below.
                };
            }
            // Case 1.2
            else {
                *ao = div(bo, ro) / factor_o;
                let amount_out_o: &mut u256 = vec_map::get_mut(&mut amounts_out, &o);
                let fee_o: &mut u256 = vec_map::get_mut(&mut fees, &o);
                let vol_fee_o: u256 = *vec_map::get(&volatility_fees, &o);
                // Case 1.2.1
                if (*ao <= get_bal(self, o)) {
                    *amount_out_o = *amount_out_o + *ao;
                    split_withdrawal_fee(amount_out_o, fee_o, vol_fee_o);
                    return WithdrawalOutput { amounts: amounts_out, fees, value: *ao, remaining: 0}
                };
                // Case 1.2.2
                if (*ao > get_bal(self, o)) {
                    *amount_out_o = *amount_out_o + get_bal(self, o);
                    split_withdrawal_fee(amount_out_o, fee_o, vol_fee_o);
                    *a_remaining = *ao - get_bal(self, o);
                    let imb_ratio_o = vec_map::get_mut(&mut imb_ratios, &o);
                    // to avoid choosing token o again in the next steps
                    *imb_ratio_o = 0;
                    // Withdrawal continued with different token, see below.
                };
            };
        };

        // Potential case: withdrawal continued with different tokens
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
                    let fee_k: &mut u256 = vec_map::get_mut(&mut fees, &k);
                    let vol_fee_k: u256 = *vec_map::get(&volatility_fees, &k);

                    if (ak <= max_token_k) {
                        *amount_out_k = *amount_out_k + ak;
                        split_withdrawal_fee(amount_out_k, fee_k, vol_fee_k);
                        // The liquidity provider receives `ak` units of token `k`.
                        *a_remaining = 0;
                    };
                    if (ak > max_token_k) {
                        *amount_out_k = *amount_out_k + max_token_k;
                        split_withdrawal_fee(amount_out_k, fee_k, vol_fee_k);
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

        WithdrawalOutput {amounts: amounts_out, fees, value: *ao, remaining: *a_remaining}
    }
}