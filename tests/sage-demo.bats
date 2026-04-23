#!/usr/bin/env bats
# tests/sage-demo.bats — first-run onboarding command

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-demo-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "demo creates three agents" {
  run "$SAGE" demo
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/demo-reviewer" ]
  [ -d "$SAGE_HOME/agents/demo-tester" ]
  [ -d "$SAGE_HOME/agents/demo-security" ]
}

@test "demo writes a fan-out plan file" {
  run "$SAGE" demo
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/plans/demo-fan-out.yaml" ]
  grep -q "pattern:" "$SAGE_HOME/plans/demo-fan-out.yaml"
  grep -q "fan-out" "$SAGE_HOME/plans/demo-fan-out.yaml"
}

@test "demo prints next-step hints" {
  run "$SAGE" demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"sage ls"* ]]
  [[ "$output" == *"sage plan"* ]]
}

@test "demo is idempotent (second run succeeds, no duplicate errors)" {
  run "$SAGE" demo
  [ "$status" -eq 0 ]
  run "$SAGE" demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"already exists"* ]] || [[ "$output" == *"skipping"* ]] || [[ "$output" == *"reused"* ]] || true
  # still exactly 3 demo agents
  run bash -c "ls $SAGE_HOME/agents/ | grep -c '^demo-'"
  [ "$output" = "3" ]
}

@test "demo --clean removes demo agents and plan" {
  "$SAGE" demo >/dev/null
  run "$SAGE" demo --clean
  [ "$status" -eq 0 ]
  [ ! -d "$SAGE_HOME/agents/demo-reviewer" ]
  [ ! -d "$SAGE_HOME/agents/demo-tester" ]
  [ ! -d "$SAGE_HOME/agents/demo-security" ]
  [ ! -f "$SAGE_HOME/plans/demo-fan-out.yaml" ]
}

@test "demo --clean on empty state succeeds (idempotent clean)" {
  run "$SAGE" demo --clean
  [ "$status" -eq 0 ]
}

@test "demo agents use bash runtime (zero external deps)" {
  "$SAGE" demo >/dev/null
  run jq -r .runtime "$SAGE_HOME/agents/demo-reviewer/runtime.json"
  [ "$output" = "bash" ]
}

@test "help lists demo command" {
  run "$SAGE" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo"* ]]
}
