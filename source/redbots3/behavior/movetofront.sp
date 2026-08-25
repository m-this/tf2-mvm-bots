/* How close counts as being there, how long the walk gets, and how often it may start over

The front is the far end of the map: five thousand units from the upgrade station on Coaltown,
which is twenty-odd seconds of walking on top of the shopping. So the clock is generous and only
being wedged spends an attempt. A clock that spent one would turn every bot that merely has a long
way to go into a bot standing still halfway there, which is what it did when this was first
written. */
#define MOVE_TO_FRONT_ARRIVED   80.0
#define MOVE_TO_FRONT_REACH     60.0
#define MOVE_TO_FRONT_TRIES     3

float m_vecGoalArea[MAXPLAYERS + 1][3];
float m_ctMoveTimeout[MAXPLAYERS + 1];
int m_iMoveToFrontTry[MAXPLAYERS + 1];
bool m_bAtTheFront[MAXPLAYERS + 1];

/* Whether this bot has finished taking up its position for the coming wave

Standing where he meant to stand and giving up short of it are the same answer here: both mean
he has stopped walking and is not going to move again before the wave. */
bool IsWaitingAtTheFront(int client)
{
	return m_bAtTheFront[client];
}

BehaviorAction CTFBotMoveToFront()
{
	BehaviorAction action = ActionsManager.Create("DefenderMoveToFront");
	
	action.OnStart = CTFBotMoveToFront_OnStart;
	action.Update = CTFBotMoveToFront_Update;
	action.OnEnd = CTFBotMoveToFront_OnEnd;
	
	return action;
}

/* Where the robots come out, which is where the team should be waiting for them

The holograms are the markers the game puts at the robot spawns, so the one nearest the enemy
spawn room is the start of the bomb's path. Standing on the ground beside it is the difference
between opening fire as the gate drops and meeting the wave halfway up the map. */
static bool PickTheFront(int actor)
{
	/* On a hard mission the nest is the front, and on an easy one the gate still is
	
	The gate is where the robots come out, and standing on it is how a defender meets a giant with
	nothing behind him. Waiting at the nest instead starts the wave with a sentry, a dispenser and
	the rest of the team in reach.
	
	Both were measured and the answer is not the same on both. Bavarian Botbash wave 3, three
	attempts each: at the gate 62 robots killed and 160 seconds held, at the nest 72 and 180. Decoy
	on its normal mission, two waves: at the gate both cleared with 206 robots killed, at the nest
	one cleared with 165.
	
	Which is the difference between a wave you can walk into and one that walks over you. So the
	rule is the mission: meet them at the gate while the team can afford to, and hold the nest when
	it cannot. */
	if (Feature(FEATURE_HOLD_THE_NEST) && IsHardMission() && PickTheNest(actor))
		return true;

	int spawn = -1;
	
	while ((spawn = FindEntityByClassname(spawn, "func_respawnroomvisualizer")) != -1)
	{
		if (GetEntProp(spawn, Prop_Data, "m_iDisabled"))
			continue;
		
		if (BaseEntity_GetTeamNumber(spawn) == BaseEntity_GetTeamNumber(actor))
			continue;
		
		break;
	}
	
	if (spawn == -1)
		return false;
	
	float flSmallestDistance = 99999.0;
	int iBestEnt = -1;
	
	int holo = -1;
	
	while ((holo = FindEntityByClassname(holo, "prop_dynamic")) != -1)
	{
		char strModel[PLATFORM_MAX_PATH]; GetEntPropString(holo, Prop_Data, "m_ModelName", strModel, PLATFORM_MAX_PATH);
		
		if (!StrEqual(strModel, "models/props_mvm/robot_hologram.mdl"))
			continue;
	
		if (GetEntProp(holo, Prop_Send, "m_fEffects") & 32)
			continue;
		
		float flDistance = GetVectorDistance(WorldSpaceCenter(spawn), WorldSpaceCenter(holo));
		
		if (flDistance <= flSmallestDistance && IsPathToVectorPossible(actor, WorldSpaceCenter(holo)))
		{
			iBestEnt = holo;
			flSmallestDistance = flDistance;
		}
	}
	
	if (iBestEnt == -1)
		return false;
	
	CNavArea area = TheNavMesh.GetNearestNavArea(WorldSpaceCenter(iBestEnt), true, 1000.0, true, true, GetClientTeam(actor));
	
	if (area == NULL_AREA)
		return false;
	
	CNavArea_GetRandomPoint(area, m_vecGoalArea[actor]);
	
	//A new goal is worth a path this frame rather than at the end of the old one's interval
	m_flRepathTime[actor] = 0.0;
	
	return true;
}

