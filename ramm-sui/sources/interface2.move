/// Public interface for 2-asset RAMMs.
module ramm_sui::interface2 {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map;

    use switchboard::aggregator::Aggregator;

    use ramm_sui::ramm::{Self, LP, RAMM, RAMMAdminCap};

    const TWO: u8 = 2;

    /// Amounts of LP tokens are considered to have 9 decimal places.
    ///
    /// This `const` factor is used when performing calculations with LP tokens.
    const FACTOR_LPT: u256 = 1_000_000_000_000 / 1_000_000_000; // FACTOR_LPT = 10**(PRECISION_DECIMAL_PLACES-LP_TOKENS_DECIMAL_PLACES)

    const ERAMMInvalidSize: u64 = 0;
    const EDepositsDisabled: u64 = 1;
    const EInvalidDeposit: u64 = 2;
    const ENoLPTokensInCirculation: u64 = 3;
    const ERAMMInsufficientBalance: u64 = 4;
    const ETradeAmountTooSmall: u64 = 5;
    const ENotAdmin: u64 = 6;
    const ELiqWthdrwLPTBurn: u64 = 7;

    /// Trading function for a RAMM with two (2) assets.
    /// Used to deposit a given amount of asset `T_i`, in exchange for asset `T_o`.
    ///
    /// # Aborts
    ///
    /// * If this function is called on a RAMM that does not have 2 assets.
    /// * If the provided asset types don't exist in the RAMM
    /// * If the amount being traded in is lower than the RAMM's minimum for the corresponding asset
    /// * If the RAMM has not minted any LP tokens for the inbound asset
    /// * If the RAMM's balance for the outgoing token is 0
    /// * If the aggregator for each asset doesn't match the address in the RAMM's records
    public entry fun trade_amount_in_2<AssetIn, AssetOut>(
        self: &mut RAMM,
        amount_in: Coin<AssetIn>,
        min_ao: u64,
        feed_in: &Aggregator,
        feed_out: &Aggregator,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_asset_count(self) == TWO, ERAMMInvalidSize);

        let i = ramm::get_asset_index<AssetIn>(self);
        assert!(coin::value(&amount_in) >= ramm::get_min_trade_amount(self, i), ETradeAmountTooSmall);
        assert!(ramm::lptok_in_circulation<AssetIn>(self, i) > 0, ENoLPTokensInCirculation);

        let o = ramm::get_asset_index<AssetOut>(self);
        let o_bal: u64 = (ramm::get_bal(self, o) as u64);
        assert!(o_bal > 0, ERAMMInsufficientBalance);

        let asset_prices = vec_map::empty<u8, u256>();
        let factors_for_prices = vec_map::empty<u8, u256>();
        ramm::check_feed_and_get_price(self, i, feed_in, &mut asset_prices, &mut factors_for_prices);
        ramm::check_feed_and_get_price(self, o, feed_out, &mut asset_prices, &mut factors_for_prices);

        let trade: ramm::TradeOutput = ramm::trade_i<AssetIn, AssetOut>(
            self,
            i,
            o,
            (coin::value(&amount_in) as u256),
            asset_prices,
            factors_for_prices
        );

