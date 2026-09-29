#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=common.sh
source "$repo_dir/scripts/common.sh"
require_commands mktemp mkdir cp cmp find grep ln rm mv rmdir bash awk sed
if [ "$#" -eq 0 ]; then
  "$0" --target codex
  "$0" --target claude
  python3 "$repo_dir/scripts/test-models.py"
  exit 0
fi
[ "$#" -eq 2 ] && [ "$1" = --target ] || fail 'Usage: scripts/test-install.sh [--target codex|claude]'
client=$2
case "$client" in
  codex) extension=toml; source_subdir=agents; home_option=--codex-home; config_file=config.toml ;;
  claude) extension=md; source_subdir=claude/agents; home_option=--claude-home; config_file=settings.json ;;
  *) fail 'Invalid test target' ;;
esac
temp_root=${TMPDIR:-/tmp}
scratch=$(mktemp -d "${temp_root%/}/five-agent-test.XXXXXX")
# Only this uniquely created temporary tree is removed, never a user-supplied path.
trap 'rm -rf "$scratch"' EXIT
fixture="$scratch/clone with spaces"
mkdir -p "$fixture"
fixture=$(cd "$fixture" && pwd -P)
cp -R "$repo_dir/agents" "$repo_dir/claude" "$repo_dir/skills" "$repo_dir/scripts" "$repo_dir/templates" "$fixture/"
cp "$repo_dir/install.sh" "$repo_dir/uninstall.sh" "$repo_dir/README.md" "$repo_dir/LICENSE" "$fixture/"
target_home="$scratch/$client home"
skill_target="$scratch/personal skills"
options=(--target "$client" "$home_option" "$target_home" --skills-dir "$skill_target")
expect_failure() {
  if "$@" > "$scratch/expected-error" 2>&1; then fail "Unexpected success: $*"; fi
}
"$fixture/install.sh" < /dev/null > "$scratch/menu"
grep -q 'Install for Codex' "$scratch/menu"
grep -q 'Install for Claude Code' "$scratch/menu"
grep -q 'nothing installed' "$scratch/menu"
[ ! -e "$target_home" ] && [ ! -e "$skill_target" ] || fail 'No-argument menu wrote files'
for choice in 1 2 3 4 5 6 7 8; do
  choose_install_options <<< "$choice" > "$scratch/menu"
  case "$choice" in
    1) expected='--target codex' ;;
    2) expected='--target claude' ;;
    3) expected='--target codex --force' ;;
    4) expected='--target claude --force' ;;
    5) expected='--target codex --dry-run' ;;
    6) expected='--target claude --dry-run' ;;
    7) expected='--target codex --models' ;;
    8) expected='--target claude --models' ;;
  esac
  [ "${menu_args[*]}" = "$expected" ] || fail "Wrong menu action for $choice"
