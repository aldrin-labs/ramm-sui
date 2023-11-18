#[test_only]
module ramm_sui::math_tests {
    //use std::debug;

    use sui::test_utils;
    use sui::vec_map::{Self, VecMap};

    use switchboard::math as sb_math;

    use ramm_sui::ramm;
    use ramm_sui::test_util;
    use ramm_sui::math as ramm_math;

    const EIncorrectMath: u64 = 0;
    const EInvalidImbalanceRatios: u64 = 1;

    /// Number of decimal places of precision.
    const PRECISION_DECIMAL_PLACES: u8 = 12;
    const MAX_PRECISION_DECIMAL_PLACES: u8 = 25;
    const LP_TOKENS_DECIMAL_PLACES: u8 = 9;

    // FACTOR = 10**(PRECISION_DECIMAL_PLACES-LP_TOKENS_DECIMAL_PLACES)
    const FACTOR_LPT: u256 = 1_000_000_000_000 / 1_000_000_000;

    const ONE: u256 = 1_000_000_000_000;

    /// Miguel's note:
    /// Maximum permitted deviation of the imbalance ratios from 1.0. 2 decimal places
    /// are considered.
    ///
    /// Hence DELTA=25 is interpreted as 0.25
    const DELTA: u256 = 25 * 1_000_000_000_000 / 100; // DELTA = _DELTA * 10**(PRECISION_DECIMAL_PLACES-2)

    const BASE_FEE: u256 = 10 * 1_000_000_000_000 / 10000; // _BASE_FEE * 10**(PRECISION_DECIMAL_PLACES-4)
    const PROTOCOL_FEE: u256 = 50 * 1_000_000_000_000 / 100;

    // BASE_LEVERAGE = _BASE_LEVERAGE * ONE
    const BASE_LEVERAGE: u256 = 100 * 1_000_000_000_000;

