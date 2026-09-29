#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
  done
}

# Shared CLI and fixed ownership list; no global config parsing or modification.
parse_options() {
  codex_dir=${CODEX_HOME:-${HOME:?HOME must be set}/.codex}
  skills_dir=${HOME:?HOME must be set}/.agents/skills
  dry_run=0
  force=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --codex-home|--skills-dir)
        [ "$#" -ge 2 ] || fail "$1 requires an absolute path"
        if [ "$1" = --codex-home ]; then codex_dir=$2; else skills_dir=$2; fi
        shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --force)
        [ "$operation" = install ] || fail '--force is only supported for installation'
        force=1; shift ;;
      --help|-h)
        printf 'Usage: %s [--dry-run] [--codex-home ABSOLUTE_PATH] [--skills-dir ABSOLUTE_PATH]' "$0"
        if [ "$operation" = install ]; then printf ' [--force]'; fi
        printf '\n'; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done
  for target_root in "$codex_dir" "$skills_dir"; do
    case "$target_root" in
      /*) ;;
      *) fail "Target must be absolute: $target_root" ;;
    esac
    case "$target_root/" in
      /|//|*/../*|*/./*|*//*|*$'\n'*|*$'\r'*) fail "Unsafe target path: $target_root" ;;
    esac
  done
  codex_dir=${codex_dir%/}
  skills_dir=${skills_dir%/}
  sources=("$repo_dir/agents/scout.toml" "$repo_dir/agents/builder.toml"
    "$repo_dir/agents/verifier.toml" "$repo_dir/agents/operator.toml"
    "$repo_dir/skills/five-agent-engineering")
  destinations=("$codex_dir/agents/scout.toml" "$codex_dir/agents/builder.toml"
    "$codex_dir/agents/verifier.toml" "$codex_dir/agents/operator.toml"
    "$skills_dir/five-agent-engineering")
}

# /tmp and /var may be system aliases on macOS. Existing ancestors are allowed;
# refuse symlinks at the explicitly selected roots and managed agent directory.
check_directory() {
  local directory=$1
  [ ! -L "$directory" ] || fail "Refusing symlinked target directory: $directory"
  if [ -e "$directory" ]; then
    [ -d "$directory" ] || fail "Not a directory: $directory"
  fi
}

owned_link() {
  [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]
}

check_targets() {
  check_directory "$codex_dir"
  check_directory "$codex_dir/agents"
  check_directory "$skills_dir"
  # Prevent a link cycle or an installation overwriting its own source checkout.
  local i parent physical_parent physical_source
  for i in 0 1 2 3 4; do
    parent=$(dirname "${destinations[$i]}")
    if [ -d "$parent" ]; then
      physical_parent=$(cd "$parent" && pwd -P)
      physical_source=$(cd "$(dirname "${sources[$i]}")" && pwd -P)/$(basename "${sources[$i]}")
      [ "$physical_parent/$(basename "${destinations[$i]}")" != "$physical_source" ] ||
        fail "Target is the source checkout: ${destinations[$i]}"
    fi
  done
}
