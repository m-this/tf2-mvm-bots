# TODO

What the bots still need. Every item says where it stands and what blocks it.

## 1. Per-map engineer and teleporter data. Open

`configs/defenderbots/map/*.cfg` carries a `SniperSpot` block for all 27 maps
and nothing else. The code reads three more blocks and finds them empty:

- `EngineerNest`, ground for an engineer to hold. `PickConfiguredNestArea`
  prefers these over anything the nav mesh reasoning arrives at, and scores
  them, so several spots spread several engineers instead of stacking them.
- `TeleporterEntrance`, near the spawn the engineer walks back to.
- `TeleporterExit`, near the nest it feeds.

An engineer builds no teleporter until a map names both teleporter blocks.
That is deliberate. A guessed entrance lands in a doorway on half the maps.
A bot walking back to spawn mid-wave also costs the team more than the
teleporter returns.

The compiled map does not hold this data. It is somebody standing on the
ground and deciding it is the spot. `sm_dump_spot <block>` prints the standing
position as the configuration line to paste, and logs it, so you author the
data in the map:

```
sm_dump_spot EngineerNest
sm_dump_spot TeleporterEntrance
sm_dump_spot TeleporterExit
```

Start with the six official maps: `mvm_coaltown`, `mvm_decoy`,
`mvm_mannworks`, `mvm_bigrock`, `mvm_rottenburg`, `mvm_mannhattan`. Three to
five nest spots per map is enough for a six-bot team.

## 2. Demoman stickies do nothing. Open

A bot carrying the stock Stickybomb Launcher fires bombs that never explode.
Nothing in this repository detonates them: there is no read of
`m_iPipebombCount` and no alt-fire detonation anywhere. `EvalTankWeapon_Demo`
in `behavior/attacktank.sp` scores `TF_WEAPON_PIPEBOMBLAUNCHER` at 0, so the
weapon is never chosen against a tank either.

Stickies are the largest damage a Demoman has in Mann vs Machine. This is the
biggest single hole in what the bots do to robots.

What it needs:

- Lay a trap. Aim at the ground the robots walk over, not at a robot, and fire
  a bounded number of bombs. The launcher holds eight.
- Detonate. Press alt-fire when enough robots stand inside the blast.
  `ShouldAimRocketsAtFeet` in `botaim.sp` answers the same question for a
  soldier.
- Score the weapon against a tank. A full clip of stickies under a tank is
  worth more than the same clip of pipes thrown at it.
- Charge a Quickiebomb or Scottish Resistance differently, or refuse the item
  and let the loadout code pick a launcher the behaviour handles.

Every count needs a ceiling: bombs laid, and bombs held. A trap also needs a
deadline, after which the bot drops it and goes back to shooting.
