#!/usr/bin/env bats
# tests/sage-stop-failed.bats — stop --failed stops only RUNNING agents whose latest task failed

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-stop-failed-$$"
  mkdir -p "$SAGE_HOME/agents/winner/results" \
           "$SAGE_HOME/agents/loser/results" \
           "$SAGE_HOME/agents/zombie/results" \
           "$SAGE_HOME/logs"
  for a in winner loser zombie; do
    echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/$a/runtime.json"
    echo '' > "$SAGE_HOME/agents/$a/system_prompt"
  done
  echo '{}' > "$SAGE_HOME/config.json"
  # winner: running, succeeded (should NOT be stopped)
  echo '{"id":"t1","status":"done","exit_code":0,"finished_at":100}' > "$SAGE_HOME/agents/winner/results/t1.status.json"
  # loser: running, failed (SHOULD be stopped)
  echo '{"id":"t2","status":"failed","exit_code":1,"finished_at":200}' > "$SAGE_HOME/agents/loser/results/t2.status.json"
  # zombie: NOT running, failed (should NOT be stopped — already stopped)
  echo '{"id":"t3","status":"failed","exit_code":1,"finished_at":300}' > "$SAGE_HOME/agents/zombie/results/t3.status.json"
  # simulate running for winner and loser via .pid files pointing to PID 1 (init, always alive)
  echo 1 > "$SAGE_HOME/agents/winner/.pid"
  echo 1 > "$SAGE_HOME/agents/loser/.pid"
  # zombie has no .pid — not running
}

teardown() {
  tmux kill-session -t sage 2>/dev/null || true
  rm -rf "$SAGE_HOME"
}

@test "stop --failed --dry-run lists only running failed agents" {
  run "$BATS_TEST_DIRNAME/../sage" stop --failed --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"loser"* ]]
  [[ "$output" != *"winner"* ]]
  [[ "$output" != *"zombie"* ]]
}

@test "stop --failed --dry-run does not actually stop" {
  run "$BATS_TEST_DIRNAME/../sage" stop --failed --dry-run
  [ "$status" -eq 0 ]
  # pid files remain
  [ -f "$SAGE_HOME/agents/loser/.pid" ]
  [ -f "$SAGE_HOME/agents/winner/.pid" ]
}

@test "stop --failed with no failed running agents exits 0" {
  rm "$SAGE_HOME/agents/loser/.pid"
  run "$BATS_TEST_DIRNAME/../sage" stop --failed --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"loser"* ]]
}
