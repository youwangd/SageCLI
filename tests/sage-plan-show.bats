#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --force 2>/dev/null
  mkdir -p "$SAGE_HOME/plans"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# Helper: create a plan JSON with given tasks and statuses
create_plan() {
  local file="$1" goal="$2" status="$3"
  shift 3
  local tasks="[]"
  while [[ $# -ge 3 ]]; do
    local tid="$1" tstat="$2" tdesc="$3"
    tasks=$(echo "$tasks" | jq --argjson id "$tid" --arg s "$tstat" --arg d "$tdesc" \
      '. + [{id:$id, template:"implement", description:$d, depends:[], status:$s}]')
    shift 3
  done
  jq -n --arg g "$goal" --arg s "$status" --arg pid "plan-test" --argjson t "$tasks" \
    '{goal:$g, status:$s, plan_id:$pid, tasks:$t}' > "$file"
}

@test "plan --show displays goal" {
  create_plan "$SAGE_HOME/plans/p1.json" "Build a widget" "completed" 1 "done" "Design widget"
  run sage plan --show "$SAGE_HOME/plans/p1.json"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Build a widget"
}

@test "plan --show displays overall status" {
  create_plan "$SAGE_HOME/plans/p1.json" "Test goal" "running" 1 "running" "Task A"
  run sage plan --show "$SAGE_HOME/plans/p1.json"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "running"
}

@test "plan --show displays task ids and descriptions" {
  create_plan "$SAGE_HOME/plans/p1.json" "Multi task" "completed" \
    1 "done" "First task" 2 "done" "Second task"
  run sage plan --show "$SAGE_HOME/plans/p1.json"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "#1"
  echo "$output" | grep -q "First task"
  echo "$output" | grep -q "#2"
  echo "$output" | grep -q "Second task"
}

@test "plan --show displays task status" {
  create_plan "$SAGE_HOME/plans/p1.json" "Mixed" "running" \
    1 "done" "Done task" 2 "running" "Active task" 3 "pending" "Waiting" 4 "failed" "Broken"
  run sage plan --show "$SAGE_HOME/plans/p1.json"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "done"
  echo "$output" | grep -q "running"
  echo "$output" | grep -q "pending"
  echo "$output" | grep -q "failed"
}

@test "plan --show groups tasks by wave" {
  # Task 2 depends on task 1 → wave 1 and wave 2
  local file="$SAGE_HOME/plans/p1.json"
  jq -n '{goal:"Waves test", status:"completed", plan_id:"plan-w",
    tasks:[{id:1,template:"implement",description:"Base",depends:[],status:"done"},
           {id:2,template:"implement",description:"Build on base",depends:[1],status:"done"}]}' > "$file"
  run sage plan --show "$file"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Wave 1"
  echo "$output" | grep -q "Wave 2"
}

@test "plan --show fails on missing file" {
  run sage plan --show "/nonexistent/plan.json"
  [ "$status" -ne 0 ]
}

@test "plan --show fails with no argument" {
  run sage plan --show
  [ "$status" -ne 0 ]
}
