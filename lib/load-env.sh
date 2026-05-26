#!/usr/bin/env bash
# load-env.sh - Shared .env and Jira secrets loading with validation warnings.
# Sources $WORK_SCRIPTS_DIR/.env and optionally $JIRA_SECRETS_ENV.
# Prints warnings to stderr for missing files or variables but never exits.
#
# After sourcing, callers can check:
#   - $OBSIDIAN_VAULT (non-empty if available)
#   - $JIRA_LOADED (true if all three Jira vars are set)
#
# Usage: source "$LIB_DIR/load-env.sh"
#   Requires WORK_SCRIPTS_DIR to be set before sourcing.

JIRA_LOADED=false

_warn() { echo "WARNING: $*" >&2; }

# Load .env
_env_file="$WORK_SCRIPTS_DIR/.env"
if [ ! -f "$_env_file" ]; then
  _warn ".env not found at $_env_file — some functionality may be limited."
  _warn "Run: cp .env.example .env  (in $(cd "$WORK_SCRIPTS_DIR" && pwd))"
else
  set -a
  # shellcheck disable=SC1090
  source "$_env_file"
  set +a

  if [ -z "${OBSIDIAN_VAULT:-}" ]; then
    _warn "OBSIDIAN_VAULT not set in .env — Obsidian integration will not work."
  fi

  if [ -z "${JIRA_SECRETS_ENV:-}" ]; then
    _warn "JIRA_SECRETS_ENV not set in .env — Jira integration will not work."
  fi
fi

# Load Jira secrets
if [ -n "${JIRA_SECRETS_ENV:-}" ]; then
  _jira_secrets="${JIRA_SECRETS_ENV/#\~/$HOME}"
  if [ ! -f "$_jira_secrets" ]; then
    _warn "Jira secrets file not found at $_jira_secrets — Jira integration will not work."
  else
    # shellcheck disable=SC1090
    source "$_jira_secrets"

    _missing_jira_vars=""
    [ -z "${JIRA_HOST:-}" ] && _missing_jira_vars="${_missing_jira_vars} JIRA_HOST"
    [ -z "${JIRA_EMAIL:-}" ] && _missing_jira_vars="${_missing_jira_vars} JIRA_EMAIL"
    [ -z "${JIRA_TOKEN:-}" ] && _missing_jira_vars="${_missing_jira_vars} JIRA_TOKEN"

    if [ -n "$_missing_jira_vars" ]; then
      _warn "Missing Jira vars in $_jira_secrets:${_missing_jira_vars} — Jira integration will not work."
    else
      JIRA_LOADED=true
    fi
  fi
fi

unset _env_file _jira_secrets _missing_jira_vars
unset -f _warn
