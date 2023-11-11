use std::{default::Default, env, fs, path::PathBuf, process::ExitCode};

use shared_crypto::intent::Intent;

use suibase::Helper;

use sui_json_rpc_types::SuiTransactionBlockResponseOptions;
use sui_keys::keystore::{AccountKeystore, FileBasedKeystore, Keystore};
use sui_move_build::{CompiledPackage, BuildConfig};
use sui_sdk::SuiClientBuilder;
use sui_types::{
    base_types::ObjectID,
    transaction::Transaction,
    quorum_driver_types::ExecuteTransactionRequestType
};

use ramm_sui_deploy::RAMMDeploymentConfig;

/// This represents the gas budget (in MIST units, where 10^9 MIST is 1 SUI) to be used
/// when publishing the RAMM package.
///
/// Publishing it in the testnet in mid/late 2023 cost roughly 0.7 SUI, on average.
const PACKAGE_PUBLICATION_GAS_BUDGET: u64 = 1_000_000_000;


#[tokio::main]
async fn main() -> ExitCode {
    /*
    RAMM deployment config parsing
    */

    let args = &mut env::args();
    let exec_name: PathBuf = PathBuf::from(args.next().unwrap());
    println!("Process name: {}", exec_name.display());
    let config_path: PathBuf = match args.next() {
        None => {
            println!("No TOML config provided; exiting.");
            return ExitCode::from(0)
        },
        Some(s) => PathBuf::from(s),
    };
    let config_string: String = match fs::read_to_string(config_path) {
        Err(err) => {
            eprintln!("Could not parse config file into `String`: {:?}", err);
            return ExitCode::from(1)
        },
        Ok(str) => str,
    };

    let config: RAMMDeploymentConfig= match toml::from_str(&config_string) {
        Ok(cfg) => cfg,
        Err(err) => {
            eprintln!("Could not parse config file into `String`: {err}");
            return ExitCode::from(1)
        }
    };
    println!("Using deployment config:\n{}", config);

    /*
    Sui client creation, with the help of `suibase` for network selection
    */

    let suibase = Helper::new();
    match suibase.select_workdir("active") {
        Ok(_) => {},
        Err(err) => {
            eprintln!("Failure to select workdir: {}", err);
            return ExitCode::from(1)
        }
    }
    match suibase.workdir() {
        Ok(workdir) => println!("Using suibase workdir [{}]", workdir),
        Err(err) => {
            eprintln!("Failed to fetch current workdir: {:?}", err);
            return ExitCode::from(1)
        }
    }
    let rpc_url = match suibase.rpc_url() {
        Ok(ru) => ru,
        Err(err) => {
            eprintln!("Failed to fetch current RPC URL: {:?}", err);
            return ExitCode::from(1)
        }
    };
    let sui_client = match SuiClientBuilder::default().build(rpc_url).await {
        Ok(cl) => cl,
        Err(err) => {
            eprintln!("Failed to build Sui client from RPC URL: {:?}", err);
            return ExitCode::from(1)
        }
    };

    /*
    Building the RAMM package
    */

    let build_config: BuildConfig = Default::default();
    let ramm_package_path: PathBuf = PathBuf::from("../ramm-sui");
    // NOTE: hardcoded package path for now, will change this as needed
    let compiled_ramm_package: CompiledPackage = match build_config.build(ramm_package_path.clone()) {
        Ok(cp) => {
            println!("Successfully compiled the RAMM Move package located at {:?}", ramm_package_path);
            cp
        },
        Err(err) => {
            eprintln!("Failed to compile RAMM Move package: {:?}", err);
            return ExitCode::from(1)
        }
    };
    let ramm_compiled_modules: Vec<Vec<u8>> =
        compiled_ramm_package.get_package_bytes(/* with_unpublished_deps */ false);
    let ramm_dep_ids: Vec<ObjectID> = compiled_ramm_package.dependency_ids.published.values().cloned().collect();

    /*
    Publishing the compiled Move RAMM package
    */

    let client_address = match suibase.client_sui_address("active") {
        Ok(adr) => {
            println!("Using address {} to publish the RAMM package.", adr);
            adr
        },
        Err(err) => {
            eprintln!("Failed to fetch the active address for the Sui client: {:?}", err);
            return ExitCode::from(1)
        }
    };

    let publish_tx = match sui_client
        .transaction_builder()
        .publish(
            client_address,
            ramm_compiled_modules,
            ramm_dep_ids,
            // Recall that choosing `None` allows the client to choose a gas object instead of
            // the user.
            None,
            PACKAGE_PUBLICATION_GAS_BUDGET
        )
        .await {
            Ok(tx) => tx,
            Err(err) => {
                eprintln!("Failed to publish the RAMM package: {:?}", err);
                return ExitCode::from(1)
            }
        };

    // Get the keystore using the location given by suibase.
    let keystore_pathname = match suibase.keystore_pathname() {
        Ok(k_pn) => k_pn,
        Err(err) => {
            eprintln!("Failed to fetch keystore pathname: {:?}", err);
            return ExitCode::from(1)
        }
    };
    let keystore_pathbuf = PathBuf::from(keystore_pathname);
    let keystore = match FileBasedKeystore::new(&keystore_pathbuf) {
        Ok(k_pb) => Keystore::File(k_pb),
        Err(err) => {
            eprintln!("Failed to fetch keystore from suibase: {:?}", err);
            return ExitCode::from(1)
        }
    };

    // Sign the transaction
    let signature = match keystore.sign_secure(&client_address, &publish_tx, Intent::sui_transaction()) {
        Ok(sig) => sig,
        Err(err) => {
            eprintln!("Failed to sign publish tx: {:?}", err);
            return ExitCode::from(1)
        }
    };
    println!("Successfully signed publish tx");

    let publish_tx = Transaction::from_data(publish_tx, Intent::sui_transaction(), vec![signature]);
    let response = match sui_client
        .quorum_driver_api()
        .execute_transaction_block(
            publish_tx,
            SuiTransactionBlockResponseOptions::new().with_effects(),
            Some(ExecuteTransactionRequestType::WaitForLocalExecution),
        )
        .await {
            Ok(txblock_response) => txblock_response,
            Err(err) => {
                eprintln!("Failed to execute block containing publish tx. Response: {}", err);
                return ExitCode::from(1)
            }
        };

    // Success, exit
    ExitCode::SUCCESS
}