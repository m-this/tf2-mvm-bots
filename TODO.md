# TODO

What the bots still need. The 1.9.0 play-test bugs come first: a bot that stands
in spawn costs a whole seat, which is worth more than any tuning below it.

The 1.3 play-test report, what the code actually did about each complaint, and
what was changed, is in `specs/playtest-1.3.md`. This file is what is left.

## Bugs from the 1.9.0 play-test

### 17. Engineers freeze in spawn after a restart or a lost wave. Open, from the 1.9.0 play-test

Two reports of what is probably one bug. EZKSupernova: "if you restart a mission
via the vote menu, the engi bots just freeze in spawn", which Peppy confirmed,
and "the engie bots just freeze in spawn when wave is lost".

What those two have in common is that the round ends without the mission
advancing. A wave completing runs the nest re-score and the teardown; a restart
and a loss both reset the world under a bot whose action stack was built for the
wave that is gone. An engineer holding a handle to a sentry the reset deleted,
or suspended for a build action that will never finish because the building it
was placing no longer exists, stands still and looks exactly like this.

It is engineers only, out of six bots, which is the useful part of the report:
the engineer is the one class here with a long-lived action stack that owns
world entities. Everybody else re-decides every tick.

Two events to look at, `mvm_wave_failed` and whatever the vote restart fires,
against `CTFBotMvMEngineerIdle_Update` and the build actions, and against
`CTFBotUpgrade_OnEnd`, which detonates after shopping and is already gated on
the relocation convar per item 10.

Repro on the test-bed, both ways, and both are scriptable with nobody on the
server: lose a wave by leaving the bots to it on a mission they cannot clear,
and fire the restart from the console rather than the vote menu once it is
confirmed the two take the same path. Telemetry is the engineer's current action
name and his building handles, logged on the reset and again five seconds later.
A frozen engineer is one whose action name does not change, and that is the
number to hold a fix against.
### 15. Sniper bots on the stock loadout stand in spawn. Open, from the 1.9.0 play-test

Peppy, and he says it predates 1.9.0: "Sniper bots with the stock loadout don't
seem to work, they just stay in spawn."

A Sniper standing in spawn is a bot with nowhere it wants to be. The place to
look is `SetupSniperSpotHints`, which is the only thing in this mod that tells a
Sniper where to stand: with no `SniperSpot` block in the map config it does not
add hints, it strips the team off every `func_tfbot_hint` on the map instead,
and logs an error saying so. Twenty-two of the twenty-eight map configs have no
hand-walked data at all, per item 3, and the six that do may not carry sniper
spots either. Check that first, because it explains "stays in spawn" exactly and
it explains why it is not new.

Why the loadout would matter is the other half and it may be a coincidence of
reporting: a stock Sniper Rifle wants a scoped shot at range, and a bot with no
spot to hold and no threat in range of the rifle has no reason to leave. If a
Huntsman Sniper walks out and a stock one does not, the gate is a weapon range
check rather than the hints, and `EquipBestWeaponForThreat` is where to look.

Repro on the test-bed, on a map whose config has no `SniperSpot`, with a lineup
forced to Sniper through `sm_redbots_manager_team_composition`. The report
already writes down damage a wave per bot, so a Sniper at zero for six waves is
the signal, and distance walked from spawn is the telemetry to add if it is not
there: it separates "never left" from "left and did nothing".

### 16. Engineers build two dispensers. Open, from the 1.9.0 play-test

Peppy: "Engineer bots can sometimes build 2 dispensers."

Two engineers is the obvious reading and it is fine: they skip a dispenser spot
another engineer already occupies, and two engineers with two dispensers is the
lineup working. One engineer with two is the bug, and the report does not say
which, so the first job is telemetry that does.

The suspect is the dispenser build ending on a flag. The build stopped ending
itself three seconds in on a flag only the idle action refreshes, and Mannworks
went from 13% dispenser uptime to 39%, so the flag is not the only thing holding
that state. An engineer who believes he has no dispenser while one stands behind
him builds a second, and the game allows it: the limit is one per engineer only
because the engineer usually detonates the first.

Log the owner and the entity index at every `obj_dispenser` spawn, plus the
count that engineer already owns. A run where the count reaches two names the
engineer and the frame, and a run where two different engineers each own one
says there was never a bug.

`testbed/sweep.sh` plays every installed map, which is the right shape here
because "sometimes" is a rate. Count dispensers per engineer across a sweep
before and after any fix.

### 7. Bot seating for specific classes. Open, and 1.9.0 named the mechanism

Reported three times now and not diagnosed. Three things decide the lineup and they may
not agree: the class preference flags (`player_pref.sp`), the lineup modes
(`menu.sp`), and `sm_redbots_manager_team_composition`.

The 1.9.0 play-test named the mechanism and the launcher half is fixed. Peppy:
"the bot seats I set as 'Let the mod pick' still picks from classes that I have
unchecked in the Classes tab." Those two settings are
`sm_redbots_manager_team_composition` and `sm_redbots_manager_class_blacklist`.
tf2-archipelago was dropping the draw seats out of the composition, so a team of
nothing but draws wrote an empty convar. See its item 9; it writes the seats out
as holes now.

What is left is this mod's rule, and it is a real one.
`GetWantedTeamComposition` falls back to the map config's own composition when
the convar is empty, and `IsBotClassBlacklisted` then returns false for every
class that default names, because a named team beats the blacklist. That rule is
right for a team somebody typed into the console and wrong for a default this
mod guessed at: the map's answer is a suggestion and the blacklist is an
instruction. The map default should be filtered through
`PickAllowedBotClass` like everything else.

