# TODO

What the bots still need. Every item says where it stands and what blocks it.

The 1.3 play-test report, what the code actually did about each complaint, and
what was changed, is in `specs/playtest-1.3.md`. This file is what is left.

## Done since 1.3

One line each. The spec has the detail and the reasoning.

- Engineers buy for their primary and secondary, ranked under the sentry.
- Sentry busters: the engineer hauls the sentry out of the way, everybody else
  runs. The evade action existed and had never once run.
- The wrangler comes out for the shield, not only for the reach.
- Nests have a minimum distance from the bomb, and are scored on how much of
  the approach they can actually see rather than one trace to one point.
- Nest spots are read from the map's own `bot_hint_sentrygun` entities.
- Medics deploy by medigun type instead of by panic.
- Upgrades are bought several tiers at a time, which is one chat line each.
- Scouts jump.
- Demomen use the sticky launcher, lay a trap with it, and detonate it.
- Spy checking: paranoia from the last sighting, suspect the teammate who was
  not there a moment ago.
- Rockets aim at the ground when the splash pays. That was written for a code
  path that is not compiled.
- Bots stop riding a teleporter backwards to reach its entrance.
- `testbed/` measures a run: waves cleared, how long, who died to what. It
  plays a mission with nobody on the server.
- Six maps carry hand written nest, dispenser and teleporter exit data, walked
  in game rather than guessed. See item 3.
- Engineers place dispensers on authored spots, and skip one another engineer
  already occupies.
- Engineers re-score their nest when a wave ends and haul to a better one.
- Rottenburg's two conditional nests work: `NestTankOnly` and `NestNoTank`,
  decided by the wave's class icons rather than by looking for a live tank.
- `PickBuildArea` skips `BLOCKED` areas. Only `PickBuildAreaPreRound` did.
- `GetBombInfo` tested `BLUE_SPAWN_ROOM` twice where it meant `RED_SPAWN_ROOM`,
  in two places, so RED spawn counted toward the length of the bomb path.

## 1. The crash. Fixed, and it was the test-bed's own entrypoint

`testbed/entrypoint.sh` installed the staged tree with `cp -r`, every thirty
seconds, for as long as the server ran. `cp` truncates the destination before
it writes it. Truncating a file the running server has mapped invalidates the
pages under it, so the next instruction the game executes out of that extension
is a `SIGBUS`, or a `SIGSEGV` once it is running a half written one.

The fix is one flag. `cp -ru` compares the timestamp, the staged tree never
changes, and nothing is rewritten after the first copy. The script this one was
adapted from, `deploy/bots/build.sh` in tf2-archipelago, has always had it, and
carries the comment saying why. Dropping it is what took a day.

Before: five or six crashes in ten minutes, with no plugin loaded and nobody
connected. After: ten minutes, no crash, thirteen bots on the server and every
extension loaded.

Worth keeping, because none of it was obvious from the symptom:

- The crash names whichever library the loop happened to rewrite, so it moved
  between `cbasenpc.ext` and `rip.ext` as the run changed. Every backtrace
  pointed at the first instruction of some extension's frame hook, which reads
  like that extension is broken.
- Every experiment that "fixed" it worked by taking a file out of the staged
  tree, which stopped the loop rewriting it. That is why removing the plugins
  looked like it cleared the crash, and why removing CBaseNPC did.
- The Windows server under Wine ran clean for twenty-seven minutes, which read
  as a platform difference. It was not: that run had no supervising loop at all
  because it was started by hand.
- The tf2-archipelago server on this machine looked like a working control and
  was not one. It has no CBaseNPC and no defender bots installed, only
  `tf2_archipelago.smx`, so it was never running the thing under test.

Two other things were wrong in here and are fixed:

- `seed-volume.sh` copied the source server's `tf/addons` as well as the game.
  The game only now, so the image seeds `addons/` from its own layers.
- Nothing installed the game. The image carries SourceMod and the server
  scripts, not the fifteen gigabytes, and every run so far had seeded a volume
  from another server. A clean run exited 127 on a missing `srcds_run`.
  `install-game.sh` downloads it, and `run.sh` calls it.

To get a backtrace, if this is ever needed again: launch the server under gdb
directly and turn symbol loading off, or 64-bit gdb dies with its own internal
error reading the stripped 32-bit inferior.

```
gdb -batch -ex 'set auto-solib-add off' -ex run -ex 'info proc mappings' \
    -ex bt --args ./srcds_linux <the srcds_run arguments>
```

`srcds_run -debug` is not enough: it only symbolises a core file, the container
produces none, and it writes a `debug.log` holding a header and no frames.

## 2. None of it is play-tested. Open, and the test-bed can run now

Every number in the work above is an argument. The nest range floor, the buster
distances, the crowd worth a sticky cluster, how long a Spy has to stand behind
a bot: all of them were reasoned about and none of them were measured.

`testbed/` exists for exactly this, and it works: a fake client holds a seat and
readies up, the mod spawns six bots, they shop, the wave begins, and every wave
is written down. Run a mission before the changes and the same mission after,
and read `report.py`. Do the baseline twice before believing either.

