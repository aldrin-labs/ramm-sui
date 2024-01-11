#[test_only]
module ramm_sui::liquidity_provision_fees_tests {
    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::test_scenario;
    use sui::test_utils;

    use std::debug;
    use std::vector;

    use ramm_sui::interface2;
    use ramm_sui::ramm::{LP, RAMM, RAMMAdminCap};
    use ramm_sui::test_util::{Self, ETH, USDT};

    use switchboard::aggregator::Aggregator;

    const ALICE: address = @0xACE;

    const ETraderShouldHaveAsset: u64 = 0;

    fun is_power_of_two(x: u64): bool {
        if ((x & (x - 1)) == 0) {
            return true
        } else {
            return false
        }
    }

    /// Given a 2-asset ETH/USDT RAMM, with an initial ETH price of 2000 USDT,
    /// perform the trades in the whitepaper's second practical example.
    /// 1. First, a purchase of 20 ETH
    /// 2. Next, a redemption of every LPETH token by a provider
    /// 3. Finally, a redemption of every LPUSDT token by a provider
    fun liquidity_provision_fees_test(
        admin_address: address,
        max_iterations: u64
    ) {
        let (ramm_id, eth_ag_id, usdt_ag_id, scenario_val) = test_util::create_ramm_test_scenario_eth_usdt(admin_address);
        let scenario = &mut scenario_val;

        // First part of the test: a trader, Alice, wishes to buy 20 ETH
        // from the ETH/USDT RAMM, with the current price of 2000 USDT per ETH.

        test_scenario::next_tx(scenario, ALICE);

        //

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let eth_amnt = (1 * test_util::eth_factor() as u64);
            let usdt_amnt = (2000 * test_util::usdt_factor() as u64);
            let i: u64 = 1;
            while (i <= max_iterations) {
                let amount_in = coin::mint_for_testing<ETH>(eth_amnt, test_scenario::ctx(scenario));
                interface2::trade_amount_in_2<ETH, USDT>(
                    &mut ramm,
                    &clock,
                    amount_in,
                    1,
                    &eth_aggr,
                    &usdt_aggr,
                    test_scenario::ctx(scenario)
                );

                let amount_in = coin::mint_for_testing<USDT>(usdt_amnt, test_scenario::ctx(scenario));
                interface2::trade_amount_in_2<USDT, ETH>(
                    &mut ramm,
                    &clock,
                    amount_in,
                    1,
                    &usdt_aggr,
                    &eth_aggr,
                    test_scenario::ctx(scenario)
                );

                i = i + 1;
            };

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        //

        test_scenario::next_tx(scenario, admin_address);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let lp_eth = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, admin_address);
            test_utils::assert_eq(coin::value(&lp_eth), (500 * test_util::eth_factor() as u64));
            let lp_usdt = test_scenario::take_from_address<Coin<LP<USDT>>>(scenario, admin_address);
            test_utils::assert_eq(coin::value(&lp_usdt), (900_000 * test_util::usdt_factor() as u64));

            interface2::liquidity_withdrawal_2<ETH, USDT, ETH>(
                &mut ramm,
                &clock,
                lp_eth,
                &eth_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            interface2::liquidity_withdrawal_2<ETH, USDT, USDT>(
                &mut ramm,
                &clock,
                lp_usdt,
                &eth_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);

            // Remember to remove trading fees from total fee count to avoid counting them twice
        };

        test_scenario::next_tx(scenario, admin_address);
        let (withdrawn_eth, withdrawn_usdt) = {
            let eth = test_scenario::take_from_address<Coin<ETH>>(scenario, admin_address);
            let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, admin_address);

            let eth_value: u64 = coin::value(&eth);
            let usdt_value: u64 = coin::value(&usdt);

            test_scenario::return_to_address(admin_address, eth);
            test_scenario::return_to_address(admin_address, usdt);

            (eth_value, usdt_value)
        };

        // Next step: collect the RAMM fees to the collection address (in this case, the admin's address)

        test_scenario::next_tx(scenario, admin_address);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let admin_cap: RAMMAdminCap = test_scenario::take_from_address<RAMMAdminCap>(scenario, admin_address);

            interface2::collect_fees_2<ETH, USDT>(
                &mut ramm,
                &admin_cap,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address<RAMMAdminCap>(admin_address, admin_cap);
        };

        test_scenario::next_tx(scenario, admin_address);

        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(scenario, admin_address);
            let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, admin_address);

            debug::print(&(withdrawn_eth + coin::value(&eth)));
            debug::print(&(withdrawn_usdt + coin::value(&usdt)));

            test_scenario::return_to_address(admin_address, eth);
            test_scenario::return_to_address(admin_address, usdt);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun liquidity_provision_fees_test_runner() {
        let addresses: vector<address> = vector[
            @0x1,
            @0x2,
            @0x3,
            @0x4,
            @0x5,
            @0x6,
            @0x7,
            @0x8,
            @0x9,
            @0xA
        ];

        let i = 0;
        while (i < 10) {
            liquidity_provision_fees_test(
                *vector::borrow(&addresses, i),
                sui::math::pow(2, (i as u8))
            );
        };
    }
}