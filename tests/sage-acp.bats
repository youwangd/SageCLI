#!/usr/bin/env bats
# tests/sage-acp.bats — ACP Registry discovery (ls/show/install)

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-acp-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  # Pre-seed registry cache so tests are hermetic (no network)
  cat > "$SAGE_HOME/acp-registry.json" <<'JSON'
{
  "version": "1.0.0",
  "agents": [
    {
      "id": "test-agent",
      "name": "Test Agent",
      "version": "1.2.3",
      "description": "A test ACP agent for unit tests",
      "repository": "https://github.com/example/test-agent",
      "license": "MIT",
      "distribution": {
        "npx": { "package": "@example/test-agent", "args": ["--acp"] }
      }
    },
    {
      "id": "bin-only",
      "name": "Binary Only",
      "version": "0.1.0",
      "description": "Binary distribution agent",
      "repository": "https://github.com/example/bin-only",
      "license": "Apache-2.0",
      "distribution": {
        "binary": {
          "linux-x86_64": { "archive": "https://example.com/x.tar.gz", "cmd": "./x" }
        }
      }
    }
  ]
}
JSON
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "acp ls shows agent ids and names from cache" {
  run "$SAGE" acp ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-agent"* ]]
  [[ "$output" == *"bin-only"* ]]
  [[ "$output" == *"Test Agent"* ]]
}

@test "acp ls --json emits raw registry" {
  run "$SAGE" acp ls --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.agents | length == 2' >/dev/null
}

@test "acp show <id> prints agent details" {
  run "$SAGE" acp show test-agent
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-agent"* ]]
  [[ "$output" == *"1.2.3"* ]]
  [[ "$output" == *"npx"* ]]
}

@test "acp show on unknown id exits non-zero" {
  run "$SAGE" acp show does-not-exist
  [ "$status" -ne 0 ]
}

@test "acp install <id> creates sage agent using id as name" {
  run "$SAGE" acp install test-agent
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/test-agent" ]
  run jq -r .runtime "$SAGE_HOME/agents/test-agent/runtime.json"
  [ "$output" = "acp" ]
}

@test "acp install --as <name> overrides agent name" {
  run "$SAGE" acp install test-agent --as my-wrapper
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/my-wrapper" ]
  [ ! -d "$SAGE_HOME/agents/test-agent" ]
}

@test "acp install refuses binary-only agent (not supported yet)" {
  run "$SAGE" acp install bin-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"binary"* ]] || [[ "$output" == *"not supported"* ]] || [[ "$output" == *"npx"* ]] || [[ "$output" == *"uvx"* ]]
}

@test "acp ls with no cache and no network fails cleanly" {
  rm -f "$SAGE_HOME/acp-registry.json"
  # force offline by pointing at an invalid URL
  SAGE_ACP_REGISTRY_URL="http://127.0.0.1:1/nope.json" run "$SAGE" acp ls
  [ "$status" -ne 0 ]
  [[ "$output" == *"registry"* ]] || [[ "$output" == *"fetch"* ]] || [[ "$output" == *"cache"* ]]
}

@test "help lists acp command" {
  run "$SAGE" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"acp"* ]]
}
