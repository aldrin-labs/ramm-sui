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
    fun sui_usdc_usdt_liquidity_test() {
        let (ramm_id, sui_ag_id, usdt_ag_id, usdc_ag_id, mut scenario_val) = test_util::create_ramm_test_scenario_sui_usdc_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ADMIN);

        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);

            let lp_sui = test_scenario::take_from_address<Coin<LP<SUI>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_sui), (100 * test_util::sui_factor() as u64));

            let lp_usdc = test_scenario::take_from_address<Coin<LP<USDC>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_usdc), (145 * test_util::usdc_factor() as u64) * 1_000);

            let lp_usdt = test_scenario::take_from_address<Coin<LP<USDT>>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&lp_usdt), (148 * test_util::usdt_factor() as u64) * 1_000);

            test_scenario::return_to_address<Coin<LP<SUI>>>(ADMIN, lp_sui);
            test_scenario::return_to_address<Coin<LP<USDC>>>(ADMIN, lp_usdc);
            test_scenario::return_to_address<Coin<LP<USDT>>>(ADMIN, lp_usdt);
            test_scenario::return_shared<RAMM>(ramm);
        };

        test_scenario::next_tx(scenario, ADMIN);

        test_scenario::end(scenario_val);
    }
}