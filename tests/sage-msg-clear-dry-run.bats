#!/usr/bin/env bats
# tests/sage-msg-clear-dry-run.bats — msg clear --dry-run previews count without deleting
# Mirrors tests/sage-memory-dry-run.bats for the sibling msg subsystem.

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/agents/worker/messages"
  echo '{"ts":1,"from":"a","text":"hi"}' > "$SAGE_HOME/agents/worker/messages/1.json"
  echo '{"ts":2,"from":"b","text":"yo"}' > "$SAGE_HOME/agents/worker/messages/2.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "msg clear --dry-run previews count without deleting" {
  run ./sage msg clear worker --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would clear 2"
  [ -f "$SAGE_HOME/agents/worker/messages/1.json" ]
  [ -f "$SAGE_HOME/agents/worker/messages/2.json" ]
}

@test "msg clear --dry-run reports 0 for agent with no messages" {
  mkdir -p "$SAGE_HOME/agents/empty/messages"
  run ./sage msg clear empty --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would clear 0"
}

@test "msg clear without --dry-run still deletes" {
  run ./sage msg clear worker
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/agents/worker/messages/1.json" ]
  [ ! -f "$SAGE_HOME/agents/worker/messages/2.json" ]
}
