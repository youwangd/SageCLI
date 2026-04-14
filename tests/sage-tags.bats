#!/usr/bin/env bats
# tests/sage-tags.bats — tests for task tagging (send --tag, history --tag)

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-tags-$$"
  sage init --quiet 2>/dev/null || true
  sage create tagger --runtime bash 2>/dev/null || true
}

@test "send --tag stores tag in status.json" {
  run ./sage send tagger "echo hello" --headless --tag bugfix
  [ "$status" -eq 0 ]
  # Find the status file and check for tag
  local sf
  sf=$(ls "$SAGE_HOME/agents/tagger/results/"*.status.json 2>/dev/null | head -1)
  [ -n "$sf" ]
  run jq -r '.tags[0]' "$sf"
  [ "$output" = "bugfix" ]
}

@test "send --tag multiple tags stored as array" {
  run ./sage send tagger "echo hello" --headless --tag bugfix --tag auth
  [ "$status" -eq 0 ]
  local sf
  sf=$(ls "$SAGE_HOME/agents/tagger/results/"*.status.json 2>/dev/null | head -1)
  [ -n "$sf" ]
  run jq -r '.tags | length' "$sf"
  [ "$output" = "2" ]
}

@test "history --tag filters by tag" {
  # Send two tasks with different tags (sleep to get unique task IDs)
  sage send tagger "echo one" --headless --tag review
  sleep 1
  sage send tagger "echo two" --headless --tag deploy
  run sage history --tag review
  [ "$status" -eq 0 ]
  [[ "$output" == *"tagger"* ]]
}

@test "history --tag no matches shows info" {
  ./sage send tagger "echo one" --headless --tag review
  run ./sage history --tag nonexistent
  [ "$status" -eq 0 ]
  [[ "$output" == *"no task history"* ]]
}

@test "history --json includes tags field" {
  sage send tagger "echo hello" --headless --tag bugfix
  run sage history --json
  [ "$status" -eq 0 ]
  local tag_val
  tag_val=$(echo "$output" | jq -r '.[0].tags[0]' 2>/dev/null)
  [ "$tag_val" = "bugfix" ]
}
