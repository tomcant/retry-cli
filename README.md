# retry-cli

A utility for retrying failed CLI commands.

```
USAGE:
    retry [OPTIONS] [--] <COMMAND>...

ARGS:
    <COMMAND>...    The command to run

OPTIONS:
    -a, --attempts <ATTEMPTS>
            The total number of attempts [default: 5]

    -d, --delay <DELAY>
            How long to wait before each retry [default: 1s]

    -m, --delay-multiplier <DELAY_MULTIPLIER>
            Multiply the delay after each failed attempt [default: 1]

    -q, --quiet
            Suppress output when the wrapped command fails

    -h, --help
            Print help information

    -V, --version
            Print version information
```
