#!/bin/bash
# run_reviewer.sh — dispatch the adversarial plan review to the best
# available external AI CLI, preferring a different model family than the
# host that loaded this skill.
#
# Usage: run_reviewer.sh <plan-file>
#
# Exit codes:
#   0  — success; JSON response on stdout, "PROVIDER=<name>" on stderr.
#   2  — bad invocation (missing/invalid plan file).
#   10 — no usable external reviewer CLI available. Caller should fall back
#        to in-subagent self-review (same model; weaker but still useful).
#
# Provider preference (first available that is NOT the host wins):
#   1. codex   (OpenAI GPT-5 family — strongest contrast for Anthropic/Google hosts)
#   2. gemini  (Google — contrast for Anthropic/OpenAI hosts)
#   3. opencode (multi-provider proxy)
#   4. claude  (Anthropic — only useful if host is not Claude Code)

set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SKILL_DIR/references/prompt_template.md"
SCHEMA_FILE="$SKILL_DIR/assets/response_schema.json"

if [ $# -lt 1 ] || [ ! -f "$1" ]; then
  echo "run_reviewer.sh: expected a plan file path as argument" >&2
  exit 2
fi
PLAN_FILE="$1"

# Build the adversarial prompt body (template + plan).
PROMPT_FILE=$(mktemp -t second-opinion-prompt.XXXXXX)
trap 'rm -f "$PROMPT_FILE"' EXIT
cat "$TEMPLATE" > "$PROMPT_FILE"
cat "$PLAN_FILE" >> "$PROMPT_FILE"

# For non-codex providers we also inline the JSON schema with an explicit
# "return ONLY JSON" instruction, since they don't support --output-schema.
SCHEMA_BODY=$(cat "$SCHEMA_FILE")
NON_CODEX_PROMPT=$(mktemp -t second-opinion-nc.XXXXXX)
trap 'rm -f "$PROMPT_FILE" "$NON_CODEX_PROMPT"' EXIT
{
  cat "$PROMPT_FILE"
  printf '\n\nReturn ONLY a single JSON object matching this JSON Schema. No preamble, no code fences, no trailing text.\n\nSCHEMA:\n'
  printf '%s\n' "$SCHEMA_BODY"
} > "$NON_CODEX_PROMPT"

# --- host detection -------------------------------------------------------
# Claude Code sets CLAUDE_CODE_ENTRYPOINT. Opencode typically sets OPENCODE
# or OPENCODE_* (heuristic). Gemini CLI: no stable env var known; we
# conservatively never exclude gemini. Codex: also no exclusion needed —
# codex-as-host calling codex-exec is still useful locally.
HOST=""
if [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
  HOST="claude"
elif [ -n "${OPENCODE:-}${OPENCODE_BIN:-}${OPENCODE_HOME:-}" ]; then
  HOST="opencode"
fi

# --- provider functions ---------------------------------------------------
# Each emits raw provider output to stdout on success (caller extracts JSON),
# returns non-zero on failure.

try_codex() {
  command -v codex >/dev/null 2>&1 || return 127
  local timeout_cmd=""
  if command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout 300"
  fi
  # shellcheck disable=SC2086
  $timeout_cmd codex exec \
    --skip-git-repo-check \
    --sandbox read-only \
    -c model_reasoning_effort=high \
    --output-schema "$SCHEMA_FILE" \
    - < "$PROMPT_FILE"
}

try_gemini() {
  command -v gemini >/dev/null 2>&1 || return 127
  # Gemini CLI reads a prompt via -p; pass the schema-augmented prompt.
  gemini -p "$(cat "$NON_CODEX_PROMPT")"
}

try_opencode() {
  command -v opencode >/dev/null 2>&1 || return 127
  # `opencode run` takes the message as args or stdin.
  opencode run "$(cat "$NON_CODEX_PROMPT")"
}

try_claude() {
  command -v claude >/dev/null 2>&1 || return 127
  # `claude -p` prints the response and exits. Pipe prompt via stdin.
  claude -p < "$NON_CODEX_PROMPT"
}

# --- provider chain -------------------------------------------------------
# Ordered list; skip the host to preserve model-family diversity.
PROVIDERS=(codex gemini opencode claude)

for provider in "${PROVIDERS[@]}"; do
  if [ "$provider" = "$HOST" ]; then
    continue
  fi
  if ! command -v "$provider" >/dev/null 2>&1; then
    continue
  fi
  echo "run_reviewer.sh: trying $provider" >&2
  if OUTPUT=$("try_$provider" 2>/dev/null); then
    # Sanity check: output must contain a JSON object with our required key.
    if printf '%s' "$OUTPUT" | grep -q '"verdict"'; then
      echo "PROVIDER=$provider" >&2
      printf '%s\n' "$OUTPUT"
      exit 0
    else
      echo "run_reviewer.sh: $provider returned no JSON verdict; trying next" >&2
    fi
  else
    echo "run_reviewer.sh: $provider invocation failed; trying next" >&2
  fi
done

echo "run_reviewer.sh: no external reviewer CLI produced a usable response" >&2
exit 10
