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
#include <tf2utils>
#include <actions>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

//A wave is hundreds of deaths and a line is written per wave, so the file is small on purpose
#define STATS_LINE_LENGTH	3072

/* A frame the server did not finish inside its own tick

The mod runs a path computation or two per bot per second and there are a dozen bots, so the
question of whether it fits in a tick is a real one and it is not answerable by watching. The
server runs at 66 ticks a second, which is a budget of about fifteen milliseconds a frame; twice
that is a frame somebody felt, and four times it is the watchdog's territory.

Counted rather than averaged. A mean frame time hides exactly the thing worth finding, which is
the one frame in a thousand that took a third of a second. */
#define FRAME_BUDGET_MS		15.0
#define FRAME_SLOW_MS		30.0
#define FRAME_STALL_MS		100.0

/* Every frame long enough to be worth a line of its own, with when it happened

The per-wave counts say how many frames went over a hundred milliseconds and how bad the worst was.
They do not say when, and when is the whole question: the watchdog killed three runs on the frame a
wave starts on and none in the middle of one, so a count that mixes the two answers nothing.

A quarter of a second is four times the tick and a quarter of the way to the watchdog, and frames
that long are rare enough that a line each costs nothing. */
#define FRAME_REPORT_MS		250.0

/* How far a building may sit from the nest before it is worth writing down as wrong

A dispenser is meant to be beside the sentry. One at the other end of the map feeds nothing, and
it is the shape of the bug the reach deadline used to cause, so the distance goes in the file
rather than a verdict about it. */
#define ENGINEER_LINE_LENGTH	512

/* How often the engineers are looked at while a wave runs

What each one had when the wave began says what the between-rounds time bought. It says nothing
about the eight minutes of a Bigrock wave he spent with no sentry at all, which is the shape most
"the engineer misbehaves on this map" reports actually have: not a nest he never built, but one he
could not keep.

Five seconds is a hundred and some samples in a long wave and a handful in a short one, which is
enough to tell "lost it once and rebuilt" from "never had one". */
#define ENGINEER_SAMPLE_INTERVAL	5.0

public Plugin myinfo =
{
	name = "MvM Defender Bots: wave statistics",
	author = "m-this",
	description = "Records the result of every MvM wave as one line of JSON",
	version = PLUGIN_VERSION,
	url = "https://github.com/m-this/tf2-mvm-bots"
};

//The projectile whose hit was counted last, so one blast into a crowd is one hit
static int g_iLastCountedProjectile = -1;

ConVar g_cvPath;

char g_sMap[PLATFORM_MAX_PATH];

int g_iWave;
float g_flWaveStart;