//Advanced and above, which is where meeting the wave at its own gate stops paying
static bool IsHardMission()
{
	static eMissionDifficulty difficulty = MISSION_UNKNOWN;
	static float asked;

	//Asked once a wave rather than once a bot: it reads the popfile name off an entity every time
	if (asked < GetGameTime() - 30.0)
	{
		difficulty = GetMissionDifficulty();
		asked = GetGameTime();

		LogMessage("MoveToFront: mission difficulty is %d, holding the nest is %s",
			difficulty, difficulty == MISSION_ADVANCED || difficulty == MISSION_EXPERT ? "on" : "off");
	}

	return difficulty == MISSION_ADVANCED || difficulty == MISSION_EXPERT;
}

/* Ground beside a teammate's sentry, or false when the team has none up yet
 *
 * The nearest one, because two engineers are two nests and the one to stand at is the one on the
 * way to where this bot already is. */
static bool PickTheNest(int actor)
{
	int best = -1;
	float bestRange = 0.0;
	float mine[3]; mine = WorldSpaceCenter(actor);

	int sentry = -1;

	while ((sentry = FindEntityByClassname(sentry, "obj_sentrygun")) != -1)
	{
		if (BaseEntity_GetTeamNumber(sentry) != GetClientTeam(actor))
			continue;

		if (GetEntProp(sentry, Prop_Send, "m_bPlacing") != 0 || GetEntProp(sentry, Prop_Send, "m_bCarried") != 0)
			continue;

		float range = GetVectorDistance(mine, WorldSpaceCenter(sentry));

		if (best == -1 || range < bestRange)
		{
			best = sentry;
			bestRange = range;
		}
	}

	if (best == -1)
		return false;

	CNavArea area = TheNavMesh.GetNearestNavArea(WorldSpaceCenter(best), true, 1000.0, true, true, GetClientTeam(actor));

	if (area == NULL_AREA)
		return false;

	CNavArea_GetRandomPoint(area, m_vecGoalArea[actor]);

	m_flRepathTime[actor] = 0.0;

	return true;
}

public Action CTFBotMoveToFront_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iMoveToFrontTry[actor] = 0;
	m_bAtTheFront[actor] = false;
	m_ctMoveTimeout[actor] = GetGameTime() + MOVE_TO_FRONT_REACH;
	
	if (!PickTheFront(actor))
	{
		SetPlayerReady(actor, true);
		return action.Done("Cannot find the start of the robots' path from wherever we are");
	}
	
	return action.Continue();
}

