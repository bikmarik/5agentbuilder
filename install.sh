#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  if [ "$argument" = --dry-run ]; then exec >/dev/null 2>&1; fi
done
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$repo_dir/scripts/common.sh"
operation=install
require_commands dirname basename readlink mkdir ln mv mktemp cat cmp rm bash grep
# A standalone dry run checks both clients without selecting one for installation.
if [ "$#" -eq 1 ] && [ "$1" = --dry-run ]; then
  status=0
  for client in codex claude; do
    bash "$repo_dir/install.sh" --target "$client" --dry-run || status=1
  done
  exit "$status"
fi
if [ "$#" -eq 0 ]; then
  print_install_menu
  if [ ! -t 0 ]; then
    printf '\nNo terminal input: nothing installed. Use --target codex or --target claude (see --help).\n'
    exit 0
  fi
  if ! choose_install_options; then exit 0; fi
  set -- "${menu_args[@]}"
fi
for argument in "$@"; do
  if [ "$argument" = --dry-run ]; then exec >/dev/null 2>&1; fi
done
parse_options "$@"
check_targets
link_agents=0
if can_link_agents; then link_agents=1; fi
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
  if [ "$i" -lt 4 ] && [ "$link_agents" -eq 1 ]; then continue; fi
  if unchanged_resource "$i"; then
    continue
  fi
  replacements=("$destination")
  if [ "$i" -lt 4 ]; then
    replacements+=("$receipt_dir/${roles[$i]}.source" "$receipt_dir/${roles[$i]}.snapshot")
  fi
  for existing in "${replacements[@]}"; do
    if [ -e "$existing" ] || [ -L "$existing" ]; then
      [ "$force" -eq 1 ] || fail "Conflict: $existing. Nothing installed. Use --force to back it up first."
    fi
  done
done
if owned_link "$legacy_skill" "$legacy_source"; then
  printf 'MIGRATE %s to %s\n' "$legacy_skill" "${destinations[4]}"
elif [ -e "$legacy_skill" ] || [ -L "$legacy_skill" ]; then
  printf 'KEEP %s (old Skill is not owned by this checkout)\n' "$legacy_skill"
fi
if [ "$dry_run" -eq 1 ]; then
  exit 0
fi
model_options=(--target "$target" --home "$agent_home" --repo "$repo_dir")
smoke_options=(--target "$target" --skills-dir "$skills_dir" "--$target-home" "$agent_home")
model_plan=
if [ "$keep_models" -eq 0 ]; then
  require_commands python3 "$target"
  model_plan=$(mktemp "${TMPDIR:-/tmp}/five-agent-model-plan.XXXXXX")
  trap 'rm -f "$model_plan"' EXIT
  python3 "$repo_dir/scripts/models.py" choose "${model_options[@]}" --plan "$model_plan"
elif [ "$agent_sources" != "$template_sources" ]; then
  require_commands python3
fi
if [ "$models_only" -eq 1 ]; then
  [ -e "${destinations[4]}/SKILL.md" ] || fail 'Install the workflow before changing its models.'
  python3 "$repo_dir/scripts/models.py" apply "${model_options[@]}" --plan "$model_plan"
  bash "$repo_dir/scripts/smoke-test.sh" "${smoke_options[@]}"
  printf 'Global models updated for all five agents. Restart the client to load changes.\n'
  exit 0
fi
mkdir -p "$agent_home" "$skills_dir"
if [ "$link_agents" -eq 1 ]; then
  if ! owned_link "$agent_home/agents" "$agent_sources"; then
    if [ -d "$agent_home/agents" ]; then
      backup_dir=$(mktemp -d "$agent_home/.five-agent-backup.XXXXXX")
      mv "$agent_home/agents" "$backup_dir/agents"
      printf 'Backup: %s/agents\n' "$backup_dir"
    fi
    ln -s "$agent_sources" "$agent_home/agents"
  fi
else
  mkdir -p "$agent_home/agents" "$receipt_dir"
fi
for i in 0 1 2 3 4; do
  if [ "$i" -lt 4 ] && [ "$link_agents" -eq 1 ]; then continue; fi
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
if [ -n "$model_plan" ]; then
  python3 "$repo_dir/scripts/models.py" apply "${model_options[@]}" --plan "$model_plan"
elif [ "$agent_sources" != "$template_sources" ]; then
  python3 "$repo_dir/scripts/models.py" refresh "${model_options[@]}"
fi
# Validate the selected client and resolved destinations, including custom roots.
# Repeat installs are checked even when there are no files to change.
printf 'Running installation smoke test for %s...\n' "$target"
if ! bash "$repo_dir/scripts/smoke-test.sh" "${smoke_options[@]}"; then
  fail 'Installation verification failed. Files and backups were retained; fix the reported problem and rerun the installer.'
fi
# Remove only our exact old link, after the renamed Skill has passed verification.
if owned_link "$legacy_skill" "$legacy_source"; then
  rm "$legacy_skill"
  printf 'REMOVE migrated Skill link %s\n' "$legacy_skill"
fi
printf 'Installed for %s; automatic smoke test passed. Restart the client to load changes.\n' "$target"
