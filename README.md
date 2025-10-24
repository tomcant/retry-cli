# Retry

![CI](https://github.com/tomcant/retry-cli/actions/workflows/ci.yml/badge.svg)

A utility for retrying failed CLI commands on Unix-like systems.

See the [latest release](https://github.com/tomcant/retry-cli/releases) for supported platforms.

## Features

- Configurable delay before retrying with human readable units (e.g. `1s`, `20ms`, `3m` etc.)
- Exponential back-off with the `-m|--delay-multiplier` option
- Proxies stop signals to the child command (`SIGHUP`, `SIGINT`, `SIGQUIT`, `SIGTERM`)

## Usage

```
Usage: retry [OPTIONS] <COMMAND>...

Arguments:
  <COMMAND>...  The command to run

Options:
  -a, --attempts <ATTEMPTS>
          The total number of attempts [default: 5]
  -d, --delay <DELAY>
          How long to wait before each retry [default: 1s]
  -m, --delay-multiplier <DELAY_MULTIPLIER>
          Multiply the delay after each failed attempt [default: 1]
  -q, --quiet
          Suppress output when the wrapped command fails
  -h, --help
          Print help
  -V, --version
          Print version
```

## Examples

```bash
# Default 1 second delay before retrying, total of 5 attempts
➜ retry /path/to/mission-critical-script.sh

# No delay before retrying, total of 3 attempts
➜ retry --delay 0s --attempts 3 ssh user@some.host some-remote-task

# Exponential backoff: 10ms, 20ms, 40ms, 80ms, etc. before successive retries
➜ retry --delay 10ms --delay-multiplier 2 /bin/sh -c "echo 'important work'"
```

## Output

All output from the child command is piped to the `stdout`/`stderr` streams of `retry-cli`.
If the child command exits with a non-zero code then a summary of each failed invocation is printed to `stderr` (unless the `-q|--quiet` option is provided).

```bash
➜ retry -d 10ms -m 2 false

command `false` exited with non-zero code (1) on attempt #1; retrying in 10ms
command `false` exited with non-zero code (1) on attempt #2; retrying in 20ms
command `false` exited with non-zero code (1) on attempt #3; retrying in 40ms
command `false` exited with non-zero code (1) on attempt #4; retrying in 80ms
command `false` exited with non-zero code (1) on attempt #5; maximum attempts reached

➜ echo $?

1
```

The exit code of `retry-cli` will always match the last exit code of the child command.
