use std::{env, path::PathBuf, process::ExitCode};

use shared_crypto::intent::Intent;
use sui_json_rpc_types::{
    OwnedObjectRef, SuiObjectDataOptions, SuiTransactionBlockEffectsAPI,
    SuiTransactionBlockResponseOptions,
};
use sui_keys::keystore::AccountKeystore;
use sui_types::{
    base_types::{MoveObjectType, ObjectID, ObjectType, SuiAddress},
    object::Owner,
    programmable_transaction_builder::ProgrammableTransactionBuilder,
    quorum_driver_types::ExecuteTransactionRequestType,
    transaction::{Argument, ObjectArg, ProgrammableTransaction, Transaction, TransactionData},
    Identifier, TypeTag,
};

use ramm_sui_deploy::{
    deployment_cfg_from_args, get_keystore, get_suibase_and_sui_client, new_ramm_tx_runner,
    publish_ramm_pkg_runner,
    types::{AssetConfig, RAMMPkgAddrSrc},
    user_assent_interaction, UserAssent, build_aggr_obj_args,
};

/// Gas budget for the PTB that will add assets to the RAMM, and initialize it.
const RAMM_PTB_GAS_BUDGET: u64 = 100_000_000;

#[tokio::main]
async fn main() -> ExitCode {
    /*
    RAMM deployment config parsing
    */
    let args = &mut env::args_os();
    let exec_name: PathBuf = PathBuf::from(args.next().unwrap());
    println!("Process name: {}", exec_name.display());

    let dplymt_cfg = match deployment_cfg_from_args(args) {
        Err(err) => {
            eprintln!("{}", err);
            return ExitCode::from(1);
        }
        Ok(ok) => ok,
    };

    // Show deployment cfg to user, and ask them to confirm information.
    // If user rejects, end the program.
    if let UserAssent::Rejected = user_assent_interaction(&dplymt_cfg) {
        return ExitCode::from(0);
    }

    /*
    Sui client creation, with the help of `suibase` for network selection
    */
    let (suibase, sui_client) = match get_suibase_and_sui_client(&dplymt_cfg.target_env).await {
        Err(err) => {
            eprintln!("{}", err);
            return ExitCode::from(1);
        }
        Ok(pair) => pair,
    };

    // Fetch the sui client's active address, to use it for publishing
    let client_address: SuiAddress = match suibase.client_sui_address("active") {
        Ok(adr) => adr,
        Err(err) => {
            eprintln!(
                "Failed to fetch the active address for the Sui client: {:?}",
                err
            );
            return ExitCode::from(1);
        }
    };
    println!(
        "Using address {} to publish the RAMM package.",
        client_address
    );

    let keystore = match get_keystore(&suibase) {
        Err(err) => {
            eprintln!("{}", err);
            return ExitCode::from(1);
        }
        Ok(a) => a,
    };

    /*
    Building the RAMM package
    */

    let ramm_package_id = match &dplymt_cfg.ramm_pkg_addr_or_path {
        // RAMM package address provided in TOML
        RAMMPkgAddrSrc::FromTomlConfig(addr) => {
            println!("RAMM library package ID read from TOML config.");
            *addr
        }
        // RAMM package must be published to get a new package ID
        RAMMPkgAddrSrc::FromPkgPublication(path) => {
            println!(
                "RAMM library package ID to be obtained from publication of package at path {:?}",
                path.as_os_str()
            );
            let response = match publish_ramm_pkg_runner(
                &sui_client,
                &keystore,
                path.to_path_buf(),
                &client_address,
            )
            .await
            {
                Err(err) => {
                    eprintln!("{}", err);
                    return ExitCode::from(1);
                }
                Ok(r) => r,
            };
            println!(
                "Status of RAMM library publication tx: {:?}",
                response.status_ok()
            );

            // Get the package's ID from the tx response.
            let ramm_package_id: ObjectID = response
                .effects
                .expect("Publish Tx *should* result in non-empty effects")
                .created()
                .into_iter()
                .filter(|oor|  Owner::is_immutable(&oor.owner))
                .collect::<Vec<&OwnedObjectRef>>()
                .first()
                .expect("Publish Tx *should* result in at least 1 immutable object, i.e. the published package")
                .reference
                .object_id;
            ramm_package_id
        }
    };
    println!("RAMM package ID: {ramm_package_id}");

    /*
    Create the RAMM, and then use the SDK to get the IDs of the admin and new asset caps.

    It is also necessary to query the network for each asset's `Aggregator`, to construct
    a `sui_types::ObjectArg` for use in the PTB.
    */

    // Construct the non-PTB tx to create the RAMM and associated capability objects, and then
    // sign, submit and await it
    let response = match new_ramm_tx_runner(
        &sui_client,
        &dplymt_cfg,
        &keystore,
        &client_address,
        ramm_package_id,
    )
    .await
    {
        Err(err) => {
            eprintln!("{}", err);
            return ExitCode::from(1);
        }
        Ok(r) => r,
    };
    println!("Status of RAMM creation tx: {:?}", response.status_ok());

    // Collect the RAMM object from the tx response
    let owned_obj_refs = response
        .effects
        .as_ref()
        .expect("RAMM creation tx *should* result in non-empty effects")
        .created()
        .into_iter()
        .filter(|oor| oor.owner.is_shared())
        .collect::<Vec<_>>();
    let ramm_owned_obj_ref = owned_obj_refs
        .first()
        .expect("The RAMM creation should result in *exactly* 1 new shared object");
    // The above `sui_json_rpc_types::OwnedObjectRef` must be converted into a
    // `sui_types::ObjectArg`, for use in a PTB later.
    let ramm_obj_seq_num = match ramm_owned_obj_ref.owner {
        Owner::Shared {
            initial_shared_version,
        } => initial_shared_version,
        _ => {
            eprintln!("RAMM OwnedObjectRef::owner supposed to be shared!");
            return ExitCode::from(1);
        }
    };
    let ramm_obj_arg = ObjectArg::SharedObject {
        id: ramm_owned_obj_ref.object_id(),
        initial_shared_version: ramm_obj_seq_num,
        // Recall that
        // 1. to add assets to the RAMM, and
        // 2. initialize it
        // it must be passed in as `ramm: &mut RAMM`, so the below must be set to true.
        mutable: true,
    };

/*
    Disambiguate between created capability objects

    This is needed because when using regular transactions, the only information gleanable
    from the transaction response are created, mutated and deleted object IDs.
    
    Doing this, it is possible to get the object IDs of both
    a. the RAMM's admin capability
    b. the RAMM's new asset capability
    but not to tell which is which.
*/

    // `ObjectArg`s of both the admin cap, and the new asset cap
    let cap_obj_args: Vec<ObjectArg> = response
        .effects
        .expect("RAMM creation tx *should* result in non-empty effects")
        .created()
        .into_iter()
        // the ramm creation tx should have created 2 objects owned by the tx sender
        .filter(|oor| oor.owner == client_address)
        .map(|oor| match oor.owner {
            Owner::AddressOwner(addr) => {
                assert!(addr == client_address);
                ObjectArg::ImmOrOwnedObject((oor.object_id(), oor.version(), oor.reference.digest))
            }
            _ => {
                panic!("RAMM Cap OwnedObjectRef::owner supposed to be AddressOwner!")
            }
        })
        .collect::<Vec<_>>();
    assert!(cap_obj_args.len() == 2);

    // To tell both capability objects apart, the below must be done:
    // 1. Use the SDK to query the network on one of the two object IDs in the RAMM creation
    //      response
    let cap_object = match sui_client
        .read_api()
        .get_object_with_options(
            cap_obj_args[0].id(),
            SuiObjectDataOptions::new().with_type(),
        )
        .await
    {
        Ok(o) => o,
        Err(err) => {
            eprintln!("Failed to fetch cap object data. Node response: {}", err);
            return ExitCode::from(1);
        }
    };
    // 2. Extract the type from the queried object's information
    let cap_obj_ty = cap_object.object().unwrap().object_type().unwrap();
    let cap_move_obj_ty: MoveObjectType = match cap_obj_ty {
        ObjectType::Package => {
            panic!("Type of cap object is `ObjectType::Package`: not supposed to happen!")
        }
        ObjectType::Struct(mot) => mot,
    };

    // 3. Pattern match on the type, and assign `ObjectID`s to be used in the later PTB
    let (admin_cap_obj_arg, new_asset_cap_obj_arg): (ObjectArg, ObjectArg) =
        match cap_move_obj_ty.name().as_str() {
            "RAMMAdminCap" => (cap_obj_args[0], cap_obj_args[1]),
            "RAMMNewAssetCap" => (cap_obj_args[1], cap_obj_args[0]),
            _ => panic!("`MoveObjectType` must be of either capability: not supposed to happen!"),
        };

    println!("RAMM: {:?}", ramm_obj_arg);
    println!("Admin cap : {:?}", admin_cap_obj_arg);
    println!("New asset cap: {:?}", new_asset_cap_obj_arg);

    // For each asset's aggregator address read from the TOML, use the `SuiClient`'s `ReadApi`
    // to query its `SuiObjectData`, and then use that to build an `ObjectArg` for use in the PTB.
    let aggr_obj_args = match build_aggr_obj_args(&sui_client, &dplymt_cfg).await {
        Err(err) => {
            eprintln!("{}", err);
            return ExitCode::from(1);
        }
        Ok(a) => a,
    };
    
    /*
    Constructing the PTB that will populate and initialize the RAMM
    */

    // 1. Find the coin object to be used as gas for the PTB
    let coins = match sui_client
        .coin_read_api()
        .get_coins(client_address, None, None, None)
        .await
    {
        Err(err) => {
            eprintln!(
                "Failed to fetch coin object from active address to pay for PTB. Error: {}",
                err
            );
            return ExitCode::from(1);
        }
        Ok(c) => c,
    };
    let coin = coins.data.into_iter().next().unwrap();
    let gas_price = match sui_client.read_api().get_reference_gas_price().await {
        Err(err) => {
            eprintln!("Failed to fetch gas price for the PTB. Error: {}", err);
            return ExitCode::from(1);
        }
        Ok(g) => g,
    };

    // 2. Build the PTB object via the `sui-sdk` builder API
    let mut ptb = ProgrammableTransactionBuilder::new();
    let ramm_arg: Argument = ptb.obj(ramm_obj_arg).unwrap();
    // Add the cap objects as inputs to the PTB. Recall: inputs to PTBs are added before it is
    // built, and accessible to all subsequent commands.
    let admin_cap_arg: Argument = ptb.obj(admin_cap_obj_arg).unwrap();
    let new_asset_cap_arg: Argument = ptb.obj(new_asset_cap_obj_arg).unwrap();

    /*
    Create PTB to perform the following actions:
    1. Add assets specified in the RAMM deployment config
    2. Initialize it
    */

    // Add all of the assets specified in the TOML config
    for ix in 0..(dplymt_cfg.asset_count as usize) {
        // `N`-th asset to be added to the RAMM
        let asset_data: &AssetConfig = &dplymt_cfg.assets[ix];
        let aggr_arg = ptb.obj(aggr_obj_args[ix]).unwrap();

        // Arguments for the `add_asset_to_ramm` Move call
        let move_call_args: Vec<Argument> = vec![
            ramm_arg,
            aggr_arg,
            ptb.pure(asset_data.minimum_trade_amount).unwrap(),
            ptb.pure(asset_data.decimal_places).unwrap(),
            admin_cap_arg,
            new_asset_cap_arg,
        ];

        // Type argument to the `add_asset_to_ramm` Move call
        let asset_type_tag: TypeTag = asset_data.asset_type.clone();

        ptb.programmable_move_call(
            ramm_package_id,
            ramm_sui_deploy::RAMM_MODULE_NAME.to_owned(),
            Identifier::new("add_asset_to_ramm").unwrap(),
            vec![asset_type_tag],
            move_call_args,
        );
    }

    // Initialize the RAMM
    ptb.programmable_move_call(
        ramm_package_id,
        ramm_sui_deploy::RAMM_MODULE_NAME.to_owned(),
        Identifier::new("initialize_ramm").unwrap(),
        vec![],
        vec![ramm_arg, admin_cap_arg, new_asset_cap_arg],
    );

    // 3. Finalize the PTB object
    let pt: ProgrammableTransaction = ptb.finish();

    // 4. Convert PTB into tx data to be signed and sent to the network for execution
    let ptx_data = TransactionData::new_programmable(
        client_address,
        vec![coin.object_ref()],
        pt,
        RAMM_PTB_GAS_BUDGET,
        gas_price,
    );

    // 4.1 Sign the tx data with the same key used to publish the package and create the RAMM
    let signature =
        match keystore.sign_secure(&client_address, &ptx_data, Intent::sui_transaction()) {
            Ok(sig) => sig,
            Err(err) => {
                eprintln!("Failed to sign PTx: {:?}", err);
                return ExitCode::from(1);
            }
        };
    println!("Successfully signed PTx");

    // 4.2 Submit the tx to the network, and await execution result
    println!("\nExecuting the PTB\n");
    match sui_client
        .quorum_driver_api()
        .execute_transaction_block(
            Transaction::from_data(ptx_data, Intent::sui_transaction(), vec![signature]),
            SuiTransactionBlockResponseOptions::full_content(),
            Some(ExecuteTransactionRequestType::WaitForLocalExecution),
        )
        .await
    {
        Err(err) => {
            eprintln!("Programmable transaction failed with: {:?}", err);
            return ExitCode::from(1);
        }
        Ok(r) => println!("PTB response status: {:?}", r.status_ok()),
    };

    // Success, exit
    ExitCode::SUCCESS
}
