# Project Instructions for AI Agents

## What this is

SourcePawn plugin giving TF2's TFBots the behaviour to play Mann vs Machine on
the RED team: nests, upgrades, shopping between waves, teleporters, and the
per-class play that makes a seat worth filling.

- `source/redbots3/` — the plugin. Behaviour actions live under `behavior/`.
- `gamedata/`, `configs/` — signatures and per-map data.
- `specs/` — the reasoning and measurements behind a change. Read the relevant
  spec before touching behaviour; most decisions here were measured, not guessed.
- `docs/` — how the bots break, per-class notes, test-bed metrics.
- `testbed/` — plays a mission with nobody on the server and reports on the run.

`sp.toml` lists the include dependencies. CI is `.github/workflows/main.yml`.

## Build and test

```bash
testbed/build.sh            # build the plugin
testbed/run.sh              # play one mission and write a run report
testbed/sweep.sh            # play every installed map
testbed/sweepreport/        # read a whole sweep
```

`testbed/README.md` has the detail. `docs/testbed-metrics.md` explains what the
numbers in a run report mean.

A behaviour change is not done until the test-bed measured it. "Fixed and
measured" in a close reason means exactly that, and it is the standard here.


## Triage from Discord

All user-facing discussion for this project happens in Discord. There is no bot
and no export: nobody working in this repo can read it directly. The workflow is
copy-paste. The maintainer pastes raw chat, an agent turns it into beads.

When you are handed a paste:

- **Match before you create.** Run `bd list` and check the paste against what is
  already there. A new symptom for an open bead is a `bd comment`, not a second
  bead. Duplicates are the main way this backlog rots.
- **Keep the reporter's words.** Paste the complaint verbatim into the
  description, with the reporter's name, and put your reading of it underneath.
  The quote is evidence and it outlives your interpretation of it.
- **Do not invent a diagnosis.** If the cause is not obvious from the message,
  say so and leave the bead a report. A confident wrong root cause is worse than
  an open question.
- **Label it `discord`** so chat-sourced items stay separable.
- **Route by repo.** Where the symptom appeared is not where the bug lives; the
  wave-loss money bug surfaced in the mod and belonged to the launcher.
- **Most of it is noise.** Thanks, jokes and chatter get dropped. Say what you
  dropped so the maintainer can pull anything back.

A report that contradicts a closed bead is worth more than a new one. Check the
close reason before reopening: it usually names the trigger it was measured
against, and the new report often turns out to be that same trigger described
differently.

## Beads conventions here

- Prefix `mvm`. Priorities: P0 crashes and data loss, P1 bugs that cost a
  player a run, P2 everything else that is broken, P3 features and polish.
- `.beads/issues.jsonl` is committed and auto-exported on write. The Dolt
  database under `.beads/` is gitignored.
- **No Dolt remote is configured**, so the JSONL is the only thing that crosses
  machines. A fresh clone has no issues until someone runs `bd init --from-jsonl`.
  Do not treat the JSONL as live state in a working checkout; `bd` reads Dolt.
- The database is shared and last-write-wins. If another session is working the
  same repo, re-read a bead with `bd show` before overwriting its status.
- Do not add a markdown TODO list. TODO.md was migrated into beads and deleted
  on purpose; the closed-work narrative lives in `docs/`.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
