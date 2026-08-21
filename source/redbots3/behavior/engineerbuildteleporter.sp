/* A teleporter, but only when it costs the team nothing

An engineer is a sentry and the metal that keeps it firing. Everything here is what he does with
the time left over, so it happens between rounds, with the nest already standing, and it is
abandoned the moment the sentry needs him. A wave that arrives to find the engineer walking back
from spawn with a teleporter in his hands has already been made worse by it.

The entrance goes on the way out of spawn, read off the nav mesh's own route rather than guessed
from spawn geometry, and the exit goes beside the nest rather than on top of it. */

/* One half of a teleporter, walk included

The entrance is at the far end of the map from the nest, so most of this is walking: Coaltown is
about ten seconds each way at an engineer's speed, and the attempts after that are a few seconds
each. Short enough that a wave never starts without the engineer, and the readiness grace bounds
the pair of them whatever this says. */
#define TELEPORTER_BUILD_MAX_TIME	40.0

/* How long he may spend walking to where the exit goes before he builds it where he stands

The same rock the dispenser found on Rottenburg. A nav mesh says ground is connected; it does not
promise a bot can squeeze past a boulder to reach the middle of it, and the old code asked again
next frame forever.

The exit only. He is standing at his nest when this runs out, which is where an exit belongs
anyway, so building it there costs nothing. The entrance has the length of the map to walk and no
business being dropped wherever the walk stopped, so it is bounded by the build time above and
gives up rather than settling. */
#define TELEPORTER_EXIT_REACH_TIME	12.0

//He stands a build's reach short of where it goes, because a building lands in front of the man
#define TELEPORTER_BUILD_REACH		90.0

/* Stepping out of the spawn door until the floor takes it

An entrance belongs where a player leaving spawn walks into it, so the first attempt is a little
way out of the door and each one after it is a step further along the route to the nest. A doorway
itself never takes one, and neither does the ground a respawning player stands on. */
#define TELEPORTER_SPAWN_OFFSET		200.0
#define TELEPORTER_SPAWN_STEP		150.0

/* The exit stands off the nest centre rather than on it

The nest centre is where the sentry is, so eight stand points looking at the centre are eight
looks at the sentry and eight refusals. The spot walks round the nest instead, and he stands
between the two: far enough out not to be inside his own sentry, a build's reach short of where
the exit goes. */
#define TELEPORTER_EXIT_RADIUS		150.0

#define TELEPORTER_TRY_POINTS		8
#define TELEPORTER_TRY_TIME			1.5

float m_ctTeleporterGiveUp[MAXPLAYERS + 1];
float m_ctTeleporterReachDeadline[MAXPLAYERS + 1];
float m_ctTeleporterTryDeadline[MAXPLAYERS + 1];
int m_iTeleporterTry[MAXPLAYERS + 1];
TFObjectMode m_nTeleporterMode[MAXPLAYERS + 1];
float m_vTeleporterSpot[MAXPLAYERS + 1][3];
float m_vTeleporterStand[MAXPLAYERS + 1][3];
float m_vTeleporterSpawn[MAXPLAYERS + 1][3];
float m_vTeleporterNest[MAXPLAYERS + 1][3];
/* The way out of spawn, read once while he is still standing at the far end of it

Read per attempt instead, it was read from wherever he had walked to, and the second attempt asked
a two hundred and ninety unit route for a point three hundred and fifty units from spawn. He tried
one place on Coaltown and gave up. */
float m_vTeleporterRouteSpot[MAXPLAYERS + 1][TELEPORTER_TRY_POINTS][3];
float m_vTeleporterRouteStand[MAXPLAYERS + 1][TELEPORTER_TRY_POINTS][3];
int m_iTeleporterRoutePoints[MAXPLAYERS + 1];
//The map named the spot, so the attempts walk around it instead of out of the spawn door
bool m_bTeleporterNamedSpot[MAXPLAYERS + 1];
/* He tried everything and none of it worked, so he stops asking until the next wave is over

Without this the idle action suspends into this one again the moment it ends, which is an engineer
walking the same refused route for the rest of the round, and readiness waiting on him while he
does it. */
bool m_bTeleporterGaveUp[MAXPLAYERS + 1];
//Why the last attempt ended, for sm_dump_nest, since every give-up looks the same from outside
char m_sTeleporterLastResult[MAXPLAYERS + 1][64];

