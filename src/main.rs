use clap::Parser;
use signal_hook::{consts::SIGTERM, flag};
use std::process::{exit, Command};
use std::sync::{atomic::AtomicBool, atomic::Ordering, Arc};
use std::thread::sleep;
use std::time::Duration;

/// A utility for retrying failed console commands
#[derive(Parser)]
#[clap(version)]
struct Args {
    /// The total number of attempts
    #[clap(short, long, default_value_t = 5, display_order = 1)]
    attempts: u32,

    /// How long to wait before each retry
    #[clap(short, long, default_value = "1s", display_order = 2)]
    delay: humantime::Duration,

    /// Multiply the delay after each failed attempt
    #[clap(short = 'm', long, default_value_t = 1, display_order = 3)]
    delay_multiplier: u32,

    /// The command to run
    #[clap(required = true, last = true)]
    command: Vec<String>,
}

fn main() -> Result<(), std::io::Error> {
    let args = Args::parse();

    let mut num_attempts = 0;
    let mut delay: Duration = args.delay.into();

    let handle_sigterm = Arc::new(AtomicBool::new(false));
    flag::register(SIGTERM, Arc::clone(&handle_sigterm))?;

    while num_attempts < args.attempts {
        let mut child = Command::new(&args.command[0])
            .args(&args.command[1..])
            .spawn()
            .expect("Could not spawn child process");

        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    if status.success() {
                        return Ok(());
                    }
                    break;
                }
                Ok(None) => {
                    if handle_sigterm.load(Ordering::Relaxed) {
                        if let Ok(()) = child.kill() {
                            child.wait()?;
                        }
                        return Ok(());
                    }
                    sleep(Duration::from_millis(100));
                }
                Err(e) => {
                    println!("Error waiting for child process: {e}");
                    exit(1);
                }
            }
        }

        num_attempts += 1;

        if num_attempts < args.attempts {
            println!(
                "Command `{}` exited with a non-zero status on attempt #{}. Retrying in {}.",
                args.command.join(" "),
                num_attempts,
                humantime::Duration::from(delay)
            );
            sleep(delay);
            delay *= args.delay_multiplier;
        }
    }

    println!(
        "Command `{}` exited with a non-zero status on attempt #{}. Maximum attempts reached. Exiting.",
        args.command.join(" "),
        num_attempts
    );

    Ok(())
}
