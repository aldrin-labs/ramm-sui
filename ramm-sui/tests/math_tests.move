#[test_only]
module ramm_sui::math_tests {
    use sui::test_utils;
    use sui::vec_map::{Self, VecMap};

    use switchboard::math as sb_math;

    use ramm_sui::ramm;
    use ramm_sui::math as ramm_math;

    const EIncorrectMath: u64 = 0;

    /// Number of decimal places of precision.
    const PRECISION_DECIMAL_PLACES: u8 = 12;
    const MAX_PRECISION_DECIMAL_PLACES: u8 = 25;
    const LP_TOKENS_DECIMAL_PLACES: u8 = 9;

    // FACTOR = 10**(PRECISION_DECIMAL_PLACES-LP_TOKENS_DECIMAL_PLACES)
    const FACTOR_LPT: u256 = 1_000_000_000_000 / 1_000_000_000;

    const ONE: u256 = 1_000_000_000_000;

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

    #[test]
    fun test_mul_1() {
        test_utils::assert_eq(ramm::mul(27 * ONE, 65 * ONE), 1755 * ONE)
    }

    #[test]
    fun test_mul_2() {
        test_utils::assert_eq(ramm::mul(27 * ONE, 65 * ONE / 100), 1755 * ONE / 100)
    }

    #[test]
    fun test_mul_3() {
        test_utils::assert_eq(ramm::mul(27 * ONE, 65), 1755)
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EMulOverflow)]
    fun test_mul_4() {
        ramm::mul(1 + ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES), 2);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EMulOverflow)]
    fun test_mul_5() {
        let max = ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES);
        ramm::mul(1 + max / 2, 2 * ONE);
    }

    #[test]
    fun test_div_1() {
        test_utils::assert_eq(ramm::div(430794 * ONE, 789 * ONE), 546 * ONE)
    }

    #[test]
    fun test_div_2() {
        test_utils::assert_eq(ramm::div(2 * ONE, ONE / 10), 20 * ONE)
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EDividendTooLarge)]
    fun test_div_3() {
        test_utils::assert_eq(ramm::div(1 + ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES), 2), 2)
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EDivOverflow)]
    fun test_div_4() {
        let max = ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES);
        ramm::div(1 + max / 2, 2 * ONE / 10);
    }

    #[test]
    fun test_pow_n_1() {
        test_utils::assert_eq(ramm::pow_n(2 * ONE, 10), 1024 * ONE)
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowNExponentTooLarge)]
    fun test_pow_n_2() {
        ramm::pow_n(2 * ONE, 128);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowNBaseTooLarge)]
    fun test_pow_n_3() {
        ramm::pow_n(1 + ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES), 2);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EMulOverflow)]
    fun test_pow_n_4() {
        ramm::pow_n(ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES - 2), 2);
    }

    #[test]
    /// Check that 0.75 ** 0.5 ~ 0.8660254
    fun test_pow_d_1() {
        test_utils::assert_eq(ramm::pow_d(75 * ONE / 100, 5 * ONE / 10), 866_025_403_793);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowDBaseOutOfBounds)]
    fun test_pow_d_2() {
        ramm::pow_d(151 * ONE / 100, ONE - 1);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowDExpTooLarge)]
    fun test_pow_d_3() {
        ramm::pow_d(75 * ONE / 100, ONE);
    }

    #[test]
    /// Check that 0.75 ** 5.45 ~ 0.2084894
    fun test_power() {
        test_utils::assert_eq(ramm::power(75 * ONE / 100, 545 * ONE / 100), 208_489_354_864);
    }

    // ---------
    // Functions
    // ---------

    fun imbalance_ratios(
        bal_0: u256,
        bal_1: u256,
        bal_2: u256,
        prices_decimal_places: u8,
        balances_decimal_places: u8
    ): VecMap<u8, u256> {
        let balances = vec_map::empty<u8, u256>();
        let lp_tokens_issued = vec_map::empty<u8, u256>();
        let prices = vec_map::empty<u8, u256>();
        let factors_prices = vec_map::empty<u8, u256>();
        let factors_balances = vec_map::empty<u8, u256>();

        vec_map::insert(&mut balances, 0, bal_0);
        vec_map::insert(&mut lp_tokens_issued, 0, 200 * FACTOR_LPT);
        vec_map::insert(&mut prices, 0, 1_800_000_000_000);
        vec_map::insert(&mut factors_prices, 0, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 0, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        vec_map::insert(&mut balances, 1, bal_1);
        vec_map::insert(&mut lp_tokens_issued, 1, 200_000 * FACTOR_LPT);
        vec_map::insert(&mut prices, 1, 1_200_000_000);
        vec_map::insert(&mut factors_prices, 1, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 1, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        vec_map::insert(&mut balances, 2, bal_2);
        vec_map::insert(&mut lp_tokens_issued, 2, 400_000 * FACTOR_LPT);
        vec_map::insert(&mut prices, 2, 1_000_000_000);
        vec_map::insert(&mut factors_prices, 2, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 2, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_prices,
            &factors_balances,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            FACTOR_LPT
        )
    }

    #[test]
    fun imbalance_ratios_1() {
        let imbs = imbalance_ratios(200 * ONE, 200_000 * ONE, 400_000 * ONE, 9, 8);

        test_utils::assert_eq(*vec_map::get(&imbs, &0), ONE);
        test_utils::assert_eq(*vec_map::get(&imbs, &1), ONE);
        test_utils::assert_eq(*vec_map::get(&imbs, &2), ONE);

    }

    #[test]
    fun imbalance_ratios_2() {
        let imbs = imbalance_ratios(209995 * ONE / 1000, 200_000 * ONE, 38_202_653 * ONE / 100, 9, 8);

        test_utils::assert_eq(*vec_map::get(&imbs, &0), 1049956594260);
        test_utils::assert_eq(*vec_map::get(&imbs, &1), 999982470307);
        test_utils::assert_eq(*vec_map::get(&imbs, &2), 955049582980);
    }

    #[test]
    fun imbalance_ratios_3() {
        let imbs = imbalance_ratios(21499 * ONE / 100, 19251134 * ONE / 100, 38_202_653 * ONE / 100, 9, 8);

        test_utils::assert_eq(*vec_map::get(&imbs, &0), 1074926203283);
        test_utils::assert_eq(*vec_map::get(&imbs, &1), 962535391391);
        test_utils::assert_eq(*vec_map::get(&imbs, &2), 955045182209);
    }
}