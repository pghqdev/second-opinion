---
name: second-opinion
description: Use this skill to get an adversarial second opinion on a plan or brainstorm from a different AI model (Codex/GPT-5, Gemini, or another installed CLI) before committing to a risky implementation. Use whenever the user requests a "second opinion", "sanity check", or "another model's view"; whenever a PreToolUse hook blocks ExitPlanMode with a second-opinion-required message; whenever a plan touches migrations, auth, billing, infrastructure, production data, destructive operations, or >3 files; or whenever the user expresses genuine uncertainty about which approach to pick. This skill MUST be executed inside a general-purpose subagent — never run it directly from the main session, because the reviewer's output is large and would pollute the main context.
---

# second-opinion

Get an adversarial critique of a plan from a different AI model and return a compact structured verdict.

## CRITICAL: subagent-only

If you are reading this from the main session (not a subagent), **stop immediately**. Dispatch this skill via the `Agent` / subagent tool of your host, passing the plan text in the prompt. Rationale: the reviewer returns 5–20k tokens of reasoning; running it inline wastes the main context on output you will summarize anyway.

Quick self-check: if you can see earlier messages in this conversation that are not about this specific critique task, you are in the main session. Re-dispatch and stop.

## Inputs you receive as a subagent

Your dispatcher will give you:
- The plan text (required).
- Optionally, a `transcript_path` to the session JSONL for extra context.
- Optionally, a `cwd` / `project_dir` for repo context.

## What to do

1. **Write the plan to a tempfile:**
   ```bash
   PLAN_FILE=$(mktemp -t second-opinion-plan.XXXXXX.md)
   cat > "$PLAN_FILE" <<'PLAN_EOF'
   <plan text here>
   PLAN_EOF
   ```

2. **Run the reviewer dispatcher:**
   ```bash
   ~/.claude/skills/second-opinion/scripts/run_reviewer.sh "$PLAN_FILE"
   ```
   The dispatcher tries external AI CLIs in preference order (codex → gemini → opencode → claude), excluding the current host to maintain model-family diversity. It prepends the adversarial prompt template and (for non-codex providers) the JSON schema. On success: JSON verdict on stdout, `PROVIDER=<name>` on stderr. On failure (exit 10): no external reviewer is available — proceed to step 3.

3. **Fallback: in-subagent self-review (only if run_reviewer exits 10).**
   Load `references/self_review_prompt.md`, read it carefully, then apply its instructions to the plan yourself. Emit a single JSON object matching `assets/response_schema.json`. This is the *same model family as the host*, so it's a weaker second opinion — a structured adversarial self-critique, not a true external review. **Surface that caveat to the user.**

4. **Parse the JSON response.** Fields: `fatal_flaws[]`, `hidden_assumptions[]`, `simpler_alternative` (string or null), `points_of_agreement[]`, `verdict` (`SHIP` / `REVISE` / `RECONSIDER`), `verdict_reason` (one line).

5. **Tell the dispatcher how to retry ExitPlanMode.** The PreToolUse hook (if wired) keeps denying the same plan unless a sentinel is present. Include this line verbatim in your returned summary:

   > "After sharing this verdict with the user, append `<!-- second-opinion: reviewed -->` to the plan file before retrying ExitPlanMode."

6. **Return a compact markdown summary** to the dispatcher:
   ```
   **Verdict: <SHIP|REVISE|RECONSIDER>** (reviewer: <provider or "self-review (same model family)">)
   <verdict_reason>

   **Agrees on:**
   - <point_of_agreement>

   **Concerns:**
   - <fatal_flaw or assumption>

   **Suggested alternative:** <simpler_alternative or "none">
   ```
   Under ~250 words. Do not include the reviewer's raw reasoning or chain-of-thought.

## Why this design

- **Subagent isolation** keeps the reviewer's reasoning tokens out of the main context.
- **Provider chain with host exclusion** preserves model-family diversity: the whole point of a second opinion is to get a view from a different training lineage. If the host is Claude Code, calling `claude` again is a same-lineage review and adds little value — so the dispatcher skips it by default.
- **Adversarial framing** (`references/prompt_template.md`) counteracts LLM sycophancy — models default to validating plans unless explicitly instructed to attack them.
- **Structured JSON output** makes the critique parseable and forces the reviewer to separately commit to agreement *and* disagreement — so we surface both honestly.
- **Self-review fallback** is better than nothing when no external CLI is present. A fresh-context, adversarially-framed re-read of the plan catches real problems a cooperative author misses, even from the same model.

## Manual invocation

Users can invoke this skill explicitly without the hook (e.g., "give me a second opinion on this approach"). Same flow — plan text comes from the user's prompt instead of the hook payload.
