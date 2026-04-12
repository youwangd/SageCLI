#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- fan-out pattern ---

@test "plan --pattern fan-out requires --task" {
  run sage plan --pattern fan-out --inputs "a,b,c" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"--task"* ]]
}

@test "plan --pattern fan-out requires --inputs" {
  run sage plan --pattern fan-out --task "echo {}" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"--inputs"* ]]
}

@test "plan --pattern fan-out generates plan with one task per input" {
  run sage plan --pattern fan-out --task "Review {}" --inputs "a.py,b.py,c.py" --save "$SAGE_HOME/test-plan.json" --yes
  [ -f "$SAGE_HOME/test-plan.json" ]
  local count=$(jq '.tasks | length' "$SAGE_HOME/test-plan.json")
  [ "$count" -eq 3 ]
}

@test "plan --pattern fan-out replaces {} placeholder in task descriptions" {
  run sage plan --pattern fan-out --task "Audit file: {}" --inputs "x.py,y.py" --save "$SAGE_HOME/test-plan.json" --yes
  local desc1=$(jq -r '.tasks[0].description' "$SAGE_HOME/test-plan.json")
  local desc2=$(jq -r '.tasks[1].description' "$SAGE_HOME/test-plan.json")
  [[ "$desc1" == *"x.py"* ]]
  [[ "$desc2" == *"y.py"* ]]
}

@test "plan --pattern fan-out tasks have no dependencies (all parallel)" {
  run sage plan --pattern fan-out --task "Check {}" --inputs "a,b,c" --save "$SAGE_HOME/test-plan.json" --yes
  local deps=$(jq '[.tasks[].depends | length] | add' "$SAGE_HOME/test-plan.json")
  [ "$deps" -eq 0 ]
}

@test "plan --pattern fan-out sets goal from task template" {
  run sage plan --pattern fan-out --task "Lint {}" --inputs "a,b" --save "$SAGE_HOME/test-plan.json" --yes
  local goal=$(jq -r '.goal' "$SAGE_HOME/test-plan.json")
  [[ "$goal" == *"fan-out"* ]]
}

@test "plan --pattern unknown fails with error" {
  run sage plan --pattern nonexistent --task "x" --inputs "a"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown pattern"* ]]
}

# --- pipeline pattern ---

@test "plan --pattern pipeline requires --task with multiple steps" {
  run sage plan --pattern pipeline --task "Analyze {}" --inputs "src/" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 2"* ]]
}

@test "plan --pattern pipeline requires --inputs" {
  run sage plan --pattern pipeline --task "Analyze {},Test {}" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"--inputs"* ]]
}

@test "plan --pattern pipeline generates sequential tasks" {
  run sage plan --pattern pipeline --task "Analyze {},Refactor {},Test {}" --inputs "main.py" --save "$SAGE_HOME/test-plan.json" --yes
  [ -f "$SAGE_HOME/test-plan.json" ]
  local count=$(jq '.tasks | length' "$SAGE_HOME/test-plan.json")
  [ "$count" -eq 3 ]
}

@test "plan --pattern pipeline tasks have linear dependencies" {
  run sage plan --pattern pipeline --task "Step A {},Step B {},Step C {}" --inputs "data" --save "$SAGE_HOME/test-plan.json" --yes
  # Task 1: no deps, Task 2: depends on 1, Task 3: depends on 2
  local d1=$(jq '.tasks[0].depends | length' "$SAGE_HOME/test-plan.json")
  local d2=$(jq '.tasks[1].depends[0]' "$SAGE_HOME/test-plan.json")
  local d3=$(jq '.tasks[2].depends[0]' "$SAGE_HOME/test-plan.json")
  [ "$d1" -eq 0 ]
  [ "$d2" -eq 1 ]
  [ "$d3" -eq 2 ]
}

@test "plan --pattern pipeline replaces {} in each step" {
  run sage plan --pattern pipeline --task "Read {},Transform {}" --inputs "file.txt" --save "$SAGE_HOME/test-plan.json" --yes
  local desc1=$(jq -r '.tasks[0].description' "$SAGE_HOME/test-plan.json")
  local desc2=$(jq -r '.tasks[1].description' "$SAGE_HOME/test-plan.json")
  [[ "$desc1" == "Read file.txt" ]]
  [[ "$desc2" == "Transform file.txt" ]]
}

@test "plan --pattern pipeline sets goal with pipeline label" {
  run sage plan --pattern pipeline --task "A {},B {}" --inputs "x" --save "$SAGE_HOME/test-plan.json" --yes
  local goal=$(jq -r '.goal' "$SAGE_HOME/test-plan.json")
  [[ "$goal" == *"pipeline"* ]]
}