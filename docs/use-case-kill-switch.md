# Use Case: Vendor Kill-Switch

## The problem

Your production workflow runs on one AI vendor. It's 3 AM on release night. The
vendor's CLI starts returning 429s. Or their binary segfaults after an update.
Or their SSO expires and auth is broken until someone's awake in corporate IT.

Every hour your workflow is down is an hour of engineering velocity lost. And
you're stuck — because the workflow was built on a vendor-specific orchestrator
(claude-flow, ruflo, mux, emdash) that has no concept of "try a different
backend." Your only recovery is to rewrite the workflow by hand.

## The sage answer

Sage is runtime-agnostic by design. Any workflow can declare one primary and
N fallbacks. If the primary's runtime binary is unreachable at dispatch time,
sage automatically routes to the next healthy fallback — same command, same
output format, same `sage result <id>` retrieval.

### Send-level failover (shipped)

    $ sage send reviewer-primary "Review src/main.py" \
        --fallback reviewer-gemini \
        --fallback reviewer-local

    ⚠  primary 'reviewer-primary' runtime unreachable → failing over to 'reviewer-gemini'
    ✓  task t-1776981073-4498 → reviewer-gemini

If all three are down, sage refuses to dispatch with a clear error rather
than silently hanging.

### Plan-level failover (Phase 20 in progress)

See [docs/demos/kill-switch-drill.yaml](demos/kill-switch-drill.yaml) for the
YAML schema being added to `sage plan`:

    steps:
      - name: review-code
        send: reviewer-primary
        fallback:
          - reviewer-gemini
          - reviewer-local
        message: "Review this code for obvious bugs..."

Each step in a plan declares its own fallback list. One step can fall over to
Gemini while another stays on Claude.

## What "unreachable" means

Sage's health check is intentionally simple and fast (no LLM calls):

- **claude-code / codex / cline / kiro / gemini-cli / llama-cpp**: `command -v <binary>` — is the runtime's CLI binary on PATH?
- **ollama**: `command -v ollama` AND `curl http://localhost:11434/api/version` responds — is the daemon actually serving?
- **bash**: always healthy (no external runtime).

This catches the common failures: missing install, wrong PATH, daemon down,
SSO not refreshed (binary exits non-zero), auth broken. It does NOT catch:
mid-task failures, rate limits, quota exhaustion. Those are handled separately
by `--retry` and `--on-fail`, or by the post-dispatch failover planned for v2.

## Why only sage can do this today

| Competitor | Primary vendor | Fallback support |
|---|---|---|
| claude-flow (32K ⭐) | Claude only | ❌ cannot fall back — vendor-locked |
| ruflo (31K ⭐) | Claude + Codex | ❌ no cross-vendor failover primitive |
| mux (1.6K ⭐) | Claude-focused | ❌ |
| emdash (YC W26) | Claude-focused | ❌ |
| cli-agent-orchestrator (AWS) | Bedrock | ❌ |
| **sage** | **any of 8 runtimes** | ✅ **`--fallback` (shipped v1.4.0+)** |

The fallback feature is trivial code (≈40 lines of bash). What's non-trivial
is having 8 runtime shims behind a uniform command surface — that's the moat.
Every competitor would need to rebuild that substrate to compete here. Most
don't want to; they've bet on a single vendor intentionally.

## Try it

1. Create two agents on different runtimes:

       sage create primary --runtime claude-code
       sage create backup --runtime ollama --model llama3.2:3b

2. Send with fallback:

       sage send primary "hello" --fallback backup

3. To force failover without actually uninstalling Claude Code, stash the binary
   temporarily:

       export PATH_BAK=$PATH
       export PATH=$(echo $PATH | tr ':' '\n' | grep -v claude | paste -sd:)
       sage send primary "hello" --fallback backup
       # ⚠  primary 'primary' runtime unreachable → failing over to 'backup'
       export PATH=$PATH_BAK

## What's next (v2)

- **Plan-level `fallback:` YAML** — per-step fallback list in `sage plan` (in progress)
- **Mid-task failover** — if primary starts generating but returns an error or times out
  within N seconds, cancel and route to fallback
- **Health-check caching** — avoid redundant `command -v` calls when dispatching
  many tasks in a loop
- **Fallback used telemetry** — `sage stats --fallbacks` to show how often each
  vendor's fallback was triggered (helps justify multi-vendor spend to finance)

## The bigger picture

This is the **neutrality moat in its purest form**. Every feature sage adds
should ask: does this make it easier to swap or combine vendors? Kill-switch
is the strongest possible answer to that question — it's a feature that only
exists because sage treats all 8 runtimes as interchangeable citizens.

Other orchestrators will need to copy this eventually. When they do, they'll
discover the hard part wasn't the fallback logic — it's the 8 runtime shims
that make the fallback meaningful. We got there first.
