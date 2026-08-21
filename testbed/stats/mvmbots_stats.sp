/* What the bots did with a wave, written down so it can be compared with what they did last time
 *
 * The mod is judged by play, and play is an opinion until somebody counts something. This counts
 * the few things that are not opinions: whether the wave was cleared, how long it took, how many
 * robots died and to whom, how many defenders died and to what, and what the engineers lost.
 *
 * One JSON object per line, appended, never rewritten. A wave is a line. That format is chosen
 * so a run that crashes halfway still leaves everything it measured, and so two runs can be
 * compared with nothing more than a file each.
 *
 * It is a test-bed plugin and belongs on a test server. It hooks events, writes a file, and does
 * nothing to the game.
 */

#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

//A wave is hundreds of deaths and a line is written per wave, so the file is small on purpose
#define STATS_LINE_LENGTH	2048

public Plugin myinfo =
{
	name = "MvM Defender Bots: wave statistics",
	author = "m-this",
	description = "Records the result of every MvM wave as one line of JSON",
	version = PLUGIN_VERSION,
	url = "https://github.com/m-this/tf2-mvm-bots"
};

ConVar g_cvPath;

char g_sMap[PLATFORM_MAX_PATH];

int g_iWave;
float g_flWaveStart;

//Everything counted for the wave in progress. Reset when one begins, written when one ends
enum struct WaveCounters
{
	int robotKills;
	int giantKills;
	int tankKills;
	int sentryKills;
	int defenderDeaths;
	int backstabs;
	int busterDetonations;
	int sentriesLost;
	int dispensersLost;
	/* Contribution, not just body count

	Waves cleared says whether the team held. It does not say who held it, and two builds that
	both clear five waves can be doing completely different work to get there. Damage, healing
	and what the sentry did are the numbers that separate them */
	int damageDealt;
	int damageToTanks;
	int sentryDamage;
	int healingDone;
	int ubersDeployed;
	int damageByClass[view_as<int>(TFClass_Engineer) + 1];
	/* Who killed what, on both sides

	"Five waves cleared" hides everything worth knowing. Which defender class does the killing
	says which one is worth its seat, and what kills the defenders says what the team has no
	answer to */
	int killsByClass[view_as<int>(TFClass_Engineer) + 1];
	int giantKillsByClass[view_as<int>(TFClass_Engineer) + 1];
	int deathsToClass[view_as<int>(TFClass_Engineer) + 1];
	int deathsToSentry;
	int deathsToTank;

	void Reset()
	{
		this.robotKills = 0;
		this.giantKills = 0;
		this.tankKills = 0;
		this.sentryKills = 0;
		this.defenderDeaths = 0;
		this.backstabs = 0;
		this.busterDetonations = 0;
		this.sentriesLost = 0;
		this.dispensersLost = 0;
		this.damageDealt = 0;
		this.damageToTanks = 0;
		this.sentryDamage = 0;
		this.healingDone = 0;
		this.ubersDeployed = 0;
		
		this.deathsToSentry = 0;
		this.deathsToTank = 0;
		
		for (int i = 0; i < sizeof(this.damageByClass); i++)
		{
			this.damageByClass[i] = 0;
			this.killsByClass[i] = 0;
			this.giantKillsByClass[i] = 0;
			this.deathsToClass[i] = 0;
		}
	}
}

WaveCounters g_Wave;

public void OnPluginStart()
{
	g_cvPath = CreateConVar("mvmbots_stats_path", "logs/mvmbots_stats.jsonl",
		"Where to append wave results, relative to addons/sourcemod unless it starts with a slash.");

	HookEvent("mvm_begin_wave", Event_WaveBegin);
	HookEvent("mvm_wave_complete", Event_WaveComplete);
	HookEvent("mvm_wave_failed", Event_WaveFailed);
	HookEvent("mvm_mission_complete", Event_MissionComplete);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("object_destroyed", Event_ObjectDestroyed);
	HookEvent("player_healed", Event_PlayerHealed);
	HookEvent("player_chargedeployed", Event_ChargeDeployed);
	HookEvent("player_spawn", Event_PlayerSpawn);

	g_Wave.Reset();
}

public void OnMapStart()
{
	GetCurrentMap(g_sMap, sizeof(g_sMap));

	g_iWave = 0;
	g_flWaveStart = 0.0;
	g_Wave.Reset();
}

