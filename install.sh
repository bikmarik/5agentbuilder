#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$repo_dir/scripts/common.sh"
operation=install
require_commands dirname basename readlink mkdir ln mv mktemp
parse_options "$@"
check_targets

# Preflight ALL resources before any filesystem mutation.
for i in 0 1 2 3 4; do
  source_path=${sources[$i]}
  destination=${destinations[$i]}
  [ -e "$source_path" ] || fail "Missing source: $source_path"
  if owned_link "$destination" "$source_path"; then
    printf 'UNCHANGED %s -> %s\n' "$destination" "$source_path"
  elif [ -e "$destination" ] || [ -L "$destination" ]; then
    if [ "$force" -eq 0 ]; then
      fail "Conflict: $destination. Nothing installed. Use --force to back it up first."
    fi
    printf 'WARNING: will back up existing %s before replacing it\n' "$destination" >&2
  fi
  printf 'INSTALL %s -> %s\n' "$destination" "$source_path"
done
if [ "$dry_run" -eq 1 ]; then
  printf 'Dry run: no files or directories changed.\n'
  exit 0
fi
mkdir -p "$codex_dir/agents" "$skills_dir"
for i in 0 1 2 3 4; do
  source_path=${sources[$i]}
  destination=${destinations[$i]}
  if owned_link "$destination" "$source_path"; then continue; fi
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    [ "$force" -eq 1 ] || fail "Destination changed during installation: $destination"
    backup_dir=$(mktemp -d "$(dirname "$destination")/.five-agent-backup.XXXXXX")
    mv "$destination" "$backup_dir/$(basename "$destination")"
    printf 'BACKUP %s\n' "$backup_dir/$(basename "$destination")"
  fi
  # No -f: refuse unexpected late conflicts rather than silently overwriting.
  ln -s "$source_path" "$destination"
done
printf 'Installed. Keep this clone in place. Restart Codex and run scripts/smoke-test.sh.\n'
