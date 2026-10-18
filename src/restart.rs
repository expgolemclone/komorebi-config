use crate::{
    config,
    log::Log,
    model::{self, Layout, Screen, Stability},
    process::{self, Invocation, Job},
    windows::{
        display::{self, Adapter},
        poll, processes,
    },
};
use anyhow::{Context, Result, bail, ensure};
use std::{env, ffi::OsString, path::PathBuf, time::Duration};
use windows::{
    Win32::System::Registry::{HKEY_CURRENT_USER, REG_DWORD, RegSetKeyValueW},
    core::w,
};

pub trait Backend {
    type Prepared;
    type Attempt;
    fn prepare(&self, recover: bool) -> Result<Self::Prepared>;
    fn stop(&self, prepared: &Self::Prepared) -> Result<()>;
    fn recover(&self, prepared: &Self::Prepared) -> Result<()>;
    fn start(&self, prepared: &Self::Prepared) -> Result<Self::Attempt>;
    fn ready(&self, prepared: &Self::Prepared) -> Result<Vec<Layout>>;
    fn apply(&self, prepared: &Self::Prepared, layouts: &[Layout]) -> Result<()>;
    fn verify(&self, prepared: &Self::Prepared, layouts: &[Layout]) -> Result<()>;
    fn release(&self, attempt: Self::Attempt);
    fn abort(&self, attempt: Self::Attempt) -> Result<()>;
}

pub fn run(backend: &impl Backend, recover: bool) -> Result<()> {
    let prepared = backend.prepare(recover)?;
    backend.stop(&prepared)?;
    if recover {
        backend.recover(&prepared)?;
    }
    let attempt = backend.start(&prepared)?;
    let result = (|| {
        let layouts = backend.ready(&prepared)?;
        backend.apply(&prepared, &layouts)?;
        backend.verify(&prepared, &layouts)
    })();
    match result {
        Ok(()) => {
            backend.release(attempt);
            Ok(())
        }
        Err(error) => {
            if let Err(cleanup) = backend.abort(attempt) {
                bail!("{error:#}; startup cleanup failed: {cleanup:#}");
            }
            Err(error)
        }
    }
}

pub struct Native<'a> {
    pub root: PathBuf,
    pub log: &'a Log,
}

pub struct Prepared {
    command: Invocation,
    screens: Vec<Screen>,
    managed: Vec<PathBuf>,
    stop: Vec<PathBuf>,
    adapter: Option<Adapter>,
    pnputil: Option<PathBuf>,
}

fn installed(name: &str) -> Result<PathBuf> {
    which::which(name)
        .with_context(|| format!("{name} is not installed or not on PATH"))?
        .canonicalize()
        .with_context(|| format!("resolving {name}"))
}

fn single_process(count: usize) -> Result<bool> {
    ensure!(
        count <= 1,
        "multiple managed processes during readiness: {count}"
    );
    Ok(count == 1)
}

impl Native<'_> {
    fn command(
        &self,
        prepared: &Prepared,
        arguments: &[&str],
        timeout: Duration,
    ) -> Result<Vec<u8>> {
        self.log
            .event(format!("komorebic: {}", arguments.join(" ")))?;
        process::capture(&prepared.command.clone().args(arguments), timeout)
    }
}

