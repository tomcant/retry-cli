#!/bin/bash

BIN_PATH=$1
[ ! -x "${BIN_PATH}" ] && { echo "error: required argument BIN_PATH is either missing or not executable" >&2; exit 1; }
command -v jq >/dev/null || { echo "error: required dependency 'jq' is missing." >&2; exit 1; }

givenScript() {
  local script="$1"
  echo -e "#!/bin/sh\n${script}" > ./script
  chmod +x ./script
}

assertEqual() {
  local case="$1"
  local expected="$2"
  local actual="$3"

  if [[ "${expected}" = "${actual}" ]]; then
    echo -e "\033[32m✔ ${case}\033[0m"
  else
    echo -e "\033[31m✘ ${case}\033[0m"
    echo "    Failed asserting that values match:"
    echo "      Expected: ${expected}"
    echo "      Actual: ${actual}"
  fi
}

assertExitCode() {
  local case="$1"
  local expected="$2"
  local command="$3"

  ${command} >&2 2>/dev/null
  exitCode=$?

  assertEqual "${case}" "${expected}" ${exitCode}
}

#
# Tests
#

assertEqual \
  "It reports the version configured in Cargo.toml" \
  "$(cargo metadata 2>/dev/null | jq -r '.packages[] | select(.name == "retry-cli") | .version')" \
  "$(${BIN_PATH} --version | cut -d' ' -f2)"

givenScript "exit 0"
assertExitCode "It exits successfully when the child command exits successfully" 0 "${BIN_PATH} -- ./script"

givenScript "exit 2"
assertExitCode "It reflects the non-zero exit code of the child command when it fails" 2 "${BIN_PATH} -a 1 -- ./script"

rm ./script
