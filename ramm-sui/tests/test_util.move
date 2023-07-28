#[test_only]
/// Name change from `test_utils` -> `test_util` to avoid clashing
/// with `sui::test_utils`.
module ramm_sui::test_util {
    use std::vector;
    use sui::coin;
    use sui::object::{Self, ID};
    use sui::test_scenario::{Self, Scenario};
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use switchboard::aggregator::{Self, Aggregator};
    use switchboard::math as sb_math;

    use ramm_sui::interface2;
    use ramm_sui::interface3;
    use ramm_sui::math as ramm_math;
    use ramm_sui::ramm::{Self, RAMM, RAMMAdminCap, RAMMNewAssetCap};

    friend ramm_sui::math_tests;
    friend ramm_sui::ramm_tests;
    friend ramm_sui::interface2_safety_tests;
    friend ramm_sui::interface2_tests;
    friend ramm_sui::interface3_safety_tests;
    friend ramm_sui::interface3_tests;

    /// --------------------------------------------------------------------------------------------
    /// Coins used in testing - for coins to be using in the test*net*, see the `ramm-misc` package.
    /// --------------------------------------------------------------------------------------------

    struct BTC has drop {}
    struct ETH has drop {}
    struct MATIC has drop {}
    struct SOL has drop {}
    struct USDC has drop {}
    struct USDT has drop {}

    /// Decimal places of this module's BTC coin type.
    public(friend) fun btc_dec_places(): u8 {
        8
    }

    /// Scaling factor for BTC coin type.
    public(friend) fun btc_factor(): u256 {
        ramm_math::pow(10u256, btc_dec_places())
    }

    /// Decimal places of this module's ETH coin type.
    public(friend) fun eth_dec_places(): u8 {
        8
    }

    /// Scaling factor for ETH coin type.
    public(friend) fun eth_factor(): u256 {
        ramm_math::pow(10u256, eth_dec_places())
    }

    /// Decimal places of this module's SOL coin type.
    public(friend) fun sol_dec_places(): u8 {
        8
    }

    /// Scaling factor for SOL coin type.
    public(friend) fun sol_factor(): u256 {
        ramm_math::pow(10u256, sol_dec_places())
    }

    /// Decimal places of this module's MATIC coin type.
    public(friend) fun matic_dec_places(): u8 {
        8
    }

    /// Scaling factor for MATIC coin type.
    public(friend) fun matic_factor(): u256 {
        ramm_math::pow(10u256, matic_dec_places())
    }

    /// Decimal places of this module's USDT coin type.
    public(friend) fun usdt_dec_places(): u8 {
        8
    }

    /// Scaling factor for USDT coin type.
    public(friend) fun usdt_factor(): u256 {
        ramm_math::pow(10u256, usdt_dec_places())
    }

    /// ----------------
    /// Aggregator utils
    /// ----------------

    /// For testing use only - one time witness for aggregator creation.
    struct SecretKey has drop {}

