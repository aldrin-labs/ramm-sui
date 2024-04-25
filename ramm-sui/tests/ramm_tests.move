#[test_only]
module ramm_sui::ramm_tests {
    use sui::balance::Supply;

    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, TransactionEffects};
    use sui::test_utils;

    use ramm_sui::ramm::{Self, LP, LPTSupplyBag, RAMM, RAMMAdminCap, RAMMNewAssetCap};
    use ramm_sui::test_util::{Self, BTC, ETH, MATIC, USDT, btc_dec_places};

    use switchboard_std::aggregator::{Self, Aggregator};

    const THREE: u8 = 3;

    const ADMIN: address = @0xA1;
    const ALICE: address = @0xACE;
    const BOB: address = @0xFACE;

    const ERAMMCreation: u64 = 0;
    const ERAMMAssetAddition: u64 = 1;
    const ERAMMDepositStatus: u64 = 3;
    const ERAMMFailedDeletion: u64 = 4;

    #[test]
    /// Basic flow test:
    /// 1. Create RAMM
    /// 2. Add assets to RAMM
    ///   2a. Create aggregators for test assets
    ///   2b. Share aggregator objects
    /// 3. Initialize the RAMM
    fun create_ramm() {
        let mut scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        // Check that the RAMM and caps don't yet exist before the RAMM's creation
        assert!(!test_scenario::has_most_recent_shared<RAMM>(), ERAMMCreation);
        assert!(!test_scenario::has_most_recent_for_address<RAMMAdminCap>(ADMIN), ERAMMCreation);
        assert!(!test_scenario::has_most_recent_for_address<RAMMNewAssetCap>(ADMIN), ERAMMCreation);
        // Create the RAMM
        {
            ramm::new_ramm(ADMIN, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ADMIN);
        // Check that they do exist, now
        assert!(test_scenario::has_most_recent_shared<RAMM>(), ERAMMCreation);
        assert!(test_scenario::has_most_recent_for_address<RAMMAdminCap>(ADMIN), ERAMMCreation);
        assert!(test_scenario::has_most_recent_for_address<RAMMNewAssetCap>(ADMIN), ERAMMCreation);

        // Create a testing aggregator for the asset used in this test

        let _aggr_id = test_util::create_write_share_aggregator(scenario, 2780245000000, 8, false, 100);

        test_scenario::next_tx(scenario, ADMIN);

        // Retrieve RAMM and caps from storage, and add above asset to it
         {
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ADMIN);
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);

            let btc_aggr = test_scenario::take_shared<Aggregator>(scenario);

            assert!(ramm::get_asset_count(&ramm) == 0, ERAMMCreation);
            ramm::add_asset_to_ramm<BTC>(&mut ramm, &btc_aggr, 1000, btc_dec_places(), &admin_cap, &new_asset_cap);
            assert!(ramm::get_asset_count(&ramm) == 1, ERAMMCreation);

            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
            test_scenario::return_to_address<RAMMNewAssetCap>(ADMIN, new_asset_cap);
            test_scenario::return_shared<RAMM>(ramm);
        };
        test_scenario::next_tx(scenario, ADMIN);

        // 1. retrieve objects from storage again
        // 2. initialize the RAMM, and
        // 3. check that the new_asset_cap used to add new objects no longer exists
        {
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ADMIN);

            ramm::initialize_ramm(&mut ramm, &admin_cap, new_asset_cap);

            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
        };
         test_scenario::next_tx(scenario, ADMIN);

        assert!(!test_scenario::has_most_recent_for_address<RAMM>(ADMIN), ERAMMCreation);

        // Assert that after initialization, the new asset cap has been deleted.
        assert!(!test_scenario::has_most_recent_for_address<RAMMNewAssetCap>(ADMIN), ERAMMCreation);
        assert!(!test_scenario::has_most_recent_for_sender<RAMMNewAssetCap>(scenario), ERAMMCreation);
        assert!(!test_scenario::has_most_recent_shared<RAMMNewAssetCap>(), ERAMMCreation);
        assert!(!test_scenario::has_most_recent_immutable<RAMMNewAssetCap>(), ERAMMCreation);

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Test for RAMM asset addition.
    ///
    /// 1. Create a RAMM
    /// 2. Create and populate a test asset price aggregator
    /// 3. Add an asset (test BTC) to the RAMM
    /// 4. Verify the RAMM's internal state after the asset addition
    fun add_asset_to_ramm_tests() {
        let mut scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        // Create the RAMM
        {
            ramm::new_ramm(ADMIN, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ADMIN);

        // Create a test aggregator
        let _aggr_id = test_util::create_write_share_aggregator(scenario, 2780245000000, 8, false, 100);

        test_scenario::next_tx(scenario, ADMIN);

        // Retrieve RAMM and caps from storage, and add above assets to it
         {
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ADMIN);
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);

            let btc_aggr = test_scenario::take_shared<Aggregator>(scenario);

            let min_trade_amount: u64 = 1000;
            ramm::add_asset_to_ramm<BTC>(
                &mut ramm,
                &btc_aggr,
                min_trade_amount,
                btc_dec_places(),
                &admin_cap,
                &new_asset_cap
            );

            // Check the RAMM's internal state after the asset has been added
            assert!(ramm::get_admin_cap_id(&ramm) == object::id(&admin_cap), ERAMMAssetAddition);
            assert!(ramm::get_new_asset_cap_id(&ramm) == object::id(&new_asset_cap), ERAMMAssetAddition);
            assert!(!ramm::is_initialized(&ramm), ERAMMAssetAddition);

            assert!(ramm::get_collected_protocol_fees<BTC>(&ramm) == 0u64, ERAMMAssetAddition);
            assert!(ramm::get_fee_collector(&ramm) == ADMIN, ERAMMAssetAddition);

            assert!(ramm::get_asset_count(&ramm) == 1, ERAMMAssetAddition);
            assert!(!ramm::get_deposit_status<BTC>(&ramm), ERAMMAssetAddition);
            assert!(ramm::get_factor_for_balance<BTC>(&ramm) == 10000u256, ERAMMAssetAddition);
            assert!(ramm::get_minimum_trade_amount<BTC>(&ramm) == min_trade_amount, ERAMMAssetAddition);
            assert!(ramm::get_type_index<BTC>(&ramm) == 0u8, ERAMMAssetAddition);

            assert!(ramm::get_aggregator_address<BTC>(&ramm) == aggregator::aggregator_address(&btc_aggr), ERAMMAssetAddition);
            assert!(ramm::get_previous_price<BTC>(&ramm) == 0, ERAMMAssetAddition);
            assert!(ramm::get_previous_price_timestamp<BTC>(&ramm) == 0, ERAMMAssetAddition);
            assert!(ramm::get_volatility_index<BTC>(&ramm) == 0, ERAMMAssetAddition);
            assert!(ramm::get_volatility_timestamp<BTC>(&ramm) == 0, ERAMMAssetAddition);

            assert!(ramm::get_balance<BTC>(&ramm) == 0u256, ERAMMAssetAddition);
            assert!(ramm::get_typed_balance<BTC>(&ramm) == 0u256, ERAMMAssetAddition);

            assert!(ramm::get_lptokens_issued<BTC>(&ramm) == 0u256, ERAMMAssetAddition);
            assert!(ramm::get_typed_lptokens_issued<BTC>(&ramm) == 0u256, ERAMMAssetAddition);

            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
            test_scenario::return_to_address<RAMMNewAssetCap>(ADMIN, new_asset_cap);
            test_scenario::return_shared<RAMM>(ramm);
        };
        test_scenario::next_tx(scenario, ADMIN);

        test_scenario::end(scenario_val);
    }

    #[test]
    /// 1. Create a RAMM
    /// 2. Add an asset to it
    /// 3. Verify that its deposits are disabled
    /// 4. Initialize the RAMM
    /// 5. Verify that its deposits are now enabled, and nothing else in its internal state changed
    fun check_deposit_status_after_init() {
        let mut scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        // Create RAMM
        {
            ramm::new_ramm(ADMIN, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ADMIN);

        // Create test aggregator
        let _aggr_id = test_util::create_write_share_aggregator(scenario, 2780245000000, 8, false, 100);

        test_scenario::next_tx(scenario, ADMIN);

        {
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ADMIN);

            let btc_aggr = test_scenario::take_shared<Aggregator>(scenario);

            let minimum_trade_amount = 1000;

            ramm::add_asset_to_ramm<BTC>(
                &mut ramm,
                &btc_aggr,
                minimum_trade_amount,
                btc_dec_places(),
                &admin_cap,
                &new_asset_cap
            );
            // Check that immediately after adding an asset, its deposits are disabled
            assert!(!ramm::get_deposit_status<BTC>(&ramm), ERAMMDepositStatus);
            let new_asset_cap_id: ID = object::id(&new_asset_cap);
            ramm::initialize_ramm(&mut ramm, &admin_cap, new_asset_cap);
            // Check that immediately after initializing the RAMM, the asset's deposits are now enabled
            assert!(ramm::get_deposit_status<BTC>(&ramm), ERAMMDepositStatus);

            assert!(ramm::is_initialized(&ramm), ERAMMDepositStatus);

            // Check every other field in the RAMM's internal state, after the asset has been added *and*
            // the RAMM has been initialized.
            //
            // This list is the same as in the `add_asset_to_ramm_tests` test, excluding the `get_deposit_status`
            // getter.
            //
            // This is to make sure initialization changes nothing more than it needs to - deposit statuses.
            assert!(ramm::get_admin_cap_id(&ramm) == object::id(&admin_cap), ERAMMDepositStatus);
            assert!(ramm::get_new_asset_cap_id(&ramm) == new_asset_cap_id, ERAMMAssetAddition);
            assert!(ramm::is_initialized(&ramm), ERAMMAssetAddition);

            assert!(ramm::get_fee_collector(&ramm) == ADMIN, ERAMMDepositStatus);
            assert!(ramm::get_collected_protocol_fees<BTC>(&ramm) == 0u64, ERAMMDepositStatus);

            assert!(ramm::get_asset_count(&ramm) == 1, ERAMMDepositStatus);
            assert!(ramm::get_factor_for_balance<BTC>(&ramm) == 10000u256, ERAMMDepositStatus);
            assert!(ramm::get_minimum_trade_amount<BTC>(&ramm) == minimum_trade_amount, ERAMMDepositStatus);
            assert!(ramm::get_type_index<BTC>(&ramm) == 0u8, ERAMMDepositStatus);

            assert!(ramm::get_aggregator_address<BTC>(&ramm) == aggregator::aggregator_address(&btc_aggr), ERAMMDepositStatus);
            assert!(ramm::get_previous_price<BTC>(&ramm) == 0, ERAMMAssetAddition);
            assert!(ramm::get_previous_price_timestamp<BTC>(&ramm) == 0, ERAMMAssetAddition);
            assert!(ramm::get_volatility_index<BTC>(&ramm) == 0, ERAMMDepositStatus);
            assert!(ramm::get_volatility_timestamp<BTC>(&ramm) == 0, ERAMMDepositStatus);

            assert!(ramm::get_balance<BTC>(&ramm) == 0u256, ERAMMDepositStatus);
            assert!(ramm::get_typed_balance<BTC>(&ramm) == 0u256, ERAMMDepositStatus);

            assert!(ramm::get_lptokens_issued<BTC>(&ramm) == 0u256, ERAMMDepositStatus);
            assert!(ramm::get_typed_lptokens_issued<BTC>(&ramm) == 0u256, ERAMMDepositStatus);

            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<RAMM>(ramm);
            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
        };

        test_scenario::next_tx(scenario, ADMIN);

        test_scenario::end(scenario_val);
    }

    /// -----------------------
    /// `AdminCap` safety tests
    /// -----------------------

    /// Function to create two RAMMs with different accounts, and return their IDs for
    /// easier retrieval, along with the populated scenario.
    ///
    /// Useful for the tests below.
    fun double_create(): (ID, ID, test_scenario::Scenario) {
        let mut scenario_val = test_scenario::begin(ALICE);
        let scenario = &mut scenario_val;

        // Create first RAMM
        {
            ramm::new_ramm(ALICE, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, BOB);
        let alice_ramm_id = option::extract<ID>(&mut test_scenario::most_recent_id_shared<RAMM>());

        // Create second RAMM
        {
            ramm::new_ramm(BOB, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ADMIN);
        let bob_ramm_id = option::extract<ID>(&mut test_scenario::most_recent_id_shared<RAMM>());
        // Create test aggregator
        let _aggr_id = test_util::create_write_share_aggregator(scenario, 2780245000000, 8, false, 100);
        test_scenario::next_tx(scenario, ADMIN);

        (alice_ramm_id, bob_ramm_id, scenario_val)
    }

    #[test]
    #[expected_failure(abort_code = ramm::ENotAdmin)]
    /// Create two RAMMs whose `AdminCap`s belong to different users, and then
    /// attempt to add an asset to one using the other's `AdminCap`.
    ///
    /// This *must* fail.
    fun add_asset_mismatched_admin_cap() {
        let (_, bob_ramm_id, scenario_val) = double_create();
        let scenario = &scenario_val;

        {
            let mut bob_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, bob_ramm_id);
            let alice_admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ALICE);
            let alice_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ALICE);

            let btc_aggr = test_scenario::take_shared<Aggregator>(scenario);
            ramm::add_asset_to_ramm<BTC>(&mut bob_ramm, &btc_aggr, 0, btc_dec_places(), &alice_admin_cap, &alice_cap);

            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_to_address<RAMMAdminCap>(BOB, alice_admin_cap);
            test_scenario::return_to_address<RAMMNewAssetCap>(ALICE, alice_cap);
            test_scenario::return_shared<RAMM>(bob_ramm);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::EWrongNewAssetCap)]
    /// Create two RAMMs whose `NewAssetCap`s belong to different users, and then
    /// attempt to add an asset to one using the other's `NewAssetCap`.
    ///
    /// This *must* fail.
    fun add_asset_mismatched_new_asset_cap() {
        let (_, bob_ramm_id, scenario_val) = double_create();
        let scenario = &scenario_val;

        {
            let mut bob_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, bob_ramm_id);
            let bob_admin = test_scenario::take_from_address<RAMMAdminCap>(scenario, BOB);
            let alice_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ALICE);

            let btc_aggr = test_scenario::take_shared<Aggregator>(scenario);
            ramm::add_asset_to_ramm<BTC>(&mut bob_ramm, &btc_aggr, 0, btc_dec_places(), &bob_admin, &alice_cap);

            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_to_address<RAMMAdminCap>(BOB, bob_admin);
            test_scenario::return_to_address<RAMMNewAssetCap>(ALICE, alice_cap);
            test_scenario::return_shared<RAMM>(bob_ramm);
        };

        test_scenario::end(scenario_val);
    }

    /// Given a RAMM's object ID and the address of its `AdminCap` owner, add an asset to
    /// it.
    fun add_asset_to_ramm<Asset>(
        ramm_id: ID,
        sender: address,
        scenario: &mut test_scenario::Scenario
    ) {
        test_scenario::next_tx(scenario, sender);
        let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
        let admin = test_scenario::take_from_address<RAMMAdminCap>(scenario, sender);
        let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, sender);
        let aggr = test_scenario::take_shared<Aggregator>(scenario);

        ramm::add_asset_to_ramm<Asset>(&mut ramm, &aggr, 0, btc_dec_places(), &admin, &new_asset_cap);

        test_scenario::return_shared<Aggregator>(aggr);
        test_scenario::return_to_address<RAMMAdminCap>(sender, admin);
        test_scenario::return_to_address<RAMMNewAssetCap>(sender, new_asset_cap);
        test_scenario::return_shared<RAMM>(ramm);
        test_scenario::next_tx(scenario, sender);
    }

    /// Create two test RAMMs with different owners, and then add the same asset
    /// to both.
    fun double_add_asset<Asset>(): (ID, ID, test_scenario::Scenario) {
        let (alice_ramm_id, bob_ramm_id, mut scenario_val) = double_create();
        let scenario = &mut scenario_val;

        add_asset_to_ramm<Asset>(alice_ramm_id, ALICE, scenario);
        add_asset_to_ramm<Asset>(bob_ramm_id, BOB, scenario);

        (alice_ramm_id, bob_ramm_id, scenario_val)
    }

    #[test]
    #[expected_failure(abort_code = ramm::ENotAdmin)]
    /// After creating two RAMMs with different owners and adding an asset to both,
    /// attempt to initialize one with the other's `AdminCap`.
    ///
    /// This *must* fail.
    fun initialize_mismatch_admin_cap() {
        let (_alice_ramm_id, bob_ramm_id, scenario_val) = double_add_asset<BTC>();
        let scenario = &scenario_val;

        {
            let mut bob_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, bob_ramm_id);
            let alice_admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ALICE);
            let alice_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ALICE);

            ramm::initialize_ramm(&mut bob_ramm, &alice_admin_cap, alice_cap);

            test_scenario::return_to_address<RAMMAdminCap>(BOB, alice_admin_cap);
            test_scenario::return_shared<RAMM>(bob_ramm);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::EWrongNewAssetCap)]
    /// After creating two RAMMs with different owners and adding an asset to both,
    /// attempt to initialize one with the other's `AdminCap`.
    ///
    /// This *must* fail.
    fun initialize_mismatch_new_asset_cap() {
        let (_alice_ramm_id, bob_ramm_id, scenario_val) = double_add_asset<BTC>();
        let scenario = &scenario_val;

        {
            let mut bob_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, bob_ramm_id);
            let bob_admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, BOB);
            let alice_new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ALICE);

            ramm::initialize_ramm(&mut bob_ramm, &bob_admin_cap, alice_new_asset_cap);

            test_scenario::return_to_address<RAMMAdminCap>(BOB, bob_admin_cap);
            test_scenario::return_shared<RAMM>(bob_ramm);
        };

        test_scenario::end(scenario_val);
    }

    /// Given a RAMM's object ID and the address of its `AdminCap` owner, add an asset to
    /// it, and then initialize it.
    fun initialize_ramm(
        ramm_id: ID,
        sender: address,
        scenario: &mut test_scenario::Scenario
    ) {
        test_scenario::next_tx(scenario, sender);
        {
            let mut ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let admin = test_scenario::take_from_address<RAMMAdminCap>(scenario, sender);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, sender);
            ramm::initialize_ramm(&mut ramm, &admin, new_asset_cap);
            test_scenario::return_to_address<RAMMAdminCap>(sender, admin);
            test_scenario::return_shared<RAMM>(ramm);
        };
        test_scenario::next_tx(scenario, sender);
    }

    fun double_initialize<Asset>(): (ID, ID, test_scenario::Scenario) {
        let (alice_ramm_id, bob_ramm_id, mut scenario_val) = double_add_asset<Asset>();
        let scenario = &mut scenario_val;

        initialize_ramm(alice_ramm_id, ALICE, scenario);
        initialize_ramm(bob_ramm_id, BOB, scenario);

        (alice_ramm_id, bob_ramm_id, scenario_val)
    }

    #[test]
    #[expected_failure(abort_code = ramm::ENotAdmin)]
    /// Check that setting a new fee collecting address with the wrong `RAMMAdminCap` will fail.
    fun set_fee_collector_admin_cap_mismatch() {
        let (_alice_ramm_id, bob_ramm_id, scenario_val) = double_initialize<BTC>();
        let scenario = &scenario_val;
        {
            let mut bob_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, bob_ramm_id);
            let alice_admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ALICE);

            ramm::set_fee_collector(&mut bob_ramm, &alice_admin_cap, ALICE);

            test_scenario::return_to_address<RAMMAdminCap>(ALICE, alice_admin_cap);
            test_scenario::return_shared<RAMM>(bob_ramm);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::ENotAdmin)]
    /// Check that setting minimum trade amounts with the wrong `RAMMAdminCap` will fail.
    fun set_minimum_trade_amount_admin_cap_mismatch() {
        let (_alice_ramm_id, bob_ramm_id, scenario_val) = double_initialize<BTC>();
        let scenario = &scenario_val;
        {
            let mut bob_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, bob_ramm_id);
            let alice_admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ALICE);

            ramm::set_minimum_trade_amount<BTC>(&mut bob_ramm, &alice_admin_cap, 1);

            test_scenario::return_to_address<RAMMAdminCap>(ALICE, alice_admin_cap);
            test_scenario::return_shared<RAMM>(bob_ramm);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Check that setting minimum trade amounts works as intended.
    fun set_minimum_trade_amount_test() {
        let mut scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        let _aggr_id = test_util::create_write_share_aggregator(scenario, 2780245000000, 8, false, 100);
        test_scenario::next_tx(scenario, ADMIN);

        // Create the RAMM
        {
            ramm::new_ramm(ADMIN, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ADMIN);

        // Retrieve RAMM and caps from storage, and add above assets to it
        {
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ADMIN);
            let mut ramm = test_scenario::take_shared<RAMM>(scenario); 

            let btc_aggr = test_scenario::take_shared<Aggregator>(scenario);

            let minimum = 1000;
            ramm::add_asset_to_ramm<BTC>(
                &mut ramm,
                &btc_aggr,
                minimum,
                btc_dec_places(),
                &admin_cap,
                &new_asset_cap
            );

            ramm::initialize_ramm(&mut ramm, &admin_cap, new_asset_cap);

            test_utils::assert_eq(ramm::get_minimum_trade_amount<BTC>(&ramm), minimum);
            ramm::set_minimum_trade_amount<BTC>(&mut ramm, &admin_cap, 2000);
            test_utils::assert_eq(ramm::get_minimum_trade_amount<BTC>(&ramm), 2000);

            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<RAMM>(ramm);
        };

        test_scenario::next_tx(scenario, ADMIN);

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Check that changing the fee collection address works as intended.
    fun set_fee_collector_test() {
        let mut scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        // Create the RAMM
        {
            ramm::new_ramm(ADMIN, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ADMIN);

        // Retrieve RAMM and caps from storage, and add above assets to it
        {
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);

            test_utils::assert_eq(ramm::get_fee_collector(&ramm), ADMIN);
            ramm::set_fee_collector(&mut ramm, &admin_cap, ALICE);
            test_utils::assert_eq(ramm::get_fee_collector(&ramm), ALICE);

            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
            test_scenario::return_shared<RAMM>(ramm);
        };

        test_scenario::next_tx(scenario, ADMIN);

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::ENotAdmin)]
    /// Check that enabling deposits for an asset with the wrong `RAMMAdminCap` will fail.
    fun enable_deposits_admin_cap_mismatch() {
        let (_alice_ramm_id, bob_ramm_id, scenario_val) = double_initialize<BTC>();
        let scenario = &scenario_val;
        {
            let mut bob_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, bob_ramm_id);
            let alice_admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ALICE);

            ramm::enable_deposits<BTC>(&mut bob_ramm, &alice_admin_cap);

            test_scenario::return_to_address<RAMMAdminCap>(ALICE, alice_admin_cap);
            test_scenario::return_shared<RAMM>(bob_ramm);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = ramm::ENotAdmin)]
    /// Check that disabling deposits for an asset with the wrong `RAMMAdminCap` will fail.
    fun disable_deposits_admin_cap_mismatch() {
        let (_alice_ramm_id, bob_ramm_id, scenario_val) = double_initialize<BTC>();
        let scenario = &scenario_val;
        {
            let mut bob_ramm = test_scenario::take_shared_by_id<RAMM>(scenario, bob_ramm_id);
            let alice_admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ALICE);

            ramm::disable_deposits<BTC>(&mut bob_ramm, &alice_admin_cap);

            test_scenario::return_to_address<RAMMAdminCap>(ALICE, alice_admin_cap);
            test_scenario::return_shared<RAMM>(bob_ramm);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Check that setting (enabling/disabling) deposit status works as intended.
    fun set_deposit_status_test() {
        let mut scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        let _aggr_id = test_util::create_write_share_aggregator(scenario, 2780245000000, 8, false, 100);
        test_scenario::next_tx(scenario, ADMIN);

        // Create the RAMM
        {
            ramm::new_ramm(ADMIN, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ADMIN);

        // Retrieve RAMM and caps from storage, and add above assets to it
        {
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ADMIN);
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);

            let btc_aggr = test_scenario::take_shared<Aggregator>(scenario);

            ramm::add_asset_to_ramm<BTC>(
                &mut ramm,
                &btc_aggr,
                1000,
                btc_dec_places(),
                &admin_cap,
                &new_asset_cap
            );

            ramm::initialize_ramm(&mut ramm, &admin_cap, new_asset_cap);

            test_utils::assert_eq(ramm::get_deposit_status<BTC>(&ramm), true);
            ramm::disable_deposits<BTC>(&mut ramm, &admin_cap);
            test_utils::assert_eq(ramm::get_deposit_status<BTC>(&ramm), false);
            ramm::enable_deposits<BTC>(&mut ramm, &admin_cap);
            test_utils::assert_eq(ramm::get_deposit_status<BTC>(&ramm), true);

            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<RAMM>(ramm);
        };

        test_scenario::next_tx(scenario, ADMIN);

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Check that setting a new address of an `Aggregator` works as intended.
    fun set_aggregator_address_test() {
        let mut scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        let fst_aggr_addr: address =
                object::id_to_address(
                    &test_util::create_write_share_aggregator(scenario, 2780245000000, 8, false, 100)
                );
        let snd_aggr_addr: address =
            object::id_to_address(
                &test_util::create_write_share_aggregator(scenario, 5, 8, false, 100)
            );

        test_scenario::next_tx(scenario, ADMIN);

        // Create the RAMM
        {
            ramm::new_ramm(ADMIN, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, ADMIN);

        // Retrieve RAMM and caps from storage, and add above assets to it
        {
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);
            let new_asset_cap = test_scenario::take_from_address<RAMMNewAssetCap>(scenario, ADMIN);
            let mut ramm = test_scenario::take_shared<RAMM>(scenario);

            // Add the asset with the address of the first created aggregator.
            let btc_aggr = test_scenario::take_shared_by_id<Aggregator>(scenario, object::id_from_address(fst_aggr_addr));

            ramm::add_asset_to_ramm<BTC>(
                &mut ramm,
                &btc_aggr,
                1000,
                btc_dec_places(),
                &admin_cap,
                &new_asset_cap
            );

            test_utils::assert_eq(ramm::get_aggregator_address<BTC>(&ramm), fst_aggr_addr);
            ramm::set_aggregator_address<BTC>(&mut ramm, &admin_cap, snd_aggr_addr);
            test_utils::assert_eq(ramm::get_aggregator_address<BTC>(&ramm), snd_aggr_addr);

            test_scenario::return_to_address<RAMMAdminCap>(ADMIN, admin_cap);
            test_scenario::return_to_address<RAMMNewAssetCap>(ADMIN, new_asset_cap);
            test_scenario::return_shared<Aggregator>(btc_aggr);
            test_scenario::return_shared<RAMM>(ramm);
        };

        test_scenario::next_tx(scenario, ADMIN);

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Check that emitting an event with a pool's state works.
    fun get_pool_state_test() {
        let (ramm_id, _, _, _, mut scenario_val) = test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ALICE);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);

            ramm::get_pool_state(&ramm, test_scenario::ctx(scenario));

            test_scenario::return_shared<RAMM>(ramm);
        };

        let tx_fx: TransactionEffects = test_scenario::next_tx(scenario, ALICE);
        // Verify that one user event was emitted - the pool state query.
        //
        // The Sui Move test framework does not currently allow inspection of a tx's emitted
        // events, but simply verifying an event was emitted would have prevented a past bug:
        //
        // * due to an infinite loop in `get_pool_state`, the function never terminated, and
        // no event was ever emitted due to transaction execution failure over exhausted resources.
        test_utils::assert_eq(test_scenario::num_user_events(&tx_fx), 1);

        test_scenario::end(scenario_val);
    }

    #[test]
    /// Check that 3-asset RAMM deletion works as intended.
    fun delete_ramm_3_test() {
        let (ramm_id, _, _, _, mut scenario_val) = test_util::create_ramm_test_scenario_eth_matic_usdt(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ADMIN);

        {
            let ramm = test_scenario::take_shared_by_id<RAMM>(scenario, ramm_id);
            let admin_cap = test_scenario::take_from_address<RAMMAdminCap>(scenario, ADMIN);

            ramm.delete_ramm_3<ETH, MATIC, USDT>(admin_cap, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, ADMIN);

        let eth_amnt: u64 = 200 * (test_util::eth_factor() as u64);
        let matic_amnt: u64 = 200_000 * (test_util::matic_factor() as u64);
        let usdt_amnt: u64 = 400_000 * (test_util::usdt_factor() as u64);

        {
            // First, check that the RAMM's funds have been returned to the admin, as it was
            // the only liquidity depositor in this scenario.
            let eth = test_scenario::take_from_address<Coin<ETH>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&eth), eth_amnt);

            let matic = test_scenario::take_from_address<Coin<MATIC>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&matic), matic_amnt);

            let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, ADMIN);
            test_utils::assert_eq(coin::value(&usdt), usdt_amnt);

            test_scenario::return_to_address(ADMIN, eth);
            test_scenario::return_to_address(ADMIN, matic);
            test_scenario::return_to_address(ADMIN, usdt);

            // Next, verify that each of the asset's `Supply<LP<T>>` object was safely returned to
            // the admin.
            let mut supply_bag = test_scenario::take_from_address<LPTSupplyBag>(scenario, ADMIN);
            assert!(ramm::get_supply_obj_count(&supply_bag) == THREE, ERAMMFailedDeletion);

            let eth_supply: &mut Supply<LP<ETH>> = supply_bag.get_supply<ETH>();
            assert!(eth_supply.supply_value() == eth_amnt, ERAMMFailedDeletion);

            let matic_supply: &mut Supply<LP<MATIC>> = supply_bag.get_supply<MATIC>();
            assert!(matic_supply.supply_value() == matic_amnt, ERAMMFailedDeletion);

            let usdt_supply: &mut Supply<LP<USDT>> = supply_bag.get_supply<USDT>();
            assert!(usdt_supply.supply_value() == usdt_amnt, ERAMMFailedDeletion);

            test_scenario::return_to_address(ADMIN, supply_bag);

            // Lastly, check that the RAMM and its admin cap have been deleted.
            assert!(!test_scenario::has_most_recent_shared<RAMM>(), ERAMMFailedDeletion);
            assert!(!test_scenario::has_most_recent_for_address<RAMMAdminCap>(ADMIN), ERAMMFailedDeletion);
        };

        test_scenario::end(scenario_val);
    }
}