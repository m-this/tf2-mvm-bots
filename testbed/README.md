# Test-bed

A Team Fortress 2 server that plays Mann vs Machine with nobody on it, and
writes down what the bots did with every wave.

The mod is judged by play, and play is an opinion until something is counted.
This counts the few things that are not opinions: whether the wave was cleared,
how long it took, how many robots died, how many defenders died, how many of
them died to a knife in the back, and what the engineers lost.

It builds the mod from the working tree, not from a tag. The point is to
measure the change you just made.

The server stack comes from `tf2-archipelago`, which already had a working
Docker build of this mod. What is new here is that nothing is played by a
person and everything is written down.

## Running it

```sh
testbed/run.sh                                   # six waves of Decoy
testbed/run.sh --mission mvm_decoy_advanced      # a named popfile
testbed/run.sh --waves 12 --timeout 3600         # a longer look
testbed/run.sh --out testbed/results/after.jsonl # somewhere to compare against
```

Then compare two runs:

```sh
go run ./testbed/report testbed/results/after.jsonl testbed/results/before.jsonl
```

Needs Docker and Python 3.

The first run needs Team Fortress 2, which is about fourteen gigabytes. On a
machine that already has a server on it, `run.sh` finds
`tf2-archipelago_tf2game` and copies it rather than downloading the game again;
`TESTBED_SEED_FROM=some_volume` names a different one. It is a copy and not a
shared mount on purpose: the test-bed installs its own plugins over `addons/`,
and doing that to the volume a live server is reading ruins the evening for
whoever is playing on it. With nothing to copy from, the game downloads.

The server is left running when the script finishes, because the second run of
the day should not do any of that again. `--down` stops it.

It listens on **27025**, not 27015, so it can share a machine with a server
that is already running. Loopback only: it has no password, no Steam session
and a known rcon password, and it exists to be shouted at by a script.

### Alongside the worklab server

worklab already runs the `tf2-archipelago` stack, deployed by
`ansible-lab/worklab/roles/tf2-archipelago`, and that is where the fourteen
gigabytes come from. The test-bed is deliberately a separate compose project,
on a separate port, with a copy of the game rather than a share of it, so an
apply of that role and a run of this cannot reach each other. Nothing here is
managed by Ansible and nothing here should be: a test-bed that has to be
deployed is a test-bed nobody runs.

The one thing they do share is the machine, so a run competes with whatever the
laptop is doing. Wave durations measured while it compiles something else are
not comparable with wave durations measured while it is idle.

## How a wave starts with nobody playing

This took several wrong answers to get right, so here is the working one.

**A fake client has to hold a seat.** The mod adds its bots in response to a
human pressing F4: its ready listener passes its own bots straight through, and
Mann vs Machine will not begin a wave with nobody ready. An empty server sits in
the pre-round forever. `mvmbots_host.sp` connects one fake client, puts it on
RED, gives it a class and readies it. It has no AI and does nothing else.

**Ready has to be pressed twice.** In `READY_BOTS` mode the first press answers
"Press ready again to start the bots" and does nothing else; the second, within
three seconds, is what spawns them. The mod also rate limits a client to one
command every 0.3 seconds, so the host presses, waits a second, and presses
again.

**Hibernation has to go.** An empty server stops simulating, so no timer runs
and nothing ever adds a bot. The convar is `tf_allow_server_hibernation`, not
the generic `sv_hibernate_when_empty`, which does not exist in Team Fortress 2
and can be set all day without doing anything.

**And one ready player has to be enough**, which is
`tf_mvm_min_players_to_start 1`, with `sm_redbots_manager_min_players -1` to
turn off the mod's own gate, which counts RED before the bots exist.

With all four, the chain runs by itself: host connects, double-readies, the mod
spawns six bots, the bots shop and ready themselves, and the wave begins.

The host is a body in a spawn room and not a seventh bot. The mod counts humans
and its own bots when it decides how many to add, and the host is neither, so
RED ends up with six real bots plus the host. Every `wave_begin` line records
how many of RED were bots, so a results file can always say what it measured.

## What comes out

One JSON object per line, appended as the waves happen. A crashed run still
leaves everything it measured.

```json
{"event":"wave_end","map":"mvm_decoy","wave":3,"result":"cleared","duration":184.2,
 "robot_kills":214,"giant_kills":6,"tank_kills":1,"sentry_kills":63,
 "defender_deaths":9,"backstabs":2,"buster_detonations":1,
 "sentries_lost":2,"dispensers_lost":1}
```

Which of those to read depends on what changed:

| the change             | the number that should move                 |
| ---------------------- | ------------------------------------------- |
| sentry buster reaction | `sentries_lost`, `buster_detonations`       |
| spy checking           | `backstabs`                                 |
| engineer nests         | `sentry_kills` up, `sentries_lost` down     |
| uber deployment        | `defender_deaths`                           |
| stickies, scout jumps  | `robot_kills`, `duration`                   |
| anything at all        | `result` and `duration`                     |

## When the server crashes

`run.sh` greps the container's log for `core dumped` on every poll and stops
with a message rather than waiting out the timeout, because from outside a
crashing server and a slow one look the same: no new results either way.

The first thing the test-bed ever found was a crash in the branch it was built
to measure. That is what it is for. To chase one:

```sh
docker compose -f testbed/compose.yml logs srcds | grep -iE 'core dumped|Segmentation'
```

For a backtrace rather than a guess, run the server by hand with `-debug`,
which writes `tf/debug.log` inside the game volume:

```sh
docker compose -f testbed/compose.yml run --rm srcds \
  bash -c 'cd $STEAMAPPDIR && ./srcds_run -game tf -console -debug \
           -port 27025 -usercon +maxplayers 32 +map mvm_decoy'
```

## How much to believe it

Not much, from one run.

A wave is not deterministic. The bots draw their loadouts, the mod picks their
classes, and a giant that walks left instead of right decides a wave. Two
seconds of difference in one wave's duration is noise. So is one cleared wave.

What is worth something is the clear rate over a dozen waves, and a number that
moves the same way across several runs of the same mission. Run the baseline
twice before believing the first comparison, and if the two baselines disagree
with each other by as much as the change did, the change has not been measured
yet.

The numbers cannot see everything either. A wave cleared by six bots standing
on the hatch is a cleared wave and so is a wave they held at the choke, and only
one of those is the bots playing well. This says whether a change helped. It
does not say whether the bots look right, and somebody still has to watch them.

## Files

| file                    | what it is                                            |
| ----------------------- | ----------------------------------------------------- |
| `run.sh`                | brings the server up, runs the mission, reads results  |
| `report/`               | turns a results file into a table, and compares two    |
| `build.sh`              | stages the mod and its dependencies from this tree     |
| `seed-volume.sh`        | copies an existing game install into the test-bed's    |
| `Dockerfile`            | the server image                                       |
| `compose.yml`           | one service, loopback only                             |
| `entrypoint.sh`         | installs into the game volume, writes `server.cfg`     |
| `stats/mvmbots_stats.sp`| the plugin that counts                                 |
| `stats/mvmbots_host.sp` | the fake client that holds a seat and readies up       |
| `rcon.py`               | Source RCON client, from tf2-archipelago               |
| `versions.env`          | every pinned version                                   |

`build/` and `results/` are working directories and are not committed.