    /// Create an `Aggregator` for testing
    public(friend) fun create_aggregator_for_testing(ctx: &mut TxContext): Aggregator {
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

    /// Set a test `Aggregator`'s value.
    public(friend) fun set_aggregator_value(
        value: u128,        // example the number 10 would be 10 * 10^dec (dec automatically scaled to 9)
        scale_factor: u8,   // example 9 would be 10^9, 10 = 1000000000
        negative: bool,     // example -10 would be true
        aggregator: &mut Aggregator, // aggregator
        now: u64,           // timestamp (in seconds)
        ctx: &mut TxContext
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

    /// Create an `Aggregator`, and populate it with the providede values.
    ///
    /// This function does not create a shared object, see `create_write_share_aggregator`.
    public(friend) fun create_write_aggregator(
        scenario: &mut Scenario,
        val: u128,
        scale: u8,
        neg: bool,
        timestamp: u64
    ): Aggregator {
        let ctx = test_scenario::ctx(scenario);
        let aggr = create_aggregator_for_testing(ctx);
        set_aggregator_value(val, scale, neg, &mut aggr, timestamp, ctx);
        aggr
    }

    /// Useful helper in tests; will reduce boilerplate.
    ///
    /// 1. Create an aggregator
    /// 2. populate it with the values passed as arguments to this function
    /// 3. Transform it into a shared object
    /// 4. Return its ID
    public(friend) fun create_write_share_aggregator(
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

    /// -------------------------------
    /// Customized RAMM setup for tests
    /// -------------------------------

    /// Helper that creates 2-asset RAMM, and allows customization:
    /// * prices for each asset's aggregator
    /// * scaling factor for each price
    /// * minimum trade amounts for each asset
    /// * decimal places for each asset
    /// * per-asset liquidity (or its absence)
    public(friend) fun create_populate_initialize_ramm_2_asset<Asset1, Asset2>(
        asset_prices: VecMap<u8, u128>,
        asset_price_scales: VecMap<u8, u8>,
        asset_minimum_trade_amounts: VecMap<u8, u64>,
        asset_decimal_places: VecMap<u8, u8>,
        initial_asset_liquidity: VecMap<u8, u64>,
        sender: address
    ): (ID, ID, ID, test_scenario::Scenario) {
        let scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;

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
            100
        );
        let aggr2_id = create_write_share_aggregator(
            scenario,
            *vec_map::get(&asset_prices, &1),
            *vec_map::get(&asset_price_scales, &1),
            false,
            100
        );

        test_scenario::next_tx(scenario, sender);

        // The pattern is the same - create the required aggregators, add their respective assets to
        // the RAMM, initialize it, etc
        let ramm_id = {
            let ramm = test_scenario::take_shared<RAMM>(scenario);
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
                    amount_in,
                    &aggr2,
                    &aggr1,
                    test_scenario::ctx(scenario)
                );
            };

            test_scenario::return_shared<Aggregator>(aggr1);
            test_scenario::return_shared<Aggregator>(aggr2);
            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address<RAMMAdminCap>(sender, admin_cap);
            rid
        };

        test_scenario::next_tx(scenario, sender);

        (ramm_id, aggr1_id, aggr2_id, scenario_val)
    }

    /// Helper that creates 3-asset RAMM, and allows customization:
    /// * prices for each asset's aggregator
    /// * scaling factor for each price
    /// * minimum trade amounts for each asset
    /// * decimal places for each asset
    /// * per-asset liquidity (or its absence)
    public(friend) fun create_populate_initialize_ramm_3_asset<Asset1, Asset2, Asset3>(
        asset_prices: VecMap<u8, u128>,
        asset_price_scales: VecMap<u8, u8>,
        asset_minimum_trade_amounts: VecMap<u8, u64>,
        asset_decimal_places: VecMap<u8, u8>,
        initial_asset_liquidity: VecMap<u8, u64>,
        sender: address
    ): (ID, ID, ID, ID, test_scenario::Scenario) {
        let scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;

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
            100
        );
        let aggr2_id = create_write_share_aggregator(
            scenario,
            *vec_map::get(&asset_prices, &1),
            *vec_map::get(&asset_price_scales, &1),
            false,
            100
        );
        let aggr3_id = create_write_share_aggregator(
            scenario,
            *vec_map::get(&asset_prices, &2),
            *vec_map::get(&asset_price_scales, &2),
            false,
            100
        );

        test_scenario::next_tx(scenario, sender);

        // The pattern is the same - create the required aggregators, add their respective assets to
        // the RAMM, initialize it, etc
        let ramm_id = {
            let ramm = test_scenario::take_shared<RAMM>(scenario);
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
            test_scenario::return_to_address<RAMMAdminCap>(sender, admin_cap);
            rid
        };

        test_scenario::next_tx(scenario, sender);

