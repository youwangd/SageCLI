#!/usr/bin/env bats
# tests/sage-skill-json.bats — skill ls --json output tests

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME"/{agents,runtimes,skills}
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'EOF'
runtime_start() { :; }
runtime_inject() { echo "ok"; }
EOF
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "skill ls --json emits empty array when no skills" {
  run sage skill ls --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'length')" = "0" ]
  [ "$(echo "$output" | jq -r 'type')" = "array" ]
}

@test "skill ls --json emits array of installed skills" {
  mkdir -p "$SAGE_HOME/skills/code-review"
  cat > "$SAGE_HOME/skills/code-review/skill.json" << 'EOF'
{"name":"code-review","version":"1.0.0","description":"Code review templates"}
EOF
  run sage skill ls --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'length')" = "1" ]
  [ "$(echo "$output" | jq -r '.[0].name')" = "code-review" ]
  [ "$(echo "$output" | jq -r '.[0].description')" = "Code review templates" ]
}

@test "skill ls --json composes with jq for name extraction" {
  mkdir -p "$SAGE_HOME/skills/alpha" "$SAGE_HOME/skills/beta"
  echo '{"name":"alpha","description":"A"}' > "$SAGE_HOME/skills/alpha/skill.json"
  echo '{"name":"beta","description":"B"}' > "$SAGE_HOME/skills/beta/skill.json"
  run bash -c "sage skill ls --json | jq -r '.[].name' | sort"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}
