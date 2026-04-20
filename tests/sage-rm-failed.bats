#!/usr/bin/env bats
# tests/sage-rm-failed.bats — rm --failed bulk removes stopped agents whose latest task failed

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-rm-failed-$$"
  mkdir -p "$SAGE_HOME/agents/ok/results" \
           "$SAGE_HOME/agents/bad1/results" \
           "$SAGE_HOME/agents/bad2/results" \
           "$SAGE_HOME/agents/running-bad/results" \
           "$SAGE_HOME/logs"
  for a in ok bad1 bad2 running-bad; do
    echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/$a/runtime.json"
  done
  echo '{}' > "$SAGE_HOME/config.json"
  # ok: latest task succeeded (exit_code 0)
  echo '{"id":"t1","status":"done","exit_code":0,"finished_at":100}' > "$SAGE_HOME/agents/ok/results/t1.status.json"
  # bad1: latest task failed, stopped
  echo '{"id":"t1","status":"failed","exit_code":2,"finished_at":200}' > "$SAGE_HOME/agents/bad1/results/t1.status.json"
  # bad2: older success, newer failure
  echo '{"id":"t1","status":"done","exit_code":0,"finished_at":100}' > "$SAGE_HOME/agents/bad2/results/t1.status.json"
  echo '{"id":"t2","status":"failed","exit_code":1,"finished_at":300}' > "$SAGE_HOME/agents/bad2/results/t2.status.json"
  # running-bad: latest failed BUT agent is running — must be skipped
  echo '{"id":"t1","status":"failed","exit_code":1,"finished_at":250}' > "$SAGE_HOME/agents/running-bad/results/t1.status.json"
  echo $$ > "$SAGE_HOME/agents/running-bad/.pid"
}

@test "rm --failed removes stopped agents whose latest task failed" {
  run ./sage rm --failed
  [ "$status" -eq 0 ]
  [[ "$output" == *"bad1"* ]]
  [[ "$output" == *"bad2"* ]]
  [[ "$output" != *"ok"* ]] || [[ "$output" != *"removed: ok"* ]]
  [ -d "$SAGE_HOME/agents/ok" ]
  [ ! -d "$SAGE_HOME/agents/bad1" ]
  [ ! -d "$SAGE_HOME/agents/bad2" ]
  # running-bad skipped because it's still running
  [ -d "$SAGE_HOME/agents/running-bad" ]
}

@test "rm --failed --dry-run previews without deleting" {
  run ./sage rm --failed --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"bad1"* ]]
  [[ "$output" == *"bad2"* ]]
  [[ "$output" == *"dry-run"* ]]
  [ -d "$SAGE_HOME/agents/bad1" ]
  [ -d "$SAGE_HOME/agents/bad2" ]
}

@test "rm --failed rejects positional name arg" {
  run ./sage rm --failed myagent
  [ "$status" -ne 0 ]
}
