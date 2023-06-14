module ramm_sui::math {
    use sui::vec_map::{Self, VecMap};

    use switchboard::math as sb_math;

    friend ramm_sui::ramm;
    friend ramm_sui::math_tests;

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

    /// Raise a `base: u256` to the power of a `u8` `exp`onent.
    ///
    /// # Aborts
    ///
    /// If the calculation overflows.
    fun pow_u256(base: u256, exp: u8): u256 {
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

    /// Convert an `switchboard::aggregator::SwitchboardDecimal` to a `u256`.
    ///
    /// # Aborts
    ///
    /// If the `SwitchboardDecimal`'s `neg`ative flag was set to `true`.
    public(friend) fun sbd_to_u256(sbd: sb_math::SwitchboardDecimal): u256 {
        let (value, scaling_factor, neg) = sb_math::unpack(sbd);
        assert!(!neg, ENegativeSbD);

        (value as u256) / pow_u256(10, scaling_factor)
    }

    /// Raise a `base: u256` to the power of a `u8` `exp`onent.
    ///
    /// # Aborts
    ///
    /// If the calculation overflows.
    public(friend) fun pow(base: u256, exp: u8): u256 {
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

    public(friend) fun mul(x: u256, y: u256, prec: u8, max_prec: u8): u256 {
        let max = pow(10u256, max_prec);
        assert!(x <= max && y <= max, EMulOverflow);
        let result = x * y / pow(10u256, prec);
        assert!(result <= max, EMulOverflow);

        result
    }

    public(friend) fun mul3(x: u256, y: u256, z: u256, prec: u8, max_prec: u8): u256 {
        mul(x, mul(y, z, prec, max_prec), prec, max_prec)
    }

    public(friend) fun div(x: u256, y: u256, prec: u8, max_prec: u8): u256 {
        let max = pow(10u256, max_prec);
        assert!(x <= max, EDividendTooLarge);
        let result = x * pow(10u256, prec) / y;
        assert!(result <= max, EDivOverflow);

        result
    }

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
    /// Computes x^a, where a is a real number that belongs to the interval [0,128).
    /// Both a and x have to be given with PRECISION_DECIMAL_PLACES decimal places.
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

    /// ---------
    /// Functions
    /// ---------

    public(friend) fun weights(
        balances: &VecMap<u8, u256>,
        prices: &VecMap<u8, u256>,
        factor_balances: &VecMap<u8, u256>,
        factors_prices: &VecMap<u8, u256>,
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
                *vec_map::get(prices, &j) * *vec_map::get(factors_prices, &j),
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

    public(friend) fun compute_B_and_L(
        balances: &VecMap<u8, u256>,
        lp_tokens_issued: &VecMap<u8, u256>,
        prices: &VecMap<u8, u256>,
        factors_prices: &VecMap<u8, u256>,
        factors_balances: &VecMap<u8, u256>,
        prec: u8,
        max_prec: u8,
        factor_lpt: u256
    ): (u256, u256) {
        let _B: u256 = 0;
        let _L: u256 = 0;

        let _N = (vec_map::size(balances) as u8);
        let j: u8 = 0;
        while (j < _N) {
            let price_j = *vec_map::get(prices, &j) * *vec_map::get(factors_prices, &j);
            _B = _B + mul(price_j, *vec_map::get(balances, &j) * *vec_map::get(factors_balances, &j), prec, max_prec);
            _L = _L + mul(price_j, *vec_map::get(lp_tokens_issued, &j) * factor_lpt, prec, max_prec);

            j = j + 1;
        };

        (_B, _L)
    }

    public(friend) fun imbalance_ratios(
        balances: &VecMap<u8, u256>,
        lp_tokens_issued: &VecMap<u8, u256>,
        prices: &VecMap<u8, u256>,
        factors_prices: &VecMap<u8, u256>,
        factors_balances: &VecMap<u8, u256>,
        prec: u8,
        max_prec: u8,
        factor_lpt: u256
    ): VecMap<u8, u256> {
        let (_B, _L): (u256, u256) = compute_B_and_L(
            balances,
            lp_tokens_issued,
            prices,
            factors_prices,
            factors_balances,
            prec,
            max_prec,
            factor_lpt
        );

        let imbs = vec_map::empty();

        let _N = (vec_map::size(balances) as u8);
        let j: u8 = 0;
        while (j < _N) {
            if (*vec_map::get(lp_tokens_issued, &j) != 0) {
                let val = div(
                    mul(*vec_map::get(balances, &j) * *vec_map::get(factors_balances, &j), _L, prec, max_prec),
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

}