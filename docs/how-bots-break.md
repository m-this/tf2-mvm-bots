# How these bots break, and how to find out

Every fault reported against this mod so far has arrived the same way: somebody
played a wave, saw a bot standing somewhere stupid, and said so. Then whoever
looked at it guessed at a cause, and was wrong about as often as right.

This is the accumulated shape of those faults, so the next person starts from
the pattern instead of from the symptom.

## The pattern

**Every one of them is a decision made from a model of the world that was never
checked against the world.** Not a type error, not a crash, not a memory bug. A
stronger language would have caught none of them.

Worked examples, all real, all found the hard way:

| The code | What it assumed | What happened |
|---|---|---|
| `stand[2] = spot[2]` | ground exists beside the spot | a spot on raised ground put the stand point in mid-air; the engineer walked to the floor below and held the toolbox until a clock saved him |
| `if (!IsWeapon(actor, TF_WEAPON_BUILDER))` | the toolbox is set to what I want | it remembers its last job, so a dispenser went down where the teleporter entrance belonged |
| `flLowestTime = 30.0` | money about to vanish is the money worth taking | freshly dropped cash has its whole lifetime left, so a heap at the end of a wave was never a candidate at all |
| `IsBetterPatient` + a separate distance rule | two orderings agree | they disagreed every two seconds; the medic walked half way to one patient, turned round, and parked at the fixed point of the oscillation |
| `GetObjectOfType` inside `DetonateObjectOfType` | an engineer owns one dispenser | he owned two; the teardown removed one and the other outlived every wave |
| `m_pPath.ComputeToTarget(...)` with the result discarded | a path was built | it returns `bool`; a refusal left an empty path, `Update` walked the bot along nothing, and the behaviour above believed it was travelling |
| `IsPathToVectorPossible` as a filter on authored spots | reachable now means reachable | the same refusal silently deleted a hand-walked coordinate, so the engineer built somewhere else and nothing said why |
| the dispenser repair branch placed before the sentry's | either order works | the branch returns, so an engineer polished a dispenser while his sentry was destroyed |

Note what they share. The world can refuse anything: the nav mesh has no ground
there, the entity list has two of something, a weapon holds state you did not
set, a rule you added disagrees with a rule already there. Anything read from
the game is an assertion, not a fact.

## They all look identical from inside the game

A bot that cannot do its job stands still. So does a bot doing its job. Five
different causes produced one symptom, which is why guessing did so badly.

Two things follow.

**Do not diagnose from a screenshot.** Get the state. `sm_dump_medic`,
`sm_dump_front` and `sm_dump_nest` print the behaviour stack, the goal, the
distance and every building with its owner. The medic oscillation above was
found in one sample after two wrong guesses had been shipped.

**Prefer a measurement to a theory.** The testbed writes per-bot and
per-building samples every five seconds (`docs/testbed-metrics.md`). If a
theory does not predict something in that file, it is not yet a theory.

## Recurring specifics

- **A full entity or nav scan inside something that reads like a cheap
  predicate, on a path that runs every frame.** Found five times. `IsPossible`
  functions are called every frame by the behaviour gate. Cache on an interval
  and short-circuit on a held answer.
- **Flat clocks.** `SENTRY_REACH_TIME 12.0` was written when the walk was
  inside the nest and stayed after the walk started at the upgrade station.
  Price a deadline by the distance it has to cover.
- **Settling for where you stand.** Every build action had a fallback that
  placed the building at the engineer's feet when a clock ran out, and two of
  them had no distance test on it at all. A building in the wrong place is
  worse than a building that is late.
- **Readiness as a proxy.** `IsPlayerReady` was used in four places to mean
  "has finished preparing". The moment a human on RED started forcing bots
  ready, all four silently answered yes, and the bots stopped shopping from
  wave two onward. If a flag means two things, one of them is wrong.

## Authored data is not a suggestion

`configs/defenderbots/map/*.cfg` holds coordinates somebody walked the map to
find. Four separate rules have now quietly discarded them — a distance bound, an
ownership rule, a height test, and a reachability query — and in every case the
only symptom was a player noticing a building in the wrong place weeks later.

The rule that came out of it: **an authored spot may be refused only by
something permanent.** Another engineer's building standing on it is permanent.
A path query that answered no once, from wherever the engineer happened to be
standing this second, is not. Unreachable is a last resort, not a disqualifier.

The report checks this now. `printSpotUse` measures every sampled building
against the map's own coordinates, per wave, by median:

```
how close the buildings got to the spots mvm_coaltown names
  Bob dispenser    wave 1: 114  wave 2: 61  wave 3: 780!!
```

Per wave and median rather than best-ever, because wave one is the wave the
engineer starts beside his nest with a whole break to build in. Taking the
closest a building ever got reported every map as perfect and hid the thing
actually being complained about, which was every wave after the first.

## Having no answer is worse than having a poor one

Three separate changes this session removed a candidate from a list because it
looked wrong, and all three made the bot worse:

| removed | what happened |
|---|---|
| an authored spot a path query refused | the engineer built somewhere random instead |
| a teammate the medic could not path to | the medic dropped out of the heal action and walked to the bomb |
| a teammate standing in the respawn room | the medic spent *more* of the wave in the spawn, healing fell 13566 → 10592 |

The behaviours are written so that an empty answer ends the action, and what
takes the bot next is the game's own code, which knows nothing about any of
this. So a filter that removes the last candidate does not produce a better
choice, it produces no choice.

**Rank it last. Do not remove it.** The only things that should remove a
candidate outright are permanent and physical: a building already standing on
the spot, a teammate who is dead.

## Measure the thing the change is aimed at

`medic_nearest` and `medic_leaves_spawn` were both obviously right and both
lost. Waves cleared barely moved either time (6/6 against 5/7, then 6/6 against
7/5) because clear rate is dominated by everything else; what settled both was
healing delivered and time-on-target, which is what the change was actually
about.

Beware the variance. The same OFF arm measured 29%, 35% and 43% beam time on
three different runs of the same two maps. A 6-wave, 2-map A/B separates a
halving; it does not separate ten percent.

## A thrown native takes the rest of the callback with it

SourcePawn has no way to catch one, so a native that throws is a `return` you
did not write, from wherever it happened, skipping every line after it.

Two of these have cost real time:

- `ActionsManager.Iterator` throws on a client that is not a NextBot. The
  test-bed's seat-holder is an ordinary fake client, so the first client of
  every telemetry pass killed the whole pass and the results file simply never
  appeared.
- `TF2Util_EquipPlayerWearable` asserts that the wearable ended up attached and
  throws when the game declines it. The hat entity is created a few lines
  earlier, so every refusal leaks a `tf_wearable` that nobody wears and nothing
  frees. A server that leaks an edict per bot per respawn runs out of them.

So: check the precondition yourself where you can, and where you cannot, make
the failure harmless. The wearables are swept at every wave start rather than
prevented, because whether the game will accept one cannot be asked in advance.

## The failsafe

`UpdateStuckWatchdog` in `nextbot_behavior.sp` catches the shared symptom: a bot
that is pathing somewhere and has not moved 72 units in 12 seconds gets its
behaviour thrown away and rebuilt, and the fact is printed with the action stack.
It only fires while the bot is asking to go somewhere, so an engineer at a
finished nest and a sniper on his perch do not trip it.

It fixes nothing. It makes silent failures loud, which is the part that was
missing.
