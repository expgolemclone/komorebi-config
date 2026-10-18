use komorebi_config::{
    log::Log,
    process::{self, Invocation},
    windows::privilege::RestartLock,
};
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};
use windows::Win32::{
    Foundation::{CloseHandle, ERROR_INVALID_PARAMETER, WAIT_OBJECT_0},
    System::Threading::{
        OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_SYNCHRONIZE, PROCESS_TERMINATE,
        TerminateProcess, WaitForSingleObject,
    },
};

fn fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_process-fixture"))
}
fn command(arguments: &[&str]) -> Invocation {
    Invocation::new(fixture()).args(arguments)
}

fn read_pid(path: &Path) -> u32 {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        if let Ok(text) = fs::read_to_string(path)
            && let Ok(pid) = text.trim().parse()
        {
            return pid;
        }
        assert!(
            Instant::now() < deadline,
            "fixture did not report its PID: {}",
            path.display()
        );
        thread::sleep(Duration::from_millis(10));
    }
}

fn ended(pid: u32) -> bool {
    match unsafe {
        OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SYNCHRONIZE,
            false,
            pid,
        )
    } {
        Ok(handle) => {
            let ended = unsafe { WaitForSingleObject(handle, 0) } == WAIT_OBJECT_0;
            unsafe {
                CloseHandle(handle).unwrap();
            }
            ended
        }
        Err(error)
            if error.code() == windows::core::HRESULT::from_win32(ERROR_INVALID_PARAMETER.0) =>
        {
            true
        }
        Err(error) => panic!("opening fixture {pid}: {error}"),
    }
}

struct Descendant(u32);
impl Drop for Descendant {
    fn drop(&mut self) {
        if let Ok(handle) =
            unsafe { OpenProcess(PROCESS_TERMINATE | PROCESS_SYNCHRONIZE, false, self.0) }
        {
            unsafe {
                let _ = TerminateProcess(handle, 1);
                WaitForSingleObject(handle, 2000);
                let _ = CloseHandle(handle);
            }
        }
    }
}