/* How a defender died, which is not the same question as who killed him

"Killed by a Spy" and "killed by a knife in the back" are different failures: the first is a bot
that lost a fight, the second is a bot that never had one. Counting the causes is what tells a
hundred-Spy wave apart from a hundred-Heavy wave in the numbers */
enum
{
	DEATH_CAUSE_BULLET = 0,
	DEATH_CAUSE_EXPLOSION,
	DEATH_CAUSE_FIRE,
	DEATH_CAUSE_MELEE,
	DEATH_CAUSE_BACKSTAB,
	DEATH_CAUSE_HEADSHOT,
	DEATH_CAUSE_FALL,
	DEATH_CAUSE_OTHER,
	DEATH_CAUSE_COUNT
}

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
	/* What the defenders did to themselves, which nothing has ever counted

	A soldier firing a rocket at a tank he is stood against takes the blast himself, and from the
	scoreboard that is indistinguishable from a soldier who fought well and got shot: damage up,
	kills up, deaths up. It was found by somebody watching it happen and saying so.

	Self damage separates the two without an opinion in it. A class with a column here is a class
	whose own weapon is one of the things killing it, and the number is comparable between two
	builds, which is the whole point. */
	/* The Demoman's two weapons, counted apart
	
	He is the weakest seat on the team by damage and has two entirely different ways of dealing it,
	and "demoman 1608 a wave" cannot say whether the pipes are missing or the stickies are never
	detonated. The inflictor is already in hand here, so the split costs nothing. */
	int demoPipeDamage;
	int demoStickyDamage;
	int demoMeleeDamage;
	int soldierRocketDamage;
	int soldierOtherDamage;
	/* Explosive projectiles thrown, against the ones that hurt something
	
	The Soldier and the Demoman are the two seats that fight with an arcing projectile and they are
	the two lowest scoring seats on the team. "He does a thousand a wave" cannot tell a bot that
	never shoots from a bot whose every shot goes past the robot, and those want opposite fixes. */
	int projectilesFired[view_as<int>(TFClass_Engineer) + 1];
	int projectilesHit[view_as<int>(TFClass_Engineer) + 1];
	int selfDamageByClass[view_as<int>(TFClass_Engineer) + 1];
	int selfDeathsByClass[view_as<int>(TFClass_Engineer) + 1];
	/* Who killed what, on both sides

	"Five waves cleared" hides everything worth knowing. Which defender class does the killing
	says which one is worth its seat, and what kills the defenders says what the team has no
	answer to */
	int killsByClass[view_as<int>(TFClass_Engineer) + 1];
	int giantKillsByClass[view_as<int>(TFClass_Engineer) + 1];
	int deathsToClass[view_as<int>(TFClass_Engineer) + 1];
	int deathsToSentry;
	int deathsToTank;
	//How it happened, which is a different question from who did it
	int deathsByCause[DEATH_CAUSE_COUNT];
	//What the server's own frame times did while the wave ran, which is the mod's cost to the tick
	int frames;
	int framesSlow;
	int framesStalled;
	float frameWorstMs;
	float frameTotalMs;

	void Reset()
	{
		this.frames = 0;
		this.framesSlow = 0;
		this.framesStalled = 0;
		this.frameWorstMs = 0.0;
		this.frameTotalMs = 0.0;
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
		
		this.demoPipeDamage = 0;
		this.demoStickyDamage = 0;
		this.demoMeleeDamage = 0;
		this.soldierRocketDamage = 0;
		this.soldierOtherDamage = 0;
		
		for (int i = 0; i < sizeof(this.projectilesFired); i++)
		{
			this.projectilesFired[i] = 0;
			this.projectilesHit[i] = 0;
		}
		this.deathsToSentry = 0;
		this.deathsToTank = 0;
		
		for (int i = 0; i < DEATH_CAUSE_COUNT; i++)
			this.deathsByCause[i] = 0;
		
		for (int i = 0; i < sizeof(this.damageByClass); i++)
		{
			this.damageByClass[i] = 0;
			this.selfDamageByClass[i] = 0;
			this.selfDeathsByClass[i] = 0;
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

/* The wall clock either side of a frame, which is the only honest way to ask what a frame cost

GetGameFrameTime is the tick interval the server intends, not the time it spent, so it says
fifteen milliseconds through a stall as happily as through an idle frame. The gap between one
frame starting and the next one starting is what actually elapsed. */
static float g_flLastFrame;

/* The worst frame since the last wave began, counted whether or not one is running

The per-wave numbers only ever covered frames inside a wave, and the frame that matters is the one
the wave starts on: every robot spawns and begins pathing at once, and the watchdog kills the
server there rather than in the middle of a wave. Three runs of an A/B died on it, all of them
immediately after "NextBot tickrate changed from 0 to 7", and none of them had written a wave
result yet, so nothing in the file said how close the frames had been getting.

Reported on the wave_begin line, which is the first thing written after that frame. */
static float g_flWorstFrameBetween;

/* When the worst one happened, in seconds since the map started

Without it the number is unattributable, and I have already read it wrong once: a gap of one and a
half seconds before wave one reads as a server about to be killed by the watchdog, and if it lands
twenty seconds into a map that has just finished loading it is the server starting up and nothing
to do with a wave at all. */
static float g_flWorstFrameAt;
static float g_flMapStart;

/* How much of the wave each engineer spent with something standing

Counted in samples rather than seconds because the sample is what is actually observed, and a
fraction of samples is a fraction of the wave whatever the interval is set to. */
static int g_iEngineerSamples[MAXPLAYERS + 1];
static int g_iSamplesWithSentry[MAXPLAYERS + 1];
static int g_iSamplesWithLevel3[MAXPLAYERS + 1];
static int g_iSamplesWithDispenser[MAXPLAYERS + 1];

/* Sampled off the frame hook rather than a repeating timer

A timer without TIMER_FLAG_NO_MAPCHANGE dies with the map, and one created in OnPluginStart is
created once. The first results file this wrote had a sample count of zero for every engineer on
every map, which is a measurement that says nothing and looks like a measurement. The frame hook
is already running for the frame times and cannot be killed out from under this. */
static float g_flNextEngineerSample;

static void ResetEngineerSamples()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iEngineerSamples[i] = 0;
		g_iSamplesWithSentry[i] = 0;
		g_iSamplesWithLevel3[i] = 0;
		g_iSamplesWithDispenser[i] = 0;
	}

	g_flNextEngineerSample = 0.0;
}

static void SampleEngineers()
{
	//Only while a wave is being played: between rounds he is building, and that is not uptime
	if (g_flWaveStart <= 0.0 || GameRules_GetRoundState() != RoundState_RoundRunning)
		return;

	if (GetGameTime() < g_flNextEngineerSample)
		return;

	g_flNextEngineerSample = GetGameTime() + ENGINEER_SAMPLE_INTERVAL;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || TF2_GetClientTeam(i) != TFTeam_Red)
			continue;

		if (TF2_GetPlayerClass(i) != TFClass_Engineer)
			continue;

		g_iEngineerSamples[i]++;

		int sentry = FindOwnedObject(i, TFObject_Sentry);

		if (sentry != -1)
		{
			g_iSamplesWithSentry[i]++;

			if (GetEntProp(sentry, Prop_Send, "m_iUpgradeLevel") >= 3)
				g_iSamplesWithLevel3[i]++;
		}

		if (FindOwnedObject(i, TFObject_Dispenser) != -1)
			g_iSamplesWithDispenser[i]++;
	}
}

