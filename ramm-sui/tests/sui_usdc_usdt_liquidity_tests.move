#[test_only]
module ramm_sui::sui_usdc_usdt_liquidity_tests {
    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, TransactionEffects};
    use sui::test_utils;

    use ramm_sui::interface3;
    use ramm_sui::math;
    use ramm_sui::ramm::{Self, LP,  RAMM, RAMMAdminCap};
    use ramm_sui::test_util::{Self, USDC, USDT};

    use switchboard::aggregator::Aggregator;

    const ADMIN: address = @0xFACE;
    const ALICE: address = @0xACE;
    const BOB: address = @0xBACE;

    #[test]
    /// Test designed to correct issue with LP withdrawals being wildly incorrect in their
    /// precision.
    ///
    /// Recall that this `SUI/USDC/USDT` pool begins with
    /// * 100 SUI
    /// * 145 USDC
    /// * 148 USDT
    ///
    /// The test runs as follows:
    /// 1. The pool is created, with the `ADMIN` holding all of the initial liquidity
    /// 2. `ALICE` moves in to deposit 650 USDC
    /// 3. Alice deposits 500 SUI
    /// 4. The admin then withdraws from all of their positions
    ///
    /// The withdrawn amounts are then tallied, and their precision must be correct - the 145
    /// USDC withdrawal must correspond to the 145 USDC deposited, and not 0.14 USDC, or 1000
    /// times smaller than expected.
    fun sui_usdc_usdt_liquidity_test() {
        let (ramm_id, sui_ag_id, usdc_ag_id, usdt_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_sui_usdc_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ALICE);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let sui_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sui_ag_id);
            let usdc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdc_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let sui = coin::mint_for_testing<SUI>(
                500 * (test_util::sui_factor() as u64),
                test_scenario::ctx(scenario)
            );

            interface3::liquidity_deposit_3<SUI, USDC, USDT>(
                &mut ramm,
                &clock,
                sui,
                &sui_aggr,
                &usdc_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            test_utils::assert_eq(ramm::get_lptokens_issued<USDC>(&ramm), 145 * test_util::usdc_factor() * 1_000);
            test_utils::assert_eq(ramm::get_lptokens_issued<SUI>(&ramm), 600 * test_util::sui_factor());
            test_utils::assert_eq(ramm::get_lptokens_issued<USDT>(&ramm), 148 * test_util::usdt_factor() * 1_000);

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(sui_aggr);
            test_scenario::return_shared<Aggregator>(usdc_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        test_scenario::next_tx(scenario, ADMIN);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let sui_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, sui_ag_id);
            let usdc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdc_ag_id);
            let usdt_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, usdt_ag_id);

            let lp_sui = test_scenario::take_from_address<Coin<LP<SUI>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_sui), (100 * test_util::sui_factor() as u64));

            let lp_usdc = test_scenario::take_from_address<Coin<LP<USDC>>>(scenario, ADMIN);
            // Observer how the lambda factor applied to USDT and USDC is incorrect - the whitepaper
            // advises a lambda of 1 as a reasonable default, and using the `FACTOR_LP` constant
            // when a pool's assets have different decimal places leads to this.
            test_utils::assert_eq(coin::value(&lp_usdc), (145 * test_util::usdc_factor() as u64) * 1_000);

            let lp_usdt = test_scenario::take_from_address<Coin<LP<USDT>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_usdt), (148 * test_util::usdt_factor() as u64) * 1_000);

            interface3::liquidity_withdrawal_3<SUI, USDC, USDT, SUI>(
                &mut ramm,
                &clock,
                lp_sui,
                &sui_aggr,
                &usdc_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            interface3::liquidity_withdrawal_3<SUI, USDC, USDT, USDC>(
                &mut ramm,
                &clock,
                lp_usdc,
                &sui_aggr,
                &usdc_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            interface3::liquidity_withdrawal_3<SUI, USDC, USDT, USDT>(
                &mut ramm,
                &clock,
                lp_usdt,
                &sui_aggr,
                &usdc_aggr,
                &usdt_aggr,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_shared<Clock>(clock);
            test_scenario::return_shared<Aggregator>(sui_aggr);
            test_scenario::return_shared<Aggregator>(usdc_aggr);
            test_scenario::return_shared<Aggregator>(usdt_aggr);
        };

        test_scenario::next_tx(scenario, ADMIN);

        {
            let sui = test_scenario::take_from_address<Coin<SUI>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&sui), (996 * test_util::sui_factor() as u64) / 10);

            let usdc = test_scenario::take_from_address<Coin<USDC>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&usdc), (14442 * test_util::usdc_factor() as u64) / 100);

            let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&usdt), (147408 * test_util::usdt_factor() as u64) / 1000);

            test_scenario::return_to_address<Coin<SUI>>(ADMIN, sui);
            test_scenario::return_to_address<Coin<USDC>>(ADMIN, usdc);
            test_scenario::return_to_address<Coin<USDT>>(ADMIN, usdt);
        };

        test_scenario::end(scenario_val);
    }
}