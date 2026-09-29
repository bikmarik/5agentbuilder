#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$repo_dir/scripts/common.sh"
operation=install
require_commands dirname basename readlink mkdir ln mv mktemp cat cmp rm bash grep
if [ "$#" -eq 0 ]; then
  print_install_menu
  if [ ! -t 0 ]; then
    printf '\nNo terminal input: nothing installed. Use --target codex or --target claude (see --help).\n'
    exit 0
  fi
  if ! choose_install_options; then exit 0; fi
  set -- "${menu_args[@]}"
fi
parse_options "$@"
check_targets
[ -f "$repo_dir/scripts/smoke-test.sh" ] && [ -r "$repo_dir/scripts/smoke-test.sh" ] ||
  fail 'Missing or unreadable installation smoke test: scripts/smoke-test.sh'

# Preflight ALL resources before any filesystem mutation.
for i in 0 1 2 3 4; do
  source_path=${sources[$i]}
  destination=${destinations[$i]}
  if [ "$i" -lt 4 ]; then
    [ -f "$source_path" ] && [ ! -L "$source_path" ] || fail "Not a regular agent source: $source_path"
  else
    [ -d "$source_path" ] || fail "Missing Skill source: $source_path"
  fi
  if unchanged_resource "$i"; then
    printf 'UNCHANGED %s from %s\n' "$destination" "$source_path"
    continue
  fi
  replacements=("$destination")
  if [ "$i" -lt 4 ]; then
    replacements+=("$receipt_dir/${roles[$i]}.source" "$receipt_dir/${roles[$i]}.snapshot")
  fi
  for existing in "${replacements[@]}"; do
    if [ -e "$existing" ] || [ -L "$existing" ]; then
      [ "$force" -eq 1 ] || fail "Conflict: $existing. Nothing installed. Use --force to back it up first."
      printf 'WARNING: will back up existing %s before replacing it\n' "$existing" >&2
    fi
  done
  printf 'INSTALL %s from %s\n' "$destination" "$source_path"
done
if owned_link "$legacy_skill" "$legacy_source"; then
  printf 'MIGRATE %s to %s\n' "$legacy_skill" "${destinations[4]}"
elif [ -e "$legacy_skill" ] || [ -L "$legacy_skill" ]; then
  printf 'KEEP %s (old Skill is not owned by this checkout)\n' "$legacy_skill"
fi
if [ "$dry_run" -eq 1 ]; then
  printf 'Dry run: no files or directories changed.\n'
  exit 0
fi
mkdir -p "$agent_home/agents" "$skills_dir" "$receipt_dir"
for i in 0 1 2 3 4; do
  source_path=${sources[$i]}
  destination=${destinations[$i]}
  if unchanged_resource "$i"; then continue; fi
  replacements=("$destination")
  if [ "$i" -lt 4 ]; then
    replacements+=("$receipt_dir/${roles[$i]}.source" "$receipt_dir/${roles[$i]}.snapshot")
  fi
  for existing in "${replacements[@]}"; do
    if [ -e "$existing" ] || [ -L "$existing" ]; then
      [ "$force" -eq 1 ] || fail "Resource changed during installation: $existing"
      backup_dir=$(mktemp -d "$(dirname "$existing")/.five-agent-backup.XXXXXX")
      mv "$existing" "$backup_dir/$(basename "$existing")"
      printf 'BACKUP %s\n' "$backup_dir/$(basename "$existing")"
    fi
  done
  if [ "$i" -eq 4 ]; then
    # No -f: refuse unexpected late conflicts rather than silently overwriting.
    ln -s "$source_path" "$destination"
  else
    role=${roles[$i]}
    # Old receipts were backed up before publishing new bytes. An interruption
    # is fail-closed: a missing receipt needs inspection and --force to recover.
    # noclobber refuses a late destination instead of following/overwriting it.
    (set -o noclobber; cat "$source_path" > "$destination")
    (set -o noclobber; cat "$destination" > "$receipt_dir/$role.snapshot")
    (set -o noclobber; printf '%s\n' "$source_path" > "$receipt_dir/$role.source")
  fi
done
# Validate the selected client and resolved destinations, including custom roots.
# Repeat installs are checked even when there are no files to change.
smoke_options=(--target "$target" --skills-dir "$skills_dir")
if [ "$target" = codex ]; then
  smoke_options+=(--codex-home "$agent_home")
else
  smoke_options+=(--claude-home "$agent_home")
fi
printf 'Running installation smoke test for %s...\n' "$target"
if ! bash "$repo_dir/scripts/smoke-test.sh" "${smoke_options[@]}"; then
  fail 'Installation verification failed. Files and backups were retained; fix the reported problem and rerun the installer.'
fi
# Remove only our exact old link, after the renamed Skill has passed verification.
if owned_link "$legacy_skill" "$legacy_source"; then
  rm "$legacy_skill"
  printf 'REMOVE migrated Skill link %s\n' "$legacy_skill"
fi
printf 'Installed for %s; automatic smoke test passed. Keep this clone in place and restart the client.\n' "$target"