public void OnGameFrame()
{
	float now = GetEngineTime();

	if (g_flLastFrame > 0.0)
	{
		float sinceLast = (now - g_flLastFrame) * 1000.0;

		if (sinceLast > g_flWorstFrameBetween)
		{
			g_flWorstFrameBetween = sinceLast;
			g_flWorstFrameAt = GetGameTime() - g_flMapStart;
		}

		if (sinceLast > FRAME_REPORT_MS)
			ReportStall(sinceLast);
	}

	if (g_flLastFrame > 0.0 && g_flWaveStart > 0.0)
	{
		float ms = (now - g_flLastFrame) * 1000.0;

		g_Wave.frames++;
		g_Wave.frameTotalMs += ms;

		if (ms > g_Wave.frameWorstMs)
			g_Wave.frameWorstMs = ms;

		if (ms > FRAME_STALL_MS)
			g_Wave.framesStalled++;
		else if (ms > FRAME_SLOW_MS)
			g_Wave.framesSlow++;
	}

	g_flLastFrame = now;

	SampleEngineers();
	SampleTelemetry();
}

static void ReportStall(float ms)
{
	char line[ENGINEER_LINE_LENGTH];
	FormatEx(line, sizeof(line),
		"{\"event\":\"stall\",\"map\":\"%s\",\"wave\":%d,\"ms\":%.0f,\"round\":%d,\"in_wave\":%d}",
		g_sMap, g_iWave, ms, GameRules_GetRoundState(), g_flWaveStart > 0.0 ? 1 : 0);

	WriteLine(line);
}

public void OnMapStart()
{
	GetCurrentMap(g_sMap, sizeof(g_sMap));

	/* The clock starts again, because a map load is not a frame

	OnGameFrame does not run while the server is loading, so the gap between the last frame of the
	old map and the first frame of the new one is the whole load. Left running across the change,
	that gap was reported as the worst frame before wave one: 1256ms on Coaltown, which read as a
	server a quarter of a second from the watchdog and sent me looking for what was on that frame.
	Nothing was. It was the map loading, which every server does and no watchdog counts. */
	g_flLastFrame = 0.0;
	g_flWorstFrameBetween = 0.0;
	g_flWorstFrameAt = 0.0;
	g_flMapStart = GetGameTime();

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

	ResetEngineerSamples();

	/* The features that are on go in the file with the numbers they produced

	A results file whose settings are not recorded is a file nobody can compare with anything: two
	runs of the same mission look identical on disk and were not the same mod. The bots plugin
	publishes the set, and this only copies it. */
	char features[512];
	ConVar cvFeatures = FindConVar("sm_redbots_features_active");
	
	if (cvFeatures != null)
		cvFeatures.GetString(features, sizeof(features));
	
	char line[STATS_LINE_LENGTH];
	FormatEx(line, sizeof(line), "{\"event\":\"wave_begin\",\"map\":\"%s\",\"wave\":%d,\"red\":%d,\"bots\":%d,"
		... "\"worst_frame_before_ms\":%.0f,\"worst_frame_at_s\":%.0f,\"features\":\"%s\"}",
		g_sMap, g_iWave, CountTeam(TFTeam_Red, false), CountTeam(TFTeam_Red, true),
		g_flWorstFrameBetween, g_flWorstFrameAt, features);

	WriteLine(line);

	g_flWorstFrameBetween = 0.0;
	g_flWorstFrameAt = 0.0;

	/* Both ends of the wave, because the two questions are different

	At the beginning it says what the engineer had time to finish between rounds, which is where a
	teleporter comes from and where a nest that never reached level three shows up. At the end it
	says what survived. */
	WriteEngineers("begin");
}

static void Event_WaveComplete(Event event, const char[] name, bool dontBroadcast)
{
	WriteWaveResult("cleared");
}

