#[test_only]
module ramm_sui::interface2_tests {
    //use std::debug;

    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, TransactionEffects};
    use sui::test_utils;

    use ramm_sui::interface2;
    use ramm_sui::math;
    use ramm_sui::ramm::{Self, LP, RAMM, RAMMAdminCap};
    use ramm_sui::test_util::{Self, ETH, USDT};

    use switchboard::aggregator::Aggregator;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;

    const ETraderShouldHaveAsset: u64 = 0;
    const EFeeCollectionError: u64 = 1;

    #[test]
    /// Given a 2-asset ETH/USDT RAMM, with an initial ETH price of 2000 USDT,
    /// perform the trades in the whitepaper's second practical example.
    /// 1. First, a purchase of 20 ETH
    /// 2. Next, a redemption of every LPETH token by a provider
    /// 3. Finally, a redemption of every LPUSDT token by a provider
    fun liquidity_withdrawal_2_test() {
        let (ramm_id, eth_ag_id, usdt_ag_id, scenario_val, clock) = test_util::create_ramm_test_scenario_eth_usdt(ADMIN);
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
                &clock,
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
            let usdt_trade_fees = 1_201_708_581;

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
                &clock,
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
                &clock,
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

    #[test]
    /// Test for fee collection after a trade.
    ///
    /// After a trader sells 10 ETH to a perfectly balanced pool:
    /// * the admin should receive 0.03 ETH (or 300000 units when using 8 decimal places) of
    ///   protocol fees from this trade, and 0 of any other asset.
    /// * futhermore, the RAMM's fees should be null after the collection
    fun collect_fees_2_test_1() {
        let (ramm_id, eth_ag_id, usdt_ag_id, scenario_val, clock) = test_util::create_ramm_test_scenario_eth_usdt(ADMIN);
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

        // Trade: 10 ETH in, roughly 20k USDT out
        // The pool is fresh, so all imbalance ratios are 1
        let eth_trade_fee: u256 = {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let initial_eth_balance: u256 = ramm::get_typed_balance<ETH>(&ramm);
            let initial_usdt_balance: u256 = ramm::get_typed_balance<USDT>(&ramm);
            test_utils::assert_eq(initial_eth_balance, 500 * test_util::eth_factor());
            test_utils::assert_eq(initial_usdt_balance, 900_000 * test_util::eth_factor());

            let amount_in = coin::mint_for_testing<ETH>(eth_trade_amount, test_scenario::ctx(scenario));
            interface2::trade_amount_in_2<ETH, USDT>(
                &mut ramm,
                &clock,
                amount_in,
                16_000 * (test_util::usdt_factor() as u64),
                &eth_aggr,
                &usdt_aggr,
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
            
            // The pool should have received 9.97 ETH to its balance of 500, and no other asset.
            test_utils::assert_eq(
                new_eth_balance,
                initial_eth_balance + input_eth
            );
            // There should be a non-zero outflow of USDT
            test_util::assert_lt(
                ramm::get_typed_balance<USDT>(&ramm),
                initial_usdt_balance,
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);

            trade_fee
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        // Next step: collect the RAMM fees to the collection address (in this case, the admin's)

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);

            interface2::collect_fees_2<ETH, USDT>(
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
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            // Check that the RAMM admin has been return an appropriate ammount of funds as fees
            // Since the imbalance ratios were all 1 before the trade, the fee applied
            // will have been the base fee of 0.1%, 30% of which will be protocol fees
            // collected by the pool, which is what the admin will have access to.
            let eth_fees = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&eth_fees), (eth_trade_fee as u64));

            // Check that the admin has not received any funds other than the fees collected from
            // the ETH/USDT trade, which should be denominated in ETH.
            assert!(!test_scenario::has_most_recent_for_address<Coin<USDT>>(ADMIN), EFeeCollectionError);

            test_scenario::return_to_address<Coin<ETH>>(ADMIN, eth_fees);
            test_scenario::return_shared<RAMM>(ramm);
        }; 

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Test for fee collection after a liquidity withdrawal.
    ///
    /// After the pool's admin withdraws all of their 500 ETH liquidity from a perfectly balanced pool:
    /// * the admin should receive 0.8 ETH (or 8000000 units when using 8 decimal places) of
    ///   protocol fees from this withdrawal, and 0 of any other asset.
    /// * futhermore, the RAMM's fees should be null after the collection
    fun collect_fees_2_test_2() {
        let (ramm_id, eth_ag_id, usdt_ag_id, scenario_val, clock) = test_util::create_ramm_test_scenario_eth_usdt(ADMIN);
        let scenario = &mut scenario_val;

        let prec: u8 = test_util::eth_dec_places();
        let max_prec: u8 = 2 * test_util::eth_dec_places();
        let one: u256 = test_util::eth_factor();
        let liq_wthdrwl_fee: u256 = 40 * one / 10000;

        test_scenario::next_tx(scenario, ADMIN);

        // First step: the admin withdraws the ETH they've provided to the pool
        let (initial_eth_balance, initial_usdt_balance): (u256, u256) = {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let init_eth: u256 = ramm::get_typed_balance<ETH>(&ramm);
            let init_usdt: u256 = ramm::get_typed_balance<USDT>(&ramm);
            let lp_eth = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_eth), (init_eth as u64));

            interface2::liquidity_withdrawal_2<ETH, USDT, ETH>(
                &mut ramm,
                &clock,
                lp_eth,
                &eth_aggr,
                &usdt_aggr,
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
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);

            (init_eth, init_usdt)
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        // Second step: the admin performs the fee collection
        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);

            interface2::collect_fees_2<ETH, USDT>(
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
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), initial_usdt_balance);

            // Check that the RAMM has no more fees to collect
            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
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