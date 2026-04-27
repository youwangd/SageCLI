# Portable orchestration beats locked-in orchestration

*2026-04-27*

Most popular orchestrators for AI coding CLIs are locked to a single vendor. Claude-flow (32K⭐), mux (1.6K⭐), claude-squad (7K⭐), emdash (YC W26) — all Claude-first. Ruflo (31K⭐) added Codex last month but is still Anthropic-primary.

This is a problem people don't take seriously until it bites them.

## The outage nobody plans for

Anthropic's public status page logged 12 incidents affecting Claude Code in the first 20 days of April 2026 alone:

- **Apr 15** — elevated errors across Claude.ai, API, and Claude Code (covered by [CNBC](https://www.cnbc.com/2026/04/15/anthropic-outage-elevated-errors-claude-chatbot-code-api.html), [Mashable](https://mashable.com/article/anthropic-claude-outage-april-15))
- **Apr 13** — Claude.ai down
- **Apr 20** — Sonnet 4.5 error spike + Opus 4.6 elevated errors (two incidents, same day)
- **Mar 2** — widespread disruption ([TechCrunch](https://techcrunch.com/2026/03/02/anthropics-claude-reports-widespread-outage/))
- **Feb 25** — partial outage ([Forbes](https://www.forbes.com/sites/tylerroush/2026/02/25/claude-outage-thousands-report-issues-with-anthropics-ai-chatbot/))

Full list: [status.claude.com/history](https://status.claude.com/history). I'm not picking on Anthropic — OpenAI and Google have similar ledgers.

The question isn't "does my vendor go down?" It's "what happens to my workflow when they do?" For every orchestrator above, the answer is: **it halts.** No failover primitive. No way to re-route to a different vendor's CLI without editing config and restarting.

## The proxy non-solution

The popular response is to put a proxy in front: claude-code-router (32.5K⭐), LiteLLM, Helicone. The pitch is "switch backends without changing your code." The reality:

- **Proxies translate at the API level, not the CLI level.** Claude Code emits `stream-json` with Anthropic-specific tool-call schemas. Gemini CLI emits its own format. Codex emits a third. A proxy can swap the model behind the call, but your orchestration layer is still parsing Claude-shaped output. When Anthropic changes the wire format, the proxy breaks and so does everything downstream.
- **Proxies add a single point of failure.** You traded "Anthropic might go down" for "Anthropic or my proxy might go down."
- **Proxies re-create the CLI on top of the model API.** The whole point of using Claude Code is the tool execution, workspace management, prompt caching, and auth handling it ships. A proxy strips all of that back to the bare model API.

The proxy approach optimizes for the wrong layer. The thing you want to swap is the **agent CLI**, not the model behind it.

## Portable orchestration, done right

Accept that each vendor's CLI is its own runtime with its own idioms, and build an orchestration layer that speaks all of them natively. Sage has 8 runtime adapters: `claude-code`, `gemini-cli`, `codex`, `cline`, `kiro`, `ollama`, `llama-cpp`, `acp`, `bash`. Each is one file with two functions (`runtime_start` + `runtime_inject`). Total: ~600 lines of bash across all 8.

This buys three properties a proxy can't:

1. **Vendor-specific features stay available** — prompt caching on Claude Code, grounding on Gemini, auto-approve on Codex. Real CLI, real features.
2. **Auth stays native** — Bedrock for Claude Code, Google OAuth for Gemini, LiteLLM config for Codex. The vendor CLI handles it.
3. **Failover is a flag, not an architecture.**

```bash
sage send reviewer-primary "Review src/main.py" \
  --fallback reviewer-gemini \
  --fallback reviewer-local
# ⚠  primary 'reviewer-primary' runtime unreachable → failing over to 'reviewer-local'
# ✓  task t-1776985392-26333 → reviewer-local
```

Pre-flight health check. If the primary's binary is unreachable or the daemon isn't responding, the next fallback runs. No config change. No restart.

## The benchmark that only portable orchestration can run

If different vendor CLIs are different runtimes, a question becomes answerable: **which is actually better for my workload?**

No benchmark article can answer this for you. Vendor blogs test on MMLU. Independent comparisons test model quality, not the agent-plus-CLI stack. Nobody tests the stack *you* run — because nobody else drives all the CLIs from one command surface.

With portable orchestration:

```bash
sage bench run ./my-tasks --agents claude-agent,gemini-agent,codex-agent,ollama-agent
sage bench report --format markdown
```

Dogfooding on the sage repo itself — 5 tasks × 3 agents, CPU-only box:

| Agent | Success rate | Median wall |
|---|---|---|
| Claude Code | 60% | 46,268 ms |
| llama3.2:3b (local) | 100% | 2,577 ms |
| echo baseline | 0% | 2,057 ms |

Surprise: for trivial orchestration tasks, a small local model on CPU beats a full coding agent CLI. Not because it's smarter — it isn't. The coding agent's scaffolding cost dominates wall-time when the actual work is 2 lines. Claude Code spends 40 seconds reading files and making tool calls before it answers "7 × 8 = 56."

Not a dunk. For real coding it almost certainly wins. But you can't know which is which for *your* workload without running both. Full methodology + caveats: [use-case-bench.md](../use-case-bench.md).

## The costs

Vendor-neutrality isn't free:

- Every adapter is a maintenance burden. Claude Code changed its output format twice this year; we absorbed it so users didn't.
- Feature fragmentation. Prompt caching works on claude-code but not codex. We normalize where we can, document where we can't.
- Bigger test surface. Sage has 928 bats tests, CI matrix on ubuntu + macOS, because every primitive must work across 8 runtimes.

These costs are paid once by the orchestration layer, not N times by every user. In exchange: **the workflow outlives the vendor.**

## When lock-in is fine

If your team standardized on Claude Code, you trust Anthropic's uptime, and you're not benchmark-curious — claude-flow is a fine choice. Well-built, 32K stars for a reason.

But the moment one of those assumptions weakens — a price change, a model deprecation, an EU compliance requirement, a teammate who prefers Codex — you're stuck. Locked-in orchestration is only as good as the vendor relationship.

Portable orchestration is yours.

## Try it

One bash script. Deps: bash, jq, tmux. Install in under 10 seconds:

```bash
brew tap youwangd/sage && brew install sage
# or
curl -fsSL https://raw.githubusercontent.com/youwangd/SageCLI/main/install.sh | bash
```

[github.com/youwangd/SageCLI](https://github.com/youwangd/SageCLI) — README, kill-switch demo, full bench methodology. Pushback welcome in the issues.
