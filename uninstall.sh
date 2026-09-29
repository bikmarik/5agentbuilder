#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$repo_dir/scripts/common.sh"
operation=uninstall
require_commands dirname basename readlink rm
parse_options "$@"
check_targets
for i in 0 1 2 3 4; do
  destination=${destinations[$i]}
  if owned_link "$destination" "${sources[$i]}"; then
    printf 'REMOVE %s\n' "$destination"
    if [ "$dry_run" -eq 0 ]; then rm "$destination"; fi
  elif [ -e "$destination" ] || [ -L "$destination" ]; then
    printf 'KEEP %s (not a link owned by this checkout)\n' "$destination"
  else
    printf 'ABSENT %s\n' "$destination"
  fi
done
if [ "$dry_run" -eq 1 ]; then
  printf 'Dry run: no files or directories changed.\n'
else
  printf 'Only owned links removed; configuration, backups, and other files preserved.\n'
fi
