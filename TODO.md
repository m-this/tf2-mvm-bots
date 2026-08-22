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
- Engineers build teleporters. The entrance comes off the nav mesh's own route
  out of spawn instead of a straight line through the walls, the exit stands
  beside the nest instead of on the sentry, and an all-bot team holds the ready
  long enough for him to do it. See item 5.
- The medic picks his patient from the whole team rather than from whoever is
  within nine metres, which is what parked him at the engineer's nest for the
  length of a wave. See item 14.
- The bots wear hats rather than tournament medals. The pool was drawn from the
  schema's misc slot, which is mostly UGC and ozfortress season badges; it is
  filed by equip region now, because the head slot is the game's old single-hat
  one and no modern item reports it.
- `AddBotsFromChosenTeamComposition` counts who is already on RED. It added the
  whole lineup, which is right only while nothing else fills the team before the
  wave, and tf2-archipelago now does.
- The dispenser build stopped ending itself three seconds in on a flag only the
  idle action refreshes. Mannworks went from 13% dispenser uptime to 39%.
- An engineer with no sentry builds one instead of considering a move, which is
  what left him standing on Bigrock for most of a wave.
- The sentry stands in front of the engineer like the other two buildings, and
  every part of building one has a clock on it.
- `testbed/sweep.sh` plays every installed map and `testbed/sweepreport` reads a
  whole sweep. See `specs/sweep-2026-08-22.md`.
- The loadout file can name a seat of `sm_redbots_manager_team_composition` and
  not only a class, so seat 1 holds the wrangler and seat 2 need not.

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

## 5. Teleporters. Built now, and the order they go up in is still a question

They are built. What was wrong was three separate things and none of them was
the map data:

- The entrance spot was the spawn point plus the direction to the nest times a
  distance, which is a line drawn through whatever wall is in the way. It reads
  the nav mesh's route from the engineer to the spawn point now, and samples it
  backwards from the spawn end, so the attempts walk the way a player walks.
- The exit spot was the nest centre, which is where the sentry is, so all eight
  attempts asked the game to put a teleporter inside a sentry gun. It stands off
  the centre now and he stands between the two.
- On a team of nothing but bots the wave started the instant the last nest
  finished, so the build action gave up on its first update with "Wave started".
  `IsDefenderPrepared` holds the ready for the teleporter, but only when there
  is no human on the server: a player who has finished shopping should not be
  held for a building the bots want, and their shopping is already the time the
  engineer needs.

What is still open is the order. The entrance goes up first, on the reasoning
that an exit alone moves nobody, and that is also the order that maximises the
chance of the wave starting while the engineer is at the far end of the map. The
other order leaves him at his nest when the time runs out, and leaves an exit
nobody can reach. Neither half is worth anything alone, so this is a question
about which way to be caught, and it wants a play-test rather than an argument.

No official map names a `TeleporterEntrance` and none needs to: the route out of
spawn is read from the mesh. The six that name a `TeleporterExit` still use it.

## 6a. The Demoman is the weakest seat, and it is in every lineup. Open

A sweep of every map put it at 1634 damage a wave across forty waves, against
the Heavy's 8594, with a seat in all seven lineups.

It is not aim. 308 damage a kill is better than the Pyro's 354 and the Heavy's
425: it is efficient with what it fires and does not fire enough.

Holding the launcher by default was tried and measured and it is worse. Six
waves of Coaltown either way, one build, one switch between them:

| | damage a wave | kills | cleared |
| --- | --- | --- | --- |
| pipes first | 1821 | 27 | 5 of 6 |
| stickies first | 880 | 11 | 4 of 6 |

Half the damage, so the switch is gone rather than left off. The hole in the
argument was that the bot fires at where a robot is rather than where it is
going: a sticky thrown at a walking robot lands behind it and catches nobody,
and the clip and the reload are spent for nothing where a pipe at least does its
damage when it connects.

Which leaves the trap, and the trap is the thing the guides are actually
describing when they say a Demoman's damage is in his secondary. Bombs go on
ground the robots have not reached yet, and the bot waits. `behavior/stickytrap.sp`
lays one, and it only ever runs when no threat is visible at all, on a twenty
second cooldown, so during a wave it never runs. That gate is the next thing to
move, and it wants measuring the same way this was.

Two smaller things went in alongside and are unmeasured, because they were in
both arms: a Medic is always worth the switch to the launcher, and detonation is
counted across the whole cluster rather than answered by the first bomb that
qualifies.

