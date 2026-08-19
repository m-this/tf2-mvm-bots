/* A teleporter, but only when it costs the team nothing

An engineer is a sentry and the metal that keeps it firing. Everything here is what he does with
the time left over, so it happens between rounds, with the nest already standing, and it is
abandoned the moment the sentry needs him. A wave that arrives to find the engineer walking back
from spawn with a teleporter in his hands has already been made worse by it.

The spots come from the map configuration and nowhere else. Guessing an entrance from spawn
geometry puts it in a doorway on half the maps, so a map that names no spots gets no teleporter */

//Long enough to walk the length of a map, short enough that a wave never starts without the engineer
#define TELEPORTER_BUILD_MAX_TIME 25.0

float m_ctTeleporterGiveUp[MAXPLAYERS + 1];
TFObjectMode m_nTeleporterMode[MAXPLAYERS + 1];
float m_vTeleporterSpot[MAXPLAYERS + 1][3];

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
	float range = GetVectorDistance(GetAbsOrigin(actor), spot);

	if (range > 70.0)
	{
		g_arrPluginBot[actor].SetPathGoalVector(spot);
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

	VS_PressFireButton(actor);

	return action.Continue();
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
		if (!NearestConfiguredSpot(g_arrMapConfig.adtTeleporterEntranceLocation, GetAbsOrigin(actor), m_vTeleporterSpot[actor]))
			return false;

		m_nTeleporterMode[actor] = TFObjectMode_Entrance;

		return true;
	}

	if (GetObjectOfType(actor, TFObject_Teleporter, TFObjectMode_Exit) == INVALID_ENT_REFERENCE)
	{
		if (m_aNestArea[actor] == NULL_AREA)
			return false;

		float nest[3]; m_aNestArea[actor].GetCenter(nest);

		if (!NearestConfiguredSpot(g_arrMapConfig.adtTeleporterExitLocation, nest, m_vTeleporterSpot[actor]))
			return false;

		m_nTeleporterMode[actor] = TFObjectMode_Exit;

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
