#!/usr/bin/env bats
# tests/sage-ls-failed.bats — ls --failed filter shows agents whose most recent task exited non-zero

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ls-failed-$$"
  mkdir -p "$SAGE_HOME/agents/winner/results" "$SAGE_HOME/agents/loser/results" "$SAGE_HOME/agents/neutral/results"
  for a in winner loser neutral; do
    echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/$a/runtime.json"
  done
  echo '{}' > "$SAGE_HOME/config.json"
  # winner: most recent task succeeded
  echo '{"id":"t1","status":"done","exit_code":0,"finished_at":100}' > "$SAGE_HOME/agents/winner/results/t1.status.json"
  # loser: most recent task failed (non-zero exit); has older successful task
  echo '{"id":"t2","status":"done","exit_code":0,"finished_at":100}' > "$SAGE_HOME/agents/loser/results/t2.status.json"
  echo '{"id":"t3","status":"failed","exit_code":1,"finished_at":200}' > "$SAGE_HOME/agents/loser/results/t3.status.json"
  # neutral: no tasks yet (empty results dir)
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "ls --failed shows only agents with non-zero exit on most recent task" {
  run "$BATS_TEST_DIRNAME/../sage" ls --failed
  [ "$status" -eq 0 ]
  [[ "$output" == *"loser"* ]]
  [[ "$output" != *"winner"* ]]
  [[ "$output" != *"neutral"* ]]
}

@test "ls --failed --json returns array of failed agents" {
  run "$BATS_TEST_DIRNAME/../sage" ls --failed --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | length == 1'
  echo "$output" | jq -e '.[0].name == "loser"'
}

@test "ls --failed shows nothing when all agents succeeded" {
  rm "$SAGE_HOME/agents/loser/results/t3.status.json"
  run "$BATS_TEST_DIRNAME/../sage" ls --failed
  [ "$status" -eq 0 ]
  [[ "$output" != *"loser"* ]]
  [[ "$output" != *"winner"* ]]
}

@test "ls --failed works with -q quiet mode" {
  run "$BATS_TEST_DIRNAME/../sage" ls --failed -q
  [ "$status" -eq 0 ]
  [ "$output" = "loser" ]
}
