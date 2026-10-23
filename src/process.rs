use anyhow::{Context, Result, bail, ensure};
use process_wrap::std::{ChildWrapper, CommandWrap, CreationFlags, JobObject};
use std::{
    fs::File,
    io::{Read, Seek, SeekFrom},
    process::{Command, ExitStatus, Stdio},
    thread,
    time::{Duration, Instant},
};
use windows::Win32::System::Threading::CREATE_NO_WINDOW;

const OUTPUT_LIMIT: u64 = 1024 * 1024;
const POLL: Duration = Duration::from_millis(10);

pub struct Job {
    child: Box<dyn ChildWrapper>,
    armed: bool,
}

impl Job {
    fn spawn(mut command: Command) -> Result<Self> {
        command.stdin(Stdio::null());
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

pub fn capture(mut command: Command, timeout: Duration) -> Result<Vec<u8>> {
    let program = command.get_program().to_string_lossy().into_owned();
    let mut stdout = tempfile::tempfile().context("creating stdout capture")?;
    let mut stderr = tempfile::tempfile().context("creating stderr capture")?;
    command
        .stdout(stdout.try_clone()?)
        .stderr(stderr.try_clone()?);
    let mut job = Job::spawn(command).with_context(|| format!("launching {program}"))?;
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
            return Err(error).with_context(|| format!("running {program}"));
        }
        (Ok(_), Err(error)) => return Err(error),
        (Err(error), Err(cleanup)) => bail!("{error:#}; child cleanup also failed: {cleanup:#}"),
    };
    let stdout = read_capture(&mut stdout)?;
    let stderr = read_capture(&mut stderr)?;
    ensure!(
        status.success(),
        "{program} failed with exit code {:?}; stdout: {}; stderr: {}",
        status.code(),
        String::from_utf8_lossy(&stdout).trim(),
        String::from_utf8_lossy(&stderr).trim()
    );
    Ok(stdout)
}

pub fn launch(mut command: Command, timeout: Duration, log: &File) -> Result<Job> {
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
