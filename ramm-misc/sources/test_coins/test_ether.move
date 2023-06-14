module ramm_misc::eth {
    use std::option;
    use sui::tx_context::TxContext;

    use ramm_misc::test_coin_creation;

    /// The type identifier of coin. The coin will have a type
    /// tag of kind: `Coin<package_object::eth::ETH>`
    struct ETH has drop {}

    /// Module initializer. See https://examples.sui.io/samples/coin.html
    fun init(witness: ETH, ctx: &mut TxContext) {
        test_coin_creation::init_coin(witness, 6, b"ETH", b"", b"", option::none(), ctx);
    }
}
