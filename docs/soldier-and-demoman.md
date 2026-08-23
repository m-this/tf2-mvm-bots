# The soldier and the demoman

The two seats that fight with an arcing, exploding projectile, and the two
lowest-scoring seats on the team. Every number here came out of
`testbed/report`.

## The baseline

```
class      damage per wave   (30 waves, two maps)
heavy         4787
scout         3278
engineer      2903
pyro          2335
demoman       1608
soldier       1004
```

## What it is not

**It is not accuracy.** Six waves on Decoy:

```
projectiles   soldier 465 fired, 187 hit (40%);  demoman 302 fired, 130 hit (43%)
```

Forty percent with a projectile that arcs, against robots that are walking, is
not a bot that cannot shoot.

**It is not that they stand too close.** The Demoman's median distance to the
nearest robot is 1044 units, which is further out than the 600 his own attack
action is trying to close him to.

**It is not one half of the demoman's kit.** Pipes and stickies both land:
`pipes 4164, stickies 3922` over six waves. The stickybomb detonation rule
works.

## What it is

```
hurt themselves    soldier 3988   demoman 2380   (six waves)
soldier damage     rockets 16721
killed themselves  soldier 4
```

**A quarter of the Soldier's output goes into his own feet**, and it kills him
four times in six waves. The Demoman gives up about a sixth the same way.

**And trying to stop it made everything worse.** `explosive_min_range` gave the
Soldier his shotgun inside 220 units and stopped him aiming at feet inside 350.
Six waves on Decoy against six without:

```
                        ON      OFF
soldier damage       10886    16890
soldier accuracy       40%      60%
soldier self-kills       3        6
demoman damage        8269    11265
defender deaths         47       28
```

The hit rate is the explanation. **The ground does not move and a robot does.**
A rocket at the floor lands and splashes whatever the robot did next; one aimed
at a chest arrives where the chest was. The splash he catches is the price of
the shots that land at all, and it is a price worth paying: he traded a third
of his damage for three fewer self-kills, and the team died more anyway.

So the self-damage is real, it is large, and it is not a defect. Two of the
three things below are gone.

The original reasoning, kept because it is the reasoning anyone will have:

1. **No minimum range on an explosive.** `EquipBestWeaponForThreat` never asked
   how near the threat was, so a Soldier fired rockets into whatever walked up
   to him. He carries a shotgun that does not explode; the Demoman carries a
   bottle.
2. **Feet-aiming had no lower bound.** Shooting the ground makes a rocket
   unreflectable and catches a crowd, and both are worth having at a distance.
   Up close the ground under the robot is the ground under the Soldier — and
   the rule fires unconditionally on robot Pyros, which are the class that
   closes to his face. The shot written to dodge a reflection was the one
   making the splash.
3. **Blast resistance was priced by the wave.** Resistances are ranked by what
   the coming robots carry, which is the right question for damage somebody
   else deals. These two explode themselves in every wave whatever the robots
   are made of, so the resistance has a floor for them now.

**Blast resistance did not pay either.** `blast_resist_self` put a floor under
the resistance for these two, on the grounds that their own weapons are in
every wave. Six waves on Decoy each way:

```
                        ON      OFF
soldier self-damage   2147     3272     <- the resistance works
soldier self-kills       1        3
soldier damage       13485    14187
waves cleared            3        3
defender deaths         50       40
```

The mechanism does what it says and buys nothing with it. Credits spent there
come out of upgrades that produce damage, and on this harness a five percent
swing over six waves is inside the noise. Deleted.

## Still open

The Soldier's rocket launcher has no entry in `weapon_tuning.sp` and falls
through to a 1250-unit desired range, while every comparable explosive in the
table sits at 600–650 (Loose Cannon 650, Iron Bomber 600, Beggar's 600). A
rocket takes over a second to cross 1250 units and the blast covers 146 of
them. `soldier_closes_in` (750) is written and not yet measured.

Whether it matters depends on the item below, because a desired range only
means something if he can act on it.

## The path bug reaches both of them

`ComputeToTarget` returns a bool and every one of the mod's twenty-one call
sites discarded it. An empty path walks the bot nowhere while the behaviour
above believes it is travelling. It was fixed in `PluginBot_SimulateFrame`
first and nowhere else, which left `attack.sp` — the action every fighting
class spends 40–56% of its samples in — still holding bots at whatever range
the mesh happened to refuse at.

That is the likeliest reason the Demoman sits at 1044 units while asking to be
at 600. `attack_path_nudge` covers it and is not yet measured.
