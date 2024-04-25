#[test_only]
module ramm_sui::volatility2_tests {
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, TransactionEffects};
    use sui::test_utils;

    use ramm_sui::interface2;
    use ramm_sui::oracles;
    use ramm_sui::ramm::{Self, LP, RAMM};
    use ramm_sui::test_util::{Self, BTC, ETH, USDT};

    use switchboard_std::aggregator::Aggregator;

    const PRECISION_DECIMAL_PLACES: u8 = 12;
    const PRICE_TIMESTAMP_STALENESS_THRESHOLD: u64 = 60 * 60 * 1000;
    const ONE: u256 = 1_000_000_000_000;
    const BASE_FEE: u256 = 10 * 1_000_000_000_000 / 10000;
    const PROTOCOL_FEE: u256 = 30 * 1_000_000_000_000 / 100;
    const BASE_WITHDRAWAL_FEE: u256 = 40 * 1_000_000_000_000 / 10000;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;

    const ETraderShouldHaveAsset: u64 = 0;
    const ETraderShouldNotHaveAsset: u64 = 0;

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
        let (ramm_id, eth_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_eth_usdt(ADMIN);
        let scenario = &mut scenario_val;

        // First part of the test: the RAMM's admin, who also happens to have administrative rights
        // for all its `Aggregator`s, updates the price for the `ETH` and `USDT` feed.

        test_scenario::next_tx(scenario, ADMIN);

        {
            let clock = test_scenario::take_shared<Clock>(scenario);
            let mut eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let mut usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let current_timestamp: u64 = clock::timestamp_ms(&clock);

            let (price_eth, scaling_eth, timestamp_eth) = oracles::get_price_from_oracle(
                    &eth_aggr,
                    current_timestamp,
                    PRICE_TIMESTAMP_STALENESS_THRESHOLD,
                    PRECISION_DECIMAL_PLACES
                );
            let (price_usdt, scaling_usdt, timestamp_usdt) = oracles::get_price_from_oracle(
                    &usdt_aggr,
                    current_timestamp,
                    PRICE_TIMESTAMP_STALENESS_THRESHOLD,
                    PRECISION_DECIMAL_PLACES
                );

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

            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        // Second part of the test: a trader, Alice, wishes to sell 10,000 USDT to the pool
        // for ETH, with the new price of 2100 USDT/ETH.
        test_scenario::next_tx(scenario, ALICE);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
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

            let total_usdt: u256 = 900000_000000;
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
                &clock,
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
            // test USDT has 6 decimal places of precision - hence, the correction below by 10^6,
            // or 1_000_000.
            let total_trade_fee: u256 = ramm::mul3(PROTOCOL_FEE, BASE_FEE + 10 * ONE / 100, 10_000 * ONE) / 1_000_000;
            test_utils::assert_eq(ramm::get_balance<USDT>(&ramm), total_usdt + (usdt_trade_amount - total_trade_fee));
            test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), total_usdt + (usdt_trade_amount - total_trade_fee));

            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), (total_trade_fee as u64));

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 500 * test_util::eth_factor());

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
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
        let (ramm_id, eth_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_eth_usdt(ADMIN);
        let scenario = &mut scenario_val;

        // First part of the test: the RAMM's admin, who also happens to have administrative rights
        // for all its `Aggregator`s, updates the price for the `ETH` and `USDT` feed.

        test_scenario::next_tx(scenario, ADMIN);

        {
            let clock = test_scenario::take_shared<Clock>(scenario);
            let mut eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let mut usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let current_timestamp: u64 = clock::timestamp_ms(&clock);

            let (price_eth, scaling_eth, timestamp_eth) = oracles::get_price_from_oracle(
                    &eth_aggr,
                    current_timestamp,
                    PRICE_TIMESTAMP_STALENESS_THRESHOLD,
                    PRECISION_DECIMAL_PLACES
                );
            let (price_usdt, scaling_usdt, timestamp_usdt) = oracles::get_price_from_oracle(
                    &usdt_aggr,
                    current_timestamp,
                    PRICE_TIMESTAMP_STALENESS_THRESHOLD,
                    PRECISION_DECIMAL_PLACES
                );

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

            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        // The trader sends 12k USDT to the RAMM
        let usdt_trade_amount: u256 = 12_000 * test_util::usdt_factor();

        let total_usdt: u256 = 900000_000000;
        // Second part of the test: a trader, Alice, wishes to buy 5 ETH
        // from the ETH/USDT RAMM, with the new price of 2100 USDT per ETH.
        test_scenario::next_tx(scenario, ALICE);
        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
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
                &clock,
                5 * (test_util::eth_factor() as u64),
                max_ai,
                &usdt_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
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

    #[test]
    /// Test for interaction between volatility fee and liquidity deposits.
    ///
    /// Inbound/outbound deposit*LP token amounts should not be affected by volatility, but they should
    /// still update the RAMM's internal volatility data after each asset's respective oracle query.
    fun liquidity_deposit_2_volatility_test() {
        let (ramm_id, btc_ag_id, eth_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_btc_eth_no_liq(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ADMIN);
        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let mut btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, btc_ag_id);
            let mut eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);

            let current_timestamp: u64 = clock::timestamp_ms(&clock);

            let (price_btc, scaling_btc, timestamp_btc) = oracles::get_price_from_oracle(
                    &btc_aggr,
                    current_timestamp,
                    PRICE_TIMESTAMP_STALENESS_THRESHOLD,
                    PRECISION_DECIMAL_PLACES
                );
            let (price_eth, scaling_eth, timestamp_eth) = oracles::get_price_from_oracle(
                    &eth_aggr,
                    current_timestamp,
                    PRICE_TIMESTAMP_STALENESS_THRESHOLD,
                    PRECISION_DECIMAL_PLACES
                );

            //
            // First part of the test: pre-deposit, pre-aggregator checks
            //

            // Check that the initial prices, price scaling factors, and price timestamps
            // all match their expected values.
            test_utils::assert_eq(price_btc, 27_800_000_000_000);
            test_utils::assert_eq(scaling_btc, 1_000);
            test_utils::assert_eq(timestamp_btc, 0);

            test_utils::assert_eq(price_eth, 1_880_000_000_000);
            test_utils::assert_eq(scaling_eth, 1_000);
            test_utils::assert_eq(timestamp_eth, 0);

            // Pre-deposit volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<BTC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<BTC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 0);

            test_utils::assert_eq(ramm::get_volatility_index<BTC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<BTC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 0);
            //

            //
            // Second part of the test: the RAMM's admin, who also happens to have administrative
            // rights for all its `Aggregator`s,
            // 1. deposits BTC liquidity, and then
            // 2. updates the price for the `BTC` and `ETH` feeds.
            //

            let amount_in = coin::mint_for_testing<BTC>(
                (10 * test_util::btc_factor() as u64),
                test_scenario::ctx(scenario)
            );
            interface2::liquidity_deposit_2<BTC, ETH>(
                &mut ramm,
                &clock,
                amount_in,
                &btc_aggr,
                &eth_aggr,
                test_scenario::ctx(scenario)
            );

            // increase the BTC price by 5%
            test_util::set_aggregator_value(
                29_190_000_000_000,
                9,
                false,
                &mut btc_aggr,
                timestamp_btc + 30,
                test_scenario::ctx(scenario)
            );
            // increase the ETH price by 5%
            test_util::set_aggregator_value(
                1_974_000_000_000,
                9,
                false,
                &mut eth_aggr,
                timestamp_eth + 30,
                test_scenario::ctx(scenario)
            );

            //
            // Third part of the test: the RAMM's admin deposits ETH liquidity
            //

            // Post-first-deposit volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<BTC>(&ramm), 27_800_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<BTC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 1_880_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 0);

            test_utils::assert_eq(ramm::get_volatility_index<BTC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<BTC>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 0);
            //

            let amount_in = coin::mint_for_testing<ETH>(
                (100 * test_util::eth_factor() as u64),
                test_scenario::ctx(scenario)
            );
            interface2::liquidity_deposit_2<ETH, BTC>(
                &mut ramm,
                &clock,
                amount_in,
                &eth_aggr,
                &btc_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<Aggregator>(eth_aggr);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ADMIN);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 2);

        //
        // Fourth part of the test: checks to the RAMM's internal state are made,
        // and it must be consistent with both the 2 liquidity deposits, and the
        // price feed updates.
        //
        // Furthermore, the volatility should not affect the amount of minted LP tokens.
        //
        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);

            // Post-second-deposit volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<BTC>(&ramm), 29_190_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<BTC>(&ramm), 30);
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 1_974_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 30);

            test_utils::assert_eq(ramm::get_volatility_index<BTC>(&ramm), 5 * ONE / 100);
            test_utils::assert_eq(ramm::get_volatility_timestamp<BTC>(&ramm), 30);
            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 5 * ONE / 100);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 30);
            //

            let lp_btc = test_scenario::take_from_address<Coin<LP<BTC>>>(scenario, ADMIN);
            let lp_eth = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, ADMIN);

            test_utils::assert_eq(ramm::get_lptokens_issued<BTC>(&ramm), 10 * test_util::btc_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<BTC>(&ramm), 10 * test_util::btc_factor());
            test_utils::assert_eq(coin::value(&lp_btc), (10 * test_util::btc_factor() as u64));

            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 100 * test_util::eth_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 100 * test_util::eth_factor());
            test_utils::assert_eq(coin::value(&lp_eth), (100 * test_util::eth_factor() as u64));

            test_scenario::return_to_address(ADMIN, lp_btc);
            test_scenario::return_to_address(ADMIN, lp_eth);
            test_scenario::return_shared<RAMM>(ramm);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Given a 2-asset ETH/USDT RAMM, with an initial ETH price of 2000 USDT,
    /// 1. increase the price of the `ETH`/USDT `Aggregator`s by 5%
    /// 2. perform a `liquidity_withdrawal_2` of ETH
    /// 3. verify that the applied volatility fee was 5% on top of the expected 0.4% base
    ///    liquidity withdrawal fee
    ///
    /// The applied fee to the withdrawal would be 5.4%:
    /// - 5% volatility for outbound asset, plus
    /// - 0.4% base liquidity withdrawal fee
    fun liquidity_withdrawal_2_volatility_test() {
        let (ramm_id, eth_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_eth_usdt(ADMIN);
        let scenario = &mut scenario_val;

        // First part of the test: the RAMM's admin, who also happens to have administrative rights
        // for all its `Aggregator`s, updates the price for the `ETH` and `USDT` feed.

        test_scenario::next_tx(scenario, ADMIN);

        {
            let clock = test_scenario::take_shared<Clock>(scenario);
            let mut eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let mut usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let current_timestamp: u64 = clock::timestamp_ms(&clock);

            let (price_eth, scaling_eth, timestamp_eth) = oracles::get_price_from_oracle(
                    &eth_aggr,
                    current_timestamp,
                    PRICE_TIMESTAMP_STALENESS_THRESHOLD,
                    PRECISION_DECIMAL_PLACES
                );
            let (price_usdt, scaling_usdt, timestamp_usdt) = oracles::get_price_from_oracle(
                    &usdt_aggr,
                    current_timestamp,
                    PRICE_TIMESTAMP_STALENESS_THRESHOLD,
                    PRECISION_DECIMAL_PLACES
                );

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

            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        //
        // Second part of the test: the admin wishes to withdraw all of their deposited 500 ETH
        // from the pool
        //
        test_scenario::next_tx(scenario, ADMIN);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            // Pre-withdrawal volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 2_000_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_previous_price<USDT>(&ramm), 1_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<USDT>(&ramm), 0);

            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_index<USDT>(&ramm), 0);
            test_utils::assert_eq(ramm::get_volatility_timestamp<USDT>(&ramm), 0);
            //

            let lp_eth: Coin<LP<ETH>> = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, ADMIN);
            interface2::liquidity_withdrawal_2<ETH, USDT, ETH>(
                &mut ramm,
                &clock,
                lp_eth,
                &eth_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        //
        // Third part of the test: post-trade, check that
        // 1. The RAMM has updated each asset's previously recorded prices/timestamps
        // 2. the levied volatlity fee was 5%, which is the volatility fee of the outbound asset;
        //    the price of the RAMM's other asset also changed by 5% in the last `TAU` seconds, but
        //    it is not relevant for withdrawals.
        //
        test_scenario::next_tx(scenario, ADMIN);
        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            assert!(!test_scenario::has_most_recent_for_address<Coin<LP<ETH>>>(ADMIN), ETraderShouldNotHaveAsset);
            assert!(test_scenario::has_most_recent_for_address<Coin<ETH>>(ADMIN), ETraderShouldHaveAsset);

            // Post-withdrawal volatility data checks
            test_utils::assert_eq(ramm::get_previous_price<ETH>(&ramm), 2_100_000_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<ETH>(&ramm), 30);
            test_utils::assert_eq(ramm::get_previous_price<USDT>(&ramm), 1_050_000_000);
            test_utils::assert_eq(ramm::get_previous_price_timestamp<USDT>(&ramm), 30);

            test_utils::assert_eq(ramm::get_volatility_index<ETH>(&ramm), 5 * ONE / 100);
            test_utils::assert_eq(ramm::get_volatility_timestamp<ETH>(&ramm), 30);
            test_utils::assert_eq(ramm::get_volatility_index<USDT>(&ramm), 5 * ONE / 100);
            test_utils::assert_eq(ramm::get_volatility_timestamp<USDT>(&ramm), 30);
            //

            test_utils::assert_eq(ramm::get_balance<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), 0);

            let eth = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            // Recall that the RAMM uses 12 decimal places for internal calculations, and that
            // test ETH has 8 decimal places of precision - hence, the correction below by 10^4,
            // or 10_000.
            let withdrawal_amnt: u256 = ramm::mul(ONE - (BASE_WITHDRAWAL_FEE + 5 * ONE / 100), 500 * ONE) / 10_000;
            test_utils::assert_eq(withdrawal_amnt, (coin::value(&eth) as u256));
            test_utils::assert_eq(withdrawal_amnt, (coin::value(&eth) as u256));

            // See above for explanation on correction by 10^4.
            let withdrawal_fee: u256 = ramm::mul(BASE_WITHDRAWAL_FEE + 5 * ONE / 100, 500 * ONE) / 10_000;
            test_utils::assert_eq(ramm::get_collected_protocol_fees<ETH>(&ramm), (withdrawal_fee as u64));
            test_utils::assert_eq(ramm::get_collected_protocol_fees<USDT>(&ramm), 0);

            // Check that the RAMM should correctly state that there are 0 circulating ETH LP tokens.
            test_utils::assert_eq(ramm::get_lptokens_issued<ETH>(&ramm), 0);
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<ETH>(&ramm), 0);

            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());
            test_utils::assert_eq(ramm::get_typed_lptokens_issued<USDT>(&ramm), 900_000 * test_util::usdt_factor());

            test_scenario::return_to_address(ADMIN, eth);
            test_scenario::return_shared<RAMM>(ramm);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ALICE);
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 0);

        {
            // the trader should not have any ETH LP tokens
            assert!(!test_scenario::has_most_recent_for_address<Coin<LP<ETH>>>(ALICE), ETraderShouldNotHaveAsset);
        };

        test_scenario::end(scenario_val);
    }
}