done
choose_install_options <<< $'invalid\n5' > "$scratch/menu"
grep -q 'Invalid choice' "$scratch/menu"
[ "${menu_args[*]}" = '--target codex --dry-run' ] || fail 'Menu did not recover from invalid input'
if choose_install_options <<< '' > "$scratch/menu"; then fail 'Empty menu choice did not cancel'; fi
if choose_install_options < /dev/null > "$scratch/menu"; then fail 'Menu EOF did not cancel'; fi
"$fixture/install.sh" --keep-models "${options[@]}" --dry-run > "$scratch/log"
[ ! -s "$scratch/log" ] || fail 'Dry run printed output'
[ ! -e "$target_home" ] && [ ! -e "$skill_target" ] || fail 'Dry run wrote directories'
mkdir -p "$target_home/agents" "$skill_target"
printf 'unrelated agent\n' > "$target_home/agents/unrelated.txt"
printf 'model = "preserve-me"\n' > "$target_home/$config_file"
cp "$target_home/$config_file" "$scratch/original-config"
printf 'unrelated\n' > "$skill_target/unrelated"
legacy_source="$fixture/skills/five-agent-engineering"
if [ "$client" = claude ]; then legacy_source="$fixture/claude/skills/five-agent-engineering"; fi
ln -s "$legacy_source" "$skill_target/five-agent-engineering"
"$fixture/install.sh" --keep-models "${options[@]}" --dry-run > "$scratch/log"
[ -L "$skill_target/five-agent-engineering" ] || fail 'Dry run removed old Skill link'
[ ! -e "$skill_target/five-agent-build" ] || fail 'Dry run installed renamed Skill'
# A failed automatic test must fail installation without removing the legacy link.
cp "$fixture/scripts/smoke-test.sh" "$scratch/original-smoke"
printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf "injected smoke failure\\n"\nexit 23\n' > "$fixture/scripts/smoke-test.sh"
"$fixture/install.sh" --keep-models "${options[@]}" --dry-run > "$scratch/log"
if grep -q 'injected smoke failure' "$scratch/log"; then fail 'Dry run executed the smoke test'; fi
expect_failure "$fixture/install.sh" --keep-models "${options[@]}"
grep -q 'injected smoke failure' "$scratch/expected-error"
grep -q 'Installation verification failed' "$scratch/expected-error"
if grep -q '^Installed for' "$scratch/expected-error"; then fail 'Failed verification reported success'; fi
[ -L "$skill_target/five-agent-engineering" ] || fail 'Failed verification removed legacy Skill'
[ -f "$target_home/agents/scout.$extension" ] || fail 'Failed verification unexpectedly rolled back installed files'
cp "$scratch/original-smoke" "$fixture/scripts/smoke-test.sh"
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"
grep -q 'automatic smoke test passed' "$scratch/log"
[ ! -L "$skill_target/five-agent-engineering" ] || fail 'Old owned Skill link was not migrated'
[ -f "$skill_target/five-agent-build/SKILL.md" ] || fail 'Renamed Skill is not readable'
# Foreign old links and real directories are not ours to migrate.
ln -s "$scratch/foreign-old-skill" "$skill_target/five-agent-engineering"
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"
[ -L "$skill_target/five-agent-engineering" ] || fail 'Removed foreign old Skill link'
rm "$skill_target/five-agent-engineering"
mkdir "$skill_target/five-agent-engineering"
printf 'keep\n' > "$skill_target/five-agent-engineering/user.txt"
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"
grep -q '^keep$' "$skill_target/five-agent-engineering/user.txt"
"$fixture/scripts/smoke-test.sh" "${options[@]}"
# Both clients follow the same workflow; only host invocation metadata differs.
awk 'BEGIN { delimiters=0 } /^---$/ && delimiters<2 { delimiters++; next } delimiters==2 { print }' "$fixture/skills/five-agent-build/SKILL.md" > "$scratch/codex-body"
awk 'BEGIN { delimiters=0 } /^---$/ && delimiters<2 { delimiters++; next } delimiters==2 { print }' "$fixture/claude/skills/five-agent-build/SKILL.md" > "$scratch/claude-body"
cmp "$scratch/codex-body" "$scratch/claude-body"
expect_failure "$fixture/install.sh" --target invalid
expect_failure "$fixture/install.sh" --target
expect_failure "$fixture/install.sh" --target claude --codex-home "$scratch/wrong-home"
expect_failure "$fixture/install.sh" --target codex --claude-home "$scratch/wrong-home"
[ ! -e "$scratch/wrong-home" ] || fail 'Invalid option combination wrote files'
# Invocation controls are required, not merely documented.
if [ "$client" = codex ]; then
  policy_file="$fixture/skills/five-agent-build/agents/openai.yaml"
  cp "$policy_file" "$scratch/valid-policy"
  printf 'policy:\n  allow_implicit_invocation: true\n' > "$policy_file"
else
  policy_file="$fixture/claude/skills/five-agent-build/SKILL.md"
  cp "$policy_file" "$scratch/valid-policy"
  sed 's/disable-model-invocation: true/disable-model-invocation: false/' "$scratch/valid-policy" > "$policy_file"
fi
expect_failure "$fixture/scripts/smoke-test.sh" "${options[@]}"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}"
grep -q 'Installation verification failed' "$scratch/expected-error"
cp "$scratch/valid-policy" "$policy_file"
# The other client has independent ownership and must survive this uninstall.
if [ "$client" = codex ]; then
  other_client=claude; other_home_option=--claude-home; other_extension=md
else
  other_client=codex; other_home_option=--codex-home; other_extension=toml
