module ramm_sui::events {
    use std::string::String;
    use std::type_name::TypeName;

    use sui::event;
    use sui::object::ID;
    use sui::vec_map::VecMap;

    friend ramm_sui::ramm;
    friend ramm_sui::interface2;
    friend ramm_sui::interface3;

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

    struct PoolStateEvent has copy, drop {
        ramm_id: ID,
        sender: address,
        asset_types: vector<TypeName>,
        asset_balances: vector<u256>,
        asset_lpt_issued: vector<u256>,
    }

    public(friend) fun pool_state_event(
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
    struct TradeIn {}
    /// Phantom type to mark a `TradeEvent` as the result of `trade_amount_out`
    struct TradeOut {}

    /// Datatype used to emit, to the Sui blockchain, information on a successful trade.
    ///
    /// A phantom type is used to mark whether it's the result of a call to `trade_amount_in`
    /// (selling an exact amount of an asset to the RAMM), or to `trade_amount_out` (buying
    /// an exact amount of an asset from the RAMM).
    struct TradeEvent<phantom TradeType> has copy, drop {
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        token_out: TypeName,
        amount_in: u64,
        amount_out: u64,
        protocol_fee: u64,
        execute_trade: bool
    }

    /// Given all the information necessary to identify a given RAMM's trade event,
    /// emit it.
    public(friend) fun trade_event<TradeType>(
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        token_out: TypeName,
        amount_in: u64,
        amount_out: u64,
        protocol_fee: u64,
        execute_trade: bool
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
                execute_trade,
            }
        )
    }

    /// Datatype used to emit, to the Sui blockchain, information on an unsucessful trade.
    ///
    /// A phantom type is used to mark whether it's the result of a call to `trade_amount_in`
    /// (selling an exact amount of an asset to the RAMM), or to `trade_amount_out` (buying
    /// an exact amount of an asset from the RAMM).
    struct TradeFailure<phantom TradeType> has copy, drop {
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        token_out: TypeName,
        amount_in: u64,
        message: String
    }

    /// Given all the information necessary to identify a given RAMM's failed trade,
    /// emit an event describing it.
    public(friend) fun trade_failure_event<TradeType>(
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        token_out: TypeName,
        amount_in: u64,
        message: String
    ) {
        event::emit(
            TradeFailure<TradeType> {
                ramm_id,
                trader,
                token_in,
                token_out,
                amount_in,
                message
            }
        )
    }

    /// Datatype used to emit, to the Sui blockchain, information on a successful liquidity deposit.
    struct LiquidityDepositEvent has copy, drop {
        ramm_id: ID,
        trader: address,
        token_in: TypeName,
        amount_in: u64,
        lpt: u64,
    }

    /// Given all the information necessary to identify a given RAMM's liquidity deposit event,
    /// emit it.
    public(friend) fun liquidity_deposit_event(
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
    struct LiquidityWithdrawalEvent has copy, drop {
        ramm_id: ID,
        trader: address,
        token_out: TypeName,
        lpt: u64,
        amounts_out: VecMap<TypeName, u64>,
        fees: VecMap<TypeName, u64>,
    }

    /// Given all the information necessary to identify a given RAMM's liquidity withdrawal event,
    /// emit it.
    public(friend) fun liquidity_withdrawal_event(
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

    /// Datatype describing a Sui event for a given RAMM's fee collection.
    struct FeeCollectionEvent has copy, drop {
        ramm_id: ID,
        admin: address,
        fee_collector: address,
        collected_fees: VecMap<TypeName, u64>
    }

    /// Given all the information necessary to identify a given RAMM's fee collection event,
    /// emit it.
    public(friend) fun fee_collection_event(
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