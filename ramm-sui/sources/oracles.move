module ramm_sui::oracles {
    use switchboard::aggregator::{Self, Aggregator};
    use switchboard::math as sb_math;

    use ramm_sui::math;

    friend ramm_sui::ramm;

    const ENegativeSbD: u64 = 0;
    const EStalePrice: u64 = 1;

    fun sbd_data_to_info(value: u128, scaling_factor: u8, neg: bool, prec: u8): (u256, u256) {
        assert!(!neg, ENegativeSbD);

        ((value as u256), math::pow(10u256, prec - scaling_factor))
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

    fun check_price_staleness(
        current_clock_timestamp: u64,
        latest_feed_timestamp: u64,
        staleness_threshold: u64,
    ) {
        // Recall that Sui Move will abort on underflow, so this is safe.
        assert!(
            math::abs_diff_u64(current_clock_timestamp, latest_feed_timestamp) <= staleness_threshold,
            EStalePrice
        );
    }

    spec check_price_staleness {
        aborts_if math::abs_diff_u64(current_clock_timestamp, latest_feed_timestamp) > staleness_threshold with EStalePrice;
    }

    /// Given a Switchboard aggregator, fetch the pricing data within it.
    /// Returns a tuple with the `u256` price, and the appropriate scaling factor to use when
    /// working with `PRECISION_DECIMAL_PLACES`.
    ///
    /// This function is NOT safe to call *without* first checking that the aggregator's address
    /// matches the RAMM's record for the given asset.
    public fun get_price_from_oracle(
        feed: &Aggregator,
        current_clock_timestamp: u64,
        staleness_threshold: u64,
        prec: u8
    ): (u256, u256, u64) {
        // the timestamp can be used in the future to check for price staleness
        let (latest_result, latest_feed_timestamp) = aggregator::latest_value(feed);

        check_price_staleness(current_clock_timestamp, latest_feed_timestamp, staleness_threshold);

        // Current price, and its scaling factor.
        let (price, scaling) = sbd_to_price_info(latest_result, prec);

        (price, scaling, latest_feed_timestamp)

    }

    /// This `0x2` is the only abort raised by `switchboard_std::aggregator::latest_value`.
    spec get_price_from_oracle {
        aborts_with ENegativeSbD, EStalePrice, EXECUTION_FAILURE, 0x2;
    }
}