use std::{env, fs, path::PathBuf, process::ExitCode};

use suibase::Helper;
use sui_sdk::SuiClientBuilder;
use toml::de;

use ramm_sui_deploy::{FaucetData, AssetConfig, RAMMDeploymentConfig};

#[tokio::main]
async fn main() -> ExitCode {
    let suibase = Helper::new();
    match suibase.select_workdir("active") {
        Ok(_) => {},
        Err(err) => {
            eprintln!("Failure to select workdir: {}", err);
            return ExitCode::from(1)
        }
    }
    match suibase.workdir() {
        Ok(workdir) => println!("Using suibase workdir [{}]", workdir),
        Err(err) => {
            eprintln!("Failed to fetch current workdir: {:?}", err);
            return ExitCode::from(1)
        }
    }

    let rpc_url = match suibase.rpc_url() {
        Ok(ru) => ru,
        Err(err) => {
            eprintln!("Failed to fetch current RPC URL: {:?}", err);
            return ExitCode::from(1)
        }
    };
    let sui_client = match SuiClientBuilder::default().build(rpc_url).await {
        Ok(cl) => cl,
        Err(err) => {
            eprintln!("Failed to fetch current RPC URL: {:?}", err);
            return ExitCode::from(1)
        }
    };

    let args = &mut env::args();
    let exec_name: PathBuf = PathBuf::from(args.next().unwrap());
    println!("Process name: {}", exec_name.display());
    let config_path: PathBuf = match args.next() {
        None => {
            println!("No TOML config provided; exiting.");
            return ExitCode::from(0)
        },
        Some(s) => PathBuf::from(s),
    };
    let config_string: String = match fs::read_to_string(config_path) {
        Err(err) => {
            eprintln!("Could not parse config file into `String`: {:?}", err);
            return ExitCode::from(1)
        },
        Ok(str) => str,
    };

    let config: Result<RAMMDeploymentConfig, de::Error> = toml::from_str(&config_string);
    match config {
        Ok(cfg) => {
            println!("{}", cfg);
            ExitCode::SUCCESS
        },
        Err(err) => {
            eprintln!("Could not parse config file into `String`: {err}");
            return ExitCode::from(1)
        }
    }
}