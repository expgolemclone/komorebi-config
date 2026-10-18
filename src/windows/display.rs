use super::wide;
use crate::model::{Screen, Size, cursor_target};
use anyhow::{Context, Result, ensure};
use std::mem::size_of;
use windows::{
    Win32::{
        Devices::DeviceAndDriverInstallation::*,
        Foundation::{ERROR_INSUFFICIENT_BUFFER, ERROR_NO_MORE_ITEMS, LPARAM, RECT},
        Graphics::Gdi::{EnumDisplayMonitors, GetMonitorInfoW, HDC, HMONITOR, MONITORINFO},
        UI::{
            HiDpi::{
                DPI_AWARENESS_CONTEXT, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
                SetThreadDpiAwarenessContext,
            },
            WindowsAndMessaging::{GetForegroundWindow, GetWindowRect, SetCursorPos},
        },
    },
    core::{BOOL, Error, HRESULT, PCWSTR},
};

struct Dpi(DPI_AWARENESS_CONTEXT);

impl Dpi {
    fn enter() -> Result<Self> {
        let previous =
            unsafe { SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) };
        ensure!(
            !previous.0.is_null(),
            "enabling physical screen coordinates: {}",
            Error::from_thread()
        );
        Ok(Self(previous))
    }
}

impl Drop for Dpi {
    fn drop(&mut self) {
        unsafe {
            SetThreadDpiAwarenessContext(self.0);
        }
    }
}

pub fn screens() -> Result<Vec<Screen>> {
    struct Enumeration {
        screens: Vec<Screen>,
        error: Option<Error>,
    }
    unsafe extern "system" fn monitor(
        monitor: HMONITOR,
        _: HDC,
        _: *mut RECT,
        data: LPARAM,
    ) -> BOOL {
        let state = unsafe { &mut *(data.0 as *mut Enumeration) };
        let mut info = MONITORINFO {
            cbSize: size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        if !unsafe { GetMonitorInfoW(monitor, &mut info) }.as_bool() {
            state.error = Some(Error::from_thread());
            return BOOL(0);
        }
        state.screens.push(Screen {
            left: info.rcMonitor.left,
            top: info.rcMonitor.top,
            size: Size {
                width: info.rcMonitor.right - info.rcMonitor.left,
                height: info.rcMonitor.bottom - info.rcMonitor.top,
            },
        });
        BOOL(1)
    }
    let _dpi = Dpi::enter()?;
    let mut state = Enumeration {
        screens: Vec::new(),
        error: None,
    };
    let success = unsafe {
        EnumDisplayMonitors(
            None,
            None,
            Some(monitor),
            LPARAM((&mut state as *mut Enumeration) as isize),
        )
    };
    if let Some(error) = state.error {
        return Err(error).context("reading physical monitor geometry");
    }
    success.ok().context("enumerating active monitors")?;
    ensure!(
        !state.screens.is_empty(),
        "Windows reported no active screens"
    );
    for screen in &state.screens {
        screen.size.validate()?;
    }
    state.screens.sort();
    Ok(state.screens)
}

pub fn move_cursor() -> Result<()> {
    let _dpi = Dpi::enter()?;
    let window = unsafe { GetForegroundWindow() };
    ensure!(!window.0.is_null(), "no foreground window");
    let mut rect = RECT::default();
    unsafe {
        GetWindowRect(window, &mut rect)?;
    }
    let (x, y) = cursor_target(rect.left, rect.top, rect.right, rect.bottom)?;
    ensure!(
        unsafe { GetForegroundWindow() } == window,
        "foreground window changed while reading its bounds"
    );
    unsafe {
        SetCursorPos(x, y)?;
    }
    Ok(())
}

struct DeviceSet(HDEVINFO);
impl Drop for DeviceSet {
    fn drop(&mut self) {
        unsafe {
            let _ = SetupDiDestroyDeviceInfoList(self.0);
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Adapter {
    pub instance: String,
}

pub fn healthy_adapters() -> Result<Vec<Adapter>> {
    let devices = DeviceSet(unsafe {
        SetupDiGetClassDevsW(
            Some(&GUID_DEVCLASS_DISPLAY),
            PCWSTR::null(),
            None,
            DIGCF_PRESENT,
        )?
    });
    let mut adapters = Vec::new();
    for index in 0.. {
        let mut device = SP_DEVINFO_DATA {
            cbSize: size_of::<SP_DEVINFO_DATA>() as u32,
            ..Default::default()
        };
        if let Err(error) = unsafe { SetupDiEnumDeviceInfo(devices.0, index, &mut device) } {
            if error.code() == HRESULT::from_win32(ERROR_NO_MORE_ITEMS.0) {
                break;
            }
            return Err(error).context("enumerating display adapters");
        }
        let mut status = CM_DEVNODE_STATUS_FLAGS::default();
        let mut problem = CM_PROB::default();
        ensure!(
            unsafe { CM_Get_DevNode_Status(&mut status, &mut problem, device.DevInst, 0) }
                == CR_SUCCESS,
            "cannot read display adapter health"
        );
        if status.0 & DN_STARTED.0 == 0 || problem.0 != 0 {
            continue;
        }
        let mut length = 0;
        let error =
            unsafe { SetupDiGetDeviceInstanceIdW(devices.0, &device, None, Some(&mut length)) }
                .err()
                .context("unexpected successful zero-length device ID query")?;
        ensure!(
            error.code() == HRESULT::from_win32(ERROR_INSUFFICIENT_BUFFER.0),
            "querying device ID size: {error}"
        );
        let mut id = vec![0u16; length as usize];
        unsafe {
            SetupDiGetDeviceInstanceIdW(devices.0, &device, Some(&mut id), None)?;
        }
        let end = id
            .iter()
            .position(|value| *value == 0)
            .context("unterminated display adapter ID")?;
        adapters.push(Adapter {
            instance: String::from_utf16(&id[..end])?,
        });
    }
    Ok(adapters)
}

pub fn adapter_argument(adapter: &Adapter) -> Result<std::ffi::OsString> {
    wide(&adapter.instance)?;
    Ok(adapter.instance.clone().into())
}
