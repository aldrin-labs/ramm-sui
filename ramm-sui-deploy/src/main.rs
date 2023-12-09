use std::{env, path::PathBuf, process::ExitCode};

use sui_json_rpc_types::{OwnedObjectRef, SuiTransactionBlockEffectsAPI};
use sui_types::{
    base_types::{ObjectID, SuiAddress},
    object::Owner,
};

use ramm_sui_deploy::{
    add_assets_and_init_ramm_runner, build_aggr_obj_args, build_ramm_obj_args,
    deployment_cfg_from_args, get_keystore, get_suibase_and_sui_client, new_ramm_tx_runner,
    publish_ramm_pkg_runner, types::RAMMPkgAddrSrc, user_assent_interaction, UserAssent,
};

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
                .filter(|oor| Owner::is_immutable(&oor.owner))
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
    Create the RAMM through a non-PTB tx, and then use the SDK to extract the created Move objects:
    * the shared RAMM object,
    * the admin capability, and
    * the new asset capability.
    */
    let new_ramm_tx_response = match new_ramm_tx_runner(
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
    println!(
        "Status of RAMM creation tx: {:?}",
        new_ramm_tx_response.status_ok()
    );

    let ramm_obj_args =
        match build_ramm_obj_args(&sui_client, new_ramm_tx_response, client_address).await {
            Err(err) => {
                eprintln!("{}", err);
                return ExitCode::from(1);
            }
            Ok(a) => a,
        };

    println!("RAMM: {:?}", ramm_obj_args.ramm);
    println!("Admin cap : {:?}", ramm_obj_args.admin_cap);
    println!("New asset cap: {:?}", ramm_obj_args.new_asset_cap);

    /*
    For each asset's aggregator address read from the TOML, use the `SuiClient`'s `ReadApi`
    to query its `SuiObjectData`, and then use that to build an `ObjectArg` for use in the PTB.
    */

    let aggr_obj_args = match build_aggr_obj_args(&sui_client, &dplymt_cfg).await {
        Err(err) => {
            eprintln!("{}", err);
            return ExitCode::from(1);
        }
        Ok(a) => a,
    };

    /*
    Construct the PTB that will populate and initialize the RAMM.
    Note that a PTB requires a coin and the network's current gas price, which have to be obtained
    as part of the process.
    */
    match add_assets_and_init_ramm_runner(
        &sui_client,
        &keystore,
        &dplymt_cfg,
        client_address,
        ramm_package_id,
        ramm_obj_args,
        aggr_obj_args,
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
