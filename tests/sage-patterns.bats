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

# --- debate pattern ---

@test "plan --pattern debate requires --task" {
  run sage plan --pattern debate --inputs "a,b,c" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"--task"* ]]
}

@test "plan --pattern debate requires --inputs with at least 2 participants" {
  run sage plan --pattern debate --task "Implement auth" --inputs "solo" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 2"* ]]
}

@test "plan --pattern debate generates N+1 tasks (N participants + synthesizer)" {
  run sage plan --pattern debate --task "Implement auth" --inputs "claude,gemini,codex" --save "$SAGE_HOME/test-plan.json" --yes
  [ -f "$SAGE_HOME/test-plan.json" ]
  local count=$(jq '.tasks | length' "$SAGE_HOME/test-plan.json")
  [ "$count" -eq 4 ]
}

@test "plan --pattern debate first N tasks are parallel (no deps)" {
  run sage plan --pattern debate --task "Solve puzzle" --inputs "a,b,c" --save "$SAGE_HOME/test-plan.json" --yes
  local d1=$(jq '.tasks[0].depends | length' "$SAGE_HOME/test-plan.json")
  local d2=$(jq '.tasks[1].depends | length' "$SAGE_HOME/test-plan.json")
  local d3=$(jq '.tasks[2].depends | length' "$SAGE_HOME/test-plan.json")
  [ "$d1" -eq 0 ]
  [ "$d2" -eq 0 ]
  [ "$d3" -eq 0 ]
}

@test "plan --pattern debate synthesizer depends on all participants" {
  run sage plan --pattern debate --task "Design API" --inputs "a,b,c" --save "$SAGE_HOME/test-plan.json" --yes
  local last_deps=$(jq -c '.tasks[-1].depends | sort' "$SAGE_HOME/test-plan.json")
  [ "$last_deps" = "[1,2,3]" ]
}

@test "plan --pattern debate synthesizer description mentions synthesize" {
  run sage plan --pattern debate --task "Build feature" --inputs "x,y" --save "$SAGE_HOME/test-plan.json" --yes
  local desc=$(jq -r '.tasks[-1].description' "$SAGE_HOME/test-plan.json")
  [[ "$desc" == *"ynthesize"* ]] || [[ "$desc" == *"best"* ]]
}

@test "plan --pattern debate sets goal with debate label" {
  run sage plan --pattern debate --task "Write tests" --inputs "a,b" --save "$SAGE_HOME/test-plan.json" --yes
  local goal=$(jq -r '.goal' "$SAGE_HOME/test-plan.json")
  [[ "$goal" == *"debate"* ]]
}

# --- map-reduce pattern ---

@test "plan --pattern map-reduce requires --task" {
  run sage plan --pattern map-reduce --inputs "a,b,c"
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires --task"* ]]
}

@test "plan --pattern map-reduce requires {} in --task" {
  run sage plan --pattern map-reduce --task "Review code" --inputs "a,b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"{}"* ]]
}

@test "plan --pattern map-reduce requires at least 2 inputs" {
  run sage plan --pattern map-reduce --task "Review {}" --inputs "a"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 2"* ]]
}

@test "plan --pattern map-reduce generates N+1 tasks (N map + 1 reduce)" {
  run sage plan --pattern map-reduce --task "Review {}" --inputs "a,b,c" --save "$SAGE_HOME/test-plan.json" --yes
  local count=$(jq '.tasks | length' "$SAGE_HOME/test-plan.json")
  [ "$count" -eq 4 ]
}

@test "plan --pattern map-reduce map tasks are parallel (no deps)" {
  run sage plan --pattern map-reduce --task "Lint {}" --inputs "x,y,z" --save "$SAGE_HOME/test-plan.json" --yes
  local d1=$(jq '.tasks[0].depends | length' "$SAGE_HOME/test-plan.json")
  local d2=$(jq '.tasks[1].depends | length' "$SAGE_HOME/test-plan.json")
  local d3=$(jq '.tasks[2].depends | length' "$SAGE_HOME/test-plan.json")
  [ "$d1" -eq 0 ]
  [ "$d2" -eq 0 ]
  [ "$d3" -eq 0 ]
}

@test "plan --pattern map-reduce reduce depends on all map tasks" {
  run sage plan --pattern map-reduce --task "Test {}" --inputs "a,b,c" --save "$SAGE_HOME/test-plan.json" --yes
  local last_deps=$(jq -c '.tasks[-1].depends | sort' "$SAGE_HOME/test-plan.json")
  [ "$last_deps" = "[1,2,3]" ]
}

@test "plan --pattern map-reduce substitutes {} in map task descriptions" {
  run sage plan --pattern map-reduce --task "Audit {}" --inputs "auth,db" --save "$SAGE_HOME/test-plan.json" --yes
  local d1=$(jq -r '.tasks[0].description' "$SAGE_HOME/test-plan.json")
  local d2=$(jq -r '.tasks[1].description' "$SAGE_HOME/test-plan.json")
  [[ "$d1" == *"auth"* ]]
  [[ "$d2" == *"db"* ]]
}

@test "plan --pattern map-reduce reduce description mentions reduce/merge" {
  run sage plan --pattern map-reduce --task "Check {}" --inputs "a,b" --save "$SAGE_HOME/test-plan.json" --yes
  local desc=$(jq -r '.tasks[-1].description' "$SAGE_HOME/test-plan.json")
  [[ "$desc" == *"educe"* ]] || [[ "$desc" == *"erge"* ]]
}