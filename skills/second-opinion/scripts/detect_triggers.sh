#!/bin/bash
# detect_triggers.sh — PreToolUse hook for ExitPlanMode.
#
# Reads the hook JSON payload from stdin, extracts the plan text, and decides
# whether to block ExitPlanMode and demand a second opinion from Codex.
#
# Trigger rules (any match blocks):
#   1. Destructive / irreversible keywords anywhere in the plan.
#   2. High-risk domain keywords (auth, billing, migration, production, etc.).
#   3. Plan lists >3 file paths to modify (heuristic: count of `.ext` tokens in
#      inline code spans).
#
# On block, emits JSON to stdout telling Claude to invoke the second-opinion
# skill via the Agent tool before retrying ExitPlanMode. On no block, exits
# silently so plan mode exits normally.

set -u

PAYLOAD=$(cat)

# Require jq. If absent, fail open (don't block work on missing dep) but
# surface a warning so the user knows the safety net is off.
if ! command -v jq >/dev/null 2>&1; then
  echo "second-opinion hook: jq not found on PATH; skipping gate (install jq to enable)." >&2
  exit 0
fi

TOOL_NAME=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "ExitPlanMode" ]; then
  exit 0
fi

PLAN=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.plan // empty')
if [ -z "$PLAN" ]; then
  exit 0
fi

# Loop-break: if the plan carries the "already reviewed" sentinel, the
# subagent has already run and Claude has appended it before retrying.
# Pass through to avoid an infinite deny→retry→deny cycle.
if printf '%s' "$PLAN" | grep -qF -- '<!-- second-opinion: reviewed -->'; then
  exit 0
fi

# Hard bypass (HTML-comment form to avoid accidental substring matches in
# natural plan text or quoted references to this skill).
if printf '%s' "$PLAN" | grep -qF -- '<!-- skip second opinion -->'; then
  exit 0
fi

# Lowercased copy for case-insensitive keyword checks.
PLAN_LC=$(printf '%s' "$PLAN" | tr '[:upper:]' '[:lower:]')

TRIGGERED=0
REASONS=()

# Destructive / irreversible.
for kw in \
  "drop table" \
  "drop column" \
  "delete from" \
  "truncate " \
  "rm -rf" \
  "force-push" \
  "force push" \
  "git push --force" \
  "--no-verify" \
  "reset --hard"
do
  if printf '%s' "$PLAN_LC" | grep -qF -- "$kw"; then
    TRIGGERED=1
    REASONS+=("destructive keyword: \"$kw\"")
  fi
done

# High-risk domains.
for kw in \
  "migration" \
  "schema change" \
  "production " \
  "prod deploy" \
  " auth" \
  "authentication" \
  "billing" \
  "payment" \
  "stripe" \
  "oauth" \
  "secret" \
  "credential"
do
  if printf '%s' "$PLAN_LC" | grep -qF -- "$kw"; then
    TRIGGERED=1
    REASONS+=("high-risk domain: \"${kw# }\"")
  fi
done

# File-count heuristic: count distinct `word.ext` tokens inside backticks.
# Extensions we treat as "code files" — tuned for signal, not recall.
FILE_COUNT=$(printf '%s' "$PLAN" \
  | grep -oE '`[^`]*\.(ts|tsx|js|jsx|py|rs|go|rb|java|kt|swift|c|cc|cpp|h|hpp|sh|sql|json|yaml|yml|toml|md)`' \
  | sort -u \
  | wc -l \
  | tr -d ' ')
if [ "${FILE_COUNT:-0}" -gt 3 ]; then
  TRIGGERED=1
  REASONS+=("plan touches $FILE_COUNT files (>3)")
fi

if [ "$TRIGGERED" -eq 0 ]; then
  exit 0
fi

# De-duplicate reasons while preserving order.
UNIQUE_REASONS=$(printf '%s\n' "${REASONS[@]}" | awk '!seen[$0]++' | paste -sd ';' - | sed 's/;/; /g')

REASON_MSG="Second opinion required before exiting plan mode. Triggers: ${UNIQUE_REASONS}.

Do not retry ExitPlanMode yet. Instead:
1. Invoke the \`second-opinion\` skill via the Agent tool (subagent_type=\"general-purpose\"), passing the full plan text in the prompt.
2. Summarize the subagent's verdict to the user.
3. If the user wants to proceed, edit the plan file to (a) incorporate any revisions, AND (b) append the literal HTML comment marker \`<!-- second-opinion: reviewed -->\` at the end. Then call ExitPlanMode again with the updated plan. The marker tells this hook the review already happened, avoiding a deny loop.

To skip the review entirely, add \`<!-- skip second opinion -->\` to the plan. Use sparingly — the gate exists because the plan touches risky surface area."

# Block the tool call. Claude sees the reason and must respond.
jq -n --arg reason "$REASON_MSG" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": $reason
  }
}'
exit 0
