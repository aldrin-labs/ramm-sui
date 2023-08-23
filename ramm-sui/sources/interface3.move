/// Public interface for 3-asset RAMMs.
module ramm_sui::interface3 {
    use std::type_name::{Self, TypeName};
    use std::string;

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use switchboard::aggregator::Aggregator;

    use ramm_sui::events::{Self, TradeIn, TradeOut};
    use ramm_sui::ramm::{Self, LP, RAMM, RAMMAdminCap, TradeOutput};

    const THREE: u8 = 3;

    /// Amounts of LP tokens are considered to have 9 decimal places.
    ///
    /// Sui Move does not allow the export of `const`s, so this is a redefinition from `ramm.move`.
    ///
    /// This `const` factor is used when performing calculations with LP tokens.
    const FACTOR_LPT: u256 = 1_000_000_000_000 / 1_000_000_000; // FACTOR_LPT = 10**(PRECISION_DECIMAL_PLACES-LP_TOKENS_DECIMAL_PLACES)

    const ERAMMInvalidSize: u64 = 0;
    const EDepositsDisabled: u64 = 1;
    const EInvalidDeposit: u64 = 2;
    const ENoLPTokensInCirculation: u64 = 3;
    const ERAMMInsufficientBalance: u64 = 4;
    /// The pool may have sufficient balance to perform the trade, but doing so
    /// would leave it unable to redeem a liquidity provider's LP tokens
    const ERAMMInsufBalForCirculatingLPToken: u64 = 5;
    const ETradeAmountTooSmall: u64 = 6;
    const ENotAdmin: u64 = 7;
    const ELiqWthdrwLPTBurn: u64 = 8;
    const EInvalidWithdrawal: u64 = 9;

    /// Trading function for a RAMM with three (3) assets.
    /// Used to deposit a given amount of asset `T_i`, in exchange for asset `T_o`.
    ///
    /// # Aborts
    ///
    /// * If this function is called on a RAMM that does not have 3 assets.
    /// * If the provided asset types don't exist in the RAMM
    /// * If the amount being traded in is lower than the RAMM's minimum for the corresponding asset
    /// * If the RAMM has not minted any LP tokens for the inbound asset
    /// * If the RAMM's balance for the outgoing token is 0
    /// * If the aggregator for each asset doesn't match the address in the RAMM's records
    public entry fun trade_amount_in_3<AssetIn, AssetOut, Other>(
        self: &mut RAMM,
        amount_in: Coin<AssetIn>,
        min_ao: u64,
        feed_in: &Aggregator,
        feed_out: &Aggregator,
        other: &Aggregator,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_asset_count(self) == THREE, ERAMMInvalidSize);

        let i = ramm::get_asset_index<AssetIn>(self);
        assert!(coin::value(&amount_in) >= ramm::get_min_trade_amount(self, i), ETradeAmountTooSmall);
        assert!(ramm::lptok_in_circulation<AssetIn>(self, i) > 0, ENoLPTokensInCirculation);

         let o = ramm::get_asset_index<AssetOut>(self);
        let o_bal: u64 = (ramm::get_bal(self, o) as u64);
        assert!(o_bal > 0, ERAMMInsufficientBalance);

        // The trade's size should be checked before oracles are accessed, to spare the trouble
        // of locking the oracle object only to have the tx abort anyway.
        ramm::check_trade_amount_in<AssetIn>(self, (coin::value(&amount_in) as u256));

        let oth = ramm::get_asset_index<Other>(self);

        let new_prices = vec_map::empty<u8, u256>();
        let factors_for_prices = vec_map::empty<u8, u256>();
        let new_price_timestamps = vec_map::empty<u8, u64>();
        ramm::check_feed_and_get_price_data(
            self,
            i,
            feed_in,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );
        ramm::check_feed_and_get_price_data(
            self,
            o,
            feed_out,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );
        ramm::check_feed_and_get_price_data(
            self,
            oth,
            other,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );

        /*
        Calculate volatility data to be used in trading business logic
        */

