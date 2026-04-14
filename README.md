# second-opinion

A Claude Code skill + hook that gets an **adversarial second opinion** on your plan from a different AI model — Codex (GPT-5), Gemini, or another installed CLI — before you commit to a risky implementation.

When you exit plan mode on something that touches migrations, auth, billing, infra, production data, destructive operations, or more than a handful of files, a `PreToolUse` hook intercepts the call and forces a review pass from a fresh model in a different lineage. If no external reviewer CLI is available, it falls back to a structured adversarial self-review.

Because second opinions catch the mistakes your own model family is most prone to miss.

## Install

### One-liner (Claude Code, opencode, or any tool reading `~/.claude/skills/`)

```bash
curl -fsSL https://raw.githubusercontent.com/pghqdev/second-opinion/main/install.sh | bash
```

This copies the skill to `~/.claude/skills/second-opinion/` and — if `jq` is available — wires the `PreToolUse:ExitPlanMode` hook into `~/.claude/settings.json`.

### As a Claude Code plugin

```
/plugin marketplace add pghqdev/second-opinion
/plugin install second-opinion
```

The plugin manifest at `.claude-plugin/plugin.json` and hooks at `hooks/hooks.json` are declared relative to `${CLAUDE_PLUGIN_ROOT}`, so no path setup is needed.

### Environment overrides

| Env var | Default | Purpose |
|---|---|---|
| `SECOND_OPINION_REF` | `main` | branch/tag/sha to install |
| `SECOND_OPINION_SKIP_HOOK` | unset | if `1`, skips settings.json mutation |
| `SECOND_OPINION_PREFIX` | `$HOME/.claude` | install root |

## How it works

1. **Hook** (`scripts/detect_triggers.sh`) runs on every `ExitPlanMode`. It reads the plan text from stdin, scans for destructive keywords, high-risk domains (auth/billing/migration/prod/etc.), and file-path count. If any trigger fires, it returns a `deny` decision asking Claude to dispatch the `second-opinion` skill first.
2. **Skill** (`SKILL.md`) runs as a subagent so the reviewer's 5–20k reasoning tokens stay out of the main context. It dispatches to `scripts/run_reviewer.sh`.
3. **Dispatcher** (`run_reviewer.sh`) tries external CLIs in order — `codex`, `gemini`, `opencode`, `claude` — skipping whichever one is the current host (via `CLAUDE_CODE_ENTRYPOINT` etc.) to preserve model-family diversity. Only `codex` uses the strict `--output-schema`; others get the schema inlined into the prompt.
4. **Fallback** (`references/self_review_prompt.md`) — if no external CLI is available, the subagent does a fresh-context adversarial self-review using its own model. Weaker, but still catches real problems.
5. **Return path.** The skill returns a compact verdict (`SHIP` / `REVISE` / `RECONSIDER`) plus what the reviewer agreed and disagreed on. To retry `ExitPlanMode` after review, append `<!-- second-opinion: reviewed -->` to the plan.

### Bypass & escape hatches

- **Skip a single review:** include `<!-- skip second opinion -->` anywhere in the plan text.
- **Disable globally:** delete the `PreToolUse:ExitPlanMode` entry from `~/.claude/settings.json`, or run the installer with `SECOND_OPINION_SKIP_HOOK=1`.
- **Manual invocation anytime:** ask for a "second opinion" — the skill works without the hook.

## Requirements

- bash, curl (or git/wget), tar
- **Optional but recommended:** `jq` — enables auto-hook-wiring during install and is used by the hook script to parse its stdin payload. Without it, the gate falls open with a visible warning.
- **At least one reviewer CLI** for best results: [`codex`](https://github.com/openai/codex), [`gemini-cli`](https://github.com/google-gemini/gemini-cli), [`opencode`](https://opencode.ai), or another `claude` installation (used only if not the host). Without any, the skill does self-review.

## Why adversarial framing

Models default to validating the plans they're shown. The prompt template explicitly instructs the reviewer to find what's wrong, not to agree, and to cite concrete steps. The JSON schema forces separate commitments to agreement *and* disagreement — so genuine concurrence is signal, not reflex praise.

## License

MIT. See `LICENSE`.
