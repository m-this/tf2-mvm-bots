# What the testbed measures

`testbed/run.sh` plays a mission with nobody in it and writes one JSON object
per line to `testbed/results/`. `go run ./testbed/report <file>` turns that into
prose; a second file argument compares two runs.

Facts go in the file, verdicts go in the report. Changing your mind about what
counts as a useless dispenser should cost a recompile, not another run.

## The lines

| `event` | One per | What it answers |
|---|---|---|
| `wave_end` | wave | did the team hold, who did the damage, what killed them |
| `wave_begin` | wave | what the between-rounds time bought |
| `engineer` | engineer, twice a wave | what he had standing and where |
| `perf` | wave | frame times, and the worst frame with a timestamp |
| `stall` | frame over 250 ms | when the server hitched |
| `bot` | bot, every 5 s | where he was and what he was doing |
| `building` | building, every 5 s | where it was and whether it was worth its metal |

`bot` and `building` sample in **both** round states. Half of what has gone
wrong went wrong between waves — the walk to the front, the shopping trip, the
toolbox still set to the last building — so sampling only during a wave samples
the half that was never the problem.

## Reading the bot samples

```
what the bots were doing (312 samples)
  Wesley       medic     DefenderMedicHeal 71%, DefenderGotoUpgrade 18%, none 11%
                         beam on somebody 44% of the time
                         secondary 88%/primary 12%, hurt 9% of the time
```

- **the action share** is where the time went. A bot stuck in a house shows as
  one action at 90% with nothing to show for it.
- **beam on somebody** is the medic's actual output. Following a patient and
  healing him are different things and this is the only number that separates
  them.
- **the weapon slot share** answers "is the Heavy using his minigun or his
  shotgun" without anyone watching him.

## Reading the building samples

```
  Bob sentry         level 3, saw a robot 61% of samples (1.8 at a time), 1.2 teammates in range
  Bob dispenser      level 3, saw a robot  4% of samples (0.1 at a time), 2.4 teammates in range
  Bob mini sentry    level 1, saw a robot  8% of samples (0.2 at a time), 0.1 teammates in range
```

- **saw a robot** is a sentry's worth. It traces to every live robot in range,
  so it is line of sight and not just distance. A sentry that never saw one is
  in the wrong place however healthy it is.
- **teammates in range** is a dispenser's worth. That is the question the
  hand-walked `DispenserSpot` entries in `configs/defenderbots/map/` exist to
  answer, and nothing checked it before.
- **two rows for one owner and one building type** means a duplicate, which is
  a real bug that happened and survived four waves.

## Self-damage

`hurt themselves` and `killed themselves` on the wave line, per class. A soldier
firing rockets at a tank he is standing against looks, on any scoreboard, exactly
like a soldier who fought hard and got shot: damage up, kills up, deaths up.
This is the column that tells them apart, and it is comparable between builds.

Printed only when non-zero.

## Cost

Six bots and five buildings at five seconds is roughly 130 lines a minute. The
results directory is gitignored. A `bot` line carries the whole behaviour stack,
so keep `STATS_LINE_LENGTH` ahead of it.

## Gotchas paid for already

- **`ActionsManager.Iterator` throws on a client that is not a NextBot**, and a
  thrown native takes the whole callback with it. `mvmbots_host` parks an
  ordinary fake client on RED to hold a seat, so the first client of every pass
  killed the pass and the file never appeared. Guarded by `HasBehaviour`.
- **Sample off the frame hook, not a timer.** A timer without
  `TIMER_FLAG_NO_MAPCHANGE` dies with the map, and one created in
  `OnPluginStart` is created once. That produced a results file with a sample
  count of zero for every engineer on every map — a measurement that says
  nothing and looks like a measurement.
- **`docker logs` retains history across container restarts.** One crash in the
  morning read as a crash in every run for the rest of the day until the check
  grew a `--since`.
- **Do not edit a shell script while it is running.** `sh` resumes at a byte
  offset; the tail of the old file becomes a new command.