        let in_vol_fee: u256 = ramm::compute_volatility_fee(
            self,
            i,
            *vec_map::get(&new_prices, &i),
            *vec_map::get(&new_price_timestamps, &i)
        );
        let out_vol_fee: u256 = ramm::compute_volatility_fee(
            self,
            o,
            *vec_map::get(&new_prices, &o),
            *vec_map::get(&new_price_timestamps, &o)
        );
        let other_vol: u256 = ramm::compute_volatility_fee(
            self,
            i,
            *vec_map::get(&new_prices, &oth),
            *vec_map::get(&new_price_timestamps, &oth)
        );
        let calculated_volatility_fee: u256 = in_vol_fee + out_vol_fee;

        /*
        */

        let amount_in_u64: u64 = coin::value(&amount_in);
        let trade: TradeOutput = ramm::trade_i<AssetIn, AssetOut>(
            self,
            i,
            o,
            (amount_in_u64 as u256),
            new_prices,
            factors_for_prices,
            calculated_volatility_fee
        );

        /*
        Update pricing and volatility data for every asset
        */

        let previous_price_i: u256 = ramm::get_prev_prc(self, i);
        let previous_price_timestamp_i = ramm::get_prev_prc_tmstmp(self, i);
        let previous_price_o: u256 = ramm::get_prev_prc(self, o);
        let previous_price_timestamp_o = ramm::get_prev_prc_tmstmp(self, o);
        let previous_price_oth: u256 = ramm::get_prev_prc(self, oth);
        let previous_price_timestamp_oth = ramm::get_prev_prc_tmstmp(self, oth);

        let new_price_i: u256 = *vec_map::get(&new_prices, &i);
        let new_timestamp_i: u64 = *vec_map::get(&new_price_timestamps, &i);
        let new_price_o: u256 = *vec_map::get(&new_prices, &o);
        let new_timestamp_o: u64 = *vec_map::get(&new_price_timestamps, &o);
        let new_price_oth: u256 = *vec_map::get(&new_prices, &oth);
        let new_timestamp_oth: u64 = *vec_map::get(&new_price_timestamps, &oth);

        ramm::update_volatility_data(self, i, previous_price_i, previous_price_timestamp_i, new_price_i, new_timestamp_i, in_vol_fee);
        ramm::update_volatility_data(self, o, previous_price_o, previous_price_timestamp_o, new_price_o, new_timestamp_o, out_vol_fee);
        ramm::update_volatility_data(self, oth, previous_price_oth, previous_price_timestamp_oth, new_price_oth, new_timestamp_oth, other_vol);
        ramm::update_pricing_data<AssetIn>(self, new_price_i, new_timestamp_i);
        ramm::update_pricing_data<AssetOut>(self, new_price_o, new_timestamp_o);
        ramm::update_pricing_data<Other>(self, new_price_oth, new_timestamp_oth);

        /*
        */

        let amount_out_u256: u256 = ramm::amount(&trade);
        ramm::check_trade_amount_out<AssetOut>(self, amount_out_u256);

        let amount_out_u64: u64 = (amount_out_u256 as u64);
        if (ramm::execute(&trade) && amount_out_u64 >= min_ao) {
            let amount_in: Balance<AssetIn> = coin::into_balance(amount_in);

            let fee: u64 = (ramm::protocol_fee(&trade) as u64);
            let fee_bal: Balance<AssetIn> = balance::split(&mut amount_in, fee);
            ramm::join_protocol_fees(self, i, fee_bal);

            ramm::join_bal(self, i, (balance::value(&amount_in) as u256));
            ramm::join_typed_bal(self, i, amount_in);

            ramm::split_bal(self, o, amount_out_u256);
            let amnt_out: Balance<AssetOut> = ramm::split_typed_bal(self, o, amount_out_u64);
            let amnt_out: Coin<AssetOut> = coin::from_balance(amnt_out, ctx);
            transfer::public_transfer(amnt_out, tx_context::sender(ctx));

            events::trade_event<TradeIn>(
                ramm::get_id(self),
                tx_context::sender(ctx),
                type_name::get<AssetIn>(),
                type_name::get<AssetOut>(),
                amount_in_u64,
                amount_out_u64,
                fee,
                ramm::execute(&trade)
            );
        } else if (!ramm::execute(&trade)) {
            transfer::public_transfer(amount_in, tx_context::sender(ctx));

            events::trade_failure_event<TradeIn>(
                ramm::get_id(self),
                tx_context::sender(ctx),
                type_name::get<AssetIn>(),
                type_name::get<AssetOut>(),
                amount_in_u64,
                ramm::message(&trade)
            );
        // In this case, `trade.execute` is true, but `amount_out < min_ao`
        } else {
            transfer::public_transfer(amount_in, tx_context::sender(ctx));

            events::trade_failure_event<TradeIn>(
                ramm::get_id(self),
                tx_context::sender(ctx),
                type_name::get<AssetIn>(),
                type_name::get<AssetOut>(),
                amount_in_u64,
                string::utf8(b"Trade not executed due to slippage tolerance.")
            );
        };

