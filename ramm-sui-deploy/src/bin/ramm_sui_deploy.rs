use std::{env, path::PathBuf};

use sui_types::base_types::{ObjectID, SuiAddress};

use ramm_sui_deploy::{self, error::RAMMDeploymentError, types::{RAMMPkgAddrSrc, RAMMDeploymentConfig}, util, UserAssent, RAMMObjectIDs};

async fn ramm_deployment(dplymt_cfg: RAMMDeploymentConfig) -> Result<RAMMObjectIDs, RAMMDeploymentError> {
    /*
    Sui client creation, with the help of `suibase` for network selection
    */
    let (suibase, sui_client) =
        ramm_sui_deploy::get_suibase_and_sui_client(&dplymt_cfg.target_env).await?;

    // Fetch the sui client's active address, to use it for publishing
    let client_address: SuiAddress = suibase
        .client_sui_address("active")
        .map_err(RAMMDeploymentError::SuiClientActiveAddressError)?;
    log::info!(
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
            log::info!("RAMM library package ID read from TOML config.");
            *addr
        }
        // RAMM package must be published to get a new package ID
        RAMMPkgAddrSrc::FromPkgPublication(path) => {
            log::info!(
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

            log::info!(
                "Status of RAMM library publication tx: {:?}",
                response.status_ok()
            );

            // Get the package's ID from the tx response.
            let ramm_package_id: ObjectID = ramm_sui_deploy::get_ramm_id_from_tx_response(response);
            ramm_package_id
        }
    };
    log::info!("RAMM package ID: {ramm_package_id}");

    // The response from the tx that creates the RAMM.
    let new_ramm_tx_response = ramm_sui_deploy::new_ramm_tx_runner(
        &sui_client,
        &dplymt_cfg,
        &keystore,
        &client_address,
        ramm_package_id,
    )
    .await?;
    log::info!(
        "Status of RAMM creation tx: {:?}",
        new_ramm_tx_response.status_ok()
    );

    /*
    The RAMM and its capabilities, extracted from the tx response, and represented as
    ObjectArg`s, which is the SDK's representation of Move objects.

    Also returned are the IDs of those objects, to display to the user at the end of the program.
    */
    let (ramm_obj_args, ramm_obj_ids) =
        ramm_sui_deploy::build_ramm_obj_args(&sui_client, new_ramm_tx_response, client_address)
            .await?;

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

    log::info!("PTB response status: {:?}", ptb_response.status_ok());

    Ok(ramm_obj_ids)
}

#[tokio::main]
async fn main() {
    /*
    Logging infrastructure initialization
    */
    if let Err(err) = util::init_logging_infrastructure(None,log::LevelFilter::Info) {
        eprintln!("Failed to initialize logging infrastructure: {}", err);
        return ();
    }

    /*
    RAMM deployment config parsing
    */
    let args = &mut env::args_os();
    let exec_name: PathBuf = PathBuf::from(args.next().unwrap());
    log::info!("Process name: {}", exec_name.display());

    let dplymt_cfg = match ramm_sui_deploy::deployment_cfg_from_args(args) {
        Ok(dplymt_cfg) => dplymt_cfg,
        Err(e) => {
            log::error!("Error reading the TOML config file into a `String`: {}", e);
            return ();
        }
    };

    // Show deployment cfg to user, and ask them to confirm information.
    // If user rejects, end the program.
    match ramm_sui_deploy::user_assent_interaction(&dplymt_cfg) {
        UserAssent::Rejected => {
            log::info!("User rejected the parsed configuration. Exiting.");
            return ();
        },
        UserAssent::Accepted => {
            log::info!("User accepted the parsed configuration. Continuing with deployment.");
        }
        
    }

    let ramm_ids = ramm_deployment(dplymt_cfg).await;
    match ramm_ids {
        Ok(ramm_ids) => {
            println!("Success!");
            println!("These are the IDs of the generated objects:\n{}", ramm_ids);
        },
        Err(e) => {
            log::error!("RAMM deployment error: {}", e);
        }
    }
}