#[test_only]
/// Name change from `test_utils` -> `test_util` to avoid clashing
/// with `sui::test_utils`.
module ramm_sui::test_util {
    use sui::clock::{Self, Clock};
    use sui::coin;
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    use sui::test_utils;
    use sui::vec_map::{Self, VecMap};

    use switchboard_std::aggregator::{Self, Aggregator};
    use switchboard_std::math as sb_math;

    use ramm_sui::interface2;
    use ramm_sui::interface3;
    use ramm_sui::math as ramm_math;
    use ramm_sui::ramm::{Self, RAMM, RAMMAdminCap, RAMMNewAssetCap};

    /* friend ramm_sui::interface2_safety_tests; */
    /* friend ramm_sui::interface2_oracle_safety_tests; */
    /* friend ramm_sui::interface2_tests; */
    /* friend ramm_sui::interface3_safety_tests; */
    /* friend ramm_sui::interface3_oracle_safety_tests; */
    /* friend ramm_sui::interface3_tests; */
    /* friend ramm_sui::liquidity_provision_fees_tests; */
    /* friend ramm_sui::math_tests; */
    /* friend ramm_sui::ramm_tests; */
    /* friend ramm_sui::volatility2_tests; */
    /* friend ramm_sui::volatility3_tests; */

    /// ----------------
    /// Useful operators
    /// ----------------
    
    /// Check that the first operand is stricly less (`<`) than the second.
    public(package) fun assert_lt(t1: u256, t2: u256) {
        let res = t1 < t2;
        if (!res) {
            test_utils::print(b"Assertion failed:");
            std::debug::print(&t1);
            test_utils::print(b"is not strictly less than");
            std::debug::print(&t2);
            abort(0)
        }
    }

    /// Compare two `u256`s  up to a given `eps: u256`.
    ///
    /// If the numbers are farther apart than `eps`, the assertion fails.
    public(package) fun assert_eq_eps(t1: u256, t2: u256, eps: u256) {
        let sub: u256;
        if (t1 > t2) { sub = t1 - t2; } else { sub = t2 - t1; };
        if (!(sub <= eps)) {
            test_utils::print(b"Assertion failed:");
            test_utils::print(b"t1 is:");
            std::debug::print(&t1);
            test_utils::print(b"t2 is:");
            std::debug::print(&t2);
            test_utils::print(b"eps is");
            std::debug::print(&eps);
            test_utils::print(b"|t1 - t2| > eps");
            abort(0)
        }
    }

    /// --------------------------------------------------------------------------------------------
    /// Coins used in testing - for coins to be using in the test*net*, see the `ramm-misc` package.
    /// --------------------------------------------------------------------------------------------

    public struct BTC has drop {}
    public struct ETH has drop {}
    public struct MATIC has drop {}
    public struct SOL has drop {}
    public struct USDC has drop {}
    public struct USDT has drop {}

    /// Decimal places of the globally known SUI coin type.
    public(package) fun sui_dec_places(): u8 {
        9
    }

    /// Scaling factor for SUI coin type.
    public(package) fun sui_factor(): u256 {
        ramm_math::pow(10u256, sui_dec_places())
    }

    /// Decimal places of this module's BTC coin type.
    public(package) fun btc_dec_places(): u8 {
        8
    }

    /// Scaling factor for BTC coin type.
    public(package) fun btc_factor(): u256 {
        ramm_math::pow(10u256, btc_dec_places())
    }

    /// Decimal places of this module's ETH coin type.
    public(package) fun eth_dec_places(): u8 {
        8
    }

    /// Scaling factor for ETH coin type.
    public(package) fun eth_factor(): u256 {
        ramm_math::pow(10u256, eth_dec_places())
    }

    /// Decimal places of this module's SOL coin type.
    public(package) fun sol_dec_places(): u8 {
        8
    }

    /// Scaling factor for SOL coin type.
    public(package) fun sol_factor(): u256 {
        ramm_math::pow(10u256, sol_dec_places())
    }

    /// Decimal places of this module's MATIC coin type.
    public(package) fun matic_dec_places(): u8 {
        8
    }

