# Five-agent engineering for Codex and Claude Code

A portable engineering workflow packaged as an **explicit-only Skill**, with four
custom specialists. It runs when you request it, not automatically because a task
looks substantial. Bash scripts support macOS and Linux without Python, Node, or an
orchestration service.

The idea: your main conversation (CHIEF) coordinates investigation by SCOUT,
implementation by BUILDER, independent review by VERIFIER, and final checks by
OPERATOR. Specialists challenge plans and changes with evidence; CHIEF resolves
disagreements. Invoke `$five-agent-build` in Codex or `/five-agent-build` in Claude Code.

There are exactly **five logical roles**: CHIEF, SCOUT, BUILDER, VERIFIER, OPERATOR.
**CHIEF is your primary conversation**, not a custom subagent. There is no
`chief.toml` or `chief.md`. Codex TOML and Claude Markdown files are two representations
of the same four specialists, not additional agents.

```text
                       USER
                        │
                        ▼
                      CHIEF
                 primary conversation
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
      SCOUT          BUILDER         VERIFIER
        \               ↕               /
         \──────── critique loop ──────/
                        │
                        ▼
                    OPERATOR
                        │
                        ▼
                      CHIEF
                        │
                        ▼
                       USER
```

| Resource | Purpose |
| --- | --- |
| Skill | How we work: phases, critique, rebuttal, adjudication |
| Custom agents | Who performs specialist work |
| Project `AGENTS.md` / `CLAUDE.md` | What this specific repository requires |

## Explicit invocation

| Client | Invoke | Automatic activation disabled by |
| --- | --- | --- |
| Codex | `$five-agent-build` | `policy.allow_implicit_invocation: false` in `agents/openai.yaml` |
| Claude Code | `/five-agent-build` | `disable-model-invocation: true` in Skill frontmatter |

These controls disable automatic Skill loading, not every form of delegation the
client supports. They do not disable built-in subagents or other installed skills.
The workflow body also limits invocation to the requested task rather than carrying
it into unrelated later tasks. Claude specialist descriptions scope their use to
explicit workflow/specialist requests; descriptions are guidance, not an access control.
If you previously copied an automatic-workflow reminder into global or project
instructions, replace it with the opt-in template below.

