#!/usr/bin/env bats
# tests/sage-version-verbose.bats — version --verbose shows environment details

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-version-$$"
  mkdir -p "$SAGE_HOME/agents/alpha" "$SAGE_HOME/agents/beta"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/beta/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "version --verbose shows sage version" {
  run "$BATS_TEST_DIRNAME/../sage" version --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"sage"* ]]
  [[ "$output" == *"1."* ]]
}

@test "version --verbose shows bash version" {
  run "$BATS_TEST_DIRNAME/../sage" version --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"bash"* ]]
}

@test "version --verbose shows agent count" {
  run "$BATS_TEST_DIRNAME/../sage" version --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents"* ]]
  [[ "$output" == *"2"* ]]
}

@test "version --verbose shows SAGE_HOME path" {
  run "$BATS_TEST_DIRNAME/../sage" version --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SAGE_HOME"* ]]
}

@test "version (no flag) still shows just sage X.Y.Z" {
  run "$BATS_TEST_DIRNAME/../sage" version
  [ "$status" -eq 0 ]
  [[ "$output" == "sage "* ]]
  [[ "$output" != *"bash"* ]]
}