fn assert_ended(pid: u32) {
    let deadline = Instant::now() + Duration::from_secs(3);
    while !ended(pid) {
        assert!(
            Instant::now() < deadline,
            "descendant {pid} survived job cleanup"
        );
        thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn native_argv_preserves_unicode_spaces_quotes_empty_and_trailing_slashes() {
    let args = [
        "",
        "設定 with spaces",
        "quoted\"value",
        "C:\\path with spaces\\",
        "& | % $ ;",
        "\\\\server\\share\\",
    ];
    let result =
        process::capture(&command(&["arguments"]).args(args), Duration::from_secs(5)).unwrap();
    assert_eq!(
        serde_json::from_slice::<Vec<String>>(&result).unwrap(),
        args
    );
}

#[test]
fn failure_contains_exit_code_and_both_output_streams() {
    let error = process::capture(&command(&["failure"]), Duration::from_secs(5)).unwrap_err();
    let detail = format!("{error:#}");
    for expected in ["7", "stdout: output detail", "stderr: error detail"] {
        assert!(detail.contains(expected), "{detail}");
    }
}

#[test]
fn excessive_output_fails_without_unbounded_memory_or_deadlock() {
    let started = Instant::now();
    let error = process::capture(&command(&["flood"]), Duration::from_secs(5)).unwrap_err();
    assert!(format!("{error:#}").contains("output limit"));
    assert!(started.elapsed() < Duration::from_secs(8));
}

#[test]
fn timeout_terminates_the_entire_owned_tree() {
    let temporary = tempfile::tempdir().unwrap();
    let pid_file = temporary.path().join("descendant.pid");
    let invocation = command(&["tree"]).args([pid_file.as_os_str(), std::ffi::OsStr::new("stay")]);
    let error = process::capture(&invocation, Duration::from_millis(1500)).unwrap_err();
    assert!(format!("{error:#}").contains("timed out"));
    let descendant = Descendant(read_pid(&pid_file));
    assert_ended(descendant.0);
}

#[test]
fn completed_finite_command_does_not_leave_background_children() {
    let temporary = tempfile::tempdir().unwrap();
    let pid_file = temporary.path().join("descendant.pid");
    process::capture(
        &command(&["tree"]).args([pid_file.as_os_str()]),
        Duration::from_secs(5),
    )
    .unwrap();
    let descendant = Descendant(read_pid(&pid_file));
    assert_ended(descendant.0);
}

#[test]
fn launcher_failure_and_later_postflight_failure_reap_descendants() {
    let temporary = tempfile::tempdir().unwrap();
    let log = Log::open(&temporary.path().join("restart.log")).unwrap();
    for mode in ["failed-tree", "tree"] {
        let pid_file = temporary.path().join(format!("{mode}.pid"));
        let result = process::launch(
            &command(&[mode]).args([pid_file.as_os_str()]),
            Duration::from_secs(5),
            &log.output().unwrap(),
        );
        if mode == "failed-tree" {
            assert!(result.is_err());
        } else {
            drop(result.unwrap());
        }
        let descendant = Descendant(read_pid(&pid_file));
        assert_ended(descendant.0);
    }
}

#[test]
fn successful_handoff_survives_later_launches_without_waiting_for_daemon_eof() {
    let temporary = tempfile::tempdir().unwrap();
    let log = Log::open(&temporary.path().join("restart.log")).unwrap();
    let pid_file = temporary.path().join("descendant.pid");
    let started = Instant::now();
    let job = process::launch(
        &command(&["tree"]).args([pid_file.as_os_str()]),
        Duration::from_secs(5),
        &log.output().unwrap(),
    )
    .unwrap();
    let descendant = Descendant(read_pid(&pid_file));
    assert!(!ended(descendant.0));
    assert!(started.elapsed() < Duration::from_secs(5));
    job.release();
    process::capture(&command(&["arguments", "later"]), Duration::from_secs(5)).unwrap();
    assert!(
        !ended(descendant.0),
        "later launch reaped a successfully handed-off tree"
    );
}

#[test]
fn nested_native_jobs_remain_owned_by_the_outer_attempt() {
    let temporary = tempfile::tempdir().unwrap();
    let pid_file = temporary.path().join("descendant.pid");
    let log_path = temporary.path().join("restart.log");
    let log = Log::open(&log_path).unwrap();
    let job = process::launch(
        &command(&["nested-tree"]).args([pid_file.as_os_str(), log_path.as_os_str()]),
        Duration::from_secs(5),
        &log.output().unwrap(),
    )
    .unwrap();
    let descendant = Descendant(read_pid(&pid_file));
    assert!(!ended(descendant.0));
    drop(job);
    assert_ended(descendant.0);
}

#[cfg(feature = "live-tests")]
fn supervisor_case(mode: &str, seconds: &str, succeeds: bool) {
    let temporary = tempfile::tempdir().unwrap();
    let local = std::env::var_os("LOCALAPPDATA").unwrap();
    let runner = PathBuf::from(local).join("task-scheduler-management/bin/task-runner.exe");
    assert!(
        runner.is_file(),
        "installed task-runner is required for this explicit test"
    );
    let pid_file = temporary.path().join("descendant.pid");
    let log_path = temporary.path().join("native.log");
    let report = temporary.path().join("report.json");
    let log = Log::open(&log_path).unwrap();
    let invocation = Invocation::new(runner).args([
        std::ffi::OsString::from("--task-identity"),
        format!("\\NativeKomorebiTest-{mode}-{}", std::process::id()).into(),
        "--program".into(),
        fixture().into_os_string(),
        "--handoff".into(),
        "--attempt-timeout-seconds".into(),
        seconds.into(),
        "--action-working-directory".into(),
        temporary.path().as_os_str().to_owned(),
        "--report-path".into(),
        report.clone().into_os_string(),
        "--log-path".into(),
        temporary.path().join("supervisor.log").into_os_string(),
        format!("--arg={mode}").into(),
        format!("--arg={}", pid_file.display()).into(),
        format!("--arg={}", log_path.display()).into(),
    ]);
    let job = process::launch(&invocation, Duration::from_secs(15), &log.output().unwrap());
    let descendant = Descendant(read_pid(&pid_file));
    let report: serde_json::Value = serde_json::from_slice(&fs::read(report).unwrap()).unwrap();
    if succeeds {
        assert_eq!(report["exitCode"], 0);
        assert!(!ended(descendant.0));
        drop(job.unwrap());
    } else {
        assert!(job.is_err());
        assert_ne!(report["exitCode"], 0);
        assert_eq!(report["attempts"][0]["timedOut"], true);
    }
    assert_ended(descendant.0);
}

#[cfg(feature = "live-tests")]
#[test]
fn installed_supervisor_hands_off_nested_native_jobs() {
    supervisor_case("nested-tree", "10", true);
}

#[cfg(feature = "live-tests")]
#[test]
fn installed_supervisor_timeout_reaps_nested_native_jobs() {
    supervisor_case("nested-stay", "1", false);
}

#[cfg(feature = "live-tests")]
#[test]
fn repository_map_does_not_depend_on_an_inherited_interactive_execution_policy() {
    let expected = komorebi_config::config::repository_root().unwrap();
    for policy in [None, Some("Restricted")] {
        let output = process::capture(
            &command(&["repository-root"]).env("PSExecutionPolicyPreference", policy),
            Duration::from_secs(40),
        )
        .unwrap();
        let actual: PathBuf = serde_json::from_slice(&output).unwrap();
        assert_eq!(actual, expected);
    }
}

#[test]
fn child_environment_is_scoped_and_can_remove_legacy_variables() {
    let invocation = command(&["environment", "KOMOREBI_TEST_ONLY"])
        .env("KOMOREBI_TEST_ONLY", Some("child value"));
    assert_eq!(
        process::capture(&invocation, Duration::from_secs(5)).unwrap(),
        b"child value"
    );
    let cleared = invocation.env("KOMOREBI_TEST_ONLY", None::<&str>);
    assert!(
        process::capture(&cleared, Duration::from_secs(5))
            .unwrap()
            .is_empty()
    );
    assert!(std::env::var_os("KOMOREBI_TEST_ONLY").is_none());
}

#[test]
fn named_lock_serializes_separate_processes() {
    let name = format!("Local\\komorebi-fixture-{}", std::process::id());
    let guard = RestartLock::named(&name).unwrap().unwrap();
    assert!(process::capture(&command(&["lock", &name]), Duration::from_secs(5)).is_err());
    drop(guard);
    process::capture(&command(&["lock", &name]), Duration::from_secs(5)).unwrap();
}

#[test]
fn early_restart_errors_are_logged_even_with_nul_output_handles() {
    let temporary = tempfile::tempdir().unwrap();
    let status = Command::new(env!("CARGO_BIN_EXE_komorebi-config"))
        .arg("restart")
        .env("LOCALAPPDATA", temporary.path())
        .env("SystemRoot", temporary.path())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap();
    assert!(!status.success());
    let log = fs::read_to_string(temporary.path().join("komorebi/restart.log")).unwrap();
    assert!(log.contains("restart failed:"));
    assert!(log.contains("Windows tool is missing:"));
    assert!(!log.contains("stopping managed processes"));
}

#[cfg(not(debug_assertions))]
#[test]
fn release_entrypoint_does_not_allocate_a_console() {
    let image = fs::read(env!("CARGO_BIN_EXE_komorebi-config")).unwrap();
    let pe = u32::from_le_bytes(image[0x3c..0x40].try_into().unwrap()) as usize;
    assert_eq!(&image[pe..pe + 4], b"PE\0\0");
    let subsystem = pe + 24 + 68;
    assert_eq!(
        u16::from_le_bytes(image[subsystem..subsystem + 2].try_into().unwrap()),
        2
    );
}

#[test]
fn cli_help_and_version_are_native_and_do_not_start_the_desktop() {
    for argument in ["--help", "--version"] {
        let result = Command::new(env!("CARGO_BIN_EXE_komorebi-config"))
            .arg(argument)
            .output()
            .unwrap();
        assert!(result.status.success());
        assert!(
            String::from_utf8(result.stdout)
                .unwrap()
                .contains("komorebi-config")
        );
    }
    let result = Command::new(env!("CARGO_BIN_EXE_komorebi-config"))
        .args(["restart", "--origin-sid", "S-1-5"])
        .output()
        .unwrap();
    assert!(!result.status.success());
}
