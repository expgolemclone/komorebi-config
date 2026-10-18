pub mod display;
pub mod privilege;
pub mod processes;
pub mod service;

use anyhow::{Context, Result, ensure};
use std::{
    ffi::OsStr,
    os::windows::ffi::OsStrExt,
    path::Path,
    thread,
    time::{Duration, Instant},
};
use windows::{
    Win32::{
        Foundation::{CloseHandle, HANDLE, WAIT_OBJECT_0, WAIT_TIMEOUT},
        Globalization::{CSTR_EQUAL, CompareStringOrdinal},
        System::Threading::WaitForSingleObject,
    },
    core::Error,
};

pub(crate) struct Handle(pub HANDLE);

impl Drop for Handle {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseHandle(self.0);
        }
    }
}

pub(crate) fn wide(value: impl AsRef<OsStr>) -> Result<Vec<u16>> {
    let mut wide: Vec<_> = value.as_ref().encode_wide().collect();
    ensure!(!wide.contains(&0), "embedded NUL in Windows string");
    wide.push(0);
    Ok(wide)
}

pub fn paths_equal(left: &Path, right: &Path) -> Result<bool> {
    let left: Vec<_> = left.canonicalize()?.as_os_str().encode_wide().collect();
    let right: Vec<_> = right.canonicalize()?.as_os_str().encode_wide().collect();
    Ok(unsafe { CompareStringOrdinal(&left, &right, true) } == CSTR_EQUAL)
}

pub(crate) fn wait(handle: HANDLE, timeout: Duration) -> Result<bool> {
    let millis = u32::try_from(timeout.as_millis()).context("Windows wait timeout exceeds u32")?;
    match unsafe { WaitForSingleObject(handle, millis) } {
        WAIT_OBJECT_0 => Ok(true),
        WAIT_TIMEOUT => Ok(false),
        _ => Err(Error::from_thread().into()),
    }
}

pub fn poll<T>(
    timeout: Duration,
    interval: Duration,
    mut probe: impl FnMut(Duration) -> Result<Option<T>>,
) -> Result<T> {
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        ensure!(
            !remaining.is_zero(),
            "operation did not become ready within {:.2}s",
            timeout.as_secs_f64()
        );
        if let Some(value) = probe(remaining)? {
            return Ok(value);
        }
        thread::sleep(interval.min(deadline.saturating_duration_since(Instant::now())));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn polling_exhausts_a_real_deadline_and_propagates_fatal_errors() {
        let started = Instant::now();
        assert!(
            poll::<()>(Duration::from_millis(25), Duration::from_millis(2), |_| Ok(
                None
            ))
            .is_err()
        );
        assert!(started.elapsed() < Duration::from_secs(2));
        let error = poll::<()>(Duration::from_secs(1), Duration::ZERO, |_| {
            anyhow::bail!("fatal probe")
        })
        .unwrap_err();
        assert_eq!(error.to_string(), "fatal probe");
    }

    #[test]
    fn windows_strings_reject_nul() {
        assert!(wide("bad\0path").is_err());
        assert_eq!(wide("safe").unwrap().last(), Some(&0));
    }
}