impl Backend for Native<'_> {
    type Prepared = Prepared;
    type Attempt = Job;

    fn prepare(&self, recover: bool) -> Result<Prepared> {
        self.log.event("preflight")?;
        config::validate_native_bindings(&self.root)?;
        let shared = config::shared_executable()?;
        let configuration = config::read(&self.root)?;
        let version = config::schema_version(&configuration)?;
        let komorebic = installed("komorebic.exe")?;
        let komorebi = installed("komorebi.exe")?;
        let whkd = installed("whkd.exe")?;
        ensure!(
            komorebic.parent() == komorebi.parent(),
            "komorebic and komorebi resolve to different installations"
        );
        let mut directories: Vec<_> = [&komorebic, &whkd, &shared]
            .into_iter()
            .map(|path| {
                path.parent()
                    .context("executable has no directory")
                    .map(PathBuf::from)
            })
            .collect::<Result<_>>()?;
        let inherited = env::var_os("PATH").context("PATH is missing")?;
        for directory in env::split_paths(&inherited) {
            if !directories.iter().any(|path| {
                path.to_string_lossy()
                    .eq_ignore_ascii_case(&directory.to_string_lossy())
            }) {
                directories.push(directory);
            }
        }
        let command = Invocation::new(&komorebic)
            .env("PATH", Some(env::join_paths(directories)?))
            .env("KOMOREBI_CONFIG_HOME", Some(&self.root))
            .env("WHKD_CONFIG_HOME", Some(&self.root))
            .env("KOMOREBI_AUTOHOTKEY", None::<&str>);
        let actual = process::capture(
            &command.clone().args(["--version"]),
            Duration::from_secs(10),
        )?;
        let actual = std::str::from_utf8(&actual)?;
        ensure!(
            actual.lines().next() == Some(format!("komorebic {version}").as_str()),
            "installed komorebic version does not match configured schema {version}"
        );
        self.log
            .event("validating configuration with installed komorebic")?;
        process::capture(
            &command.clone().args([
                OsString::from("check"),
                OsString::from("--komorebi-config"),
                self.root.join("komorebi.json").into_os_string(),
            ]),
            Duration::from_secs(10),
        )
        .context("installed komorebic rejected the configuration before shutdown")?;
        let screens = display::screens()?;
        let (adapter, pnputil) = if recover {
            let adapters = display::healthy_adapters()?;
            ensure!(
                adapters.len() == 1,
                "expected exactly one healthy display adapter, found {}",
                adapters.len()
            );
            (
                adapters.into_iter().next(),
                Some(config::system_tool("System32/pnputil.exe")?),
            )
        } else {
            (None, None)
        };
        let bar = komorebi
            .parent()
            .context("komorebi directory is missing")?
            .join("komorebi-bar.exe");
        let stop = vec![komorebi.clone(), whkd.clone(), bar];
        // Detect conflicting same-session installations before any stop or setting mutation.
        processes::find(&stop, false)?;
        Ok(Prepared {
            command,
            screens,
            managed: vec![komorebi, whkd],
            stop,
            adapter,
            pnputil,
        })
    }

    fn stop(&self, prepared: &Prepared) -> Result<()> {
        self.log.event("stopping managed processes")?;
        let timeout = 1000u32;
        unsafe {
            RegSetKeyValueW(
                HKEY_CURRENT_USER,
                w!("Control Panel\\Desktop"),
                w!("LowLevelHooksTimeout"),
                REG_DWORD.0,
                Some((&timeout as *const u32).cast()),
                std::mem::size_of_val(&timeout) as u32,
            )
            .ok()?;
        }
        processes::stop(&prepared.stop)
    }

    fn recover(&self, prepared: &Prepared) -> Result<()> {
        let adapter = prepared
            .adapter
            .as_ref()
            .context("display recovery was not prepared")?;
        let pnputil = prepared
            .pnputil
            .as_ref()
            .context("PnPUtil was not prepared")?;
        self.log
            .event(format!("recovering display adapter {}", adapter.instance))?;
        process::capture(
            &Invocation::new(pnputil).args([
                OsString::from("/restart-device"),
                display::adapter_argument(adapter)?,
            ]),
            Duration::from_secs(60),
        )?;
        let mut stable = Stability::default();
        let mut last_sample = String::new();
        poll(Duration::from_secs(30), Duration::from_millis(200), |_| {
            let sample = display::healthy_adapters().and_then(|adapters| {
                let screens = display::screens()?;
                Ok(adapters.contains(adapter) && screens == prepared.screens)
            });
            let matches = match sample {
                Ok(matches) => {
                    last_sample = format!("adapter and screen geometry match: {matches}");
                    matches
                }
                Err(error) => {
                    last_sample = format!("{error:#}");
                    false
                }
            };
            Ok(stable.sample(matches, 5).then_some(()))
        })
        .with_context(|| {
            format!("waiting for display pipeline recovery; last sample: {last_sample}")
        })?;
        self.log
            .event("restarting Windows Night Light (DisplayEnhancementService)")?;
        process::capture(
            &Invocation::new(env::current_exe()?).args(["night-light-worker"]),
            Duration::from_secs(10),
        )
        .context("bounded Night Light recovery")?;
        Ok(())
    }

    fn start(&self, prepared: &Prepared) -> Result<Job> {
        self.log
            .event("starting komorebi with upstream background launcher")?;
        let attempt = process::launch(
            &prepared
                .command
                .clone()
                .args(["start", "--clean-state", "--whkd"]),
            Duration::from_secs(15),
            &self.log.output()?,
        )?;
        self.log.event(format!("upstream launcher PID {} exited successfully; retaining descendants until verification", attempt.id()))?;
        Ok(attempt)
    }

    fn ready(&self, prepared: &Prepared) -> Result<Vec<Layout>> {
        self.log.event("waiting for komorebi IPC")?;
        let mut failure = String::new();
        let monitors = poll(
            Duration::from_secs(15),
            Duration::from_millis(200),
            |remaining| {
                let running = processes::find(&prepared.managed[..1], false)?;
                if !single_process(running.len())? {
                    failure = "komorebi has not started yet".into();
                    return Ok(None);
                }
                match self.command(
                    prepared,
                    &["monitor-information"],
                    remaining.min(Duration::from_secs(2)),
                ) {
                    Ok(json) => Ok(Some(model::monitor_sizes(&json)?)),
                    Err(error) => {
                        failure = format!("{error:#}");
                        Ok(None)
                    }
                }
            },
        )
        .with_context(|| format!("komorebi IPC failed readiness; last probe: {failure}"))?;
        self.log.event("waiting for managed processes")?;
        poll(Duration::from_secs(15), Duration::from_millis(200), |_| {
            let processes = processes::find(&prepared.managed, false)?;
            let mut ready = true;
            for path in &prepared.managed {
                let count = processes
                    .iter()
                    .filter(|process| {
                        process
                            .executable
                            .to_string_lossy()
                            .eq_ignore_ascii_case(&path.to_string_lossy())
                    })
                    .count();
                ready &= single_process(count)
                    .with_context(|| format!("waiting for {}", path.display()))?;
            }
            Ok(ready.then_some(()))
        })?;
        ensure!(
            display::screens()? == prepared.screens,
            "physical monitor topology changed during startup"
        );
        model::layouts(&monitors, &prepared.screens)
    }

    fn apply(&self, prepared: &Prepared, layouts: &[Layout]) -> Result<()> {
        for (index, layout) in layouts.iter().enumerate() {
            self.command(
                prepared,
                &[
                    "workspace-layout",
                    &index.to_string(),
                    "0",
                    layout.command(),
                ],
                Duration::from_secs(10),
            )?;
        }
        Ok(())
    }

    fn verify(&self, prepared: &Prepared, layouts: &[Layout]) -> Result<()> {
        ensure!(
            display::screens()? == prepared.screens,
            "physical monitor topology changed while applying layouts"
        );
        model::verify_state(
            &self.command(prepared, &["state"], Duration::from_secs(10))?,
            &prepared.screens,
            layouts,
        )?;
        let running = processes::find(&prepared.stop, false)?;
        ensure!(
            running.len() == 2
                && running
                    .iter()
                    .all(|process| prepared.managed.contains(&process.executable)),
            "unexpected managed process set after restart"
        );
        self.log
            .event("verified monitors, layouts, and managed processes")
    }

    fn release(&self, attempt: Job) {
        attempt.release();
    }
    fn abort(&self, mut attempt: Job) -> Result<()> {
        attempt.terminate()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    struct Fake {
        events: RefCell<Vec<&'static str>>,
        fail: Option<&'static str>,
    }
    impl Fake {
        fn stage(&self, stage: &'static str) -> Result<()> {
            self.events.borrow_mut().push(stage);
            ensure!(self.fail != Some(stage), "injected {stage} failure");
            Ok(())
        }
    }
    impl Backend for Fake {
        type Prepared = ();
        type Attempt = ();
        fn prepare(&self, _: bool) -> Result<()> {
            self.stage("prepare")
        }
        fn stop(&self, _: &()) -> Result<()> {
            self.stage("stop")
        }
        fn recover(&self, _: &()) -> Result<()> {
            self.stage("recover")
        }
        fn start(&self, _: &()) -> Result<()> {
            self.stage("start")
        }
        fn ready(&self, _: &()) -> Result<Vec<Layout>> {
            self.stage("ready")?;
            Ok(vec![Layout::Columns])
        }
        fn apply(&self, _: &(), _: &[Layout]) -> Result<()> {
            self.stage("apply")
        }
        fn verify(&self, _: &(), _: &[Layout]) -> Result<()> {
            self.stage("verify")
        }
        fn release(&self, _: ()) {
            self.stage("release").unwrap();
        }
        fn abort(&self, _: ()) -> Result<()> {
            self.stage("abort")
        }
    }

    #[test]
    fn readiness_waits_for_delayed_start_but_rejects_duplicate_processes() {
        assert!(!single_process(0).unwrap());
        assert!(single_process(1).unwrap());
        assert!(single_process(2).is_err());
    }

    #[test]
    fn ordinary_restart_never_recovers_display_and_releases_only_after_verification() {
        let fake = Fake {
            events: RefCell::default(),
            fail: None,
        };
        run(&fake, false).unwrap();
        assert_eq!(
            *fake.events.borrow(),
            [
                "prepare", "stop", "start", "ready", "apply", "verify", "release"
            ]
        );
    }

    #[test]
    fn recovery_happens_between_stop_and_start_only_when_explicit() {
        let fake = Fake {
            events: RefCell::default(),
            fail: None,
        };
        run(&fake, true).unwrap();
        assert_eq!(
            *fake.events.borrow(),
            [
                "prepare", "stop", "recover", "start", "ready", "apply", "verify", "release"
            ]
        );
    }

    #[test]
    fn preflight_failure_does_not_stop_anything() {
        let fake = Fake {
            events: RefCell::default(),
            fail: Some("prepare"),
        };
        assert!(run(&fake, true).is_err());
        assert_eq!(*fake.events.borrow(), ["prepare"]);
    }

    #[test]
    fn every_post_start_failure_aborts_without_release() {
        for stage in ["ready", "apply", "verify"] {
            let fake = Fake {
                events: RefCell::default(),
                fail: Some(stage),
            };
            assert!(run(&fake, false).is_err());
            assert_eq!(fake.events.borrow().last(), Some(&"abort"));
            assert!(!fake.events.borrow().contains(&"release"));
        }
    }
}