## 6b. Nothing deploys the Medic's Projectile Shield. Open

Every guide puts one tick of it first for a Medic and they are right about a
person: it is the strongest single thing a Medic does to a wave. It is deployed
with the special attack key, and no behaviour in this mod has ever pressed one.

So `generate rage on heal` was three hundred credits at the top of the Medic's
list buying a meter that fills a button nobody uses. It is refused in
`IsUpgradeWasted` until something presses it, and the moment something does it
goes straight back to the top.

The wider point is worth keeping: the wiki is written for people, and a
recommendation is only worth copying where this mod's bots can do the thing it
assumes. Three of them failed that test in one pass. The Pyro's Destroy
Projectiles is an airblast the Phlogistinator has not got. Jump height reaches
credits a person can see on a ledge, and a bot walks where the nav mesh says.
And this one.

The two that passed are worth naming too, because the test is not "distrust the
guide": the Sniper really does aim at the head bone, so Explosive Headshot earns
its place at the top, and the Engineer's own play-tested ordering beat the page.

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

## 10. Nest relocation trips the server watchdog. Open, and it is off

`sm_redbots_manager_engineer_nest_relocate` defaults to 0 because turning it on
kills the server at the first wave transition:

```
WatchDog! Server took too long to process (probably infinite loop).
FATAL ERROR: Host_Error: WatchdogHandler called - server exiting.
```

Reproduced twice on `mvm_decoy` with two engineers in the lineup, both times
straight after wave 1. The same mission on 1.5.5-tf2ap.10 plays six waves, and
so does this build with the convar at 0, so it is this feature and nothing else
in the release.

What was tried and did not fix it: the evaluation used to run a full nav mesh
sweep per engineer inside the `mvm_wave_complete` frame, which is a real hazard
and is now one engineer per timer tick. The crash did not move. So the cost is
not in `ShouldRelocateNest`, and the next place to look is the relocation branch
in `CTFBotMvMEngineerIdle_Update`. An action that suspends for another which
finishes at once and hands control straight back spins inside a single frame,
which is what the watchdog measures.

The teardown gating rides on the same convar, and getting that wrong is worth
recording: gating only on "is the nest moving" meant that with the feature off
nothing ever moved, so the teardown never ran and every engineer held wave one's
nest for the whole mission. It now asks the convar too, so with the feature off
`CTFBotUpgrade_OnEnd` detonates after every shopping trip exactly as it did
before, and nothing else in the release depends on this being fixed.

## 12. The Gas Passer crashed the server. Fixed; the rest of the watchdog is still open

A Pyro carrying a Gas Passer trips the watchdog at a wave transition:

```
WatchDog! Server took too long to process (probably infinite loop).
FATAL ERROR: Host_Error: WatchdogHandler called - server exiting.
```

Four runs in six on `mvm_decoy`, and clean six waves running with a shotgun in
that slot instead. It was four in six rather than every run because the forced
lineup has no Pyro in it: `sm_redbots_manager_extra_bots` adds one beyond the
composition and sometimes rolls Pyro.

The fault is here, not in the weapon. `EquipBestWeaponForThreat` says to throw
gas whenever `HasAmmo(secondary)` is true, and `HasAmmo` on a weapon that fires
off a charge meter rather than a clip is always true. So the Pyro equips a jar
it cannot throw, every tick, and never picks the flamethrower back up.

Fixed: `IsThrowableReady` asks the meter instead of the ammo, and the three
places in that switch which reached for `HasAmmo` on a jar now go through it.
The Gas Passer's meter is on the player, per loadout slot, because it fills from
damage dealt; Jarate, Mad Milk and the Cleaver fill on a clock the weapon
carries. Both are read.

The loadout still gives the Pyro a shotgun. Putting the Gas Passer back is a
balance question rather than a crash one now, and the file already says the
airblast it costs is worth measuring rather than assuming.

The Gas Passer is not the whole story. 1.5.5-tf2ap.10, which has no loadout file
at all, crashed twice in three runs of the same mission afterwards, with the same
watchdog line. So there is an intermittent watchdog crash in this mod that
predates all of the above, and the Gas Passer made it far more likely rather than
causing it alone. Rates seen so far, all on `mvm_decoy` with six bots:

| build | crashes |
| --- | --- |
| tf2ap.10 | 2 in 9 |
| this branch, Gas Passer | 4 in 6 |
| this branch, shotgun | 0 in 5 |

