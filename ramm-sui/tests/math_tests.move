#[test_only]
module ramm_sui::math_tests {
    use switchboard::math as sb_math;

    use ramm_sui::math as ramm_math;

    const EIncorrectMath: u64 = 0;

    #[test]
    fun test_switchboard_decimal() {
        let sbd = sb_math::new(1234567000, 3, false);

        assert!(ramm_math::sbd_to_u256(sbd) == 1234567u256, EIncorrectMath);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::ENegativeSbD)]
    fun test_switchboard_decimal_fail() {
        let sbd = sb_math::new(1234567000, 3, true);
        let _ = ramm_math::sbd_to_u256(sbd);
    }
}