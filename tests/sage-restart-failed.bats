#!/usr/bin/env bats
# tests/sage-restart-failed.bats — restart --failed restarts only agents whose latest task failed

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-restart-failed-$$"
  mkdir -p "$SAGE_HOME/agents/winner/results" "$SAGE_HOME/agents/loser/results" "$SAGE_HOME/logs"
  for a in winner loser; do
    echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/$a/runtime.json"
    echo '' > "$SAGE_HOME/agents/$a/system_prompt"
  done
  echo '{}' > "$SAGE_HOME/config.json"
  echo '{"id":"t1","status":"done","exit_code":0,"finished_at":100}' > "$SAGE_HOME/agents/winner/results/t1.status.json"
  echo '{"id":"t2","status":"failed","exit_code":1,"finished_at":200}' > "$SAGE_HOME/agents/loser/results/t2.status.json"
}

teardown() {
  # Clean up any tmux sessions/windows spawned
  tmux kill-session -t sage 2>/dev/null || true
  rm -rf "$SAGE_HOME"
}

@test "restart --failed only restarts failed agents (dry-run prints names)" {
  run "$BATS_TEST_DIRNAME/../sage" restart --failed --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"loser"* ]]
  [[ "$output" != *"winner"* ]]
}

@test "restart --failed with no failed agents exits 0" {
  rm "$SAGE_HOME/agents/loser/results/t2.status.json"
  run "$BATS_TEST_DIRNAME/../sage" restart --failed --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"loser"* ]]
}

@test "restart --failed --dry-run does not actually restart" {
  run "$BATS_TEST_DIRNAME/../sage" restart --failed --dry-run
  [ "$status" -eq 0 ]
  # no pid files should appear
  [ ! -f "$SAGE_HOME/agents/loser/.pid" ]
}