Sources: [Codex skill configuration](https://learn.chatgpt.com/docs/build-skills),
[Claude Code invocation controls](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill).

## Install

Keep the clone in a stable location. Run without arguments for an interactive menu:

```bash
./install.sh
```

Choose Codex or Claude Code installation, an update with conflict backups, or a
read-only preview. Enter `h` for command-line options or `0`/Enter to exit. Invalid
choices prompt again; closed input cancels. Without terminal input the installer
prints the menu and exits without changes, so scripts must pass explicit options.

For a direct Codex installation:

```bash
./install.sh --dry-run
./install.sh --target codex
./scripts/smoke-test.sh
```

For Claude Code:

```bash
./install.sh --target claude --dry-run
./install.sh --target claude
./scripts/smoke-test.sh --target claude
```

For both, run both installations. Each manages its own destinations independently.
`--target` accepts exactly `codex` or `claude`.
With explicit options but no `--target`, Codex remains the default.

| Target | Regular agent files | Skill directory link |
| --- | --- | --- |
| Codex | `${CODEX_HOME:-$HOME/.codex}/agents/{scout,builder,verifier,operator}.toml` | `$HOME/.agents/skills/five-agent-build` |
| Claude Code | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents/{scout,builder,verifier,operator}.md` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/five-agent-build` |

All agent files are **regular copies**. Symlinked Codex agents have been reported
as unavailable even when their TOML is valid; see
[the upstream report](https://github.com/openai/codex/issues/40131).
Skill directories remain linked, so keep this clone in place.

Matching owned copies and the Skill link are unchanged on repeat installation.
Existing agent symlinks, unowned copies, modified files, updates, and conflicting
receipts require `--force`. All conflicts are checked before writing. Preview first:

```bash
./install.sh --target claude --force --dry-run
./install.sh --target claude --force
```

Each replaced resource is backed up in a unique `.five-agent-backup.*` directory
next to it; paths are printed and backups are never automatically removed. The
installer does not edit `config.toml`, `settings.json`, credentials, global
instructions, or unrelated agents. It does not install either client. Restart your
client after installation; fully quit/reopen Codex when refreshing custom agents.

Custom absolute roots, including paths with spaces, are supported:

```bash
./install.sh --codex-home "/path/to/codex home" --skills-dir "/path/to/codex skills"
./install.sh --target claude --claude-home "/path/to/claude home"
```

Claude's default skill path follows `--claude-home`. `--skills-dir` overrides the
selected client's skill destination, but does not configure client discovery. Use
a directory your client actually scans, and pass the same options to smoke/uninstall.
Use separate client roots. Wrong-client home flags are rejected. Required commands
are Bash 3.2+ and standard Unix utilities. Do not use `sudo` or run installers
concurrently. Managed target directories and receipt files cannot be symlinks.

## Uninstall and update

```bash
./uninstall.sh --dry-run
./uninstall.sh
./uninstall.sh --target claude --dry-run
./uninstall.sh --target claude
```

Only unchanged agent copies owned by this checkout and its matching Skill link are
removed. Each client root has a `.five-agent-engineering` receipt directory recording
source paths and installed bytes. This lets uninstall recognize unchanged old copies
after a repository update while preserving locally edited files. Missing or incomplete
receipts never establish ownership. Receipt conflicts also require force and backups.

The Skill was renamed from `five-agent-engineering` to `five-agent-build`. Installation
removes the old Skill link only when it points exactly to this checkout's former
Skill path, and only after the new installation succeeds. Foreign links and real
directories with the old name are preserved. Dry runs report migration without
changing either link. The internal `.five-agent-engineering` receipt directory keeps
its original name so existing agent ownership survives the rename.

User-modified files, foreign/legacy links, backups, unknown receipt files, and client
configuration remain. Byte-identical replacement cannot be distinguished from the
original installed copy. Uninstall before moving/deleting the clone; a new clone
cannot claim old ownership. Use force with backups to adopt the new location.

After reviewing and pulling updates, rerun each installed target:

```bash
git pull --ff-only
./install.sh --force
./install.sh --target claude --force
./scripts/smoke-test.sh
./scripts/smoke-test.sh --target claude
```

Agent updates require installation; Skill edits are visible through links. Restart
clients to refresh metadata and agents. Interrupted installation may leave partial
copies or receipts; inspect printed paths and use `--force` to recover. Installation
is preflighted and repeatable, not a transaction across all files.

## Repository structure

```text
.
├── README.md, LICENSE, .gitignore
├── install.sh, uninstall.sh
├── agents/{scout,builder,verifier,operator}.toml
├── skills/five-agent-build/
│   ├── SKILL.md
│   ├── agents/openai.yaml
│   └── references/{critique-protocol,workflow}.md
├── claude/
│   ├── agents/{scout,builder,verifier,operator}.md
│   └── skills/five-agent-build/
│       ├── SKILL.md
│       └── references -> ../../../skills/five-agent-build/references
├── templates/{AGENTS,CLAUDE}.md
└── scripts/{common,smoke-test,test-install}.sh
```

The two Skill entrypoints have the same workflow body and client-specific metadata;
tests enforce body parity. Reference documents are shared through a relative link.
When editing the workflow body, update both entrypoints together. Keep the four
role representations aligned when changing specialist responsibilities.

## How the critique loop works

Scout investigates before Chief drafts a plan. Builder critiques feasibility and
Verifier critiques correctness before implementation. Chief resolves objections
using evidence, then assigns bounded implementation to Builder. Scout and Verifier
independently inspect the actual changes. Builder answers every finding. Rejected
or partially accepted findings return to the original critic for reconsideration.
Chief records ACCEPTED, PARTIALLY ACCEPTED, or REJECTED with justification.

Verifier rechecks fixes. Operator then runs repository-level integration checks.
Blockers return through Chief to Builder, Verifier when correctness changes, and
Operator for another check. Unresolved blockers stop completion. There is no vote,
no manufactured dissent, and no requirement to invent a bug in a clean review.

CHIEF routes communication without relying on direct peer messaging:

```text
Scout → Chief → Builder
Builder → Chief → Verifier
Verifier → Chief → Builder
```

Parallel independent critiques are encouraged. Builder is the only feature-code
writer. Pause writes during review and integration; do not overlap checks that
mutate shared resources. Serialize if concurrency slots are scarce. This workflow
has one Builder role; future multi-writer workflows would require isolated worktrees.
Trivial edits receive proportionate checks; review-only and plan-only requests stop
at their requested boundaries. Works across Rust, Go, C++, TypeScript, Python, and
mixed repositories by using project-specific commands.

## Client capabilities and limits

Codex inspection on 2026-09-29 used local `codex-cli 0.155.0-alpha.16.4`, CLI help,
feature listing, and official documentation. Standalone TOMLs use `name`,
`description`, `developer_instructions`, and `sandbox_mode`. Scout/Verifier default
to `read-only`; Builder/Operator to `workspace-write`. Model and reasoning overrides
are supported but omitted here. Parent runtime permissions can override defaults.
See [Codex custom agents](https://learn.chatgpt.com/docs/agent-configuration/subagents).

Optional Codex settings may be manually merged into an existing `[agents]` table:

```toml
[agents]
enabled = true
max_concurrent_threads_per_session = 4
```

This excludes the primary thread; `agents.max_threads` is the legacy alias.
The installer does not change concurrency. See the
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).

Claude definitions use Markdown with YAML `name`, `description`, and `tools`.
Scout/Verifier allow only Read, Grep, Glob: they cannot execute tests, so they must
report that limit and route shell reproductions through Chief. Builder additionally
has Bash, Edit, Write; Operator has Bash. Shell access can write files; Operator's
feature-edit restriction is behavioral. No elevated permission mode, model pin, or
nested delegation tool is granted. See [Claude custom agents](https://code.claude.com/docs/en/sub-agents).
Personal paths follow [Claude's configuration directory](https://code.claude.com/docs/en/claude-directory).

Claude Code was not installed on the development machine. Its formats and paths
were checked against official documentation and isolated installation tests, not
a live Claude run. This targets **Claude Code**, not Claude web chat or Cowork.
Neither client's filesystem checks prove runtime role discovery. Built-in roles
remain available; the workflow itself uses exactly its four specialists.

## Project instructions

Merge `templates/AGENTS.md` for Codex or `templates/CLAUDE.md` for Claude Code into
existing project instructions. Replace placeholders with architecture, commands,
and constraints. Do not overwrite existing instructions or duplicate the entire Skill.
Codex layers applicable instructions as described in
[AGENTS.md discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

Optional reminder, merged manually into existing global/project instructions:

```markdown
Use the five-agent-build Skill only when the user explicitly requests it.
Do not activate the workflow automatically based on task size.
Never simulate named subagents when the workflow requires actual delegation.
```

No instruction files are installed automatically.

## Example prompts

In Codex:

```text
$five-agent-build
Implement portfolio-level risk allocation.
```

In Claude Code:

```text
/five-agent-build Refactor the execution engine to separate order generation
from exchange IO. Do not implement until the plan has been critiqued.
```

After explicitly invoking the Skill in either client:

```text
Find and fix the race condition causing duplicate orders.
Use Scout to investigate before making assumptions.
Use Verifier to try to reproduce the bug independently within its tool permissions.
```

```text
Do not modify anything.
Use Scout and Verifier to independently review the current authentication system.
Have Chief reconcile disagreements and report the findings.
```

## Validation and conversational smoke test

Every installation and update automatically runs the smoke test for the selected
client, including repeat installs and custom paths. It checks the four installed
agents, ownership records, Skill link, metadata, and explicit-only setting. A failure
returns a nonzero exit status and retains files and backups for inspection; it does
not report success or roll back automatically. Dry runs skip the installed-file test.
No model calls are made: live agent invocation still needs the conversational test.
The full isolated installer regression suite remains a separate developer check.

```bash
./scripts/test-install.sh                    # isolated tests for both clients
./scripts/test-install.sh --target claude    # one client only
./scripts/smoke-test.sh                      # real Codex installation
./scripts/smoke-test.sh --target claude       # real Claude installation
```

Tests use disposable directories. They cover dry runs, regular copies, legacy link
migration, updates, backups, source changes, local edits, foreign ownership, malformed
receipts, uninstall, invocation controls, and workflow parity. Smoke checks validate
basic metadata, required references, four regular owned agent copies, the Skill link,
and explicit-only policy. They are not full TOML/YAML parsers or runtime tests.

Start a fresh client session and invoke `$five-agent-build` in Codex or
`/five-agent-build` in Claude Code, then supply:

```text
Do not modify project files.
1. Spawn Scout and inspect this repository.
2. Chief proposes one meaningful improvement.
3. Builder critiques the plan.
4. Verifier independently critiques the plan.
5. Chief adjudicates the objections.
6. Stop before implementation.
Report which real named agents were invoked and their identifiers.
Do not simulate an agent response in the primary thread.
```

Check actual subagent activity/tool events, not just prose saying “Scout invoked.”
“Scout would probably say...” and invented specialist responses are prohibited.
The plan-only test intentionally excludes Operator; test it on a small authorized
implementation after review passes. In Claude Code, `/agents` also helps inspect
loaded specialist definitions. Restart when client changes are not reflected.

## Troubleshooting

- **Workflow runs unasked:** restart to reload invocation metadata; remove old
  automatic-workflow reminders from instructions. Check for another installed copy.
- **Missing roles:** ensure agents are regular files in the selected client root;
  check project overrides and client support. Restart the client. Never fake a role.
- **Missing Skill:** check the chosen discovery path, duplicate names, and disabled
  client settings. A custom `--skills-dir` does not configure discovery.
- **Denied tests:** report the unrun check accurately and route an authorized run
  through Chief. Read-only Claude reviewers intentionally have no shell tool.
- **Install conflict:** inspect the file before using force; backups are printed.
  Invalid receipt node types/symlinks require manual inspection, even with force.
- **Clone moved:** restore its location for uninstall or inspect exact stale
  resources manually. Never recursively delete a client configuration directory.
- **Too few slots:** serialize work. Five logical roles need not run simultaneously.
- **Cost/platform:** extra agents consume time and tokens. No Windows/PowerShell
  support or client installation is bundled. The workflow is instructions, not a
  deterministic state machine or a global prohibition on other agents.

MIT licensed; the original repository copyright notice is preserved.
