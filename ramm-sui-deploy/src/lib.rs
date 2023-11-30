use std::{fmt::Display, str::FromStr};

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
        write!(f, "\tasset list:\n")?;
        for asset in &self.assets {
            asset.asset_cfg_fmt(f, 3)?;
        }
        write!(f, "\tfee collection address: {}\n", self.fee_collection_address)?;
        write!(f, "\tasset count: {}", self.asset_count)
    }
}