use crate::process::{Invocation, capture};
use anyhow::{Context, Result, ensure};
use serde_json::Value;
use std::{
    env, fs,
    path::{Path, PathBuf},
    time::Duration,
};

pub fn system_tool(relative: &str) -> Result<PathBuf> {
    let root = PathBuf::from(env::var_os("SystemRoot").context("SystemRoot is missing")?);
    ensure!(root.is_absolute(), "SystemRoot must be absolute");
    let path = root.join(relative);
    ensure!(
        path.is_file(),
        "Windows tool is missing: {}",
        path.display()
    );
    Ok(path)
}

pub fn repository_root() -> Result<PathBuf> {
    let powershell = system_tool("System32/WindowsPowerShell/v1.0/powershell.exe")?;
    let script = r#"$ErrorActionPreference = 'Stop'; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); Import-Module (Join-Path $HOME 'local-repository-map/repository-map.psm1') -ErrorAction Stop; Get-LocalRepositoryPath 'expgolemclone/komorebi-config' | ConvertTo-Json -Compress"#;
    let output = capture(
        &Invocation::new(powershell).args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            script,
        ]),
        Duration::from_secs(30),
    )
    .context("resolving configuration through RepositoryMap")?;
    let root: PathBuf = serde_json::from_slice(&output)
        .context("RepositoryMap returned an invalid path response")?;
    ensure!(
        root.is_absolute() && root.is_dir(),
        "RepositoryMap did not return an existing absolute directory"
    );
    Ok(root)
}

pub fn read(root: &Path) -> Result<Value> {
    let path = root.join("komorebi.json");
    serde_json::from_slice(&fs::read(&path).with_context(|| format!("reading {}", path.display()))?)
        .context("invalid komorebi.json")
}

pub fn validate_native_bindings(root: &Path) -> Result<()> {
    let content = fs::read_to_string(root.join("whkdrc")).context("reading whkdrc")?;
    ensure!(
        content.lines().any(|line| line.trim() == ".shell cmd"),
        "whkdrc must use .shell cmd"
    );
    ensure!(
        !content.contains("KOMOREBI_AUTOHOTKEY")
            && !content.contains("move-cursor-bottom-center.ahk"),
        "whkdrc still uses the legacy AHK helper; finish the approved hotkey cutover before using native restart"
    );
    for direction in ["left", "down", "up", "right"] {
        let action = format!(
            r#"komorebic focus {direction} && start "" /b "%LOCALAPPDATA%\envx\runtimes\rust\bin\komorebi-config.exe" move-cursor"#
        );
        ensure!(
            content
                .lines()
                .filter(|line| !line.trim_start().starts_with('#'))
                .filter_map(|line| line.split_once(':'))
                .any(|(_, command)| command.trim() == action),
            "whkdrc lacks the shared native cursor binding for {direction}"
        );
    }
    Ok(())
}

pub fn shared_executable() -> Result<PathBuf> {
    let root = PathBuf::from(env::var_os("LOCALAPPDATA").context("LOCALAPPDATA is missing")?);
    ensure!(root.is_absolute(), "LOCALAPPDATA must be absolute");
    let executable = root.join("envx/runtimes/rust/bin/komorebi-config.exe");
    ensure!(
        executable.is_file(),
        "shared native helper is missing: {}",
        executable.display()
    );
    Ok(executable)
}

pub fn schema_version(config: &Value) -> Result<&str> {
    let schema = config["$schema"]
        .as_str()
        .context("komorebi.json has no schema URL")?;
    let version = schema
        .strip_prefix("https://raw.githubusercontent.com/LGUG2Z/komorebi/v")
        .and_then(|value| value.strip_suffix("/schema.json"))
        .context("unexpected komorebi schema URL")?;
    ensure!(
        !version.is_empty()
            && version.split('.').count() == 3
            && version
                .split('.')
                .all(|part| !part.is_empty() && part.bytes().all(|byte| byte.is_ascii_digit())),
        "invalid schema version"
    );
    Ok(version)
}
