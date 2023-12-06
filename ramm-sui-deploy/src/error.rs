use thiserror::Error;

#[derive(Debug, Error)]
pub enum RAMMDeploymentError {
    #[error("Error reading the TOML config file into a `String`: {0}")]
    TOMLFileReadError(std::io::Error),
    #[error("Error parsing the executable's user input: {0}")]
    CLIError(clap::Error),
    #[error("No TOML config file provided - it is mandatory to provide one.")]
    NoTOMLConfigProvided,
    #[error("Failed to parse the TOML config data: {0}")]
    TOMLParseError(toml::de::Error),

    #[error("The parsed TOML config has bad data.")]
    InvalidConfigData,

    #[error("Failed to fetch Suibase workdir specified in config: {0}")]
    SuibaseWorkdirError(suibase::Error),
    #[error("Failed to get the RPC URL for the selected workdir: {0}")]
    RpcUrlSelectionError(suibase::Error),
    #[error("Failed to build a Sui client from the selected RPC URL: {0}")]
    BuildSuiClientFromRpcUrlError(sui_sdk::error::Error),

    #[error("Failed to fetch pathname of file-based keystore: {0}")]
    KeystorePathnameError(suibase::Error),
    #[error("Failed to open file-based keystore: {0}")]
    KeystoreOpenError(anyhow::Error),

    #[error("Failed to build the RAMM package: {0}")]
    PkgBuildError(sui_types::error::SuiError),

    #[error("Failed to build publication transaction for RAMM library: {0}")]
    PublishTxError(anyhow::Error),
    #[error("Failed to sign transaction: {0}")]
    TxSignatureError(signature::Error),
    #[error("Failed to execute transaction block: {0}")]
    TxBlockExecutionError(sui_sdk::error::Error),
    #[error("Failed to build RAMM creation tx: {0}")]
    NewRammTxError(anyhow::Error),
}
