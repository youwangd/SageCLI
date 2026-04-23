# Sage — Positioning

Single source of truth for *what sage is* and *what it isn't*. Use this to decide
whether to accept a feature request, approve a roadmap item, or frame a blog post.

## One-sentence pitch

> **Sage is the Unix-native control plane for agent CLIs.**
> You already have Claude Code, Codex, and Gemini CLI installed.
> Sage lets them work together — or swap between them — without writing Python.

## What sage IS

1. **Vendor-neutral** — the only orchestrator where `claude-code + codex + gemini-cli + ollama`
   work from one command surface, with identical semantics, today.
2. **Zero-dependency** — one bash script. `curl | bash`. No `venv`, no `nvm`, no `pnpm`.
   Works on any Linux/macOS, including CI runners, airgapped boxes, and ephemeral containers.
3. **Unix-native** — JSON out, stdin in, everything pipes. Behaves like `kubectl` / `git` / `jq`,
   not like a chat UI.
4. **A compatibility layer** — when Anthropic changes Claude Code's flags, when Google deprecates
   a Gemini option, when Codex restructures auth — the user's `sage plan` YAML keeps working.
   The 8 runtime shims are the moat.
5. **Protocol-agnostic** — ships MCP client, ACP client. If the industry standardizes on either,
   sage is already there. If on something else, a new runtime shim is one file.

## What sage is NOT

1. **Not a coding assistant.** We don't write code. We don't have a model. We don't compete
   with Claude Code / Aider / Cline on code quality.
2. **Not a parallel inference router.** Ollama + vLLM do this natively with GPU awareness
   we don't have. Our "parallel" means orchestration-parallel (independent agents with independent
   contexts), not inference-parallel (batched GPU tensor ops).
3. **Not a Claude wrapper.** claude-flow / ruflo / emdash / mux all optimize for Claude.
   Sage intentionally does not prefer any backend.
4. **Not a web dashboard / SaaS.** No server to host, no account to create, no telemetry.
5. **Not a framework.** You don't import sage. You invoke it. It doesn't own your code.

## The three competitive moats (in priority order)

1. **Neutrality** → rebuts claude-flow, ruflo, mux, emdash (all Claude-centric)
2. **Zero-dependency posture** → rebuts every Node/Python/Rust orchestrator
3. **Unix-citizen behavior** → rebuts web dashboards, TUIs-as-primary-interface, SaaS

Every feature decision should strengthen at least one of these three.

## Target users

- **Platform engineers** at companies supporting multiple AI tools for compliance/procurement
- **CI/CD authors** needing agent workflows in GitHub Actions without heavyweight deps
- **Multi-vendor enterprises** that can't bet the farm on one AI provider
- **Power users** who want the `kubectl` of AI agents, not another chat UI

## Decision rubric

Before shipping a new feature, ask:

1. Does it strengthen neutrality, zero-dependency posture, or Unix-citizen behavior?
2. Would a coding-assistant vendor (Claude Code, Aider, Cline) ever ship this feature?
   If yes → **it's in their lane, not ours.**
3. Does it bolt sage to a specific vendor / runtime? If yes → **refuse.**
4. Does it add a non-bash runtime dependency? If yes → **refuse or isolate behind an optional feature flag.**

## What we STOP doing

- **Stop adding runtimes for the sake of it.** 8 is enough. Each new runtime is maintenance debt
  against a moving target. Invest in making the existing 8 more robust (failure modes, version
  pinning, auth refresh, structured output stability).
- **Stop competing on inference.** ollama + vLLM do inference parallelism better.
- **Stop drifting toward coding-workflow features.** "Sage plans a PR review" → Claude Code's job.
  "Sage lets Claude + Gemini + Codex cooperate on a PR review" → our job.
- **Stop leading with feature lists.** Lead with the one-sentence pitch and the three moats.

## What we START doing

1. **Kitchen-sink interop matrix** — publicly prove neutrality with a CI job that runs the same
   `sage plan` YAML across all 8 runtimes and publishes the output diff.
2. **Vendor-kill-switch narrative** — sage is the insurance policy when your primary agent
   goes down. Write this up.
3. **Blog posts that exploit the moats** (already queued in roadmap):
   - "Native runtimes beat proxies" (vs claude-code-router 32.5K ⭐)
   - "Portable orchestration beats locked-in orchestration" (vs claude-flow 32.4K ⭐)
4. **Target the buyer, not just the reader.** Platform engineers searching for
   *"multi-vendor AI CLI orchestrator"* should find sage first.

## Anti-goals (projects we're NOT)

- ❌ A chat UI
- ❌ A Claude Code wrapper
- ❌ An IDE plugin
- ❌ A hosted service
- ❌ A multi-LLM proxy (that's claude-code-router)
- ❌ A model router (that's ollama + vLLM)
- ❌ An agent framework (that's LangGraph / AutoGen / CrewAI)

---

*Last reviewed: 2026-04-23. If you're about to ship something that contradicts this doc,
update the doc first and note why.*