    /// Scaling factor for MATIC coin type.
    public(package) fun matic_factor(): u256 {
        ramm_math::pow(10u256, matic_dec_places())
    }

    /// Decimal places of this module's USDT coin type.
    public(package) fun usdt_dec_places(): u8 {
        6
    }

    /// Scaling factor for USDT coin type.
    public(package) fun usdt_factor(): u256 {
        ramm_math::pow(10u256, usdt_dec_places())
    }

    /// Decimal places of this module's USDC coin type.
    public(package) fun usdc_dec_places(): u8 {
        6
    }

    /// Scaling factor for USDC coin type.
    public(package) fun usdc_factor(): u256 {
        ramm_math::pow(10u256, usdc_dec_places())
    }

    /// ----------------
    /// Aggregator utils
    /// ----------------

    /// For testing use only - one time witness for aggregator creation.
    public struct SecretKey has drop {}

    #[test_only]
    /// Create an `Aggregator` for testing
    public(package) fun create_aggregator_for_testing(ctx: &mut TxContext): Aggregator {
        aggregator::new(
            b"test", // name
            @0x0, // queue_addr
            1, // batch_size
            1, // min_oracle_results
            1, // min_job_results
            0, // min_update_delay_seconds
            sb_math::zero(), // variance_threshold
            0, // force_report_period
            false, // disable_crank
            0, // history_limit
            0, // read_charge
            @0x0, // reward_escrow
            vector::empty(), // read_whitelist
            false, // limit_reads_to_whitelist
            0, // created_at
            tx_context::sender(ctx), // authority, - this is the owner of the aggregator
            &SecretKey {},
            ctx,
        )
    }

    #[test_only]
    /// Set a test `Aggregator`'s value.
    public(package) fun set_aggregator_value(
        value: u128,        // example the number 10 would be 10 * 10^dec (dec automatically scaled to 9)
        scale_factor: u8,   // example 9 would be 10^9, 10 = 1000000000
        negative: bool,     // example -10 would be true
        aggregator: &mut Aggregator, // aggregator
        now: u64,           // timestamp (in seconds)
        ctx: &TxContext
    ) {

        // set the value of a test aggregator
        aggregator::push_update(
            aggregator,
            tx_context::sender(ctx),
            sb_math::new(value, scale_factor, negative),
            now,
            &SecretKey {},
        );
    }

    #[test_only]
    /// Create an `Aggregator`, and populate it with the providede values.
    ///
    /// This function does not create a shared object, see `create_write_share_aggregator`.
    public(package) fun create_write_aggregator(
        scenario: &mut Scenario,
        val: u128,
        scale: u8,
        neg: bool,
        timestamp: u64
    ): Aggregator {
        let ctx = test_scenario::ctx(scenario);
        let mut aggr = create_aggregator_for_testing(ctx);
        set_aggregator_value(val, scale, neg, &mut aggr, timestamp, ctx);
        aggr
    }

    #[test_only]
    /// Useful helper in tests; will reduce boilerplate.
    ///
    /// 1. Create an aggregator
    /// 2. populate it with the values passed as arguments to this function
    /// 3. Transform it into a shared object
    /// 4. Return its ID
    public(package) fun create_write_share_aggregator(
        scenario: &mut Scenario,
        val: u128,
        scale: u8,
        neg: bool,
        timestamp: u64
    ): ID {
        let aggr = create_write_aggregator(scenario, val, scale, neg, timestamp);
        let id = object::id(&aggr);
        aggregator::share_aggregator(aggr);
        id
    }

    // -------------------------------
    // Customized RAMM setup for tests
    // -------------------------------

