pub enum RAMMDeploymentError {
    /// The user did not use the `--publish` flag *and* also did not provided an `AccountAddress`
    /// for a published version of the RAMM library
    NoPkgAddrAndNoPublishFlag,

    /// An error reading form the TOML config to a `String` 
    TOMLFileReadError(std::io::Error),
    CLIError(clap::Error),
    NoTOMLConfigProvided,
    TOMLParseError(toml::de::Error),
}