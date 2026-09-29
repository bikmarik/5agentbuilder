# Codex five-agent engineering

A portable, Bash-and-Markdown engineering workflow for macOS and Linux. Keep this
repository in a stable location, install it once, and use it across software projects.
No Python, Node, orchestration server, or framework is required.

Exactly **five logical agents** participate: **CHIEF, SCOUT, BUILDER, VERIFIER,
OPERATOR**. CHIEF is the primary Codex thread you interact with. There is no
`chief.toml`: the main thread already orchestrates and communicates with you.
Only Scout, Builder, Verifier, and Operator are custom subagents.

```text
                       USER
                        │
                        ▼
                      CHIEF
                 primary Codex thread
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
| Project `AGENTS.md` | What this specific repository requires |

## Verified Codex capabilities

Inspected on 2026-09-29 with local `codex-cli 0.155.0-alpha.16.4`:
`codex --version`, `codex --help`, `codex features list`, and
`codex debug prompt-input --help`. No standalone configuration schema was located
in the application resources. The following official documentation was also read;
older clients may differ.

| Capability | Supported configuration used here |
| --- | --- |
| Personal custom agents | `$CODEX_HOME/agents/*.toml`, default `~/.codex/agents/` |
| Standalone agent fields | `name`, `description`, `developer_instructions` |
| Per-agent sandbox | `sandbox_mode = "read-only"` or `"workspace-write"` |
| Optional model settings | `model`, `model_reasoning_effort`; omitted here to inherit |
| Personal skills | `$HOME/.agents/skills/<name>/SKILL.md` |
| Skill metadata | YAML frontmatter containing `name` and `description` |

Sources: [custom agents and permissions](https://learn.chatgpt.com/docs/agent-configuration/subagents),
[skill discovery and format](https://learn.chatgpt.com/docs/build-skills).
The older `$CODEX_HOME/skills` location remains visible in this machine's skill
catalog, but the installer defaults to the currently documented personal location.
Do not install duplicates in both locations.

Optional settings can be **manually merged into the existing** `[agents]` table:

```toml
[agents]
enabled = true
max_concurrent_threads_per_session = 4
```

The limit excludes the primary thread. `agents.max_threads` is a legacy alias.
The installer does not change either setting. See the
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
A concurrency ceiling does not enforce role identities or guarantee four slots.

Codex invokes specialists through its available subagent tools following the Skill's
instructions. Tool signatures vary by host; the Skill requires actual custom-role
selection, not just a role-shaped task label. Parent live permission overrides can
supersede agent defaults. Built-in Codex agents remain present, but this workflow
uses only its four specialist roles. It does not disable unrelated user agents.
See [subagent orchestration](https://learn.chatgpt.com/docs/agent-configuration/subagents).

## Install

Clone this repository to a stable directory, enter the clone, then run:

```bash
./install.sh --dry-run
./install.sh
./scripts/smoke-test.sh
```

The installer creates five absolute symlinks: four agent TOMLs under
`${CODEX_HOME:-$HOME/.codex}/agents`, and the Skill directory under
`$HOME/.agents/skills`. It prints each source and destination. Keep the clone in
place: symlinks deliberately make `git pull` updates visible without recopying files.
Restart Codex after installing and run the conversational smoke test below.

Existing matching links are unchanged. Any conflict aborts preflight before writing.
To replace conflicting files, directories, or links **with a backup first**:

```bash
./install.sh --force --dry-run
./install.sh --force
```

Backups are retained in uniquely named `.five-agent-backup.*` directories next to
the destination and printed individually. They are never deleted automatically.
Inspect and restore them manually after uninstalling if desired. Installation does
not touch `config.toml`, global instructions, credentials, or unrelated agents.
No Codex executable or login is needed merely to install the resources.

Explicit absolute targets are supported (including spaces):

```bash
./install.sh --codex-home "/path/to/codex home" --skills-dir "/path/to/skills"
```

`--skills-dir` is a destination override, not a Codex discovery setting. For real use,
select a location your Codex client discovers. `CODEX_HOME` changes the agent root;
it does not change the default personal skill root. Use the same overrides when
uninstalling or smoke-testing. Required commands are standard Bash 3.2+ and Unix
utilities; missing commands produce an error. Do not run installers concurrently
or use `sudo`. Managed target directories must not themselves be symlinks.

## Uninstall and update

```bash
./uninstall.sh --dry-run
./uninstall.sh
```

Only the five symlinks pointing exactly into **this checkout** are removed. Files
replaced by the user, foreign links, backups, directories, and configuration remain.
Run uninstall before deleting/moving the clone. To move it, uninstall from the old
location and install from the new one. A different clone cannot claim ownership of
the old links; `--force` installation backs them up before adopting the new location.

To update, inspect/pull changes into the existing clone, then:

```bash
git pull --ff-only
./install.sh --dry-run
./install.sh
./scripts/smoke-test.sh
```

Because links are live, reviewed changes take effect from the clone immediately;
restart Codex to reload agents. An interrupted install can leave a partial set of
links and retained backups; rerun the installer to complete it. The operation is
preflighted and repeatable, not a cross-filesystem transaction.

## Repository structure

```text
.
├── README.md
├── LICENSE
├── .gitignore
├── install.sh
├── uninstall.sh
├── agents/
│   ├── scout.toml
│   ├── builder.toml
│   ├── verifier.toml
│   └── operator.toml
├── skills/five-agent-engineering/
│   ├── SKILL.md
│   └── references/
│       ├── critique-protocol.md
│       └── workflow.md
├── templates/AGENTS.md
└── scripts/
    ├── common.sh
    ├── smoke-test.sh
    └── test-install.sh
```

## Critique loop

Scout investigates before Chief drafts the plan. Builder critiques feasibility and
Verifier critiques correctness before implementation. Chief resolves objections
using evidence and revises the bounded assignment. After Builder implements, Scout
and Verifier independently inspect the actual changes. Builder must answer every
finding; rejected or partially accepted findings return to the original critic for
reconsideration. Chief adjudicates remaining disputes with explicit ACCEPTED,
PARTIALLY ACCEPTED, or REJECTED decisions and justification.

Verifier rechecks fixes. Only then does Operator run repository-wide checks. An
integration blocker returns through Chief to Builder, then Verifier when behavior
changes, then Operator for another check. Only Chief reports overall completion.
Unresolved blocking findings stop progression and are reported honestly.

Direct free-form subagent-to-subagent communication may not be available. Chief is
the router and adjudicator:

```text
Scout → Chief → Builder
Builder → Chief → Verifier
Verifier → Chief → Builder
```

There is no vote and no obligation to disagree. Concrete reproducible evidence wins.
A clean review is valid after serious attempts to falsify correctness.

Scout and Verifier normally stay read-only. Builder is the feature-code writer.
Operator runs checks after review, including checks that generate local artifacts,
but routes feature repairs back to Builder. Parallel plan critiques and independent
reviews are encouraged; concurrent writes to the shared working tree are prohibited.
Serialize if slots are scarce. This repository defines one Builder role; a future
workflow with multiple writers would require isolated Git worktrees.

The full workflow is for substantial work across Rust, Go, C++, TypeScript, Python,
and mixed repositories. Trivial mechanical changes get proportionate checks.
Review-only and plan-only requests stop at their requested boundaries.

## Add project instructions

Merge [templates/AGENTS.md](templates/AGENTS.md) into an existing project file.
For a project without one, copy the template and replace its placeholders with
architecture, test/lint/format/build commands, and constraints. Do not overwrite
existing instructions or copy the whole Skill into every project.

Codex layers global instructions with project instructions from the repository root
toward the working directory; `AGENTS.override.md` takes precedence at each level.
See [AGENTS.md discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

Optionally merge this tiny reminder into `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`:

```markdown
For substantial software-engineering tasks, use the
`five-agent-engineering` Skill when appropriate.

Never simulate named subagents when the workflow requires actual delegation.
```

The installer never writes this global instruction file.

## Example prompts

```text
Implement portfolio-level risk allocation.

Use the five-agent engineering workflow.
```

```text
Refactor the execution engine to separate order generation from exchange IO.

Use the full five-agent workflow.
Do not implement until the plan has been critiqued.
```

```text
Find and fix the race condition causing duplicate orders.

Use Scout to investigate before making assumptions.
Use Verifier to try to reproduce the bug independently.
```

```text
Do not modify anything.

Use Scout and Verifier to independently review the current authentication system.
Have Chief reconcile disagreements and report the findings.
```

You can also explicitly mention `$five-agent-engineering` in Codex.

## Validation and smoke tests

Run the isolated install/uninstall regression suite; it uses disposable directories,
never your real Codex installation:

```bash
./scripts/test-install.sh
```

After installation, `./scripts/smoke-test.sh` checks the four-file agent set, required
resources, basic metadata, shell syntax, and the five owned, non-broken links. It
does not parse arbitrary TOML or prove agent registration, sandbox enforcement, or
successful model calls. For actual runtime verification, use this prompt in a new
Codex session:

```text
Do not modify project files.

Use the five-agent engineering workflow.

1. Spawn Scout and inspect this repository.
2. Chief proposes one meaningful improvement.
3. Builder critiques the plan.
4. Verifier independently critiques the plan.
5. Chief adjudicates the objections.
6. Stop before implementation.

Report which real named agents were invoked.
Do not simulate an agent response in the primary thread.
```

Inspect actual subagent activity/tool events and returned session identifiers:

```text
Scout subagent invoked
Builder subagent invoked
Verifier subagent invoked
```

Text alone is not proof. The following are prohibited substitutes:

```text
"Scout would probably say..."
"Builder thinks..."
```

The plan-only smoke test intentionally does not invoke Operator. Validate Operator
on a small authorized implementation task after both implementation reviews pass;
confirm its real activity and integration report. Do not claim full runtime coverage
from a filesystem check or from the plan-only test.

## Troubleshooting and limitations

- **Roles missing:** restart Codex, inspect the links, check the active `CODEX_HOME`,
  project role overrides, and your client's support for standalone custom agents.
  Upgrade an older client using its supported distribution. This repository does
  not auto-convert older role-registration formats or invent unsupported keys.
- **Skill missing:** check the documented personal skill directory, duplicate skill
  names, and disabled entries under `skills.config`. A custom destination alone
  does not make Codex discover it.
- **Delegation unavailable:** check whether `agents.enabled` is disabled or the host
  exposes named-role selection. Report the limitation; never fake specialist output.
- **Too few slots:** reuse or close inactive sessions where supported and serialize
  independent critiques. Five logical roles do not require five simultaneous tasks.
- **Read-only tests cannot run:** report the denied check and arrange an authorized
  isolated run. Do not turn a blocked check into PASS. Parent runtime overrides and
  connector permissions mean sandbox defaults are not an absolute feature-code ACL.
- **Install conflict:** inspect the destination before choosing `--force`. The backup
  path is printed. Uninstall keeps foreign/replaced resources by design.
- **Clone moved/deleted:** restore its location to uninstall, or inspect and manually
  remove the exact stale links. Never recursively delete a Codex directory.
- **Scope and cost:** extra agents consume tokens and time. The protocol is a Skill,
  not a deterministic state machine or a technical restriction on built-in roles.
- **Platform support:** Bash scripts target macOS/Linux. Windows/PowerShell is not
  provided. No model is pinned; availability and reasoning support vary by account.

MIT licensed; the existing repository copyright notice is preserved.
