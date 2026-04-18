#!/usr/bin/env bats
# tests/sage-rm-stopped.bats — rm --stopped bulk removes stopped agents

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-rm-stopped-$$"
  mkdir -p "$SAGE_HOME/agents/alive" "$SAGE_HOME/agents/dead1" "$SAGE_HOME/agents/dead2" "$SAGE_HOME/logs"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alive/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/dead1/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/dead2/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"
  # alive has a real pid
  echo $$ > "$SAGE_HOME/agents/alive/.pid"
  # dead1 and dead2 have no pid — they're stopped
}

@test "rm --stopped removes all stopped agents" {
  run ./sage rm --stopped
  [ "$status" -eq 0 ]
  [[ "$output" == *"dead1"* ]]
  [[ "$output" == *"dead2"* ]]
  [[ "$output" != *"alive"* ]]
  [ -d "$SAGE_HOME/agents/alive" ]
  [ ! -d "$SAGE_HOME/agents/dead1" ]
  [ ! -d "$SAGE_HOME/agents/dead2" ]
}

@test "rm --stopped --dry-run previews without deleting" {
  run ./sage rm --stopped --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dead1"* ]]
  [[ "$output" == *"dead2"* ]]
  [[ "$output" == *"dry-run"* ]]
  [ -d "$SAGE_HOME/agents/dead1" ]
  [ -d "$SAGE_HOME/agents/dead2" ]
}

@test "rm --stopped rejects positional name arg" {
  run ./sage rm --stopped myagent
  [ "$status" -ne 0 ]
}

@test "rm --stopped with no stopped agents shows message" {
  # all agents are alive
  echo $$ > "$SAGE_HOME/agents/dead1/.pid"
  echo $$ > "$SAGE_HOME/agents/dead2/.pid"
  run ./sage rm --stopped
  [ "$status" -eq 0 ]
  [[ "$output" == *"0"* ]] || [[ "$output" == *"no stopped"* ]]
}