fi
other_options=(--target "$other_client" "$other_home_option" "$scratch/other client" --skills-dir "$scratch/other skills")
"$fixture/install.sh" --keep-models "${other_options[@]}" > "$scratch/log"
cmp "$target_home/$config_file" "$scratch/original-config"
"$fixture/uninstall.sh" "${options[@]}" --dry-run > "$scratch/log"
[ -f "$target_home/agents/scout.$extension" ] && [ ! -L "$target_home/agents/scout.$extension" ] || fail 'Uninstall dry run removed a copy'
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
"$fixture/scripts/smoke-test.sh" "${other_options[@]}" > "$scratch/log"
[ -f "$scratch/other client/agents/scout.$other_extension" ] || fail 'Uninstall touched the other client'
"$fixture/uninstall.sh" "${other_options[@]}" > "$scratch/log"
[ ! -e "$target_home/agents/scout.$extension" ] || fail 'Uninstall retained owned copy'
[ -f "$skill_target/unrelated" ] || fail 'Uninstall removed unrelated file'
cmp "$target_home/$config_file" "$scratch/original-config"
# Require explicit client selection and check Claude's default skill path.
if [ "$client" = codex ]; then
  expect_failure "$fixture/install.sh" --codex-home "$scratch/default-client" --skills-dir "$scratch/default-skills"
  "$fixture/install.sh" --keep-models --target codex --codex-home "$scratch/default-client" --skills-dir "$scratch/default-skills" > "$scratch/log"
  [ -f "$scratch/default-client/agents/scout.toml" ] || fail 'Explicit Codex selection failed'
else
  "$fixture/install.sh" --keep-models --target claude --claude-home "$scratch/default-client" > "$scratch/log"
  "$fixture/scripts/smoke-test.sh" --target claude --claude-home "$scratch/default-client" > "$scratch/log"
  [ -L "$scratch/default-client/skills/five-agent-build" ] || fail 'Claude skill root did not follow --claude-home'
fi

# A late conflict must not install earlier resources.
printf 'my verifier\n' > "$target_home/agents/verifier.$extension"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}"
[ ! -e "$target_home/agents/scout.$extension" ] || fail 'Conflict caused partial installation'
"$fixture/install.sh" --keep-models "${options[@]}" --force --dry-run > "$scratch/log" 2>&1
grep -q 'my verifier' "$target_home/agents/verifier.$extension"
"$fixture/install.sh" --keep-models "${options[@]}" --force > "$scratch/log" 2>&1
backup=$(find "$target_home/agents" -path "*/.five-agent-backup.*/verifier.$extension")
[ -n "$backup" ] || fail 'Missing conflict backup'
grep -q 'my verifier' "$backup"

# User replacements and foreign links are not owned, even after a prior install.
rm "$target_home/agents/scout.$extension" "$target_home/agents/builder.$extension"
printf 'user replacement\n' > "$target_home/agents/scout.$extension"
ln -s "$scratch/missing-foreign-target" "$target_home/agents/builder.$extension"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
grep -q 'user replacement' "$target_home/agents/scout.$extension"
[ -L "$target_home/agents/builder.$extension" ] || fail 'Removed foreign broken link'
[ -f "$backup" ] || fail 'Removed backup'

# Force preserves a conflicting skill directory and a dangling agent link.
mkdir -p "$skill_target/five-agent-build"
printf 'custom skill\n' > "$skill_target/five-agent-build/custom.txt"
"$fixture/install.sh" --keep-models "${options[@]}" --force > "$scratch/log" 2>&1
skill_backup=$(find "$skill_target" -path '*/.five-agent-backup.*/five-agent-build/custom.txt')
grep -q 'custom skill' "$skill_backup"
"$fixture/scripts/smoke-test.sh" "${options[@]}" > "$scratch/log"

