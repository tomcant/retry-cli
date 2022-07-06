#!/bin/bash

BIN_PATH=$1
[ ! -x "${BIN_PATH}" ] && { echo "error: required argument BIN_PATH is either missing or not executable" >&2; exit 1; }
command -v jq >/dev/null || { echo "error: required dependency 'jq' is missing." >&2; exit 1; }

failCount=0

givenScript() {
  local script="$1"
  rm ./script ./output >/dev/null 2>&1
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

    failCount=$((failCount + 1))
  fi
}

assertExitCode() {
  local case="$1"
  local expected="$2"
  local command="$3"

  ${command} >/dev/null 2>&1
  local exitCode=$?

  assertEqual "${case}" "${expected}" ${exitCode}
}

#
# Given: Invocation with `--version`
#  Then: It reports the version configured in Cargo.toml
#
assertEqual \
  "It reports the version configured in Cargo.toml" \
  "$(cargo metadata 2>/dev/null | jq -r '.packages[] | select(.name == "retry-cli") | .version')" \
  "$(${BIN_PATH} --version | cut -d' ' -f2)"

#
# Given: The child exits zero
#  Then: The parent exits zero
#
givenScript "exit 0"
assertExitCode "The parent exits zero given the child exits zero" 0 "${BIN_PATH} -- ./script"

#
# Given: The child exits non-zero
#  Then: The parent matches the child's exit code
#
givenScript "exit 2"
assertExitCode "The parent matches the child's non-zero exit code" 2 "${BIN_PATH} -a 1 -- ./script"

#
# Given: The child is running
#  When: The parent receives a stop signal
#  Then: The stop signal is sent to the child
#
givenScript "
  trap 'echo \"child received TERM signal\" && exit 0' TERM
  i=0
  while [ \$i -lt 3 ]; do
    i=\$((i+1))
    sleep 1
  done
"

${BIN_PATH} -- ./script > ./output &
sleep 1 # Give the child time to start; TODO: find a better way

processId=$!
kill -s TERM ${processId}
wait ${processId} 2>/dev/null

assertEqual \
  "Stop signals received by the parent are sent to the child" \
  "child received TERM signal" \
  "$(cat ./output)"

rm ./script ./output >/dev/null 2>&1

[ ${failCount} = 0 ] && exit 0 || exit 1
