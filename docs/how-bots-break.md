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

## The failsafe

`UpdateStuckWatchdog` in `nextbot_behavior.sp` catches the shared symptom: a bot
that is pathing somewhere and has not moved 72 units in 12 seconds gets its
behaviour thrown away and rebuilt, and the fact is printed with the action stack.
It only fires while the bot is asking to go somewhere, so an engineer at a
finished nest and a sniper on his perch do not trip it.

It fixes nothing. It makes silent failures loud, which is the part that was
missing.
