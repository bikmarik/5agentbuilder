# five-agent-build

An on-demand, five-agent engineering workflow for **Codex and Claude Code**.
One lead coordinates investigation, implementation, independent critique, and final checks.

## Install

Clone the repository and open the installer:

```bash
git clone https://github.com/bikmarik/5agentbuilder.git
cd 5agentbuilder
./install.sh
```

Have your chosen client installed and signed in, plus Python 3.11+. Choose Codex or
Claude Code, then pick a model for **each of the five agents**. The installer reads
the available models from your client and shows guidance beside each role. Enter
keeps the current setting. You can also select the client directly:

```bash
./install.sh --target codex
./install.sh --target claude
```

Choices are global for your selected client; CHIEF sets its main-session default.
The Skill links to this checkout, and the agents directory links to configured files
in the client's `.five-agent-build` folder. Keep the clone and rerun the installer
after pulling updates; your choices are preserved. Other agents are left in place.
Installation checks run automatically. Restart your client to load the changes.

Every install offers model selection. To change only models, choose **Change models**
from the menu or run `./install.sh --target codex --models` (or `--target claude`).
For unattended installs, add `--keep-models` to retain existing choices without prompts.

Invoke **`$five-agent-build`** in Codex or **`/five-agent-build`** in Claude Code.
The workflow runs only when you ask for it.

Update or uninstall:

```bash
git pull
./install.sh --target codex --force     # or --target claude
./uninstall.sh --target codex           # or --target claude
```

`--force` backs up conflicts before replacing them. `./install.sh --dry-run` silently
checks both clients without changing files; its exit code indicates success or failure.
Add `--target` to check one client. Use `--help` for custom installation paths.

## Pipeline

**CHIEF is your main conversation.** Four specialists do the work:

| Agent | Job |
| --- | --- |
| SCOUT | Investigate the existing code and check architectural fit |
| BUILDER | Critique the plan, implement, and respond to findings |
| VERIFIER | Challenge correctness and recheck fixes |
| OPERATOR | Run final integration checks |

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

CHIEF plans from SCOUT's findings. BUILDER and VERIFIER critique the plan before
implementation; SCOUT and VERIFIER review the result. BUILDER responds, critics
recheck, and CHIEF resolves disagreements using evidence. OPERATOR runs final checks
before CHIEF reports back. Failed checks return to BUILDER for repair and another review.
Reviews can run in parallel; implementation has one writer.

Merge `templates/AGENTS.md` or `templates/CLAUDE.md` into your project instructions
for project-specific commands and conventions. Run `./scripts/test-install.sh` to
check the installer for both clients.
