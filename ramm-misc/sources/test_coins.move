module ramm_misc::test_coins {
    use std::type_name;

    use sui::bag::{Self, Bag};
    use sui::balance;
    use sui::tx_context::TxContext;

    /* friend ramm_misc::test_coin_faucet; */

    // These coins below are the only ones for which a Switchboard Testnet feed exists
    // as of 2024-01-22.
    public struct USDT has drop {}
    public struct USDC has drop {}
    public struct ETH has drop {}
    public struct BTC has drop {}
    public struct SOL has drop {}
    public struct DOT has drop {}
    public struct ADA has drop {}
    //struct SUI has drop {}

    /// For every currently available `Aggregator` in the Sui testnet, create a `Supply` for it,
    /// control of which will belong to this package's publisher. See `ramm_misc::faucet::init()`.
    public(package) fun create_test_coin_suplies(ctx: &mut TxContext): Bag {
        let mut coins = bag::new(ctx);

        bag::add(&mut coins, (type_name::get<USDT>()), balance::create_supply(USDT {}));
        bag::add(&mut coins, (type_name::get<USDC>()), balance::create_supply(USDC {}));
        bag::add(&mut coins, (type_name::get<ETH>()), balance::create_supply(ETH {}));
        bag::add(&mut coins, (type_name::get<BTC>()), balance::create_supply(BTC {}));
        bag::add(&mut coins, (type_name::get<SOL>()), balance::create_supply(SOL {}));
        bag::add(&mut coins, (type_name::get<DOT>()), balance::create_supply(DOT {}));
        bag::add(&mut coins, (type_name::get<ADA>()), balance::create_supply(ADA {}));

        coins
    }
}