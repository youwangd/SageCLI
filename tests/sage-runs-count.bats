#!/usr/bin/env bats
# tests/sage-runs-count.bats — sage runs --count prints plain integer

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$(mktemp -d)"
  sage init --force >/dev/null 2>&1
  local rd="$SAGE_HOME/runs"
  mkdir -p "$rd/run-001" "$rd/run-002" "$rd/run-003"
  echo '{"run_id":"run-001","status":"running","current_cycle":3,"goal":"build feature X"}' > "$rd/run-001/state.json"
  echo '{"run_id":"run-002","status":"done","current_cycle":7,"goal":"fix bug Y"}' > "$rd/run-002/state.json"
  echo '{"run_id":"run-003","status":"failed","current_cycle":2,"goal":"deploy Z"}' > "$rd/run-003/state.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "runs --count prints plain integer of all runs" {
  run sage runs --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "runs --count composes with --active filter" {
  run sage runs --active --count
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "runs --count output is scriptable (pure digits)" {
  local n
  n=$(sage runs --active --count)
  [[ "$n" =~ ^[0-9]+$ ]]
  [ "$n" -eq 1 ]
}
