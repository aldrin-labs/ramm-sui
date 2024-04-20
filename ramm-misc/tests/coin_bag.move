//! Testnet notes

#[test_only]
module ramm_misc::coin_bag {
    use sui::bag;
    use sui::coin::{Self, Coin};
    use sui::test_scenario;
    use sui::sui::SUI;

    use ramm_misc::test_coins::BTC;
    use ramm_misc::test_coins::ETH;
    use ramm_misc::test_coins::SOL;
    use ramm_misc::test_coins::USDC;

    use std::debug;
    use std::type_name;

    const ADDRESS: address = @0xACE;

    const EInvalidAmount: u64 = 0;

    #[test]
    fun test_bag() {
        let mut new_scenario = test_scenario::begin(ADDRESS);
        let scenario = &mut new_scenario;
        let ctx = test_scenario::ctx(scenario);

        let amount: u64 = 1000;
        let btc = coin::mint_for_testing<BTC>(amount, ctx);
        let sol = coin::mint_for_testing<SOL>(amount * 2, ctx);
        let usdc = coin::mint_for_testing<USDC>(amount * 3, ctx);
        let eth = coin::mint_for_testing<ETH>(amount * 4, ctx);

        let mut bag = bag::new(ctx);
        test_scenario::next_tx(scenario, ADDRESS);

        bag::add<u64, Coin<BTC>>(&mut bag, 0, btc);
        bag::add<u64, Coin<SOL>>(&mut bag, 1, sol);
        bag::add<u64, Coin<ETH>>(&mut bag, 2, eth);
        bag::add<u64, Coin<USDC>>(&mut bag, 3, usdc);

        let mut amnt: u64 = 0;

        let btc = bag::remove<u64, Coin<BTC>>(&mut bag, 0);
        amnt = amnt + coin::burn_for_testing(btc);

        let sol = bag::remove<u64, Coin<SOL>>(&mut bag, 1);
        amnt = amnt + coin::burn_for_testing(sol);

        let eth = bag::remove<u64, Coin<ETH>>(&mut bag, 2);
        amnt = amnt + coin::burn_for_testing(eth);

        let usdc = bag::remove<u64, Coin<USDC>>(&mut bag, 3);
        amnt = amnt + coin::burn_for_testing(usdc);

        let _type_name = type_name::get<SUI>();

        debug::print(&type_name::into_string(_type_name));

        assert!(amnt == 10000, EInvalidAmount);
        bag::destroy_empty(bag);
        test_scenario::end(new_scenario);
    }
}
