module ramm_misc::test_coin_creation {
    use std::option::Option;

    use sui::coin;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::Url;

    /// Module initializer is called once on module publish. A treasury
    /// cap is sent to the publisher, who then controls minting and burning.
    ///
    /// In order to create several test coins, the below cannot be `init`, and
    /// must be public.
    public fun init_coin<T: drop>(
        witness: T,
        // Number of decimal places the coin uses.
        decimals: u8,
        // Name for the token
        token_name: vector<u8>,
        // Symbol for the token
        token_symbol: vector<u8>,
        // Description of the token
        token_desc: vector<u8>,
        // URL for the token logo
        token_URL: Option<Url>,
        ctx: &mut TxContext
    ) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            decimals,
            token_name,
            token_symbol,
            token_desc,
            token_URL,
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx))
    }
}