        (ramm_id, aggr1_id, aggr2_id, aggr3_id, scenario_val)
    }

    /// ------------------
    /// Instantiated RAMMs
    /// ------------------

    /// Create a scenario with
    /// * a 2-asset BTC/ETH RAMM
    /// * valid prices and aggregators, and
    /// * per-asset starting liquidity specified in a `VecMap` argument
    public(friend) fun create_ramm_test_scenario_btc_eth(
        sender: address,
        initial_asset_liquidity: VecMap<u8, u64>
    ): (ID, ID, ID, test_scenario::Scenario) {
        let asset_prices: VecMap<u8, u128> = vec_map::empty();
            vec_map::insert(&mut asset_prices, 0, 27802450000000);
            vec_map::insert(&mut asset_prices, 1, 1884085000000);
        let asset_price_scales: VecMap<u8, u8> = vec_map::empty();
            vec_map::insert(&mut asset_price_scales, 0, 9);
            vec_map::insert(&mut asset_price_scales, 1, 9);
        let asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
            // min trade amount for BTC is 0.0001 BTC
            vec_map::insert(&mut asset_minimum_trade_amounts, 0, (btc_factor() / 10000 as u64));
            // min trade amount for ETH is 0.001 ETH
            vec_map::insert(&mut asset_minimum_trade_amounts, 1, (eth_factor() / 1000 as u64));
        let asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
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

    /// Create a scenario with
    /// * a 2-asset BTC/ETH RAMM
    /// * valid prices and aggregators, and
    /// * 1000 units of starting liquidity in all assets
    public(friend) fun create_ramm_test_scenario_btc_eth_with_liq(sender: address)
        : (ID, ID, ID, test_scenario::Scenario) {
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, (1000 * btc_factor() as u64));
            vec_map::insert(&mut initial_asset_liquidity, 1, (1000 * eth_factor() as u64));

        create_ramm_test_scenario_btc_eth(
            sender,
            initial_asset_liquidity
        )
    }

    /// Create a scenario with
    /// * a 2-asset BTC/ETH RAMM
    /// * valid prices and aggregators, and
    /// * no starting liquidity
    public(friend) fun create_ramm_test_scenario_btc_eth_no_liq(sender: address)
        : (ID, ID, ID, test_scenario::Scenario) {
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, 0);
            vec_map::insert(&mut initial_asset_liquidity, 1, 0);

        create_ramm_test_scenario_btc_eth(
            sender,
            initial_asset_liquidity
        )
    }

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
    public(friend) fun create_ramm_test_scenario_btc_eth_sol(
        sender: address,
        initial_asset_liquidity: VecMap<u8, u64>
    ): (ID, ID, ID, ID, test_scenario::Scenario) {
        let asset_prices: VecMap<u8, u128> = vec_map::empty();
        vec_map::insert(&mut asset_prices, 0, 27802450000000);
        vec_map::insert(&mut asset_prices, 1, 1884085000000);
        vec_map::insert(&mut asset_prices, 2, 20526500000);
        let asset_price_scales: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_price_scales, 0, 9);
        vec_map::insert(&mut asset_price_scales, 1, 9);
        vec_map::insert(&mut asset_price_scales, 2, 9);
        let asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut asset_minimum_trade_amounts, 0, (btc_factor() / 10000 as u64));
        vec_map::insert(&mut asset_minimum_trade_amounts, 1, (eth_factor() / 1000 as u64));
        vec_map::insert(&mut asset_minimum_trade_amounts, 2, (sol_factor() / 10 as u64));
        let asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
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

    /// Does the same as `create_ramm_test_scenario_btc_eth_sol`, but adds initial liquidity
    /// to each of the BTC/ETH/SOL assets in the RAMM:
    /// 1. 1000 BTC
    /// 2. 1000 ETH
    /// 3. 1000 SOL
    public(friend) fun create_ramm_test_scenario_btc_eth_sol_with_liq(
        sender: address,
    ): (ID, ID, ID, ID, test_scenario::Scenario) {
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, (1000 * btc_factor() as u64));
            vec_map::insert(&mut initial_asset_liquidity, 1, (1000 * eth_factor() as u64));
            vec_map::insert(&mut initial_asset_liquidity, 2, (1000 * sol_factor() as u64));

        create_ramm_test_scenario_btc_eth_sol(
            sender,
            initial_asset_liquidity
        )
    }

    /// Does the same as `create_ramm_test_scenario_btc_eth_sol`, without initial liquidity
    /// for any of the BTC/ETH/SOL assets in the RAMM.
    public(friend) fun create_ramm_test_scenario_btc_eth_sol_no_liq(
        sender: address,
    ): (ID, ID, ID, ID, test_scenario::Scenario) {
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, 0);
            vec_map::insert(&mut initial_asset_liquidity, 1, 0);
            vec_map::insert(&mut initial_asset_liquidity, 2, 0);

        create_ramm_test_scenario_btc_eth_sol(
            sender,
            initial_asset_liquidity
        )
    }

    /// -------------------
    /// Whitepaper examples
    /// -------------------

    /// Create an ETH/USDT pool with the parameters from the whitepaper's second
    /// practical example.
    public(friend) fun create_testing_ramm_eth_udst(sender: address): (ID, ID, ID, Scenario) {
        let asset_prices: VecMap<u8, u128> = vec_map::empty();
        vec_map::insert(&mut asset_prices, 0, 2000000000000);
        vec_map::insert(&mut asset_prices, 1, 1000000000);
        let asset_price_scales: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_price_scales, 0, 9);
        vec_map::insert(&mut asset_price_scales, 1, 9);
        let asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut asset_minimum_trade_amounts, 0, 1 * (eth_factor() as u64) / 1000);
        vec_map::insert(&mut asset_minimum_trade_amounts, 1, 1 * (usdt_factor() as u64));
        let asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_decimal_places, 0, eth_dec_places());
        vec_map::insert(&mut asset_decimal_places, 1, usdt_dec_places());
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut initial_asset_liquidity, 0, 500 * (eth_factor() as u64));
        vec_map::insert(&mut initial_asset_liquidity, 1, 900_000 * (matic_factor() as u64));

        create_populate_initialize_ramm_2_asset<ETH, USDT>(
            asset_prices,
            asset_price_scales,
            asset_minimum_trade_amounts,
            asset_decimal_places,
            initial_asset_liquidity,
            sender
        )
    }

    /// Create an ETH/MATIC/USDT pool with the parameters from the whitepaper's first
    /// practical example.
    public(friend) fun create_ramm_test_scenario_eth_matic_usdt(sender: address): (ID, ID, ID, ID, Scenario) {
        let asset_prices: VecMap<u8, u128> = vec_map::empty();
        vec_map::insert(&mut asset_prices, 0, 1800000000000);
        vec_map::insert(&mut asset_prices, 1, 1200000000);
        vec_map::insert(&mut asset_prices, 2, 1000000000);
        let asset_price_scales: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_price_scales, 0, 9);
        vec_map::insert(&mut asset_price_scales, 1, 9);
        vec_map::insert(&mut asset_price_scales, 2, 9);
        let asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut asset_minimum_trade_amounts, 0, 1 * (eth_factor() as u64) / 1000);
        vec_map::insert(&mut asset_minimum_trade_amounts, 1, 1 * (matic_factor() as u64));
        vec_map::insert(&mut asset_minimum_trade_amounts, 2, 1 * (usdt_factor() as u64));
        let asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_decimal_places, 0, eth_dec_places());
        vec_map::insert(&mut asset_decimal_places, 1, matic_dec_places());
        vec_map::insert(&mut asset_decimal_places, 2, usdt_dec_places());
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
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
}