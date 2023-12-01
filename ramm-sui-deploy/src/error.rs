use thiserror::Error;

#[derive(Debug, Error)]
pub enum RAMMDeploymentError {
    /// The user did not use the `--publish` flag *and* also did not provided an `AccountAddress`
    /// for a published version of the RAMM library
    #[error("No RAMM package address and no `--publish` flag specified. Please supply at least one.")]
    NoPkgAddrAndNoPublishFlag,

    #[error("Error reading the TOML config file into a `String`: {0}")]
    TOMLFileReadError(std::io::Error),
    #[error("Error parsing the executable's user input: {0}")]
    CLIError(clap::Error),
    #[error("No TOML config file provided - it is mandatory to provide one.")]
    NoTOMLConfigProvided,
    #[error("Failed to parse the TOML config data: {0}")]
    TOMLParseError(toml::de::Error),

    #[error("Failed to fetch Suibase workdir specified in config: {0}")]
    SuibaseWorkdirError(suibase::Error),
    #[error("Failed to get the RPC URL for the selected workdir: {0}")]
    RpcUrlSelectionError(suibase::Error),
    #[error("Failed to build a Sui client from the selected RPC URL: {0}")]
    BuildSuiClientFromRpcUrlError(sui_sdk::error::Error)
}