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
# Given: The child exit code is zero
#  Then: The exit code is zero
#
givenScript "exit 0"
assertExitCode "The exit code is zero when the child exit code is zero" 0 "${BIN_PATH} -- ./script"

#
# Given: The child exit code is non-zero
#  Then: The exit code matches the child exit code
#
givenScript "exit 2"
assertExitCode "The exit code matches the child exit code when the child exit code is non-zero" 2 "${BIN_PATH} --attempts 1 -- ./script"

#
# Given: The child exit code is non-zero
#  Then: The exit code matches the last child exit code
#
givenScript "echo . >>output; exit \"\$(wc -l output | awk '{print \$1}')\""
assertExitCode "The exit code matches the last child exit code when the child exit code is non-zero" 3 "${BIN_PATH} --attempts 3 --delay 0s -- ./script"

#
# Given: The child is running
#  When: A stop signal is received
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
${BIN_PATH} -- ./script >output &
processId=$!

sleep 1 # Give the child time to start; TODO: find a better way

kill -s TERM ${processId}
wait ${processId} 2>/dev/null

assertEqual \
  "Stop signals are sent to the child" \
  "child received TERM signal" \
  "$(cat ./output)"

#
# Given: The child exits non-zero,
#        and there are attempts remaining
#  When: A stop signal is received
#  Then: No further attempts occur
#
givenScript "exit 1"
${BIN_PATH} --attempts 3 --delay 1s -- ./script >output 2>&1 &
processId=$!

sleep 1 # Give the child time to start; TODO: find a better way

outputBeforeStop=$(cat ./output)
kill -s TERM ${processId}
wait ${processId} 2>/dev/null

assertEqual \
  "No further attempts occur when a stop signal is received" \
  "${outputBeforeStop}" \
  "$(cat ./output)"

rm ./script ./output >/dev/null 2>&1

[ ${failCount} = 0 ] && exit 0 || exit 1
