module ramm_sui::oracles {
    use switchboard::aggregator::{Self, Aggregator};
    use switchboard::math as sb_math;

    use ramm_sui::math;

    /* friend ramm_sui::ramm; */

    const ENegativeSbD: u64 = 0;
    const EStalePrice: u64 = 1;

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

        assert!(!neg, ENegativeSbD);

        ((value as u256), math::pow(10u256, prec - scaling_factor))
    }

    fun check_price_staleness(
        current_clock_timestamp: u64,
        latest_feed_timestamp: u64,
        staleness_threshold: u64,
    ) {
        // The timestamp is in seconds, but the staleness threshold, as well as the clock's
        // timestamp, are in milliseconds.
        let latest_feed_timestamp_scaled = latest_feed_timestamp * 1000;

        // Recall that Sui Move will abort on underflow, so this is safe.
        assert!(
            math::abs_diff_u64(current_clock_timestamp, latest_feed_timestamp_scaled) <= staleness_threshold,
            EStalePrice
        );
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

}