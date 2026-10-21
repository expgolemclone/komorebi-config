use komorebi_config::config::{read, schema_version, validate_native_bindings};
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn configuration() -> Value {
    read(&root()).unwrap()
}

#[test]
fn configuration_retains_automatic_monitors_and_visual_settings() {
    let config = configuration();
    for absent in ["monitors", "display_index_preferences"] {
        assert!(config.get(absent).is_none());
    }
    assert!(!root().join("komorebi.bar.json").exists());
    assert_eq!(config["default_workspace_padding"], 0);
    assert_eq!(config["default_container_padding"], 0);
    assert_eq!(config["border"], true);
    assert_eq!(config["border_width"], 8);
    assert_eq!(config["border_implementation"], "Windows");
    assert_eq!(config["mouse_follows_focus"], false);
    for name in ["single", "stack", "monocle", "floating"] {
        assert_eq!(config["border_colours"][name], "#00FFFF");
    }
    schema_version(&config).unwrap();
}

#[test]
fn configuration_preserves_console_office_outlook_and_libreoffice_rules() {
    let config = configuration();
    let rule = |kind: &str, id: &str, strategy: &str| json!({"kind": kind, "id": id, "matching_strategy": strategy});
    assert_eq!(
        config["manage_rules"],
        json!([rule("Class", "ConsoleWindowClass", "Equals")])
    );
    assert!(config["ignore_rules"].as_array().unwrap().contains(&rule(
        "Exe",
        "OUTLOOK.EXE",
        "Equals"
    )));
    assert!(
        config["ignore_rules"]
            .as_array()
            .unwrap()
            .contains(&rule("Class", "_WwB", "Legacy"))
    );
    assert_eq!(
        config["layered_applications"],
        json!([
            rule("Exe", "EXCEL.EXE", "Equals"),
            rule("Exe", "POWERPNT.EXE", "Equals"),
            rule("Exe", "WINWORD.EXE", "Equals")
        ])
    );
    assert!(
        config["object_name_change_applications"]
            .as_array()
            .unwrap()
            .contains(&rule("Exe", "soffice.bin", "Equals"))
    );
}

#[test]
fn schema_version_rejects_missing_malformed_and_foreign_urls() {
    for schema in [
        json!(null),
        json!("https://example.com/v1.2.3/schema.json"),
        json!("https://raw.githubusercontent.com/LGUG2Z/komorebi/v1..3/schema.json"),
    ] {
        assert!(schema_version(&json!({"$schema": schema})).is_err());
    }
}

#[test]
fn hotkeys_continue_to_target_only_workspace_zero() {
    validate_native_bindings(&root()).unwrap();
    let keys = fs::read_to_string(root().join("whkdrc")).unwrap();
    assert!(keys.lines().any(|line| line.trim() == ".shell cmd"));
    for line in keys
        .lines()
        .filter(|line| line.contains("focus-workspace") || line.contains("move-to-workspace"))
    {
        assert!(line.trim_end().ends_with("workspace 0"));
    }
    assert!(keys.contains("komorebic replace-configuration"));
    assert!(!keys.contains("reload-configuration"));
}

#[test]
fn native_restart_requires_complete_native_hotkey_bindings() {
    let temporary = tempfile::tempdir().unwrap();
    fs::write(
        temporary.path().join("whkdrc"),
        ".shell cmd\nKOMOREBI_AUTOHOTKEY\n",
    )
    .unwrap();
    assert!(validate_native_bindings(temporary.path()).is_err());
    let binding = |direction| {
        format!(
            "alt + x : komorebic focus {direction} && start \"\" /b \"komorebi-config.exe\" move-cursor\n"
        )
    };
    let keys = format!(
        ".shell cmd\n{}",
        ["left", "down", "up", "right"].map(binding).join("")
    );
    fs::write(temporary.path().join("whkdrc"), &keys).unwrap();
    validate_native_bindings(temporary.path()).unwrap();
    fs::write(
        temporary.path().join("whkdrc"),
        keys.replace(&binding("right"), ""),
    )
    .unwrap();
    assert!(validate_native_bindings(temporary.path()).is_err());
}

#[test]
fn configuration_directory_is_explicit_absolute_and_complete() {
    assert!(komorebi_config::config::directory(Path::new(".")).is_err());
    let temporary = tempfile::tempdir().unwrap();
    let directory = temporary.path().join("日本語's configuration");
    fs::create_dir(&directory).unwrap();
    assert!(komorebi_config::config::directory(&directory).is_err());
    fs::write(directory.join("komorebi.json"), "{}\n").unwrap();
    assert!(komorebi_config::config::directory(&directory).is_err());
    fs::write(directory.join("whkdrc"), ".shell cmd\n").unwrap();
    assert_eq!(
        komorebi_config::config::directory(&directory).unwrap(),
        directory.canonicalize().unwrap()
    );
    assert!(komorebi_config::config::directory(&directory.join("komorebi.json")).is_err());
}

fn check_text(path: &Path) {
    let bytes = fs::read(path).unwrap();
    assert!(
        std::str::from_utf8(&bytes).is_ok(),
        "{} is not UTF-8",
        path.display()
    );
    assert!(
        !bytes.windows(2).any(|pair| pair == b"\r\n"),
        "{} has CRLF",
        path.display()
    );
}

fn check_directory(path: &Path) {
    for entry in fs::read_dir(path).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            check_directory(&path);
        } else {
            check_text(&path);
        }
    }
}

#[test]
fn maintained_native_sources_and_configuration_are_utf8_lf() {
    for name in [
        "Cargo.toml",
        "Cargo.lock",
        "README.md",
        ".gitignore",
        ".gitattributes",
        "komorebi.json",
        "whkdrc",
    ] {
        check_text(&root().join(name));
    }
    check_directory(&root().join("src"));
    check_directory(&root().join("tests/native"));
}
