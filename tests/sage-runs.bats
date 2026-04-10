#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-runs-test-$$"
  "$SAGE" init 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "sage runs with no runs shows header only" {
  run "$SAGE" runs
  [ "$status" -eq 0 ]
  [[ "$output" == *"RUN"* ]]
  [[ "$output" == *"STATUS"* ]]
}

@test "sage runs lists existing run" {
  mkdir -p "$SAGE_HOME/runs/test-run-001/cycles"
  cat > "$SAGE_HOME/runs/test-run-001/state.json" <<'EOF'
{"run_id":"test-run-001","status":"completed","current_cycle":3,"goal":"Fix the bug"}
EOF
  cat > "$SAGE_HOME/runs/test-run-001/run.md" <<'EOF'
# Test Run
This is a test run.
EOF
  run "$SAGE" runs
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-run-001"* ]]
  [[ "$output" == *"completed"* ]]
  [[ "$output" == *"Fix the bug"* ]]
}

@test "sage runs --active filters to running only" {
  mkdir -p "$SAGE_HOME/runs/run-done" "$SAGE_HOME/runs/run-active"
  echo '{"run_id":"run-done","status":"completed","current_cycle":2,"goal":"done"}' > "$SAGE_HOME/runs/run-done/state.json"
  echo '{"run_id":"run-active","status":"running","current_cycle":1,"goal":"active"}' > "$SAGE_HOME/runs/run-active/state.json"
  run "$SAGE" runs --active
  [ "$status" -eq 0 ]
  [[ "$output" == *"run-active"* ]]
  [[ "$output" != *"run-done"* ]]
}

@test "sage runs <id> shows run.md content" {
  mkdir -p "$SAGE_HOME/runs/my-run"
  echo '{"run_id":"my-run","status":"completed","current_cycle":1,"goal":"test"}' > "$SAGE_HOME/runs/my-run/state.json"
  echo "# My Run Output" > "$SAGE_HOME/runs/my-run/run.md"
  run "$SAGE" runs my-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"My Run Output"* ]]
}

@test "sage runs <id> -c N shows cycle output" {
  mkdir -p "$SAGE_HOME/runs/my-run/cycles"
  echo '{"run_id":"my-run","status":"completed","current_cycle":1,"goal":"test"}' > "$SAGE_HOME/runs/my-run/state.json"
  echo "Worker did stuff" > "$SAGE_HOME/runs/my-run/cycles/001-worker.md"
  echo '{"tests":"pass"}' > "$SAGE_HOME/runs/my-run/cycles/001-mechanical.json"
  echo "Validator approved" > "$SAGE_HOME/runs/my-run/cycles/001-validator.md"
  run "$SAGE" runs my-run -c 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Worker did stuff"* ]]
  [[ "$output" == *"Validator approved"* ]]
}

@test "sage runs with nonexistent id fails" {
  run "$SAGE" runs nonexistent-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
