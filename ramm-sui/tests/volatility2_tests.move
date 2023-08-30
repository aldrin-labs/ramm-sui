#[test_only]
module ramm_sui::volatility2_tests {

    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, TransactionEffects};
    use sui::test_utils;

    use ramm_sui::interface2;
    use ramm_sui::ramm::{Self, RAMM};
    use ramm_sui::test_util::{Self, ETH, USDT};

    use switchboard::aggregator::Aggregator;

    const ONE: u256 = 1_000_000_000_000;
    const BASE_FEE: u256 = 10 * 1_000_000_000_000 / 10000;
    const PROTOCOL_FEE: u256 = 30 * 1_000_000_000_000 / 100;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;
    const BOB: address = @0xBACE;

    const ETraderShouldHaveAsset: u64 = 0;
    const ETraderShouldNotHaveAsset: u64 = 0;
    const EFeeCollectionError: u64 = 2;

    #[test]
    /// Given a 2-asset ETH/USDT RAMM, with an initial ETH price of 2000 USDT,
    /// 1. increase the price of the `ETH`/USDT `Aggregator`s by 5%
    /// 2. perform a `trade_amount_in_2` of USDT for ETH
    /// 3. verify that the applied volatility fee was 10% on top of the expected 0.1% base fee
    ///
    /// The applied fee to the trade, which would the RAMM's first (hence with undisturbed
    /// imbalance ratios), would be 3.03%:
    /// - total trade fee is 10.1%
    ///     - 5% volatility for inbound asset, plus
    ///     - 5% outbound asset volatility, plus
    ///     - 0.1% base trading fee
    /// - protocol fee is 30% of the total, so 3.03%
    fun trade_amount_in_2_volatility_test() {
        let (ramm_id, eth_ag_id, usdt_ag_id, scenario_val) = test_util::create_ramm_test_scenario_eth_usdt(ADMIN);
        let scenario = &mut scenario_val;

        // First part of the test: the RAMM's admin, who also happens to have administrative rights
        // for all its `Aggregator`s, updates the price for the `ETH` and `USDT` feed.

        test_scenario::next_tx(scenario, ADMIN);

        {
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let (price_eth, scaling_eth, timestamp_eth) = ramm::get_price_from_oracle(&eth_aggr);
            let (price_usdt, scaling_usdt, timestamp_usdt) = ramm::get_price_from_oracle(&usdt_aggr);

            // Check that the initial prices, price scaling factors, and price timestamps
            // all match their expected values.
            test_utils::assert_eq(price_eth, 2_000_000_000_000);
            test_utils::assert_eq(scaling_eth, 1_000);
            test_utils::assert_eq(timestamp_eth, 0);

            test_utils::assert_eq(price_usdt, 1_000_000_000);
            test_utils::assert_eq(scaling_usdt, 1_000);
            test_utils::assert_eq(timestamp_usdt, 0);

            // increase the ETH price by 5%
            test_util::set_aggregator_value(
                2_100_000_000_000,
                9,
                false,
                &mut eth_aggr,
                timestamp_eth + 30,
                test_scenario::ctx(scenario)
            );
            // increase the USDT price by 5%
            test_util::set_aggregator_value(
                1_050_000_000,
                9,
                false,
                &mut usdt_aggr,
                timestamp_usdt + 30,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        // Second part of the test: a trader, Alice, wishes to sell 10,000 USDT to the pool
        // for ETH, with the new price of 2100 USDT/ETH.
        test_scenario::next_tx(scenario, ALICE);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            // Pre-trade volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 2_000_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_previous_price<USDT>(&ramm), 1_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<USDT>(&ramm), 0);

            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_index<USDT>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<USDT>(&ramm), 0);
            //

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 500 * test_util::eth_factor());

            let total_usdt: u256 = 900000_00000000;
            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), total_usdt);
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), total_usdt);

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            // The trader sends 10k USDT to the RAMM
            let usdt_trade_amount: u256 = 10_000 * test_util::usdt_factor();

            let amount_in = coin::mint_for_testing<USDT>((usdt_trade_amount as u64), test_scenario::ctx(scenario));
            interface2::trade_amount_in_2<USDT, ETH>(
                &mut ramm,
                amount_in,
                4 * (test_util::eth_factor() as u64),
                &usdt_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            // Third part of the test: post-trade, check that
            // 1. The RAMM has updated each asset's previously recorded prices/timestamps
            // 2. the levied volatlity fee was 10%, the sum of volatility in the last `TAU`
            //    seconds for both the inbound and outbound asset

            // Post-trade volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 2_100_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 30);
            test_utils::assert_eq(ramm::get_previous_price<USDT>(&ramm), 1_050_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<USDT>(&ramm), 30);

            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 5 * ONE / 100);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 30);
            test_utils::assert_eq(ramm::get_volatility_index<USDT>(&ramm), 5 * ONE / 100);
            test_utils::assert_eq(ramm::get_volatility_timestamp<USDT>(&ramm), 30);
            //

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 495_50542655);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 495_50542655);

            // Recall that the RAMM uses 12 decimal places for internal calculations, and that
            // test USDT has 8 decimal places of precision - hence, the correction below by 10^4,
            // or 10_000.
            let total_trade_fee: u256 = ramm::mul3(PROTOCOL_FEE, BASE_FEE + 10 * ONE / 100, 10_000 * ONE) / 10_000;
            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), total_usdt + (usdt_trade_amount - total_trade_fee));
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), total_usdt + (usdt_trade_amount - total_trade_fee));

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), (total_trade_fee as u64));

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ALICE);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        {
            // the trader should not have any USDT
            assert!(!test_scenario::has_most_recent_for_address<Coin<USDT>>(ALICE), ETraderShouldNotHaveAsset);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Given a 2-asset ETH/USDT RAMM, with an initial ETH price of 2000 USDT,
    /// 1. increase the price of the `ETH`/USDT `Aggregator`s by 5%
    /// 2. perform a `trade_amount_out_2` of USDT for ETH
    /// 3. verify that the applied volatility fee was 10% on top of the expected 0.1% base fee
    ///
    /// The applied fee to the trade, which would the RAMM's first (hence with undisturbed
    /// imbalance ratios), would be 3.03%:
    /// - total trade fee is 10.1%
    ///     - 5% volatility for inbound asset, plus
    ///     - 5% outbound asset volatility, plus
    ///     - 0.1% base trading fee
    /// - protocol fee is 30% of the total, so 3.03%
    fun trade_amount_out_2_volatility_test() {
        let (ramm_id, eth_ag_id, usdt_ag_id, scenario_val) = test_util::create_ramm_test_scenario_eth_usdt(ADMIN);
        let scenario = &mut scenario_val;

        // First part of the test: the RAMM's admin, who also happens to have administrative rights
        // for all its `Aggregator`s, updates the price for the `ETH` and `USDT` feed.

        test_scenario::next_tx(scenario, ADMIN);

        {
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let (price_eth, scaling_eth, timestamp_eth) = ramm::get_price_from_oracle(&eth_aggr);
            let (price_usdt, scaling_usdt, timestamp_usdt) = ramm::get_price_from_oracle(&usdt_aggr);

            // Check that the initial prices, price scaling factors, and price timestamps
            // all match their expected values.
            test_utils::assert_eq(price_eth, 2_000_000_000_000);
            test_utils::assert_eq(scaling_eth, 1_000);
            test_utils::assert_eq(timestamp_eth, 0);

            test_utils::assert_eq(price_usdt, 1_000_000_000);
            test_utils::assert_eq(scaling_usdt, 1_000);
            test_utils::assert_eq(timestamp_usdt, 0);

            // increase the ETH price by 5%
            test_util::set_aggregator_value(
                2_100_000_000_000,
                9,
                false,
                &mut eth_aggr,
                timestamp_eth + 30,
                test_scenario::ctx(scenario)
            );
            // increase the USDT price by 5%
            test_util::set_aggregator_value(
                1_050_000_000,
                9,
                false,
                &mut usdt_aggr,
                timestamp_usdt + 30,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        // The trader sends 12k USDT to the RAMM
        let usdt_trade_amount: u256 = 12_000 * test_util::usdt_factor();

        let total_usdt: u256 = 900000_00000000;
        // Second part of the test: a trader, Alice, wishes to buy 5 ETH
        // from the ETH/USDT RAMM, with the new price of 2100 USDT per ETH.
        test_scenario::next_tx(scenario, ALICE);
        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            // Pre-trade volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 2_000_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_previous_price<USDT>(&ramm), 1_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<USDT>(&ramm), 0);

            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_index<USDT>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<USDT>(&ramm), 0);
            //

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 500 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), total_usdt);
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), total_usdt);

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            let max_ai = coin::mint_for_testing<USDT>((usdt_trade_amount as u64), test_scenario::ctx(scenario));
            interface2::trade_amount_out_2<USDT, ETH>(
                &mut ramm,
                5 * (test_util::eth_factor() as u64),
                max_ai,
                &usdt_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ALICE);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        // Third part of the test: post-trade, check that
        // 1. The RAMM has updated each asset's previously recorded prices/timestamps
        // 2. the levied volatlity fee was 10%, the sum of volatility in the last `TAU`
        //    seconds for both the inbound and outbound asset
        {
            // the trader should have some remaining USDT
            assert!(test_scenario::has_most_recent_for_address<Coin<USDT>>(ALICE), ETraderShouldHaveAsset);
            let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, ALICE);
            let remaining_usdt: u256 = (coin::value(&usdt) as u256);

            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);

            // Post-trade volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 2_100_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 30);
            test_utils::assert_eq(ramm::get_previous_price<USDT>(&ramm), 1_050_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<USDT>(&ramm), 30);

            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 5 * ONE / 100);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 30);
            test_utils::assert_eq(ramm::get_volatility_index<USDT>(&ramm), 5 * ONE / 100);
            test_utils::assert_eq(ramm::get_volatility_timestamp<USDT>(&ramm), 30);
            //

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 495_00000000);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 495_00000000);

            // Recall that the RAMM uses 12 decimal places for internal calculations, and that
            // test USDT has 8 decimal places of precision - hence, a correction by 10^4, or
            // 10_000 is necessary.
            //
            // However, note that the third multiplicand represents a USDT amount with 8 decimal
            // places, so it can be interpreted as a quantity with 12 decimal places that has already
            // been divided by 10^4.
            let total_trade_fee: u256 = ramm::mul3(PROTOCOL_FEE, BASE_FEE + 10 * ONE / 100, usdt_trade_amount - remaining_usdt);
            let usdt_in: u256 =
                ramm::mul(
                    ONE - ramm::mul(PROTOCOL_FEE, BASE_FEE + 10 * ONE / 100),
                    usdt_trade_amount - remaining_usdt
                );

            // Because the amounts below can be represented only imprecisely with integers, it only
            // makes sense to compare them within a given `eps`, in this case 1 in 10^12 parts, or one
            // in one trillion parts.
            test_util::assert_eq_eps(ramm::get_balance<USDT>(&ramm), total_usdt + usdt_in, 1);
            test_util::assert_eq_eps(ramm::get_typed_balance<USDT>(&ramm), total_usdt + usdt_in, 1);

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), (total_trade_fee as u64));

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            test_scenario::return_to_address(ALICE, usdt);
            test_scenario::return_shared<RAMM>(ramm);
        };

        test_scenario::end(scenario_val);
    }
}