#!/usr/bin/env bats
# tests/sage-result-agent.bats — result --agent filters by agent

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-result-agent-$$"
  mkdir -p "$SAGE_HOME/agents/alpha/results" "$SAGE_HOME/agents/beta/results"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/beta/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"

  local now
  now=$(date +%s)

  # Alpha has 2 tasks — t2 is newer
  printf '{"id":"t1","status":"done","started_at":%d,"finished_at":%d}\n' "$((now - 200))" "$((now - 100))" > "$SAGE_HOME/agents/alpha/results/t1.status.json"
  echo '{"output":"alpha-result-1"}' > "$SAGE_HOME/agents/alpha/results/t1.result.json"
  sleep 1
  printf '{"id":"t2","status":"done","started_at":%d,"finished_at":%d}\n' "$((now - 50))" "$((now - 10))" > "$SAGE_HOME/agents/alpha/results/t2.status.json"
  echo '{"output":"alpha-result-2"}' > "$SAGE_HOME/agents/alpha/results/t2.result.json"

  # Beta has 1 task
  printf '{"id":"t3","status":"done","started_at":%d,"finished_at":%d}\n' "$((now - 300))" "$((now - 250))" > "$SAGE_HOME/agents/beta/results/t3.status.json"
  echo '{"output":"beta-result"}' > "$SAGE_HOME/agents/beta/results/t3.result.json"
}

@test "result --agent alpha shows alpha's most recent result" {
  run ./sage result --agent alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha-result-2"* ]]
  [[ "$output" != *"beta-result"* ]]
}

@test "result --agent beta shows beta's result" {
  run ./sage result --agent beta
  [ "$status" -eq 0 ]
  [[ "$output" == *"beta-result"* ]]
  [[ "$output" != *"alpha-result"* ]]
}

@test "result --agent nonexistent fails" {
  run ./sage result --agent nonexistent
  [ "$status" -ne 0 ]
}

@test "result --agent with task-id scopes search to that agent" {
  run ./sage result --agent alpha t3
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
