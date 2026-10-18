use anyhow::{Context, Result, ensure};
use serde::Deserialize;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd)]
pub struct Size {
    #[serde(rename = "right")]
    pub width: i32,
    #[serde(rename = "bottom")]
    pub height: i32,
}

impl Size {
    pub fn validate(self) -> Result<Self> {
        ensure!(
            self.width > 0 && self.height > 0,
            "invalid dimensions: {}x{}",
            self.width,
            self.height
        );
        Ok(self)
    }
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct Screen {
    pub left: i32,
    pub top: i32,
    pub size: Size,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
pub enum Layout {
    Columns,
    Rows,
}

impl Layout {
    pub fn command(self) -> &'static str {
        match self {
            Self::Columns => "columns",
            Self::Rows => "rows",
        }
    }
}

pub fn layouts(sizes: &[Size], screens: &[Screen]) -> Result<Vec<Layout>> {
    ensure!(!sizes.is_empty(), "komorebi did not detect any monitors");
    ensure!(
        sizes.len() == screens.len(),
        "komorebi detected {} monitors, Windows reported {}",
        sizes.len(),
        screens.len()
    );
    for size in sizes
        .iter()
        .copied()
        .chain(screens.iter().map(|screen| screen.size))
    {
        size.validate()?;
    }
    let mut windows_sizes: Vec<_> = screens.iter().map(|screen| screen.size).collect();
    let mut daemon_sizes = sizes.to_vec();
    windows_sizes.sort();
    daemon_sizes.sort();
    ensure!(
        windows_sizes == daemon_sizes,
        "komorebi monitor sizes {daemon_sizes:?} differ from Windows {windows_sizes:?}"
    );
    Ok(sizes
        .iter()
        .map(|size| {
            if size.width > size.height {
                Layout::Columns
            } else {
                Layout::Rows
            }
        })
        .collect())
}

pub fn cursor_target(left: i32, top: i32, right: i32, bottom: i32) -> Result<(i32, i32)> {
    let width = i64::from(right) - i64::from(left);
    ensure!(
        width > 0 && bottom > top,
        "foreground window has invalid bounds"
    );
    Ok((
        i32::try_from(i64::from(left) + width / 2).context("cursor x overflow")?,
        bottom.checked_sub(10).context("cursor y overflow")?,
    ))
}

#[derive(Deserialize)]
struct MonitorInformation {
    size: Size,
}

pub fn monitor_sizes(json: &[u8]) -> Result<Vec<Size>> {
    let monitors: Vec<MonitorInformation> =
        serde_json::from_slice(json).context("invalid monitor-information JSON")?;
    Ok(monitors.into_iter().map(|monitor| monitor.size).collect())
}

#[derive(Deserialize)]
struct Ring<T> {
    elements: Vec<T>,
}

#[derive(Deserialize)]
struct State {
    monitors: Ring<Monitor>,
}

#[derive(Deserialize)]
struct Monitor {
    size: Size,
    workspaces: Ring<Workspace>,
}

#[derive(Deserialize)]
struct Workspace {
    layout: serde_json::Value,
}

pub fn verify_state(json: &[u8], screens: &[Screen], expected: &[Layout]) -> Result<()> {
    let state: State = serde_json::from_slice(json).context("invalid komorebi state JSON")?;
    let sizes: Vec<_> = state
        .monitors
        .elements
        .iter()
        .map(|monitor| monitor.size)
        .collect();
    ensure!(
        layouts(&sizes, screens)? == expected,
        "monitor topology changed during restart"
    );
    for (index, (monitor, layout)) in state.monitors.elements.iter().zip(expected).enumerate() {
        ensure!(
            monitor.workspaces.elements.len() == 1,
            "monitor {index} must have exactly one workspace"
        );
        let actual = &monitor.workspaces.elements[0].layout;
        let wanted = serde_json::json!({ "Default": format!("{layout:?}") });
        ensure!(
            actual == &wanted,
            "monitor {index} workspace 0 layout is {actual}, expected {wanted}"
        );
    }
    Ok(())
}

#[derive(Default)]
pub struct Stability {
    consecutive: usize,
}

impl Stability {
    pub fn sample(&mut self, matches: bool, required: usize) -> bool {
        self.consecutive = if matches { self.consecutive + 1 } else { 0 };
        self.consecutive >= required
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn screen(width: i32, height: i32) -> Screen {
        Screen {
            left: 0,
            top: 0,
            size: Size { width, height },
        }
    }

    #[test]
    fn orientation_preserves_daemon_order_not_windows_order() {
        let screens = [screen(900, 1600), screen(1920, 1080), screen(800, 800)];
        let sizes = [screens[1].size, screens[2].size, screens[0].size];
        assert_eq!(
            layouts(&sizes, &screens).unwrap(),
            [Layout::Columns, Layout::Rows, Layout::Rows]
        );
    }

    #[test]
    fn duplicate_sizes_are_counted() {
        let screens = [screen(900, 1600), screen(900, 1600)];
        assert_eq!(
            layouts(&[screens[0].size; 2], &screens).unwrap(),
            [Layout::Rows; 2]
        );
        assert!(layouts(&[screens[0].size], &screens).is_err());
    }

    #[test]
    fn invalid_dimensions_and_mismatched_topology_fail() {
        for size in [
            Size {
                width: 0,
                height: 100,
            },
            Size {
                width: 100,
                height: -1,
            },
        ] {
            assert!(
                layouts(
                    &[size],
                    &[Screen {
                        left: 0,
                        top: 0,
                        size
                    }]
                )
                .is_err()
            );
        }
        assert!(layouts(&[], &[]).is_err());
        assert!(layouts(&[screen(100, 200).size], &[screen(200, 100)]).is_err());
    }

    #[test]
    fn cursor_uses_integer_width_and_signed_physical_coordinates() {
        assert_eq!(cursor_target(-1921, -100, 0, 1000).unwrap(), (-961, 990));
        assert_eq!(cursor_target(100, 0, 201, 301).unwrap(), (150, 291));
        assert!(cursor_target(1, 0, 1, 100).is_err());
        assert!(cursor_target(0, 2, 100, 1).is_err());
        assert!(cursor_target(0, i32::MIN, 100, i32::MIN + 1).is_err());
    }

    #[test]
    fn stability_resets_on_any_mismatch() {
        let mut stable = Stability::default();
        assert!(!stable.sample(true, 3));
        assert!(!stable.sample(false, 3));
        assert!(!stable.sample(true, 3));
        assert!(!stable.sample(true, 3));
        assert!(stable.sample(true, 3));
    }

    #[test]
    fn state_requires_exactly_one_correct_workspace() {
        let screens = [screen(1920, 1080)];
        let state = serde_json::json!({ "monitors": { "elements": [{ "size": { "right": 1920, "bottom": 1080 }, "workspaces": { "elements": [{ "layout": { "Default": "Columns" } }] } }] } });
        let encoded = serde_json::to_vec(&state).unwrap();
        verify_state(&encoded, &screens, &[Layout::Columns]).unwrap();
        let mut wrong = state;
        wrong["monitors"]["elements"][0]["workspaces"]["elements"] = serde_json::json!([]);
        assert!(
            verify_state(
                &serde_json::to_vec(&wrong).unwrap(),
                &screens,
                &[Layout::Columns]
            )
            .is_err()
        );
        assert!(monitor_sizes(b"not JSON").is_err());
    }
}
