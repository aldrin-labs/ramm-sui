pub mod error;
pub mod types;

use std::{io, path::PathBuf, ffi::OsString, fs, str::FromStr};

use clap::{Arg, Command, ArgMatches};
use colored::Colorize;
use error::RAMMDeploymentError;

use move_core_types::{identifier::IdentStr, ident_str};
use shared_crypto::intent::Intent;
use sui_json_rpc_types::{SuiTransactionBlockResponseOptions, SuiTransactionBlockResponse};
use suibase::Helper;

use sui_keys::keystore::{Keystore, FileBasedKeystore, AccountKeystore};
use sui_move_build::{BuildConfig, CompiledPackage};
use sui_sdk::{SuiClient, SuiClientBuilder, json::SuiJsonValue};
use sui_types::{
    base_types::{SuiAddress, ObjectID},
    transaction::{TransactionData, Transaction},
    quorum_driver_types::ExecuteTransactionRequestType
};

use types::RAMMDeploymentConfig;

/// This represents the gas budget (in MIST units, where 10^9 MIST is 1 SUI) to be used
/// when publishing the RAMM package.
///
/// Publishing it in the testnet in mid/late 2023 cost roughly 0.25 SUI, on average.
const PACKAGE_PUBLICATION_GAS_BUDGET: u64 = 500_000_000;

/// Name of the module in the RAMM package that contains the API to create and initialize it.
pub const RAMM_MODULE_NAME: &IdentStr = ident_str!("ramm");

/// Gas budget for the transaction that creates the RAMM.
const CREATE_RAMM_GAS_BUDGET: u64 = 100_000_000;

/// Parse a RAMM's deployment configuration from a given `FilePath`.
///
/// It is assumed that configs are not sizable files, so they're read directly from the
/// filesystem into a `String`, and from there parsed using `toml::from_str`.
fn parse_ramm_cfg(toml_path: PathBuf) -> Result<RAMMDeploymentConfig, RAMMDeploymentError> {
    let config_string: String = fs::read_to_string(toml_path)
        .map_err(RAMMDeploymentError::TOMLFileReadError)?;

    let cfg: RAMMDeploymentConfig = toml::from_str(&config_string)
        .map_err(RAMMDeploymentError::TOMLParseError)?;

    match cfg.validate_ramm_cfg() {
        true => Ok(cfg),
        _ => Err(RAMMDeploymentError::InvalidConfigData)
    }
}

/// Build a [`RAMMDeploymentConfig`] from `main`'s `args` iterator.
///
/// This function performs IO. It does the following:
///
/// 1. parse the user's CLI input from the `args` iterator
/// 2. parse the RAMM's deployment config from the TOML file
/// 3. check whether
///
///    a. to use the config's address of an already published RAMM library, or
///
///    b. to publish the library residing at the filepath specified by the user
pub fn deployment_cfg_from_args(
    args: impl Iterator<Item = OsString>,
) -> Result<RAMMDeploymentConfig, RAMMDeploymentError> {
    let deployer = Command::new("deployer")
        .about("Deploy a RAMM to a Sui target network with assets specified in a TOML config.")
        .help_expected(true)
        .arg(Arg::new("TOML config")
            .short('t')
            .long("toml")
            .help("Path to the TOML config containing the RAMM's deployment parameters.")
            .required(true)
            .num_args(1)
            .value_parser(clap::value_parser!(PathBuf))
        )
        .no_binary_name(true);
    let deployer_m: ArgMatches = match deployer
        .try_get_matches_from(args) {
            Err(err) => return Err(RAMMDeploymentError::CLIError(err)),
            Ok(sub_cmd) => sub_cmd
        };

    let toml_path: PathBuf = match deployer_m.get_one::<PathBuf>("TOML config") {
        None => return Err(RAMMDeploymentError::NoTOMLConfigProvided),
        Some(input) => input.to_path_buf()
    };

    // Parse the deployment config from the provided filepath.
    let ramm_cfg = parse_ramm_cfg(toml_path)?;

    Ok(ramm_cfg)
}

pub enum UserAssent {
    Rejected,
    Accepted
}

/// This function:
///
/// 1. Prints the RAMM deployment config parsed from the TOML to the user
/// 2. Asks the user to check if all its information is correct
/// 3. Returns the appropriate value to be handled by the caller on whether to proceed with
///    program execution
///
/// Warning, this function:
/// * Reads from `STDIN`
/// * Writes to `STDOUT`
/// * Uses [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
pub fn user_assent_interaction(cfg: &RAMMDeploymentConfig) -> UserAssent {
    println!(
        "The following configuration will be used to {}, {} with assets, and {} a RAMM.",
        "create".bright_blue(),
        "populate".bright_green(),
        "initialize".bright_magenta()
    );
    println!("Please, {} analyze it:", "carefully".on_red());
    println!("{}", cfg);
    println!("Is this information correct?");
    println!("Reply with {} or {}.", "\"yes\"".green(), "\"no\"".red());
    let mut input = String::new();
    loop {
        io::stdin()
            .read_line(&mut input)
            .expect("Failed to read line!");
        match input.as_ref() {
            "yes\n" => {
                println!("{} with the displayed configuration.", "Proceeding".bright_blue());
                break
            },
            "no\n" => {
                println!(
                    "{} the provided configuration {} as desired, and then {} this program",
                    "Alter".purple(),
                    "file".purple(),
                    "rerun".purple()
                );
                println!("This program will now {}.", "exit".magenta());
                return UserAssent::Rejected
            },
            _ => println!("Reply with {} or {}.", "\"yes\"".green(), "\"no\"".red()),
        }
        input.clear();
    }

    UserAssent::Accepted
}

