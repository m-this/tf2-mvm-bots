/* Generated from internal/threat. Do not edit.

What a robot is worth killing first. The numbers are an order, not a measurement: the caller
compares two of them and takes the larger, so only the ordering means anything.

Anything inside THREAT_URGENT_RANGE outranks the list. A bot that ignores the Heavy in front of it
to shoot a Sniper across the map dies holding a good idea.

Both distances were widened after measuring. At 400 units the order was costing more than it
bought: ten runs on Decoy put defender deaths at 54 against the old code's 43, for the same waves
cleared. 400 is a rocket's splash, not a firefight, so a bot would walk its aim off the Heavy
shooting it as soon as anything better appeared anywhere. And a priority target beyond
THREAT_PRIORITY_RANGE is not a target, it is a plan: past that the nearest one wins. */

#define THREAT_URGENT_RANGE		750.0
#define THREAT_PRIORITY_RANGE	1500.0

enum
{
	THREAT_PRIORITY_NONE = 0,
	THREAT_PRIORITY_BOMB,
	THREAT_PRIORITY_GIANT,
	THREAT_PRIORITY_GIANT_BOMB,
	THREAT_PRIORITY_SUPPORT,
	THREAT_PRIORITY_MEDIC,
	THREAT_PRIORITY_URGENT,
};

#define THREAT_BANDS		3
#define THREAT_CLASSES		10
#define THREAT_FLAGS		16

/* Which side of the two range comparisons a target falls on

Both tests are strict, so a range exactly on a boundary is in the band above it. This is the whole
of what the decision reads about a distance. */
stock int ThreatBand(float rangeSq)
{
	if (rangeSq < THREAT_URGENT_RANGE * THREAT_URGENT_RANGE)
		return 0;
	
	if (rangeSq > THREAT_PRIORITY_RANGE * THREAT_PRIORITY_RANGE)
		return 2;
	
	return 1;
}

static const int g_ThreatPriority[THREAT_BANDS * THREAT_CLASSES * THREAT_FLAGS] =
{
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 3,
	0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 3,
	0, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 4,
	0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 3,
	0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 3,
	0, 0, 0, 5, 0, 0, 0, 5, 0, 0, 0, 5, 0, 0, 0, 5,
	0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 3,
	0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 3,
	0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 3,
	0, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 4,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

/* What one threat is worth, from what the caller already knows about it

A record rather than an entity index, which is the point of the move. Whoever fills this decides
what counts as a threat, and this decides what it is worth. Every scan in the mod that finds one
walks player slots, and a tank occupies none, which is mvm-ds3: not fixed here, and fixable here
for the first time.

isPlayer and inGame are read as one pair because the shipped code tested them together, and the
caller has to fill them the same way: the shipped test is || and short circuits, so IsClientInGame
is never reached for a non-player. Calling it anyway to fill this record throws "Client index is
invalid" on every tank in the game. Fill inGame as isPlayer && IsClientInGame(threat). */
stock int ThreatPriorityOf(float rangeSq, bool isPlayer, bool inGame, TFClassType pclass, bool giant, bool carrier)
{
	int flags = (isPlayer ? 1 : 0) | (inGame ? 2 : 0) | (giant ? 4 : 0) | (carrier ? 8 : 0);
	int index = (ThreatBand(rangeSq) * THREAT_CLASSES + view_as<int>(pclass)) * THREAT_FLAGS + flags;
	
	return g_ThreatPriority[index];
}
