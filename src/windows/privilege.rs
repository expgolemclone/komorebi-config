use super::{Handle, wide};
use crate::entry::{Identity, elevation_arguments};
use anyhow::{Context, Result, ensure};
use std::mem::{size_of, size_of_val};
use windows::{
    Win32::{
        Foundation::{
            ERROR_CANCELLED, ERROR_INSUFFICIENT_BUFFER, HANDLE, HLOCAL, LocalFree, WAIT_ABANDONED,
            WAIT_OBJECT_0, WAIT_TIMEOUT,
        },
        Security::{
            Authorization::ConvertSidToStringSidW, GetTokenInformation, TOKEN_ELEVATION,
            TOKEN_QUERY, TOKEN_USER, TokenElevation, TokenUser,
        },
        System::{
            RemoteDesktop::ProcessIdToSessionId,
            Threading::{
                CreateMutexW, GetCurrentProcess, GetCurrentProcessId, GetExitCodeProcess, INFINITE,
                OpenProcessToken, ReleaseMutex, WaitForSingleObject,
            },
        },
        UI::{
            Shell::{
                SEE_MASK_NOASYNC, SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW, ShellExecuteExW,
            },
            WindowsAndMessaging::SW_HIDE,
        },
    },
    core::{Error, HRESULT, PCWSTR, PWSTR, w},
};

fn token() -> Result<Handle> {
    let mut token = HANDLE::default();
    unsafe {
        OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token)?;
    }
    Ok(Handle(token))
}

pub fn is_elevated() -> Result<bool> {
    let token = token()?;
    let mut elevation = TOKEN_ELEVATION::default();
    let mut required = 0;
    unsafe {
        GetTokenInformation(
            token.0,
            TokenElevation,
            Some((&mut elevation as *mut TOKEN_ELEVATION).cast()),
            size_of_val(&elevation) as u32,
            &mut required,
        )?;
    }
    Ok(elevation.TokenIsElevated != 0)
}

pub fn session(pid: u32) -> Result<u32> {
    let mut session = 0;
    unsafe {
        ProcessIdToSessionId(pid, &mut session)?;
    }
    Ok(session)
}

pub fn identity() -> Result<Identity> {
    let token = token()?;
    let mut bytes = 0;
    let error = unsafe { GetTokenInformation(token.0, TokenUser, None, 0, &mut bytes) }
        .err()
        .context("unexpected successful zero-length TOKEN_USER query")?;
    ensure!(
        error.code() == HRESULT::from_win32(ERROR_INSUFFICIENT_BUFFER.0),
        "querying account SID size: {error}"
    );
    // The TOKEN_USER pointer needs pointer alignment, not an arbitrary byte buffer.
    let mut storage = vec![0usize; (bytes as usize).div_ceil(size_of::<usize>())];
    unsafe {
        GetTokenInformation(
            token.0,
            TokenUser,
            Some(storage.as_mut_ptr().cast()),
            bytes,
            &mut bytes,
        )?;
    }
    let user = unsafe { &*storage.as_ptr().cast::<TOKEN_USER>() };
    let mut sid = PWSTR::null();
    unsafe {
        ConvertSidToStringSidW(user.User.Sid, &mut sid)?;
    }
    let result = unsafe { sid.to_string() }.context("decoding account SID");
    unsafe {
        let _ = LocalFree(Some(HLOCAL(sid.0.cast())));
    }
    Ok(Identity {
        sid: result?,
        session: session(unsafe { GetCurrentProcessId() })?,
    })
}

