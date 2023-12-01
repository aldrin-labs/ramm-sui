pub mod error;
pub mod types;

use std::{path::PathBuf, ffi::OsString, fs};

use clap::{Arg, Command, ArgMatches};
use error::RAMMDeploymentError;
use sui_sdk::{SuiClient, SuiClientBuilder};
use suibase::Helper;
use types::{RAMMDeploymentConfig, RAMMPkgAddrSrc};

/// Parse a RAMM's deployment configuration from a given `FilePath`.
///
/// It is assumed that configs are not sizable files, so they're read directly from the
/// filesystem into a `String`, and from there parsed using `toml::from_str`.
fn parse_ramm_cfg(toml_path: PathBuf) -> Result<RAMMDeploymentConfig, RAMMDeploymentError> {
    let config_string: String = fs::read_to_string(toml_path)
        .map_err(RAMMDeploymentError::TOMLFileReadError)?;

    toml::from_str(&config_string)
        .map_err(RAMMDeploymentError::TOMLParseError)
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
) -> Result<(RAMMDeploymentConfig, RAMMPkgAddrSrc), RAMMDeploymentError> {
    let deployer = Command::new("deployer")
        .about("Deploy a RAMM to a Sui target network with assets specified in a TOML config.")
        .help_expected(true)
        .arg(Arg::new("publish RAMM package")
            .short('p')
            .long("publish")
            .help("Path to the RAMM library to be published.")
            .num_args(1)
            .value_parser(clap::value_parser!(PathBuf))
        )
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

    let ramm_pkg_path: Option<&PathBuf> = deployer_m.get_one("publish RAMM package");
    let toml_path: PathBuf = match deployer_m.get_one::<PathBuf>("TOML config") {
        None => return Err(RAMMDeploymentError::NoTOMLConfigProvided),
        Some(input) => input.to_path_buf()
    };

    // Parse the deployment config from the provided filepath.
    let ramm_cfg = parse_ramm_cfg(toml_path)?;

    let ramm_pkg_addr = match (ramm_pkg_path, ramm_cfg.pkg_address) {
        (None, None) => return Err(RAMMDeploymentError::NoPkgAddrAndNoPublishFlag),
        (Some(path), None) => RAMMPkgAddrSrc::FromPkgPublication(path.to_path_buf()),
        (_, Some(_)) => RAMMPkgAddrSrc::FromTOMLConfig,
    };

    Ok((ramm_cfg, ramm_pkg_addr))
}



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

