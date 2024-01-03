#[test_only]
module ramm_sui::interface3_safety_tests {
    use sui::coin;
    use sui::test_scenario;
    use sui::vec_map::{Self, VecMap};

    use ramm_sui::interface3;
    use ramm_sui::ramm::{Self, LP, RAMM, RAMMAdminCap};
    use ramm_sui::test_util::{Self, BTC, ETH, SOL, USDC};

    use switchboard::aggregator::Aggregator;

    /// ------------------------
    /// Structure of this module
    /// ------------------------

    /*
    IMPORTANT NOTE

    Each externally `public` function from `ramm_sui::interface3` will have, where applicable,
    the following safety checks, grouped in the same section of the module:
    1. calling the function with a RAMM of inappropriate size fails
    2. calling the function with an asset the RAMM does not have fails
    3. calling the function with an amount below the minimum required for that operation fails
        - liquidity withdrawal excluded
    4. calling the function with insufficient liquidity in the pool fails
        - liquidity operations excluded
    5. calling the function on a RAMM with insufficient outbound assets fails
        - liquidity operations excluded
    6. executing a trade with excessive inbound assets fails
        - liquidity operations excluded
    7. executing a trade with excessive outbound assets fails
        - liquidity operations excluded
    8. calling the function using an incorrect `Aggregator` for one of the assets fails
    9. calling the function on a pool with exactly enough balance to satisfy the order, but whose
       outbound asset has circulating LP tokens that would be left unredeemable
         - `trade_amount_out` only

    The tests will be in this order:
    1. tests for `trade_amount_in`
    2. `trade_amount_out`
    3. `liquidity_deposit`
    4. `liquidity_withdrawal`
    5. `collect_fees`

    */

    const ALICE: address = @0xACE;
    const BOB: address = @0xBACE;

    // -------------------------
    // Tests for trade_amount_in
    // -------------------------