/* What every engineer had standing, and where, written as its own line per engineer

Not folded into the wave line, because there is one of these per engineer and the wave line is a
fixed shape that two runs are diffed on. What it is for is the complaint that reads "the engineer
misbehaves on this map": a nest that never got a level three sentry, a dispenser at the other end
of the map from it, a teleporter that never went up. All three are distances and levels rather
than opinions, and a map that produces them every wave is a map with bad data or bad ground. */
static void WriteEngineers(const char[] when)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || TF2_GetClientTeam(i) != TFTeam_Red)
			continue;

		if (TF2_GetPlayerClass(i) != TFClass_Engineer)
			continue;

		int sentry = FindOwnedObject(i, TFObject_Sentry);
		int dispenser = FindOwnedObject(i, TFObject_Dispenser);
		int entrance = FindOwnedTeleporter(i, TFObjectMode_Entrance);
		int teleExit = FindOwnedTeleporter(i, TFObjectMode_Exit);

		float sentryAt[3];
		bool haveSentry = sentry != -1;

		if (haveSentry)
			GetEntPropVector(sentry, Prop_Send, "m_vecOrigin", sentryAt);

		char name[MAX_NAME_LENGTH]; GetClientName(i, name, sizeof(name));

		char line[ENGINEER_LINE_LENGTH];
		FormatEx(line, sizeof(line),
			"{\"event\":\"engineer\",\"map\":\"%s\",\"wave\":%d,\"when\":\"%s\",\"who\":\"%s\","
			... "\"sentry\":%d,\"dispenser\":%d,\"entrance\":%d,\"exit\":%d,"
			... "\"dispenser_from_sentry\":%.0f,\"exit_from_sentry\":%.0f,\"alive\":%d,"
			... "\"samples\":%d,\"with_sentry\":%d,\"with_level3\":%d,\"with_dispenser\":%d}",
			g_sMap, g_iWave, when, name,
			BuildingLevel(sentry), BuildingLevel(dispenser), BuildingLevel(entrance), BuildingLevel(teleExit),
			haveSentry ? RangeToBuilding(sentryAt, dispenser) : -1.0,
			haveSentry ? RangeToBuilding(sentryAt, teleExit) : -1.0,
			IsPlayerAlive(i) ? 1 : 0,
			g_iEngineerSamples[i], g_iSamplesWithSentry[i], g_iSamplesWithLevel3[i], g_iSamplesWithDispenser[i]);

		WriteLine(line);
	}
}

//Level, or zero when there is no such building, which is the answer the file wants either way
static int BuildingLevel(int building)
{
	if (building == -1)
		return 0;

	return GetEntProp(building, Prop_Send, "m_iUpgradeLevel");
}

static float RangeToBuilding(const float from[3], int building)
{
	if (building == -1)
		return -1.0;

	float at[3]; GetEntPropVector(building, Prop_Send, "m_vecOrigin", at);

	return GetVectorDistance(from, at);
}

static int FindOwnedObject(int client, TFObjectType type)
{
	int count = TF2Util_GetPlayerObjectCount(client);

	for (int i = 0; i < count; i++)
	{
		int owned = TF2Util_GetPlayerObject(client, i);

		if (TF2_GetObjectType(owned) == type)
			return owned;
	}

	return -1;
}

