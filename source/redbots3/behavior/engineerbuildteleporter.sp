/* A teleporter, but only when it costs the team nothing

An engineer is a sentry and the metal that keeps it firing. Everything here is what he does with
the time left over, so it happens between rounds, with the nest already standing, and it is
abandoned the moment the sentry needs him. A wave that arrives to find the engineer walking back
from spawn with a teleporter in his hands has already been made worse by it.

The spots come from the map configuration and nowhere else. Guessing an entrance from spawn
geometry puts it in a doorway on half the maps, so a map that names no spots gets no teleporter */

//Long enough to walk the length of a map, short enough that a wave never starts without the engineer
#define TELEPORTER_BUILD_MAX_TIME 25.0

/* Stepping out of the spawn until the floor takes it

An entrance belongs where a player leaving spawn walks into it, so the walk starts a little way
out of the door and steps further along the way to the nest until the game stops refusing. A
doorway itself never takes one, and neither does the ground a respawning player stands on.

He stands a build's reach short of where it goes, because a building lands in front of the man
and not under him. */
#define TELEPORTER_BUILD_REACH		90.0
#define TELEPORTER_SPAWN_OFFSET		200.0
#define TELEPORTER_SPAWN_STEP		150.0
#define TELEPORTER_TRY_POINTS		8
#define TELEPORTER_TRY_TIME			1.5

float m_ctTeleporterGiveUp[MAXPLAYERS + 1];
float m_ctTeleporterTryDeadline[MAXPLAYERS + 1];
int m_iTeleporterTry[MAXPLAYERS + 1];
TFObjectMode m_nTeleporterMode[MAXPLAYERS + 1];
float m_vTeleporterSpot[MAXPLAYERS + 1][3];
float m_vTeleporterStand[MAXPLAYERS + 1][3];
float m_vTeleporterSpawn[MAXPLAYERS + 1][3];
//Empty when the map named the spot, and the way out of spawn when it did not
float m_vTeleporterPathOut[MAXPLAYERS + 1][3];

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
	m_ctTeleporterTryDeadline[actor] = GetGameTime() + TELEPORTER_TRY_TIME;
	m_iTeleporterTry[actor] = 0;

	TeleporterStandPoint(actor);

	UpdateLookAroundForEnemies(actor, true);

	return action.Continue();
}

public Action CTFBotMvMEngineerBuildTeleporter_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	//The sentry outranks this, always
	if (GameRules_GetRoundState() != RoundState_BetweenRounds)
		return action.Done("Wave started");

	if (GetObjectOfType(actor, TFObject_Sentry) == INVALID_ENT_REFERENCE)
		return action.Done("No sentry to leave behind");

	if (m_ctTeleporterGiveUp[actor] < GetGameTime())
		return action.Done("Took too long to build a teleporter");

	if (GetObjectOfType(actor, TFObject_Teleporter, m_nTeleporterMode[actor]) != INVALID_ENT_REFERENCE)
	{
		g_arrPluginBot[actor].bPathing = false;

		return action.Done("Built a teleporter");
	}

	float spot[3]; spot = m_vTeleporterSpot[actor];
	float stand[3]; stand = m_vTeleporterStand[actor];
	float range = GetVectorDistance(GetAbsOrigin(actor), stand);

	if (range > 70.0)
	{
		g_arrPluginBot[actor].SetPathGoalVector(stand);
		g_arrPluginBot[actor].bPathing = true;

		return action.Continue();
	}

	g_arrPluginBot[actor].bPathing = false;

	if (!IsWeapon(actor, TF_WEAPON_BUILDER))
	{
		FakeClientCommandThrottled(actor, m_nTeleporterMode[actor] == TFObjectMode_Entrance ? "build 1 0" : "build 1 1");

		return action.Continue();
	}

	INextBot myNextbot = CBaseNPC_GetNextBotOfEntity(actor);
	IBody myBody = myNextbot.GetBodyInterface();

	AimHeadTowards(myBody, spot, MANDATORY, 0.1, _, "Placing teleporter");

	int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);

	if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_BUILDER)
	{
		int objBeingBuilt = GetEntPropEnt(myWeapon, Prop_Send, "m_hObjectBeingBuilt");

		if (objBeingBuilt == -1)
			return action.Continue();

		//This floor will not take it, so walk on to the next place that might
		if (!IsPlacementOK(objBeingBuilt) && myBody.IsHeadAimingOnTarget()
			&& GetGameTime() > m_ctTeleporterTryDeadline[actor])
		{
			m_iTeleporterTry[actor]++;

			TeleporterStandPoint(actor);

			m_ctTeleporterTryDeadline[actor] = GetGameTime() + TELEPORTER_TRY_TIME;

			return action.Continue();
		}
	}

	VS_PressFireButton(actor);

	return action.Continue();
}

