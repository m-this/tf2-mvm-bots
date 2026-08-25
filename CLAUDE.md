# tf2-mvm-bots

SourcePawn plugin. It lets the TF2 TFBots play Mann vs Machine on the RED team.

- `source/redbots3/` — the plugin. The behaviour actions are in `behavior/`.
- `specs/` — the measurement behind each change. Read it before you change behaviour.
- `docs/` — how the bots fail, the per-class notes, the test-bed metrics.
- `testbed/` — it plays a mission with no players and reports the run.

## How to change behaviour

Do not guess. The test-bed decides. Repeat these steps:

1. Reproduce the bug on the test-bed.
2. Read the run report. If it does not show the bug, add the statistic that does.
3. Make one change.
4. Start `testbed/ab.sh --feature <name>`. It plays the same maps with the change on and off.
5. Compare the two run reports. Keep the change if the numbers improve.
6. If the numbers do not improve, remove the change and try a different one.
7. Go back to step 3 until the numbers are good enough.

A close reason that says "fixed and measured" means you did these steps.

```bash
testbed/build.sh   # build the plugin
testbed/run.sh     # play one mission and write one run report
testbed/sweep.sh   # play every installed map
```

## Triage from Discord

All discussion happens in Discord and no bot reads it. The maintainer copies the
chat here. Turn it into beads.

- Read `bd list` first. Comment on the open bead. Do not create a second one.
- Quote the reporter and give their name. Put your reading under the quote.
- If the message does not show the cause, say so and leave the bead a report.
- Add the label `discord`. Drop the messages that report nothing, then say so.
- Read the close reason before you reopen a bead. It names the trigger measured.

## Beads

Use `bd prime` to list the commands. The prefix is `mvm`. P0 crash, P1 costs a
player a run, P2 bug, P3 polish.

- Git tracks `.beads/issues.jsonl`. Git ignores the Dolt database.
- There is no Dolt remote. A new clone needs `bd init --from-jsonl`.
- Two sessions share one database and can overwrite each other. Check with
  `bd show` before you set a status.
- Do not write a markdown TODO list. TODO.md is now in beads.
