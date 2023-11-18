# ramm-sui

This repository hosts an implementation of a RAMM in Sui Move.

At present, there are 2 Sui Move packages:
* `ramm-sui` contains an implementation for the RAMM, which is ongoing work.
* `ramm-misc` has a faucet with tokens useful for testnet development/testing
  - it also has a simple demo that showcases price information querying from [Switchboard](https://app.switchboard.xyz/sui/testnet) aggregators

## Table of contents
1. [RAMM in Sui Move](#ramm-sui-ramm-in-sui-move)
2. [Deploying and testing the RAMM on the testnet](#interacting-with-the-ramm-on-the-testnet)
   - 2.1. [Addresses of currently published packages and instantiated objects](#addresses-of-currently-published-packages-and-instantiated-objects)
   - 2.2. [Regarding `suibase`](#regarding-suibase)
   - 2.3. [Requesting tokens from the faucet](#requesting-tokens-from-the-faucet)
   - 2.4. [RAMM creation/funding](#manually-creating-and-funding-a-ramm-on-the-testnet)
3. [Testing a Switchboard price feed](#testing-a-price-feed)
4. [Regarding AMMs with variable numbers of assets in Sui Move](#on-supporting-variable-sized-pools-with-a-single-implementation)

## `ramm-sui`: RAMM in Sui Move

The principal data structure in the `ramm-sui` package is the `RAMM` object.
In order for traders to
* deposit/withdraw liquidity
* buy/sell assets
they must interact with a `RAMM` object through the contract APIs in the `interface*` modules.

### Structure of `ramm-sui` package and modules

#### Library

The public API, in `ramm_sui/sources`, is split in different modules:
* Functions that can be called on RAMMs of any size exist in `ramm_sui::ramm`
* for 2-asset RAMMs, the module `ramm_sui::interface2` is to be used
* for 3-asset RAMMs, use `ramm_sui::interface3`
  - any future additions of higher-order RAMMs will follow this pattern: 4-asset RAMMs => `ramm_sui::interface4`, etc.
* mathematical operators related to the RAMM protocol in `ramm_sui::math`

#### Tests

The `ramm_sui/tests/` directory has an extensive suite of tests for the RAMM's functionality.
Among them:
* Utilities used to create non-trivial test scenarios, and avoid boilerplate when setting up test
  environments in `test_util.move`
* Tests to the basic mathematical operators required to implement the RAMM, in `math_tests.move`
* Basic unit-tests for RAMM creation and initialization, in `ramm_tests.move`
* Safety tests for each of the sized RAMM's interfaces: `interface2_safety_tests.move` for 2-asset
  RAMMs, and so on; these safety tests include:
    * checking that priviledged RAMM operations performed with an incorrect `Cap` object fail
    * providing an incorrect `Aggregator` to trading functions will promptly fail
* End-to-end tests in `interface{n}_tests.move` that use the functionality present in
  `sui::test_scenario` to flow from RAMM and `Aggregator` creation, all the way to liquidity
  deposits, withdrawals and trading with the RAMM
* Tests to the RAMM's volatility fee in `volatility{n}_tests.move`

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

This is because the RAMM must be a (shared) object; whereby it must have the `key` ability.
If `RAMM has key`, then
* all its fields must have `store`
* in particular, `vector<Aggregator>` must have store
  - so `Aggregator` must have `store`
* Which it does not, so RAMM cannot have `key`
* Meaning it cannot be used be turned into a shared object with 
  `sui::transfer::share_object`
* which it *must* be, to be readable and writable by all

## Interacting with the RAMM on the testnet

### Addresses of currently published packages and instantiated objects

The Bash variables below should be declared in a terminal/script for ease of use when running
the example commands.

#### Package IDs

The latest package IDs of

* the `ramm_sui` package, which is the library to create/interact with RAMM objects, as well as the
* `ramm_misc` package, used to create test tokens on the testnet,

are the following:

```bash
export FAUCET_PACKAGE_ID=0x76a5ecf30b2cf49a342a9bd74a479702a1b321b0d45f06920618dbe7c2da52b1 \
export RAMM_SUI_PACKAGE_ID=0x0adad52b9aa0a00460e47c3d5884dd4610bafdd772d62321558005387abe1174
```

#### Object IDs / Addresses

The object IDs of

* the most recently created `ramm_misc::faucet::Faucet` object, as well as
* a 3-asset `BTC/ETH/SOL` RAMM, and
  - its fee collection address (can be changed)
  - its admin capability, and
  - its new asset capability (since deleted with its initialization)

are:

```bash
export FAUCET_ID=0xaf774e31764afcf13761111b662892d12d6998032691160e1b3f7d7f0ab039bd \

export RAMM_ID=0xbee296f4efc42bb228c284c944d58c28a971d5c29c015ba9fe6b0db20b07896d \
export FEE_COLLECTOR=0x1fad963ac9311c5f99685bc430dc022a5b0d36f6860603495ca0a0e3a46dd120 \
export ADMIN_CAP_ID=0xaacbaebf49380e6b5587ce0a26dc54dc4576045ff9c6e3a8aab30e2b48e81ecd \
export NEW_ASSET_CAP_ID=0xb7bcf12b4984e0ea6b11a969b4bc2fa11efa3d488b6ba6696c43425c886d2915
```

The object IDs of

* a 2-asset `ETH/USDC` RAMM, and
  - its fee collection address (can be changed)
  - its admin capability, and
  - its new asset capability (since deleted with its initialization)

are

```bash
export RAMM_ID=0x14cd5b0a0fdb09ca16959ed8b30ac674521fed8ed0089ff4a3d321f3295668ef \
export FEE_COLLECTOR=0x1fad963ac9311c5f99685bc430dc022a5b0d36f6860603495ca0a0e3a46dd120 \
export ADMIN_CAP_ID=0x0c4baabcfe4b9fcfe7c45c5bf5f639e54ab948be0794d8cc9246545edcb8f49a \
export NEW_ASSET_CAP_ID=0xf3d8e8f21e84d4220cec2edb1e30bb3667a57d390d6298e68bbeef2b202e105e
```

Verify these using `tsui client object {object-id}`.

The object IDs of the six Switchboard `Aggregators` presently on the Sui testnet, for
* `BTC, ETH, SOL, SUI, USDT, USDC`
are:

```bash
export BTC_AGG_ID=0x7c30e48db7dfd6a2301795be6cb99d00c87782e2547cf0c63869de244cfc7e47 \
export ETH_AGG_ID=0x68ed81c5dd07d12c629e5cdad291ca004a5cd3708d5659cb0b6bfe983e14778c \
export SOL_AGG_ID=0x35c7c241fa2d9c12cd2e3bcfa7d77192a58fd94e9d6f482465d5e3c8d91b4b43 \
export SUI_AGG_ID=0x84d2b7e435d6e6a5b137bf6f78f34b2c5515ae61cd8591d5ff6cd121a21aa6b7 \
export USDT_AGG_ID=0xe8a09db813c07b0a30c9026b3ff7d5617d2505a097f1a90a06a941d34bee9585 \
export USDC_AGG_ID=0xde58993e6aabe1248a9956557ba744cb930b61437f94556d0380b87913d5ef47
```

### Regarding suibase

[Suibase](https://suibase.io/intro.html) is a tool that assists in the development, testing
and deployment of Sui smart contracts.

It provides a suite of tools and SDKs for Rust/Python that let developers easily target
different Sui networks (e.g. devnet, testnet, main) and configure the development environment,
e.g. by allowing the specification of an exact version of the `sui` binaries, and/or from a forked
repository.

For the purposes of this project, `suibase` will be needed to build/test/deploy the RAMM on a given
network - in this case, the testnet.

After installing `suibase`, optionally [setting](https://suibase.io/how-to/configure-suibase-yaml.html#change-default-repo-and-branch)
the `sui` version to be used, and running `testnet start`, `tsui` will be ready for use in the
user's `$PATH`.

### Requesting tokens from the faucet

In order to create/interact with the RAMM, fictitious tokens are required.

Then, for the purpose of creating test coins to be used to interact with the RAMM,
`ramm-misc/sources/test_coins` offers 5 different tokens for which there exists a corresponding
Switchboard `Aggregator` on the Sui testnet:
 * `BTC, ETH, SOL, USDT, USDC`

`SUI` for gas fees can be requested in the Sui [Discord](https://discord.com/invite/sui) server.

To interact with the faucet, the following data are required:
1. The ID of the `ramm_misc` package, which contains the faucet: it may be `export`ed as
   `FAUCET_PACKAGE_ID`
   - See [above](#addresses-of-currently-published-packages-and-instantiated-objects) a list of
     currently published package IDs
2. The ID of a `ramm_misc::faucet::Faucet` that is currently instantiated on the testnet,
   may it be called `FAUCET_ID`
   - See [above](#addresses-of-currently-published-packages-and-instantiated-objects)
3. The amount of the token to be minted, `COIN_AMNT`.
   - See [below](#obtaining-a-coint-types-decimal-place-count) for a note on how many decimal
     places each fictitious asset has
4. A type argument specifying the specific asset to be requested, `export`ed as `COIN`
   - In the case of e.g. `ETH`, it'll be `"$FAUCET_PACKAGE_ID"::test_coins::"$COIN`, which will
     expand to `"$FAUCET_PACKAGE_ID"::test_coins::ETH`

After these data are set as variables, a specific token, i.e. `ramm_misc::test_coins::BTC`, can be
requested with

```bash
tsui client call --package "$FAUCET_PACKAGE_ID" \
--module test_coin_faucet \
--function mint_test_coins \
--args "$FAUCET_ID" "$COIN_AMNT" \
--type-args "$FAUCET_PACKAGE_ID"::test_coins::"$COIN" \
--gas-budget 100000000
```

#### Obtaining a `Coin<T>` type's decimal place count

For these tests, all assets can be considered to have 8 decimal places.

However, when using real tokens bridged from other chains into Sui, in order to obtain its decimal
place count, do the following:

1. Obtain the ID of the package containing the Sui-side version of the bridged token from
   [the official docs](https://docs.sui.io/learn/sui-bridging); in the case of `WSOL`, it is
  `export PACKAGE_ID=0xb7844e289a8410e50fb3ca48d69eb9cf29e27d223ef90353fe1bd8e27ff8f3f8`
2. Use a [Sui RPC inspector](https://www.suirpc.app/method/suix_getCoinMetadata) to run the
   `get_CoinMetadata` method on `PACKAGE_ID::coin::COIN`
3. In the JSON response, the `decimals` field will be the decimal places the token was configured
   with; for `WSOL`, `8`

### Creating, populating and initializing a RAMM to the testnet

#### Creation

In order to create a RAMM, the following data are necessary:
1. The previously stored `RAMM_PACKAGE_ID`, and
2.  an address for fee collection needs to be specified, e.g. as `FEE_COLLECTOR`.

See [above](#addresses-of-currently-published-packages-and-instantiated-objects) for the addresses
of currently published RAMMs.

After the above:

```bash
tsui client call --package "$RAMM_PACKAGE_ID" \
--module ramm \
--function new_ramm \
--args "$FEE_COLLECTOR" \
--gas-budget 1000000000
```

#### Asset addition

The previous transaction should have resulted in several newly created objects:
1. the RAMM object, which should be `export`ed as `RAMM_ID`
2. an admin capability object, `ADMIN_CAP_ID`
3. a capability used to add new assets, `NEW_ASSET_CAP_ID`

For an asset to be added, assuming its `Aggregator`'s ID from
[the list of presently available testnet aggregators](#addresses-of-currently-published-packages-and-instantiated-objects)
has been `export`ed as `AGGREGATOR_ID`:

```bash
tsui client call --package "$RAMM_PACKAGE_ID" \
  --module ramm \
  --function add_asset_to_ramm \
  --args "$RAMM_ID" "$AGGREGATOR_ID" $MIN_TRADE_AMNT $ASSET_DEC_PLACES "$ADMIN_CAP_ID" "$NEW_ASSET_CAP_ID" \
  --gas-budget 1000000000
```

The values `MIN_TRADE_AMNT` and `ASSET_DEC_PLACES` are the asset's minimum trade amount, and
its decimal places, respectively.
See the note [above](#obtaining-a-coint-types-decimal-place-count) to know how many decimal places
each test token has.

#### Initialize the RAMM

Run the following

```bash
tsui client call --package "$RAMM_PACKAGE_ID" \
  --module ramm \
  --function initialize_ramm \
  --args "$RAMM_ID" "$ADMIN_CAP_ID" "$NEW_ASSET_CAP_ID" \
  --gas-budget 1000000000
```

This will delete the new asset capability associated with this RAMM whose ID is `NEW_ASSET_CAP_ID`,
so no more assets can be added to that RAMM.

Carefully consider the RAMM's desired asset count before initializing it.

#### Depositing liquidity in the RAMM

Consider a concrete example of a `BTC/ETH/SOL` 3-asset RAMM.
As the RAMM has 3 assets, the corresponding public interface must be used.
In order to deposit liquidity for an asset in the RAMM, the following data are required:

1. The previously stored `$RAMM_ID`
2. The coins previously requested from the faucet
   - in this case, `$BTC_ID` is the object ID of the `Coin<$FAUCET_PACKAGE_ID::test_coins::BTC>`
     gotten from the faucet
3. Aggregator IDs for each of the RAMM's 3 assets, once again gotten from [here](https://app.switchboard.xyz/sui/testnet)
   - `$BTC_AGG_ID` for `BTC`
   - `$ETH_AGG_ID` for `ETH`, etc
4. the type information of each of the RAMM's assets
   - in this case, `$FAUCET_PACKAGE_ID::test_coins::BTC` for `BTC`
   - `$FAUCET_PACKAGE_ID::test_coins::ETH` for `ETH`, etc

Note that:
* the first type provided corresponds to the type of the coin object i.e. of the asset for which
  liquidity is being deposited
* the order in which the `Aggregator`s are provided must match the order in which the types are
  given

All of the above results in the following:

```bash
tsui client call --package "$RAMM_PACKAGE_ID" \
  --module interface3 \
  --function liquidity_deposit_3 \
  --args "$RAMM_ID" "$BTC_ID" "$BTC_AGG_ID" "$ETH_AGG_ID" "$SOL_AGG_ID" \
  --gas-budget 1000000000 \
  --type-args "$FAUCET_PACKAGE_ID::test_coins::BTC" "$FAUCET_PACKAGE_ID::test_coins::ETH" "$FAUCET_PACKAGE_ID::test_coins::SOL" 
```

#### Trading with the RAMM

The examples below assume a 3-asset `BTC/ETH/SOL` RAMM with existing initial liquidity.

##### Depositing a specific amount of an asset

In order to eg. deposit exactly 20 ETH into the RAMM, the following data are required:

1. `$RAMM_ID`
2. The ID of the `Coin<$FAUCET_PACKAGE_ID::test_coins::ETH>` previously requested from the faucet
3. The minimum amount of the outbound asset the trader expects to receive, which can be `export`ed
   as `MIN_AMNT_OUT`.
   - Recall that all test coins are created to have 8 decimal places, so e.g. 1 unit of `BTC` should
     be `100000000`
4. Aggregator IDs for each of the RAMM's 3 assets, as always taken from [here](https://app.switchboard.xyz/sui/testnet)
5. the type information of each of the RAMM's assets
   - in this case, `$FAUCET_PACKAGE_ID::test_coins::BTC` for `BTC`, etc

Note that:
* the first type provided corresponds to the inbound asset, as well as the type of the coin object
* the second type provided corresponds to outbound asset
* the order in which the `Aggregator`s are provided must match the order in which the types are
  given

```bash
tsui client call --package "$RAMM_PACKAGE_ID" \
  --module interface3 \
  --function trade_amount_in_3 \
  --args "$RAMM_ID" "$ETH_ID" "$MIN_AMNT_OUT" "$ETH_AGG_ID" "$BTC_AGG_ID" "$SOL_AGG_ID" \
  --gas-budget 1000000000 \
  --type-args "$FAUCET_PACKAGE_ID::test_coins::ETH" "$FAUCET_PACKAGE_ID::test_coins::BTC" "$FAUCET_PACKAGE_ID::test_coins::SOL"
```

##### Withdrawing an exact amount of an asset

In order to e.g. withdraw exactly 1 BTC from the RAMM, the following data are required:

1. `$RAMM_ID`
2. The amount of the outbound asset the trader wishes to receive, which can be `export`ed
   as `AMNT_OUT`.
   - Recall that all test coins are created to have 8 decimal places, so e.g. 1 unit of `BTC` should
     be `100000000`
3. The ID of the coin object previously requested from the faucet
4. Aggregator IDs for each of the RAMM's 3 assets, as always taken from [here](https://app.switchboard.xyz/sui/testnet)
5. the type information of each of the RAMM's assets
   - in this case, `$FAUCET_PACKAGE_ID::test_coins::BTC` for `BTC`, etc

Note that:
* the first type provided corresponds to the inbound asset, as well as the type of the coin object
* the second type provided corresponds to outbound asset
* the order in which the `Aggregator`s are provided must match the order in which the types are
  given

```bash
tsui client call --package "$RAMM_PACKAGE_ID" \
  --module interface3 \
  --function trade_amount_out_3 \
  --args "$RAMM_ID" "$AMNT_OUT" "$BTC_ID"  "$BTC_AGG_ID" "$ETH_AGG_ID" "$SOL_AGG_ID" \
  --gas-budget 1000000000 \
  --type-args "$FAUCET_PACKAGE_ID::test_coins::BTC" "$FAUCET_PACKAGE_ID::test_coins::ETH" "$FAUCET_PACKAGE_ID::test_coins::SOL"
```

#### Executing a liquidity withdrawal

Below are the data required to perform a liquidity withdrawal from the RAMM.
This example also considers the above 3-asset `BTC/ETH/SOL` pool.

1. The `$RAMM_ID` is necessary
2. The object ID, call it `$LP_ID` of the liquidity pool (LP) `Coin`s emitted by the pool upon the
   asset's prior deposit
3. Aggregator IDs for each of the RAMM's 3 assets, as always taken from [here](https://app.switchboard.xyz/sui/testnet)
4. the type information of each of the RAMM's assets, appended by the type of the asset meant to be
   withdrawn
   - in this case, since the pool has 3 assets, 4 type arguments are needed

Note that:
* the last type provided corresponds to
  - the inbound LP tokens which will be burned
  - the outbound asset
* the order in which the `Aggregator`s are provided must match the order in which the pool's types
  are given

```bash
tsui client call --package "$RAMM_PACKAGE_ID" \
  --module interface3 \
  --function liquidity_withdrawal_3 \
  --args "$RAMM_ID" "$LP_ID" "$BTC_AGG_ID" "$ETH_AGG_ID" "$SOL_AGG_ID" \
  --gas-budget 1000000000 \
  --type-args "$FAUCET_PACKAGE_ID::test_coins::BTC" "$FAUCET_PACKAGE_ID::test_coins::ETH" \
     "$FAUCET_PACKAGE_ID::test_coins::SOL" "$FAUCET_PACKAGE_ID::test_coins::BTC"
```

## Testing a Switchboard price feed

A list of price information feeds currently available on the test Sui testnet can be found
[here](https://app.switchboard.xyz/sui/testnet).

In order to test a price feed from the CLI using the `ramm_misc` package, perform the following
actions:

```bash
cd ramm-misc
sui move build
sui client publish --gas-budget 20000000
# export the above package ID to $FAUCET_PACKAGE_ID

# $AGGREGATOR_ID is an ID from https://app.switchboard.xyz/sui/testnet
sui client call \
  --package $FAUCET_PACKAGE_ID \
  --module switchboard_feed_parser \
  --function log_aggregator_info \
  --args $AGGREGATOR_ID \
  --gas-budget 10000000 \
# export the resulting object ID to AGGREGATOR_INFO

sui client object $AGGREGATOR_INFO
```

The relevant information will be in the `latest_result, latest_result_scaling_factor`
fields.

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

The goal of this experiment is to perform a trivial operation: add all of the testing tokens'
amounts.
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