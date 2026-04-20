#!/usr/bin/env bats
# tests/sage-result-failed.bats — result --failed shows results only from failed latest tasks

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-result-failed-$$"
  mkdir -p "$SAGE_HOME/agents/winner/results" "$SAGE_HOME/agents/loser/results"
  for a in winner loser; do
    echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/$a/runtime.json"
  done
  echo '{}' > "$SAGE_HOME/config.json"
  echo '{"id":"t1","status":"done","exit_code":0,"finished_at":100}' > "$SAGE_HOME/agents/winner/results/t1.status.json"
  echo 'winner output' > "$SAGE_HOME/agents/winner/results/t1.result.json"
  echo '{"id":"t2","status":"failed","exit_code":1,"finished_at":200}' > "$SAGE_HOME/agents/loser/results/t2.status.json"
  echo 'loser traceback' > "$SAGE_HOME/agents/loser/results/t2.result.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "result --failed shows only failed agents' results" {
  run "$BATS_TEST_DIRNAME/../sage" result --failed
  [ "$status" -eq 0 ]
  [[ "$output" == *"loser"* ]]
  [[ "$output" == *"traceback"* ]]
  [[ "$output" != *"winner"* ]]
}

@test "result --failed --json returns only failed agents" {
  run "$BATS_TEST_DIRNAME/../sage" result --failed --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | length == 1'
  echo "$output" | jq -e '.[0].agent == "loser"'
}

@test "result --failed shows nothing when all succeeded" {
  rm "$SAGE_HOME/agents/loser/results/t2.status.json"
  run "$BATS_TEST_DIRNAME/../sage" result --failed
  [ "$status" -eq 0 ]
  [[ "$output" != *"loser"* ]]
}