## 3. Map data. Six maps done, the rest open

`mvm_bigrock`, `mvm_coaltown`, `mvm_decoy`, `mvm_mannworks`, `mvm_mannhattan`
and `mvm_rottenburg` now carry `EngineerNest`, `DispenserSpot` and
`TeleporterExit` blocks. Somebody flew each map and stood on each spot, so they
outrank the nav mesh reasoning and the map's own hint entities.

The raw capture is in `testbed/results/`: `spots.log` is what the command
printed, `chat.log` is what was said while printing it, and
`spots-annotated.tsv` joins the two and carries the corrections. Spots that
were dumped and then rejected are marked rejected rather than deleted, so a
coordinate that looks odd can be traced back to what was said about it.

What is left is the other twenty-two config files, none of which have been
walked. `sm_dump_spot <block> [aim]` prints the line to paste. Stand on the
spot for accuracy; `aim` traces the crosshair to the world, which is how a map
gets marked from above without landing on every spot.

## 4. A nest is scored for the bomb and not for the team. Open

`ScoreNestArea` weighs range to the bomb, height, room and spacing from the
other engineers. It does not know where the rest of the lineup is standing.

A nest the team walks through is a dispenser that heals somebody and a sentry
with bodies in front of it. A nest nobody passes is an engineer alone. Distance
to where the team holds belongs in that score, and the reason it is not there
yet is that nothing in this mod says where the team holds.

## 5. Teleporters: whether to build one at all. Open, and it is a question first

The bots do not build them. Six maps now name a `TeleporterExit`, but none
names a `TeleporterEntrance`, and the build behaviour refuses without both.

The play-test found the ride is worth less than it looks: the entrance is at
spawn, so taking one means walking backwards first. `ShouldUseTeleporter` now
refuses unless the fight is far enough up the path to pay for that walk.

Answer the question before authoring any map data. If a defender bot should
rarely ride one, an engineer should rarely spend the metal and the walk on
building one, and the right fix is to leave it alone rather than to fill in
twenty-eight config files.

## 6. The sticky launchers that want playing differently. Open

`behavior/stickytrap.sp` handles the stock launcher. A Quickiebomb wants its
shots charged, and a Scottish Resistance wants bombs kept in several places at
once and detonated selectively, which is a different behaviour rather than a
tuning of this one.

Either could be refused outright instead, so the loadout code hands the bot a
launcher the existing behaviour already plays well.

## 7. Bot seating for specific classes. Open, needs a repro

Reported twice and not diagnosed. Three things decide the lineup and they may
not agree: the class preference flags (`player_pref.sp`), the lineup modes
(`menu.sp`), and `sm_redbots_manager_team_composition`.

Blocked on the reporter saying which of the three they used and what they got.
Guessing which one is broken would waste the change.

## 8. The Spy tells that are about behaviour. Open

What is implemented is a Spy who is close and appeared out of nowhere. What a
human actually reads is a teammate walking against the flow of the team, one
who never shoots at anything, and one whose class is not in a lineup the bots
themselves chose.

That last one is nearly free here, because the mod picks the RED team and knows
exactly which classes it asked for. A RED Heavy on a team with no Heavy in it is
a Spy, and no human on the server would have to be told.

## 9. Nothing senses which way the robots came. Open

The nest scorer reasons about the bomb and about static mesh data. `BOMB_DROP`,
nav visibility, the spawn room flags and `bot_hint_sentrygun` are all baked at
map compile time and identical every wave. The only dynamic inputs are the
bomb's position, which resets to the same place each wave, and `BLOCKED`, which
is now read.

So on a map where the mesh does not change and only the spawn door differs,
`ShouldRelocateNest` computes a gain near zero and correctly does nothing.
Mannworks is exactly that map, and it is where the note asking for this was
written.

The cheap way in is to watch the robots instead of the map. Sample live BLU
players on a timer, map each to a nav area, count visits per area, and use
"where robots actually walked" as the approach sample in place of the radius
around the bomb, falling back to today's sample when the count is empty. It is
one wave behind by construction: wave N is chosen from wave N-1's traffic,
which is right whenever the spawn side repeats and wrong exactly once when it
flips.

Parsing the popfile would know the route before the wave instead of after. It
is a text parser for a format with no schema, plus a file location problem on
custom missions, for information that arrives one wave later for free.

## 10. Engineers now keep their buildings across waves. Needs a play-test

`CTFBotUpgrade_OnEnd` used to detonate the sentry and the dispenser at the end
of every shopping trip, so no engineer ever kept a building across a wave and
the nest was silently re-picked every time, with a level 3 rebuilt from
nothing. That teardown is now gated on whether the nest actually changed.

It is what makes item 3's relocation observable, and it is a real change to how
every map plays. Nobody has watched a mission with it on.

## 11. Not this repository

A cash bundle spent on upgrades leaves the money negative when the wave is
lost. It is `tf2-archipelago`'s to fix, item 12 in its TODO: the plugin writes
`m_nCurrency` directly, so the game's wave-loss restore never knew the money
existed.