# A different checkout cannot uninstall this checkout's copies.
"$repo_dir/uninstall.sh" "${options[@]}" > "$scratch/log"
[ -f "$target_home/agents/operator.$extension" ] || fail 'Foreign checkout removed owned copy'
expect_failure "$fixture/install.sh" --target "$client" "$home_option" relative --skills-dir "$skill_target"
expect_failure "$fixture/install.sh" --target "$client" "$home_option" / --skills-dir "$skill_target"
expect_failure "$fixture/install.sh" --target "$client" "$home_option" "$scratch/../escape" --skills-dir "$skill_target"
expect_failure "$fixture/install.sh" --unknown
expect_failure "$fixture/install.sh" --skills-dir
expect_failure "$fixture/uninstall.sh" --force
self_target=$fixture
if [ "$client" = claude ]; then self_target="$fixture/claude"; fi
expect_failure "$fixture/install.sh" --target "$client" "$home_option" "$self_target" --skills-dir "$skill_target"
ln -s "$target_home" "$scratch/symlink-root"
expect_failure "$fixture/install.sh" --target "$client" "$home_option" "$scratch/symlink-root" --skills-dir "$skill_target"
mkdir -p "$scratch/redirected-home" "$scratch/outside-agents"
ln -s "$scratch/outside-agents" "$scratch/redirected-home/agents"
expect_failure "$fixture/install.sh" --target "$client" "$home_option" "$scratch/redirected-home" --skills-dir "$skill_target"
[ ! -e "$scratch/outside-agents/scout.$extension" ] || fail 'Wrote through symlinked agent directory'

# Updating the clone leaves installed bytes owned until explicitly upgraded.
cp "$target_home/agents/operator.$extension" "$scratch/old-operator"
printf '\n# updated source\n' >> "$fixture/$source_subdir/operator.$extension"
expect_failure "$fixture/scripts/smoke-test.sh" "${options[@]}"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}"
cmp "$target_home/agents/operator.$extension" "$scratch/old-operator"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
[ ! -e "$target_home/agents/operator.$extension" ] || fail 'Updated source broke copy ownership'
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"
printf '\n# second update\n' >> "$fixture/$source_subdir/operator.$extension"
"$fixture/install.sh" --keep-models "${options[@]}" --force > "$scratch/log" 2>&1
cmp "$fixture/$source_subdir/operator.$extension" "$target_home/agents/operator.$extension"
"$fixture/scripts/smoke-test.sh" "${options[@]}" > "$scratch/log"

# Legacy symlinks, even matching ones, require force and retain their backups.
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
for role in scout builder verifier operator; do
  ln -s "$fixture/$source_subdir/$role.$extension" "$target_home/agents/$role.$extension"
done
expect_failure "$fixture/scripts/smoke-test.sh" "${options[@]}"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}"
"$fixture/install.sh" --keep-models "${options[@]}" --force > "$scratch/log" 2>&1
for role in scout builder verifier operator; do
  [ -f "$target_home/agents/$role.$extension" ] && [ ! -L "$target_home/agents/$role.$extension" ] || fail 'Migration retained agent link'
  cmp "$fixture/$source_subdir/$role.$extension" "$target_home/agents/$role.$extension"
done
[ -n "$(find "$target_home/agents" -type l -path "*/.five-agent-backup.*/scout.$extension")" ] || fail 'Legacy link backup missing'

# Identical copies without complete receipts are unowned (including interruption).
receipt_target="$target_home/.five-agent-engineering"
rm "$receipt_target/scout.source" "$receipt_target/builder.snapshot"
expect_failure "$fixture/scripts/smoke-test.sh" "${options[@]}"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
[ -f "$target_home/agents/scout.$extension" ] && [ -f "$target_home/agents/builder.$extension" ] || fail 'Partial receipt claimed ownership'
"$fixture/install.sh" --keep-models "${options[@]}" --force > "$scratch/log" 2>&1

# Preflight all receipt nodes before mutations, even a fourth-role conflict.
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
mkdir "$receipt_target/operator.snapshot"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}" --force
[ ! -e "$target_home/agents/scout.$extension" ] || fail 'Late invalid receipt caused partial install'
rmdir "$receipt_target/operator.snapshot"
printf 'outside receipt\n' > "$scratch/outside-receipt"
ln -s "$scratch/outside-receipt" "$receipt_target/operator.source"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}" --force
expect_failure "$fixture/uninstall.sh" "${options[@]}"
expect_failure "$fixture/scripts/smoke-test.sh" "${options[@]}"
grep -q '^outside receipt$' "$scratch/outside-receipt"
[ ! -e "$target_home/agents/scout.$extension" ] || fail 'Symlink receipt caused partial install'
rm "$receipt_target/operator.source"
mv "$receipt_target" "$scratch/retained-receipt-backups"
ln -s "$scratch" "$receipt_target"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}" --force
rm "$receipt_target"
printf 'invalid root\n' > "$receipt_target"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}" --force
rm "$receipt_target"
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"

