use std::{env, path::PathBuf};

use sui_types::base_types::{ObjectID, SuiAddress};

use ramm_sui_deploy::{self, error::RAMMDeploymentError, types::RAMMPkgAddrSrc, UserAssent};

#[tokio::main]
async fn main() -> Result<(), RAMMDeploymentError> {
    /*
    RAMM deployment config parsing
    */
    let args = &mut env::args_os();
    let exec_name: PathBuf = PathBuf::from(args.next().unwrap());
    println!("Process name: {}", exec_name.display());

    let dplymt_cfg = ramm_sui_deploy::deployment_cfg_from_args(args)?;

    // Show deployment cfg to user, and ask them to confirm information.
    // If user rejects, end the program.
    if let UserAssent::Rejected = ramm_sui_deploy::user_assent_interaction(&dplymt_cfg) {
        return Ok(());
    }

    /*
    Sui client creation, with the help of `suibase` for network selection
    */
    let (suibase, sui_client) =
        ramm_sui_deploy::get_suibase_and_sui_client(&dplymt_cfg.target_env).await?;

    // Fetch the sui client's active address, to use it for publishing
    let client_address: SuiAddress = suibase
        .client_sui_address("active")
        .map_err(RAMMDeploymentError::SuiClientActiveAddressError)?;
    println!(
        "Using address {} for publishing and deployment.",
        client_address
    );

    let keystore = ramm_sui_deploy::get_keystore(&suibase)?;

    /*
    Obtaining the RAMM package ID, either from the TOML config or from publishing the package.
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
            let response = ramm_sui_deploy::publish_ramm_pkg_runner(
                &sui_client,
                &keystore,
                path.to_path_buf(),
                &client_address,
            )
            .await?;

            println!(
                "Status of RAMM library publication tx: {:?}",
                response.status_ok()
            );

            // Get the package's ID from the tx response.
            let ramm_package_id: ObjectID = ramm_sui_deploy::get_ramm_id_from_tx_response(response);
            ramm_package_id
        }
    };
    println!("RAMM package ID: {ramm_package_id}");

    // The response from the tx that creates the RAMM.
    let new_ramm_tx_response = ramm_sui_deploy::new_ramm_tx_runner(
        &sui_client,
        &dplymt_cfg,
        &keystore,
        &client_address,
        ramm_package_id,
    )
    .await?;
    println!(
        "Status of RAMM creation tx: {:?}",
        new_ramm_tx_response.status_ok()
    );

    /*
    The RAMM and its capabilities, extracted from the tx response, and represented as
    ObjectArg`s, which is the SDK's representation of Move objects.
    */
    let ramm_obj_args =
        ramm_sui_deploy::build_ramm_obj_args(&sui_client, new_ramm_tx_response, client_address)
            .await?;

    println!("RAMM: {:?}", ramm_obj_args.ramm);
    println!("Admin cap : {:?}", ramm_obj_args.admin_cap);
    println!("New asset cap: {:?}", ramm_obj_args.new_asset_cap);

    /*
    For each asset's aggregator address read from the TOML, use the `SuiClient`'s `ReadApi`
    to query its `SuiObjectData`, and then use that to build an `ObjectArg` for use in the PTB.
    */
    let aggr_obj_args = ramm_sui_deploy::build_aggr_obj_args(&sui_client, &dplymt_cfg).await?;

    /*
    Construct the PTB that will populate and initialize the RAMM.
    Note that a PTB requires a coin and the network's current gas price, which have to be obtained
    as part of the process.
    */
    let ptb_response = ramm_sui_deploy::add_assets_and_init_ramm_runner(
        &sui_client,
        &keystore,
        &dplymt_cfg,
        client_address,
        ramm_package_id,
        ramm_obj_args,
        aggr_obj_args,
    )
    .await?;

    println!("PTB response status: {:?}", ptb_response.status_ok());

    Ok(())
}
