#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-export-test-$$"
  "$SAGE" init 2>/dev/null
  "$SAGE" create myagent --runtime bash 2>/dev/null
  echo "You are a helpful assistant" > "$SAGE_HOME/agents/myagent/system_prompt"
  mkdir -p "$SAGE_HOME/agents/myagent/skills/test-skill"
  echo '{"name":"test"}' > "$SAGE_HOME/agents/myagent/skills/test-skill/skill.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
  rm -f "$BATS_TMPDIR"/myagent.tar.gz "$BATS_TMPDIR"/custom.tar.gz
}

@test "sage export requires agent name" {
  run "$SAGE" export
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "sage export fails for nonexistent agent" {
  run "$SAGE" export noagent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "sage export creates tar.gz in current dir" {
  cd "$BATS_TMPDIR"
  run "$SAGE" export myagent
  [ "$status" -eq 0 ]
  [ -f "$BATS_TMPDIR/myagent.tar.gz" ]
}

@test "sage export archive contains runtime.json and system_prompt" {
  cd "$BATS_TMPDIR"
  run "$SAGE" export myagent
  [ "$status" -eq 0 ]
  run tar tzf "$BATS_TMPDIR/myagent.tar.gz"
  [[ "$output" == *"runtime.json"* ]]
  [[ "$output" == *"system_prompt"* ]]
}

@test "sage export archive contains skills" {
  cd "$BATS_TMPDIR"
  run "$SAGE" export myagent
  [ "$status" -eq 0 ]
  run tar tzf "$BATS_TMPDIR/myagent.tar.gz"
  [[ "$output" == *"skills/"* ]]
}

@test "sage export --output custom path" {
  run "$SAGE" export myagent --output "$BATS_TMPDIR/custom.tar.gz"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TMPDIR/custom.tar.gz" ]
}

@test "sage export excludes state and workspace dirs" {
  mkdir -p "$SAGE_HOME/agents/myagent/state" "$SAGE_HOME/agents/myagent/workspace"
  echo "data" > "$SAGE_HOME/agents/myagent/state/task.json"
  echo "data" > "$SAGE_HOME/agents/myagent/workspace/file.txt"
  cd "$BATS_TMPDIR"
  run "$SAGE" export myagent
  [ "$status" -eq 0 ]
  run tar tzf "$BATS_TMPDIR/myagent.tar.gz"
  [[ "$output" != *"state/"* ]]
  [[ "$output" != *"workspace/"* ]]
}

@test "sage create --from imports exported archive" {
  cd "$BATS_TMPDIR"
  "$SAGE" export myagent
  run "$SAGE" create imported --from "$BATS_TMPDIR/myagent.tar.gz"
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/imported/runtime.json" ]
  [ -f "$SAGE_HOME/agents/imported/system_prompt" ]
  local name
  name=$(jq -r '.name' "$SAGE_HOME/agents/imported/runtime.json")
  [ "$name" = "imported" ]
}