    #[test]
    fun test_switchboard_decimal() {
        let sbd = sb_math::new(1234567000, 9, false);
        let (price, factor_for_price) = ramm_math::sbd_to_price_info(sbd, PRECISION_DECIMAL_PLACES);

        test_utils::assert_eq(price, 1234567000u256);
        test_utils::assert_eq(factor_for_price, 1000u256);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::ENegativeSbD)]
    fun test_switchboard_decimal_fail() {
        let sbd = sb_math::new(1234567000, 3, true);
        let (_, _) = ramm_math::sbd_to_price_info(sbd, PRECISION_DECIMAL_PLACES);
    }

    #[test]
    /// Check that `27 * 65 == 1755`, with `PRECISION_DECIMAL_PLACES`.
    fun test_mul_1() {
        test_utils::assert_eq(ramm::mul(27 * ONE, 65 * ONE), 1755 * ONE)
    }

    #[test]
    /// Check that `27 * 0.65 == 17.55`, with `PRECISION_DECIMAL_PLACES`.
    fun test_mul_2() {
        test_utils::assert_eq(ramm::mul(27 * ONE, 65 * ONE / 100), 1755 * ONE / 100)
    }

    #[test]
    /// Check that `26 * (65 * 10e-12) == 1755 * 10e-12`, with `PRECISION_DECIMAL_PLACES`.
    fun test_mul_3() {
        test_utils::assert_eq(ramm::mul(27 * ONE, 65), 1755)
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EMulOverflow)]
    /// Check that `mul` aborts if a multiplicand exceeds `10^MAX_PRECISION_DECIMAL_PLACES`.
    fun test_mul_4() {
        ramm::mul(1 + ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES), 2);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EMulOverflow)]
    /// Check that `mul` aborts if the result exceeds `10^MAX_PRECISION_DECIMAL_PLACES`.
    fun test_mul_5() {
        let max = ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES);
        ramm::mul(1 + max / 2, 2 * ONE);
    }

    #[test]
    /// Check that `430794 / 789 == 546` (exactly), with `PRECISION_DECIMAL_PLACES`.
    fun test_div_1() {
        test_utils::assert_eq(ramm::div(430794 * ONE, 789 * ONE), 546 * ONE)
    }

    #[test]
    /// Check that `2 / 0.1 == 20` (exactly), with `PRECISION_DECIMAL_PLACES`.
    fun test_div_2() {
        test_utils::assert_eq(ramm::div(2 * ONE, ONE / 10), 20 * ONE)
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EDividendTooLarge)]
    /// Check that `div` aborts when the dividend exceeds `10^MAX_PRECISION_DECIMAL_PLACES`.
    fun test_div_3() {
        test_utils::assert_eq(ramm::div(1 + ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES), 2), 2)
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EDivOverflow)]
    /// Check that `div` aborts when, although the dividend does not exceed `10^MAX_PRECISION_DECIMAL_PLACES`,
    /// the result would.
    fun test_div_4() {
        let max = ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES);
        ramm::div(1 + max / 2, 2 * ONE / 10);
    }

    #[test]
    /// Check that `2^10 == 1024`, with `PRECISION_DECIMAL_PLACES`.
    fun test_pow_n_1() {
        test_utils::assert_eq(ramm::pow_n(2 * ONE, 10), 1024 * ONE)
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowNExponentTooLarge)]
    /// Assert that using `pow_n` with an overly large exponent aborts.
    fun test_pow_n_2() {
        ramm::pow_n(2 * ONE, 128);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowNBaseTooLarge)]
    /// Assert that using `pow_n` with an overly large base aborts.
    fun test_pow_n_3() {
        ramm::pow_n(1 + ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES), 2);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EMulOverflow)]
    /// Assert that an internal `mul` overflow in `pow_n` will lead to an abort.
    fun test_pow_n_4() {
        ramm::pow_n(ramm_math::pow(10, MAX_PRECISION_DECIMAL_PLACES - 2), 2);
    }

    #[test]
    /// Check that `0.75 ** 0.5 ~ 0.8660254`, with `PRECISION_DECIMAL_PLACES`.
    fun test_pow_d_1() {
        test_utils::assert_eq(ramm::pow_d(75 * ONE / 100, 5 * ONE / 10), 866_025_403_793);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowDBaseOutOfBounds)]
    /// Check that calling `pow_d` with a base lower than `0.67` will abort.
    fun test_pow_d_2() {
        ramm::pow_d(64 * ONE / 100, ONE - 1);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowDBaseOutOfBounds)]
    /// Check that calling `pow_d` with a base higher than `1.5` will abort.
    fun test_pow_d_3() {
        ramm::pow_d(151 * ONE / 100, ONE - 1);
    }

    #[test]
    #[expected_failure(abort_code = ramm_math::EPowDExpTooLarge)]
    /// Check that calling `pow_d` with an exponent not in `[0, 1[` will fail.
    fun test_pow_d_4() {
        ramm::pow_d(75 * ONE / 100, ONE);
    }

    #[test]
    /// Check that `0.75 ** 5.45 ~ 0.2084894`
    fun test_power() {
        test_utils::assert_eq(ramm::power(75 * ONE / 100, 545 * ONE / 100), 208_489_354_864);
    }

    // ---------
    // Functions
    // ---------

    /*
    Some tests below rely on an example from the whitepaper, with a 3-asset RAMM with
    ETH (0), MATIC (1) and USDT (2) - see page 12.

    The initial prices of the assets, in terms of USDT, are:
    * 0: 1,800.00 ETH/USDT
    * 1: 1.20 MATIC/USDT
    * 2: 1.00 USDT/USDT

    All three assets are assumed to have 8 places of precision, and LP tokens will have 9.
    */ 

    /// Helper to check RAMM weight calculation using the whitepaper's example, with a
    /// 3-asset RAMM with ETH, MATIC, USDT.
    ///
    /// The exact results do not matter, the tests below using this function are just checks
    /// to alert developers of any change to the mathematical functions' behavior.
    fun weights(
        bal_0: u256,
        bal_1: u256,
        bal_2: u256,
        prices_decimal_places: u8,
        balances_decimal_places: u8
    ): VecMap<u8, u256> {
        let balances = vec_map::empty<u8, u256>();
        let prices = vec_map::empty<u8, u256>();
        let factors_prices = vec_map::empty<u8, u256>();
        let factors_balances = vec_map::empty<u8, u256>();

        vec_map::insert(&mut balances, 0, bal_0);
        vec_map::insert(&mut prices, 0, 1_800_000_000_000);
        vec_map::insert(&mut factors_prices, 0, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 0, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        vec_map::insert(&mut balances, 1, bal_1);
        vec_map::insert(&mut prices, 1, 1_200_000_000);
        vec_map::insert(&mut factors_prices, 1, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 1, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        vec_map::insert(&mut balances, 2, bal_2);
        vec_map::insert(&mut prices, 2, 1_000_000_000);
        vec_map::insert(&mut factors_prices, 2, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 2, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        ramm_math::weights(
            &balances,
            &prices,
            &factors_prices,
            &factors_balances,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        )
    }

    #[test]
    /// Weight calculation before any trade is done, after every asset has liquidity deposited in.
    fun weights_1() {
        let ws = weights(200 * ONE, 200_000 * ONE, 400_000 * ONE, 9, 8);

        test_utils::assert_eq(*vec_map::get(&ws, &0), 36 * ONE / 100);
        test_utils::assert_eq(*vec_map::get(&ws, &1), 24 * ONE / 100);
        test_utils::assert_eq(*vec_map::get(&ws, &2), 40 * ONE / 100);
    }

    #[test]
    /// Weight calculation after the first trade, ETH/USDT
    fun weights_2() {
        let ws = weights(209995 * ONE / 1000, 200_000 * ONE, 38_202_653 * ONE / 100, 9, 8);

        test_utils::assert_eq(*vec_map::get(&ws, &0), 377984373933);
        test_utils::assert_eq(*vec_map::get(&ws, &1), 239995792873);
        test_utils::assert_eq(*vec_map::get(&ws, &2), 382019833192);
    }

    #[test]
    /// Weight calculation after the second trade, ETH/MATIC
    fun weights_3() {
        let ws = weights(21499 * ONE / 100, 19251134 * ONE / 100, 38_202_653 * ONE / 100, 9, 8);

        test_utils::assert_eq(*vec_map::get(&ws, &0), 386973433182);
        test_utils::assert_eq(*vec_map::get(&ws, &1), 231008493933);
        test_utils::assert_eq(*vec_map::get(&ws, &2), 382018072883);
    }

    /// Helper to check calculation of RAMM imbalance ratios using the whitepaper's example of
    /// a 3-asset RAMM with ETH, MATIC, USDT.
    ///
    /// The exact results do not matter, the tests below using this function are just checks
    /// to alert developers of any change to the mathematical functions' behavior.
    fun imbalance_ratios(
        bal_0: u256,
        bal_1: u256,
        bal_2: u256,
        prices_decimal_places: u8,
        balances_decimal_places: u8
    ): (VecMap<u8, u256>, VecMap<u8, u256>, VecMap<u8, u256>, VecMap<u8, u256>, VecMap<u8, u256>,) {
        let balances = vec_map::empty<u8, u256>();
        let lp_tokens_issued = vec_map::empty<u8, u256>();
        let prices = vec_map::empty<u8, u256>();
        let factors_prices = vec_map::empty<u8, u256>();
        let factors_balances = vec_map::empty<u8, u256>();

        vec_map::insert(&mut balances, 0, bal_0);
        vec_map::insert(&mut lp_tokens_issued, 0, 200 * test_util::eth_factor());
        vec_map::insert(&mut prices, 0, 1_800_000_000_000);
        vec_map::insert(&mut factors_prices, 0, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 0, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        vec_map::insert(&mut balances, 1, bal_1);
        vec_map::insert(&mut lp_tokens_issued, 1, 200_000 * test_util::matic_factor());
        vec_map::insert(&mut prices, 1, 1_200_000_000);
        vec_map::insert(&mut factors_prices, 1, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 1, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        vec_map::insert(&mut balances, 2, bal_2);
        vec_map::insert(&mut lp_tokens_issued, 2, 400_000 * test_util::usdt_factor());
        vec_map::insert(&mut prices, 2, 1_000_000_000);
        vec_map::insert(&mut factors_prices, 2, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 2, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - balances_decimal_places));

        (balances, lp_tokens_issued, prices, factors_prices, factors_balances)
    }

    #[test]
    /// Imbalance ratio calculation before any trade is done, after every asset has liquidity deposited in.
    ///
    /// This test also verifies the result of `check_imbalance_ratios` and `scaled_fee_and_leverage` before
    /// any trade is done.
    fun imbalance_ratios_1() {
        let (balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(
                200 * test_util::eth_factor(),
                200_000 * test_util::matic_factor(),
                400_000 * test_util::usdt_factor(),
                9,
                8
        );

        let imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        test_utils::assert_eq(*vec_map::get(&imbs, &0), ONE);
        test_utils::assert_eq(*vec_map::get(&imbs, &1), ONE);
        test_utils::assert_eq(*vec_map::get(&imbs, &2), ONE);

        // These indices, and the scaled fee and leverage they are used to calculate,
        // refer to the *next* trade that is going to happen;
        // In the example, it's ETH/USDT
        let i = 0;
        let o = 2;
        let (scaled_fee, scaled_leverage) = ramm_math::scaled_fee_and_leverage(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            BASE_FEE,
            BASE_LEVERAGE,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        test_utils::assert_eq(BASE_LEVERAGE, scaled_leverage);
        test_utils::assert_eq(BASE_FEE, scaled_fee);
    }

    #[test]
    /// Imbalance ratio calculation after the first trade, ETH/USDT.
    ///
    /// Furthermore, verify that `check_imbalance_rations` would permit the trade.
    /// This test also verifies the result of  `scaled_fee_and_leverage` after the first trade is
    /// done, or equivalently, the leverage and fee values that'll be used for the second trade.
    fun imbalance_ratios_2() {
        let i: u8 = 0;
        let o: u8 = 2;
        let prev_eth = 200 * test_util::eth_factor();
        let new_eth = 209995 * test_util::eth_factor() / 1000;
        let ai: u256 = new_eth - prev_eth;
        let old_usdt = 400_000 * test_util::usdt_factor();
        let new_usdt = 38_202_653 * test_util::usdt_factor() / 100;
        let ao: u256 = old_usdt - new_usdt;

        let (balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(new_eth, 200_000 * test_util::matic_factor(), new_usdt, 9, 8);

        let imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        test_utils::assert_eq(*vec_map::get(&imbs, &0), 1049956594260);
        test_utils::assert_eq(*vec_map::get(&imbs, &1), 999982470307);
        test_utils::assert_eq(*vec_map::get(&imbs, &2), 955049582980);

        // These indices, and the scaled fee and leverage they are used to calculate,
        // refer to the *next* trade that is going to happen;
        // In the example, it's ETH/MATIC
        let next_i = i;
        let next_o = 1;
        let (scaled_fee, scaled_leverage) = ramm_math::scaled_fee_and_leverage(
            &balances,
            &lp_tokens_issued,
            &prices,
            next_i,
            next_o,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            BASE_FEE,
            BASE_LEVERAGE,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        // Leverage for the example's first trade should be about 86.384
        test_utils::assert_eq(86389930415662, scaled_leverage);
        // The fee for the example's first trade should be roughly 0.116%
        test_utils::assert_eq(1157542314, scaled_fee);

        let factor_i = *vec_map::get(&factors_balances, &i);
        let pr_fee: u256 = ramm_math::mul3(
                PROTOCOL_FEE,
                scaled_fee,
                ai * factor_i,
                PRECISION_DECIMAL_PLACES,
                MAX_PRECISION_DECIMAL_PLACES
            ) / factor_i;
        let imbalance_ratios_check = ramm_math::check_imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        assert!(imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    #[test]
    /// Imbalance ratio calculation after the second trade, ETH/MATIC.
    ///
    /// Furthermore, verify that `check_imbalance_rations` would permit the trade.
    fun imbalance_ratios_3() {
        let i: u8 = 0;
        let o: u8 = 1;
        let prev_eth = 209995 * test_util::eth_factor() / 1000;
        let new_eth = 21499 * test_util::eth_factor() / 100;
        let ai: u256 = new_eth - prev_eth;
        let old_matic = 200_000 * test_util::matic_factor();
        let new_matic = 19251134 * test_util::matic_factor() / 100;
        let ao: u256 = old_matic - new_matic;

        let (balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(new_eth, new_matic, 38_202_653 * test_util::usdt_factor() / 100, 9, 8);

        let imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        let (scaled_fee, scaled_leverage) = ramm_math::scaled_fee_and_leverage(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            BASE_FEE,
            BASE_LEVERAGE,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );


        // Leverage for a hypothetical third trade should be roughly 71.798
        test_utils::assert_eq(71798301729756, scaled_leverage);
        // The corresponding fee would be roughly 0.139%
        test_utils::assert_eq(1392790602, scaled_fee);

        let factor_i = *vec_map::get(&factors_balances, &i);
        let pr_fee: u256 = ramm_math::mul3(
                PROTOCOL_FEE,
                scaled_fee,
                ai * factor_i,
                PRECISION_DECIMAL_PLACES,
                MAX_PRECISION_DECIMAL_PLACES
            ) / factor_i;
        let imbalance_ratios_check = ramm_math::check_imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        test_utils::assert_eq(*vec_map::get(&imbs, &0), 1074926203283);
        test_utils::assert_eq(*vec_map::get(&imbs, &1), 962535391391);
        test_utils::assert_eq(*vec_map::get(&imbs, &2), 955045182209);

        assert!(imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    #[test]
    /// Imbalance ratio failure check.
    ///
    /// Uses the ETH/MATIC/USDT RAMM from the example, with its state modified so that
    /// an excess of ETH has been sold to the pool for outgoing USDT.
    ///
    /// Since the imbalance ratios for ETH and USDT are outside of the permissible interval
    /// `[ONE - DELTA, ONE + DELTA]`, any trades that will further distance the ratios from
    /// the interval must be disallowed by `check_imbalance_ratios`.
    fun imbalance_ratios_fail() {
        let i: u8 = 0;
        let o: u8 = 2;
        let prev_eth = 260 * test_util::eth_factor();
        let new_eth = 270 * test_util::eth_factor();
        let ai: u256 = new_eth - prev_eth;
        let old_usdt = 29_215_918 * test_util::usdt_factor() / 100;
        let new_usdt = 27_418_571 * test_util::usdt_factor() / 100;
        let ao: u256 = old_usdt - new_usdt;

        let (balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(new_eth, 200_000 * test_util::matic_factor(), new_usdt, 9, 8);

        let imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        assert!(*vec_map::get(&imbs, &0) > ONE + DELTA, EInvalidImbalanceRatios);
        let matic_imb_rat = *vec_map::get(&imbs, &1);
        assert!(ONE - DELTA <= matic_imb_rat && matic_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);
        assert!(*vec_map::get(&imbs, &2) < ONE - DELTA, EInvalidImbalanceRatios);

        let (scaled_fee, _) = ramm_math::scaled_fee_and_leverage(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            BASE_FEE,
            BASE_LEVERAGE,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        let factor_i = *vec_map::get(&factors_balances, &i);
        let pr_fee: u256 = ramm_math::mul3(
                PROTOCOL_FEE,
                scaled_fee,
                ai * factor_i,
                PRECISION_DECIMAL_PLACES,
                MAX_PRECISION_DECIMAL_PLACES
            ) / factor_i;
        let imbalance_ratios_check = ramm_math::check_imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        // Assert that the imbalance ratio check 
        assert!(!imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    #[test]
    /// Imbalance ratio check.
    ///
    /// Uses the ETH/MATIC/USDT RAMM from the example, with its state modified so that
    /// an excess of ETH has been sold to the pool for outgoing USDT.
    ///
    /// Since the imbalance ratios for ETH and USDT are outside of the permissible interval
    /// `[ONE - DELTA, ONE + DELTA]`, any trades that will further distance the ratios from
    /// the interval must be disallowed by `check_imbalance_ratios`.
    ///
    /// However, a trade that will bring these ratios closer, even if not back inside the
    /// interval, is permissible.
    fun imbalance_ratios_pass() {
        let i: u8 = 2;
        let o: u8 = 0;
        let old_eth = 260 * test_util::eth_factor();
        let new_eth = 252 * test_util::eth_factor();
        let ao: u256 = old_eth - new_eth;
        let old_usdt = 27_418_571 * test_util::usdt_factor() / 100;
        let new_usdt = 288_564_486 * test_util::usdt_factor() / 1000;
        let ai: u256 = new_usdt - old_usdt;

        let (balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(new_eth, 200_000 * test_util::matic_factor(), new_usdt, 9, 8);

        let imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        assert!(*vec_map::get(&imbs, &0) > ONE + DELTA, EInvalidImbalanceRatios);
        let matic_imb_rat = *vec_map::get(&imbs, &1);
        assert!(ONE - DELTA <= matic_imb_rat && matic_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);
        assert!(*vec_map::get(&imbs, &2) < ONE - DELTA, EInvalidImbalanceRatios);

        let (scaled_fee, _) = ramm_math::scaled_fee_and_leverage(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            BASE_FEE,
            BASE_LEVERAGE,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        let factor_i = *vec_map::get(&factors_balances, &i);
        let pr_fee: u256 = ramm_math::mul3(
                PROTOCOL_FEE,
                scaled_fee,
                ai * factor_i,
                PRECISION_DECIMAL_PLACES,
                MAX_PRECISION_DECIMAL_PLACES
            ) / factor_i;
         let imbalance_ratios_check = ramm_math::check_imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &factors_balances,
            FACTOR_LPT,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        // Assert that the imbalance ratio check 
        assert!(imbalance_ratios_check, EInvalidImbalanceRatios);
    }
}