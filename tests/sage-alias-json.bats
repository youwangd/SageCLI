#!/usr/bin/env bats
# tests/sage-alias-json.bats — tests for sage alias ls --json

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-alias-json-$$"
  mkdir -p "$SAGE_HOME"
  printf '{"version":"1.0"}\n' > "$SAGE_HOME/config.json"
}

@test "alias ls --json on empty returns empty object" {
  run ./sage alias ls --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"{}"* ]]
}

@test "alias ls --json emits valid JSON object with aliases" {
  ./sage alias set review "send reviewer --headless"
  ./sage alias set audit "send auditor --strict"
  run ./sage alias ls --json
  [ "$status" -eq 0 ]
  # Must be parseable by jq and contain both keys
  echo "$output" | jq -e '.review == "send reviewer --headless"' >/dev/null
  echo "$output" | jq -e '.audit == "send auditor --strict"' >/dev/null
}

@test "alias ls --json output has no ANSI color codes" {
  ./sage alias set review "send reviewer"
  run ./sage alias ls --json
  [ "$status" -eq 0 ]
  # No ESC sequences
  [[ "$output" != *$'\e['* ]]
}