/// Given an `&str` with the target environment, create a tuple with a Suibase helper, and a
/// Sui client.
pub async fn get_suibase_and_sui_client(target_env: &str) ->
    Result<(Helper, SuiClient), RAMMDeploymentError>
{
    let suibase = Helper::new();
    suibase
        .select_workdir(target_env)
        .map_err(RAMMDeploymentError::SuibaseWorkdirError)?;

    let rpc_url = suibase
        .rpc_url()
        .map_err(RAMMDeploymentError::RpcUrlSelectionError)?;

    let sui_client = SuiClientBuilder::default()
        .build(rpc_url)
        .await
        .map_err(RAMMDeploymentError::BuildSuiClientFromRpcUrlError)?;

    Ok((suibase, sui_client))
}

/// Given a `suibase::Helper`, fetch its keystore.
///
/// A keystore is required, along with access to an address and its private keys,
/// to sign transactions for execution in the network.
pub fn get_keystore(suibase: &Helper) -> Result<Keystore, RAMMDeploymentError> {
    let keystore_pathname = suibase
        .keystore_pathname()
        .map_err(RAMMDeploymentError::KeystorePathnameError)?;
    let keystore_pathbuf = PathBuf::from(keystore_pathname);

    FileBasedKeystore::new(&keystore_pathbuf)
        .map(Keystore::File)
        .map_err(RAMMDeploymentError::KeystoreOpenError)
}

/// Given the path to a Sui Move library for the RAMM, create a Sui transaction datum
/// to be signed and submitted to the network.
pub async fn publish_tx(
    sui_client: &SuiClient,
    package_path: PathBuf,
    client_address: SuiAddress,
    ) -> Result<TransactionData, RAMMDeploymentError>
{
    let build_config: BuildConfig = Default::default();

    let compiled_ramm_package: CompiledPackage = build_config
        .build(package_path.clone())
        .map_err(RAMMDeploymentError::PkgBuildError)?;

    // The RAMM library has no unpublished deps - it depends on
    // 1. `move_stdlib`,
    // 2. `sui_framework`, and
    // 3. `switchboard`
    // which are all published.
    let ramm_compiled_modules: Vec<Vec<u8>> =
        compiled_ramm_package.get_package_bytes(/* with_unpublished_deps */ false);

    let ramm_dep_ids: Vec<ObjectID> = compiled_ramm_package
        .dependency_ids
        .published
        .values()
        .cloned()
        .collect::<Vec<_>>();

    sui_client
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
        .await
        .map_err(RAMMDeploymentError::PublishTxError)
}

pub async fn new_ramm_tx(
    sui_client: &SuiClient,
    dplymt_cfg: &RAMMDeploymentConfig,
    client_address: &SuiAddress,
    ramm_pkg_id: ObjectID,
) -> Result<TransactionData, RAMMDeploymentError>
{
    sui_client
        .transaction_builder()
        .move_call(
        *client_address,
        ramm_pkg_id,
        RAMM_MODULE_NAME.as_str(),
        "new_ramm",
        vec![],
        vec![SuiJsonValue::from_str(&dplymt_cfg.fee_collection_address.to_string()).unwrap()],
        None,
        CREATE_RAMM_GAS_BUDGET
    )
        .await
        .map_err(RAMMDeploymentError::NewRammTxError)
}

/// Given
/// * an instance of a Sui client, through which a tx will be sent to the network,
/// * a keystore (to access an address' private/public keys)
/// * a transaction's structured data, and
/// * the address with which the tx is to be signed,
///
/// sign the transaction with the given key, and submit it, along with its signature, to the
/// network for validation and inclusion in the ledger
pub async fn sign_and_execute_tx(
    sui_client: &SuiClient,
    keystore: &Keystore,
    tx_data: TransactionData,
    client_address: &SuiAddress
) -> Result<SuiTransactionBlockResponse, RAMMDeploymentError>
{
    let signature = keystore
        .sign_secure(client_address, &tx_data, Intent::sui_transaction())
        .map_err(RAMMDeploymentError::TxSignatureError)?;

    let tx = Transaction::from_data(tx_data, Intent::sui_transaction(), vec![signature]);

    sui_client
        .quorum_driver_api()
        .execute_transaction_block(
            tx,
            SuiTransactionBlockResponseOptions::new().with_effects(),
            Some(ExecuteTransactionRequestType::WaitForLocalExecution),
        )
        .await
        .map_err(RAMMDeploymentError::TxBlockExecutionError)
}