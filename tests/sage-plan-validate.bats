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

@test "plan --validate accepts valid JSON plan" {
  local f="$SAGE_HOME/plans/valid.json"
  jq -n '{goal:"Test",status:"pending",plan_id:"p1",tasks:[{id:1,template:"implement",description:"Do thing",depends:[],status:"pending"}]}' > "$f"
  run sage plan --validate "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "valid"
}

@test "plan --validate accepts valid YAML pattern" {
  local f="$SAGE_HOME/plans/valid.yaml"
  printf 'pattern: fan-out\ntask: "Review file {input}"\ninputs: a.py,b.py\n' > "$f"
  run sage plan --validate "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "valid"
}

@test "plan --validate rejects JSON missing tasks array" {
  local f="$SAGE_HOME/plans/bad.json"
  echo '{"goal":"Test","status":"pending"}' > "$f"
  run sage plan --validate "$f"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "tasks"
}

@test "plan --validate rejects YAML missing pattern field" {
  local f="$SAGE_HOME/plans/bad.yaml"
  printf 'task: "Do thing"\ninputs: a,b\n' > "$f"
  run sage plan --validate "$f"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "pattern"
}

@test "plan --validate detects cyclic dependencies in JSON" {
  local f="$SAGE_HOME/plans/cycle.json"
  jq -n '{goal:"Cycle",status:"pending",plan_id:"p1",tasks:[
    {id:1,template:"implement",description:"A",depends:[2],status:"pending"},
    {id:2,template:"implement",description:"B",depends:[1],status:"pending"}
  ]}' > "$f"
  run sage plan --validate "$f"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "cycle"
}
