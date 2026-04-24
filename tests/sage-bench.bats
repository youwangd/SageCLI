#!/usr/bin/env bats
# tests/sage-bench.bats — Phase 21: bench-as-code

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-bench-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  # Copy real runtimes for bash handler support
  cp -f "$HOME/.sage/runtimes/"*.sh "$SAGE_HOME/runtimes/" 2>/dev/null || true
  # Create a bash agent with a simple handler
  "$SAGE" create bench-a --runtime bash >/dev/null 2>&1
  cat > "$SAGE_HOME/agents/bench-a/handler.sh" <<'H'
#!/bin/bash
echo "ok"
H
  chmod +x "$SAGE_HOME/agents/bench-a/handler.sh"
  # Create task dir
  mkdir -p "$BATS_TMPDIR/bench-tasks-$$"
  echo "say hello" > "$BATS_TMPDIR/bench-tasks-$$/01-hello.prompt"
}

teardown() {
  rm -rf "$SAGE_HOME" "$BATS_TMPDIR/bench-tasks-$$"
}

@test "bench help shows usage" {
  run "$SAGE" bench help
  [ "$status" -eq 0 ]
  [[ "$output" == *"sage bench run"* ]]
}

@test "bench run requires --agents" {
  run "$SAGE" bench run "$BATS_TMPDIR/bench-tasks-$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--agents"* ]]
}

@test "bench run requires valid tasks dir" {
  run "$SAGE" bench run /nonexistent --agents bench-a
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "bench run produces results.jsonl" {
  run "$SAGE" bench run "$BATS_TMPDIR/bench-tasks-$$" --agents bench-a --timeout 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"bench complete"* ]]
  # Check results file exists
  local latest=$(cat "$SAGE_HOME/bench/latest")
  [ -f "$SAGE_HOME/bench/$latest/results.jsonl" ]
  # Check it has 1 row (1 task × 1 agent)
  local rows=$(wc -l < "$SAGE_HOME/bench/$latest/results.jsonl")
  [ "$rows" -eq 1 ]
}

@test "bench report --format csv produces valid csv" {
  "$SAGE" bench run "$BATS_TMPDIR/bench-tasks-$$" --agents bench-a --timeout 30 >/dev/null 2>&1
  run "$SAGE" bench report --format csv
  [ "$status" -eq 0 ]
  [[ "$output" == *"task,agent,run"* ]]
}

@test "bench report --format json produces valid json" {
  "$SAGE" bench run "$BATS_TMPDIR/bench-tasks-$$" --agents bench-a --timeout 30 >/dev/null 2>&1
  run "$SAGE" bench report --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "bench ls lists runs" {
  "$SAGE" bench run "$BATS_TMPDIR/bench-tasks-$$" --agents bench-a --timeout 30 >/dev/null 2>&1
  run "$SAGE" bench ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"run-"* ]]
}

@test "bench unknown subcommand fails" {
  run "$SAGE" bench bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown bench subcommand"* ]]
}