    #[test]
    #[expected_failure(abort_code = interface3::ERAMMInvalidSize)]
    /// Check that calling `trade_amount_in_3` on a RAMM without *exactly* 3 assets fails.
    fun trade_amount_in_3_invalid_ramm_size() {
        let (alice_ramm_id, btc_ag_id, eth_ag_id, scenario_val, clock) = test_util::create_ramm_test_scenario_btc_eth_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let amount_in = coin::mint_for_testing<BTC>(1000, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);

            interface3::trade_amount_in_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                amount_in,
                0,
                &btc_aggr,
                &eth_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = vec_map::EKeyDoesNotExist)]
    /// Test using `trade_amount_in_3` with an invalid asset being traded into the RAMM.
    ///
    /// This test *must* fail.
    fun trade_amount_in_3_invalid_asset() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let amount_in = coin::mint_for_testing<USDC>(1000, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            interface3::trade_amount_in_3<USDC, ETH, SOL>(
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
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::ETradeAmountTooSmall)]
    /// Test using `trade_amount_in_3` with an amount lower that the asset's minimum trade sizze,
    ///
    /// This *must* fail.
    fun trade_amount_in_3_insufficient_amount_in() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock)
            = test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let amount_in = coin::mint_for_testing<ETH>(999, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            interface3::trade_amount_in_3<ETH, BTC, SOL>(
                &mut alice_ramm,
                &clock,
                amount_in,
                0,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::ENoLPTokensInCirculation)]
    /// Test using `trade_amount_in_3` with insufficient liquidity in the pool for
    /// the inbound asset.
    ///
    /// This test *must* fail.
    fun trade_amount_in_3_no_minted_lptoken() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_no_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let amount_in = coin::mint_for_testing<BTC>(1 * (test_util::btc_factor() as u64), test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

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
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::ERAMMInsufficientBalance)]
    /// Test using `trade_amount_in_3` with the wrong aggregator provided for one of the assets.
    ///
    /// This *must* fail.
    fun trade_amount_in_3_insufficient_outbound_balance() {
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, 1000);
            vec_map::insert(&mut initial_asset_liquidity, 1, 0);
            vec_map::insert(&mut initial_asset_liquidity, 2, 0);

        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
                test_util::create_ramm_test_scenario_btc_eth_sol(ALICE, initial_asset_liquidity);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let amount_in = coin::mint_for_testing<BTC>(1 * (test_util::btc_factor() as u64), test_scenario::ctx(scenario));
            interface3::trade_amount_in_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                amount_in,
                1,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::ETradeExcessAmountIn)]
    /// This test confirms that a trade with an inflow larger than 5% of a pool's balance
    /// for the inbound asset will fail.
    fun trade_amount_in_3_excessive_amount_in() {
        // Create a 3-asset pool with BTC, ETH
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            // Recall that these test scenarios have 1000 units of each asset as starting liquidity
            // 53 / 1000 > 0.05 = MU, the maximum trade constant
            let amount_in = coin::mint_for_testing<BTC>(53 * (test_util::btc_factor() as u64), test_scenario::ctx(scenario));
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
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::ETradeExcessAmountOut)]
    /// This test confirms that a trade with an outflow larger than 5% of a pool's balance
    /// for the outbound asset will fail.
    fun trade_amount_in_3_excessive_amount_out() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            // Recall that these test scenarios have 1000 units of each asset as starting liquidity
            // Starting prices are 27802.45 for BTC and 20 for SOL.
            // This means 1 BTC  can purchase roughly 1390 SOL, meaning the trade below would
            // request about 700 SOL from the pool, more than the allowed ~500 SOL.
            let amount_in = coin::mint_for_testing<BTC>(5 * (test_util::btc_factor() as u64) / 10, test_scenario::ctx(scenario));
            interface3::trade_amount_in_3<BTC, SOL, ETH>(
                &mut alice_ramm,
                &clock,
                amount_in,
                0,
                &btc_aggr,
                &sol_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::EInvalidAggregator)]
    /// Test using `trade_amount_in_3` with the wrong aggregator provided for one of the assets.
    ///
    /// This *must* fail.
    fun trade_amount_in_3_invalid_aggregator() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let amount_in = coin::mint_for_testing<BTC>(1 * (test_util::btc_factor() as u64) / 10, test_scenario::ctx(scenario));
            // Recall that the type argument order here implies that BTC is inbound, SOL is outbound,
            // which should be reflected in the order of the aggregators (but is not, hence the error).
            interface3::trade_amount_in_3<BTC, SOL, ETH>(
                &mut alice_ramm,
                &clock,
                amount_in,
                0,
                &btc_aggr,
                &eth_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    // --------------------------
    // Tests for trade_amount_out
    // --------------------------

    #[test]
    #[expected_failure(abort_code = interface3::ERAMMInvalidSize)]
    /// Check that calling `trade_amount_out_3` on a RAMM without *exactly* 3 assets fails.
    fun trade_amount_out_3_invalid_ramm_size() {
        let (alice_ramm_id, btc_ag_id, eth_ag_id, scenario_val, clock) = test_util::create_ramm_test_scenario_btc_eth_no_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let max_amount_in = coin::mint_for_testing<BTC>(1000, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);

            interface3::trade_amount_out_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                1000,
                max_amount_in,
                &btc_aggr,
                &eth_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = vec_map::EKeyDoesNotExist)]
    /// Test using `trade_amount_out_3` with an invalid asset being traded into the RAMM.
    ///
    /// This test *must* fail.
    fun trade_amount_out_3_invalid_asset() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let max_amount_in = coin::mint_for_testing<USDC>(1000, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            interface3::trade_amount_out_3<USDC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                1000,
                max_amount_in,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::ETradeAmountTooSmall)]
    /// Test using `trade_amount_out_3` with an amount lower that the asset's minimum trade sizze,
    ///
    /// This *must* fail.
    fun trade_amount_out_3_insufficient_amount_in() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock)
            = test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            // Recall that `create_ramm_3_test_scenario_with_liquidity_in` sets a 0.001 ETH
            // minimum trade amount, and that this ETH has 8 decimal places of precision
            let max_amount_in = coin::mint_for_testing<ETH>(1, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            interface3::trade_amount_out_3<ETH, BTC, SOL>(
                &mut alice_ramm,
                &clock,
                0,
                max_amount_in,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::ENoLPTokensInCirculation)]
    /// Test using `trade_amount_out_3` with insufficient liquidity in the pool for
    /// the inbound asset.
    ///
    /// This test *must* fail.
    fun trade_amount_out_3_no_minted_lptoken() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_no_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let max_amount_in = coin::mint_for_testing<BTC>(1 * (test_util::btc_factor() as u64), test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            interface3::trade_amount_out_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                0,
                max_amount_in,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::ERAMMInsufficientBalance)]
    /// Test using `trade_amount_out_3` with the wrong aggregator provided for one of the assets.
    ///
    /// This *must* fail.
    fun trade_amount_out_3_insufficient_outbound_balance() {
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
            vec_map::insert(&mut initial_asset_liquidity, 0, 1000);
            vec_map::insert(&mut initial_asset_liquidity, 1, 0);
            vec_map::insert(&mut initial_asset_liquidity, 2, 0);

        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
                test_util::create_ramm_test_scenario_btc_eth_sol(ALICE, initial_asset_liquidity);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let max_amount_in = coin::mint_for_testing<BTC>(1 * (test_util::btc_factor() as u64), test_scenario::ctx(scenario));
            interface3::trade_amount_out_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                1 * (test_util::btc_factor() as u64),
                max_amount_in,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::ETradeExcessAmountOut)]
    /// This test confirms that a trade with an outflow larger than 5% of a pool's balance
    /// for the outbound asset will fail.
    fun trade_amount_out_3_excessive_amount_out() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let max_amount_in = coin::mint_for_testing<BTC>(53 * (test_util::btc_factor() as u64), test_scenario::ctx(scenario));
            interface3::trade_amount_out_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                (52 * test_util::eth_factor() as u64),
                max_amount_in,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::ETradeExcessAmountIn)]
    /// This test confirms that a trade with an inflow larger than 5% of a pool's balance
    /// for the inbound asset will fail.
    fun trade_amount_out_3_excessive_amount_in() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            // Recall that this test scenario has 10 units of BTC, 100 of ETH and 10000 of SOL as
            // starting liquidity; note also that
            // * the trader requests 0.3 BTC; 1 / 10 < 0.05 = MU, the maximum trade constant
            // * the trader provides 6 ETH, and the pool only has 100: 6 / 100 > MU
            let max_amount_in = coin::mint_for_testing<ETH>(6 * (test_util::eth_factor() as u64), test_scenario::ctx(scenario));
            interface3::trade_amount_out_3<ETH, BTC, SOL>(
                &mut alice_ramm,
                &clock,
                (4 * test_util::btc_factor() as u64) / 10,
                max_amount_in,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::EInvalidAggregator)]
    /// Test using `trade_amount_out_3` with the wrong aggregator provided for one of the assets.
    ///
    /// This *must* fail.
    fun trade_amount_out_3_invalid_aggregator() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let max_amount_in = coin::mint_for_testing<BTC>(1 * (test_util::btc_factor() as u64), test_scenario::ctx(scenario));
            // Recall that the type argument order here implies that BTC is inbound, SOL is outbound,
            // which should be reflected in the order of the aggregators (but is not, hence the error).
            interface3::trade_amount_out_3<BTC, SOL, ETH>(
                &mut alice_ramm,
                &clock,
                // here, any amount below the pool's liquidity is fine
                1 * (test_util::btc_factor() as u64) / 10,
                max_amount_in,
                &btc_aggr,
                &eth_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::ERAMMInsufBalForCirculatingLPToken)]
    /// Test using `trade_amount_out_3` with enough balance to perform the trade,
    /// but leaving the pool unable to satisfy a liquidity provider's redemption of LP tokens.
    ///
    /// This *must* fail.
    fun trade_amount_out_3_balance_empty_balance_with_circ_lp_tokens() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let max_amount_in = coin::mint_for_testing<ETH>(100 * (test_util::eth_factor() as u64), test_scenario::ctx(scenario));
            // Recall that the type argument order here implies that ETH is inbound, SOL is outbound
            interface3::trade_amount_out_3<ETH, SOL, BTC>(
                &mut alice_ramm,
                &clock,
                10_000 * (test_util::sol_factor() as u64),
                max_amount_in,
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

        test_scenario::end(scenario_val);
    }

    // ---------------------------
    // Tests for liquidity_deposit
    // ---------------------------

    #[test]
    #[expected_failure(abort_code = interface3::ERAMMInvalidSize)]
    /// Check that calling `liquidity_deposit_3` on a RAMM without *exactly* 3 assets fails.
    fun liquidity_deposit_3_invalid_ramm_size() {
        let (alice_ramm_id, btc_ag_id, eth_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_no_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let amount_in = coin::mint_for_testing<BTC>(1000, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);

            interface3::liquidity_deposit_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                amount_in,
                &btc_aggr,
                &eth_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = vec_map::EKeyDoesNotExist)]
    /// Test using `liquidity_deposit_3` with an invalid asset being deposit into the RAMM.
    ///
    /// This test *must* fail.
    fun liquidity_deposit_3_invalid_asset() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let amount_in = coin::mint_for_testing<USDC>(1000, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            interface3::liquidity_deposit_3<USDC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::EInvalidDeposit)]
    /// Test using `liquidity_deposit_3` with 0 coins being deposited into the RAMM.
    ///
    /// This test *must* fail.
    fun liquidity_deposit_3_zero_deposit() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let amount_in = coin::mint_for_testing<BTC>(0, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

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
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::EInvalidAggregator)]
    /// Test using `liquidity_deposit_3` with the wrong aggregator provided for one of the assets.
    ///
    /// This *must* fail.
    fun liquidity_deposit_3_invalid_aggregator() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let amount_in = coin::mint_for_testing<BTC>(1 * (test_util::btc_factor() as u64), test_scenario::ctx(scenario));
            // Recall that the type argument order here implies that BTC is inbound, SOL is outbound,
            // which should be reflected in the order of the aggregators (but is not, hence the error).
            interface3::liquidity_deposit_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &clock,
                amount_in,
                &btc_aggr,
                &eth_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    // ------------------------------
    // Tests for liquidity_withdrawal
    // ------------------------------

    #[test]
    #[expected_failure(abort_code = interface3::ERAMMInvalidSize)]
    /// Check that calling `liquidity_withdrawal_3` on a RAMM without *exactly* 3 assets fails.
    fun liquidity_withdrawal_3_invalid_ramm_size() {
        let (alice_ramm_id, btc_ag_id, eth_ag_id, scenario_val, clock) = test_util::create_ramm_test_scenario_btc_eth_no_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let lp_token = coin::mint_for_testing<LP<BTC>>(1000, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);

            interface3::liquidity_withdrawal_3<BTC, ETH, SOL, BTC>(
                &mut alice_ramm,
                &clock,
                lp_token,
                &btc_aggr,
                &eth_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = vec_map::EKeyDoesNotExist)]
    /// Test using `liquidity_withdrawal_3` with an invalid asset being deposit into the RAMM.
    ///
    /// This test *must* fail.
    fun liquidity_withdrawal_3_invalid_asset() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let lp_tokens = coin::mint_for_testing<LP<USDC>>(1000, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            interface3::liquidity_withdrawal_3<USDC, ETH, SOL, USDC>(
                &mut alice_ramm,
                &clock,
                lp_tokens,
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

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::EInvalidAggregator)]
    /// Test using `liquidity_withdrawal_3` with the wrong aggregator provided for one of the assets.
    ///
    /// This *must* fail.
    fun liquidity_withdrawal_3_invalid_aggregator() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

            let lp_tokens = coin::mint_for_testing<LP<BTC>>(1000, test_scenario::ctx(scenario));
            // Recall that the type argument order here implies that BTC is inbound, SOL is outbound,
            // which should be reflected in the order of the aggregators (but is not, hence the error).
            interface3::liquidity_withdrawal_3<BTC, ETH, SOL, BTC>(
                &mut alice_ramm,
                &clock,
                lp_tokens,
                &btc_aggr,
                &eth_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::EInvalidWithdrawal)]
    /// Test using `liquidity_withdrawal_3` with 0 LP tokens being withdrawn from the RAMM.
    ///
    /// This test *must* fail.
    fun liquidity_withdrawal_3_zero_deposit() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, btc_ag_id, eth_ag_id, sol_ag_id, scenario_val, clock) =
            test_util::create_ramm_test_scenario_btc_eth_sol_with_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let lp_tokens = coin::mint_for_testing<LP<BTC>>(0, test_scenario::ctx(scenario));
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let sol_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sol_ag_id);

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
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(sol_aggr);
        };

        test_scenario::end(scenario_val);
    }

    // -----------------------------------------------
    // End of trading/liquidity function safety checks
    // -----------------------------------------------

    // ------------------------------
    // Safety checks for collect_fees
    // ------------------------------

    #[test]
    #[expected_failure(abort_code = interface3::ERAMMInvalidSize)]
    /// Check that calling `collect_fees_3` on a RAMM without *exactly* 3 assets fails.
    fun collect_fees_3_invalid_ramm_size() {
        let (alice_ramm_id, _, _, scenario_val, clock) = test_util::create_ramm_test_scenario_btc_eth_no_liq(ALICE);
        let scenario = &mut scenario_val;

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ALICE);

            interface3::collect_fees_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &admin_cap,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(alice_ramm);
            test_scenario::return_to_address<RAMMAdminCap>(ALICE, admin_cap);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = interface3::ENotAdmin)]
    /// This test scenario creates 2 RAMM pools, and attempts to collect the fees of the first
    /// one with the `RAMMAdminCap` of the second.
    ///
    /// It *must* fail.
    fun collect_fees_3_wrong_admin_cap() {
        // Create a 3-asset pool with BTC, ETH, SOL
        let (alice_ramm_id, _, _, _, scenario_val, clock) = test_util::create_ramm_test_scenario_btc_eth_sol_no_liq(ALICE);
        let scenario = &mut scenario_val;
        
        test_scenario::next_tx(scenario, BOB);
        // Create second RAMM whose assets don't matter; only its admin cap is needed.
        // A second pool is required as it is the only way to have a second `AdminCap` for the test.
        {
            ramm::new_ramm(BOB, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ALICE);

        {
            let alice_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, alice_ramm_id);
            let bob_admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, BOB);

            interface3::collect_fees_3<BTC, ETH, SOL>(
                &mut alice_ramm,
                &bob_admin_cap,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_address<RAMMAdminCap>(BOB, bob_admin_cap);
            test_scenario::return_shared<RAMM>(alice_ramm);
        };

        test_scenario::end(scenario_val);
    } 

}