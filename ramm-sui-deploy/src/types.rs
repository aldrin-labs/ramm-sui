use std::{fmt::Display, str::FromStr, path::PathBuf};

use colored::Colorize;
use serde::{de, Deserialize, Deserializer};
use sui_types::{
    base_types::{SuiAddress, ObjectID}, TypeTag,
};

/// Minimum number of decimal places assets in Sui are allowed to have - no exact reasoning here,
/// just a heuristic in case a user writes something bad into the TOML config.
const ASSET_MIN_DECIMAL_PLACES: u8 = 4;

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
fn de_from_str<'de, D, T>(deserializer: D) -> Result<T, D::Error>
    where D: Deserializer<'de>,
          T: FromStr,
          <T as FromStr>::Err: Display
{
    let s = String::deserialize(deserializer)?;
    T::from_str(&s).map_err(de::Error::custom)
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

        write!(f, "{}{}:\n", first_pad, "asset data".purple())?;
        // This left pads each of the lines in `AssetConfig` to a variable number of `\t`
        // (tabs).
        write!(f, "{}{}: {}\n", padding, "asset type".cyan(), asset_type)?;
        write!(f, "{}{}: {}\n", padding, "aggregator address".cyan(), aggregator_address)?;
        write!(f, "{}{}: {}\n", padding, "minimum trade amount".cyan(), minimum_trade_amount)?;
        write!(f, "{}{}: {}\n", padding, "decimal places".cyan(), decimal_places)
    }
}

impl Display for AssetConfig {
    /// Display an asset's data in human readable format, with 0 tabs as leftmost indentation.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.asset_cfg_fmt(f, 0)
    }
}

#[derive(Debug)]
pub enum RAMMPkgAddrSrc {
    /// With this variant, signal that the Sui address of the RAMM library was found in the
    /// TOML deployment config.
    FromTomlConfig(ObjectID),
    /// The user specified the filepath of the RAMM library to be published, and from which the
    /// package ID to be used for deployment will be obtained.
    FromPkgPublication(PathBuf)
}

/// Deserialize a `TypeTag` from `&str/String`, instead of the usual way in which
/// `struct`s like it would be - field by field.
fn de_addr_or_path<'de, D>(deserializer: D) -> Result<RAMMPkgAddrSrc, D::Error>
    where D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    match ObjectID::from_str(&s) {
        Ok(obj) => Ok(RAMMPkgAddrSrc::FromTomlConfig(obj)),
        Err(_) => {
            PathBuf::from_str(&s)
                .map_err(de::Error::custom)
                .map(RAMMPkgAddrSrc::FromPkgPublication)
        }
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
    /// See `RAMMPkgAddrSrc`.
    #[serde(deserialize_with = "de_addr_or_path")]
    pub ramm_pkg_addr_or_path: RAMMPkgAddrSrc,
    /// Informal invariant: this field must always match `assets.len()`
    pub asset_count: u8,
    pub fee_collection_address: SuiAddress,
    pub assets: Vec<AssetConfig>,
}

impl RAMMDeploymentConfig {
    /// Validate a deployment configuration parsed from a well-formed TOML file.
    ///
    /// Returns `true` iff the config is valid per the informal specification below.
    pub(crate) fn validate_ramm_cfg(&self) -> bool {
        self.asset_count == (self.assets.len() as u8) && self.asset_count > 0 &&
        ["active", "testnet", "mainnet"].contains(&self.target_env.as_str()) &&
        self.assets.iter().all(|asset| asset.decimal_places >= ASSET_MIN_DECIMAL_PLACES)
    }
}

impl Display for RAMMDeploymentConfig {
    /// Display a RAMM's deployment config in human-readable format, with indentation
    /// for nested data for better visibility.
    ///
    /// This function uses [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
    /// to color-code the output.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:\n", "RAMM Deployment Configuration".on_bright_black())?;
        write!(f, "\t{}: {}\n", "Target environment".green(), self.target_env)?;
        write!(f, "\t{}: {}\n", "Fee collection address".green(), self.fee_collection_address)?;
        write!(f, "\t{}:\n", "List of assets".green())?;
        write!(f, "\t{}: {}\n", "Asset count".green(), self.asset_count)?;
        for asset in &self.assets {
            asset.asset_cfg_fmt(f, 3)?;
        }
        match &self.ramm_pkg_addr_or_path {
            RAMMPkgAddrSrc::FromTomlConfig(addr) => {
                write!(f, "\t{}: {}\n", "RAMM package address".green(),addr)?;
            },
            RAMMPkgAddrSrc::FromPkgPublication(path) => {
                write!(f, "\t{}: {}\n", "RAMM package ID to be obtained from publishing library at path".green(), path.display())?;
            }
        }
        write!(f, "{}\n", "End of RAMM Deployment Configuration".on_bright_black())
    }
}