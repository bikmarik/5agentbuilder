#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=common.sh
source "$repo_dir/scripts/common.sh"
operation=smoke-test
require_commands dirname basename readlink bash grep
parse_options "$@"
check_targets
shopt -s nullglob
agent_files=("$repo_dir"/agents/*.toml)
[ "${#agent_files[@]}" -eq 4 ] || fail 'Expected exactly four custom agent TOML files'
for role in scout builder verifier operator; do
  file="$repo_dir/agents/$role.toml"
  [ -f "$file" ] || fail "Missing agent: $role"
  grep -q "^name = \"$role\"$" "$file" || fail "Invalid role name: $file"
  grep -q '^description = "' "$file" || fail "Missing description: $file"
  grep -q "^developer_instructions = '''" "$file" || fail "Missing instructions: $file"
done
for file in README.md LICENSE install.sh uninstall.sh templates/AGENTS.md \
  skills/five-agent-engineering/SKILL.md \
  skills/five-agent-engineering/references/critique-protocol.md \
  skills/five-agent-engineering/references/workflow.md; do
  [ -s "$repo_dir/$file" ] || fail "Missing or empty resource: $file"
done
for file in "$repo_dir"/*.sh "$repo_dir"/scripts/*.sh; do bash -n "$file"; done
grep -q '^name: five-agent-engineering$' "$repo_dir/skills/five-agent-engineering/SKILL.md" || fail 'Invalid skill name'
grep -q '^description: .' "$repo_dir/skills/five-agent-engineering/SKILL.md" || fail 'Missing skill description'
for i in 0 1 2 3 4; do
  destination=${destinations[$i]}
  owned_link "$destination" "${sources[$i]}" || fail "Missing or foreign installation link: $destination"
  [ -e "$destination" ] || fail "Broken installation link: $destination"
  printf 'OK %s\n' "$destination"
done
printf 'PASS: structure, ownership, metadata presence, and shell syntax.\n'
printf 'This is not a TOML parser or proof of runtime delegation. Run the README conversational smoke test.\n'