BehaviorAction CTFBotMvMEngineerBuildTeleporter()
{
	BehaviorAction action = ActionsManager.Create("DefenderBuildTeleporter");

	action.OnStart = CTFBotMvMEngineerBuildTeleporter_OnStart;
	action.Update = CTFBotMvMEngineerBuildTeleporter_Update;
	action.OnEnd = CTFBotMvMEngineerBuildTeleporter_OnEnd;

	return action;
}

public Action CTFBotMvMEngineerBuildTeleporter_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_ctTeleporterGiveUp[actor] = GetGameTime() + TELEPORTER_BUILD_MAX_TIME;
	m_ctTeleporterReachDeadline[actor] = GetGameTime() + TELEPORTER_EXIT_REACH_TIME;
	m_ctTeleporterTryDeadline[actor] = GetGameTime() + TELEPORTER_TRY_TIME;
	m_iTeleporterTry[actor] = 0;
	m_iTeleporterRoutePoints[actor] = 0;

	//While he is at his nest, which is the only place the whole route can be read from
	if (m_nTeleporterMode[actor] == TFObjectMode_Entrance && !m_bTeleporterNamedSpot[actor])
		m_iTeleporterRoutePoints[actor] = SpawnRoutePoints(actor, m_vTeleporterSpawn[actor],
			TELEPORTER_SPAWN_OFFSET, TELEPORTER_SPAWN_STEP, TELEPORTER_BUILD_REACH,
			m_vTeleporterRouteSpot[actor], m_vTeleporterRouteStand[actor], TELEPORTER_TRY_POINTS);

	if (!TeleporterStandPoint(actor))
	{
		m_bTeleporterGaveUp[actor] = true;

		return TeleporterDone(action, actor, "No route out of spawn to walk");
	}

	UpdateLookAroundForEnemies(actor, true);

	return action.Continue();
}

