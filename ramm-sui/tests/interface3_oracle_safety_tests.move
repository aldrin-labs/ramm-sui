#[test_only]
module ramm_sui::interface3_oracle_safety_tests {
    use sui::clock::{Self, Clock};
    use sui::coin;
    use sui::test_scenario;

    use ramm_sui::interface3;
    use ramm_sui::oracles;
    use ramm_sui::ramm::{LP, RAMM};
    use ramm_sui::test_util::{Self, BTC, ETH, SOL};

    use switchboard::aggregator::Aggregator;

    /// ------------------------
    /// Structure of this module
    /// ------------------------

    /*
    IMPORTANT NOTE
    The trading and liquidity provision functions in `ramm-sui`'s 3-asset public interface
    (`ramm_sui::interface3`) all require an `Aggregator` to be passed for each of the RAMM's
    assets. This is by design, as the RAMM requires fresh oracle data to perform these operations.

    In order to guarantee that stale prices lead the called function to fail, there is a test
    for each function that
    1. creates a RAMM with 3 assets
    2. increments the value of the global test clock by one hour and one second, just past the
       threshold for stale prices
    3. calls the function with the appropriate aggregator for each asset, keeping in mind that
       test aggregators' timestamps are 0 unless manually changed.

    */

    const ALICE: address = @0xACE;

    const PRICE_TIMESTAMP_STALENESS_THRESHOLD: u64 = 60 * 60 * 1000;

    // -------------------------
    // Tests for trade_amount_in
    // -------------------------

    #[test]
    #[expected_failure(abort_code = oracles::EStalePrice)]
    fun trade_amount_in_3_stale_aggregator_price() {
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let btc_amount: u64 = (1 * test_util::btc_factor() / 10as u64);
            let amount_in = coin::mint_for_testing<BTC>(btc_amount, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            clock::increment_for_testing(&mut clock, PRICE_TIMESTAMP_STALENESS_THRESHOLD + 1);

            interface3::trade_amount_in_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                amount_in,
                0,
                &btc_aggr,
                &eth_aggr,
                &sol_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = oracles::EStalePrice)]
    fun trade_amount_out_3_stale_aggregator_price() {
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let btc_amount: u64 = (1 * test_util::btc_factor() as u64);
            let max_amount_in = coin::mint_for_testing<BTC>(btc_amount, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            clock::increment_for_testing(&mut clock, PRICE_TIMESTAMP_STALENESS_THRESHOLD + 1);

            interface3::trade_amount_out_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                (1 * test_util::eth_factor() as u64),
                max_amount_in,
                &btc_aggr,
                &eth_aggr,
                &sol_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = oracles::EStalePrice)]
    fun liquidity_deposit_3_stale_aggregator_price() {
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val) =
            test_util::create_ramm_test_scenario_btc_eth_sol_no_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let btc_amount: u64 = (1 * test_util::btc_factor() as u64);
            let amount_in = coin::mint_for_testing<BTC>(btc_amount, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            clock::increment_for_testing(&mut clock, PRICE_TIMESTAMP_STALENESS_THRESHOLD + 1);

            interface3::liquidity_deposit_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                amount_in,
                &btc_aggr,
                &eth_aggr,
                &sol_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = oracles::EStalePrice)]
    fun liquidity_withdrawal_3_zero_deposit() {
        // Create a 2-asset pool with BTC, ETH
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);

            let lp_btc_amount: u64 = (1 * test_util::btc_factor() as u64);
            let lp_tokens = coin::mint_for_testing<LP<BTC>>(lp_btc_amount, test_scenario::ctx(scenario));

            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            clock::increment_for_testing(&mut clock, PRICE_TIMESTAMP_STALENESS_THRESHOLD + 1);

            interface3::liquidity_withdrawal_3<BTC, ETH, SOL, BTC>(
                &mut alice_ramm,
                &clock,
                lp_tokens,
                &btc_aggr,
                &eth_aggr,
                &sol_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }
}