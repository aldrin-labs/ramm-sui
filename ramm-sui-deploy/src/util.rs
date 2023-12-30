use std::fs;

use log::SetLoggerError;
use simplelog::{
    ColorChoice, CombinedLogger, ConfigBuilder, LevelFilter, SharedLogger, TermLogger, TerminalMode,
    WriteLogger,
};

/// Function to initialize logging infrastructure.
/// Logging relies on the façade provided by `simplelog`, with the `log` library
/// providing the logging API.
///
/// The default logging configuration is used, which is then modified to allow
/// source-code information on every log message, not just errors.
///
/// # Arguments
///
/// * `opt_log_file_name` - Name of the file to which logs will be written to. If `None`, terminal-only logging is used.
/// * `log_level` - Set at which level and above the log messages will be displayed.
pub fn init_logging_infrastructure(
    opt_log_file_name : Option<&str>,
    log_level: LevelFilter
    ) -> Result<(), SetLoggerError> {
    let config = ConfigBuilder::new()
        // This enables source-code location in logging message of any level
        .set_location_level(LevelFilter::Error)
        .build();
    let term_logger = TermLogger::new(
        // This is the field used to control the granularity of logs shown in the terminal.
        log_level,
        config.clone(),
        TerminalMode::Mixed,
        ColorChoice::Auto,
    );

    // Terminal logging is always used, but file_based logging will
    // depend on the log file name the program user may or may not provide.
    let mut logger_vec: Vec<Box<dyn SharedLogger>> = vec![term_logger];

    match opt_log_file_name {
        None => {
            println!("No log file name provided.");
            println!("Terminal-only logging will be done instead.");
        }
        Some(log_file_name) => {
            let log_file = fs::File::create(log_file_name);
            match log_file {
                Err(err) => {
                    eprintln!("Could not create logging file! Error: {:?}", err);
                    eprintln!("Terminal-only logging will be attempted.");
                }
                Ok(file) => {
                    let file_logger = WriteLogger::new(
                        LevelFilter::Info,
                        config,
                        file
                    );
                    logger_vec.push(file_logger);
                }
            }
        }
    };

    CombinedLogger::init(logger_vec)
}