static void Event_WaveBegin(Event event, const char[] name, bool dontBroadcast)
{
	//The game counts from zero and everybody else counts from one
	g_iWave = event.GetInt("wave_index") + 1;
	g_flWaveStart = GetGameTime();

	g_Wave.Reset();

	char line[STATS_LINE_LENGTH];
	FormatEx(line, sizeof(line), "{\"event\":\"wave_begin\",\"map\":\"%s\",\"wave\":%d,\"red\":%d,\"bots\":%d}",
		g_sMap, g_iWave, CountTeam(TFTeam_Red, false), CountTeam(TFTeam_Red, true));

	WriteLine(line);
}

static void Event_WaveComplete(Event event, const char[] name, bool dontBroadcast)
{
	WriteWaveResult("cleared");
}

static void Event_WaveFailed(Event event, const char[] name, bool dontBroadcast)
{
	WriteWaveResult("lost");
}

static void Event_MissionComplete(Event event, const char[] name, bool dontBroadcast)
{
	char line[STATS_LINE_LENGTH];
	FormatEx(line, sizeof(line), "{\"event\":\"mission_complete\",\"map\":\"%s\",\"waves\":%d}", g_sMap, g_iWave);

	WriteLine(line);
}

/* One line for the wave, with everything that was counted while it ran
 *
 * The duration is the honest number to compare runs on: a wave that is cleared slowly is a team
 * that nearly lost it, and a change that clears the same waves faster is a change that worked */
static void WriteWaveResult(const char[] result)
{
	float duration = g_flWaveStart > 0.0 ? GetGameTime() - g_flWaveStart : 0.0;

	char line[STATS_LINE_LENGTH];
	FormatEx(line, sizeof(line),
		"{\"event\":\"wave_end\",\"map\":\"%s\",\"wave\":%d,\"result\":\"%s\",\"duration\":%.1f,"
		... "\"robot_kills\":%d,\"giant_kills\":%d,\"tank_kills\":%d,\"sentry_kills\":%d,"
		... "\"defender_deaths\":%d,\"backstabs\":%d,\"buster_detonations\":%d,"
		... "\"sentries_lost\":%d,\"dispensers_lost\":%d,"
		... "\"damage\":%d,\"tank_damage\":%d,\"sentry_damage\":%d,"
		... "\"healing\":%d,\"ubers\":%d,"
		... "\"damage_scout\":%d,\"damage_sniper\":%d,\"damage_soldier\":%d,"
		... "\"damage_demoman\":%d,\"damage_medic\":%d,\"damage_heavy\":%d,"
		... "\"damage_pyro\":%d,\"damage_spy\":%d,\"damage_engineer\":%d,"
		... "\"kills_scout\":%d,\"kills_soldier\":%d,\"kills_pyro\":%d,"
		... "\"kills_demoman\":%d,\"kills_heavy\":%d,\"kills_engineer\":%d,"
		... "\"kills_medic\":%d,\"kills_sniper\":%d,\"kills_spy\":%d,"
		... "\"giantkills_scout\":%d,\"giantkills_soldier\":%d,\"giantkills_pyro\":%d,"
		... "\"giantkills_demoman\":%d,\"giantkills_heavy\":%d,\"giantkills_engineer\":%d,"
		... "\"giantkills_medic\":%d,\"giantkills_sniper\":%d,\"giantkills_spy\":%d,"
		... "\"killedby_scout\":%d,\"killedby_soldier\":%d,\"killedby_pyro\":%d,"
		... "\"killedby_demoman\":%d,\"killedby_heavy\":%d,\"killedby_engineer\":%d,"
		... "\"killedby_medic\":%d,\"killedby_sniper\":%d,\"killedby_spy\":%d,"
		... "\"killedby_sentry\":%d,\"killedby_tank\":%d}",
		g_sMap, g_iWave, result, duration,
		g_Wave.robotKills, g_Wave.giantKills, g_Wave.tankKills, g_Wave.sentryKills,
		g_Wave.defenderDeaths, g_Wave.backstabs, g_Wave.busterDetonations,
		g_Wave.sentriesLost, g_Wave.dispensersLost,
		g_Wave.damageDealt, g_Wave.damageToTanks, g_Wave.sentryDamage,
		g_Wave.healingDone, g_Wave.ubersDeployed,
		g_Wave.damageByClass[view_as<int>(TFClass_Scout)],
		g_Wave.damageByClass[view_as<int>(TFClass_Sniper)],
		g_Wave.damageByClass[view_as<int>(TFClass_Soldier)],
		g_Wave.damageByClass[view_as<int>(TFClass_DemoMan)],
		g_Wave.damageByClass[view_as<int>(TFClass_Medic)],
		g_Wave.damageByClass[view_as<int>(TFClass_Heavy)],
		g_Wave.damageByClass[view_as<int>(TFClass_Pyro)],
		g_Wave.damageByClass[view_as<int>(TFClass_Spy)],
		g_Wave.damageByClass[view_as<int>(TFClass_Engineer)],
		g_Wave.killsByClass[view_as<int>(TFClass_Scout)],
		g_Wave.killsByClass[view_as<int>(TFClass_Soldier)],
		g_Wave.killsByClass[view_as<int>(TFClass_Pyro)],
		g_Wave.killsByClass[view_as<int>(TFClass_DemoMan)],
		g_Wave.killsByClass[view_as<int>(TFClass_Heavy)],
		g_Wave.killsByClass[view_as<int>(TFClass_Engineer)],
		g_Wave.killsByClass[view_as<int>(TFClass_Medic)],
		g_Wave.killsByClass[view_as<int>(TFClass_Sniper)],
		g_Wave.killsByClass[view_as<int>(TFClass_Spy)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_Scout)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_Soldier)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_Pyro)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_DemoMan)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_Heavy)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_Engineer)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_Medic)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_Sniper)],
		g_Wave.giantKillsByClass[view_as<int>(TFClass_Spy)],
		g_Wave.deathsToClass[view_as<int>(TFClass_Scout)],
		g_Wave.deathsToClass[view_as<int>(TFClass_Soldier)],
		g_Wave.deathsToClass[view_as<int>(TFClass_Pyro)],
		g_Wave.deathsToClass[view_as<int>(TFClass_DemoMan)],
		g_Wave.deathsToClass[view_as<int>(TFClass_Heavy)],
		g_Wave.deathsToClass[view_as<int>(TFClass_Engineer)],
		g_Wave.deathsToClass[view_as<int>(TFClass_Medic)],
		g_Wave.deathsToClass[view_as<int>(TFClass_Sniper)],
		g_Wave.deathsToClass[view_as<int>(TFClass_Spy)],
		g_Wave.deathsToSentry,
		g_Wave.deathsToTank);

	WriteLine(line);

	g_flWaveStart = 0.0;
}