    #[test_only]
    /// Helper that creates 2-asset RAMM, and allows customization:
    /// * prices for each asset's aggregator
    /// * scaling factor for each price
    /// * minimum trade amounts for each asset
    /// * decimal places for each asset
    /// * per-asset liquidity (or its absence)
    public(package) fun create_populate_initialize_ramm_2_asset<Asset1, Asset2>(
        asset_prices: VecMap<u8, u128>,
        asset_price_scales: VecMap<u8, u8>,
        asset_minimum_trade_amounts: VecMap<u8, u64>,
        asset_decimal_places: VecMap<u8, u8>,
        initial_asset_liquidity: VecMap<u8, u64>,
        sender: address
    ): (ID, ID, ID, test_scenario::Scenario) {
        let mut scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;

        // Create a clock for testing, and immediately share it to avoid
        // `sui::transfer::ESharedNonNewObject`
        let clock: Clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::share_for_testing(clock);
        test_scenario::next_tx(scenario, sender);

        // Create RAMM
        {
            ramm::new_ramm(sender, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, sender);

        // Create test aggregators with reasonable prices taken from https://beta.app.switchboard.xyz/
        let aggr1_id = create_write_share_aggregator(
            scenario,
            *vec_map::get(&asset_prices, &0),
            *vec_map::get(&asset_price_scales, &0),
            false,
            0
        );
        let aggr2_id = create_write_share_aggregator(
            scenario,
            *vec_map::get(&asset_prices, &1),
            *vec_map::get(&asset_price_scales, &1),
            false,
            0
        );

        test_scenario::next_tx(scenario, sender);

        // The pattern is the same - create the required aggregators, add their respective assets to
        // the RAMM, initialize it, etc
        let ramm_id = {
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let rid = object::id(&ramm);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, sender);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, sender);

            let aggr1 = test_scenario::take_shared_by_id<Aggregator>(scenario, aggr1_id);
            let aggr2 = test_scenario::take_shared_by_id<Aggregator>(scenario, aggr2_id);

            ramm::add_asset_to_ramm<Asset1>(
                &mut ramm,
                &aggr1,
                *vec_map::get(&asset_minimum_trade_amounts, &0),
                *vec_map::get(&asset_decimal_places, &0),
                &admin_cap,
                &new_asset_cap
            );
            ramm::add_asset_to_ramm<Asset2>(
                &mut ramm,
                &aggr2,
                *vec_map::get(&asset_minimum_trade_amounts, &1),
                *vec_map::get(&asset_decimal_places, &1),
                &admin_cap,
                &new_asset_cap
            );

            ramm::initialize_ramm(&mut ramm, &admin_cap, new_asset_cap);

            if (*vec_map::get(&initial_asset_liquidity, &0) > 0) {
                let amount_in = coin::mint_for_testing<Asset1>(
                    *vec_map::get(&initial_asset_liquidity, &0),
                    test_scenario::ctx(scenario)
                );
                interface2::liquidity_deposit_2<Asset1, Asset2>(
                    &mut ramm,
                    &clock,
                    amount_in,
                    &aggr1,
                    &aggr2,
                    test_scenario::ctx(scenario)
                );
            };
            if (*vec_map::get(&initial_asset_liquidity, &1) > 0) {
                let amount_in = coin::mint_for_testing<Asset2>(
                    *vec_map::get(&initial_asset_liquidity, &1),
                    test_scenario::ctx(scenario)
                );
                interface2::liquidity_deposit_2<Asset2, Asset1>(
                    &mut ramm,
                    &clock,
                    amount_in,
                    &aggr2,
                    &aggr1,
                    test_scenario::ctx(scenario)
                );
            };

            test_scenario::return_shared<Aggregator>(aggr1);
            test_scenario::return_shared<Aggregator>(aggr2);
            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_to_address<RAMMAdminCap>(sender, admin_cap);
            rid
        };

        test_scenario::next_tx(scenario, sender);