static int FindOwnedTeleporter(int client, TFObjectMode mode)
{
	int count = TF2Util_GetPlayerObjectCount(client);

	for (int i = 0; i < count; i++)
	{
		int owned = TF2Util_GetPlayerObject(client, i);

		if (TF2_GetObjectType(owned) == TFObject_Teleporter && TF2_GetObjectMode(owned) == mode)
			return owned;
	}

	return -1;
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
	/* A wave nobody played is not a result
	 *
	 * The game ends a wave when the round resets, which it does when the server restarts, so a
	 * restart wrote a row of zeros into the file. run.sh counts rows, so that row was the run: it
	 * stopped twenty seconds in and reported a wave lost that never began. Only a wave with a
	 * beginning is written.
	 */
	if (g_flWaveStart <= 0.0)
	{
		return;
	}

	float duration = GetGameTime() - g_flWaveStart;

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
		... "\"killedby_sentry\":%d,\"killedby_tank\":%d,"
		... "\"cause_bullet\":%d,\"cause_explosion\":%d,\"cause_fire\":%d,"
		... "\"cause_melee\":%d,\"cause_backstab\":%d,\"cause_headshot\":%d,"
		... "\"cause_fall\":%d,\"cause_other\":%d,"
		... "\"selfdamage_scout\":%d,\"selfdamage_soldier\":%d,\"selfdamage_pyro\":%d,"
		... "\"selfdamage_demoman\":%d,\"selfdamage_heavy\":%d,\"selfdamage_engineer\":%d,"
		... "\"selfdamage_medic\":%d,\"selfdamage_sniper\":%d,\"selfdamage_spy\":%d,"
		... "\"selfdeaths_scout\":%d,\"selfdeaths_soldier\":%d,\"selfdeaths_pyro\":%d,"
		... "\"selfdeaths_demoman\":%d,\"selfdeaths_heavy\":%d,\"selfdeaths_engineer\":%d,"
		... "\"selfdeaths_medic\":%d,\"selfdeaths_sniper\":%d,\"selfdeaths_spy\":%d,"
		... "\"demo_pipe_damage\":%d,\"demo_sticky_damage\":%d,\"demo_melee_damage\":%d,"
		... "\"soldier_rocket_damage\":%d,\"soldier_other_damage\":%d,"
		... "\"fired_soldier\":%d,\"hit_soldier\":%d,\"fired_demoman\":%d,\"hit_demoman\":%d}",
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
		g_Wave.deathsToTank,
		g_Wave.deathsByCause[DEATH_CAUSE_BULLET],
		g_Wave.deathsByCause[DEATH_CAUSE_EXPLOSION],
		g_Wave.deathsByCause[DEATH_CAUSE_FIRE],
		g_Wave.deathsByCause[DEATH_CAUSE_MELEE],
		g_Wave.deathsByCause[DEATH_CAUSE_BACKSTAB],
		g_Wave.deathsByCause[DEATH_CAUSE_HEADSHOT],
		g_Wave.deathsByCause[DEATH_CAUSE_FALL],
		g_Wave.deathsByCause[DEATH_CAUSE_OTHER],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_Scout)],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_Soldier)],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_Pyro)],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_DemoMan)],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_Heavy)],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_Engineer)],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_Medic)],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_Sniper)],
		g_Wave.selfDamageByClass[view_as<int>(TFClass_Spy)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_Scout)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_Soldier)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_Pyro)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_DemoMan)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_Heavy)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_Engineer)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_Medic)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_Sniper)],
		g_Wave.selfDeathsByClass[view_as<int>(TFClass_Spy)],
		g_Wave.demoPipeDamage, g_Wave.demoStickyDamage, g_Wave.demoMeleeDamage,
		g_Wave.soldierRocketDamage, g_Wave.soldierOtherDamage,
		g_Wave.projectilesFired[view_as<int>(TFClass_Soldier)],
		g_Wave.projectilesHit[view_as<int>(TFClass_Soldier)],
		g_Wave.projectilesFired[view_as<int>(TFClass_DemoMan)],
		g_Wave.projectilesHit[view_as<int>(TFClass_DemoMan)]);

	WriteLine(line);

	/* What the server's frames cost while that was happening

	Its own line, because it is about the machine rather than about the bots, and it should be
	possible to read a run's frame times without parsing everything else. */
	char perf[ENGINEER_LINE_LENGTH];
	FormatEx(perf, sizeof(perf),
		"{\"event\":\"perf\",\"map\":\"%s\",\"wave\":%d,\"frames\":%d,"
		... "\"frames_slow\":%d,\"frames_stalled\":%d,\"frame_mean_ms\":%.2f,\"frame_worst_ms\":%.1f,"
		... "\"red\":%d}",
		g_sMap, g_iWave, g_Wave.frames, g_Wave.framesSlow, g_Wave.framesStalled,
		g_Wave.frames > 0 ? g_Wave.frameTotalMs / float(g_Wave.frames) : 0.0,
		g_Wave.frameWorstMs, CountTeam(TFTeam_Red, false));

	WriteLine(perf);

	WriteEngineers("end");

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

	//A defender who is his own killer, which no scoreboard has ever told apart from being shot
	if (attacker == victim && TF2_GetClientTeam(victim) == TFTeam_Red)
	{
		int selfClass = view_as<int>(TF2_GetPlayerClass(victim));
		
		if (selfClass >= 0 && selfClass < sizeof(g_Wave.selfDeathsByClass))
			g_Wave.selfDeathsByClass[selfClass]++;
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

	g_Wave.deathsByCause[DeathCause(customKill, event.GetInt("damagebits"))]++;
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
	
	if (IsCountedProjectile(classname))
		RequestFrame(Frame_CountProjectile, EntIndexToEntRef(entity));
}

//Whether this is one of the arcing projectiles whose hit rate is worth knowing
static bool IsCountedProjectile(const char[] classname)
{
	return StrEqual(classname, "tf_projectile_rocket")
		|| StrEqual(classname, "tf_projectile_pipe")
		|| StrEqual(classname, "tf_projectile_pipe_remote");
}

/* Counted a frame later, because the owner is not set when the entity is created
 *
 * OnEntityCreated fires before the game attaches the projectile to whoever fired it, so asking for
 * the owner here answers nobody for every shot in the mission.
 */
public void Frame_CountProjectile(any ref)
{
	int projectile = EntRefToEntIndex(ref);
	
	if (projectile == INVALID_ENT_REFERENCE || !IsValidEntity(projectile))
		return;
	
	int owner = GetEntPropEnt(projectile, Prop_Send, "m_hOwnerEntity");
	
	//A pipe belongs to its thrower; the owner handle is not always the one that is set
	if ((owner < 1 || owner > MaxClients) && HasEntProp(projectile, Prop_Send, "m_hThrower"))
		owner = GetEntPropEnt(projectile, Prop_Send, "m_hThrower");
	
	if (owner < 1 || owner > MaxClients || !IsClientInGame(owner))
		return;
	
	if (TF2_GetClientTeam(owner) != TFTeam_Red)
		return;
	
	int class = view_as<int>(TF2_GetPlayerClass(owner));
	
	if (class >= 0 && class < sizeof(g_Wave.projectilesFired))
		g_Wave.projectilesFired[class]++;
}

