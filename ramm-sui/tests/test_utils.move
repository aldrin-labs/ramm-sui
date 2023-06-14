#[test_only]
module ramm_sui::test_utils {
    use std::vector;
    use sui::coin;
    use sui::object::{Self, ID};
    use sui::test_scenario::{Self, Scenario};
    use sui::tx_context::{Self, TxContext};

    use switchboard::aggregator::{Self, Aggregator};
    use switchboard::math as sb_math;

    use ramm_sui::interface3;
    use ramm_sui::ramm::{Self, RAMM, RAMMAdminCap, RAMMNewAssetCap};

    friend ramm_sui::math_tests;
    friend ramm_sui::ramm_tests;
    friend ramm_sui::interface3_tests;

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
    public(friend) fun set_value_for_testing(
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

    public(friend) fun create_write_aggregator(
        scenario: &mut Scenario,
        val: u128,
        scale: u8,
        neg: bool,
        timestamp: u64
    ): Aggregator {
        let ctx = test_scenario::ctx(scenario);
        let aggr = create_aggregator_for_testing(ctx);
        set_value_for_testing(val, scale, neg, &mut aggr, timestamp, ctx);
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

    //
    // Coins used in testing - for coins to be using in the test*net*, see the `ramm-misc` package.
    //

    struct BTC has drop {}
    struct ETH has drop {}
    struct SOL has drop {}
    struct USDC has drop {}
    struct USDT has drop {}

    //
    //
    //

    /// Create a 2-asset RAMM with valid assets and aggregators.
    ///
    /// Used to check that the API for 3-asset RAMMs will guard against being used on
    /// RAMMs without *exatly* 3 assets.
    public(friend) fun create_populate_initialize_ramm_2(
        sender: address
    ): (ID, ID, ID, test_scenario::Scenario) {
        let scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;

        // Create RAMM
        {
            ramm::new_ramm(sender, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, sender);

        let btc_aggr_id = create_write_share_aggregator(scenario, 2780245000000, 8, false, 100);
        let eth_aggr_id = create_write_share_aggregator(scenario, 1884085000000, 9, false, 100);

        test_scenario::next_tx(scenario, sender);

        let ramm_id = {
            let ramm = test_scenario::take_shared<RAMM>(scenario);
            let rid = object::id(&ramm);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, sender);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, sender);

            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_aggr_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_aggr_id);

            let minimum_trade_amount = 1000;

            ramm::add_asset_to_ramm<BTC>(&mut ramm, &btc_aggr, minimum_trade_amount, &admin_cap, &new_asset_cap);
            ramm::add_asset_to_ramm<ETH>(&mut ramm, &eth_aggr, minimum_trade_amount, &admin_cap, &new_asset_cap);

            ramm::initialize_ramm(&mut ramm, &admin_cap, new_asset_cap);

            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address<RAMMAdminCap>(sender, admin_cap);
            rid
        };

        test_scenario::next_tx(scenario, sender);

        (ramm_id, btc_aggr_id, eth_aggr_id, scenario_val)
    }

    /// Another helper for tests - create a RAMM, add 3 assets to it, initialize it, and then
    /// return the scenario with the created objects.
    /// The specific assets don't matter as this is a test, so they are fixed to be BTC, ETH, SOL,
    /// in that order.
    ///
    /// Useful to test post-initialization behavior e.g. fee collection, setting.
    ///
    /// Returns:
    /// 1. the ID of the created RAMM
    /// 2. the IDs of the created aggregators in the order their assets were added to the RAMM, and
    /// 3. the populated test scenario.
    public(friend) fun create_populate_initialize_ramm_3(
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
        let btc_aggr_id = create_write_share_aggregator(scenario, 2780245000000, 8, false, 100);
        let eth_aggr_id = create_write_share_aggregator(scenario, 1884085000000, 9, false, 100);
        let sol_aggr_id = create_write_share_aggregator(scenario, 20526500000, 9, false, 100);

        test_scenario::next_tx(scenario, sender);

        // The pattern is the same - create the required aggregators, add their respective assets to
        // the RAMM, initialize it, etc
        let ramm_id = {
            let ramm = test_scenario::take_shared<RAMM>(scenario);
            let rid = object::id(&ramm);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, sender);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, sender);

            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_aggr_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_aggr_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_aggr_id);

            let minimum_trade_amount = 1000;

            ramm::add_asset_to_ramm<BTC>(&mut ramm, &btc_aggr, minimum_trade_amount, &admin_cap, &new_asset_cap);
            ramm::add_asset_to_ramm<ETH>(&mut ramm, &eth_aggr, minimum_trade_amount, &admin_cap, &new_asset_cap);
            ramm::add_asset_to_ramm<SOL>(&mut ramm, &sol_aggr, minimum_trade_amount, &admin_cap, &new_asset_cap);

            ramm::initialize_ramm(&mut ramm, &admin_cap, new_asset_cap);

            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address<RAMMAdminCap>(sender, admin_cap);
            rid
        };

        test_scenario::next_tx(scenario, sender);

        (ramm_id, btc_aggr_id, eth_aggr_id, sol_aggr_id, scenario_val)
    }

    /// This helper does the same as `create_populate_initialize_ramm_3`, with the addition of
    /// liquidity for the test trades' inbound asset.
    public(friend) fun create_populate_initialize_ramm_3_with_liquidity_in(sender: address)
        : (ID, ID, ID, ID, test_scenario::Scenario) {
        let (ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val) = create_populate_initialize_ramm_3(sender);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let amount_in = coin::mint_for_testing<BTC>(1000, test_scenario::ctx(scenario));
            interface3::liquidity_deposit_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                amount_in,
                &btc_aggr,
                &eth_aggr,
                &sol_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };
        test_scenario::next_tx(scenario, sender);

        (ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val)
    }

    /// This helper does the same as `create_populate_initialize_ramm_3_with_liquidity_in`, with the addition of
    /// liquidity for the test trades' outbound asset.
    public(friend) fun create_populate_initialize_ramm_3_with_liquidity_in_out(sender: address)
        : (ID, ID, ID, ID, test_scenario::Scenario) {
        let (ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val) =
            create_populate_initialize_ramm_3_with_liquidity_in(sender);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let amount_in = coin::mint_for_testing<ETH>(1000, test_scenario::ctx(scenario));
            interface3::liquidity_deposit_3<ETH, BTC, SOL>(
                &mut alice_ramm,
                amount_in,
                &eth_aggr,
                &btc_aggr,
                &sol_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };
        test_scenario::next_tx(scenario, sender);

        (ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val)
    }
}