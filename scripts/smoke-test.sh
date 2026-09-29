#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=common.sh
source "$repo_dir/scripts/common.sh"
operation=smoke-test
require_commands dirname basename readlink bash grep cmp
parse_options "$@"
check_targets
shopt -s nullglob
agent_files=("$agent_sources"/*."$agent_extension")
[ "${#agent_files[@]}" -eq 4 ] || fail 'Expected exactly four custom agent definitions for the selected client'
for role in scout builder verifier operator; do
  file="$agent_sources/$role.$agent_extension"
  [ -f "$file" ] && [ ! -L "$file" ] || fail "Missing or symlinked agent: $role"
  if [ "$target" = codex ]; then
    grep -q "^name = \"$role\"$" "$file" || fail "Invalid role name: $file"
    grep -q '^description = "' "$file" || fail "Missing description: $file"
    grep -q "^developer_instructions = '''" "$file" || fail "Missing instructions: $file"
  else
    grep -q "^name: $role$" "$file" || fail "Invalid role name: $file"
    grep -q '^description: .' "$file" || fail "Missing description: $file"
    grep -q '^tools: .' "$file" || fail "Missing tool allowlist: $file"
  fi
done
for file in README.md LICENSE install.sh uninstall.sh templates/AGENTS.md \
  skills/five-agent-build/SKILL.md \
  skills/five-agent-build/references/critique-protocol.md \
  skills/five-agent-build/references/workflow.md; do
  [ -s "$repo_dir/$file" ] || fail "Missing or empty resource: $file"
done
for file in "$repo_dir"/*.sh "$repo_dir"/scripts/*.sh; do bash -n "$file"; done
grep -q '^name: five-agent-build$' "$skill_source/SKILL.md" || fail 'Invalid skill name'
grep -q '^description: .' "$skill_source/SKILL.md" || fail 'Missing skill description'
if [ "$target" = codex ]; then
  grep -q '^  allow_implicit_invocation: false$' "$skill_source/agents/openai.yaml" || fail 'Skill must be explicit-only in Codex'
else
  grep -q '^disable-model-invocation: true$' "$skill_source/SKILL.md" || fail 'Skill must be explicit-only in Claude Code'
fi
for reference in critique-protocol workflow; do
  [ -s "$skill_source/references/$reference.md" ] || fail "Missing Skill reference: $reference"
done
for i in 0 1 2 3 4; do
  destination=${destinations[$i]}
  unchanged_resource "$i" || fail "Missing, stale, modified, symlinked agent, or foreign installation: $destination"
  [ -e "$destination" ] || fail "Broken installation link: $destination"
done
if [ "$agent_sources" != "$template_sources" ]; then
  require_commands python3
  python3 "$repo_dir/scripts/models.py" verify --target "$target" --home "$agent_home" --repo "$repo_dir"
fi
printf 'PASS: %s agents and Skill verified.\n' "$target"
