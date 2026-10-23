use komorebi_config::{
    config,
    log::Log,
    model,
    process::capture,
    restart::{Backend, Native},
    windows::{display, processes},
};
use serde_json::{Value, json};
use std::{fs, path::Path, process::Command, time::Duration};

fn komorebic(arguments: &[&str]) -> Command {
    let mut command = Command::new(which::which("komorebic.exe").unwrap());
    command.args(arguments);
    command
}

#[test]
fn installed_schema_accepts_the_configuration() {
    let root = config::directory(Path::new(env!("CARGO_MANIFEST_DIR"))).unwrap();
    let configuration = config::read(&root).unwrap();
    let version = capture(komorebic(&["--version"]), Duration::from_secs(10)).unwrap();
    assert_eq!(
        std::str::from_utf8(&version)
            .unwrap()
            .lines()
            .next()
            .unwrap(),
        format!(
            "komorebic {}",
            config::schema_version(&configuration).unwrap()
        )
    );
    let schema: Value = serde_json::from_slice(
        &capture(
            komorebic(&["static-config-schema"]),
            Duration::from_secs(10),
        )
        .unwrap(),
    )
    .unwrap();
    jsonschema::validator_for(&schema)
        .unwrap()
        .validate(&configuration)
        .unwrap();
}

#[test]
fn installed_preflight_rejects_invalid_configuration() {
    let root = config::directory(Path::new(env!("CARGO_MANIFEST_DIR"))).unwrap();
    let temporary = tempfile::tempdir().unwrap();
    let invalid = temporary.path().join("invalid.json");
    fs::write(&invalid, br#"{"border_width":"not a number"}"#).unwrap();
    let mut command = komorebic(&["check", "--komorebi-config"]);
    command
        .arg(&invalid)
        .env("KOMOREBI_CONFIG_HOME", &root)
        .env("WHKD_CONFIG_HOME", &root);
    let result = capture(command, Duration::from_secs(10));
    assert!(result.is_err());
    assert!(format!("{:#}", result.unwrap_err()).contains("not a number"));
}

#[test]
fn restart_preflight_accepts_hotkey_command_whitespace_changes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let temporary = tempfile::tempdir().unwrap();
    fs::copy(
        root.join("komorebi.json"),
        temporary.path().join("komorebi.json"),
    )
    .unwrap();
    let keys = fs::read_to_string(root.join("whkdrc")).unwrap();
    let formatted = keys.replace("komorebic ", "komorebic  ");
    assert_ne!(keys, formatted);
    fs::write(temporary.path().join("whkdrc"), formatted).unwrap();
    let log = Log::open(&temporary.path().join("restart.log")).unwrap();
    let native = Native {
        root: config::directory(temporary.path()).unwrap(),
        log: &log,
    };
    native.prepare(false).unwrap();
}

#[test]
fn live_daemon_monitors_layouts_processes_and_application_rules_match() {
    let screens = display::screens().unwrap();
    let monitor_json =
        capture(komorebic(&["monitor-information"]), Duration::from_secs(10)).unwrap();
    let layouts = model::layouts(&model::monitor_sizes(&monitor_json).unwrap(), &screens).unwrap();
    let state = capture(komorebic(&["state"]), Duration::from_secs(10)).unwrap();
    model::verify_state(&state, &screens, &layouts).unwrap();
    let managed = [
        which::which("komorebi.exe")
            .unwrap()
            .canonicalize()
            .unwrap(),
        which::which("whkd.exe").unwrap().canonicalize().unwrap(),
    ];
    let processes = processes::find(&managed, false).unwrap();
    assert_eq!(processes.len(), 2);
    for path in managed {
        assert_eq!(
            processes
                .iter()
                .filter(|process| process.executable == path)
                .count(),
            1
        );
    }
    let global: Value = serde_json::from_slice(
        &capture(komorebic(&["global-state"]), Duration::from_secs(10)).unwrap(),
    )
    .unwrap();
    for executable in ["EXCEL.EXE", "POWERPNT.EXE", "WINWORD.EXE"] {
        assert!(
            global["layered_whitelist"]
                .as_array()
                .unwrap()
                .contains(&json!({"kind": "Exe", "id": executable, "matching_strategy": "Equals"}))
        );
    }
    assert!(
        global["ignore_identifiers"]
            .as_array()
            .unwrap()
            .contains(&json!({"kind": "Class", "id": "_WwB", "matching_strategy": "Legacy"}))
    );
    assert!(
        global["name_change_on_launch_identifiers"]
            .as_array()
            .unwrap()
            .contains(&json!({"kind": "Exe", "id": "soffice.bin", "matching_strategy": "Equals"}))
    );
}
