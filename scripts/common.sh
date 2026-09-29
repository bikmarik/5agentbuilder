#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
  done
}

print_install_menu() {
  cat <<'MENU'
five-agent-build installer

  1) Install for Codex
  2) Install for Claude Code
  3) Update Codex (back up conflicting files)
  4) Update Claude Code (back up conflicting files)
  5) Preview Codex installation (no changes)
  6) Preview Claude Code installation (no changes)
  h) Show command-line options
  0) Exit
MENU
}

choose_install_options() {
  local choice
  menu_args=()
  while true; do
    printf '\nChoose an option [0]: '
    if ! IFS= read -r choice; then printf '\nCancelled.\n'; return 1; fi
    case "$choice" in
      1) menu_args=(--target codex); return 0 ;;
      2) menu_args=(--target claude); return 0 ;;
      3) menu_args=(--target codex --force); return 0 ;;
      4) menu_args=(--target claude --force); return 0 ;;
      5) menu_args=(--target codex --dry-run); return 0 ;;
      6) menu_args=(--target claude --dry-run); return 0 ;;
      h|H) menu_args=(--help); return 0 ;;
      0|'') printf 'Cancelled.\n'; return 1 ;;
      *) printf 'Invalid choice. Enter 0-6 or h.\n' ;;
    esac
  done
}

# Shared CLI and fixed ownership list; no global config parsing or modification.
parse_options() {
  codex_dir=${CODEX_HOME:-${HOME:?HOME must be set}/.codex}
  claude_dir=${CLAUDE_CONFIG_DIR:-${HOME:?HOME must be set}/.claude}
  target=codex
  skills_dir=
  codex_override=0
  claude_override=0
  dry_run=0
  force=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --target)
        [ "$#" -ge 2 ] || fail '--target requires codex or claude'
        target=$2; shift 2 ;;
      --codex-home|--claude-home|--skills-dir)
        [ "$#" -ge 2 ] || fail "$1 requires an absolute path"
        [ -n "$2" ] || fail "$1 requires a nonempty path"
        case "$1" in
          --codex-home) codex_dir=$2; codex_override=1 ;;
          --claude-home) claude_dir=$2; claude_override=1 ;;
          --skills-dir) skills_dir=$2 ;;
        esac
        shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --force)
        [ "$operation" = install ] || fail '--force is only supported for installation'
        force=1; shift ;;
      --help|-h)
        printf 'Usage: %s [--target codex|claude] [--dry-run] [--codex-home ABSOLUTE_PATH | --claude-home ABSOLUTE_PATH] [--skills-dir ABSOLUTE_PATH]' "$0"
        if [ "$operation" = install ]; then printf ' [--force]'; fi
        printf '\n'; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done
  case "$target" in
    codex)
      [ "$claude_override" -eq 0 ] || fail '--claude-home requires --target claude'
      agent_home=$codex_dir
      skills_dir=${skills_dir:-$HOME/.agents/skills}
      agent_sources="$repo_dir/agents"
      skill_source="$repo_dir/skills/five-agent-build"
      agent_extension=toml ;;
    claude)
      [ "$codex_override" -eq 0 ] || fail '--codex-home requires --target codex'
      agent_home=$claude_dir
      skills_dir=${skills_dir:-$claude_dir/skills}
      agent_sources="$repo_dir/claude/agents"
      skill_source="$repo_dir/claude/skills/five-agent-build"
      agent_extension=md ;;
    *) fail 'Invalid --target; choose codex or claude' ;;
  esac
  for target_root in "$agent_home" "$skills_dir"; do
    case "$target_root" in
      /*) ;;
      *) fail "Target must be absolute: $target_root" ;;
    esac
    case "$target_root/" in
      /|//|*/../*|*/./*|*//*|*$'\n'*|*$'\r'*) fail "Unsafe target path: $target_root" ;;
    esac
  done
  agent_home=${agent_home%/}
  skills_dir=${skills_dir%/}
  receipt_dir="$agent_home/.five-agent-engineering"
  legacy_skill="$skills_dir/five-agent-engineering"
  if [ "$target" = codex ]; then
    legacy_source="$repo_dir/skills/five-agent-engineering"
  else
    legacy_source="$repo_dir/claude/skills/five-agent-engineering"
  fi
  roles=(scout builder verifier operator)
  sources=("$agent_sources/scout.$agent_extension" "$agent_sources/builder.$agent_extension"
    "$agent_sources/verifier.$agent_extension" "$agent_sources/operator.$agent_extension"
    "$skill_source")
  destinations=("$agent_home/agents/scout.$agent_extension" "$agent_home/agents/builder.$agent_extension"
    "$agent_home/agents/verifier.$agent_extension" "$agent_home/agents/operator.$agent_extension"
    "$skills_dir/five-agent-build")
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
  check_directory "$agent_home"
  check_directory "$agent_home/agents"
  check_directory "$skills_dir"
  check_directory "$receipt_dir"
  local role receipt
  for role in "${roles[@]}"; do
    for receipt in "$receipt_dir/$role.source" "$receipt_dir/$role.snapshot"; do
      [ ! -L "$receipt" ] || fail "Refusing symlinked receipt: $receipt"
      if [ -e "$receipt" ]; then
        [ -f "$receipt" ] || fail "Not a regular receipt file: $receipt"
      fi
    done
  done
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

# Ownership is based on installed bytes, never on the current source contents.
# A missing/partial receipt is deliberately not proof of ownership.
owned_agent() {
  local index=$1 role=${roles[$1]}
  [ ! -L "${destinations[$index]}" ] && [ -f "${destinations[$index]}" ] &&
    [ -f "$receipt_dir/$role.source" ] && [ -f "$receipt_dir/$role.snapshot" ] &&
    printf '%s\n' "${sources[$index]}" | cmp -s - "$receipt_dir/$role.source" &&
    cmp -s "${destinations[$index]}" "$receipt_dir/$role.snapshot"
}

unchanged_resource() {
  if [ "$1" -eq 4 ]; then
    owned_link "${destinations[$1]}" "${sources[$1]}"
  else
    owned_agent "$1" && cmp -s "${sources[$1]}" "${destinations[$1]}"
  fi
}
