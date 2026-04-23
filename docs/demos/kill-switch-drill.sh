#!/usr/bin/env bash
# Kill-Switch Drill: "Your primary AI vendor is down. Your workflow doesn't care."
#
# Proves sage's vendor-neutrality moat with shipped primitives only.
# Uses `sage send --fallback` (Phase 20 v1). No new plan engine needed.
#
# USAGE
#   bash docs/demos/kill-switch-drill.sh                 # normal run
#   CHAOS_BINARIES='claude gemini' bash ...drill.sh      # simulate cloud down
#
# WHAT IT DOES
#   Creates 3 agents on 3 different vendors, then sends a code-review task
#   with a fallback chain. If primary is down, sage auto-routes to the next
#   healthy agent. Optional CHAOS_BINARIES= mask binaries from PATH to force
#   failover without actually uninstalling anything.

set -euo pipefail

SAGE="${SAGE:-$(dirname "$0")/../../sage}"
DRILL_TAG="killswitch-drill"

# --- Chaos mode: filter named binaries out of PATH ----------------------------
if [[ -n "${CHAOS_BINARIES:-}" ]]; then
  chaos_filter=""
  for bin in $CHAOS_BINARIES; do
    chaos_filter="${chaos_filter:+$chaos_filter|}$(command -v "$bin" 2>/dev/null | xargs -r dirname)"
  done
  if [[ -n "$chaos_filter" ]]; then
    PATH=$(echo "$PATH" | tr ':' '\n' | grep -vE "^($chaos_filter)$" | paste -sd:)
    echo "[chaos] PATH filtered — these binaries are now unreachable: $CHAOS_BINARIES"
  fi
fi

# --- Setup --------------------------------------------------------------------
cleanup() {
  for a in "$DRILL_TAG-primary" "$DRILL_TAG-gemini" "$DRILL_TAG-local"; do
    "$SAGE" stop "$a" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

echo "=== Creating 3 agents on 3 vendors ==="
"$SAGE" create "$DRILL_TAG-primary" --runtime claude-code >/dev/null 2>&1 || true
"$SAGE" create "$DRILL_TAG-gemini"  --runtime gemini-cli  >/dev/null 2>&1 || true
"$SAGE" create "$DRILL_TAG-local"   --runtime ollama --model llama3.2:3b >/dev/null 2>&1 || true

# --- The actual drill: one send with fallback chain ---------------------------
echo ""
echo "=== Sending task with fallback chain ==="
echo "    primary:   $DRILL_TAG-primary  (claude-code)"
echo "    fallback1: $DRILL_TAG-gemini   (gemini-cli)"
echo "    fallback2: $DRILL_TAG-local    (ollama llama3.2:3b)"
echo ""

task_out=$("$SAGE" send "$DRILL_TAG-primary" \
  "Say HELLO in exactly one word." \
  --fallback "$DRILL_TAG-gemini" \
  --fallback "$DRILL_TAG-local" 2>&1)

echo "$task_out"

# Extract task ID
task_id=$(echo "$task_out" | grep -oE 't-[0-9]+-[0-9]+' | head -1)
if [[ -z "$task_id" ]]; then
  echo "ERROR: no task ID in send output"
  exit 1
fi

echo ""
echo "=== Waiting for task $task_id ==="
for _ in $(seq 1 60); do
  status=$("$SAGE" result "$task_id" --json 2>/dev/null | \
    python3 -c "import json,sys; print(json.load(sys.stdin).get('status','?'))" 2>/dev/null || echo "?")
  [[ "$status" == "done" ]] && break
  sleep 2
done

echo ""
echo "=== Result (status=$status) ==="
"$SAGE" result "$task_id" --json 2>&1 | python3 -c "
import json, sys, re
d = json.load(sys.stdin)
out = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', d.get('output', ''))
out = re.sub(r'[\u2800-\u28ff]', '', out).strip()
print(f\"agent that answered: {d.get('agent')}\")
print('---')
print(out[-500:])
"
