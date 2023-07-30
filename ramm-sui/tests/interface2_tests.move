#[test_only]
module ramm_sui::interface2_tests {
    //use std::debug;

    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, TransactionEffects};
    use sui::test_utils;

    use ramm_sui::interface2;
    use ramm_sui::ramm::{Self, LP,  RAMM};
    use ramm_sui::test_util::{Self, ETH, USDT};

    use switchboard::aggregator::Aggregator;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;
    const BOB: address = @0xBACE;

    const ETraderShouldHaveAsset: u64 = 0;

    #[test]
    /// Given a 2-asset ETH/USDT RAMM, with an initial ETH price of 2000 USDT,
    /// perform the trades in the whitepaper's second practical example.
    /// 1. First, a purchase of 20 ETH
    /// 2. Next, a redemption of every LPETH token by a provider
    /// 3. Finally, a redemption of every LPUSDT token by a provider
    fun liquidity_withdrawal_2_test() {
        let (ramm_id, eth_ag_id, usdt_ag_id, scenario_val) = test_util::create_testing_ramm_eth_udst(ADMIN);
        let scenario = &mut scenario_val;

        // First part of the test: a trader, Alice, wishes to buy 20 ETH
        // from the ETH/USDT RAMM, with the current price of 2000 USDT per ETH.

        test_scenario::next_tx(scenario, ALICE);

        let (total_usdt, usdt_trade_fees) : (u256, u256) = {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            // First trade: ETH in, USDT out

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 500 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());


            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            // Recall that for this example, the price for Ether is 2000 USDT, and the trader
            // wishes to buy exactly 20 ETH from the pool, so `trade_amount_out` is used.
            let max_ai = coin::mint_for_testing<USDT>(41_000 * (test_util::usdt_factor() as u64), test_scenario::ctx(scenario));
            interface2::trade_amount_out_2<USDT, ETH>(
                &mut ramm,
                (20 * test_util::eth_factor() as u64),
                max_ai,
                &usdt_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 480 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 480 * test_util::eth_factor());

            let total_usdt: u256 = 940044_93561689;
            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), total_usdt);
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), total_usdt);

            // Later in the test, when accounting for all the USDT given to liquidity providers
            // and comparing it to the pool's USDT balance, liquidity withdrawal fees count toward
            // this tally, but protocol trading fees do not - they must be removed from the count.
            let usdt_trade_fees = ramm::get_collected_protocol_fees<USDT>(&ramm);

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), usdt_trade_fees);

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);

            (total_usdt, (usdt_trade_fees as u256))
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ALICE);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        {
            assert!(test_scenario::has_most_recent_for_address<Coin<USDT>>(ALICE), ETraderShouldHaveAsset);
        };

        // Next part of the test:
        // The admin, who also happens to be a liquidity provider for the pool,
        // wishes to exchange their 300 LPETH tokens.

        test_scenario::next_tx(scenario, ADMIN);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let lp_eth = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_eth), (500 * test_util::eth_factor() as u64));

            interface2::liquidity_withdrawal_2<ETH, USDT, ETH>(
                &mut ramm,
                lp_eth,
                &eth_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        // Quick check of the funds returned to the admin after liquidity withdrawal.
        let fst_usdt_wthdrwl: u256 = {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let eth = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&eth), (47808 * test_util::eth_factor() / 100 as u64));
            let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, ADMIN);
            let first_usdt_wthdrwl: u256 = 39863_55571872;
            test_utils::assert_eq((coin::value(&usdt) as u256), first_usdt_wthdrwl);

            test_scenario::return_to_address(ADMIN, eth);
            test_scenario::return_to_address(ADMIN, usdt);
            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);

            first_usdt_wthdrwl
        };

        // Next part of the test:
        // The admin wishes to withdraw liquidity with the LPUSDT tokens they have.

        test_scenario::next_tx(scenario, ADMIN);

        let collected_usdt_liquidity_withdrawal_fees: u256 =
        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let lp_usdt = test_scenario::take_from_address<Coin<LP<USDT>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_usdt), (900_000 * test_util::usdt_factor() as u64));

            interface2::liquidity_withdrawal_2<ETH, USDT, USDT>(
                &mut ramm,
                lp_usdt,
                &eth_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            let usdt_fees = (ramm::get_collected_protocol_fees<USDT>(&ramm) as u256);

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);

            // Remember to remove trading fees from total fee count to avoid counting them twice
            usdt_fees - usdt_trade_fees
        };

        test_scenario::next_tx(scenario, ADMIN);
        let snd_udst_wthdrwl: u256 = {
            let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, ADMIN);

            let snd_udst_wthdrwl: u256 = 896421_20015571;
            test_utils::assert_eq((coin::value(&usdt) as u256), snd_udst_wthdrwl);
            test_scenario::return_to_address(ADMIN, usdt);

            snd_udst_wthdrwl
        };

        // Check that the sum of USDT amounts given to liquidity providers PLUS the collected
        // liquidity withdrawal fees match the total USDT balance of the pool after the trade.
        test_utils::assert_eq(
            collected_usdt_liquidity_withdrawal_fees + fst_usdt_wthdrwl + snd_udst_wthdrwl,
            total_usdt
        );

        test_scenario::end(scenario_val);
    }
}