static void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client < 1 || !IsClientInGame(client))
		return;
	
	/* Both teams, for two different counts
	
	The robots are hooked for the damage the defenders put into them. The defenders are hooked for
	the damage they put into themselves, and that hook used to sit behind the return below: it was
	attached to robots only, so it could never once fire, and the results file reported that nobody
	had ever hurt themselves while the same file counted Demomen killing themselves. A measurement
	that cannot produce a number looks exactly like a number of zero. */
	TFTeam team = TF2_GetClientTeam(client);
	
	if (team == TFTeam_Blue)
	{
		SDKUnhook(client, SDKHook_OnTakeDamagePost, OnRobotDamagePost);
		SDKHook(client, SDKHook_OnTakeDamagePost, OnRobotDamagePost);
	}
	else if (team == TFTeam_Red)
	{
		SDKUnhook(client, SDKHook_OnTakeDamagePost, OnDefenderDamagePost);
		SDKHook(client, SDKHook_OnTakeDamagePost, OnDefenderDamagePost);
	}
}

static void OnRobotDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	CountDefenderDamage(attacker, inflictor, damage, false);
}

/* A defender hurting himself, which is his own weapon and nobody else's fault
 *
 * Only when he is both ends of it: teammates cannot hurt each other in MvM, so anything a defender
 * does to a defender is a man standing too close to his own explosion.
 */
static void OnDefenderDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	if (victim != attacker || victim < 1 || victim > MaxClients || !IsClientInGame(victim))
		return;
	
	if (TF2_GetClientTeam(victim) != TFTeam_Red)
		return;
	
	int class = view_as<int>(TF2_GetPlayerClass(victim));
	
	if (class >= 0 && class < sizeof(g_Wave.selfDamageByClass))
		g_Wave.selfDamageByClass[class] += RoundToNearest(damage);
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
		
		if (class == view_as<int>(TFClass_DemoMan))
		{
			if (StrEqual(classname, "tf_projectile_pipe_remote"))
				g_Wave.demoStickyDamage += amount;
			else if (StrEqual(classname, "tf_projectile_pipe"))
				g_Wave.demoPipeDamage += amount;
		}
		else if (class == view_as<int>(TFClass_Soldier) && StrEqual(classname, "tf_projectile_rocket"))
		{
			g_Wave.soldierRocketDamage += amount;
		}
		
		/* One projectile counts as one hit however many robots it catches
		
		Otherwise a rocket into a crowd reads as five hits and the rate goes over a hundred. */
		if (IsCountedProjectile(classname) && inflictor != g_iLastCountedProjectile)
		{
			g_iLastCountedProjectile = inflictor;
			
			if (class >= 0 && class < sizeof(g_Wave.projectilesHit))
				g_Wave.projectilesHit[class]++;
		}
	}
	else if (inflictor == attacker)
	{
		//The inflictor is the man himself, which means a hitscan weapon or a swing
		if (class == view_as<int>(TFClass_DemoMan))
			g_Wave.demoMeleeDamage += amount;
		else if (class == view_as<int>(TFClass_Soldier))
			g_Wave.soldierOtherDamage += amount;
	}
}

