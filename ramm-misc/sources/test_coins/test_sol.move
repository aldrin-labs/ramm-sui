module ramm_misc::sol {
    use std::option;
    use sui::tx_context::TxContext;

    use ramm_misc::test_coin_creation;

    /// The type identifier of coin. The coin will have a type
    /// tag of kind: `Coin<package_object::sol::SOL>`
    struct SOL has drop {}

    /// Module initializer. See https://examples.sui.io/samples/coin.html
    fun init(witness: SOL, ctx: &mut TxContext) {
        test_coin_creation::init_coin(witness, 6, b"SOL", b"", b"", option::none(), ctx);
    }
}
