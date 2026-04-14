# second-opinion

> **A different model reads your plan before you ship it.**

Your AI coding agent is a confident collaborator — which is exactly the problem. It validates its own plans. It writes migrations that almost work. It approves architectures its training distribution quietly loves. A second opinion from a different lineage catches what your agent's blind spots can't see.

`second-opinion` is a Claude Code plugin (and portable skill) that intercepts risky plans before you commit and routes them through **Codex (GPT-5)**, **Gemini**, or **Opencode** for an adversarial review. If no external reviewer is available, it runs a structured fresh-context self-review instead. Either way, you get a compact verdict: `SHIP`, `REVISE`, or `RECONSIDER` — with specific agreements, concerns, and a simpler alternative if one exists.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/pghqdev/second-opinion/main/install.sh | bash
```

That's it. Restart your Claude Code session. The next time you exit plan mode on something risky, the gate fires automatically.

<details>
<summary>Install as a Claude Code plugin instead</summary>

```
/plugin marketplace add pghqdev/second-opinion
/plugin install second-opinion
```

The manifest at `.claude-plugin/plugin.json` and hooks at `hooks/hooks.json` use `${CLAUDE_PLUGIN_ROOT}` — zero path setup.

</details>

<details>
<summary>Install options</summary>

| Env var | Default | Purpose |
|---|---|---|
| `SECOND_OPINION_REF` | `main` | branch, tag, or sha to install |
| `SECOND_OPINION_SKIP_HOOK` | unset | set to `1` to skip modifying `settings.json` |
| `SECOND_OPINION_PREFIX` | `$HOME/.claude` | install root |

</details>

---

## What you see

When you exit plan mode on a plan that touches migrations, auth, billing, infra, production, destructive operations, or more than a handful of files, the hook fires and you get something like:

```
Verdict: REVISE   (reviewer: codex, gpt-5, high reasoning)

Codex agrees on:
  • Read-only sandbox + subagent isolation is the right boundary
  • Strict JSON schema is the right interface

Concerns:
  • Step 3 assumes /tmp/plan.md exists, but nothing in the plan writes it
  • --output-schema path is relative — will break when invoked from a different cwd
  • `timeout` is not on macOS by default; wrapper will error out

Suggested alternative:
  Drop the auto-trigger for v1; ship the skill as an explicit slash-command
  first and earn the hook after the happy path is proven.
```

No praise padding. No "overall this is a great plan" prelude. Just the things worth changing your mind over.

---

## How it works

```
┌────────────────────────┐
│  You exit plan mode    │
└───────────┬────────────┘
            ▼
┌────────────────────────┐     destructive ops? migration?
│  PreToolUse hook       │────▶ auth / billing / prod?
│  detect_triggers.sh    │     >3 files touched?
└───────────┬────────────┘
            │ yes → block ExitPlanMode, ask Claude to dispatch the skill
            ▼
┌────────────────────────┐
│  second-opinion skill  │     runs in a subagent so the reviewer's
│  (SKILL.md)            │     5–20k reasoning tokens never touch
└───────────┬────────────┘     your main context
            ▼
┌────────────────────────┐     codex → gemini → opencode → claude
│  run_reviewer.sh       │     (skipping whichever is the current host)
└───────────┬────────────┘
            │
            ├── external CLI available → structured JSON verdict
            │
            └── nothing installed → fresh-context adversarial self-review
                                   (same model family, flagged as weaker)
            ▼
┌────────────────────────┐
│  Compact markdown      │     append <!-- second-opinion: reviewed -->
│  summary to you        │     to the plan to retry ExitPlanMode
└────────────────────────┘
```

### Why adversarial framing matters

Language models default to validating the plans they're shown. The prompt template explicitly instructs the reviewer to *find what's wrong, not to agree* — with concrete step citations required. The JSON schema forces separate commitments to agreement **and** disagreement, so genuine concurrence is a real signal instead of reflex praise.

### Why a different model family

A model critiques plans using the same reasoning patterns it was trained on. Asking the same family for a second opinion gets you a different roll of the same die. Different-lineage reviewers catch different things — that's the whole value proposition. The dispatcher actively skips the current host to preserve this diversity.

---

## Bypass & escape hatches

- **Skip one review**: include `<!-- skip second opinion -->` anywhere in the plan.
- **Disable globally**: remove the `PreToolUse:ExitPlanMode` entry from `~/.claude/settings.json`, or reinstall with `SECOND_OPINION_SKIP_HOOK=1`.
- **Manual invocation anytime**: just ask — "get me a second opinion on this approach". The skill works without the hook.
- **Retry after review**: append `<!-- second-opinion: reviewed -->` to the plan.

---

## Requirements

- bash, curl (or wget/git), tar — macOS or Linux
- **Recommended**: `jq` — enables auto-hook-wiring and is used by the hook to parse its payload. Without it the gate falls open with a visible warning.
- **At least one reviewer CLI** for best results:
  - [`codex`](https://github.com/openai/codex) — the default, strongest contrast for Anthropic/Google hosts
  - [`gemini-cli`](https://github.com/google-gemini/gemini-cli) — Google
  - [`opencode`](https://opencode.ai) — multi-provider proxy
  - `claude` — only used when the host isn't Claude Code

With none installed, the skill does structured self-review. Weaker, but still catches real problems.

---

## Uninstall

```bash
rm -rf ~/.claude/skills/second-opinion
# then remove the PreToolUse:ExitPlanMode entry from ~/.claude/settings.json
```

---

## License

MIT. See [`LICENSE`](./LICENSE).
