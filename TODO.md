# TODO

What the bots still need. The 1.9.0 play-test bugs come first: a bot that stands
in spawn costs a whole seat, which is worth more than any tuning below it.

The 1.3 play-test report, what the code actually did about each complaint, and
what was changed, is in `specs/playtest-1.3.md`. This file is what is left.

## Bugs from the 1.9.0 play-test

### 17. Engineers freeze in spawn between waves. Fixed and measured

EZKSupernova reported it twice: "if you restart a mission via the vote menu, the
engi bots just freeze in spawn", which Peppy confirmed, and "the engie bots just
freeze in spawn when wave is lost".

Neither the restart nor the loss was the cause. The break was.

`g_bShoppedThisBreak` was cleared in `Event_MvmWaveBegin`, which is when a break
ends rather than when one starts. So every bot that lived through a wave carried
"has shopped" into the whole of the next break, and `GetDesiredBotAction` has
three things to offer a bot between rounds: collect loose money, go and shop, or
walk to the front. The first is rare, the second was skipped by the stale flag,
and the third refuses an engineer and a medic. Nothing left, so the bot was
handed back to the game, which has no answer for a defender between waves, and
he stood where the wave left him.

A bot that died shopped normally, because a spawn clears the same flag. That is
what made it intermittent, and it is why a lost wave and a vote restart were
what got reported: a restart kills nobody, so nobody's flag is cleared and the
whole team stands still.

The flag is cleared when the break opens now, on `mvm_wave_complete` and on
`mvm_wave_failed`.

The test-bed grew two things to see it with, and both stay. `report` has a
"between waves" table: the share of break samples with no Defender action
anywhere on the action stack, the longest run of them, where he stood and how
far he walked. And `TESTBED_BOT_MANAGER_MODE=2` plays a mission in AUTO_BOTS,
which is what tf2-archipelago runs; the test-bed had only ever played
READY_BOTS, and this bug does not show there because a lost wave kills enough
bots to clear their own flags.

Measured on Decoy, two waves, AUTO_BOTS, six bots with two engineers, both waves
cleared in both arms. The number is the share of between-wave samples with no
behaviour at all:

| | engineer | engineer | medic | soldier | heavy | demo |
| --- | --- | --- | --- | --- | --- | --- |
| before | 86% | 100% | 100% | 6% | 6% | 20% |
| after | 0% | 0% | 76% | 0% | 0% | 0% |

The engineers walked 2509 and 777 units in the break before, and 14803 and 15873
after.

The medic is still standing, and that is item 19.

### 19. The medic had nothing to do between waves. Fixed and measured

Left behind by item 17. With the shopping flag fixed the medic still spent three
quarters of the break with no behaviour on his stack.

`ShouldTakeUpPosition` refused four classes, on the reasoning that each has
somewhere else to be: the engineer has his nest, the spy is lurking, the sniper
with a rifle has his spot, and the medic follows a patient. The first three hold.
The medic does not: between rounds he heals nobody, so nothing suspends for him,
and following a patient is not a behaviour he has when there is no healing to do.
His patient is walking to the front, so that is where he goes now.

Measured on the same mission as item 17, two waves, both cleared either way:

| | medic, no behaviour in the break | healing done | defenders died | damage |
| --- | --- | --- | --- | --- |
| before | 76% | 876 | 18 | 30922 |
| after | 0% | 1560 | 17 | 32314 |

Every bot on the team is now at 0%. Two waves is too small to call the healing a
win; it is enough to say nothing regressed.

### 15. Sniper bots on the stock loadout stand in spawn. Explained by item 17, and one fix measured and thrown away

Peppy, and he said it predates 1.9.0: "Sniper bots with the stock loadout don't
seem to work, they just stay in spawn."

A sniper had never been in a test-bed lineup: 3417 engineer samples in
`results/` and not one sniper, which is why this survived. Forced into one on
Decoy, on the build with item 17 fixed, he works: `SniperLurk` under his stack
for the whole mission, 1970 damage and 14 kills over three waves.

That is the answer. A rifle sniper is one of the classes `ShouldTakeUpPosition`
refuses, so with item 17's stale shopping flag he had no behaviour for the whole
break and stood where he spawned. The same freeze as the engineers, and fixed
with them.

The rest of this item is a fix that was written, measured and thrown away, and
it is worth keeping because the reasoning was sound and the measurement said no.

`SetupSniperSpotHints` takes the team off every `func_tfbot_hint` when the map
config names no `SniperSpot`, and the game's sniping behaviour walks to a hint of
its own team. So on an unconfigured map a rifle sniper looked like he would have
nowhere to go, and the fix was to let him fight instead. Decoy with its
`SniperSpot` block removed, two waves each way:

