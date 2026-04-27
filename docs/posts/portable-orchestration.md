# Portable orchestration beats locked-in orchestration

*2026-04-27*

Most of the popular "multi-agent" tools for AI coding CLIs are locked to a single vendor. Claude-flow (32K⭐) is Claude-only. Ruflo (31K⭐) started Claude-only, added Codex last month. Mux (1.6K⭐), claude-squad (7K⭐), emdash (YC W26, 3.8K⭐) — all Claude-first, Claude-exclusive, or Claude-primary-with-token-workarounds.

This is a problem people don't take seriously until it bites them. This post is about why vendor-neutrality is a structural property worth building for, why proxy solutions aren't the same thing, and what it looks like when you treat portability as a first-class design constraint instead of a nice-to-have.

## The outage nobody plans for

On 2026-02-26, Anthropic had a 3-hour degradation window. Requests to `claude-3-5-sonnet` returned 529s intermittently. If your entire PR review pipeline ran on Claude Code — which is the only runtime claude-flow supports — you sat on your hands for 3 hours.

This wasn't a one-off. Anthropic had similar windows on 2026-03-14 (billing-side outage, 40 min), 2026-01-09 (capacity exhaustion, 2h), and 2025-11-21 (a full model endpoint unavailable for 6 hours). I'm not picking on Anthropic — OpenAI, Google, and every other vendor have their own list.

The question isn't "does my vendor go down?" It's "what happens to my workflow when they do?"

For every orchestrator I named above, the answer is: **it halts.** There is no failover primitive. There is no way to re-route a task to a different vendor's CLI without editing config and restarting.

## The proxy non-solution

The popular response is to put a proxy in front: claude-code-router (32.5K⭐), LiteLLM, Helicone, etc. The pitch is "switch backends without changing your code." The reality is different:

**Proxies translate at the API level, not the CLI level.** Claude Code's CLI emits `stream-json` events with tool-call structures specific to Anthropic's schema. Gemini CLI emits its own JSON format. Codex emits a third. A proxy can translate the underlying model API, but your orchestration layer is still parsing Claude-shaped output and sending Claude-shaped inputs. When Anthropic changes the wire format (they have, twice this year), the proxy breaks and so does everything downstream of it.

**Proxies add a single point of failure.** You traded "Anthropic might go down" for "Anthropic or my proxy might go down." Most proxies are running on someone's hobby Heroku dyno. This is not robust failover; it's one more thing that can break.

**Proxies re-create the CLI on top of the model API.** The whole point of using Claude Code as an agent is that it has tool execution, workspace management, prompt caching, retry logic, and auth handling built in. A proxy strips all of that down to the model API. If you wanted raw model access, you didn't need an agent CLI in the first place.

The proxy approach optimizes for the wrong layer. The thing you want to swap is **the whole agent CLI**, not the model behind it.

## What portable orchestration actually looks like

The alternative is to accept that each vendor's CLI is its own runtime with its own idioms, and build an orchestration layer that speaks all of them natively.

Sage has 8 runtime adapters right now:

| Runtime | What it wraps | How the adapter works |
|---|---|---|
| `claude-code` | Claude Code CLI | Spawns `claude`, parses `--output-format stream-json`, forwards tool calls to tmux |
| `gemini-cli` | Gemini CLI | Spawns `gemini -p`, parses its JSON event stream |
| `codex` | Codex CLI | Spawns `codex exec --skip-git-repo-check`, parses output |
| `cline` | Cline CLI | `cline --json` for real-time events |
| `kiro` | Kiro IDE (headless) | `kiro-cli chat` |
| `ollama` | Ollama | `ollama run <model>` for local inference |
| `llama-cpp` | llama.cpp | Direct `llama-cli` against GGUF models |
| `acp` | Agent Client Protocol | JSON-RPC 2.0 over stdio — works with any ACP agent |
| `bash` | Custom shell script | Your own `handler.sh` |

Each adapter is one file with two functions: `runtime_start()` and `runtime_inject()`. Total across all 8: ~600 lines of bash.

This costs us roughly one extra file per new vendor. In exchange, we get three properties that the proxy approach can't give us:

**1. Vendor-specific features stay available.** Claude Code's prompt caching, Gemini's grounding, Codex's auto-approve mode — all accessible because we're calling the real CLI, not an API translation.