static void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));

	if (victim < 1 || !IsClientInGame(victim))
		return;

	char weapon[64]; event.GetString("weapon", weapon, sizeof(weapon));

	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (TF2_GetClientTeam(victim) == TFTeam_Blue)
	{
		g_Wave.robotKills++;

		bool giant = HasEntProp(victim, Prop_Send, "m_bIsMiniBoss") && GetEntProp(victim, Prop_Send, "m_bIsMiniBoss");

		if (giant)
			g_Wave.giantKills++;

		//Which defender did it. A robot that killed itself leaves no attacker, and belongs to nobody
		if (attacker > 0 && IsClientInGame(attacker) && TF2_GetClientTeam(attacker) == TFTeam_Red)
		{
			int class = view_as<int>(TF2_GetPlayerClass(attacker));

			if (class >= 0 && class < sizeof(g_Wave.killsByClass))
			{
				g_Wave.killsByClass[class]++;

				if (giant)
					g_Wave.giantKillsByClass[class]++;
			}
		}

		/* A sentry buster kills itself, so the death has no attacker and the weapon is its own
		explosion. Counting them says whether the engineers are losing nests to something the
		team could have shot first */
		if (StrContains(weapon, "sentry_buster", false) != -1)
			g_Wave.busterDetonations++;

		if (StrContains(weapon, "obj_sentrygun", false) != -1 || StrContains(weapon, "sentry", false) != -1)
			g_Wave.sentryKills++;

		return;
	}

	if (TF2_GetClientTeam(victim) != TFTeam_Red)
		return;

	g_Wave.defenderDeaths++;

	/* What killed the defender

	The robot's class is the answer most of the time. A sentry is not a class and neither is a
	tank, and both kill defenders, so they get counted on their own: a team losing people to a
	robot Engineer's sentry has a different problem from one losing them to giant Heavies */
	if (StrContains(weapon, "obj_sentrygun", false) != -1 || StrContains(weapon, "sentry", false) != -1)
	{
		g_Wave.deathsToSentry++;
	}
	else if (attacker < 1 || !IsClientInGame(attacker))
	{
		//Tanks are not players, so a tank kill arrives with nobody holding the gun
		g_Wave.deathsToTank++;
	}
	else
	{
		int class = view_as<int>(TF2_GetPlayerClass(attacker));

		if (class >= 0 && class < sizeof(g_Wave.deathsToClass))
			g_Wave.deathsToClass[class]++;
	}

	//A defender who died to a knife in the back is a defender who never saw the Spy
	int customKill = event.GetInt("customkill");

	if (customKill == TF_CUSTOM_BACKSTAB || StrContains(weapon, "knife", false) != -1)
		g_Wave.backstabs++;
}


