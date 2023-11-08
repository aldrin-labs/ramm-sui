use std::fmt::Display;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct FaucetData {
    package_id: String,
    module_name: String,
}

impl FaucetData {
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
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.faucet_data_fmt(f, 0)
    }
}

#[derive(Debug, Deserialize)]
pub struct AssetConfig {
    asset_name: String,
    aggregator_address: String,
    minimum_trade_amount: u64,
    decimal_places: u8
}

impl AssetConfig {
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
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.asset_cfg_fmt(f, 0)
    }
}

#[derive(Debug, Deserialize)]
pub struct RAMMDeploymentConfig {
    faucet_data: FaucetData,

    asset_count: u8,
    fee_collection_address: String,
    assets: Vec<AssetConfig>,
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