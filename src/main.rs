#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use anyhow::{Context, Result, ensure};
use clap::{Parser, Subcommand};
use komorebi_config::{
    config,
    entry::{Identity, validate_identity},
    log::Log,
    restart,
    windows::{display, privilege, service},
};
use std::path::PathBuf;

#[derive(Parser)]
#[command(version, about = "Native helpers for komorebi configuration")]
struct Cli {
    #[command(subcommand)]
    command: Operation,
}

#[derive(Subcommand)]
enum Operation {
    /// Restart komorebi/whkd and apply orientation-based layouts.
    Restart {
        #[arg(long)]
        config_directory: PathBuf,
        #[arg(long)]
        recover_display: bool,
        #[arg(long, hide = true, requires = "origin_session")]
        origin_sid: Option<String>,
        #[arg(long, hide = true, requires = "origin_sid")]
        origin_session: Option<u32>,
    },
    /// Move the cursor to the foreground window's bottom center.
    MoveCursor,
    #[command(hide = true)]
    NightLightWorker,
}

fn execute(operation: Operation) -> Result<u32> {
    match operation {
        Operation::MoveCursor => {
            display::move_cursor()?;
            Ok(0)
        }
        Operation::NightLightWorker => {
            ensure!(
                privilege::is_elevated()?,
                "Night Light recovery requires administrator privileges"
            );
            service::restart_night_light()?;
            Ok(0)
        }
        Operation::Restart {
            config_directory,
            recover_display,
            origin_sid,
            origin_session,
        } => {
            let log = Log::application()?;
            let run = || -> Result<u32> {
                log.event(format!(
                    "restart requested; recover-display={recover_display}"
                ))?;
                let identity = privilege::identity()?;
                let origin = origin_sid
                    .zip(origin_session)
                    .map(|(sid, session)| Identity { sid, session });
                validate_identity(&identity, origin.as_ref())?;
                // Reject incomplete configuration before UAC or stopping anything.
                let root = config::directory(&config_directory)?;
                if !privilege::is_elevated()? {
                    ensure!(
                        origin.is_none(),
                        "elevated restart did not acquire administrator privileges"
                    );
                    log.event("requesting administrator privileges")?;
                    return privilege::elevate(recover_display, &identity, &root);
                }
                let Some(_lock) = privilege::RestartLock::acquire()? else {
                    log.event("another restart is already running")?;
                    return Ok(0);
                };
                restart::run(&restart::Native { root, log: &log }, recover_display)?;
                log.event("restart succeeded")?;
                Ok(0)
            };
            let result = run();
            if let Err(error) = &result {
                log.event(format!("restart failed: {error:#}"))
                    .context("writing restart failure log")?;
            }
            result
        }
    }
}

fn main() {
    let code = match execute(Cli::parse().command) {
        Ok(code) => code,
        Err(error) => {
            eprintln!("komorebi-config: {error:#}");
            1
        }
    };
    std::process::exit(code as i32);
}