/* Damage is counted where it lands, not where it was fired

A player_hurt event cannot tell an engineer's shotgun from his sentry: both name him as the
attacker. The damage hook can, because it carries the inflictor, and the sentry is the whole
reason an engineer is on the team */
public void OnEntityCreated(int entity, const char[] classname)
{
	//Tanks are not players, so nothing else here would ever see damage done to one
	if (StrEqual(classname, "tank_boss"))
		SDKHook(entity, SDKHook_OnTakeDamagePost, OnTankDamagePost);
}

static void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client < 1 || !IsClientInGame(client))
		return;
	
	//Only the robots need hooking: what we are counting is damage the defenders put into them
	if (TF2_GetClientTeam(client) != TFTeam_Blue)
		return;
	
	SDKUnhook(client, SDKHook_OnTakeDamagePost, OnRobotDamagePost);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnRobotDamagePost);
}

static void OnRobotDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	CountDefenderDamage(attacker, inflictor, damage, false);
}

static void OnTankDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	CountDefenderDamage(attacker, inflictor, damage, true);
}

static void CountDefenderDamage(int attacker, int inflictor, float damage, bool tank)
{
	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker))
		return;
	
	if (TF2_GetClientTeam(attacker) != TFTeam_Red)
		return;
	
	int amount = RoundToNearest(damage);
	
	g_Wave.damageDealt += amount;
	
	if (tank)
		g_Wave.damageToTanks += amount;
	
	int class = view_as<int>(TF2_GetPlayerClass(attacker));
	
	if (class >= 0 && class < sizeof(g_Wave.damageByClass))
		g_Wave.damageByClass[class] += amount;
	
	if (inflictor > MaxClients && IsValidEntity(inflictor))
	{
		char classname[32]; GetEntityClassname(inflictor, classname, sizeof(classname));
		
		if (StrEqual(classname, "obj_sentrygun"))
			g_Wave.sentryDamage += amount;
	}
}

static void Event_PlayerHealed(Event event, const char[] name, bool dontBroadcast)
{
	int healer = GetClientOfUserId(event.GetInt("healer"));
	
	if (healer < 1 || !IsClientInGame(healer) || TF2_GetClientTeam(healer) != TFTeam_Red)
		return;
	
	g_Wave.healingDone += event.GetInt("amount");
}

static void Event_ChargeDeployed(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client > 0 && IsClientInGame(client) && TF2_GetClientTeam(client) == TFTeam_Red)
		g_Wave.ubersDeployed++;
}

static void Event_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
	int owner = GetClientOfUserId(event.GetInt("userid"));

	if (owner < 1 || !IsClientInGame(owner) || TF2_GetClientTeam(owner) != TFTeam_Red)
		return;

	switch (view_as<TFObjectType>(event.GetInt("objecttype")))
	{
		case TFObject_Sentry: g_Wave.sentriesLost++;
		case TFObject_Dispenser: g_Wave.dispensersLost++;
	}
}

//How many are on a team, and how many of those are the mod's rather than people
static int CountTeam(TFTeam team, bool fakeOnly)
{
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || TF2_GetClientTeam(i) != team)
			continue;

		if (fakeOnly && !IsFakeClient(i))
			continue;

		count++;
	}

	return count;
}

/* Append one line, opening and closing the file each time
 *
 * A wave is minutes apart from the next one, so holding a handle open for the length of a run
 * buys nothing and loses everything written since the last flush if the server goes down */
static void WriteLine(const char[] line)
{
	char configured[PLATFORM_MAX_PATH]; g_cvPath.GetString(configured, sizeof(configured));

	char path[PLATFORM_MAX_PATH];

	if (configured[0] == '/')
		strcopy(path, sizeof(path), configured);
	else
		BuildPath(Path_SM, path, sizeof(path), "%s", configured);

	File file = OpenFile(path, "a");

	if (file == null)
	{
		LogError("mvmbots_stats: cannot open %s for writing", path);
		return;
	}

	file.WriteLine("%s", line);

	delete file;
}