        ramm::check_ramm_invariants_3<AssetIn, AssetOut, Other>(self);
    }

    /// Trading function for a RAMM with three (3) assets.
    /// Used to withdraw a given amount of asset `T_o`, in exchange for asset `T_i`.
    ///
    /// # Aborts
    ///
    /// * If this function is called on a RAMM that does not have 3 assets.
    /// * If the provided asset types don't exist in the RAMM
    /// * If the RAMM has not minted any LP tokens for the inbound asset
    /// * If the amount being traded out is lower than the RAMM's minimum for the corresponding asset
    /// * If the RAMM's balance for the outgoing token is 0
    /// * If the aggregator for each asset doesn't match the address in the RAMM's records
    public entry fun trade_amount_out_3<AssetIn, AssetOut, Other>(
        self: &mut RAMM,
        amount_out: u64,
        max_ai: Coin<AssetIn>,
        feed_in: &Aggregator,
        feed_out: &Aggregator,
        other: &Aggregator,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_asset_count(self) == THREE, ERAMMInvalidSize);

        let i = ramm::get_asset_index<AssetIn>(self);
        assert!(ramm::lptok_in_circulation<AssetIn>(self, i) > 0, ENoLPTokensInCirculation);
        let o = ramm::get_asset_index<AssetOut>(self);
        assert!(amount_out >= ramm::get_min_trade_amount(self, o), ETradeAmountTooSmall);
        let o_bal: u64 = (ramm::get_bal(self, o) as u64);
        assert!(o_bal >= amount_out, ERAMMInsufficientBalance);
        if (amount_out == o_bal) {
            assert!(ramm::lptok_in_circulation<AssetOut>(self, o) == 0, ERAMMInsufBalForCirculatingLPToken)
        };
        let oth = ramm::get_asset_index<Other>(self);

        // The trade's size should be checked before oracles are accessed, to spare the trouble
        // of locking the oracle object only to have the tx abort anyway.
        ramm::check_trade_amount_out<AssetOut>(self, (amount_out as u256));

        let new_prices = vec_map::empty<u8, u256>();
        let factors_for_prices = vec_map::empty<u8, u256>();
        let new_price_timestamps = vec_map::empty<u8, u64>();
        ramm::check_feed_and_get_price_data(
            self,
            i,
            feed_in,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );
        ramm::check_feed_and_get_price_data(
            self,
            o,
            feed_out,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );
        ramm::check_feed_and_get_price_data(
            self,
            oth,
            other,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );

        /*
        Calculate volatility data to be used in trading business logic
        */

        let in_vol_fee: u256 = ramm::compute_volatility_fee(
            self,
            i,
            *vec_map::get(&new_prices, &i),
            *vec_map::get(&new_price_timestamps, &i)
        );
        let out_vol_fee: u256 = ramm::compute_volatility_fee(
            self,
            o,
            *vec_map::get(&new_prices, &o),
            *vec_map::get(&new_price_timestamps, &o)
        );
        let other_vol: u256 = ramm::compute_volatility_fee(
            self,
            i,
            *vec_map::get(&new_prices, &oth),
            *vec_map::get(&new_price_timestamps, &oth)
        );
        let calculated_volatility_fee: u256 = in_vol_fee + out_vol_fee;

        /*
        */

        let trade: TradeOutput = ramm::trade_o<AssetIn, AssetOut>(
            self,
            i,
            o,
            amount_out,
            new_prices,
            factors_for_prices,
            calculated_volatility_fee
        );

        /*
        Update pricing and volatility data for every asset
        */

        let previous_price_i: u256 = ramm::get_prev_prc(self, i);
        let previous_price_timestamp_i = ramm::get_prev_prc_tmstmp(self, i);
        let previous_price_o: u256 = ramm::get_prev_prc(self, o);
        let previous_price_timestamp_o = ramm::get_prev_prc_tmstmp(self, o);
        let previous_price_oth: u256 = ramm::get_prev_prc(self, oth);
        let previous_price_timestamp_oth = ramm::get_prev_prc_tmstmp(self, oth);

        let new_price_i: u256 = *vec_map::get(&new_prices, &i);
        let new_timestamp_i: u64 = *vec_map::get(&new_price_timestamps, &i);
        let new_price_o: u256 = *vec_map::get(&new_prices, &o);
        let new_timestamp_o: u64 = *vec_map::get(&new_price_timestamps, &o);
        let new_price_oth: u256 = *vec_map::get(&new_prices, &oth);
        let new_timestamp_oth: u64 = *vec_map::get(&new_price_timestamps, &oth);

        ramm::update_volatility_data(self, i, previous_price_i, previous_price_timestamp_i, new_price_i, new_timestamp_i, in_vol_fee);
        ramm::update_volatility_data(self, o, previous_price_o, previous_price_timestamp_o, new_price_o, new_timestamp_o, out_vol_fee);
        ramm::update_volatility_data(self, oth, previous_price_oth, previous_price_timestamp_oth, new_price_oth, new_timestamp_oth, other_vol);
        ramm::update_pricing_data<AssetIn>(self, new_price_i, new_timestamp_i);
        ramm::update_pricing_data<AssetOut>(self, new_price_o, new_timestamp_o);
        ramm::update_pricing_data<Other>(self, new_price_oth, new_timestamp_oth);

        /*
        */

        ramm::check_trade_amount_in<AssetIn>(self, ramm::amount(&trade));
        let trade_amount = (ramm::amount(&trade) as u64);

        let max_ai_u64: u64 = coin::value(&max_ai);
        if (ramm::execute(&trade) && trade_amount <= max_ai_u64) {
            let max_ai: Balance<AssetIn> = coin::into_balance(max_ai);
            let amount_in: Balance<AssetIn> = balance::split(&mut max_ai, trade_amount);
            let remainder = max_ai;

            let fee: u64 = (ramm::protocol_fee(&trade) as u64);
            let fee_bal: Balance<AssetIn> = balance::split(&mut amount_in, fee);
            ramm::join_protocol_fees(self, i, fee_bal);

            ramm::join_bal(self, i, (balance::value(&amount_in) as u256));
            ramm::join_typed_bal(self, i, amount_in);

            ramm::split_bal(self, o, (amount_out as u256));
            let amnt_out: Balance<AssetOut> = ramm::split_typed_bal(self, o, amount_out);
            let amnt_out: Coin<AssetOut> = coin::from_balance(amnt_out, ctx);
            transfer::public_transfer(amnt_out, tx_context::sender(ctx));

            events::trade_event<TradeOut>(
                ramm::get_id(self),
                tx_context::sender(ctx),
                type_name::get<AssetIn>(),
                type_name::get<AssetOut>(),
                trade_amount,
                amount_out,
                fee,
                ramm::execute(&trade)
            );

            if (balance::value(&remainder) > 0) {
                let remainder: Coin<AssetIn> = coin::from_balance(remainder, ctx);
                transfer::public_transfer(remainder, tx_context::sender(ctx));
            } else {
                balance::destroy_zero(remainder);
            }
        } else if (!ramm::execute(&trade)) {
            transfer::public_transfer(max_ai, tx_context::sender(ctx));

            events::trade_failure_event<TradeOut>(
                ramm::get_id(self),
                tx_context::sender(ctx),
                type_name::get<AssetIn>(),
                type_name::get<AssetOut>(),
                max_ai_u64,
                ramm::message(&trade)
            );
        // In this case, `trade.execute` is true, but `trade.amount > max_ai`
        } else {
            transfer::public_transfer(max_ai, tx_context::sender(ctx));

            events::trade_failure_event<TradeOut>(
                ramm::get_id(self),
                tx_context::sender(ctx),
                type_name::get<AssetIn>(),
                type_name::get<AssetOut>(),
                max_ai_u64,
                string::utf8(b"Trade not executed due to slippage tolerance.")
            );
        };

        ramm::check_ramm_invariants_3<AssetIn, AssetOut, Other>(self);
    }

    /// Liquidity deposit for a pool with three (3) assets.
    ///
    /// # Aborts
    ///
    /// * If this function is called on a RAMM that does not have 3 assets.
    /// * If the amount being traded in is zero
    /// * If the RAMM does not contain any of the asset types provided
    /// * If the aggregator for each asset doesn't match the address in the RAMM's records
    public entry fun liquidity_deposit_3<AssetIn, Other, Another>(
        self: &mut RAMM,
        amount_in: Coin<AssetIn>,
        feed_in: &Aggregator,
        other: &Aggregator,
        another: &Aggregator,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_asset_count(self) == THREE, ERAMMInvalidSize);
        assert!(coin::value(&amount_in) > 0, EInvalidDeposit);

        let i = ramm::get_asset_index<AssetIn>(self);
        assert!(ramm::can_deposit_asset(self, i), EDepositsDisabled);

        let oth = ramm::get_asset_index<Other>(self);
        let anoth = ramm::get_asset_index<Another>(self);

        let new_prices = vec_map::empty<u8, u256>();
        let factors_for_prices = vec_map::empty<u8, u256>();
        let new_price_timestamps = vec_map::empty<u8, u64>();
        ramm::check_feed_and_get_price_data(
            self, i, feed_in, &mut new_prices, &mut factors_for_prices, &mut new_price_timestamps
        );
        ramm::check_feed_and_get_price_data(
            self, oth, other, &mut new_prices, &mut factors_for_prices, &mut new_price_timestamps
        );
        ramm::check_feed_and_get_price_data(
            self, anoth, another, &mut new_prices, &mut factors_for_prices, &mut new_price_timestamps
        );

        /*
        Calculate volatility data to be used in trading business logic

        Liquidity deposits do not levy a volatility fee, but since they access oracle data
        they must update price/volatility data to keep it as current as possible.
        */

        let in_vol: u256 = ramm::compute_volatility_fee(
            self,
            i,
            *vec_map::get(&new_prices, &i),
            *vec_map::get(&new_price_timestamps, &i)
        );
        let oth_vol: u256 = ramm::compute_volatility_fee(
            self,
            oth,
            *vec_map::get(&new_prices, &oth),
            *vec_map::get(&new_price_timestamps, &oth)
        );
        let anoth_vol: u256 = ramm::compute_volatility_fee(
            self,
            anoth,
            *vec_map::get(&new_prices, &anoth),
            *vec_map::get(&new_price_timestamps, &anoth)
        );

        /*
        */

        let lpt: u64 = ramm::liq_dep<AssetIn>(self, i, coin::value(&amount_in), new_prices, factors_for_prices);

        /*
        Update pricing and volatility data for every asset
        */

        let previous_price_i: u256 = ramm::get_prev_prc(self, i);
        let previous_price_timestamp_i = ramm::get_prev_prc_tmstmp(self, i);
        let previous_price_oth: u256 = ramm::get_prev_prc(self, oth);
        let previous_price_timestamp_oth = ramm::get_prev_prc_tmstmp(self, oth);
        let previous_price_anoth: u256 = ramm::get_prev_prc(self, anoth);
        let previous_price_timestamp_anoth = ramm::get_prev_prc_tmstmp(self, anoth);

        let new_price_i: u256 = *vec_map::get(&new_prices, &i);
        let new_timestamp_i: u64 = *vec_map::get(&new_price_timestamps, &i);
        let new_price_oth: u256 = *vec_map::get(&new_prices, &oth);
        let new_timestamp_oth: u64 = *vec_map::get(&new_price_timestamps, &oth);
        let new_price_anoth: u256 = *vec_map::get(&new_prices, &anoth);
        let new_timestamp_anoth: u64 = *vec_map::get(&new_price_timestamps, &anoth);

        ramm::update_volatility_data(self, i, previous_price_i, previous_price_timestamp_i, new_price_i, new_timestamp_i, in_vol);
        ramm::update_volatility_data(self, oth, previous_price_oth, previous_price_timestamp_oth, new_price_oth, new_timestamp_oth, oth_vol);
        ramm::update_volatility_data(self, anoth, previous_price_anoth, previous_price_timestamp_anoth, new_price_anoth, new_timestamp_anoth, anoth_vol);
        ramm::update_pricing_data<AssetIn>(self, new_price_i, new_timestamp_i);
        ramm::update_pricing_data<Other>(self, new_price_oth, new_timestamp_oth);
        ramm::update_pricing_data<Another>(self, new_price_anoth, new_timestamp_anoth);

        /*
        */

        if (lpt == 0) {
            let amount_in_u64: u64 = coin::value(&amount_in);
            transfer::public_transfer(amount_in, tx_context::sender(ctx));

            events::liquidity_deposit_failure_event(
                ramm::get_id(self),
                tx_context::sender(ctx),
                type_name::get<AssetIn>(),
                amount_in_u64
            );
        } else {
            let amount_in_u64: u64 = coin::value(&amount_in);
            let amount_in: Balance<AssetIn> = coin::into_balance(amount_in);
            ramm::join_bal(self, i, (balance::value(&amount_in) as u256));
            ramm::join_typed_bal(self, i, amount_in);

            // Update RAMM's untyped count of LP tokens for incoming asset
            ramm::incr_lptokens_issued<AssetIn>(self, lpt);
            // Update RAMM's typed count of LP tokens for incoming asset
            let lpt: Balance<LP<AssetIn>> = ramm::mint_lp_tokens(self, lpt);
            let lpt: Coin<LP<AssetIn>> = coin::from_balance(lpt, ctx);
            let lpt_u64: u64 = coin::value(&lpt);
            transfer::public_transfer(lpt, tx_context::sender(ctx));

            events::liquidity_deposit_event(
                ramm::get_id(self),
                tx_context::sender(ctx),
                type_name::get<AssetIn>(),
                amount_in_u64,
                lpt_u64
            );
        };

        ramm::check_ramm_invariants_3<AssetIn, Other, Another>(self);
    }

    /// Withdraw liquidity from a 3-asset RAMM.
    ///
    /// # Aborts
    ///
    /// * If the RAMM does not have 3 assets
    /// * If the pool does not have the asset for which the withdrawal is being requested
    /// * If the RAMM does not contain any of the asset types provided
    /// * If the aggregator for each asset doesn't match the address in the RAMM's records
    public entry fun liquidity_withdrawal_3<Asset1, Asset2, Asset3, AssetOut>(
        self: &mut RAMM,
        lp_token: Coin<ramm::LP<AssetOut>>,
        feed1: &Aggregator,
        feed2: &Aggregator,
        feed3: &Aggregator,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_asset_count(self) == THREE, ERAMMInvalidSize);
        assert!(coin::value(&lp_token) > 0, EInvalidWithdrawal);

        let fst = ramm::get_asset_index<Asset1>(self);
        let snd = ramm::get_asset_index<Asset2>(self);
        let trd = ramm::get_asset_index<Asset3>(self);
        // `o` will be have the same value as exactly *one* of the 3 above indexes -
        // because of limitations with Move's type system, the types of all the pool's assets must
        // be specified, and the type of the outgoing asset as well, separately.
        let o   = ramm::get_asset_index<AssetOut>(self);

        let new_prices = vec_map::empty<u8, u256>();
        let factors_for_prices = vec_map::empty<u8, u256>();
        let new_price_timestamps = vec_map::empty<u8, u64>();
        ramm::check_feed_and_get_price_data(
            self,
            fst,
            feed1,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );
        ramm::check_feed_and_get_price_data(
            self,
            snd,
            feed2,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );
        ramm::check_feed_and_get_price_data(
            self,
            trd,
            feed3,
            &mut new_prices,
            &mut factors_for_prices,
            &mut new_price_timestamps
        );

        /*
        Calculate volatility data to be used when updating the RAMM's data.
        */

        let fst_vol_fee: u256 = ramm::compute_volatility_fee(
            self, fst, *vec_map::get(&new_prices, &fst), *vec_map::get(&new_price_timestamps, &fst)
        );
        let snd_vol_fee: u256 = ramm::compute_volatility_fee(
            self, snd, *vec_map::get(&new_prices, &snd), *vec_map::get(&new_price_timestamps, &snd)
        );
        let trd_vol_fee: u256 = ramm::compute_volatility_fee(
            self, trd, *vec_map::get(&new_prices, &trd), *vec_map::get(&new_price_timestamps, &trd)
        );

        let volatility_fees: VecMap<u8, u256> = vec_map::empty();
        vec_map::insert(&mut volatility_fees, fst, fst_vol_fee);
        vec_map::insert(&mut volatility_fees, snd, snd_vol_fee);
        vec_map::insert(&mut volatility_fees, trd, trd_vol_fee);
        /*
        */

        let lpt_u64: u64 = coin::value(&lp_token);
        let factor_o: u256 = ramm::get_fact_for_bal(self, o);
        let withdrawal_output =
            ramm::liq_wthdrw<AssetOut>(
                self,
                o,
                lpt_u64,
                new_prices,
                factors_for_prices,
                volatility_fees
            );

        /*
        Update pricing and volatility data for every asset
        */

        let previous_price_fst: u256 = ramm::get_prev_prc(self, fst);
        let previous_price_timestamp_fst = ramm::get_prev_prc_tmstmp(self, fst);
        let previous_price_snd: u256 = ramm::get_prev_prc(self, snd);
        let previous_price_timestamp_snd = ramm::get_prev_prc_tmstmp(self, snd);
        let previous_price_trd: u256 = ramm::get_prev_prc(self, trd);
        let previous_price_timestamp_trd = ramm::get_prev_prc_tmstmp(self, trd);

        let new_price_fst: u256 = *vec_map::get(&new_prices, &fst);
        let new_timestamp_fst: u64 = *vec_map::get(&new_price_timestamps, &fst);
        let new_price_snd: u256 = *vec_map::get(&new_prices, &snd);
        let new_timestamp_snd: u64 = *vec_map::get(&new_price_timestamps, &snd);
        let new_price_trd: u256 = *vec_map::get(&new_prices, &trd);
        let new_timestamp_trd: u64 = *vec_map::get(&new_price_timestamps, &trd);

        ramm::update_volatility_data(self, fst, previous_price_fst, previous_price_timestamp_fst, new_price_fst, new_timestamp_fst, fst_vol_fee);
        ramm::update_volatility_data(self, snd, previous_price_snd, previous_price_timestamp_snd, new_price_snd, new_timestamp_snd, snd_vol_fee);
        ramm::update_volatility_data(self, trd, previous_price_trd, previous_price_timestamp_trd, new_price_trd, new_timestamp_trd, trd_vol_fee);
        ramm::update_pricing_data<Asset1>(self, new_price_fst, new_timestamp_fst);
        ramm::update_pricing_data<Asset2>(self, new_price_snd, new_timestamp_snd);
        ramm::update_pricing_data<Asset3>(self, new_price_trd, new_timestamp_trd);

        /*
        */

        let lpt_u256: u256 = (lpt_u64 as u256);
        let lpt_amount: &mut u256 = &mut (copy lpt_u256);
        if (ramm::remaining(&withdrawal_output) > 0) {
            // lpt_amount = lpt*(out.value-out.remaining)/out.value
            *lpt_amount =
                ramm::div(
                    ramm::mul(
                        lpt_u256 * FACTOR_LPT,
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
        // This cannot happen, but it's best to guard anyway.
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

        let amounts_out: VecMap<u8, u256> = ramm::amounts(&withdrawal_output);
        let fees: VecMap<u8, u256> = ramm::fees(&withdrawal_output);

        // Withdraw first asset in the RAMM for the liquidity provider
        let amount_fst: u256 = *vec_map::get(&amounts_out, &fst);
        if (amount_fst != 0) {
            let fee_fst: u256 = *vec_map::get(&fees, &fst);
            let amount_fst: Coin<Asset1> = ramm::liq_withdraw_helper<Asset1>(self, fst, amount_fst, fee_fst, ctx);
            transfer::public_transfer(amount_fst, tx_context::sender(ctx));
        };

        // Withdraw second asset in the RAMM for the liquidity provider
        let amount_snd: u256 = *vec_map::get(&amounts_out, &snd);
        if (amount_snd != 0) {
            let fee_snd: u256 = *vec_map::get(&fees, &snd);
            let amount_snd: Coin<Asset2> = ramm::liq_withdraw_helper<Asset2>(self, snd, amount_snd, fee_snd, ctx);
            transfer::public_transfer(amount_snd, tx_context::sender(ctx));
        };

        // Withdraw third asset in the RAMM for the liquidity provider
        let amount_trd: u256 = *vec_map::get(&amounts_out, &trd);
        if (amount_trd != 0) {
            let fee_trd: u256 = *vec_map::get(&fees, &trd);
            let amount_trd: Coin<Asset3> = ramm::liq_withdraw_helper<Asset3>(self, trd, amount_trd, fee_trd, ctx);
            transfer::public_transfer(amount_trd, tx_context::sender(ctx));
        };

        // Build required data structures for liquidity withdrawal event emission.

        let amounts_out_u64: VecMap<TypeName, u64> = vec_map::empty();
        let fees_u64: VecMap<TypeName, u64> = vec_map::empty();
        vec_map::insert(&mut amounts_out_u64, type_name::get<Asset1>(), (*vec_map::get(&amounts_out, &fst) as u64));
        vec_map::insert(&mut fees_u64, type_name::get<Asset1>(), (*vec_map::get(&fees, &fst) as u64));
        if (vec_map::contains(&amounts_out, &snd)) {
            vec_map::insert(&mut amounts_out_u64, type_name::get<Asset2>(), (*vec_map::get(&amounts_out, &snd) as u64));
            vec_map::insert(&mut fees_u64, type_name::get<Asset2>(), (*vec_map::get(&fees, &snd) as u64));
        };
        if (vec_map::contains(&amounts_out, &trd)) {
            vec_map::insert(&mut amounts_out_u64, type_name::get<Asset3>(), (*vec_map::get(&amounts_out, &trd) as u64));
            vec_map::insert(&mut fees_u64, type_name::get<Asset3>(), (*vec_map::get(&fees, &trd) as u64));
        };

        events::liquidity_withdrawal_event(
            ramm::get_id(self),
            tx_context::sender(ctx),
            type_name::get<AssetOut>(),
            lpt_u64,
            amounts_out_u64,
            fees_u64
        );

        ramm::check_ramm_invariants_3<Asset1, Asset2, Asset3>(self);
    }

    /// Collect fees for a given RAMM, sending them to the fee collection address
    /// specified upon the RAMM's creation.
    ///
    /// # Aborts
    ///
    /// * If called with the wrong admin capability object
    /// * If the RAMM does not have exactly 3 assets, whose types match the ones provided
    ///   as parameters.
    /// * If the RAMM does not contain any of the assets types provided
    public entry fun collect_fees_3<Asset1, Asset2, Asset3>(
        self: &mut RAMM,
        a: &RAMMAdminCap,
        ctx: &mut TxContext
    ) {
        assert!(ramm::get_admin_cap_id(self) == object::id(a), ENotAdmin);
        assert!(ramm::get_asset_count(self) == THREE, ERAMMInvalidSize);

        let fst = ramm::get_asset_index<Asset1>(self);
        let snd = ramm::get_asset_index<Asset2>(self);
        let trd = ramm::get_asset_index<Asset3>(self);

        let fst: Coin<Asset1> = coin::from_balance(ramm::get_fees_for_asset<Asset1>(self, fst), ctx);
        let snd: Coin<Asset2> = coin::from_balance(ramm::get_fees_for_asset<Asset2>(self, snd), ctx);
        let trd: Coin<Asset3> = coin::from_balance(ramm::get_fees_for_asset<Asset3>(self, trd), ctx);

        let value_fst: u64 = coin::value(&fst);
        let value_snd: u64 = coin::value(&snd);
        let value_trd: u64 = coin::value(&trd);

        let collected_fees: VecMap<TypeName, u64> = vec_map::empty();
        vec_map::insert(&mut collected_fees, type_name::get<Asset1>(), value_fst);
        vec_map::insert(&mut collected_fees, type_name::get<Asset2>(), value_snd);
        vec_map::insert(&mut collected_fees, type_name::get<Asset3>(), value_trd);

        let fee_collector = ramm::get_fee_collector(self);
        if (value_fst > 0) { transfer::public_transfer(fst, fee_collector); } else { coin::destroy_zero(fst); };
        if (value_snd > 0) { transfer::public_transfer(snd, fee_collector); } else { coin::destroy_zero(snd); };
        if (value_trd > 0) { transfer::public_transfer(trd, fee_collector); } else { coin::destroy_zero(trd); };

        events::fee_collection_event(
            ramm::get_id(self),
            tx_context::sender(ctx),
            fee_collector,
            collected_fees
        );

        ramm::check_ramm_invariants_3<Asset1, Asset2, Asset3>(self);
    }
}