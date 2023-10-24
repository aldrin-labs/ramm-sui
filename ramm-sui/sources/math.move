module ramm_sui::math {
    //use std::debug;

    use sui::vec_map::{Self, VecMap};

    use switchboard::math as sb_math;

    friend ramm_sui::ramm;

    const ENegativeSbD: u64 = 0;
    const EMulOverflow: u64 = 1;
    const EDividendTooLarge: u64 = 2;
    const EDivOverflow: u64 = 3;
    const EPowNExponentTooLarge: u64 = 4;
    const EPowNBaseTooLarge: u64 = 5;
    const EPowDBaseOutOfBounds: u64 = 6;
    const EPowDExpTooLarge: u64 = 7;

    /// ---------
    /// Operators
    /// ---------

    fun sbd_data_to_info(value: u128, scaling_factor: u8, neg: bool, prec: u8): (u256, u256) {
        assert!(!neg, ENegativeSbD);

        ((value as u256), pow(10u256, prec - scaling_factor))
    }

    /// This isn't a mistake - several spec blocks are required in order to
    /// 1. Specify all possible aborts for this function
    /// 2. Specify all (or some of the) conditions in which they occur
    ///
    /// Overflows can occur in two distinct locations:
    /// 1. in `pow`, and
    /// 2. when calculating `prec - scaling_factor`
    ///
    /// The first cannot be encoded without exponentiation specified in the MSL.
    /// That means an `aborts_if` clause for it cannot be written, which is unnecessary
    /// if all the specification asserts in which kinds of aborts occur, not how.
    ///
    /// A partial specification for how they can occur is below.
    spec sbd_data_to_info {
        aborts_with ENegativeSbD, EXECUTION_FAILURE;
    }

    spec sbd_data_to_info {
        pragma verify = true;

        // In order to have the below set to false, it'd be necessary to specify the behavior of
        // `pow`, which is not possible at the moment.
        //
        // As such, it is not possible to cover aborts caused by that function's overflow.
        pragma aborts_if_is_partial = true;

        aborts_if neg with ENegativeSbD;
        aborts_if scaling_factor > prec with EXECUTION_FAILURE;
    }

    /// Given a `switchboard::aggregator::SwitchboardDecimal`, returns:
    /// * the price as a `u256`
    /// * the scaling factor by which the price can be multiplied in order to bring it to `prec`
    ///   decimal places of precision
    ///
    /// # Aborts
    ///
    /// * If the `SwitchboardDecimal`'s `neg`ative flag was set to `true`.
    /// * If the `SwitchboardDecimal`'s `scaling_factor` is more than `prec`; in practice
    ///   this will not happen because it can be at most `9`; see documentation for
    ///   `SwitchboardDecimal`
    public fun sbd_to_price_info(sbd: sb_math::SwitchboardDecimal, prec: u8): (u256, u256) {
        let (value, scaling_factor, neg) = sb_math::unpack(sbd);

        sbd_data_to_info(value, scaling_factor, neg, prec)
    }

    /// Given a `u256` value, forecefully clamp it to the range `[0, max]`.
    public(friend) fun clamp(val: u256, max: u256): u256 {
        if (val >= max) { return max };
        val
    }

    /// Raise a `base: u256` to the power of a `u8` `exp`onent.
    ///
    /// # Aborts
    ///
    /// If the calculation overflows.
    public fun pow(base: u256, exp: u8): u256 {
        let res = 1;
        while (exp >= 1) {
            if (exp % 2 == 0) {
                base = base * base;
                exp = exp / 2;
            } else {
                res = res * base;
                exp = exp - 1;
            }
        };

        res
    }

    /// Multiplies two `u256` that represent decimal numbers with `prec` decimal places,
    /// and returns the result as another `u256` with the same amount of decimal places.
    ///
    /// # Aborts
    ///
    /// * If either operand or the result overflow past `pow(10, max_prec)`.
    public fun mul(x: u256, y: u256, prec: u8, max_prec: u8): u256 {
        let max = pow(10u256, max_prec);
        assert!(x <= max && y <= max, EMulOverflow);
        let result = x * y / pow(10u256, prec);
        assert!(result <= max, EMulOverflow);

        result
    }

    /// Given `x`, `y` and `z` with `prec` decimal places of precision, and at most `max_prec`
    /// places, calculate `x * y * z` with `prec` places, and at most `max_prec`.
    ///
    /// # Aborts
    ///
    /// * If any operand overflows past `pow(10, max_prec)`
    /// * If any intermediate/final results overflow past `pow(10, max_prec)`
    public fun mul3(x: u256, y: u256, z: u256, prec: u8, max_prec: u8): u256 {
        mul(x, mul(y, z, prec, max_prec), prec, max_prec)
    }

    /// Divides two `u256` that represent decimal numbers with `prec` decimal places,
    /// and returns the result as another `u256` with the same amount of decimal places.
    ///
    /// # Aborts
    ///
    /// * If the dividend or the result overflow past `pow(10, max_prec)`.
    public(friend) fun div(x: u256, y: u256, prec: u8, max_prec: u8): u256 {
        let max = pow(10u256, max_prec);
        assert!(x <= max, EDividendTooLarge);
        let result = x * pow(10u256, prec) / y;
        assert!(result <= max, EDivOverflow);

        result
    }

    /// Computes `x^n`, where `n` is a non-negative integer and `x` is a `u256` that represents a
    /// decimal number with `prec` decimal places.
    ///
    /// # Aborts
    ///
    /// * If the exponent exceeds `127`
    /// * If the base exceeds `10^max_prec`
    /// * If during intermediate operations, any value exceeds `10^max_prec`
    public(friend) fun pow_n(x: u256, n: u256, one: u256, prec: u8, max_prec:u8): u256 {
        let max = pow(10u256, max_prec);
        assert!(n <= 127, EPowNExponentTooLarge);
        assert!(x <= max, EPowNBaseTooLarge);

        let result: u256 = one;
        let a: u256 = x;

        while (n != 0) {
            if (n % 2 == 1) {
                result = mul(result, a, prec, max_prec);
            };
            a = mul(a, a, prec, max_prec);
            n = n / 2;
            if (n == 0) { break };
        };

        result
    }

    /// Computes `x^a`, where `a` is a real number between `0` and `1`. Both `a` and `x` have to
    /// be given with `prec` decimal places.
    ///
    /// The result is given in the same format.
    ///
    /// # Aborts
    ///
    /// * If it is not the case that `0.67 <= x <= 1.5`.
    /// * If the exponent is not in `[0, 1[` (with `prec` decimal places)
    public(friend) fun pow_d(x: u256, a: u256, one: u256, prec: u8, max_prec: u8): u256 {
        let pow = pow(10, prec - 2);
        assert!(67 * pow <= x && x <= 150 * pow, EPowDBaseOutOfBounds);
        assert!(a < one, EPowDExpTooLarge);

        let result: u256 = one;
        let n: u256 = 0;
        let tn: u256 = one;
        let sign: bool = true;
        let iters = 30;

        while (n < iters) {
            let _factor1: u256 = 0;
            let _factor2: u256 = 0;

            if (a >= n * one) {
                _factor1 = a - n * one;
            } else {
                _factor1 = n * one - a;
                sign = !sign;
            };
            if (x >= one) {
                _factor2 = x - one;
            }
            else {
                _factor2 = one - x;
                sign = !sign;
            };
            let tn1: u256 = div(mul3(tn, _factor1, _factor2, prec, max_prec), n * one + one, prec, max_prec);

            if (tn1 == 0) {
                return result
            };
            if (sign) {
                result = result + tn1;
            }
            else {
                result = result - tn1;
            };

            n = n + 1;
            tn = tn1;
        };

        result
    }

    /// Miguel's notes:
    ///
    /// Computes `x^a`, where `a` is a real number that belongs to the interval `[0,128)`.
    /// Both `a` and `x` have to be given with `prec` decimal places.
    ///
    /// The result is given in the same format.
    public(friend) fun power(x: u256, a: u256, one: u256, prec: u8, max_prec: u8): u256 {
        let n = a / pow(10u256, prec);
        mul(
            pow_n(x, n, one, prec, max_prec),
            pow_d(x, a - n * one, one, prec, max_prec),
            prec, max_prec
        )
    }

    /// Base function that adjusts the leverage parameter and the base fee.
    public(friend) fun adjust(x: u256, prec: u8, max_prec: u8): u256 {
        mul3(x, x, x, prec, max_prec)
    }

    /// ---------
    /// Functions
    /// ---------

    /// Returns a list with the weights of the tokens with respect to the given prices.
    ///
    /// The result is given in `u256` with `prec` decimal places.
    public fun weights(
        balances: &VecMap<u8, u256>,
        prices: &VecMap<u8, u256>,
        factor_balances: &VecMap<u8, u256>,
        factors_for_prices: &VecMap<u8, u256>,
        prec: u8,
        max_prec: u8,
    ): VecMap<u8, u256> {
        let _W = vec_map::empty<u8, u256>();
        let _B: u256 = 0;
        let i: u8 = 0;
        let _N = (vec_map::size(balances) as u8);
        while (i < _N) {
            vec_map::insert(&mut _W, i, 0u256);
            i = i + 1;
        };

        let j: u8 = 0;
        while (j < _N) {
            let w_j = vec_map::get_mut(&mut _W, &j);
            *w_j = mul(
                *vec_map::get(prices, &j) * *vec_map::get(factors_for_prices, &j),
                *vec_map::get(balances, &j) * *vec_map::get(factor_balances, &j),
                prec, max_prec
            );
            _B = _B + *w_j;
            j = j + 1;
        };

        let k: u8 = 0;
        while (k < _N) {
            let w_k = vec_map::get_mut(&mut _W, &k);
            *w_k = div(*w_k, _B, prec, max_prec);
            k = k + 1;
        };

        _W
    }

    /// Returns a tuple with the values of `B` and `L` (see whitepaper, page 5).
    ///
    /// The result is given in `u256` with `prec` decimal places.
    public(friend) fun compute_B_and_L(
        balances: &VecMap<u8, u256>,
        lp_tokens_issued: &VecMap<u8, u256>,
        prices: &VecMap<u8, u256>,
        factors_for_balances: &VecMap<u8, u256>,
        factor_lpt: u256,
        factors_for_prices: &VecMap<u8, u256>,
        prec: u8,
        max_prec: u8,
    ): (u256, u256) {
        let _B: u256 = 0;
        let _L: u256 = 0;

        let _N = (vec_map::size(balances) as u8);
        let j: u8 = 0;
        while (j < _N) {
            let price_j = *vec_map::get(prices, &j) * *vec_map::get(factors_for_prices, &j);
            _B = _B + mul(price_j, *vec_map::get(balances, &j) * *vec_map::get(factors_for_balances, &j), prec, max_prec);
            _L = _L + mul(price_j, *vec_map::get(lp_tokens_issued, &j) * factor_lpt, prec, max_prec);

            j = j + 1;
        };

        (_B, _L)
    }

    /// Returns a list with the imbalance ratios of the tokens.
    ///
    /// The result is given in `u256` with `prec` decimal places.
    public fun imbalance_ratios(
        balances: &VecMap<u8, u256>,
        lp_tokens_issued: &VecMap<u8, u256>,
        prices: &VecMap<u8, u256>,
        factors_for_balances: &VecMap<u8, u256>,
        factor_lpt: u256,
        factors_for_prices: &VecMap<u8, u256>,
        prec: u8,
        max_prec: u8,
    ): VecMap<u8, u256> {
        let (_B, _L): (u256, u256) = compute_B_and_L(
            balances,
            lp_tokens_issued,
            prices,
            factors_for_balances,
            factor_lpt,
            factors_for_prices,
            prec,
            max_prec,
        );

        let imbs = vec_map::empty();

        let _N = (vec_map::size(balances) as u8);
        let j: u8 = 0;
        while (j < _N) {
            if (*vec_map::get(lp_tokens_issued, &j) != 0) {
                let val = div(
                    mul(*vec_map::get(balances, &j) * *vec_map::get(factors_for_balances, &j), _L, prec, max_prec),
                    mul(_B, *vec_map::get(lp_tokens_issued, &j) * factor_lpt, prec, max_prec),
                    prec, max_prec
                );
                vec_map::insert(&mut imbs, j, val);
            } else {
                vec_map::insert(&mut imbs, j, 0);
            };

            j = j + 1;
        };

        imbs
    }

    /// For a given RAMM, checks if the imbalance ratios after a trade belong to the permissible range,
    /// or if they would be closer to the range than before the trade.
    ///
    /// As is the case with other functions in this module, the parameters
    /// `factor_lpt, prec, max_prec, one, delta`
    /// will be constants defined in the `ramm.move` module, and passed to this function.
    ///
    /// Sui Move does not permit sharing of constants between modules.
    public fun check_imbalance_ratios(
        balances: &VecMap<u8, u256>,
        lp_tokens_issued: &VecMap<u8, u256>,
        prices: &VecMap<u8, u256>,
        i: u8,
        o: u8,
        ai: u256,
        ao: u256,
        pr_fee: u256,
        factors_for_balances: &VecMap<u8, u256>,
        factor_lpt: u256,
        factors_for_prices: &VecMap<u8, u256>,
        prec: u8,
        max_prec: u8,
        one: u256,
        delta: u256
    ): bool {
        let _N = (vec_map::size(balances) as u8);

        let balances_before = vec_map::empty<u8, u256>();
        let balances_after = vec_map::empty<u8, u256>();

        let k = 0;
        while (k < _N) {
            let balance_current = *vec_map::get(balances, &k);
            vec_map::insert(&mut balances_before, k, balance_current);
            vec_map::insert(&mut balances_after, k, balance_current);
            k = k + 1;
        };

        let balance_after_i: &mut u256 = vec_map::get_mut(&mut balances_after, &i);
        *balance_after_i = *balance_after_i + ai - pr_fee;
        let balance_after_o: &mut u256 = vec_map::get_mut(&mut balances_after, &o);
        *balance_after_o = *balance_after_o - ao;

        let imb_ratios_after_trade: VecMap<u8, u256> = imbalance_ratios(
            &balances_after,
            lp_tokens_issued,
            prices,
            factors_for_balances,
            factor_lpt,
            factors_for_prices,
            prec,
            max_prec
        );

        let imb_i_after = *vec_map::get(&imb_ratios_after_trade, &i);
        let imb_o_after = *vec_map::get(&imb_ratios_after_trade, &o);

        let condition1: bool = one - delta <= imb_o_after;
        let condition2: bool = imb_i_after <= one + delta;

        condition1 && condition2
    }

    /// Returns the scaled base fee and leverage parameter for a trade where token `i` goes into the
    /// pool and token `o` goes out of the pool.
    public fun scaled_fee_and_leverage(
        balances: &VecMap<u8, u256>,
        lp_tokens_issued: &VecMap<u8, u256>,
        prices: &VecMap<u8, u256>,
        i: u8,
        o: u8,
        factors_for_balances: &VecMap<u8, u256>,
        factor_lpt: u256,
        factors_for_prices: &VecMap<u8, u256>,
        base_fee: u256,
        base_leverage: u256,
        prec: u8,
        max_prec: u8,
    ): (u256, u256) {
        let imbalances: VecMap<u8, u256> = imbalance_ratios(
            balances,
            lp_tokens_issued,
            prices,
            factors_for_balances,
            factor_lpt,
            factors_for_prices,
            prec,
            max_prec,
        );

        let adjust_i: u256 = adjust(*vec_map::get(&imbalances, &i), prec, max_prec);
        let adjust_o: u256 = adjust(*vec_map::get(&imbalances, &o), prec, max_prec);
        let scaled_fee: u256 = div(mul(adjust_i, base_fee, prec, max_prec), adjust_o, prec, max_prec);
        let scaled_leverage: u256 = div(mul(adjust_o, base_leverage, prec, max_prec), adjust_i, prec, max_prec);

        (scaled_fee, scaled_leverage)
    }

    /// Returns the volatility fee as a `u256` with `prec` decimal places.
    ///
    /// The value will represent a percentage i.e. a value between `0` and `one`, where
    /// `one` is the value `1` with `prec` decimal places.
    public fun compute_volatility_fee(
        previous_price: u256,
        previous_price_timestamp: u64,
        new_price: u256,
        new_price_timestamp: u64,
        // mutable reference to most recently stored volatility parameter for given asset
        current_volatility_param: u256,
        // mutable reference to timestamp of most recently stored volatility parameter for
        // given asset
        current_volatility_timestamp: u64,
        prec: u8,
        max_prec: u8,
        one: u256,
        // maximum trade size, `const` defined in main module
        mu: u256,
        base_fee: u256,
        // length of sliding window in seconds, `const` defined in main module
        tau: u64
    ): u256 {
        // A price change of roughly 0.17% should be enough to trigger a volatility fee.
        let maximum_tolerable_change: u256 =
            mul3(
                2 * one,
                mul3(one - mu, one - mu,one - mu, prec, max_prec),
                base_fee,
                prec,
                max_prec
            );

        // In case the time difference between price data is above our defined
        // threshold of 1 minute (60 seconds)
        if (new_price_timestamp - previous_price_timestamp > tau) {
            0
        }
        // In case the previous and current price data are not too far apart
        else {
            // The previously recorded price being zero means that no volatility indices
            // or timestamps for this asset have yet been calculated, and that this is
            // the first time the RAMM queries this asset's pricing oracle.
            //
            // As such, a sensible result is a volatility fee of simply 0%.
            if (previous_price == 0) { return 0 };

            // Sui Move doesn't support negative numbers, so the below check is required
            // to avoid aborting the program when performing the subtraction
            let price_change: u256;
            if (new_price >= previous_price) {
                price_change = (new_price - previous_price) * one / previous_price;
            } else {
                price_change = (previous_price - new_price) * one / previous_price;
            };

            let price_change_param: u256;
            if (price_change > maximum_tolerable_change) {
                price_change_param = price_change;
            } else {
                price_change_param = 0;
            };

            if (new_price_timestamp - current_volatility_timestamp > tau) {
                price_change_param
            } else {
                if (price_change_param >= current_volatility_param) {
                    price_change_param
                } else {
                    current_volatility_param
                }
            }
        }
    }

    /// Update a given asset's volatility index/timestamp.
    ///
    /// The two mutable references this function is passed will correspond to fields in the
    /// RAMM structure, whose update (or not) hinges on the result of this function.
    ///
    /// The RAMM stores, for every asset, the following pricing data:
    /// 1. the most recently queried oracle price (referred to as "previous"), and
    ///     - its timestamp
    /// 2. the most recently calculated volatility index in the last `TAU` seconds, and
    ///     - a timestamp for this as well
    ///
    /// This function uses an asset's "previous"ly stored price/its timestamp, and the
    /// most recently queried price/timestamp pair, referred to as "new", to decide whether to
    /// update the asset's stored information.
    public fun update_volatility_data(
        previous_price: u256,
        previous_price_timestamp: u64,
        new_price: u256,
        new_price_timestamp: u64,
        // mutable reference to most recently stored volatility parameter for given asset
        stored_volatility_param: &mut u256,
        // mutable reference to timestamp of most recently stored volatility parameter for
        // given asset
        stored_volatility_timestamp: &mut u64,
        // volatility calculated from all the above parameters
        calculated_volatility_fee: u256,
        one: u256,
        // length of sliding window in seconds, `const` defined in main module
        tau: u64
    ) {
        let current_volatility_param: u256 = *stored_volatility_param;
        let current_volatility_timestamp: u64 = *stored_volatility_timestamp;

        let price_change: u256;

        // If the previously recorded price is 0, this is the first volatility index calculation
        // for this asset; it is undefined, so 0 is chosen.
        if (previous_price == 0) {
            price_change = 0;
        } else {
            if (new_price >= previous_price) {
                price_change = (new_price - previous_price) * one / previous_price;
            } else {
                price_change = (previous_price - new_price) * one / previous_price;
            };
        };

        // In case the time difference between price data is below our defined
        // threshold of 1 minute (60 seconds)
        if (new_price_timestamp - previous_price_timestamp <= tau) {
            // if the currently recorded volatility data is older then `TAU`, then
            // unconditionally update it
            if (new_price_timestamp - current_volatility_timestamp > tau) {
                *stored_volatility_param = calculated_volatility_fee;
                *stored_volatility_timestamp = new_price_timestamp;
            } else {
                if (current_volatility_param <= price_change) {
                    *stored_volatility_param = calculated_volatility_fee;
                    *stored_volatility_timestamp = new_price_timestamp;
                } else {};
            }
        }
    }
}