#[test_only]
module ramm_sui::math_tests {
    //use std::debug;

    use sui::test_utils;
    use sui::vec_map::{Self, VecMap};

    use switchboard_std::math as sb_math;

    use ramm_sui::oracles;
    use ramm_sui::ramm;
    use ramm_sui::test_util;
    use ramm_sui::math as ramm_math;

    const EInvalidImbalanceRatios: u64 = 0;

    /// Number of decimal places of precision.
    const PRECISION_DECIMAL_PLACES: u8 = 12;
    const MAX_PRECISION_DECIMAL_PLACES: u8 = 25;
    const ONE: u256 = 1_000_000_000_000;

    /// Miguel's note:
    ///
    /// * Maximum permitted deviation of the imbalance ratios from 1.0.
    /// * 2 decimal places are considered.
    ///
    /// Hence, DELTA=25 is interpreted as 0.25
    const DELTA: u256 = 25 * 1_000_000_000_000 / 100; // DELTA = _DELTA * 10**(PRECISION_DECIMAL_PLACES-2)
    /// Value mu \in ]0, 1[ that dictates the maximum size a trade can have.
    /// Here, mu = 0.05, meaning trades cannot use more than 5% of the RAMM's balances at once.
    const MU: u256 = 5 * 1_000_000_000_000 / 100; // _MU * 10**(PRECISION_DECIMAL_PLACES-2)
    /// Value, in seconds, of the maximum permitted difference between oracle price information
    /// that will trigger a volatility parameter update.
    const TAU: u64 = 300;

    const BASE_FEE: u256 = 10 * 1_000_000_000_000 / 10000; // _BASE_FEE * 10**(PRECISION_DECIMAL_PLACES-4)
    const PROTOCOL_FEE: u256 = 30 * 1_000_000_000_000 / 100;
    const BASE_LEVERAGE: u256 = 100 * 1_000_000_000_000; // BASE_LEVERAGE = _BASE_LEVERAGE * ONE


    #[test]
    fun test_switchboard_decimal() {
        let sbd = sb_math::new(1234567000, 9, false);
        let (price, factor_for_price) = oracles::sbd_to_price_info(sbd, PRECISION_DECIMAL_PLACES);

        test_utils::assert_eq(price, 1234567000u256);
        test_utils::assert_eq(factor_for_price, 1000u256);
    }

    #[test]
    #[expected_failure(abort_code = oracles::ENegativeSbD)]
    /// Check that an oracle's price being negative will raise an abort.
    fun test_switchboard_negative_decimal_fail() {
        let sbd = sb_math::new(1234567000, 3, true);
        let (_, _) = oracles::sbd_to_price_info(sbd, PRECISION_DECIMAL_PLACES);
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
        let mut balances = vec_map::empty<u8, u256>();
        let mut prices = vec_map::empty<u8, u256>();
        let mut factors_prices = vec_map::empty<u8, u256>();
        let mut factors_balances = vec_map::empty<u8, u256>();

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

    /// Helper to populate maps with the balances and prices used in the whitepaper's example of
    /// a 3-asset RAMM with ETH, MATIC, USDT.
    ///
    /// The `bal_n` parameters are the asset balances at the time of the imbalance ratio
    /// calculation.
    ///
    /// In this example, all of the assets' prices have the same decimal places, and all of the
    /// balances too.
    fun imbalance_ratios(
        bal_0: u256,
        bal_1: u256,
        bal_2: u256,
        prices_decimal_places: u8,
    ): (VecMap<u8, u256>, VecMap<u8, u256>, VecMap<u8, u256>, VecMap<u8, u256>, VecMap<u8, u256>,) {
        let mut balances = vec_map::empty<u8, u256>();
        let mut lp_tokens_issued = vec_map::empty<u8, u256>();
        let mut prices = vec_map::empty<u8, u256>();
        let mut factors_prices = vec_map::empty<u8, u256>();
        let mut factors_balances = vec_map::empty<u8, u256>();

        vec_map::insert(&mut balances, 0, bal_0);
        vec_map::insert(&mut lp_tokens_issued, 0, 200 * test_util::eth_factor());
        vec_map::insert(&mut prices, 0, 1_800_000_000_000);
        vec_map::insert(&mut factors_prices, 0, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 0, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES) / test_util::eth_factor());

        vec_map::insert(&mut balances, 1, bal_1);
        vec_map::insert(&mut lp_tokens_issued, 1, 200_000 * test_util::matic_factor());
        vec_map::insert(&mut prices, 1, 1_200_000_000);
        vec_map::insert(&mut factors_prices, 1, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 1, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES) / test_util::matic_factor());

