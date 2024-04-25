module ramm_sui::events {
    use std::type_name::TypeName;

    use sui::event;
    use sui::vec_map::VecMap;

    /* friend ramm_sui::ramm; */
    /* friend ramm_sui::interface2; */
    /* friend ramm_sui::interface3; */

    /// ---------
    /// IMPORTANT
    /// ---------
    
    /*
    In Move, it is not possible to create/destroy instances of any `struct` outside
    of the module they are defined in; see

    https://move-language.github.io/move/structs-and-resources.html#privileged-struct-operations

    This would mean that, if we wanted to directly emit events from the `ramm` module, we would
    have to define the event `struct`s in the `ramm` module itself - that module is already over
    2000 lines long.

    As such, they are defined here.
    */

    public struct PoolStateEvent has copy, drop {
        ramm_id: ID,
        sender: address,
        asset_types: vector<TypeName>,
        asset_balances: vector<u256>,
        asset_lpt_issued: vector<u256>,
    }

    public(package) fun pool_state_event(
        ramm_id: ID,
        sender: address,
        asset_types: vector<TypeName>,
        asset_balances: vector<u256>,
        asset_lpt_issued: vector<u256>,
    ) {
        let pse = PoolStateEvent {
            ramm_id,
            sender,
            asset_types,
            asset_balances,
            asset_lpt_issued,
        };

        event::emit(pse)
    }

    /// Phantom type to mark a `TradeEvent` as the result of `trade_amount_in`
    public struct TradeIn {}
    /// Phantom type to mark a `TradeEvent` as the result of `trade_amount_out`
    public struct TradeOut {}

    /// Datatype used to emit, to the Sui blockchain, information on a successful trade.
    ///
    /// A phantom type is used to mark whether it's the result of a call to `trade_amount_in`
    /// (selling an exact amount of an asset to the RAMM), or to `trade_amount_out` (buying
    /// an exact amount of an asset from the RAMM).
    public struct TradeEvent<phantom TradeType> has copy, drop {
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        token_out: TypeName,
        amount_in: u64,
        amount_out: u64,
        protocol_fee: u64,
    }

    /// Given all the information necessary to identify a given RAMM's trade event,
    /// emit it.
    public(package) fun trade_event<TradeType>(
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        token_out: TypeName,
        amount_in: u64,
        amount_out: u64,
        protocol_fee: u64,
    ) {
        event::emit(
            TradeEvent<TradeType> {
                ramm_id,
                trader,
                token_in,
                token_out,
                amount_in,
                amount_out,
                protocol_fee,
            }
        )
    }

    public struct PriceEstimationEvent has copy, drop {
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        token_out: TypeName,
        amount_in: u64,
        amount_out: u64,
        protocol_fee: u64,
    }

    /// Emit an event containing pricing information estimates for a potential trade.
    ///
    /// Note that no changes are made to the RAMM's state when estimating prices,
    /// and that the price is not guaranteed to be the same when the trade is
    /// executed.
    public(package) fun price_estimation_event(
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        token_out: TypeName,
        amount_in: u64,
        amount_out: u64,
        protocol_fee: u64,
    ) {
        event::emit(
            PriceEstimationEvent {
                ramm_id,
                trader,
                token_in,
                token_out,
                amount_in,
                amount_out,
                protocol_fee,
            }
        )
    }

    /// Datatype used to emit, to the Sui blockchain, information on a successful liquidity deposit.
    public struct LiquidityDepositEvent has copy, drop {
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        amount_in: u64,
        lpt: u64,
    }

    /// Given all the information necessary to identify a given RAMM's liquidity deposit event,
    /// emit it.
    public(package) fun liquidity_deposit_event(
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        amount_in: u64,
        lpt: u64
    ) {
        event::emit(
            LiquidityDepositEvent {
                ramm_id,
                trader,
                token_in,
                amount_in,
                lpt
            }
        )
    }

    /// Datatype describing a Sui event for a given RAMM's liquidity withdrawal.
    public struct LiquidityWithdrawalEvent has copy, drop {
        ramm_id: ID,
        trader: address,
        token_out: TypeName,
        lpt: u64,
        amounts_out: VecMap<TypeName, u64>,
        fees: VecMap<TypeName, u64>,
    }

    /// Given all the information necessary to identify a given RAMM's liquidity withdrawal event,
    /// emit it.
    public(package) fun liquidity_withdrawal_event(
        ramm_id: ID,
        trader: address,
        token_out: TypeName,
        lpt: u64,
        amounts_out: VecMap<TypeName, u64>,
        fees: VecMap<TypeName, u64>,
    ) {
        let lwe = LiquidityWithdrawalEvent {
                ramm_id,
                trader,
                token_out,
                lpt,
                amounts_out,
                fees,
            };

        event::emit(lwe)
    }

    /// Description of a Sui event with a RAMM's imbalance ratios.
    ///
    /// The event contains a `VecMap`, such that
    /// * its keys are each of the RAMM asset's `TypeName`s
    /// * its values are the imbalance ratios for each of the RAMM's assets, represented with
    ///   as `u64`s with `PRECISION_DECIMAL_PLACES`
    public struct ImbalanceRatioEvent has copy, drop {
        ramm_id: ID,
        requester: address,
        imb_ratios: VecMap<TypeName, u64>,
    }

    /// Given the required data, emit an event with a RAMM's imbalance ratios.
    public(package) fun imbalance_ratios_event(
        ramm_id: ID,
        requester: address,
        imb_ratios: VecMap<TypeName, u64>,
    ) {
        let ire = ImbalanceRatioEvent {
                ramm_id,
                requester,
                imb_ratios,
            };

        event::emit(ire)
    }

    /// Datatype describing a Sui event for a given RAMM's fee collection.
    public struct FeeCollectionEvent has copy, drop {
        ramm_id: ID,
        admin: address,
        fee_collector: address,
        collected_fees: VecMap<TypeName, u64>
    }

    /// Given all the information necessary to identify a given RAMM's fee collection event,
    /// emit it.
    public(package) fun fee_collection_event(
        ramm_id: ID,
        admin: address,
        fee_collector: address,
        collected_fees: VecMap<TypeName, u64>
    ) {
        let fce = FeeCollectionEvent {
                ramm_id,
                admin,
                fee_collector,
                collected_fees,
            };

        event::emit(fce)
    }
}