        (ramm_id, aggr1_id, aggr2_id, scenario_val)
    }

    #[test_only]
    /// Helper that creates 3-asset RAMM, and allows customization:
    /// * prices for each asset's aggregator
    /// * scaling factor for each price
    /// * minimum trade amounts for each asset
    /// * decimal places for each asset
    /// * per-asset liquidity (or its absence)
    public(package) fun create_populate_initialize_ramm_3_asset<Asset1, Asset2, Asset3>(
        asset_prices: VecMap<u8, u128>,
        asset_price_scales: VecMap<u8, u8>,
        asset_minimum_trade_amounts: VecMap<u8, u64>,
        asset_decimal_places: VecMap<u8, u8>,
        initial_asset_liquidity: VecMap<u8, u64>,
        sender: address
    ): (ID, ID, ID, ID, test_scenario::Scenario) {
        let mut scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;

        // Create a clock for testing, and immediately share it to avoid
        // `sui::transfer::ESharedNonNewObject`
        let clock: Clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::share_for_testing(clock);
        test_scenario::next_tx(scenario, sender);

        // Create RAMM
        {
            ramm::new_ramm(sender, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, sender);

        // Create test aggregators with reasonable prices taken from https://beta.app.switchboard.xyz/
        let aggr1_id = create_write_share_aggregator(
            scenario,
            *vec_map::get(&asset_prices, &0),
            *vec_map::get(&asset_price_scales, &0),
            false,
            0
        );
        let aggr2_id = create_write_share_aggregator(
            scenario,
            *vec_map::get(&asset_prices, &1),
            *vec_map::get(&asset_price_scales, &1),
            false,
            0
        );
        let aggr3_id = create_write_share_aggregator(
            scenario,
            *vec_map::get(&asset_prices, &2),
            *vec_map::get(&asset_price_scales, &2),
            false,
            0
        );

        test_scenario::next_tx(scenario, sender);

        // The pattern is the same - create the required aggregators, add their respective assets to
        // the RAMM, initialize it, etc
        let ramm_id = {
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let rid = object::id(&ramm);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, sender);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, sender);

            let aggr1 = test_scenario::take_shared_by_id<Aggregator>(scenario, aggr1_id);
            let aggr2 = test_scenario::take_shared_by_id<Aggregator>(scenario, aggr2_id);
            let aggr3 = test_scenario::take_shared_by_id<Aggregator>(scenario, aggr3_id);

            ramm::add_asset_to_ramm<Asset1>(
                &mut ramm,
                &aggr1,
                *vec_map::get(&asset_minimum_trade_amounts, &0),
                *vec_map::get(&asset_decimal_places, &0),
                &admin_cap,
                &new_asset_cap
            );
            ramm::add_asset_to_ramm<Asset2>(
                &mut ramm,
                &aggr2,
                *vec_map::get(&asset_minimum_trade_amounts, &1),
                *vec_map::get(&asset_decimal_places, &1),
                &admin_cap,
                &new_asset_cap
            );
            ramm::add_asset_to_ramm<Asset3>(
                &mut ramm,
                &aggr3,
                *vec_map::get(&asset_minimum_trade_amounts, &2),
                *vec_map::get(&asset_decimal_places, &2),
                &admin_cap,
                &new_asset_cap
            );

            ramm::initialize_ramm(&mut ramm, &admin_cap, new_asset_cap);

            if (*vec_map::get(&initial_asset_liquidity, &0) > 0) {
                let amount_in = coin::mint_for_testing<Asset1>(
                    *vec_map::get(&initial_asset_liquidity, &0),
                    test_scenario::ctx(scenario)
                );
                interface3::liquidity_deposit_3<Asset1, Asset2, Asset3>(
                    &mut ramm,
                    &clock,
                    amount_in,
                    &aggr1,
                    &aggr2,
                    &aggr3,
                    test_scenario::ctx(scenario)
                );
            };
            if (*vec_map::get(&initial_asset_liquidity, &1) > 0) {
                let amount_in = coin::mint_for_testing<Asset2>(
                    *vec_map::get(&initial_asset_liquidity, &1),
                    test_scenario::ctx(scenario)
                );
                interface3::liquidity_deposit_3<Asset2, Asset1, Asset3>(
                    &mut ramm,
                    &clock,
                    amount_in,
                    &aggr2,
                    &aggr1,
                    &aggr3,
                    test_scenario::ctx(scenario)
                );
            };
            if (*vec_map::get(&initial_asset_liquidity, &2) > 0) {
                let amount_in = coin::mint_for_testing<Asset3>(
                    *vec_map::get(&initial_asset_liquidity, &2),
                    test_scenario::ctx(scenario)
                );
                interface3::liquidity_deposit_3<Asset3, Asset1, Asset2>(
                    &mut ramm,
                    &clock,
                    amount_in,
                    &aggr3,
                    &aggr1,
                    &aggr2,
                    test_scenario::ctx(scenario)
                );
            };

            test_scenario::return_shared<Aggregator>(aggr1);
            test_scenario::return_shared<Aggregator>(aggr2);
            test_scenario::return_shared<Aggregator>(aggr3);
            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_to_address<RAMMAdminCap>(sender, admin_cap);
            rid
        };

        test_scenario::next_tx(scenario, sender);

        (ramm_id, aggr1_id, aggr2_id, aggr3_id, scenario_val)
    }

    // ------------------
    // Instantiated RAMMs
    // ------------------

    #[test_only]
    /// Create a scenario with
    /// * a 2-asset BTC/ETH RAMM
    /// * valid prices and aggregators, and
    /// * per-asset starting liquidity specified in a `VecMap` argument
    public(package) fun create_ramm_test_scenario_btc_eth(
        sender: address,
        initial_asset_liquidity: VecMap<u8, u64>
    ): (ID, ID, ID, test_scenario::Scenario) {
        let mut asset_prices: VecMap<u8, u128> = vec_map::empty();
            vec_map::insert(&mut asset_prices, 0, 27_800_000000000);
            vec_map::insert(&mut asset_prices, 1, 1_880_000000000);
        let mut asset_price_scales: VecMap<u8, u8> = vec_map::empty();
            vec_map::insert(&mut asset_price_scales, 0, 9);
            vec_map::insert(&mut asset_price_scales, 1, 9);
        let mut asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
            // min trade amount for BTC is 0.0001 BTC
            vec_map::insert(&mut asset_minimum_trade_amounts, 0, (btc_factor() / 10000 as u64));
            // min trade amount for ETH is 0.001 ETH
            vec_map::insert(&mut asset_minimum_trade_amounts, 1, (eth_factor() / 1000 as u64));
        let mut asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
            vec_map::insert(&mut asset_decimal_places, 0, 8);
            vec_map::insert(&mut asset_decimal_places, 1, 8);

        create_populate_initialize_ramm_2_asset<BTC, ETH>(
            asset_prices,
            asset_price_scales,
            asset_minimum_trade_amounts,
            asset_decimal_places,
            initial_asset_liquidity,
            sender
        )
    }

    #[test_only]
    /// Create a scenario with
    /// * a 2-asset BTC/ETH RAMM
    /// * valid prices and aggregators, and
    /// * 1000 units of starting liquidity in all assets
    public(package) fun create_ramm_test_scenario_btc_eth_with_liq(sender: address)
        : (ID, ID, ID, test_scenario::Scenario) {
        let mut initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, (1000 * btc_factor() as u64));
            vec_map::insert(&mut initial_asset_liquidity, 1, (1000 * eth_factor() as u64));

        create_ramm_test_scenario_btc_eth(
            sender,
            initial_asset_liquidity
        )
    }

    #[test_only]
    /// Create a scenario with
    /// * a 2-asset BTC/ETH RAMM
    /// * valid prices and aggregators, and
    /// * no starting liquidity
    public(package) fun create_ramm_test_scenario_btc_eth_no_liq(sender: address)
        : (ID, ID, ID, test_scenario::Scenario) {
        let mut initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, 0);
            vec_map::insert(&mut initial_asset_liquidity, 1, 0);

        create_ramm_test_scenario_btc_eth(
            sender,
            initial_asset_liquidity
        )
    }

    #[test_only]
    /// Another helper for tests - create a RAMM, add 3 assets to it, initialize it, and then
    /// return the scenario with the created objects.
    /// The specific assets don't matter, so they are fixed to be BTC, ETH, SOL,
    /// in that order.
    ///
    /// Useful to test post-initialization behavior e.g. fee collection, fee collection address setting.
    ///
    /// Returns:
    /// 1. the ID of the created RAMM
    /// 2. the IDs of the created aggregators in the order their assets were added to the RAMM, and
    /// 3. the populated test scenario.
    public(package) fun create_ramm_test_scenario_btc_eth_sol(
        sender: address,
        initial_asset_liquidity: VecMap<u8, u64>
    ): (ID, ID, ID, ID, test_scenario::Scenario) {
        let mut asset_prices: VecMap<u8, u128> = vec_map::empty();
        vec_map::insert(&mut asset_prices, 0, 27_800_000000000);
        vec_map::insert(&mut asset_prices, 1, 1_880_000000000);
        vec_map::insert(&mut asset_prices, 2, 20_000000000);
        let mut asset_price_scales: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_price_scales, 0, 9);
        vec_map::insert(&mut asset_price_scales, 1, 9);
        vec_map::insert(&mut asset_price_scales, 2, 9);
        let mut asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut asset_minimum_trade_amounts, 0, (btc_factor() / 10000 as u64));
        vec_map::insert(&mut asset_minimum_trade_amounts, 1, (eth_factor() / 1000 as u64));
        vec_map::insert(&mut asset_minimum_trade_amounts, 2, (sol_factor() / 10 as u64));
        let mut asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_decimal_places, 0, 8);
        vec_map::insert(&mut asset_decimal_places, 1, 8);
        vec_map::insert(&mut asset_decimal_places, 2, 8);

        create_populate_initialize_ramm_3_asset<BTC, ETH, SOL>(
            asset_prices,
            asset_price_scales,
            asset_minimum_trade_amounts,
            asset_decimal_places,
            initial_asset_liquidity,
            sender
        )
    }

    #[test_only]
    /// Does the same as `create_ramm_test_scenario_btc_eth_sol`, but adds initial liquidity
    /// to each of the BTC/ETH/SOL assets in the RAMM:
    /// 1. 10 BTC
    /// 2. 100 ETH
    /// 3. 10000 SOL
    public(package) fun create_ramm_test_scenario_btc_eth_sol_with_liq(
        sender: address,
    ): (ID, ID, ID, ID, test_scenario::Scenario) {
        let mut initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, (10 * btc_factor() as u64));
            vec_map::insert(&mut initial_asset_liquidity, 1, (100 * eth_factor() as u64));
            vec_map::insert(&mut initial_asset_liquidity, 2, (10000 * sol_factor() as u64));

        create_ramm_test_scenario_btc_eth_sol(
            sender,
            initial_asset_liquidity
        )
    }

    #[test_only]
    /// Does the same as `create_ramm_test_scenario_btc_eth_sol`, without initial liquidity
    /// for any of the BTC/ETH/SOL assets in the RAMM.
    public(package) fun create_ramm_test_scenario_btc_eth_sol_no_liq(
        sender: address,
    ): (ID, ID, ID, ID, test_scenario::Scenario) {
        let mut initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, 0);
            vec_map::insert(&mut initial_asset_liquidity, 1, 0);
            vec_map::insert(&mut initial_asset_liquidity, 2, 0);

        create_ramm_test_scenario_btc_eth_sol(
            sender,
            initial_asset_liquidity
        )
    }

    // -------------------
    // Whitepaper examples
    // -------------------

    #[test_only]
    /// Create an ETH/USDT pool with the parameters from the whitepaper's second
    /// practical example.
    public(package) fun create_ramm_test_scenario_eth_usdt(sender: address): (ID, ID, ID, Scenario) {
        let mut asset_prices: VecMap<u8, u128> = vec_map::empty();
        vec_map::insert(&mut asset_prices, 0, 2_000_000000000);
        vec_map::insert(&mut asset_prices, 1, 1_000000000);
        let mut asset_price_scales: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_price_scales, 0, 9);
        vec_map::insert(&mut asset_price_scales, 1, 9);
        let mut asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut asset_minimum_trade_amounts, 0, 1 * (eth_factor() as u64) / 1000);
        vec_map::insert(&mut asset_minimum_trade_amounts, 1, 1 * (usdt_factor() as u64));
        let mut asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_decimal_places, 0, eth_dec_places());
        vec_map::insert(&mut asset_decimal_places, 1, usdt_dec_places());
        let mut initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut initial_asset_liquidity, 0, 500 * (eth_factor() as u64));
        vec_map::insert(&mut initial_asset_liquidity, 1, 900_000 * (usdt_factor() as u64));

        create_populate_initialize_ramm_2_asset<ETH, USDT>(
            asset_prices,
            asset_price_scales,
            asset_minimum_trade_amounts,
            asset_decimal_places,
            initial_asset_liquidity,
            sender
        )
    }

    #[test_only]
    /// Create an ETH/MATIC/USDT pool with the parameters from the whitepaper's first
    /// practical example.
    public(package) fun create_ramm_test_scenario_eth_matic_usdt(sender: address): (ID, ID, ID, ID, Scenario) {
        let mut asset_prices: VecMap<u8, u128> = vec_map::empty();
        vec_map::insert(&mut asset_prices, 0, 1_800_000000000);
        vec_map::insert(&mut asset_prices, 1, 1_200000000);
        vec_map::insert(&mut asset_prices, 2, 1_000000000);
        let mut asset_price_scales: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_price_scales, 0, 9);
        vec_map::insert(&mut asset_price_scales, 1, 9);
        vec_map::insert(&mut asset_price_scales, 2, 9);
        let mut asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut asset_minimum_trade_amounts, 0, 1 * (eth_factor() as u64) / 1000);
        vec_map::insert(&mut asset_minimum_trade_amounts, 1, 1 * (matic_factor() as u64));
        vec_map::insert(&mut asset_minimum_trade_amounts, 2, 1 * (usdt_factor() as u64));
        let mut asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_decimal_places, 0, eth_dec_places());
        vec_map::insert(&mut asset_decimal_places, 1, matic_dec_places());
        vec_map::insert(&mut asset_decimal_places, 2, usdt_dec_places());
        let mut initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut initial_asset_liquidity, 0, 200 * (eth_factor() as u64));
        vec_map::insert(&mut initial_asset_liquidity, 1, 200_000 * (matic_factor() as u64));
        vec_map::insert(&mut initial_asset_liquidity, 2, 400_000 * (usdt_factor() as u64));

        create_populate_initialize_ramm_3_asset<ETH, MATIC, USDT>(
            asset_prices,
            asset_price_scales,
            asset_minimum_trade_amounts,
            asset_decimal_places,
            initial_asset_liquidity,
            sender
        )
    }

    #[test_only]
    /// Create an SUI/USDT/USDC pool with the parameters from the first RAMM deployed to the Sui
    /// mainnet.
    ///
    /// Initial liquidity was roughly:
    /// * `SUI` - 100
    /// * `USDC` - 145
    /// * `USDT` - 148
    public(package) fun create_ramm_test_scenario_sui_usdc_usdt(sender: address): (ID, ID, ID, ID, Scenario) {
        let mut asset_prices: VecMap<u8, u128> = vec_map::empty();
        vec_map::insert(&mut asset_prices, 0, 1_500000000);
        vec_map::insert(&mut asset_prices, 1, 1_000000000);
        vec_map::insert(&mut asset_prices, 2, 1_000000000);
        let mut asset_price_scales: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_price_scales, 0, 9);
        vec_map::insert(&mut asset_price_scales, 1, 9);
        vec_map::insert(&mut asset_price_scales, 2, 9);
        let mut asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut asset_minimum_trade_amounts, 0, (1 * sui_factor() as u64) / 100);
        vec_map::insert(&mut asset_minimum_trade_amounts, 1, (1 * usdc_factor() as u64) / 100);
        vec_map::insert(&mut asset_minimum_trade_amounts, 2, (1 * usdt_factor() as u64) / 100);
        let mut asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_decimal_places, 0, sui_dec_places());
        vec_map::insert(&mut asset_decimal_places, 1, usdc_dec_places());
        vec_map::insert(&mut asset_decimal_places, 2, usdt_dec_places());
        let mut initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut initial_asset_liquidity, 0, 100 * (sui_factor() as u64));
        vec_map::insert(&mut initial_asset_liquidity, 1, 145 * (usdc_factor() as u64));
        vec_map::insert(&mut initial_asset_liquidity, 2, 148 * (usdt_factor() as u64));

        create_populate_initialize_ramm_3_asset<SUI, USDC, USDT>(
            asset_prices,
            asset_price_scales,
            asset_minimum_trade_amounts,
            asset_decimal_places,
            initial_asset_liquidity,
            sender
        )
    }
}