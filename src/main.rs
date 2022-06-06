use clap::Parser;
use std::thread::sleep;
use std::time::Duration;
use tokio::process::Command;
use tokio::signal::unix::{signal, SignalKind};

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

#[tokio::main]
async fn run() -> Result<(), i32> {
    let args = Args::parse();

    let mut last_exit_code = 1;
    let mut num_attempts = 0;
    let mut delay: Duration = args.delay.into();

    let mut stream = signal(SignalKind::terminate()).expect("Could not create signal stream");

    while num_attempts < args.attempts {
        let mut child = Command::new(&args.command[0])
            .args(&args.command[1..])
            .spawn()
            .expect("Could not spawn child process");

        loop {
            tokio::select! {
                Ok(status) = child.wait() => {
                    if status.success() {
                        return Ok(());
                    }
                    if let Some(code) = status.code() {
                        last_exit_code = code;
                    }
                    break;
                }
                _ = stream.recv() => {
                    child.kill().await.expect("Could not kill child process");
                    return Ok(());
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

    Err(last_exit_code)
}

fn main() {
    std::process::exit(match run() {
        Ok(_) => 0,
        Err(code) => code,
    });
}
