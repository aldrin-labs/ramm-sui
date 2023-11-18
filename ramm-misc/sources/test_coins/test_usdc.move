module ramm_misc::usdc {
    use std::option;
    use sui::tx_context::TxContext;

    use ramm_misc::test_coin_creation;

    /// The type identifier of coin. The coin will have a type
    /// tag of kind: `Coin<package_object::usdc::USDC>`
    struct USDC has drop {}

    /// Module initializer. See https://examples.sui.io/samples/coin.html
    fun init(witness: USDC, ctx: &mut TxContext) {
        test_coin_creation::init_coin(witness, 6, b"USDC", b"", b"", option::none(), ctx);
    }
}