| | damage | kills | standing still |
| --- | --- | --- | --- |
| lurking, as shipped | 4521 | 35 | 24 of 63 samples |
| falling back to attacking | 570 | 7 | 11 of 82 samples |

The premise was wrong. The game's lurk finds its own spot without a hint, and a
sniper on his rifle is worth eight times a sniper walking around shooting at
things. The change was reverted. What it did prove is that standing still is what
a sniper is supposed to do, so "he is not moving" is not evidence of a broken
sniper, and the next report of one wants damage per wave beside it.

### 16. Engineers build two dispensers. Measured: it is a blueprint, not a building

Peppy: "Engineer bots can sometimes build 2 dispensers."

The per-owner building samples walk `TF2Util_GetPlayerObject`, which is the
game's own list and holds one entry per type, so a second dispenser on one
builder is exactly what that list cannot show. A second instrument walks the
entities instead and counts them against `m_hBuilder`.

First run, four waves: two engineers each held two dispensers, for three samples
each. Second run, with entities that are being placed or carried excluded: none
at all, over four waves.

So no engineer ever holds two built dispensers. What he holds is the blueprint,
which is a real `obj_dispenser` with his name on it, while his own dispenser
stands at the nest. That is what a person watching sees as a second one, and it
is why the report says "sometimes".

Both are written down now: a `duplicate` line if a builder ever holds two of a
type, and a `ghost` line for each blueprint or carried building. A three wave run
had eight ghost samples on one engineer, dispenser and sentry, so a blueprint can
be out for the length of a walk across the map.

That is the honest end of this item unless somebody sends a screenshot of two
dispensers standing. If it turns out to be the blueprint that bothers people, the
fix is the engineer cancelling the placement when he stops walking to a spot, and
the `ghost` lines are what would measure it.

### 20. Bavarian Botbash wave 3 wipes the bot team. Still lost, and four things were measured

Swagdoll: "Bavarian Botbash Wave 3 is still basically impossible for me. That
Giant Crit Heavy and his two Giant Medics keep wiping everything and I'm not good
enough at Sniper to counter it."

Not solved. Six attempts at the wave with nobody on the server, in two
configurations, and all six were lost. What follows is what was measured, what it
ruled out, and the two changes that survived.

**The first three sessions measured the wrong mission.** `tf_mvm_popfile
mvm_rottenburg_advanced_bavarian_botbash` was refused, the server kept playing
Rottenburg's own default, and nothing said so. The real names are in the game's
VPK and there are two: `mvm_rottenburg_advanced1` and `_advanced2`.

```
grep -ao 'mvm_rottenburg[a-z0-9_]*' tf/tf2_misc_dir.vpk
```

`run.sh` reads the popfile back now and stops with the name it is actually
playing, because everything downstream of a silent substitution is fiction.

**A second instrument was lying.** Three of four wave results in a run came out
exactly 2047 characters long: SourceMod's `File.WriteLine` formats through a 2048
byte buffer and the wave result had outgrown it. Truncated JSON is skipped by
every reader, so a four wave run looked like a one wave run. It writes with
`WriteString` now. Any measurement in this file taken on a long line before this
was measuring fewer waves than it thought.

**The uber is not being wasted.** A `uber_held` line is written whenever a
defender dies while a live medic holds a full charge. Over a whole wave 3 there
were none, so the charge is not sitting in his pocket while the team dies.

**The medic's patient churned, and fixing it changed nothing here.** He re-picked
the biggest body every two seconds, and maximum health follows the upgrades the
team buys, so the winner flipped between bodies a few points apart: 18 patient
changes in one wave. A tie keeps the man he has now, `MEDIC_PATIENT_MARGIN`, and
that is 7 changes. The beam is on somebody 27% of the time either way, so the
churn was real and was not what keeps the beam off.

**Where they wait for the wave is worth something on a hard mission and costs on
an easy one.** `MoveToFront` sends everybody to the robots' own gate. Waiting
beside the engineer's sentry instead, three attempts each on the real wave 3:

| | deaths | robots killed | held | distance to a sentry at wave start |
| --- | --- | --- | --- | --- |
| the gate | 22 | 36 | 135s | 823 |
| the nest | 18 | 38 | 127s | 588 |

On Decoy's own mission the same change unconditionally was worse: two waves
cleared and 206 robots killed at the gate, one wave cleared and 165 at the nest.
So the rule is the mission, `hold_the_nest`: meet them at the gate while the team
can afford to, hold the nest when it cannot. Decoy with the rule in place is back
to 206 robots and both waves cleared.

