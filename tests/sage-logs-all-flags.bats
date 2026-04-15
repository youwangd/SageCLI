#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --force >/dev/null 2>&1
  mkdir -p "$SAGE_HOME/agents/alpha" "$SAGE_HOME/agents/beta" "$SAGE_HOME/logs"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/beta/runtime.json"
  printf 'alpha line 1\nalpha error here\n' > "$SAGE_HOME/logs/alpha.log"
  printf 'beta line 1\nbeta warning here\n' > "$SAGE_HOME/logs/beta.log"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "logs --all -f does not show usage error" {
  # --all -f currently fails with usage error because both write to flag
  run timeout 1 sage logs --all -f
  # timeout exits 124, sage usage error exits 1
  [[ "$output" != *"usage:"* ]]
}

@test "logs -f --all does not show usage error" {
  run timeout 1 sage logs -f --all
  [[ "$output" != *"usage:"* ]]
}

@test "logs --all --grep returns 0 when some agents match" {
  run sage logs --all --grep error
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"error"* ]]
}

@test "logs --all --grep shows only matching lines" {
  run sage logs --all --grep error
  [[ "$output" != *"beta"* ]]
}
