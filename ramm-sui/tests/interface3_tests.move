#[test_only]
module ramm_sui::interface3_tests {
    //use std::debug;

    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, TransactionEffects};
    use sui::test_utils;

    use ramm_sui::interface3;
    use ramm_sui::ramm::{Self, LP,  RAMM};
    use ramm_sui::test_util::{Self, ETH, MATIC, USDT};

    use switchboard::aggregator::Aggregator;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;
    const BOB: address = @0xBACE;

    const ETraderShouldNotHaveAsset: u64 = 0;

    #[test]
    /// Test the `trade_amount_in_3` function.
    /// This function is used for RAMM deposits i.e. the trader specifies exactly how much
    /// of the inbound asset they will deposit, and will receive however much of the outbound
    /// asset the pool can provide.
    /// The trader receives no "change".
    fun test_trade_i() {
        let (ramm_id, eth_ag_id, matic_ag_id, usdt_ag_id, scenario_val) = test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ALICE);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            // First trade: ETH in, USDT out

            let amount_in = coin::mint_for_testing<ETH>(10 * (test_util::eth_factor() as u64), test_scenario::ctx(scenario));
            interface3::trade_amount_in_3<ETH, USDT, MATIC>(
                &mut ramm,
                amount_in,
                16_000 * (test_util::usdt_factor() as u64),
                &eth_aggr,
                &usdt_aggr,
                &matic_aggr,
                test_scenario::ctx(scenario)
            );

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 209995 * test_util::eth_factor() / 1000);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 209995 * test_util::eth_factor() / 1000);

            test_utils::assert_eq(ramm::get_balance<MATIC>(&ramm), 200_000 * test_util::matic_factor());
            test_utils::assert_eq(ramm::get_typed_balance<MATIC>(&ramm), 200_000 * test_util::matic_factor());

            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), 382_026_5288 * test_util::usdt_factor() / 10000);
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), 382_026_5288 * test_util::usdt_factor() / 10000);

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 5 * (test_util::eth_factor() as u64) / 1000);
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
                amount_in,
                7_400 * (test_util::matic_factor() as u64),
                &eth_aggr,
                &matic_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            // The pool should have about 214.99 ETH after this trade
            // Recall that test ETH's decimal place count is 8.
            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 214_99210_615);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 214_99210615);

            // The pool should have about 192511.34 MATIC after the trade.
            // As above, recall that MATIC's decimal place count is 8.
            test_utils::assert_eq(ramm::get_balance<MATIC>(&ramm), 192511_33586076);
            test_utils::assert_eq(ramm::get_typed_balance<MATIC>(&ramm), 192511_33586076);

            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), 382_026_5288 * test_util::usdt_factor() / 10000);
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), 382_026_5288 * test_util::usdt_factor() / 10000);

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 789385);
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
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let lp_eth = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_eth), (200 * test_util::eth_factor() as u64));

            interface3::liquidity_withdrawal_3<ETH, USDT, MATIC, ETH>(
                &mut ramm,
                lp_eth,
                &eth_aggr,
                &usdt_aggr,
                &matic_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(matic_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            // The liquidity provider should have about 200.05 ETH, with the 0.05 ETH
            // being the result of collected fees.
            test_utils::assert_eq(coin::value(&eth), 20000518458);
            test_scenario::return_to_address(ADMIN, eth);
        };


        test_scenario::end(scenario_val);
    }

    #[test]
    /// Test the `trade_amount_out_3` function.
    /// This function is used for RAMM withdrawals i.e. the trader specifies exactly how much
    /// of an asset they desire, and provide an upper bound of the inbound asset,
    /// being returned the remainder.
    fun test_trade_o() {
        let (ramm_id, eth_ag_id, matic_ag_id, usdt_ag_id, scenario_val) = test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, BOB);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            // First trade: ETH in, USDT out
            let max_ai = coin::mint_for_testing<ETH>(10 * (test_util::eth_factor() as u64), test_scenario::ctx(scenario));
            // With the test scenario's price of `1800 USDT/ETH`, it'll take `16200 USDT` for `9 ETH`.
            interface3::trade_amount_out_3<ETH, USDT, MATIC>(
                &mut ramm,
                16_200 * (test_util::usdt_factor() as u64),
                max_ai,
                &eth_aggr,
                &usdt_aggr,
                &matic_aggr,
                test_scenario::ctx(scenario)
            );

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 20900835553);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 20900835553);

            test_utils::assert_eq(ramm::get_balance<MATIC>(&ramm), 200_000 * test_util::matic_factor());
            test_utils::assert_eq(ramm::get_typed_balance<MATIC>(&ramm), 200_000 * test_util::matic_factor());

            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), 383_800 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), 383_800 * test_util::usdt_factor());

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 450643);
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
}