/* The custom kill says the special cases, the damage bits say the ordinary ones

Order matters: a backstab is also a melee hit and a headshot is also a bullet, so the specific
answer has to be asked for first or every stab is filed as "melee" */
static int DeathCause(int customKill, int damageBits)
{
	switch (customKill)
	{
		case TF_CUSTOM_BACKSTAB:
			return DEATH_CAUSE_BACKSTAB;
		
		case TF_CUSTOM_HEADSHOT, TF_CUSTOM_HEADSHOT_DECAPITATION:
			return DEATH_CAUSE_HEADSHOT;
		
		case TF_CUSTOM_BURNING, TF_CUSTOM_BURNING_FLARE:
			return DEATH_CAUSE_FIRE;
	}
	
	if (damageBits & DMG_BURN)
		return DEATH_CAUSE_FIRE;
	
	if (damageBits & DMG_BLAST)
		return DEATH_CAUSE_EXPLOSION;
	
	if (damageBits & DMG_CLUB)
		return DEATH_CAUSE_MELEE;
	
	if (damageBits & DMG_BULLET)
		return DEATH_CAUSE_BULLET;
	
	if (damageBits & DMG_FALL)
		return DEATH_CAUSE_FALL;
	
	return DEATH_CAUSE_OTHER;
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

/* Where every bot was and what it was doing, written down instead of watched
 *
 * Five separate faults this week were found by somebody playing the game and noticing: an engineer
 * stood in a house, a medic in the middle of the map, a dispenser beside a teleporter entrance. All
 * five looked identical from outside, all five took a round of guessing to name, and two of those
 * guesses were wrong. The reason is that nothing wrote down what the bots were doing, so the only
 * instrument was a person watching one of six bots at a time.
 *
 * These lines are that instrument. Facts, not verdicts: where he is, what is in his hands, what his
 * behaviour stack says, who his medigun is on. A verdict about whether that is good belongs in the
 * report, where it can be changed without another run.
 */
#define TELEMETRY_SAMPLE_INTERVAL	5.0
#define TELEMETRY_LINE_LENGTH		1024

/* How far from a building somebody counts as being served by it
 *
 * A dispenser's own heal radius, and the range a level three sentry shoots at. The dispenser
 * number is what answers "is it in a place that is any use to the team", which is the question a
 * spot walked by hand is meant to settle and nothing has ever checked.
 */
#define DISPENSER_SERVE_RANGE	450.0
#define SENTRY_SERVE_RANGE		1100.0

static float g_flNextTelemetrySample;
static char g_sTelemetryStack[512];

static void CollectTelemetryActionName(BehaviorAction action)
{
	char name[64]; action.GetName(name, sizeof(name));

	if (g_sTelemetryStack[0] != '\0')
		StrCat(g_sTelemetryStack, sizeof(g_sTelemetryStack), " < ");

	StrCat(g_sTelemetryStack, sizeof(g_sTelemetryStack), name);
}

/* Everything with a behaviour, and nothing without one
 *
 * ActionsManager.Iterator throws on a client that is not a NextBot, and a thrown native takes the
 * whole callback with it: the seat-holder mvmbots_host puts on RED is an ordinary fake client, so
 * the first sample of every frame died on it and not one telemetry line reached the file.
 *
 * The two plugins ship in the same directory and one exists to keep the other's server running, so
 * asking it what it named its seat is cheaper than guessing at a property that tells NextBots apart
 * from fake clients. */
static bool HasBehaviour(int client)
{
	static ConVar hostName;

	if (hostName == null)
		hostName = FindConVar("mvmbots_host_name");

	if (hostName == null)
		return true;

	char seat[MAX_NAME_LENGTH]; hostName.GetString(seat, sizeof(seat));
	char name[MAX_NAME_LENGTH]; GetClientName(client, name, sizeof(name));

	return !StrEqual(name, seat);
}

static void TelemetryActionStack(int client, char[] buffer, int maxlength)
{
	g_sTelemetryStack[0] = '\0';

	if (HasBehaviour(client))
		ActionsManager.Iterator(client, CollectTelemetryActionName);

	strcopy(buffer, maxlength, g_sTelemetryStack);
}

//Live enemies within range of a point that it can actually see, which is what a sentry is worth
static int EnemiesServedBy(int building, const float at[3], float range)
{
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || TF2_GetClientTeam(i) != TFTeam_Blue)
			continue;

		float theirs[3]; GetClientAbsOrigin(i, theirs);

		if (GetVectorDistance(at, theirs) > range)
			continue;

		theirs[2] += 40.0;

		TR_TraceRayFilter(at, theirs, MASK_SHOT, RayType_EndPoint, TraceIgnoreBuilding, building);

		if (TR_DidHit())
			continue;

		count++;
	}

	return count;
}

public bool TraceIgnoreBuilding(int entity, int mask, any data)
{
	return entity != data && (entity < 1 || entity > MaxClients);
}

//Defenders within range of a point, which is what a dispenser is worth wherever somebody put it
static int TeammatesServedBy(const float at[3], float range)
{
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || TF2_GetClientTeam(i) != TFTeam_Red)
			continue;

		float theirs[3]; GetClientAbsOrigin(i, theirs);

		if (GetVectorDistance(at, theirs) <= range)
			count++;
	}

	return count;
}

/* How close the nearest robot is, which is the whole of "is he standing too far forward"
 *
 * A Soldier and a Demoman fight with a projectile that arcs and splashes. Too far and it lands
 * behind a moving robot; too close and the splash is on the man who fired it. Neither is visible
 * from a damage total, and both have been guessed at.
 */
static float RangeToNearestEnemy(int client)
{
	float mine[3]; GetClientAbsOrigin(client, mine);
	float best = -1.0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || TF2_GetClientTeam(i) != TFTeam_Blue)
			continue;
		
		float theirs[3]; GetClientAbsOrigin(i, theirs);
		
		float range = GetVectorDistance(mine, theirs);
		
		if (best < 0.0 || range < best)
			best = range;
	}
	
	return best;
}

static void WriteBotTelemetry(int client, float when, float clock)
{
	float at[3]; GetClientAbsOrigin(client, at);

	char name[MAX_NAME_LENGTH]; GetClientName(client, name, sizeof(name));
	char stack[512]; TelemetryActionStack(client, stack, sizeof(stack));

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	char weaponClass[64] = "none";
	int slot = -1;

	if (weapon != -1)
	{
		GetEntityClassname(weapon, weaponClass, sizeof(weaponClass));
		slot = TF2Util_GetWeaponSlot(weapon);
	}

	//Who the medigun is actually on, which is the difference between a medic healing and a medic walking
	char healing[MAX_NAME_LENGTH] = "";
	int medigun = GetPlayerWeaponSlot(client, 1);

	if (medigun != -1 && HasEntProp(medigun, Prop_Send, "m_hHealingTarget"))
	{
		int patient = GetEntPropEnt(medigun, Prop_Send, "m_hHealingTarget");

		if (patient > 0 && patient <= MaxClients && IsClientInGame(patient))
			GetClientName(patient, healing, sizeof(healing));
	}

	char line[TELEMETRY_LINE_LENGTH];
	FormatEx(line, sizeof(line),
		"{\"event\":\"bot\",\"map\":\"%s\",\"wave\":%d,\"t\":%.1f,\"clock\":%.1f,\"who\":\"%s\",\"class\":\"%s\","
		... "\"at\":[%.0f,%.0f,%.0f],\"hp\":%d,\"maxhp\":%d,\"weapon\":\"%s\",\"slot\":%d,"
		... "\"nearest_enemy\":%.0f,\"healing\":\"%s\",\"action\":\"%s\"}",
		g_sMap, g_iWave, when, clock, name, ClassName(TF2_GetPlayerClass(client)),
		at[0], at[1], at[2], GetClientHealth(client), TF2Util_GetEntityMaxHealth(client),
		weaponClass, slot, RangeToNearestEnemy(client), healing, stack);

	WriteLine(line);
}

