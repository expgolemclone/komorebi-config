use std::os::windows::process::CommandExt;
use std::{
    env, fs,
    io::{self, Write},
    path::Path,
    process::{Command, Stdio},
    thread,
    time::Duration,
};
use windows::Win32::System::Threading::CREATE_NO_WINDOW;

fn main() {
    let args: Vec<_> = env::args().skip(1).collect();
    match args[0].as_str() {
        "arguments" => print!("{}", serde_json::to_string(&args[1..]).unwrap()),
        "failure" => {
            println!("output detail");
            eprintln!("error detail");
            std::process::exit(7);
        }
        "flood" => {
            for _ in 0..8192 {
                io::stdout().write_all(&[b'x'; 1024]).unwrap();
            }
        }
        "sleep" => {
            fs::write(&args[1], std::process::id().to_string()).unwrap();
            thread::sleep(Duration::from_secs(60));
        }
        "tree" | "failed-tree" => {
            let mut child = Command::new(env::current_exe().unwrap())
                .args(["sleep", &args[1]])
                .stdin(Stdio::null())
                .creation_flags(CREATE_NO_WINDOW.0)
                .spawn()
                .unwrap();
            for _ in 0..100 {
                if Path::new(&args[1]).is_file() {
                    break;
                }
                thread::sleep(Duration::from_millis(10));
            }
            if args[0] == "failed-tree" {
                std::process::exit(9);
            }
            if args.get(2).is_some_and(|value| value == "stay") {
                child.wait().unwrap();
            } else {
                // Close our Windows process handle; the caller's job owns this descendant.
                drop(child);
            }
        }
        "nested-tree" | "nested-stay" => {
            let log = fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&args[2])
                .unwrap();
            let job = komorebi_config::process::launch(
                &komorebi_config::process::Invocation::new(env::current_exe().unwrap())
                    .args(["tree", &args[1]]),
                Duration::from_secs(5),
                &log,
            )
            .unwrap();
            if args[0] == "nested-stay" {
                thread::sleep(Duration::from_secs(60));
            }
            job.release();
        }
        "environment" => print!("{}", env::var(&args[1]).unwrap_or_default()),
        "lock" => {
            let lock = komorebi_config::windows::privilege::RestartLock::named(&args[1]).unwrap();
            std::process::exit(if lock.is_some() { 0 } else { 8 });
        }
        _ => panic!("unknown fixture mode"),
    }
}
