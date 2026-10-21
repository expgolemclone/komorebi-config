use komorebi_config::{
    config, model,
    process::{Invocation, capture},
    windows::{display, processes},
};
use serde_json::{Value, json};
use std::time::Duration;

#[test]
fn installed_schema_accepts_the_configuration() {
    let root = config::directory(std::path::Path::new(env!("CARGO_MANIFEST_DIR"))).unwrap();
    let configuration = config::read(&root).unwrap();
    let command = which::which("komorebic").unwrap();
    let invocation = Invocation::new(&command);
    let version = capture(
        &invocation.clone().args(["--version"]),
        Duration::from_secs(10),
    )
    .unwrap();
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
            &invocation.args(["static-config-schema"]),
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
    let root = config::directory(std::path::Path::new(env!("CARGO_MANIFEST_DIR"))).unwrap();
    let invocation = Invocation::new(which::which("komorebic").unwrap())
        .env("KOMOREBI_CONFIG_HOME", Some(&root))
        .env("WHKD_CONFIG_HOME", Some(&root));
    let temporary = tempfile::tempdir().unwrap();
    let invalid = temporary.path().join("invalid.json");
    std::fs::write(&invalid, br#"{"border_width":"not a number"}"#).unwrap();
    let result = capture(
        &invocation.args([
            std::ffi::OsString::from("check"),
            "--komorebi-config".into(),
            invalid.into_os_string(),
        ]),
        Duration::from_secs(10),
    );
    assert!(result.is_err());
    assert!(format!("{:#}", result.unwrap_err()).contains("not a number"));
}

#[test]
fn live_daemon_monitors_layouts_processes_and_application_rules_match() {
    let invocation = Invocation::new(which::which("komorebic").unwrap());
    let screens = display::screens().unwrap();
    let monitor_json = capture(
        &invocation.clone().args(["monitor-information"]),
        Duration::from_secs(10),
    )
    .unwrap();
    let layouts = model::layouts(&model::monitor_sizes(&monitor_json).unwrap(), &screens).unwrap();
    let state = capture(&invocation.clone().args(["state"]), Duration::from_secs(10)).unwrap();
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
        &capture(&invocation.args(["global-state"]), Duration::from_secs(10)).unwrap(),
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
