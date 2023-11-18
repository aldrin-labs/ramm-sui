module ramm_sui::math {
    use switchboard::math as sb_math;

    friend ramm_sui::ramm;
    friend ramm_sui::math_tests;

    const ENegativeSbD: u64 = 0;

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
}