# ramm-sui

This repository hosts an implementation of a RAMM in Sui Move.

At present, there are 2 Sui Move packages:
* `ramm-sui` contains an implementation for the RAMM, which is ongoing work.
* `ramm-misc` has a faucet with tokens useful for testnet development/testing
  - it also has a simple demo that showcases price information querying from [Switchboard](https://beta.app.switchboard.xyz/sui/testnet) aggregators

## Table of contents
1. [RAMM in Sui Move](#ramm-sui-ramm-in-sui-move)
2. [Testing a Switchboard price feed](#testing-a-price-feed)
3. [Creating tokens for tests](#creating-test-coins)
4. [Regarding AMMs with variable numbers of assets in Sui Move](#on-supporting-variable-sized-pools-with-a-single-implementation)

## `ramm-sui`: RAMM in Sui Move

The principal data structure in the `ramm-sui` package is the `RAMM` object.
In order for traders to
* deposit/withdraw liquidity
* buy/sell assets
they must interact with a `RAMM` object through the contract APIs in the `interface*` modules.

### Structure of `ramm-sui` package and modules

The public API is split in different modules:
* Functions that can be called on RAMMs of any size exist in `ramm_sui::ramm`
* for 2-asset RAMMs, the module `ramm_sui::interface2` is to be used
* for 3-asset RAMMs, use `ramm_sui::interface3`
  - any future additions of higher-order RAMMs will follow this pattern: 4-asset RAMMs => `ramm_sui::interface4`, etc.
* mathematical operators related to the RAMM protocol in `ramm_sui::math`

### RAMM Internal data

The structure stores information required for its management and operation, including datum about each of its assets:
* the `AdminCap` required to perform gated operations e.g. fee collection; see [here](#capability-pattern-as-security-measure) for more information
* minimum trade amounts per each asset
* the balance of each asset (in a scalar and typed version, see below)
* a data structure specific to Sui (`balance::Supply`) that regulates LP token issuance for each asset
* protocol fees collected for each asset

### Capability pattern as a security measure

Some RAMM operations don't require administrative privileges - trading, liquidity deposits/withdrawals - while
others must. Examples:
* add assets to an unitialized RAMM
* initialize a RAMM, thereby freezing the number and type of its assets
* disable/enable deposits for an asset
* transfer collected protocol fees to a designated address
* change the designated fee collection address
* change the minimum trading amount for an asset

In order to do this, Sui Move allows the use of the [capability pattern](https://examples.sui.io/patterns/capability.html).

Upon creation, each RAMM will have 2 associated `Cap`ability objects that will be owned by whoever created the RAMM:

1. A perennial `RAMMAdminCap`, required in **every** gated operation. Its `ID` will be stored
   in the RAMM, and checked so that only the correct object unlocks the operation
1. An ephemeral `RAMMNewAssetCap`, whose `ID` is also stored in the RAMM, in a  `new_asset_cap_id: Option<ID>` field.
   The reason why it's ephemeral:
    - This `Cap` is used to add assets to the RAMM, which can only be done before initialized
    - To initialize a RAMM, its `RAMMNewAssetCap` must be passed **by value** to be destroyed, and the
      `new_asset_cap_id` field becomes `Option::None` to mark its initialization
    - After initialization, no more assets can then be added, which is enforced by the fact that the `RAMMNewAssetCap`
      no longer exists

### Limitations of RAMM design

There are some limitations to the chosen RAMM design.

#### Duplicate fields in the RAMM

Because of limitations with Sui Move's type system, in order to both
1. create RAMMs with arbitrary asset counts, and
2. abstract over asset types

and still have a degree of code reuse, it is necessary to store certain information twice:
1. once in an untyped, scalar format e.g. `u256`, and
2. again in a typed format, e.g. `Balance<Asset>`.

This information is:
* per-asset balance information
* per-asset LP token `Supply` structures, which regulate LP token issuance

Doing this decouples the internal RAMM functions, which can do the calculations required for trading and liquidity operations
using scalars only - see `ramm_sui::ramm::{trade_i, trade_o}` - from the client-facing public API, that must have access
to the asset types themselves, and their count - see `ramm_sui::interface2::trade_amount_in_2` and 
`ramm_sui::interface3::trade_amount_in_3`.

In other words, the only code that must be repeated for every class of RAMMs is the public, typed API,
every instance of which will wrap the same typeless, scalar internal functions.

#### Ownership of `RAMM` object structure

In order for orders to be sent to the RAMM and affect its internal state, it must be shared, and
thus cannot have an owner.

This makes it subject to consensus in the Sui network, preventing traders' orders from benefitting from
the fast-tracking of transactions that occurs in contexts of in sole object ownership and object immutability.

#### Storing Switchboard Aggregators

In order to obtain current information on asset pricing, the RAMM requires the use of oracles.
In Sui, at present, there are only two alternatives: Pyth Network, and Switchboard.
Switchboard was chosen over Pyth due to its simplicity - Pyth [requires](https://docs.pyth.network/pythnet-price-feeds/sui)
attested off-chain data to be provided in each price request, while Switchboard does not.

However, unlike in the EVM where the RAMM could store each oracle's address to then interact with,
Sui's object model prevents interaction via an `address` alone, and as such:

> Switchboard's `Aggregator`s cannot be stored in the RAMM object.

This is because if `RAMM` `has key`, then
* all its fields must have `store`
* in particular, `vector<Aggregator>` must have store
  - so `Aggregator` must have `store`
* Which it does not, so RAMM cannot have `key`
* Meaning it cannot be used be turned into a shared object with 
  `sui::transfer::share_object`
* which it *must* be, to be readable and writable by all

## Testing a Switchboard price feed

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

In order to create testing coins to be used to interact with the RAMM,
`ramm-misc/sources/test_coins` offers tokens for which there exists a corresponding Switchboard
`Aggregator` with pricing information on the Sui testnet.

### Regarding suibase

[Suibase](https://suibase.io/intro.html) is a tool that assists in the development, testing
and deployment of Sui smart contracts.

It provides a suite of tools and SDKs for Rust/Python that let developers easily target
different Sui networks (e.g. devnet, testnet, main) and configure the development environment,
e.g. by allowing the specification of an exact version of the `sui` binaries, from a forked
repository.

For the purposes of this project, it will be needed to build/test/deploy the RAMM on a given
network, in this case the testnet.
After installing `suibase`, optionally [setting](https://suibase.io/how-to/configure-suibase-yaml.html#change-default-repo-and-branch)
the `sui` version to be used, and running `testnet start`, `tsui` will be ready for use in the
user's `$PATH`.

### Requesting tokens from the faucet

The `ramm_sui` package has been published to the Sui testnet; its package ID, as well as
the object ID of the `ramm_misc::faucet::Faucet` object, should be declared in a UNIX
terminal thusly in order to follow the rest of the instructions:

```bash
export FAUCET_PACKAGE_ID=0x76a5ecf30b2cf49a342a9bd74a479702a1b321b0d45f06920618dbe7c2da52b1
export FAUCET_ID=0xaf774e31764afcf13761111b662892d12d6998032691160e1b3f7d7f0ab039bd
```

`SUI` for gas fees can be requested in the Sui [Discord](https://discord.com/invite/sui) server.
After this is done, a specific token, i.e. `ramm_misc::test_coins::BTC`, can be requested with

```bash
export COIN=BTC

tsui client call --package "$FAUCET_PACKAGE_ID" \
--module test_coin_faucet \
--function mint_test_coins \
--args $FAUCET_ID 100000000000 \
--type-args "$FAUCET_PACKAGE_ID"::test_coins::"$COIN" \
--gas-budget 100000000
```

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