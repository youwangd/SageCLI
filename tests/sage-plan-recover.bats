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

# Helper: create a plan JSON
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

@test "plan --recover reports nothing when no interrupted plans" {
  create_plan "$SAGE_HOME/plans/p1.json" "Done plan" "completed" 1 "done" "Task A"
  run sage plan --recover
  [[ "$output" == *"no interrupted plans"* ]]
}

@test "plan --recover detects plan with status=running" {
  create_plan "$SAGE_HOME/plans/p1.json" "Interrupted plan" "running" 1 "done" "Task A" 2 "pending" "Task B"
  run sage plan --recover
  [[ "$output" == *"Interrupted plan"* ]]
}

@test "plan --recover shows count of interrupted plans" {
  create_plan "$SAGE_HOME/plans/p1.json" "Plan A" "running" 1 "pending" "Task"
  create_plan "$SAGE_HOME/plans/p2.json" "Plan B" "running" 1 "pending" "Task"
  run sage plan --recover
  [[ "$output" == *"2"* ]]
}

@test "plan --recover skips completed plans" {
  create_plan "$SAGE_HOME/plans/done.json" "Completed" "completed" 1 "done" "Task"
  create_plan "$SAGE_HOME/plans/stale.json" "Stale" "running" 1 "pending" "Task"
  run sage plan --recover
  [[ "$output" == *"Stale"* ]]
  [[ "$output" != *"Completed"* ]]
}

@test "doctor detects stale plans" {
  create_plan "$SAGE_HOME/plans/stale.json" "Stale plan" "running" 1 "running" "Task"
  run sage doctor
  [[ "$output" == *"stale plan"* ]] || [[ "$output" == *"interrupted plan"* ]]
}
