# r/LocalLLaMA post — Sage + Ollama orchestration

**Status**: DRAFT — ready to post
**Subreddit**: r/LocalLLaMA
**Type**: self-post (Show)
**Hook**: ride the qwen3.6-35b+OpenCode viral thread from this week

---

## Title options (pick one before posting)

1. **I built a pure-bash agent orchestrator that runs multiple local LLMs in parallel — no Python, no Node, no framework**
2. **Parallel multi-agent workflows with Ollama, in ~6000 lines of bash. Benchmarks inside.**
3. **Sage: fan out 3 local LLMs on CPU-only box in 34s. Pure bash.**

My pick: **#2** (number in title + "benchmarks inside" → upvote-bait that's actually honest)

---

## Post body

I've been working on **Sage** ([github.com/youwangd/SageCLI](https://github.com/youwangd/SageCLI)) — an AI agent orchestrator written in pure bash. No Python runtime, no Node server, no SaaS. Just bash, `jq`, and `tmux`. It can drive Claude Code, Codex, Gemini CLI, OpenCode, **and Ollama** from the same command surface.

I kept seeing the qwen3.6-35b + OpenCode threads here and thought: *"OK, but what if I want to run three local models in parallel and merge their outputs?"* Sage does that. Here's a real run on a **CPU-only** box (16-core Xeon, 62GB RAM, no GPU) using `llama3.2:3b`:

```bash
$ sage create local-writer --runtime ollama --model llama3.2:3b
$ sage create local-critic --runtime ollama --model llama3.2:3b
$ sage create local-editor --runtime ollama --model llama3.2:3b

$ sage send local-writer "Summarize in ONE sentence: why local LLMs matter."
$ sage send local-critic "List 3 limitations of local LLMs."
$ sage send local-editor "Recommend hardware for local LLMs. ONE sentence."

$ # ... 34 seconds later, all three done
$ sage result t-1776971675-20386
$ sage result t-1776971675-21366
$ sage result t-1776971675-27280
```

### Actual numbers from my box

| Metric | Value |
|---|---|
| Model | `llama3.2:3b` (Q4, ~2GB) |
| Hardware | 16-core Xeon, 62GB RAM, **no GPU** |
| Raw ollama throughput | **13.81 tok/s** generation, 23.67 tok/s prompt eval |
| 3 parallel `sage` agents end-to-end | **34 seconds** |
| ollama CPU peak | 75% (single-process, serializes internally) |
| Resident memory (1 model loaded) | ~2.4 GB |
| Sage framework overhead | ~500 KB bash, 0 deps beyond `jq`+`tmux` |

### What "parallel" actually means here

Honest caveat: ollama's default build serializes generation requests through one model instance. So three agents running against one ollama server = 3x sequential inference under the hood. The **orchestration** is parallel (agents are independent, fan out/collect works, would scale on a multi-GPU box), but the **inference** is serialized until you run multiple ollama instances or use a batching backend.

If you point each agent at a different model (e.g. writer→llama3.2:3b, critic→qwen3:8b, editor→phi-4) you get different model families in one plan, but still serialized if one ollama server. Multi-GPU or `NUM_PARALLEL=3` on ollama server unlocks real parallelism.

### Why bash?

Short version: I wanted zero cold-start, zero dependency drift, and zero "which Python env did I install this in". Every competitor in this space (claude-flow, gastown, emdash, mux) requires Node/Rust/Go/Python. Sage boots in <50ms and has one executable.

Long version: coordinating 8+ different agent CLIs (Claude Code, Codex, Gemini, OpenCode, Aider, Ollama, llama.cpp, bash) is mostly glue — spawning subprocesses, managing tmux sessions, passing JSON through pipes. Bash is genuinely good at that. The parts that would be painful in bash (JSON manipulation, async waits) I do with `jq` and file-based signaling.

### What's in it

- 8 runtimes (Claude Code, Codex, Gemini CLI, OpenCode, Cline, Kiro, **Ollama**, llama.cpp, bash)
- `sage plan` — YAML-defined multi-agent workflows with dependency waves
- `sage plan --pattern fan-out/pipeline/debate/map-reduce` — named swarm patterns
- `sage dashboard` — live TUI of all running agents
- MCP server support, skills registry, git worktree isolation per agent, persistent sessions, cost tracking
- Agent chaining: `sage send A "task" --then B --then C`
- 465 bats tests, CI on every push

### Gotcha I hit while making this post

`qwen3:0.6b` pulled 11 days ago → `Error: 400 Bad Request: does not support generate` with ollama v0.18.2. The model template is stale. Re-pull fixes it but that's a 600MB+ re-download. Small-model quirk, not a sage issue, but worth noting if you hit it.

Also: `llama3.2:3b` hallucinates the agent framework's syntax into its answers (outputs like `sage send mytask "..."`). That's the model echoing its own system prompt. 8B+ models stop doing this. Trim your system prompt aggressively for small models.

### Links

- Repo: [github.com/youwangd/SageCLI](https://github.com/youwangd/SageCLI)
- 37-second demo (asciinema): [docs/demo.gif](https://github.com/youwangd/SageCLI/blob/main/docs/demo.gif)
- Architecture diagram: [docs/diagrams/architecture.svg](https://github.com/youwangd/SageCLI/blob/main/docs/diagrams/architecture.svg)

Happy to answer questions or benchmark different model combos if people post specs.

---

## Pre-post checklist

- [ ] Verify GitHub repo is public (youwangd/SageCLI)
- [ ] Re-check README renders the architecture.svg correctly on github.com
- [ ] Drop the 34s benchmark into README.md as a callout
- [ ] Test `sage create ... --runtime ollama --model llama3.2:3b` fresh once more the morning of posting to make sure nothing broke
- [ ] Post timing: weekday morning 08:00–11:00 US Pacific (r/LocalLLaMA peak)
- [ ] No flair needed (Show-style self-post)
- [ ] Reply engagement strategy: first 30 min is make-or-break. Be online.

## What I'm NOT promising in the post

- "as good as Claude" (we're orchestrating local models, not claiming the models are good)
- any tok/s numbers for qwen3.6-35b (didn't actually run it, would be <1 tok/s on this CPU box)
- GPU benchmarks (don't have one)
- Production-readiness claims (2 stars, 465 tests, not v1.0 battle-tested)

## Expected pushback and pre-canned replies

**"Why not use OpenCode?"** → OpenCode is one agent. Sage runs multiple agents with different backends (or the same backend) and merges their output. Complementary, not competing — sage has an OpenCode runtime.

**"Bash doesn't scale"** → Correct, and I agree. It scales fine to ~100 agents on one box, which is where the "one developer orchestrating work" use case tops out. Beyond that you want something else.

**"This is just tmux + ollama"** → Yes, partly. The value is the `plan`/`send --then`/`msg`/`context`/`mcp` surface on top of that, plus the 465 tests that make sure it doesn't regress.

**"Show me a hard use case"** → PR review pipeline: `sage plan --pattern fan-out "Review PR #123"` spawns reviewer + security-auditor + test-writer in parallel, merges their findings. Works with any mix of local and cloud models.