pub fn elevate(recover: bool, identity: &Identity) -> Result<u32> {
    let executable = wide(std::env::current_exe()?)?;
    let arguments = wide(elevation_arguments(recover, identity)?)?;
    let mut info = SHELLEXECUTEINFOW {
        cbSize: size_of::<SHELLEXECUTEINFOW>() as u32,
        fMask: SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC,
        lpVerb: w!("runas"),
        lpFile: PCWSTR(executable.as_ptr()),
        lpParameters: PCWSTR(arguments.as_ptr()),
        nShow: SW_HIDE.0,
        ..Default::default()
    };
    unsafe { ShellExecuteExW(&mut info) }.map_err(elevation_error)?;
    ensure!(
        !info.hProcess.is_invalid(),
        "elevation did not return a process handle"
    );
    let process = Handle(info.hProcess);
    ensure!(
        unsafe { WaitForSingleObject(process.0, INFINITE) } == WAIT_OBJECT_0,
        "waiting for elevated restart failed: {}",
        Error::from_thread()
    );
    let mut code = 0;
    unsafe {
        GetExitCodeProcess(process.0, &mut code)?;
    }
    Ok(code)
}

fn elevation_error(error: Error) -> anyhow::Error {
    if error.code() == HRESULT::from_win32(ERROR_CANCELLED.0) {
        anyhow::anyhow!("administrator elevation was canceled")
    } else {
        anyhow::Error::from(error).context("starting elevated restart")
    }
}

pub struct RestartLock(Handle);

impl RestartLock {
    pub fn acquire() -> Result<Option<Self>> {
        Self::named("Local\\komorebi-config-restart")
    }

    pub fn named(name: &str) -> Result<Option<Self>> {
        let name = wide(name)?;
        let handle = Handle(unsafe { CreateMutexW(None, false, PCWSTR(name.as_ptr()))? });
        match unsafe { WaitForSingleObject(handle.0, 0) } {
            WAIT_OBJECT_0 | WAIT_ABANDONED => Ok(Some(Self(handle))),
            WAIT_TIMEOUT => Ok(None),
            _ => Err(Error::from_thread().into()),
        }
    }
}

impl Drop for RestartLock {
    fn drop(&mut self) {
        unsafe {
            let _ = ReleaseMutex(self.0.0);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{sync::mpsc, time::Duration};

    #[test]
    fn elevation_cancellation_and_other_errors_are_distinct_without_requesting_uac() {
        let canceled = elevation_error(Error::from_hresult(HRESULT::from_win32(ERROR_CANCELLED.0)));
        assert_eq!(canceled.to_string(), "administrator elevation was canceled");
        let missing = elevation_error(Error::from_hresult(HRESULT::from_win32(2)));
        assert!(format!("{missing:#}").contains("starting elevated restart"));
        assert!(!format!("{missing:#}").contains("canceled"));
    }

    #[test]
    fn lock_serializes_other_threads_without_touching_the_production_name() {
        let name = format!("Local\\komorebi-test-lock-{}", std::process::id());
        let lock = RestartLock::named(&name).unwrap().unwrap();
        let other = name.clone();
        assert!(
            std::thread::spawn(move || RestartLock::named(&other).unwrap().is_none())
                .join()
                .unwrap()
        );
        drop(lock);
        assert!(RestartLock::named(&name).unwrap().is_some());
    }

    #[test]
    fn abandoned_mutex_is_acquired() {
        let name = format!("Local\\komorebi-test-abandoned-{}", std::process::id());
        let retained = Handle(unsafe {
            CreateMutexW(None, false, PCWSTR(wide(&name).unwrap().as_ptr())).unwrap()
        });
        let (send, receive) = mpsc::channel();
        let worker = std::thread::spawn(move || {
            let handle = Handle(unsafe {
                CreateMutexW(None, false, PCWSTR(wide(&name).unwrap().as_ptr())).unwrap()
            });
            assert_eq!(unsafe { WaitForSingleObject(handle.0, 0) }, WAIT_OBJECT_0);
            send.send(()).unwrap();
            // Close our handle without releasing ownership; the retained handle keeps the object alive.
            drop(handle);
        });
        receive.recv_timeout(Duration::from_secs(2)).unwrap();
        worker.join().unwrap();
        assert_eq!(
            unsafe { WaitForSingleObject(retained.0, 0) },
            WAIT_ABANDONED
        );
        unsafe {
            ReleaseMutex(retained.0).unwrap();
        }
    }
}
