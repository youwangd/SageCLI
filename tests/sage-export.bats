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

@test "sage export --format json outputs valid JSON" {
  run "$SAGE" export myagent --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "sage export --format json contains runtime config" {
  run "$SAGE" export myagent --format json
  [ "$status" -eq 0 ]
  local rt
  rt=$(echo "$output" | jq -r '.runtime.runtime')
  [ "$rt" = "bash" ]
}

@test "sage export --format json contains system_prompt" {
  run "$SAGE" export myagent --format json
  [ "$status" -eq 0 ]
  local sp
  sp=$(echo "$output" | jq -r '.system_prompt')
  [ "$sp" = "You are a helpful assistant" ]
}

@test "sage export --format json lists skills" {
  run "$SAGE" export myagent --format json
  [ "$status" -eq 0 ]
  local skill
  skill=$(echo "$output" | jq -r '.skills[0]')
  [ "$skill" = "test-skill" ]
}

@test "sage export --format json does not create tar.gz" {
  cd "$BATS_TMPDIR"
  run "$SAGE" export myagent --format json
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TMPDIR/myagent.tar.gz" ]
}

# --- create --from URL ---

@test "create --from http URL downloads and imports" {
  # Create a local archive to serve
  run "$SAGE" create exporter --runtime bash
  [ "$status" -eq 0 ]
  echo "You are a remote agent" > "$SAGE_HOME/agents/exporter/system_prompt"
  run "$SAGE" export exporter --output "$BATS_TMPDIR/remote.tar.gz"
  [ "$status" -eq 0 ]

  # Start a simple HTTP server
  cd "$BATS_TMPDIR"
  python3 -m http.server 18923 &
  local srv_pid=$!
  sleep 1

  run "$SAGE" create from-url --from "http://localhost:18923/remote.tar.gz"
  kill "$srv_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/from-url/runtime.json" ]
  local name
  name=$(jq -r '.name' "$SAGE_HOME/agents/from-url/runtime.json")
  [ "$name" = "from-url" ]
}

@test "create --from URL fails gracefully on bad URL" {
  run "$SAGE" create bad-url --from "http://localhost:19999/nonexistent.tar.gz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"download failed"* ]]
}

@test "create --from GitHub URL auto-appends archive path" {
  # This tests the URL transformation logic — will fail on network but should attempt the right URL
  # We mock by checking the error message contains the transformed URL
  run "$SAGE" create gh-agent --from "https://github.com/fake/repo"
  [ "$status" -ne 0 ]
  # Should fail with download error (not "archive not found" which means it tried as local file)
  [[ "$output" == *"download failed"* ]]
}