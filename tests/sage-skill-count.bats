#!/usr/bin/env bats
# tests/sage-skill-count.bats — skill ls --count prints plain integer

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

@test "skill ls --count prints 0 when no skills installed" {
  run sage skill ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "skill ls --count prints integer count of installed skills" {
  mkdir -p "$SAGE_HOME/skills/alpha" "$SAGE_HOME/skills/beta" "$SAGE_HOME/skills/gamma"
  echo '{"name":"alpha","description":"A"}' > "$SAGE_HOME/skills/alpha/skill.json"
  echo '{"name":"beta","description":"B"}' > "$SAGE_HOME/skills/beta/skill.json"
  echo '{"name":"gamma","description":"G"}' > "$SAGE_HOME/skills/gamma/skill.json"
  run sage skill ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "skill ls --count output is scriptable (pure digits)" {
  mkdir -p "$SAGE_HOME/skills/one"
  echo '{"name":"one","description":"One"}' > "$SAGE_HOME/skills/one/skill.json"
  run sage skill ls --count
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}