/* Where this attempt puts the building, and where he stands to put it there

A spot the map named is one spot and the attempts walk around it. The way out of spawn is a line
rather than a spot, so the attempts walk along it instead: each one is a step further from the
door, which is the nearest floor to spawn that will take an entrance. */
static void TeleporterStandPoint(int actor)
{
	int attempt = m_iTeleporterTry[actor] % TELEPORTER_TRY_POINTS;
	float pathOut[3]; pathOut = m_vTeleporterPathOut[actor];

	if (IsZeroVector(pathOut))
	{
		BuildStandPoint(m_vTeleporterSpot[actor], GetAbsOrigin(actor), attempt,
			TELEPORTER_TRY_POINTS, TELEPORTER_BUILD_REACH, m_vTeleporterStand[actor]);

		return;
	}

	float out = TELEPORTER_SPAWN_OFFSET + TELEPORTER_SPAWN_STEP * float(m_iTeleporterTry[actor]);

	for (int axis = 0; axis < 3; axis++)
	{
		m_vTeleporterSpot[actor][axis] = m_vTeleporterSpawn[actor][axis] + pathOut[axis] * out;
		m_vTeleporterStand[actor][axis] = m_vTeleporterSpot[actor][axis] - pathOut[axis] * TELEPORTER_BUILD_REACH;
	}
}

public void CTFBotMvMEngineerBuildTeleporter_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	g_arrPluginBot[actor].bPathing = false;

	UpdateLookAroundForEnemies(actor, true);
}

/* The half of the teleporter this engineer should go build, or none

Entrance before exit: an exit alone moves nobody, and the pair is only worth the metal once both
ends stand. Both spots are read from the map configuration, the entrance nearest the engineer and
the exit nearest his nest, so several engineers on a map that names several spots do not all walk
to the same doorway */
bool ShouldBuildTeleporter(int actor)
{
	if (GameRules_GetRoundState() != RoundState_BetweenRounds)
		return false;

	//The nest comes first and it is not finished
	if (GetObjectOfType(actor, TFObject_Sentry) == INVALID_ENT_REFERENCE)
		return false;

	if (GetObjectOfType(actor, TFObject_Dispenser) == INVALID_ENT_REFERENCE)
		return false;

	if (GetObjectOfType(actor, TFObject_Teleporter, TFObjectMode_Entrance) == INVALID_ENT_REFERENCE)
	{
		m_nTeleporterMode[actor] = TFObjectMode_Entrance;
		m_vTeleporterPathOut[actor] = NULL_VECTOR;

		if (NearestConfiguredSpot(g_arrMapConfig.adtTeleporterEntranceLocation, GetAbsOrigin(actor), m_vTeleporterSpot[actor]))
			return true;

		if (m_aNestArea[actor] == NULL_AREA)
			return false;

		float out[3]; m_aNestArea[actor].GetCenter(out);

		//The map named none, which is most of them, so he walks out of spawn until the floor takes it
		return SpawnPathOut(actor, out, m_vTeleporterSpawn[actor], m_vTeleporterPathOut[actor]);
	}

	if (GetObjectOfType(actor, TFObject_Teleporter, TFObjectMode_Exit) == INVALID_ENT_REFERENCE)
	{
		if (m_aNestArea[actor] == NULL_AREA)
			return false;

		float nest[3]; m_aNestArea[actor].GetCenter(nest);

		m_nTeleporterMode[actor] = TFObjectMode_Exit;
		m_vTeleporterPathOut[actor] = NULL_VECTOR;

		//The nest itself when the map names no exit: the point of the pair is to arrive at the nest
		if (!NearestConfiguredSpot(g_arrMapConfig.adtTeleporterExitLocation, nest, m_vTeleporterSpot[actor]))
			m_vTeleporterSpot[actor] = nest;

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