        vec_map::insert(&mut balances, 2, bal_2);
        vec_map::insert(&mut lp_tokens_issued, 2, 400_000 * test_util::usdt_factor());
        vec_map::insert(&mut prices, 2, 1_000_000_000);
        vec_map::insert(&mut factors_prices, 2, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES - prices_decimal_places));
        vec_map::insert(&mut factors_balances, 2, ramm_math::pow(10u256, PRECISION_DECIMAL_PLACES) / test_util::usdt_factor());

        (balances, lp_tokens_issued, prices, factors_prices, factors_balances)
    }

    #[test]
    /// Imbalance ratio calculation before any trade is done, after every asset has liquidity deposited in.
    /// This test is based on an example from the original whitepaper, with an ETH/MATIC/USDT pool.
    ///
    /// This test also verifies the result of `scaled_fee_and_leverage` before any trade is done.
    fun imbalance_ratios_pre_trade_checks() {
        let (balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(
                200 * test_util::eth_factor(),
                200_000 * test_util::matic_factor(),
                400_000 * test_util::usdt_factor(),
                9,
        );

        let imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
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
    fun imbalance_ratios_example_first_trade() {
        let i: u8 = 0;
        let o: u8 = 2;
        let prev_eth = 200 * test_util::eth_factor();
        let new_eth = 209995 * test_util::eth_factor() / 1000;
        let ai: u256 = new_eth - prev_eth;
        let old_usdt = 400_000 * test_util::usdt_factor();
        let new_usdt = 38_202_653 * test_util::usdt_factor() / 100;
        let ao: u256 = old_usdt - new_usdt;

        let (balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(new_eth, 200_000 * test_util::matic_factor(), new_usdt, 9);

        let imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
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
    /// Furthermore, verify that `check_imbalance_ratios` would permit the trade.
    fun imbalance_ratios_example_second_trade() {
        let i: u8 = 0;
        let o: u8 = 1;
        let prev_eth = 209995 * test_util::eth_factor() / 1000;
        let new_eth = 21499 * test_util::eth_factor() / 100;
        let ai: u256 = new_eth - prev_eth;
        let old_matic = 200_000 * test_util::matic_factor();
        let new_matic = 19251134 * test_util::matic_factor() / 100;
        let ao: u256 = old_matic - new_matic;

        let (balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(new_eth, new_matic, 38_202_653 * test_util::usdt_factor() / 100, 9);

        let before_imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
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
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        test_utils::assert_eq(*vec_map::get(&before_imbs, &0), 1074926203283);
        test_utils::assert_eq(*vec_map::get(&before_imbs, &1), 962535391391);
        test_utils::assert_eq(*vec_map::get(&before_imbs, &2), 955045182209);

        assert!(imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    // ----------------------
    // Imbalance ratio checks
    // ----------------------

    /*

    IMPORTANT NOTE

    The tests below check whether `check_imbalance_ratios` behaves correctly in all of the
    situations below:

    1. The relevant assets' imbalance begin within bounds
        1.1 The trade keeps them within bounds (pass)
        1.2 The trade pushes them out of bounds (fail)
    2. The relevant assets' ratios begin out of bounds
        2.1 The trade pushes them into bounds (pass)
        2.2 The trade would keep them out of bounds
            2.2.1 The ratios would travel out-of-bounds to the opposite end of the spectrum
                  e.g. excess of an asset becomes scarcity due to trade's extreme volume (fail)
            2.2.2 The ratios would stay the same, or become even more skewed in the original
                  imbalance's direction (fail)

    The tests themselves simulate a 3-asset RAMM pool with ETH/MATIC/USDT, with prices in USDT
    terms of roughly 1800/1.2/1.
    The exact values are not very relevant - what matters in the tests is that a certain asset
    leaves the pool, and another is put into it, loosely according to the prices above.

    They begin by:
        * setting the `u8` indexes for the assets, `i` for inbound, `o` for outbound
        * setting the corresponding previous/new amounts, depending on the size of the trade
          needed to achieve the desired effect in the imbalance ratios
        * build the `VecMap`s required to calculate pre/post trade imbalance ratios, via
          the test-only helper `imbalance_ratios`
        * calculate pre/post trade imb ratios, and then perform the necessary `assert`s
        * calculate the hypothetical trade's estimated fee, and then use it to run
          `check_imbalance_ratios`, verifying that the result is a consequence of the
          situation's premise
    */

    #[test]
    /// Imbalance ratio calculation after the first trade, ETH/USDT.
    ///
    /// For this test, it is first established that the premise of situation 1.1 applies, and then
    /// it is verified that `check_imbalance_ratios` would permit the trade, as expected.
    fun check_imbalance_ratios_case_1_1() {
        let i: u8 = 0;
        let o: u8 = 2;
        let prev_eth = 200 * test_util::eth_factor();
        let new_eth = 209995 * test_util::eth_factor() / 1000;
        let ai: u256 = new_eth - prev_eth;
        let prev_usdt = 400_000 * test_util::usdt_factor();
        let new_usdt = 38_202_653 * test_util::usdt_factor() / 100;
        let ao: u256 = prev_usdt - new_usdt;

        let (prev_balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(prev_eth, 200_000 * test_util::matic_factor(), prev_usdt, 9);

        let before_imbs = ramm_math::imbalance_ratios(
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        let mut new_balances: VecMap<u8, u256> = copy prev_balances;
        vec_map::remove(&mut new_balances, &i);
        vec_map::insert(&mut new_balances, i, new_eth);
        vec_map::remove(&mut new_balances, &o);
        vec_map::insert(&mut new_balances, o, new_usdt);

        let after_imbs = ramm_math::imbalance_ratios(
            &new_balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        // Ensure MATIC's imbalance ratio is within bounds at all times, as the trade did not
        // concern it.
        let matic_before_imb_rat = *vec_map::get(&before_imbs, &1);
        let matic_after_imb_rat = *vec_map::get(&after_imbs, &1);
        assert!(ONE - DELTA <= matic_before_imb_rat && matic_before_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);
        assert!(ONE - DELTA <= matic_after_imb_rat && matic_after_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);

        // Verify that
        let eth_before_imb_rat = *vec_map::get(&before_imbs, &i);
        // the imbalance ratio for ETH before the trade is within bounds
        assert!(eth_before_imb_rat < ONE + DELTA, EInvalidImbalanceRatios);
        let eth_after_imb_rat = *vec_map::get(&after_imbs, &i);
        // the imbalance ratio for ETH after the trade is still within bounds
        assert!(eth_after_imb_rat < ONE + DELTA, EInvalidImbalanceRatios);

        // the imbalance ratio for USDT before the trade is within bounds
        let usdt_before_imb_rat = *vec_map::get(&before_imbs, &o);
        assert!(usdt_before_imb_rat > ONE - DELTA, EInvalidImbalanceRatios);
        // the imbalance ratio for USDT after the trade is still within bounds
        let usdt_after_imb_rat = *vec_map::get(&after_imbs, &o);
        assert!(usdt_after_imb_rat > ONE - DELTA, EInvalidImbalanceRatios);

        // Check that post-trade ratios compare correctly with pre-trade ratios:
        // 1. Incoming asset ratio increases
        // 2. Outgoing asset ration decreases
        assert!(eth_before_imb_rat < eth_after_imb_rat, EInvalidImbalanceRatios);
        assert!(usdt_after_imb_rat < usdt_before_imb_rat, EInvalidImbalanceRatios);

        let (scaled_fee, _) = ramm_math::scaled_fee_and_leverage(
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
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
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        // Verify that, as expected, this trade would be permitted.
        assert!(imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    #[test]
    /// Imbalance ratio calculation after the first trade, ETH/USDT.
    ///
    /// This covers situation 1.2, i.e. the relevant assets' ratios begin inbounds, but the trade
    /// would push them out of bounds.
    ///
    /// It is then verified that `check_imbalance_ratios` would *not* permit the trade, as
    /// expected.
    fun check_imbalance_ratios_case_1_2() {
        let i: u8 = 0;
        let o: u8 = 2;
        let prev_eth = 200 * test_util::eth_factor();
        let new_eth = 250 * test_util::eth_factor();
        let ai: u256 = new_eth - prev_eth;
        let prev_usdt = 400_000 * test_util::usdt_factor();
        let new_usdt = 292_159_18 * test_util::usdt_factor() / 100;
        let ao: u256 = prev_usdt - new_usdt;

        let (prev_balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(prev_eth, 200_000 * test_util::matic_factor(), prev_usdt, 9);

        let before_imbs = ramm_math::imbalance_ratios(
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        let mut new_balances: VecMap<u8, u256> = copy prev_balances;
        vec_map::remove(&mut new_balances, &i);
        vec_map::insert(&mut new_balances, i, new_eth);
        vec_map::remove(&mut new_balances, &o);
        vec_map::insert(&mut new_balances, o, new_usdt);

        let after_imbs = ramm_math::imbalance_ratios(
            &new_balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        // Ensure MATIC's imbalance ratio is within bounds at all times, as the trade did not
        // concern it.
        let matic_before_imb_rat = *vec_map::get(&before_imbs, &1);
        let matic_after_imb_rat = *vec_map::get(&after_imbs, &1);
        assert!(ONE - DELTA <= matic_before_imb_rat && matic_before_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);
        assert!(ONE - DELTA <= matic_after_imb_rat && matic_after_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);

        // Verify that
        let eth_before_imb_rat = *vec_map::get(&before_imbs, &i);
        // the imbalance ratio for ETH before the trade is within bounds
        assert!(eth_before_imb_rat < ONE + DELTA, EInvalidImbalanceRatios);
        let eth_after_imb_rat = *vec_map::get(&after_imbs, &i);
        // the imbalance ratio for ETH after the trade is no longer within bounds
        assert!(ONE + DELTA < eth_after_imb_rat, EInvalidImbalanceRatios);

        // the imbalance ratio for USDT before the trade is within bounds
        let usdt_before_imb_rat = *vec_map::get(&before_imbs, &o);
        assert!(ONE - DELTA < usdt_before_imb_rat , EInvalidImbalanceRatios);
        // the imbalance ratio for USDT after the trade is no longer within bounds
        let usdt_after_imb_rat = *vec_map::get(&after_imbs, &o);
        assert!(usdt_after_imb_rat < ONE - DELTA, EInvalidImbalanceRatios);

        // Check that post-trade ratios compare correctly with pre-trade ratios:
        // 1. Incoming asset ratio increases
        // 2. Outgoing asset ration decreases
        assert!(eth_before_imb_rat < eth_after_imb_rat, EInvalidImbalanceRatios);
        assert!(usdt_after_imb_rat < usdt_before_imb_rat, EInvalidImbalanceRatios);

        let (scaled_fee, _) = ramm_math::scaled_fee_and_leverage(
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
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
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        // Verify that, as expected, this trade would *not* be permitted.
        assert!(!imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    #[test]
    /// Imbalance ratio calculation after the first trade, ETH/USDT.
    ///
    /// This covers situation 2.1, i.e. the relevant assets' ratios begin out-of-bounds, but the
    /// trade will push them into bounds.
    ///
    /// It is then verified that `check_imbalance_ratios` *would* permit the trade, as expected.
    fun check_imbalance_ratios_case_2_1() {
        let i: u8 = 2;
        let o: u8 = 0;
        let prev_usdt = 292_159_18 * test_util::usdt_factor() / 100;
        let new_usdt = 400_000 * test_util::usdt_factor();
        let ai: u256 = new_usdt - prev_usdt;
        let prev_eth = 250 * test_util::eth_factor();
        let new_eth = 200 * test_util::eth_factor();
        let ao: u256 = prev_eth - new_eth;

        let (prev_balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(prev_eth, 200_000 * test_util::matic_factor(), prev_usdt, 9);

        let before_imbs = ramm_math::imbalance_ratios(
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        let mut new_balances: VecMap<u8, u256> = copy prev_balances;
        vec_map::remove(&mut new_balances, &i);
        vec_map::insert(&mut new_balances, i, new_usdt);
        vec_map::remove(&mut new_balances, &o);
        vec_map::insert(&mut new_balances, o, new_eth);

        let after_imbs = ramm_math::imbalance_ratios(
            &new_balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        // Ensure MATIC's imbalance ratio is within bounds at all times, as the trade did not
        // concern it.
        let matic_before_imb_rat = *vec_map::get(&before_imbs, &1);
        let matic_after_imb_rat = *vec_map::get(&after_imbs, &1);
        assert!(ONE - DELTA <= matic_before_imb_rat && matic_before_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);
        assert!(ONE - DELTA <= matic_after_imb_rat && matic_after_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);

        // Verify that
        let eth_before_imb_rat = *vec_map::get(&before_imbs, &o);
        // the imbalance ratio for ETH before the trade is out-of-bounds
        assert!(ONE + DELTA < eth_before_imb_rat, EInvalidImbalanceRatios);
        let eth_after_imb_rat = *vec_map::get(&after_imbs, &o);
        // the imbalance ratio for ETH after the trade is now within bounds
        assert!(eth_after_imb_rat < ONE + DELTA, EInvalidImbalanceRatios);

        // the imbalance ratio for USDT before the trade is outside of bounds
        let usdt_before_imb_rat = *vec_map::get(&before_imbs, &i);
        assert!(usdt_before_imb_rat < ONE - DELTA, EInvalidImbalanceRatios);
        // the imbalance ratio for USDT after the trade is now within bounds
        let usdt_after_imb_rat = *vec_map::get(&after_imbs, &i);
        assert!(ONE - DELTA < usdt_after_imb_rat, EInvalidImbalanceRatios);

        // Check that post-trade ratios compare correctly with pre-trade ratios:
        // 1. Incoming asset ratio increases
        // 2. Outgoing asset ration decreases
        assert!(usdt_before_imb_rat < usdt_after_imb_rat, EInvalidImbalanceRatios);
        assert!(eth_after_imb_rat < eth_before_imb_rat, EInvalidImbalanceRatios);

        let (scaled_fee, _) = ramm_math::scaled_fee_and_leverage(
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
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
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        // Verify that, as expected, this trade would be permitted.
        assert!(imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    #[test]
    /// Imbalance ratio check.
    ///
    /// Uses the ETH/MATIC/USDT RAMM from the whitepaper example, with its state modified so that
    /// an excess of ETH has been sold to the pool for outgoing USDT.
    ///
    /// In this trade, USDT is inbound, while ETH is outbound.
    ///
    /// Covers case 2.2.1, where ratios are outside of bounds in one direction, and an abnormally
    /// large trade would push them outside of bounds in the other, opposite direction.
    fun check_imbalance_ratios_case_2_2_1() {
        let i: u8 = 2;
        let o: u8 = 0;
        let prev_eth = 250 * test_util::eth_factor();
        let new_eth = 140 * test_util::eth_factor();
        let ao: u256 = prev_eth - new_eth;
        let prev_usdt = 292_159_18 * test_util::usdt_factor() / 100;
        let new_usdt = 50_784_022 * test_util::usdt_factor() / 100;
        let ai: u256 = new_usdt - prev_usdt;

        let (prev_balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(prev_eth, 200_000 * test_util::matic_factor(), prev_usdt, 9);

        let before_imbs = ramm_math::imbalance_ratios(
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        let mut new_balances: VecMap<u8, u256> = copy prev_balances;
        vec_map::remove(&mut new_balances, &i);
        vec_map::insert(&mut new_balances, i, new_usdt);
        vec_map::remove(&mut new_balances, &o);
        vec_map::insert(&mut new_balances, o, new_eth);

        let after_imbs = ramm_math::imbalance_ratios(
            &new_balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        // Ensure MATIC's imbalance ratio is within bounds at all times, as the trade did not
        // concern it.
        let matic_before_imb_rat = *vec_map::get(&before_imbs, &1);
        let matic_after_imb_rat = *vec_map::get(&after_imbs, &1);
        assert!(ONE - DELTA <= matic_before_imb_rat && matic_before_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);
        assert!(ONE - DELTA <= matic_after_imb_rat && matic_after_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);

        // Verify that
        let eth_before_imb_rat = *vec_map::get(&before_imbs, &o);
        // the imbalance ratio for ETH before the trade is above the allowed limit
        assert!(ONE + DELTA < eth_before_imb_rat, EInvalidImbalanceRatios);
        let eth_after_imb_rat = *vec_map::get(&after_imbs, &o);

        // Check that the imbalance ratio for USDT before the trade is below the allowed limit
        let usdt_before_imb_rat = *vec_map::get(&before_imbs, &i);
        assert!(usdt_before_imb_rat < ONE - DELTA, EInvalidImbalanceRatios);
        let usdt_after_imb_rat = *vec_map::get(&after_imbs, &i);
        // Check that the trade *does* bring the imbalance ratios closer to equilibrium...
        assert!(eth_after_imb_rat < eth_before_imb_rat, EInvalidImbalanceRatios);
        assert!(usdt_before_imb_rat < usdt_after_imb_rat, EInvalidImbalanceRatios);
        // ... but too far in the opposite direction:
        // the imbalance ratio for USDT after the trade is now *above* the allowed limit, and
        assert!(ONE + DELTA < usdt_after_imb_rat, EInvalidImbalanceRatios);
        // the imbalance ratio for ETH after the trade is now *below* the allowed limit
        assert!(eth_after_imb_rat < ONE - DELTA, EInvalidImbalanceRatios);

        let (scaled_fee, _) = ramm_math::scaled_fee_and_leverage(
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
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
            &prev_balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            ai,
            ao,
            pr_fee,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        // Assert that the imbalance ratio check fails, even though the trade improves
        // the imbalance ratios
        assert!(!imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    #[test]
    /// Imbalance ratio failure check.
    ///
    /// Uses the ETH/MATIC/USDT RAMM from the whitepaper example, with its state modified so that
    /// an excess of ETH has been sold to the pool for outgoing USDT.
    ///
    /// Covers situation 2.2.2 above.
    fun check_imbalance_ratios_case_2_2_2() {
        let i: u8 = 0;
        let o: u8 = 2;
        let prev_eth = 260 * test_util::eth_factor();
        let new_eth = 270 * test_util::eth_factor();
        let ai: u256 = new_eth - prev_eth;
        let prev_usdt = 29_215_918 * test_util::usdt_factor() / 100;
        let new_usdt = 27_418_571 * test_util::usdt_factor() / 100;
        let ao: u256 = prev_usdt - new_usdt;

        let (mut balances, lp_tokens_issued, prices, factors_prices, factors_balances) =
            imbalance_ratios(prev_eth, 200_000 * test_util::matic_factor(), prev_usdt, 9);

        let before_imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        vec_map::remove(&mut balances, &i);
        vec_map::insert(&mut balances, i, new_eth);
        vec_map::remove(&mut balances, &o);
        vec_map::insert(&mut balances, o, new_usdt);

        let after_imbs = ramm_math::imbalance_ratios(
            &balances,
            &lp_tokens_issued,
            &prices,
            &factors_balances,
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
        );

        // Ensure MATIC's imbalance ratio is within bounds at all times, as the trade did not
        // concern it.
        let matic_before_imb_rat = *vec_map::get(&before_imbs, &1);
        let matic_after_imb_rat = *vec_map::get(&after_imbs, &1);
        assert!(ONE - DELTA <= matic_before_imb_rat && matic_before_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);
        assert!(ONE - DELTA <= matic_after_imb_rat && matic_after_imb_rat <= ONE + DELTA, EInvalidImbalanceRatios);

        // Verify that
        let eth_before_imb_rat = *vec_map::get(&before_imbs, &i);
        // the imbalance ratio for ETH before the trade is above the allowed limit
        assert!(ONE + DELTA < eth_before_imb_rat, EInvalidImbalanceRatios);
        let eth_after_imb_rat = *vec_map::get(&after_imbs, &i);
        // the imbalance ratio for ETH after the trade is still above the allowed limit
        assert!(ONE + DELTA < eth_after_imb_rat, EInvalidImbalanceRatios);

        // the imbalance ratio for USDT before the trade is below the allowed limit
        let usdt_before_imb_rat = *vec_map::get(&before_imbs, &o);
        assert!(usdt_before_imb_rat < ONE - DELTA, EInvalidImbalanceRatios);
        // the imbalance ratio for USDT after the trade is still below the allowed limit
        let usdt_after_imb_rat = *vec_map::get(&after_imbs, &o);
        assert!(usdt_after_imb_rat < ONE - DELTA, EInvalidImbalanceRatios);

        // Check that the trade *does not* bring the imbalance ratios closer to equilibrium
        assert!(eth_before_imb_rat < eth_after_imb_rat, EInvalidImbalanceRatios);
        assert!(usdt_after_imb_rat < usdt_before_imb_rat, EInvalidImbalanceRatios);

        let (scaled_fee, _) = ramm_math::scaled_fee_and_leverage(
            &balances,
            &lp_tokens_issued,
            &prices,
            i,
            o,
            &factors_balances,
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
            &factors_prices,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            DELTA,
        );

        assert!(!imbalance_ratios_check, EInvalidImbalanceRatios);
    }

    // ---------------------------------------
    // Volatility fee calculation/update tests
    // ---------------------------------------

    /*
    IMPORTANT NOTE

    Like above for `check_imbalance_ratios`, the domains for the functions
    `compute_volatility_fee` and `update_volatility_data` are divided into mutually disjoint
    sets that produce different results, which should allow the functions' result/behavior to be
    exhaustively tested in each of them.

    Assume that

    * the RAMM has been initialized:
        * the state for each asset has both a previous price and its timestamp, and
        * the state for each asset has both a previous volatility parameter and its timestamp
    * `compute_volatility_fee` is called with information freshly queried from an asset's pricing
      oracle:
        * the most recent price, and its timestamp

    The cases for `compute_volatility_fee` are as follows:
        1. The newest price information is more than `TAU` seconds away from the last
        recorded price information
            Result: the volatility fee to be applied is 0
        2. The newest price information is within `TAU` seconds from the most recently
        recorded price information
            2.1 The newest price information is within `TAU` seconds from the most recently
                recorded volatility information
                2.1.1 The price change is under the last recorded volatility parameter
                    Result: the last recorded volatility parameter
                2.1.2 The price change is equal to the last recorded volatility parameter
                    Result: the price change as the volatility fee
                2.1.3 The price change is over the last recorded volatility parameter
                    Result: the price change as the volatility fee
            2.2 The newest price information is more than `TAU` seconds from the most recently
                recorded volatility information
                2.2.1 The price change is under the last recorded volatility parameter
                    Result: the last recorded volatility parameter
                2.2.2 The price change is equal to the last recorded volatility parameter
                    Result: the last recorded volatility parameter
                2.2.3 The price change is over the last recorded volatility parameter
                    Result: the last recorded volatility parameter
    */

    #[test]
    /// Test for volatility fee calculation; corresponds to case 1 above.
    fun compute_volatility_fee_case_1() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 0;
        let new_price: u256 = 1010;
        let new_price_timestamp: u64 = TAU + 1;
        let current_volatility_param: u256 = 0;
        let current_volatility_timestamp: u64 = 15;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            current_volatility_param,
            current_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        test_utils::assert_eq(calculated_volatility_fee, 0);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * the most recently calculated volatility parameter is younger than `TAU` seconds, and
    /// * the calculated volatility parameter is less than this most recently stored
    ///   parameter.
    ///
    /// Corresponds to case 2.1.1.
    fun compute_volatility_fee_case_2_1_1() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 0;
        // the price increases by 5%, which do not exceed the previous 10%
        let new_price: u256 = 1050;
        // the new price is obtained at most `TAU` seconds after the previous
        let new_price_timestamp: u64 = TAU;
        // 0.10, or 10%
        let current_volatility_param: u256 = 100_000_000_000;
        let current_volatility_timestamp: u64 = TAU - 20;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            current_volatility_param,
            current_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        test_utils::assert_eq(current_volatility_param, 10 * ONE / 100);
        test_utils::assert_eq(calculated_volatility_fee, current_volatility_param);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * the most recently calculated volatility parameter is younger than `TAU` seconds, and
    /// * the calculated volatility parameter equals this most recently stored
    ///   parameter.
    ///
    /// Corresponds to case 2.1.2.
    fun compute_volatility_fee_case_2_1_2() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 0;
        // the price increases by 5%, which equals the previously recorded 5% for this asset
        let new_price: u256 = 1050;
        // the new price is obtained at most `TAU` seconds after the previous
        let new_price_timestamp: u64 = TAU;
        // 0.10, or 10%
        let current_volatility_param: u256 = 50_000_000_000;
        let current_volatility_timestamp: u64 = TAU - 20;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            current_volatility_param,
            current_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        test_utils::assert_eq(current_volatility_param, 5 * ONE / 100);
        test_utils::assert_eq(calculated_volatility_fee, current_volatility_param);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * the most recently calculated volatility parameter is younger than `TAU` seconds, and
    /// * the calculated volatility parameter exceeds this most recently stored
    ///   parameter.
    ///
    /// Corresponds to case 2.1.3.
    fun compute_volatility_fee_case_2_1_3() {
        let previous_price: u256 = 1050;
        let previous_price_timestamp: u64 = 0;
        // the price drops by 10%, which exceeds the previous 5%
        let new_price: u256 = 945;
        // the new price is obtained at most `TAU` seconds after the previous
        let new_price_timestamp: u64 = TAU;
        // 0.05, or 5%
        let current_volatility_param: u256 = 50_000_000_000;
        let current_volatility_timestamp: u64 = TAU - 15;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            current_volatility_param,
            current_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        test_utils::assert_eq(current_volatility_param, 5 * ONE / 100);
        test_utils::assert_eq(calculated_volatility_fee, 10 * ONE / 100);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * there are more than `TAU` seconds between the newest price, and the most recently
    ///   calculated volatility parameter, and
    /// * the calculated volatility parameter is below the most recently stored parameter.
    ///
    /// Test for volatility fee calculation; corresponds to case 2.2.1 above.
    fun compute_volatility_fee_case_2_2_1() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 20;
        let new_price: u256 = 1040;
        let new_price_timestamp: u64 = TAU + 20;
        let current_volatility_param: u256 = 50_000_000_000;
        let current_volatility_timestamp: u64 = 15;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            current_volatility_param,
            current_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        test_utils::assert_eq(calculated_volatility_fee, 4 * ONE / 100);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * there are more than `TAU` seconds between the newest price, and the most recently
    ///   calculated volatility parameter, and
    /// * the calculated volatility parameter equals the most recently stored parameter.
    ///
    /// Test for volatility fee calculation; corresponds to case 2.2.2 above.
    fun compute_volatility_fee_case_2_2_2() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 20;
        let new_price: u256 = 1050;
        let new_price_timestamp: u64 = TAU + 20;
        let current_volatility_param: u256 = 50_000_000_000;
        let current_volatility_timestamp: u64 = 15;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            current_volatility_param,
            current_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        test_utils::assert_eq(current_volatility_param, 5 * ONE / 100);
        test_utils::assert_eq(calculated_volatility_fee, current_volatility_param);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * there are more than `TAU` seconds between the newest price, and the most recently
    ///   calculated volatility parameter, and
    /// * the calculated volatility parameter exceeds this most recently stored parameter.
    ///
    /// Corresponds to case 2.2.3.
    fun compute_volatility_fee_2_2_3() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 20;
        let new_price: u256 = 1050;
        let new_price_timestamp: u64 = TAU + 20;
        let current_volatility_param: u256 = 40_000_000_000;
        let current_volatility_timestamp: u64 = 15;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            current_volatility_param,
            current_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        test_utils::assert_eq(current_volatility_param, 4 * ONE / 100);
        test_utils::assert_eq(calculated_volatility_fee, 5 * ONE / 100);
    }

    /*

        1. The newest price information is more than `TAU` seconds away from the last
        recorded price information
            State changes: the RAMM's internal state will not change
        2. The newest price information is within `TAU` seconds from the most recently
        recorded price information
            2.1 The newest price information is within `TAU` seconds from the most recently
                recorded volatility information
                2.1.1 The price change is under the last recorded volatility parameter
                    State change: the RAMM's state will not change
                2.1.2 The price change is equal to the last recorded volatility parameter
                    State change:
                        * the asset's volatility parameter is updated to the calculated parameter
                        * the asset's parameter timestamp is updated to the newest price's
                2.1.3 The price change is over the last recorded volatility parameter
                    State change:
                        * the asset's volatility parameter is updated to the calculated parameter
                        * the asset's parameter timestamp is updated to the newest price's
            2.2 The newest price information is more than `TAU` seconds from the most recently
                recorded volatility information
                2.2.1 The price change is under the last recorded volatility parameter
                    State change:
                        * the asset's volatility parameter is updated to the calculated parameter
                        * the asset's parameter timestamp is updated to the newest price's
                2.2.2 The price change is equal to the last recorded volatility parameter
                    State change:
                        * the asset's volatility parameter is updated to the calculated parameter
                        * the asset's parameter timestamp is updated to the newest price's
                2.2.3 The price change is over the last recorded volatility parameter
                    State change:
                        * the asset's volatility parameter is updated to the calculated parameter
                        * the asset's parameter timestamp is updated to the newest price's
    */

    #[test]
    /// Test for volatility fee update; corresponds to case 1 above.
    fun update_volatility_data_case_1() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 0;
        let new_price: u256 = 1001;
        let new_price_timestamp: u64 = TAU + 10;
        // Corresponds to 0.1%
        let stored_volatility_param: &mut u256 = &mut (1 * ONE / 1000);
        let stored_volatility_timestamp: &mut u64 = &mut 15;

        let previous_volatility_param: u256 = *stored_volatility_param;
        let previous_volatility_timestamp: u64 = *stored_volatility_timestamp;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            previous_volatility_param,
            previous_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        ramm_math::update_volatility_data(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            stored_volatility_param,
            stored_volatility_timestamp,
            calculated_volatility_fee,
            ONE,
            TAU
        );

        let current_volatility_param: u256 = *stored_volatility_param;
        let current_volatility_timestamp: u64 = *stored_volatility_timestamp;

        test_utils::assert_eq(current_volatility_param, previous_volatility_param);
        test_utils::assert_eq(current_volatility_timestamp, previous_volatility_timestamp);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * the most recently calculated volatility parameter is younger than `TAU` seconds, and
    /// * the calculated volatility parameter is less than this most recently stored
    ///   parameter.
    ///
    /// Corresponds to case 2.1.1.
    fun update_volatility_data_case_2_1_1() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 0;
        // the price increases by 5%, which does not exceed the previous 10%
        let new_price: u256 = 1050;
        // the new price is obtained `TAU` seconds after the previous
        let new_price_timestamp: u64 = TAU;
        // 0.10, or 10%
        let stored_volatility_param: &mut u256 = &mut (10 * ONE / 100);
        let stored_volatility_timestamp: &mut u64 = &mut 20;

        let previous_volatility_param: u256 = *stored_volatility_param;
        let previous_volatility_timestamp: u64 = *stored_volatility_timestamp;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            previous_volatility_param,
            previous_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        ramm_math::update_volatility_data(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            stored_volatility_param,
            stored_volatility_timestamp,
            calculated_volatility_fee,
            ONE,
            TAU
        );

        let current_volatility_param: u256 = *stored_volatility_param;
        let current_volatility_timestamp: u64 = *stored_volatility_timestamp;

        test_utils::assert_eq(current_volatility_param, previous_volatility_param);
        test_utils::assert_eq(current_volatility_timestamp, previous_volatility_timestamp);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * the most recently calculated volatility parameter is younger than `TAU` seconds, and
    /// * the calculated volatility parameter equals this most recently stored
    ///   parameter.
    ///
    /// Corresponds to case 2.1.2.
    fun update_volatility_data_case_2_1_2() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 0;
        // the price increases by 5%, which equals the previously recorded 5% for this asset
        let new_price: u256 = 1050;
        // the new price is obtained `TAU` seconds after the previous
        let new_price_timestamp: u64 = TAU;
        // 0.10, or 10%
        let stored_volatility_param: &mut u256 = &mut 50_000_000_000;
        let stored_volatility_timestamp: &mut u64 = &mut (TAU - 20);

        let previous_volatility_param: u256 = *stored_volatility_param;
        let previous_volatility_timestamp: u64 = *stored_volatility_timestamp;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            previous_volatility_param,
            previous_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        ramm_math::update_volatility_data(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            stored_volatility_param,
            stored_volatility_timestamp,
            calculated_volatility_fee,
            ONE,
            TAU
        );

        let current_volatility_param: u256 = *stored_volatility_param;
        let current_volatility_timestamp: u64 = *stored_volatility_timestamp;

        test_utils::assert_eq(current_volatility_param, calculated_volatility_fee);
        test_utils::assert_eq(current_volatility_timestamp, new_price_timestamp);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * the most recently calculated volatility parameter is younger than `TAU` seconds, and
    /// * the calculated volatility parameter exceeds this most recently stored
    ///   parameter.
    ///
    /// Corresponds to case 2.1.3.
    fun update_volatility_data_case_2_1_3() {
        let previous_price: u256 = 1050;
        let previous_price_timestamp: u64 = 0;
        // the price drops by 10%, which exceeds the previous 5%
        let new_price: u256 = 945;
        // the new price is obtained over `TAU` seconds after the previous
        let new_price_timestamp: u64 = TAU;
        // 0.05, or 5%
        let stored_volatility_param: &mut u256 = &mut 50_000_000_000;
        let stored_volatility_timestamp: &mut u64 = &mut (TAU - 15);

        let previous_volatility_param: u256 = *stored_volatility_param;
        let previous_volatility_timestamp: u64 = *stored_volatility_timestamp;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            previous_volatility_param,
            previous_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        ramm_math::update_volatility_data(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            stored_volatility_param,
            stored_volatility_timestamp,
            calculated_volatility_fee,
            ONE,
            TAU
        );

        let current_volatility_param: u256 = *stored_volatility_param;
        let current_volatility_timestamp: u64 = *stored_volatility_timestamp;

        test_utils::assert_eq(calculated_volatility_fee, 100_000_000_000);
        test_utils::assert_eq(current_volatility_param, calculated_volatility_fee);
        test_utils::assert_eq(current_volatility_timestamp, new_price_timestamp);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * there are more than `TAU` seconds between the newest price, and the most recently
    ///   calculated volatility parameter, and
    /// * the calculated volatility parameter is below the most recently stored parameter.
    ///
    /// Test for volatility fee calculation; corresponds to case 2.2.1 above.
    fun update_volatility_data_case_2_2_1() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 20;
        let new_price: u256 = 1040;
        let new_price_timestamp: u64 = TAU + 20;
        let stored_volatility_param: &mut u256 = &mut 50_000_000_000;
        let stored_volatility_timestamp: &mut u64 = &mut 15;

        let previous_volatility_param: u256 = *stored_volatility_param;
        let previous_volatility_timestamp: u64 = *stored_volatility_timestamp;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            previous_volatility_param,
            previous_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        ramm_math::update_volatility_data(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            stored_volatility_param,
            stored_volatility_timestamp,
            calculated_volatility_fee,
            ONE,
            TAU
        );

        let current_volatility_param: u256 = *stored_volatility_param;
        let current_volatility_timestamp: u64 = *stored_volatility_timestamp;

        test_utils::assert_eq(current_volatility_param, calculated_volatility_fee);
        test_utils::assert_eq(current_volatility_timestamp, new_price_timestamp);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * there are more than `TAU` seconds between the newest price, and the most recently
    ///   calculated volatility parameter, and
    /// * the calculated volatility parameter equals the most recently stored parameter.
    ///
    /// Test for volatility fee calculation; corresponds to case 2.2.2 above.
    fun update_volatility_data_case_2_2_2() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 20;
        let new_price: u256 = 1050;
        let new_price_timestamp: u64 = TAU + 20;
        let stored_volatility_param: &mut u256 = &mut 50_000_000_000;
        let stored_volatility_timestamp: &mut u64 = &mut 15;

        let previous_volatility_param: u256 = *stored_volatility_param;
        let previous_volatility_timestamp: u64 = *stored_volatility_timestamp;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            previous_volatility_param,
            previous_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        ramm_math::update_volatility_data(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            stored_volatility_param,
            stored_volatility_timestamp,
            calculated_volatility_fee,
            ONE,
            TAU
        );

        let current_volatility_param: u256 = *stored_volatility_param;
        let current_volatility_timestamp: u64 = *stored_volatility_timestamp;

        test_utils::assert_eq(calculated_volatility_fee, 5 * ONE / 100);
        test_utils::assert_eq(current_volatility_param, calculated_volatility_fee);
        test_utils::assert_eq(current_volatility_timestamp, new_price_timestamp);
    }

    #[test]
    /// Case in which
    /// * a sufficiently volatile price change occurs within `TAU` seconds since the last
    ///   volatility check, and
    /// * there are more than `TAU` seconds between the newest price, and the most recently
    ///   calculated volatility parameter, and
    /// * the calculated volatility parameter exceeds this most recently stored parameter.
    ///
    /// Corresponds to case 2.2.3.
    fun update_volatility_data_2_2_3() {
        let previous_price: u256 = 1000;
        let previous_price_timestamp: u64 = 20;
        let new_price: u256 = 1050;
        let new_price_timestamp: u64 = TAU + 20;
        let stored_volatility_param: &mut u256 = &mut 40_000_000_000;
        let stored_volatility_timestamp: &mut u64 = &mut 15;

        let previous_volatility_param: u256 = *stored_volatility_param;
        let previous_volatility_timestamp: u64 = *stored_volatility_timestamp;

        let calculated_volatility_fee: u256 = ramm_math::compute_volatility_fee(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            previous_volatility_param,
            previous_volatility_timestamp,
            PRECISION_DECIMAL_PLACES,
            MAX_PRECISION_DECIMAL_PLACES,
            ONE,
            MU,
            BASE_FEE,
            TAU
        );

        ramm_math::update_volatility_data(
            previous_price,
            previous_price_timestamp,
            new_price,
            new_price_timestamp,
            stored_volatility_param,
            stored_volatility_timestamp,
            calculated_volatility_fee,
            ONE,
            TAU
        );

        let current_volatility_param: u256 = *stored_volatility_param;
        let current_volatility_timestamp: u64 = *stored_volatility_timestamp;

        test_utils::assert_eq(calculated_volatility_fee, 5 * ONE / 100);
        test_utils::assert_eq(current_volatility_param, calculated_volatility_fee);
        test_utils::assert_eq(current_volatility_timestamp, new_price_timestamp);
    }
}