Telemetry before the fix. Nothing today says why a bot got the class it got.
Log the wanted class, the class after `PickAllowedBotClass`, and where the
lineup came from (convar, map config, or lineup mode), once per bot added. A
test-bed run on a map whose config names a composition, with that class
blacklisted and no convar set, then says it in one line.

### 18. One ask adds twice. Fixed and measured

`sm_addbots N` runs `AddBotsBasedOnLineupMode(N)`, which calls
`AddBotsFromTeamComposition(N)` first. That added the seats the named team still
wanted and returned a bool: true only when it filled all N. A team that does not
name every seat cannot, so the caller fell through to the lineup mode and asked
it for N again, on top of what had just been added.

`AddBotsFromTeamComposition` returns the count it added now, and the caller
subtracts it before falling back.

Three lines of telemetry made it visible, and they stay: every
`AddBotsBasedOnLineupMode` logs what it was asked for, what the named team
filled, and what the lineup mode was left to add.

Measured on the test-bed, one wave of Decoy, `BOT_TEAM_COMP` naming three
classes with `BOT_TEAM_SIZE` at six, which is what a tf2-archipelago player
produces every time a seat is left on "Let the mod pick".

| | RED at wave 1 | the log |
| --- | --- | --- |
| before | 10 | filled 3 of 6, the lineup mode adds 6 more |
| after | 7 | filled 3 of 6, the lineup mode adds 3 more |

RED is seven rather than six because the test-bed's own host client holds a
seat. Nine bots plus the host is what Peppy reported and what the first run
reproduced.

## Crashes and the test-bed

### 10. Nest relocation trips the server watchdog. Open, and it is off

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

### 12. The Gas Passer crashed the server. Fixed; the rest of the watchdog is still open

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

### 13. The test-bed needs a machine with memory free. Open

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

### 2. None of it is play-tested. Open, and the test-bed can run now

Every number in the work above is an argument. The nest range floor, the buster
distances, the crowd worth a sticky cluster, how long a Spy has to stand behind
a bot: all of them were reasoned about and none of them were measured.

`testbed/` exists for exactly this, and it works: a fake client holds a seat and
readies up, the mod spawns six bots, they shop, the wave begins, and every wave
is written down. Run a mission before the changes and the same mission after,
and read `report.py`. Do the baseline twice before believing either.

## Behaviour and map data

### 3. Map data. Six maps done, the rest open

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

### 5. Teleporters. Built now, exit first, and that wants measuring

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

The order was the open question and the 1.9.0 play-test answered it. EZKSupernova:
"they should stop insta-teleporting to the front to build a sentry and dispenser
because now they run all the way back to spawn to place the entrance then go to
place the exit; the warp to the front only works if they place the exit first
then use the tele once they place the entrance."

So it is exit first. The engineer is already at the nest when the wave ends,
which is where the exit goes, and walking back to spawn for the entrance is the
walk the teleporter exists to remove. Building the exit first means the entrance
is the only trip, and after it he rides his own teleporter forward.

The argument for entrance first was that an exit alone moves nobody, and that is
true of a half-built pair, but it has the trip the wrong way round: the engineer
is the first passenger.

Measure it rather than assuming, because the reason for the old order was also
an argument. `testbed/` reports time spent walking and dispenser uptime, and a
mission either way on a map with a long approach, Rottenburg or Mannhattan, says
whether the engineer reaches his nest earlier. Add the telemetry first if the
report does not already carry time-to-first-sentry, because that is the number
this changes.

No official map names a `TeleporterEntrance` and none needs to: the route out of
spawn is read from the mesh. The six that name a `TeleporterExit` still use it.

### 4. A nest is scored for the bomb and not for the team. Open

`ScoreNestArea` weighs range to the bomb, height, room and spacing from the
other engineers. It does not know where the rest of the lineup is standing.

A nest the team walks through is a dispenser that heals somebody and a sentry
with bodies in front of it. A nest nobody passes is an engineer alone. Distance
to where the team holds belongs in that score, and the reason it is not there
yet is that nothing in this mod says where the team holds.

### 6a. The Demoman is the weakest seat, and it is in every lineup. Open

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

### 6b. Nothing deploys the Medic's Projectile Shield. Open

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

### 6. The sticky launchers that want playing differently. Open

`behavior/stickytrap.sp` handles the stock launcher. A Quickiebomb wants its
shots charged, and a Scottish Resistance wants bombs kept in several places at
once and detonated selectively, which is a different behaviour rather than a
tuning of this one.

Either could be refused outright instead, so the loadout code hands the bot a
launcher the existing behaviour already plays well.

### 8. The Spy tells that are about behaviour. Open

What is implemented is a Spy who is close and appeared out of nowhere. What a
human actually reads is a teammate walking against the flow of the team, one
who never shoots at anything, and one whose class is not in a lineup the bots
themselves chose.

That last one is nearly free here, because the mod picks the RED team and knows
exactly which classes it asked for. A RED Heavy on a team with no Heavy in it is
a Spy, and no human on the server would have to be told.

### 9. Nothing senses which way the robots came. Open

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

### 14. The medic's patient. Mostly closed

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

## Not this repository

A cash bundle spent on upgrades leaves the money negative when the wave is
lost. It is `tf2-archipelago`'s to fix, item 1 in its TODO: the plugin writes
`m_nCurrency` directly, so the game's wave-loss restore never knew the money
existed.

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
- The crash was the test-bed's own entrypoint: `cp -r` over a running server's
  mapped extension every thirty seconds, so the next instruction out of that
  extension was a SIGBUS. `cp -ru` fixes it. `specs/` has the full account, and
  the way to get a backtrace out of a stripped 32-bit server is worth keeping:

  ```
  gdb -batch -ex 'set auto-solib-add off' -ex run -ex 'info proc mappings' \
      -ex bt --args ./srcds_linux <the srcds_run arguments>
  ```

