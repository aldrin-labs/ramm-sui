#[test_only]
module ramm_sui::liquidity_provision_fees_tests {
    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::test_scenario;
    use sui::test_utils;

    use std::debug;

    use ramm_sui::interface2;
    use ramm_sui::ramm::{Self, LP, RAMM, RAMMAdminCap};
    use ramm_sui::test_util::{Self, ETH, USDT};

    use switchboard::aggregator::Aggregator;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;

    const ETraderShouldHaveAsset: u64 = 0;

    /// Returns true iff `\exists n: u64: x = 2^n`, false otherwise.
    fun is_power_of_two(x: u64): bool {
        if ((x & (x - 1)) == 0) {
            return true
        } else {
            return false
        }
    }

    /// # Premise
    ///
    /// This very simple test is designed to falsify the hypothesis that
    /// the RAMM's liquidity providers cannot earn fees from their provision services.
    ///
    /// # Overview
    ///
    /// The scenario is as follows:
    /// * consider a 2-asset ETH/USDT RAMM
    /// * the RAMM's admin is also its only LP, and deposits 500 ETH, and 900,000 USDT
    /// * a trader, `ALICE`, performs a number of consecutive pairs of trades:
    ///   - the first in the pair is of `10 ETH` for however much `USDT` that can buy,
    ///   - and then the second is of `20,000 USDT` for however much `ETH` that can buy.
    /// * after all the trades are completed, the admin withdraws all of their LP tokens
    /// * finally, the admin collects all of the fees that have been generated by the trades
    ///
    /// # Results
    ///
    /// Taking into account the extreme simplicity of this scenario, it does *not* allow for
    /// general inferences to be made from an LP's profit performance in all possible cases.
    ///
    /// However, it *falsifies* the hypothesis that an LP cannot earn fees from providing liquidity
    /// to a RAMM.
    ///
    /// More concretely:
    /// 1. with a(n unrealistically) fixed ETH price of 2000 USDT, and
    /// 2. with 512 trades, and
    /// 3. with `10` inbound ETH and `20000` inbound USDT per pair of trades,
    /// the following
    /// arises:
    /// * the LP's profits scale linearly with the number of trades: double the number of trades,
    ///   and the LP's profits double as well
    /// * the LP makes a profit with even a single trade (although small, at roughly
    ///   0.0038 ETH/9.5 USDT)
    /// * after about ~250 trades, the LP's profits break even with respect to liquidity
    ///   withdrawals' 0.4% fee
    ///
    /// # Conclusion
    ///
    /// As shown by this concrete example, LPs *can* earn fees from providing liquidity to a RAMM.
    ///
    /// A heuristic inference, again noting the unrealistic premise that prices stay
    /// fixed:
    /// 1. A trading volume of (roughly) a quintuple of the LP's position in the pool will
    ///    translate to a profit of (roughly) 0.4%
    fun liquidity_provision_fees_test(
        admin_address: address,
        max_iterations: u64
    ) {
        let (ramm_id, eth_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_eth_usdt(admin_address);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ALICE);

        // First part of the test: `ALICE` performs a set number of trades in the same tx,
        // printing the RAMM's balances after each trade, if the trade's ordinal is a power of two

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let eth_amnt = (10 * test_util::eth_factor() as u64);
            let usdt_amnt = (20_000 * test_util::usdt_factor() as u64);
            let mut i: u64 = 1;
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

                if (is_power_of_two(i)) {
                    // just in case!
                    test_utils::assert_eq(ramm::get_typed_balance<ETH>(&ramm), ramm::get_balance<ETH>(&ramm));
                    test_utils::assert_eq(ramm::get_typed_balance<USDT>(&ramm), ramm::get_balance<USDT>(&ramm));

                    debug::print(&ramm::get_typed_balance<ETH>(&ramm));
                    debug::print(&ramm::get_typed_balance<USDT>(&ramm));
                };

                i = i + 1;
            };

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(eth_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        // Second part of the trade: the admin, and only LP to the pool, withdraws all of their
        // LP tokens

        test_scenario::next_tx(scenario, admin_address);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let eth_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, eth_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            test_utils::print(b"quick sanity check");
            debug::print(&ramm::get_typed_balance<ETH>(&ramm));
            debug::print(&ramm::get_typed_balance<USDT>(&ramm));

            let lp_eth = test_scenario::take_from_address<Coin<LP<ETH>>>(scenario, admin_address);
            test_utils::assert_eq(coin::value(&lp_eth), (500 * test_util::eth_factor() as u64));
            let lp_usdt = test_scenario::take_from_address<Coin<LP<USDT>>>(scenario, admin_address);
            test_utils::assert_eq(coin::value(&lp_usdt), (900_000 * test_util::usdt_factor() as u64));

            test_utils::print(b"LPETH/LPUSDT Liquidity withdrawals");

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
        };

        test_scenario::next_tx(scenario, admin_address);
        {
            let withdrawn_eth = test_scenario::take_from_address<Coin<ETH>>(scenario, admin_address);
            let withdrawn_usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, admin_address);

            let withdrawn_eth_value: u64 = coin::value(&withdrawn_eth);
            let withdrawn_usdt_value: u64 = coin::value(&withdrawn_usdt);

            debug::print(&withdrawn_eth_value);
            debug::print(&withdrawn_usdt_value);

            test_scenario::return_to_address(admin_address, withdrawn_eth);
            test_scenario::return_to_address(admin_address, withdrawn_usdt);
        };

        // Next step: the admin collects the resulting fees, for display purposes only.

        test_scenario::next_tx(scenario, admin_address);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
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
            let eth_fees = test_scenario::take_from_address<Coin<ETH>>(scenario, admin_address);
            let usdt_fees = test_scenario::take_from_address<Coin<USDT>>(scenario, admin_address);

            let eth_fees_value: u64 = coin::value(&eth_fees);
            let usdt_fees_value: u64 = coin::value(&usdt_fees);

            test_utils::print(b"value of fees (ETH, USDT):");
            debug::print(&eth_fees_value);
            debug::print(&usdt_fees_value);

            test_scenario::return_to_address(admin_address, eth_fees);
            test_scenario::return_to_address(admin_address, usdt_fees);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Note: this must be run with the `--gas-limit` flag set to a very high value, as running it
    /// with hundreds operations in a tx will exhaust the default gas for tests, and lead to a
    /// timeout:
    ///
    /// `sui move test --gas-limit 10000000000`
    fun liquidity_provision_fees_test_512() {
        liquidity_provision_fees_test(ADMIN, 512);
    }
}