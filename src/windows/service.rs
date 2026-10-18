use super::poll;
use anyhow::{Context, Result};
use std::{mem::size_of, time::Duration};
use windows::{
    Win32::System::Services::*,
    core::{PCWSTR, w},
};

struct Service(SC_HANDLE);
impl Drop for Service {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseServiceHandle(self.0);
        }
    }
}

fn status(service: &Service) -> Result<SERVICE_STATUS_PROCESS> {
    let mut value = SERVICE_STATUS_PROCESS::default();
    let buffer = unsafe {
        std::slice::from_raw_parts_mut(
            (&mut value as *mut SERVICE_STATUS_PROCESS).cast(),
            size_of::<SERVICE_STATUS_PROCESS>(),
        )
    };
    let mut needed = 0;
    unsafe {
        QueryServiceStatusEx(service.0, SC_STATUS_PROCESS_INFO, Some(buffer), &mut needed)?;
    }
    Ok(value)
}

// This runs only in a bounded child. SCM control calls can themselves block.
pub fn restart_night_light() -> Result<()> {
    let manager =
        Service(unsafe { OpenSCManagerW(PCWSTR::null(), PCWSTR::null(), SC_MANAGER_CONNECT)? });
    let service = Service(unsafe {
        OpenServiceW(
            manager.0,
            w!("DisplayEnhancementService"),
            SERVICE_QUERY_STATUS | SERVICE_STOP | SERVICE_START,
        )?
    });
    let current = status(&service)?.dwCurrentState;
    if current != SERVICE_STOPPED && current != SERVICE_STOP_PENDING {
        let mut stopped = SERVICE_STATUS::default();
        unsafe {
            ControlService(service.0, SERVICE_CONTROL_STOP, &mut stopped)?;
        }
    }
    poll(Duration::from_secs(8), Duration::from_millis(100), |_| {
        Ok((status(&service)?.dwCurrentState == SERVICE_STOPPED).then_some(()))
    })
    .context("waiting for Night Light service to stop")?;
    unsafe {
        StartServiceW(service.0, None)?;
    }
    poll(Duration::from_secs(8), Duration::from_millis(100), |_| {
        Ok((status(&service)?.dwCurrentState == SERVICE_RUNNING).then_some(()))
    })
    .context("waiting for Night Light service to start")
}
