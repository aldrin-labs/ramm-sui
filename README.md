# ramm-sui

This repository hosts an implementation of a RAMM in Sui Move.

At present, there are 2 Sui Move packages:
* `ramm-sui` contains an implementation for the RAMM, which is ongoing work.
* `ramm-misc` has a simple demo that fetches pricing information from [Switchboard](https://beta.app.switchboard.xyz/sui/testnet) Sui oracles
  - it also has fictional tokens to be used later when testing the RAMM

## Table of contents
1. [RAMM in Sui Move](#ramm-sui-ramm-in-sui-move)
2. [Testing a Switchboard price feed](#testing-a-price-feed)
3. [Creating tokens for tests](#creating-test-coins)
4. [Regarding AMMs with variable numbers of assets in Sui Move](#on-supporting-variable-sized-pools-with-a-single-implementation)

## `ramm-sui`: RAMM in Sui Move

WIP

## Testing a price feed

A Sui testnet price information feed can be found in the link above,
and in `ramm-misc/sources/demo.move`, there exist constants with the aggregators'
addresses; some examples which can be used below with `$AGGREGATOR_ID`:

```Rust
const BTC_USD: address = @0x7c30e48db7dfd6a2301795be6cb99d00c87782e2547cf0c63869de244cfc7e47;
const ETH_USD: address = @0x68ed81c5dd07d12c629e5cdad291ca004a5cd3708d5659cb0b6bfe983e14778c;
const SOL_USD: address = @0x35c7c241fa2d9c12cd2e3bcfa7d77192a58fd94e9d6f482465d5e3c8d91b4b43;
const SUI_USD: address = @0x84d2b7e435d6e6a5b137bf6f78f34b2c5515ae61cd8591d5ff6cd121a21aa6b7;
```

```bash
cd ramm-misc
sui move build
sui client publish --gas-budget 20000000
# export the above package ID to $PACKAGE

# $AGGREGATOR_ID is an ID from https://beta.app.switchboard.xyz/sui/testnet
sui client call \
  --package $PACKAGE \
  --module switchboard_feed_parser \
  --function log_aggregator_info \
  --args $AGGREGATOR_ID \
  --gas-budget 10000000 \
# export the resulting object ID to AGGREGATOR_INFO

sui client object $AGGREGATOR_INFO
```

The relevant information will be in the `latest_result, latest_result_scaling_factor`
fields.

## Creating test coins

In order to create testing coins to be used in the RAMM (which is WIP),
`ramm-misc/sources/test_coins` has some modules for dummy tokens.

How to create them:
1. Publish this package
  ```bash
  sui client publish . --gas-budget 10000000
  ```
  The created objects whose ID will be necessary are:
  - the published package's ID, which can be `export`ed as `PACKAGE`
  - the `TreasuryCap`s for the created test currencies, which will need to be
    `export`ed as well, e.g. `export SOL_TREASURY_CAP=...`
2. Mint-and-transfer testing tokens:
  ```bash
  sui client call \
  --package 0x2 \
  --module coin \
  --function mint_and_transfer \
  --gas-budget 10000000 \
  --args $TOKEN_TREASURY_CAP 1000 $ADDRESS \
  --type-args $PACKAGE::token::TOKEN
  ```
  where `$ADDRESS` in a previously `export`ed valid Sui address.
  Other functions are available in the `0x2::coin` module

## On supporting variable-sized pools with a single implementation

As of its release, Sui Move will not allow a single implementation of a
RAMM for varying numbers of assets.

In other words, in order to have a RAMM with `3` assets, this will require
one implementation for that number of assets.
In order to support a RAMM with `4` assets, there will need to be another, and so forth.

To illustrate this, in `ramm-misc/tests/coin_bag.move` there's a short example using the
testing tokens previously defined.

### Scenario

In `ramm-misc/tests/coin_bag.move` module, there is a test which creates several different kinds
of testing tokens, and inserts them in a [`sui::bag::Bag`](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/bag.move#L32).

### Goal

The goal is to perform a trivial operation: add all of the testing tokens' amounts.
Doing this requires fully instantiating the types of all the involved tokens, which
by consequence prevents a fully generic RAMM from being implemented in Sui Move (as of its release).
The reasoning supporting this conclusion will be below.

Skip [further below](#summary) for the conclusion.

#### Comments

1. A `Bag` was chosen since it and `ObjectBag` are the only heterogeneous collections
  in the Sui Move standard library.
2. By holding tokens of different types in the `Bag`, the RAMM's state requirements are
  simulated in a simplified approximation.
  In the whitepaper's description of a RAMM, for a pool with `n` assets, its internal state includes:
  - the balances `B_1, B_2, ..., B_n`, which in Sui Move are necessarily typed objects:
    both the [`Coin<T>`](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/coin.move#L26) objects, and their internal structure [`Balance<T>`](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/balance.move#L32) require typed
    information to be used e.g. to receive a user's trade for/against a certain asset
  - the liquidity pool's tokens for each asset. Regardless of the way they are represented
    internally, since the RAMM protocol requires the ability to mint/burn LP tokens when
    users add/remove liquidity, this will, per Sui Move's restrictions, involve the use
    of a [`TreasuryCap<T>`](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/coin.move#L52), which is also a typed structure.

### Details

As mentioned above, in `ramm-misc/sources/coin_bag` is a module consisting of a simple test:
adding the amount of several tokens, all of different types.
This test is simple:
1. Tokens from `ramm-misc/sources/test_coins` are minted using `sui::coin::mint_for_testing`
  ```rust
  let amount: u64 = 1000;
  let btc = coin::mint_for_testing<BTC>(amount, ctx);
  let sol = coin::mint_for_testing<SOL>(amount * 2, ctx);
  ...
  ```
2. A bag is initialized:
  ```rust
  use sui::bag;
  let bag = bag::new(...);
  ```
2. Those tokens are inserted into the bag using `u64` keys:
  ```rust
  bag::add<u64, Coin<BTC>>(&mut bag, 0, btc);
  bag::add<u64, Coin<SOL>>(&mut bag, 1, sol);
  ...
  ```

Although the bag insertion function has signature
```public fun add<K: copy + drop + store, V: store>(bag: &mut Bag, k: K, v: V)```,
inserting values of different types into the collection is not the issue; in the case of
a hypothetical structure

```rust
struct RAMM {
  ...
  // Hypothetical map between `T` and `Coin<T>`
  balances: Bag,
  // Hypothetical map between `T` and `Coin<LPToken<T>>`
  lpt_balances: Bag,
  ...
}

public fun add_asset_to_pool<T>(&mut self: RAMM) {
  ...
  self.balances[T] = 0;
  self.lpt_balances = 0;
  ...
}
```

then the pool's internal state could be created incrementally, binding the above `K, V` to
a different asset, one asset at a time.

---

### Problem

The issue arises when accessing the values.

```rust
let btc = bag::remove<u64, Coin<BTC>>(&mut bag, 0);
amnt = amnt + coin::burn_for_testing(btc);

let sol = bag::remove<u64, Coin<SOL>>(&mut bag, 1);
amnt = amnt + coin::burn_for_testing(sol);

let eth = bag::remove<u64, Coin<ETH>>(&mut bag, 2);
amnt = amnt + coin::burn_for_testing(eth);

let usdc = bag::remove<u64, Coin<USDC>>(&mut bag, 3);
amnt = amnt + coin::burn_for_testing(usdc);
```

All of the functions that access a bag's values take a `V` type parameter,
in this case, `remove`:

```rust
 public fun remove<K: copy + drop + store, V: store>(bag: &mut Bag, k: K): V
```

The `bag` in question has 4 types of tokens, so in order to access all of its elements,
`remove` has to be instantiated with **exactly** 4 unique types.

In other words - it is **not** possible to sum all of the token amounts in the `bag`
*without* enumerating all of the types in it - which is a variable number.
It can be seen that for a `Bag` - or any other collection - with `N` different
types in it, where `N` is known only at runtime, the number of unique instantiations would be
`N` too.

Herein is the problem:
* functions in Sui Move cannot be variadic in their type parameters
  - i.e. `fun f<T, U>` is different from `fun f<T, U, V>`, and the first cannot be
    called with less or more than 2 parameters, as Sui Move requires all generic
    types and struct to be **fully** instantiated at runtime
* having a pool with a variable number of assets would require functions with [variable](https://en.wikipedia.org/wiki/Variadic_template) number of type parameters, which is not possible in Sui Move

### Summary

1. In Sui Move, it is not possible to build structures with a dynamic number of type parameters
2. Each class of RAMM protocols - 2 assets, 3, 4, and so on - will require its own code,
  - some of this code will need to be replicated for each pool size