public Action CTFBotMvMEngineerBuildTeleporter_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	//The sentry outranks this, always
	if (GameRules_GetRoundState() != RoundState_BetweenRounds)
		return TeleporterDone(action, actor, "Wave started");

	if (GetObjectOfType(actor, TFObject_Sentry) == INVALID_ENT_REFERENCE)
		return TeleporterDone(action, actor, "No sentry to leave behind");

	if (GetObjectOfType(actor, TFObject_Teleporter, m_nTeleporterMode[actor]) != INVALID_ENT_REFERENCE)
	{
		g_arrPluginBot[actor].bPathing = false;

		return TeleporterDone(action, actor, "Built one");
	}

	if (m_ctTeleporterGiveUp[actor] < GetGameTime())
	{
		m_bTeleporterGaveUp[actor] = true;

		return TeleporterDone(action, actor, "Ran out of time");
	}

	float spot[3]; spot = m_vTeleporterSpot[actor];
	float stand[3]; stand = m_vTeleporterStand[actor];

	//The walk to the exit ran out, so it goes down where he stands, which is his own nest
	bool outOfTime = m_nTeleporterMode[actor] == TFObjectMode_Exit
		&& GetGameTime() > m_ctTeleporterReachDeadline[actor];

	if (outOfTime)
		stand = GetAbsOrigin(actor);

	float range = GetVectorDistance(GetAbsOrigin(actor), stand);

	INextBot myNextbot = CBaseNPC_GetNextBotOfEntity(actor);
	IBody myBody = myNextbot.GetBodyInterface();

	//The toolbox comes out on the way in, so arriving is not another two seconds of standing about
	if (range < 200.0)
	{
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, m_nTeleporterMode[actor] == TFObjectMode_Entrance ? "build 1 0" : "build 1 1");

		//It goes where he looks, so he looks at the spot
		AimHeadTowards(myBody, spot, MANDATORY, 0.1, _, "Placing teleporter");
	}

	if (range > 70.0)
	{
		//The clock on this attempt starts when he arrives: the walk to it is not a look at it
		m_ctTeleporterTryDeadline[actor] = GetGameTime() + TELEPORTER_TRY_TIME;

		g_arrPluginBot[actor].SetPathGoalVector(stand);
		g_arrPluginBot[actor].bPathing = true;

		return action.Continue();
	}

	g_arrPluginBot[actor].bPathing = false;

	int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);

	if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_BUILDER)
	{
		int objBeingBuilt = GetEntPropEnt(myWeapon, Prop_Send, "m_hObjectBeingBuilt");

		//The toolbox is out but the game has not decided yet
		if (objBeingBuilt == -1)
			return action.Continue();

		/* This floor will not take it, so try the next place that might

		Only once he is actually looking at the spot: the answer while his head is still coming
		round is the answer for wherever it was pointing, which is not this spot. */
		if (!IsPlacementOK(objBeingBuilt) && !outOfTime
			&& myBody.IsHeadAimingOnTarget() && GetGameTime() > m_ctTeleporterTryDeadline[actor])
		{
			m_iTeleporterTry[actor]++;

			if (m_iTeleporterTry[actor] >= TELEPORTER_TRY_POINTS || !TeleporterStandPoint(actor))
			{
				//The exit goes down here, and an entrance nowhere near the spawn door goes nowhere
				if (m_nTeleporterMode[actor] != TFObjectMode_Exit)
				{
					m_bTeleporterGaveUp[actor] = true;

					return TeleporterDone(action, actor, "Nowhere out of spawn takes one");
				}

				m_ctTeleporterReachDeadline[actor] = GetGameTime();

				return action.Continue();
			}

			m_ctTeleporterReachDeadline[actor] = GetGameTime() + TELEPORTER_EXIT_REACH_TIME;

			return action.Continue();
		}
	}

	VS_PressFireButton(actor);

	return action.Continue();
}

/* Where this attempt puts the building, and where he stands to put it there

Three shapes, because the three cases are not the same question. A spot the map named is one spot
and the man walks round it. The way out of spawn is a route rather than a spot, so the attempts
walk along it, reading the points sampled off it when the action started. The exit has no spot at
all, only a nest, so the spot walks round the nest and the man stands between the two.

False when this attempt has nowhere left to put anything, which is the caller's cue to stop. */
static bool TeleporterStandPoint(int actor)
{
	int attempt = m_iTeleporterTry[actor];

	if (m_bTeleporterNamedSpot[actor])
	{
		BuildStandPoint(m_vTeleporterSpot[actor], GetAbsOrigin(actor), attempt,
			TELEPORTER_TRY_POINTS, TELEPORTER_BUILD_REACH, m_vTeleporterStand[actor]);

		return true;
	}

	if (m_nTeleporterMode[actor] == TFObjectMode_Exit)
	{
		float nest[3]; nest = m_vTeleporterNest[actor];

		//Both on the same ray out of the nest, so he stands a build's reach short of the spot
		BuildStandPoint(nest, GetAbsOrigin(actor), attempt,
			TELEPORTER_TRY_POINTS, TELEPORTER_EXIT_RADIUS, m_vTeleporterSpot[actor]);

		BuildStandPoint(nest, GetAbsOrigin(actor), attempt,
			TELEPORTER_TRY_POINTS, TELEPORTER_EXIT_RADIUS - TELEPORTER_BUILD_REACH, m_vTeleporterStand[actor]);

		return true;
	}

	if (attempt >= m_iTeleporterRoutePoints[actor])
		return false;

	m_vTeleporterSpot[actor] = m_vTeleporterRouteSpot[actor][attempt];
	m_vTeleporterStand[actor] = m_vTeleporterRouteStand[actor][attempt];

	return true;
}