# Orphan/foreign receipts must never be silently overwritten, even without agents.
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
printf 'foreign checkout identity\n' > "$receipt_target/scout.source"
printf 'unrelated installed bytes\n' > "$receipt_target/scout.snapshot"
cp "$receipt_target/scout.source" "$scratch/orphan-source"
cp "$receipt_target/scout.snapshot" "$scratch/orphan-snapshot"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}"
expect_failure "$fixture/install.sh" --keep-models "${options[@]}" --dry-run
"$fixture/install.sh" --keep-models "${options[@]}" --force --dry-run > "$scratch/log" 2>&1
cmp "$receipt_target/scout.source" "$scratch/orphan-source"
cmp "$receipt_target/scout.snapshot" "$scratch/orphan-snapshot"
[ ! -e "$target_home/agents/scout.$extension" ] || fail 'Orphan receipt preflight wrote agent'
[ -z "$(find "$receipt_target" -name '.five-agent-backup.*')" ] || fail 'Receipt dry run wrote backup'
"$fixture/install.sh" --keep-models "${options[@]}" --force > "$scratch/log" 2>&1
source_backup=$(find "$receipt_target" -path '*/.five-agent-backup.*/scout.source')
snapshot_backup=$(find "$receipt_target" -path '*/.five-agent-backup.*/scout.snapshot')
[ -n "$source_backup" ] && [ -n "$snapshot_backup" ] || fail 'Missing orphan receipt backups'
cmp "$source_backup" "$scratch/orphan-source"
cmp "$snapshot_backup" "$scratch/orphan-snapshot"
"$fixture/scripts/smoke-test.sh" "${options[@]}" > "$scratch/log"

# Structural smoke test catches an accidental fifth subagent definition.
cp "$fixture/$source_subdir/scout.$extension" "$fixture/$source_subdir/extra.$extension"
expect_failure "$fixture/scripts/smoke-test.sh" "${options[@]}"
rm "$fixture/$source_subdir/extra.$extension"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
cmp "$target_home/$config_file" "$scratch/original-config"
# Migrate an installation consisting of only our owned copies to a directory link.
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"
rm "$target_home/agents/unrelated.txt"
"$fixture/install.sh" --keep-models "${options[@]}" --dry-run > "$scratch/log" 2>&1
[ ! -s "$scratch/log" ] || fail 'Migration dry run printed output'
[ ! -L "$target_home/agents" ] || fail 'Migration dry run changed agents'
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"
[ -L "$target_home/agents" ] || fail 'Owned copies were not migrated to a directory link'
for role in scout builder verifier operator; do
  [ -f "$target_home/agents/$role.$extension" ] && [ ! -L "$target_home/agents/$role.$extension" ] || fail 'Agent file itself must remain regular'
done
[ -n "$(find "$target_home" -path '*/.five-agent-backup.*/agents/scout.*')" ] || fail 'Missing copied-agent migration backup'
printf '\n# linked update\n' >> "$fixture/$source_subdir/scout.$extension"
cmp "$fixture/$source_subdir/scout.$extension" "$target_home/agents/scout.$extension"
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"
"$fixture/scripts/smoke-test.sh" "${options[@]}" > "$scratch/log"
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
[ ! -L "$target_home/agents" ] || fail 'Uninstall retained directory link'
[ -f "$fixture/$source_subdir/scout.$extension" ] || fail 'Uninstall deleted source agents'
# Fresh installs use directory links as well, without changing client configuration.
"$fixture/install.sh" --keep-models "${options[@]}" > "$scratch/log"
[ -L "$target_home/agents" ] || fail 'Fresh install did not link agents'
"$fixture/uninstall.sh" "${options[@]}" > "$scratch/log"
cmp "$target_home/$config_file" "$scratch/original-config"
printf 'PASS (%s): isolated dry-run, install, idempotence, conflict, backup, ownership, path, structure, and uninstall tests.\n' "$client"
