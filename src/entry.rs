use anyhow::{Result, ensure};

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

pub fn elevation_arguments(recover: bool, identity: &Identity) -> Result<String> {
    ensure!(
        identity.sid.starts_with("S-1-")
            && identity
                .sid
                .bytes()
                .all(|byte| byte.is_ascii_digit() || matches!(byte, b'S' | b'-')),
        "invalid account SID"
    );
    Ok(format!(
        "restart{} --origin-sid {} --origin-session {}",
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
            elevation_arguments(true, &identity).unwrap(),
            "restart --recover-display --origin-sid S-1-5-21-1-1001 --origin-session 3"
        );
        assert!(
            !elevation_arguments(false, &identity)
                .unwrap()
                .contains("recover")
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
                }
            )
            .is_err()
        );
    }
}