//Every way this action can end goes through here, so the reason survives it
static Action TeleporterDone(BehaviorAction action, int actor, const char[] reason)
{
	strcopy(m_sTeleporterLastResult[actor], sizeof(m_sTeleporterLastResult[]), reason);

	return action.Done(reason);
}

public void CTFBotMvMEngineerBuildTeleporter_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	g_arrPluginBot[actor].bPathing = false;

	UpdateLookAroundForEnemies(actor, true);
}

void EngineerTeleporter_LastResult(int actor, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, m_sTeleporterLastResult[actor][0] == '\0' ? "nothing yet" : m_sTeleporterLastResult[actor]);
}

bool EngineerTeleporter_HasGivenUp(int actor)
{
	return m_bTeleporterGaveUp[actor];
}

TFObjectMode EngineerTeleporter_Mode(int actor)
{
	return m_nTeleporterMode[actor];
}

void EngineerTeleporter_Spot(int actor, float spot[3])
{
	spot = m_vTeleporterSpot[actor];
}

//A new wave is a new chance, and whatever refused him last time may have been a body standing on it
void EngineerTeleporter_ForgetGivingUp()
{
	for (int i = 1; i <= MaxClients; i++)
		m_bTeleporterGaveUp[i] = false;
}

/* The half of the teleporter this engineer should go build, or none

Entrance before exit: an exit alone moves nobody, and the pair is only worth the metal once both
ends stand. The entrance spot comes from the map configuration when it names one and from the way
out of spawn when it does not, which is every official map; the exit goes beside the nest. */
bool ShouldBuildTeleporter(int actor)
{
	if (GameRules_GetRoundState() != RoundState_BetweenRounds)
		return false;

	if (m_bTeleporterGaveUp[actor])
		return false;

	//The nest comes first and it is not finished
	if (GetObjectOfType(actor, TFObject_Sentry) == INVALID_ENT_REFERENCE)
		return false;

	if (GetObjectOfType(actor, TFObject_Dispenser) == INVALID_ENT_REFERENCE)
		return false;

	if (m_aNestArea[actor] == NULL_AREA)
		return false;

	NestBuildPosition(m_aNestArea[actor], m_vTeleporterNest[actor]);

	if (GetObjectOfType(actor, TFObject_Teleporter, TFObjectMode_Entrance) == INVALID_ENT_REFERENCE)
	{
		m_nTeleporterMode[actor] = TFObjectMode_Entrance;

		m_bTeleporterNamedSpot[actor] = NearestConfiguredSpot(g_arrMapConfig.adtTeleporterEntranceLocation,
			GetAbsOrigin(actor), m_vTeleporterSpot[actor]);

		if (m_bTeleporterNamedSpot[actor])
			return true;

		//The map named none, which is most of them, so he walks out of spawn until the floor takes it
		return NearestSpawnPoint(actor, m_vTeleporterSpawn[actor]);
	}

	if (GetObjectOfType(actor, TFObject_Teleporter, TFObjectMode_Exit) == INVALID_ENT_REFERENCE)
	{
		m_nTeleporterMode[actor] = TFObjectMode_Exit;

		//The nest itself when the map names no exit: the point of the pair is to arrive at the nest
		m_bTeleporterNamedSpot[actor] = NearestConfiguredSpot(g_arrMapConfig.adtTeleporterExitLocation,
			m_vTeleporterNest[actor], m_vTeleporterSpot[actor]);

		return true;
	}

	return false;
}

//False when the map names no spot of this kind, which is most of them
bool NearestConfiguredSpot(ArrayList spots, const float from[3], float spot[3])
{
	float nearest = -1.0;

	for (int i = 0; i < spots.Length; i++)
	{
		float candidate[3]; spots.GetArray(i, candidate);

		float distance = GetVectorDistance(from, candidate);

		if (nearest < 0.0 || distance < nearest)
		{
			nearest = distance;
			spot = candidate;
		}
	}

	return nearest >= 0.0;
}