static void WriteBuildingTelemetry(int owner, int building, float when, float clock)
{
	float at[3]; GetEntPropVector(building, Prop_Send, "m_vecOrigin", at);

	char ownerName[MAX_NAME_LENGTH]; GetClientName(owner, ownerName, sizeof(ownerName));
	char class[64]; GetEntityClassname(building, class, sizeof(class));

	float eye[3]; eye = at;
	eye[2] += 40.0;

	bool disposable = HasEntProp(building, Prop_Send, "m_bDisposableBuilding")
		&& GetEntProp(building, Prop_Send, "m_bDisposableBuilding") != 0;

	int kills = HasEntProp(building, Prop_Send, "m_iKills")
		? GetEntProp(building, Prop_Send, "m_iKills") : -1;

	char line[TELEMETRY_LINE_LENGTH];
	FormatEx(line, sizeof(line),
		"{\"event\":\"building\",\"map\":\"%s\",\"wave\":%d,\"t\":%.1f,\"clock\":%.1f,\"owner\":\"%s\","
		... "\"type\":\"%s\",\"mode\":%d,\"level\":%d,\"hp\":%d,\"maxhp\":%d,\"at\":[%.0f,%.0f,%.0f],"
		... "\"disposable\":%d,\"kills\":%d,\"enemies_seen\":%d,\"teammates_near\":%d,\"sapped\":%d}",
		g_sMap, g_iWave, when, clock, ownerName, class,
		HasEntProp(building, Prop_Send, "m_iObjectMode") ? GetEntProp(building, Prop_Send, "m_iObjectMode") : 0,
		GetEntProp(building, Prop_Send, "m_iUpgradeLevel"),
		GetEntProp(building, Prop_Data, "m_iHealth"), GetEntProp(building, Prop_Send, "m_iMaxHealth"),
		at[0], at[1], at[2], disposable ? 1 : 0, kills,
		EnemiesServedBy(building, eye, SENTRY_SERVE_RANGE),
		TeammatesServedBy(at, DISPENSER_SERVE_RANGE),
		GetEntProp(building, Prop_Send, "m_bHasSapper") != 0 ? 1 : 0);

	WriteLine(line);
}

/* Sampled in both round states, unlike the engineer uptime above
 *
 * Half of what has gone wrong went wrong between waves: the walk to the front, the shopping trip,
 * the toolbox still set to the last building. Sampling only while a wave runs is sampling the half
 * that was never the problem.
 */
static void SampleTelemetry()
{
	if (GetGameTime() < g_flNextTelemetrySample)
		return;

	g_flNextTelemetrySample = GetGameTime() + TELEMETRY_SAMPLE_INTERVAL;

	/* Seconds into the wave, and the server clock beside it
	
	Between waves there is no wave to be seconds into, so t is zero for every sample in the break.
	That makes a whole break's worth of samples look like one instant: reading the file back, one
	dispenser sampled fourteen times came out as fourteen dispensers, which is a bug this file was
	built to find and briefly invented instead. The clock is what tells two samples apart. */
	float when = g_flWaveStart > 0.0 ? GetGameTime() - g_flWaveStart : 0.0;
	float clock = GetGameTime();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsFakeClient(i) || TF2_GetClientTeam(i) != TFTeam_Red)
			continue;

		if (!IsPlayerAlive(i) || !HasBehaviour(i))
			continue;

		WriteBotTelemetry(i, when, clock);

		int objects = TF2Util_GetPlayerObjectCount(i);

		for (int n = 0; n < objects; n++)
			WriteBuildingTelemetry(i, TF2Util_GetPlayerObject(i, n), when, clock);
	}
}

//The name the rest of the file already writes into its keys, so the two agree without a lookup
static char[] ClassName(TFClassType class)
{
	char name[16];

	switch (class)
	{
		case TFClass_Scout:		name = "scout";
		case TFClass_Sniper:	name = "sniper";
		case TFClass_Soldier:	name = "soldier";
		case TFClass_DemoMan:	name = "demoman";
		case TFClass_Medic:		name = "medic";
		case TFClass_Heavy:		name = "heavy";
		case TFClass_Pyro:		name = "pyro";
		case TFClass_Spy:		name = "spy";
		case TFClass_Engineer:	name = "engineer";
		default:				name = "unknown";
	}

	return name;
}
