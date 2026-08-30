# Recover a managed defender that leaves RED

## Report

One managed defender no longer counted on RED during an MvM wave. The manager
then logged that RED held five of six and requested one replacement every
second. Every request failed because the server had no free client slot.

Purging the managed defenders recovered the game immediately: the existing
fill path recreated the lineup and every replacement joined RED.

## Cause

The manager marks each defender client after it joins RED. Its `player_team`
handler previously ignored every fake client, including an already-marked
defender that moved away from RED. That left two facts which could not converge:

- RED was one defender short, so the imbalance timer requested a replacement;
- the misplaced defender still occupied a client slot, so a full server could
  not create that replacement.

The temporary client name used while creating a bot is gone by this point, so
an operator also cannot reliably address the misplaced client by that name.

## Invariant and recovery

An identified managed defender belongs on RED for the rest of its connection.
If a non-disconnect team event moves it from RED to another team, remove that
client and its buildings. The existing imbalance timer then owns the recovery:
it sees the empty RED seat and creates one replacement through the normal join,
loadout and currency path.

The recovery is deliberately narrower than the successful manual purge. It
does not remove healthy defenders, ordinary BLU robots or humans, and it ignores
the team event emitted by an intentional disconnect.

## Verification

The SourcePawn plugin and the test-bed plugins compile with the recovery.

A live verification still has to force one identified defender from RED during
a managed wave and confirm all four outcomes:

1. only that defender is removed;
2. its buildings do not remain orphaned;
3. one replacement joins RED through the normal fill path;
4. replacement requests do not repeat after RED is full.
