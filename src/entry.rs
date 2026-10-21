use anyhow::{Context, Result, ensure};
use std::path::Path;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Identity {
    pub sid: String,
    pub session: u32,
}

pub fn validate_identity(current: &Identity, origin: Option<&Identity>) -> Result<()> {
    if let Some(origin) = origin {
        ensure!(
            current == origin,
            "elevation changed account or interactive session; refusing to select another configuration"
        );
    }
    Ok(())
}

pub fn elevation_arguments(recover: bool, identity: &Identity, directory: &Path) -> Result<String> {
    ensure!(
        identity.sid.starts_with("S-1-")
            && identity
                .sid
                .bytes()
                .all(|byte| byte.is_ascii_digit() || matches!(byte, b'S' | b'-')),
        "invalid account SID"
    );
    ensure!(
        directory.is_absolute(),
        "configuration directory must be absolute"
    );
    let path = directory
        .to_str()
        .context("configuration path is not valid Unicode")?;
    ensure!(!path.contains(['"', '\0']), "invalid configuration path");
    let trailing = "\\".repeat(path.chars().rev().take_while(|&ch| ch == '\\').count());
    Ok(format!(
        "restart --config-directory \"{path}{trailing}\"{} --origin-sid {} --origin-session {}",
        if recover { " --recover-display" } else { "" },
        identity.sid,
        identity.session
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn elevation_forwards_only_supported_arguments_and_identity() {
        let identity = Identity {
            sid: "S-1-5-21-1-1001".into(),
            session: 3,
        };
        assert_eq!(
            elevation_arguments(
                true,
                &identity,
                Path::new("C:\\settings\\日本語's directory")
            )
            .unwrap(),
            "restart --config-directory \"C:\\settings\\日本語's directory\" --recover-display --origin-sid S-1-5-21-1-1001 --origin-session 3"
        );
        assert!(
            !elevation_arguments(false, &identity, Path::new("C:\\settings"))
                .unwrap()
                .contains("recover")
        );
    }

    #[test]
    fn configuration_path_is_literal_and_cannot_add_elevation_options() {
        let identity = Identity {
            sid: "S-1-5-21-1-1001".into(),
            session: 3,
        };
        assert!(elevation_arguments(false, &identity, Path::new("relative")).is_err());
        assert!(
            elevation_arguments(false, &identity, Path::new("C:\\bad\" --recover-display"))
                .is_err()
        );
        assert_eq!(
            elevation_arguments(false, &identity, Path::new("C:\\")).unwrap(),
            "restart --config-directory \"C:\\\\\" --origin-sid S-1-5-21-1-1001 --origin-session 3"
        );
    }

    #[test]
    fn cross_account_or_session_elevation_is_rejected() {
        let current = Identity {
            sid: "S-1-5-21-1-1001".into(),
            session: 3,
        };
        validate_identity(&current, Some(&current)).unwrap();
        for origin in [
            Identity {
                sid: "S-1-5-21-1-1002".into(),
                session: 3,
            },
            Identity {
                sid: current.sid.clone(),
                session: 4,
            },
        ] {
            assert!(validate_identity(&current, Some(&origin)).is_err());
        }
        assert!(
            elevation_arguments(
                false,
                &Identity {
                    sid: "S-1-5; bad".into(),
                    session: 3
                },
                Path::new("C:\\settings")
            )
            .is_err()
        );
    }
}
