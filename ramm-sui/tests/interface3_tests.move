#[test_only]
module ramm_sui::interface3_tests {
    //use std::debug;

    use sui::coin;
    use sui::test_scenario;
    use sui::test_utils;
    use sui::vec_map::{Self, VecMap};

    use ramm_sui::interface3;
    use ramm_sui::ramm::{Self, RAMM};
    use ramm_sui::test_util::{Self, ETH, MATIC, USDT};

    use switchboard::aggregator::Aggregator;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;
    const BOB: address = @0xBACE;

    #[test] fun test_trade_i() {
        let asset_prices: VecMap<u8, u128> = vec_map::empty();
        vec_map::insert(&mut asset_prices, 0, 1800000000000);
        vec_map::insert(&mut asset_prices, 1, 1200000000);
        vec_map::insert(&mut asset_prices, 2, 1000000000);
        let asset_price_scales: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_price_scales, 0, 9);
        vec_map::insert(&mut asset_price_scales, 1, 9);
        vec_map::insert(&mut asset_price_scales, 2, 9);
        let asset_minimum_trade_amounts: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut asset_minimum_trade_amounts, 0, 1 * (test_util::eth_factor() as u64) / 1000);
        vec_map::insert(&mut asset_minimum_trade_amounts, 1, 1 * (test_util::matic_factor() as u64));
        vec_map::insert(&mut asset_minimum_trade_amounts, 2, 1 * (test_util::usdt_factor() as u64));
        let asset_decimal_places: VecMap<u8, u8> = vec_map::empty();
        vec_map::insert(&mut asset_decimal_places, 0, test_util::eth_dec_places());
        vec_map::insert(&mut asset_decimal_places, 1, test_util::matic_dec_places());
        vec_map::insert(&mut asset_decimal_places, 2, test_util::usdt_dec_places());
        let add_liquidity: VecMap<u8, bool> = vec_map::empty();
        vec_map::insert(&mut add_liquidity, 0, true);
        vec_map::insert(&mut add_liquidity, 1, true);
        vec_map::insert(&mut add_liquidity, 2, true);
        let initial_asset_liquidity: VecMap<u8, u64> = vec_map::empty();
        vec_map::insert(&mut initial_asset_liquidity, 0, 200 * (test_util::eth_factor() as u64));
        vec_map::insert(&mut initial_asset_liquidity, 1, 200_000 * (test_util::matic_factor() as u64));
        vec_map::insert(&mut initial_asset_liquidity, 2, 400_000 * (test_util::usdt_factor() as u64));

        let (ramm_id, eth_ag_id, matic_ag_id, usdt_ag_id, scenario_val) =
            test_util::create_populate_initialize_ramm<ETH, MATIC, USDT>(
                asset_prices,
                asset_price_scales,
                asset_minimum_trade_amounts,
                asset_decimal_places,
                add_liquidity,
                initial_asset_liquidity,
                ADMIN
        );
        let scenario = &mut scenario_val;

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let matic_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, matic_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

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

            // First trade: ETH in, USDT out

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

        test_scenario::end(scenario_val);
    }
}