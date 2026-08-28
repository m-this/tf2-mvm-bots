/* Make a fault happen on purpose, so a fix for it can be measured

Three engineer fixes have shipped against faults the test-bed will not produce: the setup freeze,
the refused path to a metal pack and the wedge. Each was measured against a condition that did not
happen, so each arm ran the same code and the run said nothing. See mvm-0lo.

These convars force the condition instead of waiting for it. They are for a run, not for a server:
each is off at zero and does nothing until somebody sets it.

Wedging is done by putting the bot back where it was every frame rather than by freezing it. A bot
held in place still asks for paths, still runs its actions and still fails to arrive, which is what
the real wedge looks like from the watchdog's side. Freezing the entity would be a different bug. */

//Far enough that only a teleport explains it. A bot shuffling inside the hold is still held.
#define DEBUG_WEDGE_ESCAPED	120.0

ConVar redbots_debug_wedge_seconds;
ConVar redbots_debug_wedge_class;
ConVar redbots_debug_refuse_ammo_paths;
ConVar redbots_debug_old_wedge_recovery;
ConVar redbots_debug_unreachable_goal;

//The bot being held, and until when. One at a time: two wedged bots is a different test.
static int m_iWedgedBot = -1;
static float m_flWedgedUntil;
static float m_vWedgedAt[3];

void DebugFaults_Init()
{
	redbots_debug_wedge_seconds = CreateConVar("sm_redbots_debug_wedge_seconds", "0",
		"Hold one defender in place for this many seconds after a wave starts, to exercise the stuck watchdog. 0 is off.",
		FCVAR_NOTIFY, true, 0.0, true, 300.0);

	redbots_debug_wedge_class = CreateConVar("sm_redbots_debug_wedge_class", "engineer",
		"Which class to hold when sm_redbots_debug_wedge_seconds is on.", FCVAR_NOTIFY);

	redbots_debug_refuse_ammo_paths = CreateConVar("sm_redbots_debug_refuse_ammo_paths", "0",
		"Refuse this many path answers to a metal pack per bot, to exercise the ammo failover. 0 is off.",
		FCVAR_NOTIFY, true, 0.0, true, 20.0);

	redbots_debug_unreachable_goal = CreateConVar("sm_redbots_debug_unreachable_goal", "0",
		"Send the held bot at a point off the nav mesh, so every path search walks the whole thing and finds nothing. 0 is off.",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	redbots_debug_old_wedge_recovery = CreateConVar("sm_redbots_debug_old_wedge_recovery", "0",
		"Use the pre-2.21.3 wedge recovery, which only ever tried the area the bot stands in. For measuring what that fix is worth.",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	RegServerCmd("sm_redbots_debug_sniper_spots", Command_SniperSpots);
}

//How many refusals are still owed to this bot, counted down as they are handed out
static int m_iAmmoRefusalsLeft[MAXPLAYERS + 1];

//A fresh walk to a pack starts the count again, or one bot spends the whole wave refused
void DebugFaults_OnAmmoWalkStart(int client)
{
	m_iAmmoRefusalsLeft[client] = redbots_debug_refuse_ammo_paths.IntValue;
}

/* Should this path answer be a refusal

Sits in front of PathFailedFor rather than replacing it, so a route that really failed still reads
as failed once the owed refusals run out. */
bool DebugFaults_RefuseAmmoPath(int client)
{
	if (m_iAmmoRefusalsLeft[client] <= 0)
		return false;

	m_iAmmoRefusalsLeft[client]--;
	return true;
}

//Pick somebody to hold, at the start of a wave. Nothing happens while the convar is zero.
void DebugFaults_OnWaveStart()
{
	m_iWedgedBot = -1;

	float seconds = redbots_debug_wedge_seconds.FloatValue;

	if (seconds <= 0.0)
		return;

	char wanted[32]; redbots_debug_wedge_class.GetString(wanted, sizeof(wanted));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsDefenderBot(i) || !IsPlayerAlive(i))
			continue;

		if (!StrEqual(g_sRawPlayerClassNames[TF2_GetPlayerClass(i)], wanted, false))
			continue;

		m_iWedgedBot = i;
		m_flWedgedUntil = GetGameTime() + seconds;
		m_vWedgedAt = GetAbsOrigin(i);

		LogMessage("DebugFaults: holding %N (%s) at %.0f %.0f %.0f for %.0fs",
			i, wanted, m_vWedgedAt[0], m_vWedgedAt[1], m_vWedgedAt[2], seconds);
		return;
	}

	LogMessage("DebugFaults: no %s on RED to hold", wanted);
}

