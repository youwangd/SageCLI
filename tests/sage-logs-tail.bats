#!/usr/bin/env bats
# tests/sage-logs-tail.bats — logs --tail <N> controls line count

setup() {
  export SAGE_HOME="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1
  mkdir -p "$SAGE_HOME/agents/tester" "$SAGE_HOME/logs"
  echo "bash" > "$SAGE_HOME/agents/tester/runtime"
  # Write 100 lines to the log
  local logfile="$SAGE_HOME/logs/tester.log"
  for i in $(seq 1 100); do
    echo "log line $i" >> "$logfile"
  done
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "logs --tail N shows exactly N lines" {
  run sage logs tester --tail 10
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 10 ]
  [[ "${lines[0]}" == *"log line 91"* ]]
  [[ "${lines[9]}" == *"log line 100"* ]]
}

@test "logs --tail default is 50 lines" {
  run sage logs tester
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 50 ]
  [[ "${lines[0]}" == *"log line 51"* ]]
}

@test "logs --tail works with --all" {
  run sage logs --all --tail 5
  [ "$status" -eq 0 ]
  # Should have 5 lines (prefixed with [tester])
  [ "${#lines[@]}" -eq 5 ]
}

@test "logs --tail works with --grep" {
  run sage logs tester --grep "line 9" --tail 3
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}
