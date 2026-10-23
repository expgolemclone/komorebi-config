use anyhow::{Context, Result, ensure};
use serde_json::Value;
use std::{
    env, fs,
    path::{Path, PathBuf},
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

pub fn directory(path: &Path) -> Result<PathBuf> {
    ensure!(
        path.is_absolute() && path.is_dir(),
        "configuration must be an existing absolute directory"
    );
    for name in ["komorebi.json", "whkdrc"] {
        ensure!(
            path.join(name).is_file(),
            "configuration file is missing: {name}"
        );
    }
    path.canonicalize()
        .context("resolving configuration directory")
}

pub fn read(root: &Path) -> Result<Value> {
    let path = root.join("komorebi.json");
    serde_json::from_slice(&fs::read(&path).with_context(|| format!("reading {}", path.display()))?)
        .context("invalid komorebi.json")
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