/* Put the held bot back, once a frame

Stops on its own at the deadline, and stops early if the bot died, left, or was moved a long way:
a teleport out of the hold is the watchdog's recovery working, and continuing to drag him back
would be measuring this file rather than the fix. */
void DebugFaults_OnGameFrame()
{
	if (m_iWedgedBot <= 0)
		return;

	if (GetGameTime() > m_flWedgedUntil || !IsClientInGame(m_iWedgedBot) || !IsPlayerAlive(m_iWedgedBot))
	{
		m_iWedgedBot = -1;
		return;
	}

	float here[3]; here = GetAbsOrigin(m_iWedgedBot);

	if (GetVectorDistance(here, m_vWedgedAt) > DEBUG_WEDGE_ESCAPED)
	{
		LogMessage("DebugFaults: %N left the hold, %.0f units away, so something moved him",
			m_iWedgedBot, GetVectorDistance(here, m_vWedgedAt));

		m_iWedgedBot = -1;
		return;
	}

	TeleportEntity(m_iWedgedBot, m_vWedgedAt, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
}

/* Whether to use the recovery as it was before v2.21.3

The old one asked TheNavMesh for the nearest area and took a random point in it. For a bot wedged in
geometry while standing on valid nav that area is the one under his feet, so the point landed back
on him and the move was thrown away. That is the defect, and this convar is how the arms of an A/B
differ: measuring what a fix is worth needs the fault available, not only its absence. */
bool DebugFaults_OldWedgeRecovery()
{
	return redbots_debug_old_wedge_recovery != null && redbots_debug_old_wedge_recovery.BoolValue;
}

/* Where to send the held bot so that no path exists

Far above the map, which is off every nav area there is. The search has to walk the mesh to
establish that, which is the frame the watchdog kills the server on, and the whole point of this
convar is to make that frame happen rather than wait for a map to arrange it. */
bool DebugFaults_UnreachableGoal(int client, float goal[3])
{
	if (redbots_debug_unreachable_goal == null || !redbots_debug_unreachable_goal.BoolValue)
		return false;

	if (client != m_iWedgedBot)
		return false;

	goal = m_vWedgedAt;
	goal[2] += 16384.0;
	return true;
}

/* Report whether each sniper spot can be walked to, from each sniper standing now

The stock sniper is handed to the game's CTFBotSniperLurk, which computes its own path and hangs
the frame the watchdog kills the server on. Whether the spots are reachable at all decides the
fix: an unreachable spot means filtering them before committing, a reachable one means the lurk
never starts. See mvm-bj8. */
void DebugFaults_ReportSniperSpots()
{
	ArrayList spots = g_arrMapConfig.adtSniperSpot;

	PrintToServer("[sniperspots] %d configured", spots.Length);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (!g_bIsDefenderBot[client] || TF2_GetPlayerClass(client) != TFClass_Sniper)
			continue;

		float here[3]; here = GetAbsOrigin(client);

		for (int i = 0; i < spots.Length; i++)
		{
			float spot[3]; spots.GetArray(i, spot);

			PrintToServer("[sniperspots] bot %d spot %d away %.0f reachable %d rifle %d",
				client, i, GetVectorDistance(here, spot),
				IsPathToVectorPossible(client, spot), HasSniperRifle(client));
		}
	}
}

public Action Command_SniperSpots(int args)
{
	DebugFaults_ReportSniperSpots();
	return Plugin_Handled;
}
