#!/usr/bin/env bats
# tests/sage-runs-json.bats — sage runs --json emits machine-readable list for scripting

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-runs-json-$$"
  "$SAGE" init 2>/dev/null
  mkdir -p "$SAGE_HOME/runs/run-a" "$SAGE_HOME/runs/run-b"
  echo '{"run_id":"run-a","status":"completed","current_cycle":3,"goal":"goal A"}' > "$SAGE_HOME/runs/run-a/state.json"
  echo '{"run_id":"run-b","status":"running","current_cycle":1,"goal":"goal B"}'   > "$SAGE_HOME/runs/run-b/state.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "runs --json emits valid JSON array with both runs" {
  run "$SAGE" runs --json
  [ "$status" -eq 0 ]
  local n; n=$(echo "$output" | jq 'length')
  [ "$n" -eq 2 ]
}

@test "runs --json includes run_id, status, current_cycle, goal fields" {
  run "$SAGE" runs --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.run_id=="run-a" and .status=="completed" and .current_cycle==3 and .goal=="goal A")'
}

@test "runs --active --json filters to running only" {
  run "$SAGE" runs --active --json
  [ "$status" -eq 0 ]
  local n; n=$(echo "$output" | jq 'length')
  [ "$n" -eq 1 ]
  echo "$output" | jq -e '.[0] | select(.run_id=="run-b" and .status=="running")'
}
