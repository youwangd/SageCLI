#!/usr/bin/env bats
# tests/sage-logs-failed.bats — logs --failed shows logs from only agents with failed latest task

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-logs-failed-$$"
  mkdir -p "$SAGE_HOME/agents/winner/results" "$SAGE_HOME/agents/loser/results" "$SAGE_HOME/logs"
  for a in winner loser; do
    echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/$a/runtime.json"
  done
  echo '{}' > "$SAGE_HOME/config.json"
  echo '{"id":"t1","status":"done","exit_code":0,"finished_at":100}' > "$SAGE_HOME/agents/winner/results/t1.status.json"
  echo '{"id":"t2","status":"failed","exit_code":1,"finished_at":200}' > "$SAGE_HOME/agents/loser/results/t2.status.json"
  echo "winner log line 1" > "$SAGE_HOME/logs/winner.log"
  echo "winner log line 2" >> "$SAGE_HOME/logs/winner.log"
  echo "loser error: connection refused" > "$SAGE_HOME/logs/loser.log"
  echo "loser stack trace" >> "$SAGE_HOME/logs/loser.log"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "logs --failed shows only failed agents' logs with headers" {
  run "$BATS_TEST_DIRNAME/../sage" logs --failed
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== loser ==="* ]]
  [[ "$output" == *"connection refused"* ]]
  [[ "$output" != *"winner"* ]]
}

@test "logs --failed --tail 1 limits lines per agent" {
  run "$BATS_TEST_DIRNAME/../sage" logs --failed --tail 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"loser stack trace"* ]]
  [[ "$output" != *"connection refused"* ]]
}

@test "logs --failed exits cleanly when no failed agents" {
  rm "$SAGE_HOME/agents/loser/results/t2.status.json"
  run "$BATS_TEST_DIRNAME/../sage" logs --failed
  [ "$status" -eq 0 ]
  [[ "$output" != *"loser"* ]]
}
