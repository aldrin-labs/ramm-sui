pub mod error;

use std::{fmt::Display, str::FromStr, path::PathBuf, ffi::OsString, fs};

use clap::{Arg, Command, ArgMatches};
use error::RAMMDeploymentError;
use move_core_types::account_address::AccountAddress;
use serde::{de, Deserialize, Deserializer};
use sui_types::{
    base_types::SuiAddress, TypeTag,
};

/// Asset data required to add said asset to the RAMM, using its Sui Move API and the
/// Sui Rust SDK via programmable transaction blocks (PTBs).
#[derive(Debug, Deserialize)]
pub struct AssetConfig {
    #[serde(deserialize_with = "de_from_str")] 
    pub asset_type: TypeTag,
    pub aggregator_address: SuiAddress,
    pub minimum_trade_amount: u64,
    pub decimal_places: u8
}

/// Deserialize a `TypeTag` from `&str/String`, instead of the usual way in which
/// `struct`s like it would be - field by field.
fn de_from_str<'de, D>(deserializer: D) -> Result<TypeTag, D::Error>
    where D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    TypeTag::from_str(&s).map_err(de::Error::custom)
}

impl AssetConfig {
    /// Display an asset's data in human readable format, with a variable number of
    /// tabs as leftmost indentation.
    pub(self) fn asset_cfg_fmt(&self, f: &mut std::fmt::Formatter<'_>, tab_count: usize) -> std::fmt::Result {
        let &AssetConfig {
            asset_type,
            aggregator_address,
            minimum_trade_amount,
            decimal_places
        } = &self;

        let first_pad: String = '\t'.to_string().repeat(tab_count - 1);
        let padding: String = '\t'.to_string().repeat(tab_count);

        write!(f, "{}asset data:\n", first_pad)?;
        // This left pads each of the lines in `AssetConfig` to a variable number of `\t`
        // (tabs).
        write!(f, "{}asset type: {}\n", padding, asset_type)?;
        write!(f, "{}aggregator address: {}\n", padding, aggregator_address)?;
        write!(f, "{}minimum trade amount: {}\n", padding, minimum_trade_amount)?;
        write!(f, "{}decimal places: {}\n", padding, decimal_places)
    }
}

impl Display for AssetConfig {
    /// Display an asset's data in human readable format, with 0 tabs as leftmost indentation.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.asset_cfg_fmt(f, 0)
    }
}

/// Information that specifies how a given RAMM is to deployed to the network of choice.
///
/// At the moment, it is hardcoded to deploy on the testnet, but this can be changed in the future,
/// should the tool be used for mainnet deployment.
///
/// It contains:
/// * the data of the faucet whose tokens the RAMM will use
/// * the number of assets
/// * the RAMM's initial fee collection address
/// * a vector with each of the asset's data
#[derive(Debug, Deserialize)]
pub struct RAMMDeploymentConfig {
    /// The Sui network environment to be targeted. Acceptable values:
    /// * testnet
    /// * mainnet
    /// * active (which is really just suibase shorthand for either of the two above)
    pub target_env: String,
    /// If present, the address of the already published RAMM library.
    ///
    /// If this setting is not present in the TOML config, then the `--publish` argument must
    /// have been passed in, or an error will occur.
    pub pkg_address: Option<AccountAddress>,
    /// Informal invariant: this field must always match `assets.len()`
    pub asset_count: u8,
    pub fee_collection_address: SuiAddress,
    pub assets: Vec<AssetConfig>,
}

impl Display for RAMMDeploymentConfig {
    /// Display a RAMM's deployment config in human-readable format, with indentation
    /// for nested data for better visibility.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "RAMM Deployment Configuration:\n")?;
        write!(f, "\ttarget environment:{}\n", self.target_env)?;
        match self.pkg_address {
            None => {},
            Some(addr) => {
                write!(f, "\texisting RAMM library address:{}\n", addr)?
            }
        };
        write!(f, "\tasset list:\n")?;
        for asset in &self.assets {
            asset.asset_cfg_fmt(f, 3)?;
        }
        write!(f, "\tfee collection address: {}\n", self.fee_collection_address)?;
        write!(f, "\tasset count: {}", self.asset_count)
    }
}

pub enum RAMMPkgAddrSrc {
    /// With this variant, signal that the Sui address of the RAMM library was found in the
    /// TOML deployment config.
    FromTOMLConfig,
    /// The user specified the filepath of the RAMM library to be published, and from which the
    /// package ID to be used for deployment will be obtained.
    FromPkgPublication(PathBuf)
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
pub fn build(
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
        );
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
    let ramm_cfg = RAMMDeploymentConfig::parse_ramm_cfg(toml_path)?;

    let ramm_pkg_addr = match (ramm_pkg_path, ramm_cfg.pkg_address) {
        (None, None) => return Err(RAMMDeploymentError::NoPkgAddrAndNoPublishFlag),
        (Some(path), None) => RAMMPkgAddrSrc::FromPkgPublication(path.to_path_buf()),
        (_, Some(_)) => RAMMPkgAddrSrc::FromTOMLConfig,
    };

    Ok((ramm_cfg, ramm_pkg_addr))
}

impl RAMMDeploymentConfig {
    /// Parse a RAMM's deployment configuration from a given `FilePath`.
    ///
    /// It is assumed that configs are not sizable files, so they're read directly from the
    /// filesystem into a `String`, and from there parsed using `toml::from_str`.
    fn parse_ramm_cfg(toml_path: PathBuf) -> Result<Self, RAMMDeploymentError> {
        let config_string: String = fs::read_to_string(toml_path)
            .map_err(RAMMDeploymentError::TOMLFileReadError)?;

        toml::from_str(&config_string)
            .map_err(RAMMDeploymentError::TOMLParseError)
    }
}