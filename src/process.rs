use anyhow::{Context, Result, bail, ensure};
use process_wrap::std::{ChildWrapper, CommandWrap, CreationFlags, JobObject};
use std::{
    ffi::{OsStr, OsString},
    fs::File,
    io::{Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Stdio},
    thread,
    time::{Duration, Instant},
};
use windows::Win32::System::Threading::CREATE_NO_WINDOW;

const OUTPUT_LIMIT: u64 = 1024 * 1024;
const POLL: Duration = Duration::from_millis(10);

#[derive(Clone, Debug)]
pub struct Invocation {
    pub program: PathBuf,
    pub arguments: Vec<OsString>,
    pub environment: Vec<(OsString, Option<OsString>)>,
}

impl Invocation {
    pub fn new(program: impl AsRef<Path>) -> Self {
        Self {
            program: program.as_ref().to_owned(),
            arguments: Vec::new(),
            environment: Vec::new(),
        }
    }

    pub fn args(mut self, args: impl IntoIterator<Item = impl AsRef<OsStr>>) -> Self {
        self.arguments
            .extend(args.into_iter().map(|arg| arg.as_ref().to_owned()));
        self
    }

    pub fn env(mut self, name: impl AsRef<OsStr>, value: Option<impl AsRef<OsStr>>) -> Self {
        self.environment.push((
            name.as_ref().to_owned(),
            value.map(|value| value.as_ref().to_owned()),
        ));
        self
    }

    fn command(&self) -> Command {
        let mut command = Command::new(&self.program);
        command.args(&self.arguments).stdin(Stdio::null());
        for (name, value) in &self.environment {
            match value {
                Some(value) => {
                    command.env(name, value);
                }
                None => {
                    command.env_remove(name);
                }
            }
        }
        command
    }
}

pub struct Job {
    child: Box<dyn ChildWrapper>,
    armed: bool,
}

impl Job {
    fn spawn(command: Command) -> Result<Self> {
        let mut command = CommandWrap::from(command);
        let child = command
            .wrap(CreationFlags(CREATE_NO_WINDOW))
            .wrap(JobObject)
            .spawn()
            .context("starting child in Windows job")?;
        Ok(Self { child, armed: true })
    }

    pub fn id(&self) -> u32 {
        self.child.id()
    }

    fn wait_root(
        &mut self,
        timeout: Duration,
        mut check_output: impl FnMut() -> Result<()>,
    ) -> Result<ExitStatus> {
        let deadline = Instant::now() + timeout;
        loop {
            check_output()?;
            // JobObject::wait waits for the entire tree, which is wrong for a launcher.
            if let Some(status) = self.child.try_wait()? {
                return Ok(status);
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            ensure!(
                !remaining.is_zero(),
                "native command timed out after {:.2}s",
                timeout.as_secs_f64()
            );
            thread::sleep(POLL.min(remaining));
        }
    }

    pub fn terminate(&mut self) -> Result<()> {
        if self.armed {
            self.child.start_kill().context("terminating child job")?;
            self.wait_root(Duration::from_secs(2), || Ok(()))
                .context("waiting for terminated child")?;
            self.armed = false;
        }
        Ok(())
    }

    pub fn release(mut self) {
        // process-wrap's std job has no kill-on-close policy. Closing it preserves descendants.
        self.armed = false;
    }
}

impl Drop for Job {
    fn drop(&mut self) {
        if self.armed {
            let _ = self.child.start_kill();
        }
    }
}

fn read_capture(file: &mut File) -> Result<Vec<u8>> {
    ensure!(
        file.metadata()?.len() <= OUTPUT_LIMIT,
        "native command exceeded the {OUTPUT_LIMIT}-byte output limit"
    );
    file.seek(SeekFrom::Start(0))?;
    let mut output = Vec::new();
    file.take(OUTPUT_LIMIT + 1).read_to_end(&mut output)?;
    ensure!(
        output.len() as u64 <= OUTPUT_LIMIT,
        "native command exceeded the output limit"
    );
    Ok(output)
}

pub fn capture(invocation: &Invocation, timeout: Duration) -> Result<Vec<u8>> {
    let mut stdout = tempfile::tempfile().context("creating stdout capture")?;
    let mut stderr = tempfile::tempfile().context("creating stderr capture")?;
    let mut command = invocation.command();
    command
        .stdout(stdout.try_clone()?)
        .stderr(stderr.try_clone()?);
    let mut job = Job::spawn(command)
        .with_context(|| format!("launching {}", invocation.program.display()))?;
    let result = job.wait_root(timeout, || {
        ensure!(
            stdout.metadata()?.len() <= OUTPUT_LIMIT && stderr.metadata()?.len() <= OUTPUT_LIMIT,
            "native command exceeded the {OUTPUT_LIMIT}-byte output limit"
        );
        Ok(())
    });
    let cleanup = job.terminate();
    let status = match (result, cleanup) {
        (Ok(status), Ok(())) => status,
        (Err(error), Ok(())) => {
            return Err(error).with_context(|| format!("running {}", invocation.program.display()));
        }
        (Ok(_), Err(error)) => return Err(error),
        (Err(error), Err(cleanup)) => bail!("{error:#}; child cleanup also failed: {cleanup:#}"),
    };
    let stdout = read_capture(&mut stdout)?;
    let stderr = read_capture(&mut stderr)?;
    ensure!(
        status.success(),
        "{} failed with exit code {:?}; stdout: {}; stderr: {}",
        invocation.program.display(),
        status.code(),
        String::from_utf8_lossy(&stdout).trim(),
        String::from_utf8_lossy(&stderr).trim()
    );
    Ok(stdout)
}

pub fn launch(invocation: &Invocation, timeout: Duration, log: &File) -> Result<Job> {
    let mut command = invocation.command();
    // Files, never pipes: launched daemons may inherit these handles after this process exits.
    command.stdout(log.try_clone()?).stderr(log.try_clone()?);
    let mut job = Job::spawn(command)?;
    let status = job.wait_root(timeout, || Ok(()))?;
    ensure!(
        status.success(),
        "launcher failed with exit code {:?}; see application log",
        status.code()
    );
    Ok(job)
}
