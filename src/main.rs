use clap::Parser;
use futures::stream::StreamExt;
use signal_hook::consts::signal;
use signal_hook_tokio::Signals;
use std::time::Duration;
use tokio::{process::Command, time::sleep};

/// A utility for retrying failed console commands
#[derive(Parser)]
#[command(version, arg_required_else_help = true)]
struct Args {
    /// The total number of attempts
    #[arg(short, long, default_value_t = 5, display_order = 1)]
    attempts: u32,

    /// How long to wait before each retry
    #[arg(short, long, default_value = "1s", display_order = 2)]
    delay: humantime::Duration,

    /// Multiply the delay after each failed attempt
    #[arg(short = 'm', long, default_value_t = 1, display_order = 3)]
    delay_multiplier: u32,

    /// Suppress output when the wrapped command fails
    #[arg(short, long, display_order = 4)]
    quiet: bool,

    /// The command to run
    #[arg(trailing_var_arg = true, required = true, num_args = 1..)]
    command: Vec<String>,
}

fn main() {
    let args = Args::parse();
    std::process::exit(run(args));
}

#[tokio::main]
async fn run(args: Args) -> i32 {
    let mut last_exit_code = 1;
    let mut num_attempts = 0;
    let mut should_stop = false;
    let mut delay: Duration = args.delay.into();

    let mut signals = Signals::new([
        signal::SIGHUP,
        signal::SIGINT,
        signal::SIGQUIT,
        signal::SIGTERM,
    ])
    .expect("error: could not create signal stream");

    let log = make_logger(args.quiet);

    while num_attempts < args.attempts {
        let spawn = Command::new(&args.command[0])
            .args(&args.command[1..])
            .spawn();

        if let Err(e) = spawn {
            eprintln!("error: could not spawn child process; caused by: {e:?}");
            return 1;
        }

        let mut child = spawn.unwrap();

        loop {
            tokio::select! {
                Ok(status) = child.wait() => {
                    if status.success() {
                        return 0;
                    }

                    if let Some(code) = status.code() {
                        last_exit_code = code;

                        if !should_stop {
                            break;
                        }

                        log(format!(
                            "command `{}` exited with non-zero code ({}) while handling stop signal",
                            args.command.join(" "),
                            code
                        ));
                    }

                    return last_exit_code;
                }

                Some(signal) = signals.next() => {
                    if let Some(child_pid) = child.id() {
                        unsafe {
                            libc::kill(child_pid as i32, signal);
                        }
                    }

                    should_stop = true;
                }
            }
        }

        num_attempts += 1;

        if num_attempts < args.attempts {
            log(format!(
                "command `{}` exited with non-zero code ({}) on attempt #{}; retrying in {}",
                args.command.join(" "),
                last_exit_code,
                num_attempts,
                humantime::Duration::from(delay)
            ));

            let backoff_sleep = sleep(delay);
            tokio::pin!(backoff_sleep);

            tokio::select! {
                Some(_signal) = signals.next() => {
                    log(format!("received stop signal during sleep; exiting before attempt #{}", num_attempts + 1));
                    return last_exit_code;
                }
                _ = &mut backoff_sleep => {}
            }

            delay *= args.delay_multiplier;
        }
    }

    log(format!(
        "command `{}` exited with non-zero code ({}) on attempt #{}; maximum attempts reached",
        args.command.join(" "),
        last_exit_code,
        num_attempts
    ));

    last_exit_code
}

fn make_logger(quiet: bool) -> impl Fn(String) {
    if quiet {
        |_msg| {}
    } else {
        |msg| eprintln!("{msg}")
    }
}