What is still true after all of it: the wave is lost every time, at 18 to 23
defender deaths an attempt. The bots do already shoot robot medics, 56 samples of
it in one wave, so the idea this item started with is in the mod and working.
Nobody has added a balancing knob and nobody should.

The next thing to measure is the giant demoknights. The chosen-target counts for
the wave are `demoman 148, medic 56, giant soldier 3`, which is a team spending
the wave on the escort while the thing that kills them is a charge they never see
coming. A defender who cannot outrun a demoknight has to shoot it before it
arrives, and nothing in the target ranking knows that.

### 7. Bot seating for specific classes. Fixed and measured

Reported three times, and the 1.9.0 play-test named the mechanism. Peppy: "the
bot seats I set as 'Let the mod pick' still picks from classes that I have
unchecked in the Classes tab."

Two halves, one each side. tf2-archipelago was dropping draw seats out of
`sm_redbots_manager_team_composition`, so a team of nothing but draws wrote an
empty convar; that is its item 9 and it is fixed there.

An empty convar is what makes `GetWantedTeamComposition` fall back to the map
config's own composition, and `IsBotClassBlacklisted` returned false for every
class any composition named. That rule is right for a team somebody typed into
the console and wrong for a default this mod guessed at: a guess does not get to
overrule a class the server was told never to play. It asks the convar alone
now.

Nothing said why a bot was the class it was, so `AddDefenderTFBot` writes one
line whenever the blacklist changes its mind, naming the wanted class, the class
it settled on, and where the lineup came from.

Measured on Decoy, whose map config names `scout,soldier,demoman,heavyweapons,engineer,medic`,
with `BOT_CLASS_BLACKLIST=medic` and no convar lineup. Two waves, both cleared,
and no medic on RED in 433 bot samples:

```
Adding demoman (wanted medic), lineup from the map config
```

A team typed into the convar still beats the blacklist, which is the rule that
was kept rather than measured.

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

### 10. Nest relocation trips the server watchdog. Fixed, and the feature is still off by default

`sm_redbots_manager_engineer_nest_relocate` was 0 because turning it on killed
the server at the first wave transition. Reproduced again today on Decoy with two
engineers: the server crashed before a single wave finished.

This time there is a backtrace rather than a guess. The core was read with the
game's own binaries copied out of the container, which is what makes the frames
resolve:

```
WatchDogHandler <- Host_Error <- Sys_Error
 <signal handler called>
CNavArea::GetZ <- CNavArea::ComputePortal
CNavArea::ComputeAdjacentConnectionHeightChange
SMPathFollowerCost::operator()
NavAreaBuildPath (maxPathLength=0)
Path::Compute
natives::nextbot::path::ComputeToPos
 ... SourcePawn JIT frames ...
CHookManager::PlayerRunCmd
CBasePlayer::PhysicsSimulate
```

So the frame the watchdog killed was a nav mesh search, reached from this mod's
own per-frame path refresh inside `PlayerRunCmd`, with no bound on the search.
An unreachable goal makes `NavAreaBuildPath` walk the whole mesh, and six bots
asking in the same frame multiplies it. Relocation makes unreachable goals more
likely, which is why it shows there first and why the same shape has now produced
four crashes.

The fix is a limit rather than a special case. `PATHS_PER_FRAME` is 2: the
per-frame refresh computes at most two paths a frame across the whole team, and
anybody refused tries again next frame. At 66 ticks that is 130 a second against
a refresh that wants one every 0.2 seconds per bot, so nothing waits for a path.
A behaviour that computes once when it starts is never refused, because it has no
retry.

Measured:

| | result |
| --- | --- |
| relocation on, before | crashed before wave 1 finished |
| relocation on, after | 3 waves cleared, then 3 more waves, no crash, no stalls |
| relocation off, after | 2 waves cleared, 206 robots, 17 deaths, 31819 damage |
| relocation off, before | 2 waves cleared, 206 robots, 17 deaths, 32314 damage |

The last two are the regression check: the budget changes nothing about a normal
run.

The convar stays 0. The crash is what kept it off; whether the feature is worth
having is a different question and wants its own measurement.

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

The pattern is worth naming, because it has now produced four separate crashes:
a nav mesh call inside something that reads like a predicate, called from a
per-frame path. Anything asking the mesh a question wants a clock on it.

Item 10 is the fourth, and it came with a symbolised backtrace and a limit:
`PATHS_PER_FRAME` caps the whole team at two path computations a frame. That is
the general answer to this pattern rather than another special case, and the
residual intermittent watchdog crash recorded here should be measured against it
before anything else is tried.

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