public Action CTFBotMoveToFront_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	/* The wave is what ends this, not arriving
	
	Arriving used to end it, and what happened next was nothing at all: the between-rounds branch
	of GetDesiredBotAction had no answer for a bot that had already shopped, so the game got the
	bot back and roamed it around the map. Reported as the Heavy, the Medic and the Pyro wandering
	off before the wave and turning up inside the middle house on Coaltown. */
	if (GameRules_GetRoundState() != RoundState_BetweenRounds)
		return action.Done("The wave has started");
	
	//Credits on the floor are still worth the walk while we wait
	if (CTFBotCollectMoney_IsPossible(actor))
		return action.SuspendFor(CTFBotCollectMoney(), "Money on the floor");
	
	if (m_bAtTheFront[actor])
		return action.Continue();
	
	if (GetVectorDistance(m_vecGoalArea[actor], WorldSpaceCenter(actor)) < MOVE_TO_FRONT_ARRIVED)
	{
		SetPlayerReady(actor, true);
		m_bAtTheFront[actor] = true;
		
		return action.Continue();
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	ILocomotion myLoco = myBot.GetLocomotionInterface();
	
	/* Walking into the corner of a building is what spends an attempt
	
	The locomotion already knows the difference between walking and walking on the spot, and
	nothing outside the engineer has ever asked it. A fresh random point in the same area is a
	different approach to the same place, and three of them is a bound rather than a bot that
	repaths for ever.
	
	Out of attempts, or out of clock, he stands where he is: short of the front is a bot in the
	wrong place, and handed back to the game is a bot in the middle house. */
	if (myLoco.IsStuck())
	{
		myLoco.ClearStuckStatus("Wedged on the way to the front");
		
		m_iMoveToFrontTry[actor]++;
		
		if (m_iMoveToFrontTry[actor] < MOVE_TO_FRONT_TRIES)
			PickTheFront(actor);
	}
	
	if (m_iMoveToFrontTry[actor] >= MOVE_TO_FRONT_TRIES || m_ctMoveTimeout[actor] < GetGameTime())
	{
		SetPlayerReady(actor, true);
		m_bAtTheFront[actor] = true;
		
		if (redbots_manager_debug_actions.BoolValue)
			PrintToServer("[%8.3f] CTFBotMoveToFront(#%d): giving up short of the front", GetGameTime(), actor);
		
		return action.Continue();
	}
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(3.0, 4.0);
		m_pPath[actor].ComputeToPos(myBot, m_vecGoalArea[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotMoveToFront_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_vecGoalArea[actor] = NULL_VECTOR;
	m_bAtTheFront[actor] = false;
	m_iMoveToFrontTry[actor] = 0;
}

public Action Command_DumpFront(int client, int args)
{
	BombInfo_t bomb;
	bool haveBomb = GetBombInfo(bomb);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !g_bIsDefenderBot[i])
			continue;
		
		float mine[3]; mine = GetAbsOrigin(i);
		
		char action[64] = "no waiting action";
		
		if (ActionsManager.LookupEntityActionByName(i, "DefenderMoveToFront") != INVALID_ACTION)
			Format(action, sizeof(action), m_bAtTheFront[i] ? "holding the front" : "walking to the front");
		else if (ActionsManager.LookupEntityActionByName(i, "DefenderEngineerIdle") != INVALID_ACTION)
			Format(action, sizeof(action), "at his nest");
		else if (ActionsManager.LookupEntityActionByName(i, "DefenderGotoUpgrade") != INVALID_ACTION)
			Format(action, sizeof(action), "walking to the station");
		else if (ActionsManager.LookupEntityActionByName(i, "DefenderUpgrade") != INVALID_ACTION)
			Format(action, sizeof(action), "shopping");
		
		ReplyToCommand(client, "%N (%s): %s, %.0f from his goal, %.0f from the bomb, %s, %s, stuck %d times, %d dead-end paths",
			i, g_sRawPlayerClassNames[TF2_GetPlayerClass(i)], action,
			IsZeroVector(m_vecGoalArea[i]) ? -1.0 : GetVectorDistance(mine, m_vecGoalArea[i]),
			haveBomb ? GetVectorDistance(mine, bomb.vPosition) : -1.0,
			g_bShoppedThisBreak[i] ? "has shopped" : "has not shopped",
			IsPlayerReady(i) ? "ready" : "not ready",
			StuckCountOf(i), PathFailuresOf(i));
	}
	
	return Plugin_Handled;
}