**2. Auth stays native.** Claude Code uses Bedrock credentials, Gemini uses Google OAuth, Codex uses LiteLLM config. We don't re-implement auth; the vendor CLI handles it.

**3. Failover is a flag, not an architecture.** Because the runtime is a property of each agent, swapping it is local:

```bash
sage send reviewer-primary "Review src/main.py" \
  --fallback reviewer-gemini \
  --fallback reviewer-local
# ⚠  primary 'reviewer-primary' runtime unreachable → failing over to 'reviewer-local'
# ✓  task t-1776985392-26333 → reviewer-local
```

Pre-flight health check on the primary runtime. If its binary is unreachable or the daemon isn't responding, the next fallback runs. No config change. No restart.

## The benchmark that only portable orchestration can run

If you accept that different vendor CLIs are different runtimes, a question becomes possible: **which one is actually better for my workload?**

This is a question no benchmark article can answer for you. Vendor blogs test on MMLU and their own curated suites. Independent comparisons test model quality, not the whole agent-plus-CLI stack. Nobody tests the stack that you actually run — because nobody else is driving all the CLIs from one command surface.

With portable orchestration, you can:

```bash
sage bench run ./my-actual-tasks --agents claude-agent,gemini-agent,codex-agent,ollama-agent
sage bench report --format markdown
```

Real results from dogfooding this on the sage repo itself — 5 tasks × 3 agents, on a CPU-only box:

| Agent | Success rate | Median wall-time |
|---|---|---|
| `bench-claude` (Claude Code) | 60% | 46,268 ms |
| `bench-ollama` (llama3.2:3b local) | 100% | 2,577 ms |
| `bench-echo` (null baseline) | 0% | 2,057 ms |

The surprising result: for trivial orchestration tasks, a small local model on CPU beats a full coding agent CLI. Not because the local model is smarter — it isn't — but because the coding agent's scaffolding cost dominates wall-time when the actual work is a 2-line answer. Claude Code spends 40 seconds looking around, reading files, making tool calls, before it answers "7 times 8 is 56."

This is not a dunk on Claude Code. It's exactly the right behavior for real coding tasks. But it's exactly wrong for triage-level prompts. And you can't know which is which for your workload without running both.

Full analysis with honest caveats: [docs/use-case-bench.md](../use-case-bench.md).

## Who pays the cost

Vendor-neutrality isn't free. There are real costs:

**Every adapter is a maintenance burden.** When Claude Code changes its output format — which happened twice this year — the adapter needs a fix. We absorb this cost so users don't.

**Fragmentation of features.** Prompt caching works on claude-code but not codex. Auto-approve works on codex but requires flags on gemini-cli. We normalize where we can (timeout, max-turns, streaming) and document where we can't.

**Bigger surface to test.** Sage has 928 bats tests, up from 338 a year ago, partly because every primitive has to work across all 8 runtimes. CI runs the full matrix on ubuntu and macOS.

These costs are real, but they're paid once by the orchestration layer, not N times by every user. And they bought something that single-vendor tools structurally cannot offer: **the workflow outlives the vendor.**

## When lock-in is fine

I'm not arguing nobody should use claude-flow. If you've standardized on Claude Code, your team only uses Anthropic, you trust Anthropic's uptime, and you're not benchmark-curious — claude-flow is a fine choice. It's well-built, actively maintained, and has 32K stars for a reason.

But the moment any of those assumptions weaken — a Claude Code price change, a model deprecation, a compliance requirement for an EU vendor alternative, a teammate who prefers Codex — you're stuck. Locked-in orchestration means the orchestration is only as good as the vendor relationship.

Portable orchestration means the orchestration is yours.

## Try it

Sage is one bash script. Zero dependencies beyond bash/jq/tmux. Install in under 10 seconds:

```bash
brew tap youwangd/sage && brew install sage
# or
curl -fsSL https://raw.githubusercontent.com/youwangd/SageCLI/main/install.sh | bash
```

See [github.com/youwangd/SageCLI](https://github.com/youwangd/SageCLI) for the README, the kill-switch demo, and the full bench methodology.

---

*Counter-arguments, corrections, and pushback welcome. The GitHub repo is [youwangd/SageCLI](https://github.com/youwangd/SageCLI); I'm reading the issues.*
