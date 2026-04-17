#!/usr/bin/env bats
# tests/sage-result-all.bats — result --all shows all agents' latest results

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-result-all-$$"
  mkdir -p "$SAGE_HOME/agents/alpha/results" "$SAGE_HOME/agents/beta/results" "$SAGE_HOME/agents/gamma"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/beta/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/gamma/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"

  local now
  now=$(date +%s)

  printf '{"id":"t1","status":"done","started_at":%d,"finished_at":%d}\n' "$((now - 50))" "$((now - 10))" > "$SAGE_HOME/agents/alpha/results/t1.status.json"
  echo '{"output":"alpha-out"}' > "$SAGE_HOME/agents/alpha/results/t1.result.json"

  printf '{"id":"t2","status":"done","started_at":%d,"finished_at":%d}\n' "$((now - 40))" "$((now - 5))" > "$SAGE_HOME/agents/beta/results/t2.status.json"
  echo '{"output":"beta-out"}' > "$SAGE_HOME/agents/beta/results/t2.result.json"
  # gamma has no results — should be skipped
}

@test "result --all shows results from all agents" {
  run ./sage result --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
  [[ "$output" != *"gamma"* ]]
}

@test "result --all rejects task-id positional arg" {
  run ./sage result --all t1
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be combined"* ]]
}

@test "result --all with no agents shows message" {
  rm -rf "$SAGE_HOME/agents"/*
  mkdir -p "$SAGE_HOME/agents"
  run ./sage result --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"no results"* ]] || [[ "$output" == *"No"* ]]
}

@test "result --all --json outputs array" {
  run ./sage result --all --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array"'
  echo "$output" | jq -e 'length == 2'
}
