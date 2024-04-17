#[test_only]
module ramm_sui::interface3_tests {
    //use std::debug;

    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, TransactionEffects};
    use sui::test_utils;

    use ramm_sui::interface3;
    use ramm_sui::math;
    use ramm_sui::ramm::{Self, LP,  RAMM, RAMMAdminCap};
    use ramm_sui::test_util::{Self, ETH, MATIC, USDT};

    use switchboard::aggregator::Aggregator;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;
    const BOB: address = @0xBACE;

    const ETraderShouldNotHaveAsset: u64 = 0;
    const EFeeCollectionError: u64 = 1;

    #[test]
    /// Test the `trade_amount_in_3` function.
    /// This function is used for RAMM deposits i.e. the trader specifies exactly how much
    /// of the inbound asset they will deposit, and will receive however much of the outbound
    /// asset the pool can provide.
    /// The trader receives no "change".
    fun trade_amount_in_3_test() {
        let (ramm_id, eth_ag_id, matic_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ALICE);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            // First trade: ETH in, USDT out

            let amount_in = coin::mint_for_testing<ETH>(10 * (test_util::eth_factor() as u64), test_scenario::ctx(scenario));
            interface3::trade_amount_in_3<ETH, USDT, MATIC>(
                &mut ramm,
                &clock,
                amount_in,
                16_000 * (test_util::usdt_factor() as u64),
                &eth_aggr,
                &usdt_aggr,
                &matic_aggr,
                test_scenario::ctx(scenario)
            );

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 209997 * test_util::eth_factor() / 1000);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 209997 * test_util::eth_factor() / 1000);

            test_utils::assert_eq(ramm::get_balance<MATIC>(&ramm), 200_000 * test_util::matic_factor());
            test_utils::assert_eq(ramm::get_typed_balance<MATIC>(&ramm), 200_000 * test_util::matic_factor());

            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), 382_026_5288 * test_util::usdt_factor() / 10000);
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), 382_026_5288 * test_util::usdt_factor() / 10000);

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 3 * (test_util::eth_factor() as u64) / 1000);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<MATIC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 200 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 200 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<MATIC>(&ramm), 200_000 * test_util::matic_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<MATIC>(&ramm), 200_000 * test_util::matic_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 400_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 400_000 * test_util::usdt_factor());

            // Second trade: ETH in, MATIC out

            let amount_in = coin::mint_for_testing<ETH>(5 * (test_util::eth_factor() as u64), test_scenario::ctx(scenario));
            interface3::trade_amount_in_3<ETH, MATIC, USDT>(
                &mut ramm,
                &clock,
                amount_in,
                7_400 * (test_util::matic_factor() as u64),
                &eth_aggr,
                &matic_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            // The pool should have about 214.99 ETH after this trade
            // Recall that test ETH's decimal place count is 8.
            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 214_99526364);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 214_99526364);

            // The pool should have about 192511.34 MATIC after the trade.
            // As above, recall that MATIC's decimal place count is 8.
            test_utils::assert_eq(ramm::get_balance<MATIC>(&ramm), 192511_33618744);
            test_utils::assert_eq(ramm::get_typed_balance<MATIC>(&ramm), 1925113_3618744);

            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), 382_026_5288 * test_util::usdt_factor() / 10000);
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), 382_026_5288 * test_util::usdt_factor() / 10000);

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 473636);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<MATIC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            // There must not have been any change to issued LP tokens, of any kind.
            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 200 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 200 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<MATIC>(&ramm), 200_000 * test_util::matic_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<MATIC>(&ramm), 200_000 * test_util::matic_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 400_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 400_000 * test_util::usdt_factor());

            //

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(matic_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ALICE);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 2);

        {
            assert!(!test_scenario::has_most_recent_for_address<Coin<ETH>>(ALICE), ETraderShouldNotHaveAsset);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 0);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let lp_eth = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_eth), (200 * test_util::eth_factor() as u64));

            interface3::liquidity_withdrawal_3<ETH, USDT, MATIC, ETH>(
                &mut ramm,
                &clock,
                lp_eth,
                &eth_aggr,
                &usdt_aggr,
                &matic_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(matic_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            // The liquidity provider should have about 199.2 ETH, with about 0.06 ETH
            // being the result of collected fees, and -0.8 ETH the liquidity withdrawal
            // fee of 0.4%.
            test_utils::assert_eq(coin::value(&eth), 199_20629607);
            test_scenario::return_to_address(ADMIN, eth);
        };


        test_scenario::end(scenario_val);
    }

    #[test]
    /// Test the `trade_amount_out_3` function.
    /// This function is used for RAMM withdrawals i.e. the trader specifies exactly how much
    /// of an asset they desire, and provide an upper bound of the inbound asset,
    /// being returned the remainder.
    fun trade_amount_out_3_test() {
        let (ramm_id, eth_ag_id, matic_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, BOB);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            // First trade: ETH in, USDT out
            let max_ai = coin::mint_for_testing<ETH>(10 * (test_util::eth_factor() as u64), test_scenario::ctx(scenario));
            // With the test scenario's price of `1800 USDT/ETH`, it'll take `16200 USDT` for `9 ETH`.
            interface3::trade_amount_out_3<ETH, USDT, MATIC>(
                &mut ramm,
                &clock,
                16_200 * (test_util::usdt_factor() as u64),
                max_ai,
                &eth_aggr,
                &usdt_aggr,
                &matic_aggr,
                test_scenario::ctx(scenario)
            );

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 209_01015811);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 209_01015811);

            test_utils::assert_eq(ramm::get_balance<MATIC>(&ramm), 200_000 * test_util::matic_factor());
            test_utils::assert_eq(ramm::get_typed_balance<MATIC>(&ramm), 200_000 * test_util::matic_factor());

            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), 383_800 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), 383_800 * test_util::usdt_factor());

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 270385);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<MATIC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            // There must not have been any change to issued LP tokens, of any kind.
            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 200 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 200 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<MATIC>(&ramm), 200_000 * test_util::matic_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<MATIC>(&ramm), 200_000 * test_util::matic_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 400_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 400_000 * test_util::usdt_factor());

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(matic_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, BOB);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth = test_scenario::take_from_address<Coin<ETH>>(scenario, BOB);

            // Assert that the trader is returned the remainder of the ETH used to trade.
            test_utils::assert_eq(coin::value(&eth), 98713804);

            // The RAMM had 200 ETH at the start, the trader used 10 ETH but part of it
            // was returned.
            // This `assert` checks that existing ETH, fees, incoming ETH and outbound remainder
            // all add up.
            test_utils::assert_eq(
                (coin::value(&eth) as u256) +
                ramm::get_typed_balance<ETH>(&ramm) +
                (ramm::get_collected_protocol_fees<ETH>(&ramm) as u256),
                210 * test_util::eth_factor()
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address(BOB, eth);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Check that emitting an event with the pool's imbalance ratios does so.
    fun imbalance_ratios_event_3_test() {
        let (ramm_id, eth_ag_id, matic_ag_id, usdt_ag_id, mut scenario_val) =
            test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ALICE);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            interface3::imbalance_ratios_event_3<ETH, MATIC, USDT>(
                &ramm,
                &clock,
                &eth_aggr,
                &matic_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<Aggregator>(usdt_aggr);
            test_scenario::return_shared<Aggregator>(matic_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<RAMM>(ramm);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ALICE);
        // Verify that one user event was emitted - the pool state query.
        //
        // The Sui Move test framework does not currently allow inspection of a tx's emitted
        // events, but simply verifying an event was emitted would have prevented a past bug:
        //
        // * due to an infinite loop in `get_pool_state`, the function never terminated, and
        // no event was ever emitted due to transaction execution failure over exhausted resources.
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Test for fee collection after a trade.
    ///
    /// After a trader sells 10 ETH to a perfectly balanced pool:
    /// * the admin should receive 0.03 ETH (or 300000 units when using 8 decimal places) of
    ///   protocol fees from this trade, and 0 of any other asset.
    /// * futhermore, the RAMM's fees should be null after the collection
    fun collect_fees_3_test_1() {
        let (ramm_id, eth_ag_id, matic_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        let eth_trade_amount: u64 = 10 * (test_util::eth_factor() as u64);
        // This test's dummy ETH has 8 decimal places, so the base fee and protocol fee
        // percentages should use that many places as well
        let prec: u8 = test_util::eth_dec_places();
        let max_prec: u8 = 2 * test_util::eth_dec_places();
        let one: u256 = test_util::eth_factor();
        let base_fee: u256 = 10 * one / 10000;
        let protocol_fee: u256 = 30 * one / 100;

        test_scenario::next_tx(scenario, ALICE);

        // Trade: 10 ETH in, roughly 18k USDT out
        // The pool is fresh, so all imbalance ratios are 1
        let eth_trade_fee: u256 = {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let initial_eth_balance: u256 = ramm::get_typed_balance<ETH>(&ramm);
            let initial_matic_balance: u256 = ramm::get_typed_balance<MATIC>(&ramm);
            let initial_usdt_balance: u256 = ramm::get_typed_balance<USDT>(&ramm);
            test_utils::assert_eq(initial_eth_balance, 200 * test_util::eth_factor());
            test_utils::assert_eq(initial_matic_balance, 200_000 * test_util::eth_factor());
            test_utils::assert_eq(initial_usdt_balance, 400_000 * test_util::eth_factor());

            let amount_in = coin::mint_for_testing<ETH>(eth_trade_amount, test_scenario::ctx(scenario));
            interface3::trade_amount_in_3<ETH, USDT, MATIC>(
                &mut ramm,
                &clock,
                amount_in,
                16_000 * (test_util::usdt_factor() as u64),
                &eth_aggr,
                &usdt_aggr,
                &matic_aggr,
                test_scenario::ctx(scenario)
            );
            let trade_fee: u256 = (ramm::get_collected_protocol_fees<ETH>(&ramm) as u256);
            test_utils::assert_eq(
                trade_fee,
                math::mul3(
                    (eth_trade_amount as u256),
                    base_fee,
                    protocol_fee,
                    prec,
                    max_prec
                )
            );

            let new_eth_balance = ramm::get_typed_balance<ETH>(&ramm);
            let input_eth: u256 = math::mul(
                    (eth_trade_amount as u256),
                    one - math::mul(base_fee, protocol_fee, prec, max_prec),
                    prec,
                    max_prec
                );
            
            // The pool should have received 9.97 ETH to its balance of 200, and no other asset.
            test_utils::assert_eq(
                new_eth_balance,
                initial_eth_balance + input_eth
            );
            // MATIC balance should stay unchanged
            test_utils::assert_eq(
                initial_matic_balance,
                ramm::get_typed_balance<MATIC>(&ramm)
            );
            // There should be a non-zero outflow of USDT
            test_util::assert_lt(
                ramm::get_typed_balance<USDT>(&ramm),
                initial_usdt_balance,
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(matic_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);

            trade_fee
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        // Next step: collect the RAMM fees to the collection address (in this case, the admin's)

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);

            interface3::collect_fees_3<ETH, USDT, MATIC>(
                &mut ramm,
                &admin_cap,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);

            // Check that the RAMM has no fees to be collected
            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<MATIC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            // Check that the RAMM admin has been return an appropriate ammount of funds as fees
            // Since the imbalance ratios were all 1 before the trade, the fee applied
            // will have been the base fee of 0.1%, 30% of which will be protocol fees
            // collected by the pool, which is what the admin will have access to.
            let eth_fees = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&eth_fees), (eth_trade_fee as u64));

            // Check that the admin has not received any funds other than the fees collected from
            // the ETH/USDT trade, which should be denominated in ETH.
            assert!(!test_scenario::has_most_recent_for_address<Coin<MATIC>>(ADMIN), EFeeCollectionError);
            assert!(!test_scenario::has_most_recent_for_address<Coin<USDT>>(ADMIN), EFeeCollectionError);

            test_scenario::return_to_address<Coin<ETH>>(ADMIN, eth_fees);
            test_scenario::return_shared<RAMM>(ramm);
        }; 

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Test for fee collection after a liquidity withdrawal.
    ///
    /// After the pool's admin withdraws all of their 200 ETH liquidity from a perfectly balanced pool:
    /// * the admin should receive 0.8 ETH (or 8000000 units when using 8 decimal places) of
    ///   protocol fees from this withdrawal, and 0 of any other asset.
    /// * futhermore, the RAMM's fees should be null after the collection
    fun collect_fees_3_test_2() {
        let (ramm_id, eth_ag_id, matic_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        let prec: u8 = test_util::eth_dec_places();
        let max_prec: u8 = 2 * test_util::eth_dec_places();
        let one: u256 = test_util::eth_factor();
        let liq_wthdrwl_fee: u256 = 40 * one / 10000;

        test_scenario::next_tx(scenario, ADMIN);

        // First step: the admin withdraws the ETH they've provided to the pool
        let (initial_eth_balance, initial_matic_balance, initial_usdt_balance): (u256, u256, u256) = {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let init_eth: u256 = ramm::get_typed_balance<ETH>(&ramm);
            let init_matic: u256 = ramm::get_typed_balance<MATIC>(&ramm);
            let init_usdt: u256 = ramm::get_typed_balance<USDT>(&ramm);
            let lp_eth = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_eth), (init_eth as u64));

            interface3::liquidity_withdrawal_3<ETH, USDT, MATIC, ETH>(
                &mut ramm,
                &clock,
                lp_eth,
                &eth_aggr,
                &usdt_aggr,
                &matic_aggr,
                test_scenario::ctx(scenario)
            );

            // Check that the collected ETH fee matches the expected number
            test_utils::assert_eq(
                (ramm::get_collected_protocol_fees<ETH>(&ramm) as u256),
                math::mul(init_eth, liq_wthdrwl_fee, prec, max_prec)
            );
            // Check that the pool collects no other fee except for the ETH
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 0);

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(matic_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);

            (init_eth, init_matic, init_usdt)
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        // Second step: the admin performs the fee collection
        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);

            interface3::collect_fees_3<ETH, USDT, MATIC>(
                &mut ramm,
                &admin_cap,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);

            // Check that the RAMM has 0 ETH, and unchanged balances elsewhere
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_typed_balance<MATIC>(&ramm), initial_matic_balance);
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), initial_usdt_balance);

            // Check that the RAMM has no more fees to collect
            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<MATIC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            // Verify that the fee collector (in this case, coincides with the admin)
            // has ETH fees corresponding to the ETH liquidity withdrawal, and no other fees.
            let eth_fees = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            test_utils::assert_eq(
                (coin::value(&eth_fees) as u256),
                math::mul(initial_eth_balance, liq_wthdrwl_fee, prec, max_prec)
            );
            // Check that the admin has not received any funds other than the fees collected from
            // the ETH/USDT trade, which should be denominated in ETH.
            assert!(!test_scenario::has_most_recent_for_address<Coin<MATIC>>(ADMIN), EFeeCollectionError);
            assert!(!test_scenario::has_most_recent_for_address<Coin<USDT>>(ADMIN), EFeeCollectionError);

            let eth_withdrawal = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            test_utils::assert_eq(
                (coin::value(&eth_withdrawal) as u256),
                math::mul(initial_eth_balance, one - liq_wthdrwl_fee, prec, max_prec)
            );

            test_scenario::return_to_address<Coin<ETH>>(ADMIN, eth_withdrawal);
            test_scenario::return_to_address<Coin<ETH>>(ADMIN, eth_fees);
            test_scenario::return_shared<RAMM>(ramm);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 0);

        test_scenario::end(scenario_val);
    }
}