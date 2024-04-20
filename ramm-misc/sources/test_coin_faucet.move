module ramm_misc::test_coin_faucet {
    use std::type_name::{Self, TypeName};

    use sui::bag::{Self, Bag};
    use sui::balance::{Self, Supply};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    //use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use ramm_misc::test_coins;

    const ENonexistentCoinType: u64 = 0;

    public struct Faucet has key {
        id: UID,
        coins: Bag,
        creator: address,
    }

    /// Upon publication of this package, create a `Faucet` object with hardcoded coin types,
    /// and make it a shared object.
    ///
    /// The coin phantom types are: `USDT, USDC, BTC, ETH, SOL, DOT, ADA`.
    fun init(
        ctx: &mut TxContext
    ) {
        transfer::share_object(
            Faucet {
                id: object::new(ctx),
                coins: test_coins::create_test_coin_suplies(ctx),
                creator: tx_context::sender(ctx),
            }
        )
    }

    /// Given
    /// * a `Faucet`,
    /// * a coin type `T` and an
    /// * amount of coins of that type to be minted,
    ///
    /// do so, and return the created `Coin` object for use in a PTB.
    ///
    /// # Aborts
    ///
    /// * If the provided coin type is not part of the `Faucet`'s `Bag`
    /// * if the amount provided would cause more than `u64::MAX` of type `Coin<T>` to be in
    ///   circulation
    public fun mint_test_coins_ptb<T>(
        faucet: &mut Faucet,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        let coin_name = type_name::get<T>();
        assert!(
            bag::contains_with_type<TypeName, Supply<T>>(&faucet.coins, coin_name),
            ENonexistentCoinType
        );

        let mut_supply = bag::borrow_mut<TypeName, Supply<T>>(
            &mut faucet.coins,
            coin_name
        );
        let minted_balance = balance::increase_supply(mut_supply, amount);

        let coin = coin::from_balance(minted_balance, ctx);
        
        coin
    }

    /// Given
    /// * a `Faucet`,
    /// * a coin type `T` and an
    /// * amount of coins of that type to be minted,
    ///
    /// do so and transfer ownership of the created `Coin<T>` object to the transaction's sender.
    ///
    /// # Aborts
    ///
    /// * If the provided coin type is not part of the `Faucet`'s `Bag`
    /// * if the amount provided would cause more than `u64::MAX` of type `Coin<T>` to be in
    ///   circulation
    public fun mint_test_coins<T>(
        faucet: &mut Faucet,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let coin: Coin<T> = mint_test_coins_ptb(faucet, amount, ctx);

        transfer::public_transfer(
            coin,
            tx_context::sender(ctx)
        );
    }
}