        let amount_in: Balance<AssetIn> = coin::into_balance(amount_in);
        let amount_out = (ramm::amount(&trade) as u64);
        if (ramm::execute(&trade) && amount_out >= min_ao) {
            let fee: u64 = (ramm::protocol_fee(&trade) as u64);
            let fee_bal: Balance<AssetIn> = balance::split(&mut amount_in, fee);
            ramm::join_protocol_fees(self, i, fee_bal);

            ramm::join_bal(self, i, (balance::value(&amount_in) as u256));
            ramm::join_typed_bal(self, i, amount_in);

            ramm::split_bal(self, o, (amount_out as u256));
            let amount_out: Balance<AssetOut> = ramm::split_typed_bal(self, o, amount_out);
            let amount_out: Coin<AssetOut> = coin::from_balance(amount_out, ctx);
            transfer::public_transfer(amount_out, tx_context::sender(ctx));
        } else if (!ramm::execute(&trade)) {
            let amount_in = coin::from_balance(amount_in, ctx);
            transfer::public_transfer(amount_in, tx_context::sender(ctx));
        } else {
            let amount_in = coin::from_balance(amount_in, ctx);
            transfer::public_transfer(amount_in, tx_context::sender(ctx));
        };
    }

    /// Trading function for a RAMM with two (2) assets.
    /// Used to withdraw a given amount of asset `T_o`, in exchange for asset `T_i`.
    ///
    /// # Aborts
    ///
    /// * If this function is called on a RAMM that does not have 2 assets.
    /// * If the provided asset types don't exist in the RAMM
    /// * If the RAMM has not minted any LP tokens for the inbound asset
    /// * If the amount being traded out is lower than the RAMM's minimum for the corresponding asset
    /// * If the RAMM's balance for the outgoing token is 0
    /// * If the aggregator for each asset doesn't match the address in the RAMM's records
    public entry fun trade_amount_out_2<AssetIn, AssetOut>(
        self: &mut RAMM,
        amount_out: u64,
        max_ai: Coin<AssetIn>,
        feed_in: &Aggregator,
        feed_out: &Aggregator,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_asset_count(self) == TWO, ERAMMInvalidSize);

        let i = ramm::get_asset_index<AssetIn>(self);
        assert!(ramm::lptok_in_circulation<AssetIn>(self, i) > 0, ENoLPTokensInCirculation);
        let o = ramm::get_asset_index<AssetOut>(self);
        assert!(amount_out >= ramm::get_min_trade_amount(self, o), ETradeAmountTooSmall);
        let o_bal: u64 = (ramm::get_bal(self, o) as u64);
        assert!(o_bal >= amount_out, ERAMMInsufficientBalance);
        if (amount_out == o_bal) {
            assert!(ramm::lptok_in_circulation<AssetOut>(self, o) == 0, ERAMMInsufficientBalance)
        };

        let asset_prices = vec_map::empty<u8, u256>();
        let factors_for_prices = vec_map::empty<u8, u256>();
        ramm::check_feed_and_get_price(self, i, feed_in, &mut asset_prices, &mut factors_for_prices);
        ramm::check_feed_and_get_price(self, o, feed_out, &mut asset_prices, &mut factors_for_prices);

        let trade = ramm::trade_o<AssetIn, AssetOut>(
            self,
            i,
            o,
            amount_out,
            asset_prices,
            factors_for_prices
        );

        let trade_amount = (ramm::amount(&trade) as u64);

        if (ramm::execute(&trade) && trade_amount <= coin::value(&max_ai)) {
            let max_ai: Balance<AssetIn> = coin::into_balance(max_ai);
            let amount_in: Balance<AssetIn> = balance::split(&mut max_ai, trade_amount);
            let remainder = max_ai;

            let fee: u64 = (ramm::protocol_fee(&trade) as u64);
            let fee_bal: Balance<AssetIn> = balance::split(&mut amount_in, fee);
            ramm::join_protocol_fees(self, i, fee_bal);

            ramm::join_bal(self, i, (balance::value(&amount_in) as u256));
            ramm::join_typed_bal(self, i, amount_in);

            ramm::split_bal(self, o, (amount_out as u256));
            let amount_out: Balance<AssetOut> = ramm::split_typed_bal(self, o, amount_out);
            let amount_out: Coin<AssetOut> = coin::from_balance(amount_out, ctx);
            transfer::public_transfer(amount_out, tx_context::sender(ctx));

            if (balance::value(&remainder) > 0) {
                let remainder: Coin<AssetIn> = coin::from_balance(remainder, ctx);
                transfer::public_transfer(remainder, tx_context::sender(ctx));
            } else {
                balance::destroy_zero(remainder);
            }
        } else if (!ramm::execute(&trade)) {
            transfer::public_transfer(max_ai, tx_context::sender(ctx));
        } else {
            transfer::public_transfer(max_ai, tx_context::sender(ctx));
        };
    }

    /// Liquidity deposit for a pool with two (2) assets.
    ///
    /// # Aborts
    ///
    /// * If this function is called on a RAMM that does not have 2 assets.
    /// * If the amount being traded in is zero
    /// * If the RAMM does not contain any of the asset types provided
    /// * If the aggregator for each asset doesn't match the address in the RAMM's records
    public entry fun liquidity_deposit_2<AssetIn, Other>(
        self: &mut RAMM,
        amount_in: Coin<AssetIn>,
        feed_in: &Aggregator,
        other: &Aggregator,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_asset_count(self) == TWO, ERAMMInvalidSize);
        assert!(coin::value(&amount_in) > 0, EInvalidDeposit);

        let i = ramm::get_asset_index<AssetIn>(self);
        assert!(ramm::can_deposit_asset(self, i), EDepositsDisabled);

        let oth = ramm::get_asset_index<Other>(self);

        let asset_prices = vec_map::empty<u8, u256>();
        let factors_for_prices = vec_map::empty<u8, u256>();
        ramm::check_feed_and_get_price(self, i, feed_in, &mut asset_prices, &mut factors_for_prices);
        ramm::check_feed_and_get_price(self, oth, other, &mut asset_prices, &mut factors_for_prices);

        let lpt: u64 = ramm::single_asset_deposit<AssetIn>(self, i, coin::value(&amount_in), asset_prices, factors_for_prices);

        if (lpt == 0) {
            transfer::public_transfer(amount_in, tx_context::sender(ctx));
            // TODO for after events are implemented
        } else {
            let amount_in: Balance<AssetIn> = coin::into_balance(amount_in);
            ramm::join_bal(self, i, (balance::value(&amount_in) as u256));
            ramm::join_typed_bal(self, i, amount_in);

            // Update RAMM's untyped count of LP tokens for incoming asset
            ramm::incr_lptokens_issued<AssetIn>(self, lpt);
            // Update RAMM's typed count of LP tokens for incoming asset
            let lpt: Balance<LP<AssetIn>> = ramm::mint_lp_tokens(self, lpt);
            let lpt: Coin<LP<AssetIn>> = coin::from_balance(lpt, ctx);
            
            transfer::public_transfer(lpt, tx_context::sender(ctx));
        }

    }

    /// Withdraw liquidity from a 2-asset RAMM.
    ///
    /// # Aborts
    ///
    /// * If the RAMM does not have 2 assets
    /// * If the pool does not have the asset for which the withdrawal is being requested
    /// * If the RAMM does not contain any of the asset types provided
    /// * If the aggregator for each asset doesn't match the address in the RAMM's records
    public entry fun liquidity_withdrawal_2<Asset1, Asset2, AssetOut>(
        self: &mut RAMM,
        lp_token: Coin<ramm::LP<AssetOut>>,
        feed1: &Aggregator,
        feed2: &Aggregator,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_asset_count(self) == TWO, ERAMMInvalidSize);

        let fst = ramm::get_asset_index<Asset1>(self);
        let snd = ramm::get_asset_index<Asset2>(self);
        // `o` will be have the same value as exactly *one* of the 2 above indexes -
        // because of limitations with Move's type system, the types of all the pool's assets must
        // be specified, and the type of the outgoing asset as well, separately.
        let o   = ramm::get_asset_index<AssetOut>(self);

        let asset_prices = vec_map::empty<u8, u256>();
        let factors_for_prices = vec_map::empty<u8, u256>();
        ramm::check_feed_and_get_price(self, fst, feed1, &mut asset_prices, &mut factors_for_prices);
        ramm::check_feed_and_get_price(self, snd, feed2, &mut asset_prices, &mut factors_for_prices);

        let lpt: u64 = coin::value(&lp_token);
        let factor_o: u256 = ramm::get_fact_for_bal(self, o);
        let withdrawal_output =
            ramm::single_asset_withdrawal<AssetOut>(
                self,
                o,
                lpt,
                asset_prices,
                factors_for_prices,
            );

        let lpt: u256 = (lpt as u256);
        let lpt_amount: &mut u256 = &mut (copy lpt);
        if (ramm::remaining(&withdrawal_output) > 0) {
            // lpt_amount = lpt*(out.value-out.remaining)/out.value
            *lpt_amount =
                ramm::div(
                    ramm::mul(
                        lpt * FACTOR_LPT,
                        (ramm::value(&withdrawal_output) - ramm::remaining(&withdrawal_output)) * factor_o
                    ),
                    ramm::value(&withdrawal_output) * factor_o
                ) / FACTOR_LPT;
        };

        let burn_amount: u64 = (*lpt_amount as u64);
        let lp_token: Balance<LP<AssetOut>> = coin::into_balance(lp_token);
        let burn_tokens: Balance<LP<AssetOut>> = balance::split(&mut lp_token, burn_amount);
        // Update RAMM's untyped count of LP tokens for outgoing asset
        ramm::decr_lptokens_issued<AssetOut>(self, burn_amount);
        // Update RAMM's typed count of LP tokens for outgoing asset
        let burned: u64 = ramm::burn_lp_tokens<AssetOut>(self, burn_tokens);
        assert!(burned == burn_amount, ELiqWthdrwLPTBurn);
        // All of the tokens from the provider were burned, so the `Balance` can be
        // destroyed
        if (balance::value(&lp_token) == 0) {
            balance::destroy_zero(lp_token);
        } else {
            // Not all LP tokens could be redeemed, so the remainder is returned to the
            // liquidity provider i.e. the current tx's sender.
            let lp_token: Coin<LP<AssetOut>> = coin::from_balance(lp_token, ctx);
            transfer::public_transfer(lp_token, tx_context::sender(ctx));
        };

        let amounts_out = ramm::amounts(&withdrawal_output);

        // Withdraw first asset in the RAMM for the liquidity provider
        let amount_fst: u256 = *vec_map::get(&amounts_out, &fst);
        if (amount_fst != 0) {
            ramm::split_bal(self, fst, amount_fst);
            let amount_out: Balance<Asset1> = ramm::split_typed_bal(self, fst, (amount_fst as u64));
            let amount_out: Coin<Asset1> = coin::from_balance(amount_out, ctx);
            transfer::public_transfer(amount_out, tx_context::sender(ctx));
        };

        // Withdraw second asset in the RAMM for the liquidity provider
        let amount_snd: u256 = *vec_map::get(&amounts_out, &snd);
        if (amount_snd != 0) {
            ramm::split_bal(self, snd, amount_snd);
            let amount_out: Balance<Asset2> = ramm::split_typed_bal(self, snd, (amount_snd as u64));
            let amount_out: Coin<Asset2> = coin::from_balance(amount_out, ctx);
            transfer::public_transfer(amount_out, tx_context::sender(ctx));
        };
    }

    /// Collect fees for a given RAMM, sending them to the fee collection address
    /// specified upon the RAMM's creation.
    ///
    /// # Aborts
    ///
    /// * If called with the wrong admin capability object
    /// * If the RAMM does not have exactly 2 assets, whose types match the ones provided
    ///   as parameters.
    /// * If the RAMM does not contain any of the assets types provided
    public entry fun collect_fees_2<Asset1, Asset2>(
        self: &mut RAMM,
        a: &RAMMAdminCap,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_admin_cap_id(self) == object::id(a), ENotAdmin);
        assert!(ramm::get_asset_count(self) == TWO, ERAMMInvalidSize);

        let fst = ramm::get_asset_index<Asset1>(self);
        let snd = ramm::get_asset_index<Asset2>(self);

        let fst = coin::from_balance(ramm::get_fees_for_asset<Asset1>(self, fst), ctx);
        let snd = coin::from_balance(ramm::get_fees_for_asset<Asset2>(self, snd), ctx);

        let fee_collector = ramm::get_fee_collector(self);

        transfer::public_transfer(fst, fee_collector);
        transfer::public_transfer(snd, fee_collector);
    }
}