# The engineer and the medic

The two classes that keep being reported as useless, what was actually wrong
with them, and what is still open. Every number here came out of
`testbed/report` or `testbed/sweepreport`; nothing in this file is an
impression.

## What was wrong with the engineer

Almost none of it was placement, which is where the reports pointed.

| symptom | cause | state |
|---|---|---|
| dispenser beside the teleporter entrance | the build guard asked whether the toolbox was in his hands, not what it was set to build, so he pressed fire on a toolbox still set to the last job | fixed |
| two dispensers, one engineer | same cause; `DetonateObjectOfType` then removed only the first of them, so the stray outlived every wave | fixed both ends |
| dispenser not on the authored spot | four separate rules discarded authored coordinates. The last was a path query asked from wherever he stood: it answers from the nest before wave one and refuses from the upgrade station between later waves | fixed |
| perfectly good buildings destroyed between waves | everything came down after every shopping trip | fixed: finished buildings survive an unmoved nest |
| not repairing his buildings | the dispenser branch came before the sentry branch and returned, so he polished a dispenser while the sentry was destroyed | fixed |
| stuck in spawn, stuck holding a toolbox | build stand points were computed at the spot's own height with nothing checking there was ground there | fixed: snapped to the nav mesh, refused a storey off |

### What is actually costing the team

```
no sentry standing        58% of samples (coaltown, six waves)
  engineer dead           34% of that
  alive, >1200u from nest 55% of that
```

The nest is fine and the build works. **More than half the time the team has no
sentry, the engineer is alive and walking back from spawn**, three and a half
thousand units on Coaltown. That is the thing worth attacking, and it was
invisible until the telemetry existed: "he never built one", "he built it and
lost it" and "he is on his way" all read identically from a wave line.

The build cycle log is what found it. `started` with no exit reason, then
`started` again ninety-eight seconds later — nothing else produces a missing
exit, because dying tears an action down without its update ever running.

## What was wrong with the medic

Three distinct causes, all producing "the medic is somewhere useless", found in
this order:

1. **Patient oscillation.** Two orderings disagreed: picking preferred a nearby
   man, switching used a class ranking that did not know where anybody was. So
   a far Heavy took the beam off whoever stood in front of him, every check, and
   the medic walked to the midpoint and stayed there. Fixed with one ordering.
2. **Dead-end paths.** `ComputeToTarget` returns a bool and it was discarded, so
   a refusal left an empty path and he stood still believing he was walking.
   This was the real "stuck in the middle of Coaltown". Fixed, and time on
   target went from 4% to about 30%.
3. **Spawn camping.** He picks a teammate who has just respawned, that teammate
   is inside his follow range, so he never moves — and the pair sit in the
   respawn room for a whole wave.

Cause 3 turned out to be **the test bed, not the mod**, and everything written
about it below is void. See the correction at the end of this section before
reading any of it.

## Two A/Bs that lost, and the reason they are all void

> **Void.** Every measurement in this section was taken with a fake client
> standing in the RED spawn at full health, never moving, which
> `PreferredPatient` ranks above every real teammate on the map. The medic
> pocketed it for the whole of every wave. What these A/Bs actually measured is
> whether a change can beat pocketing a statue, and nothing can, because leaving
> the statue means walking. The seat holder is a Medic now — the one class the
> ranking skips — and the medic's median distance to the nearest robot went from
> 2281 units to 991 with no change to the mod at all. The write-ups are kept
> because the reasoning in them is still the reasoning a future attempt will
> have, and because a deleted mistake teaches nobody. The numbers are not
> evidence of anything.

Kept here because both looked obviously right, and the reasoning that made them
look right is the reasoning a future attempt will have.

**`medic_nearest`** — out of reach of everybody, walk to the closest man rather
than the highest ranked. Twelve waves, two maps:

```
                  ON      OFF
healing         7481    14592
beam connected    33%      35%
```

Healing is measured in health restored and a Heavy is where health goes. The
beam spends the same seconds either way; on the big body they are worth twice
as much, so arriving late on a Heavy beats arriving early on a Scout nobody is
shooting.

**`medic_leaves_spawn`** — a man safe in the respawn room is not a patient.
Excluding him: healing 13566 → 10592, and he spent *more* of the wave in the
spawn. Ranking him last instead: 9089 → 6901, time on target 43% → 15%.

**`medic_holds_ground`** — keep him as a patient, but do not walk into the
spawn after him. This one could not end the heal action, which was what killed
the other two. It lost anyway: time on target 46% → 26%, healing 11312 → 11159.
A medic who does not walk does not close, so the beam that was going to connect
never does. The near-identical healing is the useful part: it says the spawn
trips were not costing much to begin with.

Both lost for the same reason, which is now a rule in
[how-bots-break.md](how-bots-break.md): an empty candidate list ends the
behaviour and hands the bot to the game's own code, which is worse than any
patient. Rank last, never remove.

**`engineer_rides_home`** — an engineer with no sentry, far from his nest,
takes his own teleporter instead of walking. Twelve waves, two maps:

```
                        ON     OFF
sentry standing        54%     69%
worst gap             125s     95s
no-sentry samples
  walking               58      20
```

Saying yes to `ShouldUseTeleporter` does not put the bot on a teleporter. It
lets the game's tactical monitor look for one, and the entrance is back in the
spawn he is trying to leave — so the walk it saves is shorter than the walk it
costs, and he spent nearly three times as long walking. The measurement that
suggested the change was sound; the mechanism was not the one I assumed.

## Reading a change on these two classes

Waves cleared will not settle it. The medic A/Bs came out 6/6 against 5/7 and
6/6 against 7/5 — noise, because clear rate is dominated by everything else.

Use the number the change is aimed at:

- medic: **healing delivered** and **beam connected %**
- engineer: **sentry uptime** and **longest gap with no sentry**

And beware variance: the same OFF arm measured 29%, 35% and 43% beam time on
three runs of the same two maps. A six-wave, two-map A/B separates a halving.
It does not separate ten percent.