The core dumps answered it, and the answer is pathfinding. Backtrace from
core.417, taken with the game copied out of the volume:

```
WatchDogHandler <- Sys_Error <- Host_Error
 <signal handler called>
CTFBotPathCost::operator()
NavAreaBuildPath
Path::Compute
ChasePath::RefreshPath
ChasePath::Update
```

So the frame the watchdog killed was inside path computation, not an infinite
loop in this mod. Anything that asks for a path every tick, for several bots at
once, can push a frame past the watchdog on a machine with nothing spare.

One of those was ours and is fixed: `ConfiguredDispenserSpot` called
`IsPathToVectorPossible` for every configured spot, every tick, per engineer.
The spot is chosen once when the action starts now.

Worth knowing for the next one: `IsPathToVectorPossible` is a full
`NavAreaBuildPath`, and it reads like a cheap predicate.

A sweep of every map found two more of the same shape, and both are fixed:

- An engineer with no sentry answered yes to "should the nest advance", and the
  idle action returns without acting when the answer is yes. So he never
  rebuilt, and every one of those frames ran `PickBuildArea` twice, which calls
  `GetBombInfo`, which walks every nav area on the map. Sixty-six times a
  second, per engineer, for as long as he had no sentry. On Bigrock that was
  most of a wave.
- The tactical monitor asked whether health or ammo was worth walking to on
  every frame for every bot, and the slow path computed a path to every
  candidate. MvM floors are covered in `tf_ammo_pack`. The answer is held for
  half a second now and the search is run for the nearest four candidates
  rather than all of them.

The pattern is worth naming, because it has now produced three separate
crashes: a nav mesh call inside something that reads like a predicate, called
from a per-frame path. Anything asking the mesh a question wants a clock on it.

## 13. The test-bed needs a machine with memory free. Open

Measurement stopped being possible partway through a session, on both builds at
once. 1.5.5-tf2ap.10 played six waves cleanly earlier the same day and then
failed four runs in a row, three of them before a single wave started, with the
watchdog line from item 12. The code did not change between those runs.

What did change is the machine:

```
7.8 GB of memory, around 200 MB free
5.0 GB swapped out
swap-in bursting to 20 MB/s while a run was playing
```

A page fault that stalls the server is indistinguishable, to a watchdog that
measures frame time, from an infinite loop. Running `--no-build` to skip the
per-run image build did not help, so it is the steady state rather than the
build spike.

Two ways out, and they are worth knowing before trusting any number this
test-bed produces: give it a machine with a couple of gigabytes free, or stop
whatever else is running on this one for the duration. What is not worth doing
is reading a crash rate measured under paging as a property of the code, which
is a mistake this file has already recorded once in item 12.

## 14. The medic's patient. Mostly closed

`PreferredPatient` in `nextbot_behavior.sp` works out who the medigun should be
on: the most maximum health, which names the Heavy without a class table and
follows the health upgrades the team buys. `behavior/medicheal.sp` acts on it by
doing the healing itself rather than by arguing with the game's own action.

Writing the patient into the game's action is still off, and the reason is worth
keeping: `action.SetHandleEntity(ACTION_HEAL_PATIENT_OFFSET, ...)` segfaulted the
server on the first Mannhattan run, with no watchdog line, which is a memory
fault rather than a slow frame. The offset is a hardcoded field inside one of the
game's own actions. Everything else in this mod only reads it, and the difference
matters: reading a wrong offset gives a wrong answer, writing one corrupts
whatever is really there.

What was reported and is fixed: the medic stood in the house in the middle of
Coaltown for a whole wave. The candidate list was the team within nine metres, so
once the Heavy walked out of that the ask came back with the engineer at his nest
and could never come back with anybody else. The list is the whole team now, a
healthy engineer is not on it because his own dispenser is doing that job, and
the answer is held between asks because the gate that decides whether the medic
heals at all runs every frame and every ask is a path computation per teammate.

What is still open is where he should stand once he has a patient. He follows the
patient, and nothing in this mod says where the team holds, which is the same gap
item 3 records for nest scoring.

## 11. Not this repository

A cash bundle spent on upgrades leaves the money negative when the wave is
lost. It is `tf2-archipelago`'s to fix, item 1 in its TODO: the plugin writes
`m_nCurrency` directly, so the game's wave-loss restore never knew the money
existed.
