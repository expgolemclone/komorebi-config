use anyhow::{Context, Result, ensure};
use std::{
    env,
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

pub struct Log {
    file: File,
}

impl Log {
    pub fn application() -> Result<Self> {
        let root = PathBuf::from(env::var_os("LOCALAPPDATA").context("LOCALAPPDATA is missing")?);
        ensure!(root.is_absolute(), "LOCALAPPDATA must be absolute");
        Self::open(&root.join("komorebi/restart.log"))
    }

    pub fn open(path: &Path) -> Result<Self> {
        fs::create_dir_all(path.parent().context("log has no parent directory")?)?;
        Ok(Self {
            file: OpenOptions::new()
                .create(true)
                .append(true)
                .open(path)
                .with_context(|| format!("opening log {}", path.display()))?,
        })
    }

    pub fn event(&self, message: impl AsRef<str>) -> Result<()> {
        let millis = SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis();
        let message = format!("[{millis}] pid={} {}", std::process::id(), message.as_ref());
        let mut file = &self.file;
        writeln!(file, "{message}")?;
        file.flush()?;
        let _ = writeln!(std::io::stderr(), "{message}");
        Ok(())
    }

    pub fn output(&self) -> Result<File> {
        self.file
            .try_clone()
            .context("duplicating application log handle")
    }
}
