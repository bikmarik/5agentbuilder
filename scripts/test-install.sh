#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=common.sh
source "$repo_dir/scripts/common.sh"
require_commands mktemp mkdir cp cmp find grep ln rm bash
temp_root=${TMPDIR:-/tmp}
scratch=$(mktemp -d "${temp_root%/}/five-agent-test.XXXXXX")
# Only this uniquely created temporary tree is removed, never a user-supplied path.
trap 'rm -rf "$scratch"' EXIT
fixture="$scratch/clone with spaces"
mkdir -p "$fixture"
cp -R "$repo_dir/agents" "$repo_dir/skills" "$repo_dir/scripts" "$repo_dir/templates" "$fixture/"
cp "$repo_dir/install.sh" "$repo_dir/uninstall.sh" "$repo_dir/README.md" "$repo_dir/LICENSE" "$fixture/"
codex_target="$scratch/codex home"
skill_target="$scratch/personal skills"
options=(--codex-home "$codex_target" --skills-dir "$skill_target")
expect_failure() {
  if "$@" > "$scratch/expected-error" 2>&1; then fail "Unexpected success: $*"; fi
}
"$fixture/install.sh" "${options[@]}" --dry-run > "$scratch/log"
[ ! -e "$codex_target" ] && [ ! -e "$skill_target" ] || fail 'Dry run wrote directories'
mkdir -p "$codex_target" "$skill_target"
printf 'model = "preserve-me"\n' > "$codex_target/config.toml"
cp "$codex_target/config.toml" "$scratch/original-config"
printf 'unrelated\n' > "$skill_target/unrelated"
"$fixture/install.sh" "${options[@]}" > "$scratch/log"
"$fixture/install.sh" "${options[@]}" > "$scratch/log"
"$fixture/scripts/smoke-test.sh" "${options[@]}"
cmp "$codex_target/config.toml" "$scratch/original-config"
"$fixture/uninstall.sh" "${options[@]}" --dry-run > "$scratch/log"
[ -L "$codex_target/agents/scout.toml" ] || fail 'Uninstall dry run removed a link'
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
[ ! -L "$codex_target/agents/scout.toml" ] || fail 'Uninstall retained owned link'
[ -f "$skill_target/unrelated" ] || fail 'Uninstall removed unrelated file'
cmp "$codex_target/config.toml" "$scratch/original-config"

# A late conflict must not install earlier resources.
printf 'my verifier\n' > "$codex_target/agents/verifier.toml"
expect_failure "$fixture/install.sh" "${options[@]}"
[ ! -e "$codex_target/agents/scout.toml" ] || fail 'Conflict caused partial installation'
"$fixture/install.sh" "${options[@]}" --force --dry-run > "$scratch/log" 2>&1
grep -q 'my verifier' "$codex_target/agents/verifier.toml"
"$fixture/install.sh" "${options[@]}" --force > "$scratch/log" 2>&1
backup=$(find "$codex_target/agents" -path '*/.five-agent-backup.*/verifier.toml')
[ -n "$backup" ] || fail 'Missing conflict backup'
grep -q 'my verifier' "$backup"

# User replacements and foreign links are not owned, even after a prior install.
rm "$codex_target/agents/scout.toml" "$codex_target/agents/builder.toml"
printf 'user replacement\n' > "$codex_target/agents/scout.toml"
ln -s "$scratch/missing-foreign-target" "$codex_target/agents/builder.toml"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
grep -q 'user replacement' "$codex_target/agents/scout.toml"
[ -L "$codex_target/agents/builder.toml" ] || fail 'Removed foreign broken link'
[ -f "$backup" ] || fail 'Removed backup'

# Force preserves a conflicting skill directory and a dangling agent link.
mkdir -p "$skill_target/five-agent-engineering"
printf 'custom skill\n' > "$skill_target/five-agent-engineering/custom.txt"
"$fixture/install.sh" "${options[@]}" --force > "$scratch/log" 2>&1
skill_backup=$(find "$skill_target" -path '*/.five-agent-backup.*/five-agent-engineering/custom.txt')
grep -q 'custom skill' "$skill_backup"
"$fixture/scripts/smoke-test.sh" "${options[@]}" > "$scratch/log"

# A different checkout cannot uninstall this checkout's links.
"$repo_dir/uninstall.sh" "${options[@]}" > "$scratch/log"
[ -L "$codex_target/agents/operator.toml" ] || fail 'Foreign checkout removed owned link'
expect_failure "$fixture/install.sh" --codex-home relative --skills-dir "$skill_target"
expect_failure "$fixture/install.sh" --codex-home / --skills-dir "$skill_target"
expect_failure "$fixture/install.sh" --codex-home "$scratch/../escape" --skills-dir "$skill_target"
expect_failure "$fixture/install.sh" --unknown
expect_failure "$fixture/install.sh" --skills-dir
expect_failure "$fixture/uninstall.sh" --force
expect_failure "$fixture/install.sh" --codex-home "$fixture" --skills-dir "$skill_target"
ln -s "$codex_target" "$scratch/symlink-root"
expect_failure "$fixture/install.sh" --codex-home "$scratch/symlink-root" --skills-dir "$skill_target"
mkdir -p "$scratch/redirected-home" "$scratch/outside-agents"
ln -s "$scratch/outside-agents" "$scratch/redirected-home/agents"
expect_failure "$fixture/install.sh" --codex-home "$scratch/redirected-home" --skills-dir "$skill_target"
[ ! -e "$scratch/outside-agents/scout.toml" ] || fail 'Wrote through symlinked agent directory'

# Structural smoke test catches an accidental fifth subagent definition.
cp "$fixture/agents/scout.toml" "$fixture/agents/extra.toml"
expect_failure "$fixture/scripts/smoke-test.sh" "${options[@]}"
rm "$fixture/agents/extra.toml"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
cmp "$codex_target/config.toml" "$scratch/original-config"
printf 'PASS: isolated dry-run, install, idempotence, conflict, backup, ownership, path, structure, and uninstall tests.\n'
