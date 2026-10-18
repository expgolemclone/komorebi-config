use super::{Handle, paths_equal, privilege, wait};
use anyhow::{Context, Result, ensure};
use std::{
    ffi::OsString,
    mem::size_of,
    os::windows::ffi::OsStringExt,
    path::PathBuf,
    time::{Duration, Instant},
};
use windows::{
    Win32::{
        Foundation::{ERROR_INVALID_PARAMETER, ERROR_NO_MORE_FILES},
        System::{
            Diagnostics::ToolHelp::{
                CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW,
                TH32CS_SNAPPROCESS,
            },
            Threading::{
                OpenProcess, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
                PROCESS_SYNCHRONIZE, PROCESS_TERMINATE, QueryFullProcessImageNameW,
                TerminateProcess,
            },
        },
    },
    core::{HRESULT, PWSTR},
};

pub struct ManagedProcess {
    pub pid: u32,
    pub executable: PathBuf,
    handle: Handle,
}

pub fn find(paths: &[PathBuf], terminate: bool) -> Result<Vec<ManagedProcess>> {
    let current_session = privilege::session(std::process::id())?;
    let snapshot = Handle(unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)? });
    let mut entry = PROCESSENTRY32W {
        dwSize: size_of::<PROCESSENTRY32W>() as u32,
        ..Default::default()
    };
    let mut next = unsafe { Process32FirstW(snapshot.0, &mut entry) };
    let mut result = Vec::new();
    loop {
        if let Err(error) = next {
            if error.code() == HRESULT::from_win32(ERROR_NO_MORE_FILES.0) {
                break;
            }
            return Err(error).context("enumerating managed processes");
        }
        let length = entry
            .szExeFile
            .iter()
            .position(|value| *value == 0)
            .context("unterminated process name")?;
        let name = OsString::from_wide(&entry.szExeFile[..length]);
        let candidates: Vec<_> = paths
            .iter()
            .filter(|path| {
                path.file_name().is_some_and(|file| {
                    file.to_string_lossy()
                        .eq_ignore_ascii_case(&name.to_string_lossy())
                })
            })
            .collect();
        if !candidates.is_empty() {
            let session = privilege::session(entry.th32ProcessID);
            let session = match session {
                Ok(session) => Some(session),
                Err(error)
                    if error
                        .downcast_ref::<windows::core::Error>()
                        .is_some_and(|error| {
                            error.code() == HRESULT::from_win32(ERROR_INVALID_PARAMETER.0)
                        }) =>
                {
                    None
                }
                Err(error) => return Err(error),
            };
            if session == Some(current_session) {
                let rights = PROCESS_QUERY_LIMITED_INFORMATION
                    | PROCESS_SYNCHRONIZE
                    | if terminate {
                        PROCESS_TERMINATE
                    } else {
                        Default::default()
                    };
                let handle = match unsafe { OpenProcess(rights, false, entry.th32ProcessID) } {
                    Ok(handle) => Some(Handle(handle)),
                    Err(error)
                        if error.code() == HRESULT::from_win32(ERROR_INVALID_PARAMETER.0) =>
                    {
                        None
                    }
                    Err(error) => return Err(error).context("opening managed process"),
                };
                if let Some(handle) = handle
                    && !wait(handle.0, Duration::ZERO)?
                {
                    let mut buffer = vec![0u16; 32768];
                    let mut length = buffer.len() as u32;
                    unsafe {
                        QueryFullProcessImageNameW(
                            handle.0,
                            PROCESS_NAME_WIN32,
                            PWSTR(buffer.as_mut_ptr()),
                            &mut length,
                        )?;
                    }
                    let executable = PathBuf::from(OsString::from_wide(&buffer[..length as usize]))
                        .canonicalize()?;
                    let mut expected = false;
                    for candidate in candidates {
                        expected |= paths_equal(candidate, &executable)?;
                    }
                    ensure!(
                        expected,
                        "conflicting managed process from another installation: {}",
                        executable.display()
                    );
                    result.push(ManagedProcess {
                        pid: entry.th32ProcessID,
                        executable,
                        handle,
                    });
                }
            }
        }
        next = unsafe { Process32NextW(snapshot.0, &mut entry) };
    }
    Ok(result)
}

pub fn stop(paths: &[PathBuf]) -> Result<()> {
    let processes = find(paths, true)?;
    for process in &processes {
        if let Err(error) = unsafe { TerminateProcess(process.handle.0, 1) }
            && !wait(process.handle.0, Duration::ZERO)?
        {
            return Err(error).context("stopping managed process");
        }
    }
    let deadline = Instant::now() + Duration::from_secs(10);
    for process in &processes {
        ensure!(
            wait(
                process.handle.0,
                deadline.saturating_duration_since(Instant::now())
            )?,
            "process {} did not stop within 10s",
            process.pid
        );
    }
    ensure!(
        find(paths, false)?.is_empty(),
        "a managed process restarted during shutdown"
    );
    Ok(())
}
