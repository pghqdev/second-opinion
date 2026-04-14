#!/usr/bin/env bash
# install.sh — installer for the `second-opinion` skill.
#
# Works for:
#   - Claude Code (wires the PreToolUse hook automatically)
#   - Any other AI CLI that reads skills from ~/.claude/skills (opencode, etc.)
#   - Manual use by a subagent (the files just sit at ~/.claude/skills/second-opinion)
#
# Supported OSes: macOS, Linux. Requires: bash, curl OR git, and optionally jq
# (jq is only required for the auto-hook-wiring step in Claude Code; the skill
# itself fails open without jq and prints a warning).
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/pghqdev/second-opinion/main/install.sh | bash
#
# Flags (via env vars):
#   SECOND_OPINION_REF=main     # branch/tag/sha to install
#   SECOND_OPINION_SKIP_HOOK=1  # don't modify ~/.claude/settings.json
#   SECOND_OPINION_PREFIX=...   # override install root (default: $HOME/.claude)

set -euo pipefail

REF="${SECOND_OPINION_REF:-main}"
PREFIX="${SECOND_OPINION_PREFIX:-$HOME/.claude}"
SKILL_DIR="$PREFIX/skills/second-opinion"
SETTINGS="$PREFIX/settings.json"
REPO_URL="https://github.com/pghqdev/second-opinion"
TARBALL_URL="https://codeload.github.com/pghqdev/second-opinion/tar.gz/refs/heads/$REF"

log() { printf '[second-opinion] %s\n' "$*"; }
die() { printf '[second-opinion] ERROR: %s\n' "$*" >&2; exit 1; }

# --- platform checks ------------------------------------------------------
case "$(uname -s)" in
  Darwin|Linux) : ;;
  *) die "unsupported OS: $(uname -s). Install manually from $REPO_URL" ;;
esac

command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || command -v git >/dev/null 2>&1 \
  || die "need curl, wget, or git to fetch the skill"
command -v tar >/dev/null 2>&1 || die "need tar to extract the skill"

# --- fetch & extract ------------------------------------------------------
TMP=$(mktemp -d -t second-opinion-install.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

log "fetching $REF from $REPO_URL"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$TARBALL_URL" -o "$TMP/src.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -q "$TARBALL_URL" -O "$TMP/src.tar.gz"
else
  git clone --depth 1 --branch "$REF" "$REPO_URL.git" "$TMP/src" >/dev/null 2>&1
fi

if [ -f "$TMP/src.tar.gz" ]; then
  tar -xzf "$TMP/src.tar.gz" -C "$TMP"
  SRC=$(find "$TMP" -maxdepth 1 -type d -name "second-opinion-*" | head -1)
else
  SRC="$TMP/src"
fi
[ -n "$SRC" ] && [ -d "$SRC/skills/second-opinion" ] || die "could not locate skill files in extracted archive"

# --- install skill files --------------------------------------------------
log "installing skill to $SKILL_DIR"
mkdir -p "$(dirname "$SKILL_DIR")"
rm -rf "$SKILL_DIR"
cp -R "$SRC/skills/second-opinion" "$SKILL_DIR"
chmod +x "$SKILL_DIR/scripts/"*.sh

# --- wire Claude Code hook (optional) -------------------------------------
if [ "${SECOND_OPINION_SKIP_HOOK:-0}" = "1" ]; then
  log "SECOND_OPINION_SKIP_HOOK=1 set; skipping hook registration"
elif [ ! -d "$PREFIX" ]; then
  log "no Claude directory at $PREFIX; skipping hook registration"
elif ! command -v jq >/dev/null 2>&1; then
  log "jq not installed; skipping hook registration (run install.sh again after 'brew install jq' or 'apt install jq' to enable auto-gate)"
else
  mkdir -p "$PREFIX"
  if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
  fi
  HOOK_CMD="$SKILL_DIR/scripts/detect_triggers.sh"
  # Idempotently add/replace the PreToolUse:ExitPlanMode hook entry.
  NEW=$(jq --arg cmd "$HOOK_CMD" '
    .hooks //= {}
    | .hooks.PreToolUse //= []
    | .hooks.PreToolUse |= (
        (map(select(.matcher != "ExitPlanMode" or (.hooks // []) | all(.command != $cmd))))
        + [{"matcher":"ExitPlanMode","hooks":[{"type":"command","command":$cmd}]}]
      )
    | .hooks.PreToolUse |= unique_by(.matcher)
  ' "$SETTINGS")
  printf '%s\n' "$NEW" > "$SETTINGS"
  log "wired PreToolUse:ExitPlanMode hook in $SETTINGS"
fi

# --- verify dependencies on PATH ------------------------------------------
log "installed."
log "Reviewer CLIs detected:"
for cli in codex gemini opencode claude; do
  if command -v "$cli" >/dev/null 2>&1; then
    log "  ✓ $cli ($(command -v $cli))"
  else
    log "  ✗ $cli (not installed)"
  fi
done

cat <<EOF

Next steps:
  • In Claude Code: restart the session (or run \`/hooks reload\` if available).
  • To bypass the gate on a specific plan: include \`<!-- skip second opinion -->\`.
  • To uninstall: rm -rf $SKILL_DIR and remove the hook entry from $SETTINGS.

Docs: $REPO_URL
EOF
