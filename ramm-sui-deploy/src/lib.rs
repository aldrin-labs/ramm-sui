use std::fmt::Display;
use serde::Deserialize;

use sui_types::base_types::{ObjectID, SuiAddress};

/// Data required to identify the coin faucet
/// 1. from which the RAMM's test tokens were created, and
/// 2. through which the actual `Coin` objects can be obtained to interact with the RAMM
///
/// It contains the ID of the package from which the faucet was created, and the name of
/// the module as well.
#[derive(Debug, Deserialize)]
pub struct FaucetData {
    pub package_id: ObjectID,
    pub module_name: String,
}

impl FaucetData {
    /// Display the test token faucet's data in human readable format, with a variable number of
    /// tabs as leftmost indentation.
    pub(self) fn faucet_data_fmt(&self, f: &mut std::fmt::Formatter<'_>, tab_count: usize) -> std::fmt::Result {
        let &FaucetData { package_id, module_name } = &self;

        let first_pad: String = '\t'.to_string().repeat(tab_count - 1);
        let padding: String = '\t'.to_string().repeat(tab_count);

        write!(f, "{}faucet data:\n", first_pad)?;
        write!(f, "{}package ID: {}\n", padding, package_id)?;
        write!(f, "{}module name: {}\n", padding, module_name)
    }
}

impl Display for FaucetData {
    /// Format the structure with a specific amount of tabs for indentation.
    ///
    /// In the case of this `impl`, it is 0, but when shown as part of the `struct` into which all
    /// of its occurences will be nested, `RAMMDeploymentConfig`, more indentation will be needed
    /// to correctly visualize its data.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.faucet_data_fmt(f, 0)
    }
}

/// Asset data required to add said asset to the RAMM, using its Sui Move API and the
/// Sui Rust SDK via programmable transaction blocks (PTBs).
#[derive(Debug, Deserialize)]
pub struct AssetConfig {
    pub asset_name: String,
    pub aggregator_address: SuiAddress,
    pub minimum_trade_amount: u64,
    pub decimal_places: u8
}

impl AssetConfig {
    /// Display an asset's data in human readable format, with a variable number of
    /// tabs as leftmost indentation.
    pub(self) fn asset_cfg_fmt(&self, f: &mut std::fmt::Formatter<'_>, tab_count: usize) -> std::fmt::Result {
        let &AssetConfig {
            asset_name,
            aggregator_address,
            minimum_trade_amount,
            decimal_places
        } = &self;

        let first_pad: String = '\t'.to_string().repeat(tab_count - 1);
        let padding: String = '\t'.to_string().repeat(tab_count);

        write!(f, "{}asset data:\n", first_pad)?;
        // This left pads each of the lines in `AssetConfig` to a variable number of `\t`
        // (tabs).
        write!(f, "{}asset name: {}\n", padding, asset_name)?;
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
    pub faucet_data: FaucetData,

    pub asset_count: u8,
    pub fee_collection_address: SuiAddress,
    pub assets: Vec<AssetConfig>,
}

impl Display for RAMMDeploymentConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let &RAMMDeploymentConfig {
            faucet_data,
            asset_count,
            fee_collection_address,
            assets
        } = &self;
        write!(f, "RAMM Deployment Configuration:\n")?;
        write!(f, "\tasset list:\n")?;
        for asset in assets {
            asset.asset_cfg_fmt(f, 3)?;
        }
        faucet_data.faucet_data_fmt(f, 2)?;
        write!(f, "\tfee collection address: {}\n", fee_collection_address)?;
        write!(f, "\tasset count: {}", asset_count)
    }
}