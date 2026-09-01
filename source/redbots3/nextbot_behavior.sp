//CTFBotMedicHeal::m_patient
#define ACTION_HEAL_PATIENT_OFFSET	0x4850

#define FLAMETHROWER_REACH_RANGE	350.0
#define FLAMEBALL_REACH_RANGE	526.0

PathFollower m_pPath[MAXPLAYERS + 1];
ChasePath m_pChasePath[MAXPLAYERS + 1];
float m_flRepathTime[MAXPLAYERS + 1];
/* The bottle this bot is wearing, kept rather than found again every frame

Finding it walks the entity list looking for a tf_powerup_bottle, and this runs on the player
command, which is every frame for every bot. The bottle is a wearable: it appears when the bot
spawns and does not move afterwards, so it is worth exactly one lookup a life.

The second was worse. This used to be a cached canteen type, written by the purchase code, and the
purchase code is gone: nothing wrote it any more, so the switch below always read "no bottle" and
a bot handed a canteen would never have drunk it. The type comes off the bottle now, which is
where it was always true. */
#if defined EXTRA_PLUGINBOT
//Replicate behavior of PathFollower's PluginBot
enum struct esPluginBot
{
	bool bPathing;
	float vecPathGoal[3];
	int iPathGoalEntity;
	
	void Reset()
	{
		this.bPathing = false;
		this.vecPathGoal = NULL_VECTOR;
		this.iPathGoalEntity = -1;
	}
	
	bool HasPathGoalVector()
	{
		return !Vector_IsZero(this.vecPathGoal);
	}
	
	bool HasPathGoalEntity()
	{
		return this.iPathGoalEntity != -1;
	}
	
	void SetPathGoalVector(const float vec[3])
	{
		//You can only set one or the other, not both
		this.iPathGoalEntity = -1;
		this.vecPathGoal = vec;
	}
	
	void SetPathGoalEntity(int entity)
	{
		this.vecPathGoal = NULL_VECTOR;
		this.iPathGoalEntity = entity;
	}
}

esPluginBot g_arrPluginBot[MAXPLAYERS + 1];
#endif

/* What to do when the nav mesh will not give a path to somewhere the bot has to be

Every behaviour in this mod that walks anywhere sets a goal, sets bPathing, and trusts that this
function gets the bot there. Nothing ever checked whether a path came back. ComputeToTarget returns
a bool and it was discarded, so a failed computation left an empty path, Update walked the bot
along nothing, and the behaviour above went on believing it was travelling.

Measured on Coaltown: a medic with a live patient two thousand units away, "walking", path 0 long,
in the same spot for thirty five seconds while a demoman on half health fought without him. That is
the medic stuck in the middle of the map, reported four times and blamed on four different things,
this one included.

The mesh usually refuses from one particular piece of ground rather than for the whole journey, so
the answer is to get off that ground. A step in the goal's direction, guarded the same way the
attack strafe guards one, and the next computation is made from somewhere else. Counted, because a
bot doing this often is a bot the map's nav mesh has a hole in. */

/* How many paths the whole team may compute in one frame
 *
 * NavAreaBuildPath is a search over the map's nav areas and it is what the watchdog has caught the
 * server inside three times now, most recently with nest relocation on: the symbolised frame was
 * CNavArea::GetZ under ComputePortal under NavAreaBuildPath, reached from a plugin's ComputeToPos
 * inside the per-frame PlayerRunCmd forward. An unreachable goal makes that search walk the whole
 * mesh, and six bots asking in the same frame multiplies it.
 *
 * Two a frame at 66 ticks is a hundred and thirty a second, which is far more than the 0.2 second
 * refresh below ever wants, so nobody waits for a path in practice. What it removes is the frame
 * where everybody asks at once. */
/* Write down a path search that cost real time

The crash in the cores is a frame the watchdog killed, and the story is that a bot asking for an
impossible path walks the whole mesh to find that out. Nothing has ever measured what one of these
costs, so the story has never been checked: about thirty five attempts reproduced the wedge and not
one long frame. This says what a search actually takes, which is the number the story rests on. */

/* How far a path search may walk before it gives up, and 0.0 for no limit

NavAreaBuildPath searches until it reaches the goal or runs out of mesh, so a goal it cannot reach
costs the whole map every time it is asked. Six bots asking in one frame is the 1833 ms frame
Mannhattan produced and Decoy never did.

The number is generous on purpose. It is not a leash on where a bot may go: it is the point past
which the search has plainly failed, and every real route on these maps is far inside it. */

public Action Command_DumpSpawnNav(int client, int args)
{
	ReplyToCommand(client, "Spawn NAV recovery: enabled %d, radius %.0f, max time %.1f", redbots_manager_spawn_nav_recovery.BoolValue,
		redbots_manager_spawn_nav_recovery_radius.FloatValue, redbots_manager_spawn_nav_recovery_time.FloatValue);

	for (int bot = 1; bot <= MaxClients; bot++)
	{
		if (!IsClientInGame(bot) || !IsPlayerAlive(bot) || !g_bIsDefenderBot[bot])
			continue;

		bool strict = TF2Util_IsPointInRespawnRoom(WorldSpaceCenter(bot), bot);
		float distance = DistanceToClosestDefenderSpawn(bot);
		bool near = strict || distance >= 0.0 && distance <= redbots_manager_spawn_nav_recovery_radius.FloatValue;
		float now = GetGameTime();
		float watched = m_flSpawnExitStartedAt[bot] > 0.0 ? now - m_flSpawnExitStartedAt[bot] : 0.0;
		float stalled = m_flSpawnExitProgressAt[bot] > 0.0 ? now - m_flSpawnExitProgressAt[bot] : 0.0;
		float moved = m_flSpawnExitProgressAt[bot] > 0.0 ? GetVectorDistance(GetAbsOrigin(bot), m_vecSpawnExitProgress[bot]) : 0.0;
		char anchorSource[32];
		bool anchorNav = FindSpawnRecoveryArea(bot, anchorSource, sizeof(anchorSource)) != NULL_AREA;

		ReplyToCommand(client, "%N: strict %d, spawn distance %.0f, near %d, eligible %d, upgrade zone %d, watched %.1fs, stalled %.1fs, moved %.0f, anchor %s, anchor NAV %d",
			bot, strict, distance, near, ShouldWatchDefenderSpawnExit(bot), TF2_IsInUpgradeZone(bot), watched, stalled, moved, anchorSource, anchorNav);
	}

	return Plugin_Handled;
}

public Action Command_RecoverSpawnBots(int client, int args)
{
	int recovered;

	for (int bot = 1; bot <= MaxClients; bot++)
	{
		if (!IsClientInGame(bot) || !IsPlayerAlive(bot) || !g_bIsDefenderBot[bot] || !IsInOrNearDefenderSpawn(bot))
			continue;

		if (MoveDefenderFromSpawnToBattlefield(bot, "was manually recovered by an admin"))
			recovered++;
	}

	ReplyToCommand(client, "Recovered %d defender bot(s) from the configured spawn radius.", recovered);
	return Plugin_Handled;
}

#include "generated/botqueries.sp"
#include "generated/readiness.sp"
#include "generated/pathing.sp"
#include "generated/stuckwatch.sp"
#include "generated/mediccall.sp"
#include "generated/spawnexit.sp"
#include "generated/scoutjump.sp"
#include "generated/bottle.sp"
#include "generated/dispatch.sp"
#include "generated/medicnudge.sp"
#include "generated/hooks.sp"
#include "generated/attack.sp"
#include "generated/markgiant.sp"
#include "generated/collectmoney.sp"
#include "generated/gotoupgrade.sp"
#include "generated/attributes.sp"
#include "generated/upgrade_rank.sp"
#include "generated/upgrade_rules.sp"
#include "behavior/upgrade.sp"
#include "generated/getammo.sp"
#include "generated/movetofront.sp"
#include "generated/gethealth.sp"
#include "generated/engineeridle.sp"
#include "generated/engineerbuildsentrygun.sp"
#include "generated/engineerbuilddispenser.sp"
#include "generated/engineerbuildteleporter.sp"
#include "generated/engineerbuilddisposable.sp"
#include "generated/spycheck.sp"
#include "generated/stickytrap.sp"
#include "generated/spylurk.sp"
#include "generated/spysap.sp"
#include "generated/spysapplayer.sp"
#include "generated/medicrevive.sp"
#include "generated/medic.sp"
#include "generated/attackforuber.sp"
#include "generated/evadebuster.sp"
#include "generated/campbomb.sp"
#include "generated/attacktank.sp"
#include "generated/destroyteleporter.sp"
#include "generated/guardpoint.sp"
#include "generated/collectnearmoney.sp"

void InitNextBotPathing()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		m_pPath[i] = PathFollower(_, Path_FilterIgnoreActors, Path_FilterOnlyActors);
		m_pChasePath[i] = ChasePath(LEAD_SUBJECT, _, Path_FilterIgnoreActors, Path_FilterOnlyActors);
	}
}

void ResetNextBot(int client)
{
	m_flRepathTime[client] = 0.0;
	m_flNextJumpTime[client] = 0.0;
	ResetSpyCheck(client);
	ResetStickyTrap(client);
	
	m_hPowerupBottle[client] = INVALID_ENT_REFERENCE;
	m_ctPowerupBottleLook[client] = 0.0;
	m_flNextBottleUseTime[client] = 0.0;
	
	m_iAttackTarget[client] = -1;
	m_iTarget[client] = -1;
	m_flNextMarkTime[client] = 0.0;
	m_iCurrencyPack[client] = -1;
	m_iStation[client] = -1;
	m_flNextUpgrade[client] = 0.0;
	m_nPurchasedUpgrades[client] = 0;
	m_flUpgradingTime[client] = 0.0;
	m_iAmmoPack[client] = -1;
	m_vecGoalArea[client] = NULL_VECTOR;
	m_ctMoveTimeout[client] = 0.0;
	m_iHealthPack[client] = -1;
	//NOTE: engineer-specific behavior stuff is reset in the action itself
	m_iSapTarget[client] = -1;
	m_iPlayerSapTarget[client] = -1;
	m_vecStartArea[client] = NULL_VECTOR;
	m_iTankTarget[client] = -1;
	m_iTeleporterTarget[client] = -1;
	m_vecPointDefendArea[client] = NULL_VECTOR;
	
#if defined EXTRA_PLUGINBOT
	g_arrPluginBot[client].Reset();
#endif
}

#endif

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
	//TFBots are players, ignore all other nextbots
	if (actor <= MaxClients)
	{
		if (StrEqual(name, "MainAction"))
		{
			action.SelectTargetPoint = CTFBotMainAction_SelectTargetPoint;
			action.ShouldAttack = CTFBotMainAction_ShouldAttack;
			action.Update = CTFBotMainAction_Update;
		}
		else if (StrEqual(name, "TacticalMonitor"))
		{
			action.Update = CTFBotTacticalMonitor_Update;
			
			/* NOTE: I've noticed this seems to be very inconsistent at the MainAction level and it also seems to behave differently on windows vs linux
			Let's just override it at the TacticalMonitor level, though this one doesn't actually have a function for it in its class
			But since all nextbot callbacks are virtual i think this should work fine */
			action.SelectMoreDangerousThreat = CTFBotMainAction_SelectMoreDangerousThreat;
		}
		else if (StrEqual(name, "ScenarioMonitor"))
		{
			action.Update = CTFBotScenarioMonitor_Update;
		}
		else if (StrEqual(name, "Heal"))
		{
			action.UpdatePost = CTFBotMedicHeal_UpdatePost;
		}
		else if (StrEqual(name, "FetchFlag"))
		{
			action.OnStart = CTFBotFetchFlag_OnStart;
		}
		else if (StrEqual(name, "MvMEngineerIdle"))
		{
			action.OnStart = CTFBotMvMEngineerIdle_OnStart;
		}
		else if (StrEqual(name, "SniperLurk"))
		{
			action.Update = CTFBotSniperLurk_Update;
			action.SelectMoreDangerousThreat = CTFBotSniperLurk_SelectMoreDangerousThreat;
		}
		else if (StrEqual(name, "SpyLeaveSpawnRoom"))
		{
			action.OnStart = CTFBotSpyLeaveSpawnRoom_OnStart;
		}
	}
}

/* What a robot is worth killing first

The ranges, the enum and the generated table are in generated/threat_priority.sp, written from
internal/threat in tf2-mvm-bots-go. The chain below is the one that shipped, kept beside it so the
two can be played against each other: see FEATURE_GENERATED_THREAT_PRIORITY. */

static int ThreatPriority(int threat, float rangeSq)
{
	if (rangeSq < THREAT_URGENT_RANGE * THREAT_URGENT_RANGE)
		return THREAT_PRIORITY_URGENT;
	
	//Too far to be worth walking the aim across the map for
	if (rangeSq > THREAT_PRIORITY_RANGE * THREAT_PRIORITY_RANGE)
		return THREAT_PRIORITY_NONE;
	
	if (!BaseEntity_IsPlayer(threat) || !IsClientInGame(threat))
		return THREAT_PRIORITY_NONE;
	
	switch (TF2_GetPlayerClass(threat))
	{
		//A giant with a Medic on it is not killable until the Medic is dead
		case TFClass_Medic:
			return THREAT_PRIORITY_MEDIC;
		
		//The two the rest of the team cannot get to: one sits out of reach, the other builds
		case TFClass_Sniper, TFClass_Engineer:
			return THREAT_PRIORITY_SUPPORT;
	}
	
	bool giant = TF2_IsMiniBoss(threat);
	bool carrier = TF2_HasTheFlag(threat);
	
	//Carrying the bomb halves a robot's speed, except a giant's, so that one is still running
	if (giant && carrier)
		return THREAT_PRIORITY_GIANT_BOMB;
	
	if (giant)
		return THREAT_PRIORITY_GIANT;
	
	if (carrier)
		return THREAT_PRIORITY_BOMB;
	
	return THREAT_PRIORITY_NONE;
}

/* The same question, asked of the generated table

The record is what the move in mvm-z83.6 was for: the decision takes what is known about a threat
rather than an entity index, so something that occupies no player slot can still be ranked. Every
threat scan in this mod walks player slots and a tank occupies none, which is mvm-ds3, and this
does not fix it. It makes fixing it possible.

Every field after isPlayer is filled behind it, not beside it, and the first version of this was
not. The chain above reads the class, the miniboss flag and the carrier flag only after its player
test has passed, and all three throw when asked about something that is not a player: measured,
TF2_HasTheFlag threw 3933 times over four waves on tank_boss and obj_attachment_sapper, and each
one aborted the whole threat choice for that tick.

The decision reads none of them for a non-player, so filling them false costs nothing. That is
asserted in internal/threat rather than assumed here. See mvm-z83.46. */
static int ThreatPriorityGenerated(int threat, float rangeSq)
{
	bool isPlayer = BaseEntity_IsPlayer(threat);
	bool inGame = isPlayer && IsClientInGame(threat);
	
	if (!inGame)
		return ThreatPriorityOf(rangeSq, isPlayer, false, TFClass_Unknown, false, false);
	
	return ThreatPriorityOf(rangeSq, isPlayer, true, TF2_GetPlayerClass(threat),
		TF2_IsMiniBoss(threat), TF2_HasTheFlag(threat));
}

/* Where the generated answer and the shipped chain part company, while the port is measured

The differential test proves the decision and the table agree on every combination it can be asked
about. It cannot prove the edge fills the record the way the chain reads it, because it drives both
sides from the same record. Only a running game can answer that.

Scaffolding, to be deleted with the measurement. It runs on the armed side only, so the other arm
pays nothing, and it stops writing after twenty lines because a disagreement that happens at all is
the finding and a log full of them is not more of one. */
static int g_iThreatSplits;
static int g_iThreatCompared;

/* Say how much was compared, not only what disagreed

Zero disagreements and never having run look identical in a log that only writes on a
disagreement, and reading the first as the second is the fault mvm-z83.23 is about. */
void ThreatPortAudit_Report()
{
	if (g_iThreatCompared == 0)
		return;
	
	LogMessage("threat audit: %d compared, %d disagreed", g_iThreatCompared, g_iThreatSplits);
	
	g_iThreatCompared = 0;
}

static void ThreatPortAudit(int threat, float rangeSq)
{
	g_iThreatCompared++;
	
	if (g_iThreatSplits >= 20)
		return;
	
	int shipped = ThreatPriority(threat, rangeSq);
	int fromTable = ThreatPriorityGenerated(threat, rangeSq);
	
	if (shipped == fromTable)
		return;
	
	g_iThreatSplits++;
	
	char classname[64];
	GetEntityClassname(threat, classname, sizeof(classname));
	
	LogMessage("threat audit: entity %d/%s rangeSq %.0f, chain says %d, table says %d",
		threat, classname, rangeSq, shipped, fromTable);
}

/* A bot is ready when it has done the thing its seat exists for

An engineer pressed ready the moment a sentry entity existed, which is a level one still being
hammered together, and the wave started in front of it. A level three sentry and a level three
dispenser are what an engineer's seat is for; the teleporter can be built in his own time.

The medic used to be held here too, until his charge was full. It is off again: a charge builds
into whoever he is beaming, so the wait is however long it takes him to find somebody and stay
next to them, which was minutes of everybody else standing about, and a medic who wandered off
looking for a patient held the wave from wherever he ended up. He is ready when he spawns.

Several places set a bot ready and gating each of them would be four chances to miss one, so this
takes the ready away again while the nest is unfinished, every frame, wherever it came from.

The grace is the important part. A bot that cannot finish, because a buster took the sentry or
the metal ran out, must not hold the wave forever: past it it is ready whatever it has. */

/* Readying a bot, and ending whatever is stopping it saying so

/* Whether leaving the fight to find a pack is worth what the walk costs the team

For everybody it is. For a medic it almost never is: he heals himself, three health a second and
six once he has been out of it a while, so the pack buys him what standing still would have bought
him anyway. What it costs is the medigun, for the length of a trip that the search range prices at
up to two thousand units.

Coaltown is why this is written down. The health pack there is in the house in the middle of the
map, so a medic who took eighty percent of a rocket left the front line and walked to the exact
spot he has now been reported standing in three times. Ammo goes with it: the medigun does not use
any and the syringe gun is what he holds when there is nobody to heal.

/* A bot that is trying to walk somewhere and not getting anywhere

Every one of this mod's reported faults arrives looking the same. A build spot computed in mid-air,
a toolbox still set to the last building, two rules dragging a medic between two patients, a filter
that excluded every coin on the floor: five different causes, and from inside the game all five are
a bot standing still. Standing still is silent, so each of them was found by somebody playing and
noticing, one at a time, and the first guess at the cause was wrong about as often as it was right.

This does not fix any of them. It makes them loud. The one thing true of all of them is that the
bot wanted to be somewhere and stopped getting closer to it, so that is what is measured: past the
deadline his behaviour is thrown away and rebuilt, which is what the wave-start reset already does
to every bot, and the fact is printed so a test-bed run counts them instead of a player noticing.

Only while he is asking to go somewhere. An engineer stood at a finished nest and a sniper on his
perch are both motionless on purpose and neither is stuck.

Deferred by a frame, because throwing away the action stack from inside an action's own update is
freeing the thing that is running. */
/* Whether this is a sniper who is nowhere near a spot and not on his way to one

Near a spot means he arrived and standing still is his job. Far from every one of them means he is
not doing the thing his seat exists for.

This used to require SniperLurk on his stack, which is exactly backwards for the fault Peppy
reported. His logs name it: bot 25 sat at 706 -2229 480 for 1097 samples, one position, stack
"MainAction < TacticalMonitor < ScenarioMonitor" and no SniperLurk at all, while bot 24 held the
lurk and moved through 234 positions. The stuck one has a stack, so the idle watchdog's empty-stack
test never fires either, and he is not pathing, so nothing else arms. He was invisible to every
check the watchdog had.

So the lurk is not required, in either direction: a rifle sniper parked far from every spot is the
fault whether ScenarioMonitor gave him a lurk that cannot finish or never gave him one. The reset
is what both need, and it is the same restart a custom primary causes by accident. See mvm-bj8. */
/* Somewhere out of the wedge, and false when nothing near him is far enough

A random point in his own area is what this used to take, and on Mannhunt that was the bug: he is
standing on valid nav and wedged in the geometry above it, so the nearest area is the one under his
feet and a point inside it lands back on him. Six give-ups in a row at 1014 885 274 and not one
move, which is mvm-ipf.

So his own area is tried first and only accepted when the point clears STUCK_RADIUS, then the areas
touching it. Bounded twice over: the four directions, and MOVE_WEDGED_TRIES points per area. */

/* Put a wedged bot somewhere it can walk, when resetting it has stopped working

The same shape as the spawn recovery below and for the same reason, one step further along: that
one moves a bot that never left spawn, and this one moves a bot that left and then stopped. Both
beat leaving it where it is, because a bot that cannot move asks for a path every frame and the
watchdog kills the server on the answer.

/* A Scout that keeps both feet on the ground

Nothing in this mod ever pressed IN_JUMP. Not in a fight, not to cross a gap, nowhere: a
play-test called the Scouts too easy to kill and that is the whole of the reason. A robot leads
a target moving in two dimensions perfectly well. The third one is most of what keeps a Scout
alive, and it costs him nothing: a scattergun is as accurate in the air as on the ground.

Only a Scout. Every other class is slower in the air than on it, and a Heavy who leaves the
ground has traded his aim for a hop */

//Close enough that the robot shooting back cannot miss unless it is made to

//Slow enough to be standing still, whatever the bot thinks it is doing

/* The second jump, and why it is not every time

A Scout that always double jumps is as easy to lead as one that never does: the second jump lands
on the same beat every time. Seven times in ten is often enough to be the thing an aim expects and
irregular enough that expecting it is wrong.

The second jump goes the other way. Jumping twice in one direction is one long arc and a shooter
tracks it; jumping left and then right is two arcs with a corner in the middle, and the corner is
what a robot's aim cannot follow. Reported after the 1.3 play-test: he only ever single jumps */

/* The charge and the resistance, whoever is doing the healing

Written for the game's heal action and called from the mod's own as well, because suspending an
action stops its update running and these two are not the part worth reimplementing.

The charge is pressed rather than set: the deploy belongs to the game, and this only ever asks
for it sooner than the game's own dying-patient rule would have. */
//How much more health another body needs before it is worth breaking a beam for

/* How long a medic call is worth answering for

The game gives one event and no state: nothing says the call is still wanted, and nothing says it
was met. So the call is a countdown rather than a flag, and it is short. Long enough to cross the
room he is being called across, short enough that a player who called once during a wave is not
still holding the beam a minute later.

/* Whether this bot has nowhere of its own to wait out the break

The Engineer has a nest to build, the Spy has somewhere to lurk and the Sniper has a perch, and
all three get there under their own behaviour.

/* Whether this bot is one of the ones that should fall back to holding the hatch

public bool NextBotTraceFilterIgnoreActors(int entity, int contentsMask, any iExclude)
{
	char class[64]; GetEntityClassname(entity, class, sizeof(class));
	
	if (StrEqual(class, "entity_medigun_shield"))
		return false;
	else if (StrEqual(class, "func_respawnroomvisualizer"))
		return false;
	else if (StrContains(class, "tf_projectile_", false) != -1)
		return false;
	else if (StrContains(class, "obj_", false) != -1)
		return false;
	else if (StrEqual(class, "entity_revive_marker"))
		return false;
	else if (StrEqual(class, "tank_boss"))
		return false;
	else if (StrEqual(class, "func_forcefield"))
		return false;
	
	return !CBaseEntity(entity).IsCombatCharacter();
}

bool IsPathToVectorPossible(int bot_entidx, const float vec[3], float &length = -1.0)
{
	CBaseCombatCharacter(bot_entidx).UpdateLastKnownArea();
	
	PathFollower temp_path = PathFollower(_, Path_FilterIgnoreActors, Path_FilterOnlyActors);
	
	bool success = temp_path.ComputeToPos(CBaseNPC_GetNextBotOfEntity(bot_entidx), vec);
	
	length = temp_path.GetLength();
	
	temp_path.Destroy();
	
	return success;
}


/* Whether a weapon that fires off a meter has enough of it to fire, which HasAmmo cannot say

HasAmmo is CBaseCombatWeapon::HasAmmo, and a weapon carrying a meter instead of a clip has no ammo
to run out of, so it answers yes for ever. "Always throw gas whenever HasAmmo" therefore reads as
"always hold the jar": the Pyro equipped one it could not throw, on every tick, and never picked
the flamethrower back up. Four runs in six of Decoy ended on the watchdog line because of it, and
the loadout has carried a shotgun in that slot ever since to keep away from it.

The two kinds of meter are kept in different places, which is why this is not one line. Jarate,
Mad Milk and the Cleaver refill on a clock the weapon itself carries. The Gas Passer refills out
of damage dealt, and the game keeps that on the player, per loadout slot, rather than on the
weapon.

/* The Medic behind whatever we just picked, when there is one

/* Whether a teleporter is worth walking to

It used to answer yes to everything, in both branches, so the caller that exists to stop a bot
looking for one never stopped anything. A play-test watched the result and drew the obvious
conclusion, that engineers are better off not building teleporters at all: a defender who wants
to ride one has to walk back to the entrance first, and the entrance is at the spawn the fight is
being pushed towards. So the bots walked away from the hatch, into the teleporter, and out of it
roughly where they had started, having given the wave the seconds it takes to do all that.

A ride is worth it when it saves a walk the bot would otherwise make: the fight has to be far
enough up the path that going back to spawn and coming out forward is still ahead. When the bomb
is on the hatch, nothing is forward of anything, and the answer is no.

This says nothing about which teleporter, because there is nothing here to say it with. It is the
gate on looking at all, which is where the cost is */

//Far enough up the path that the walk back to the entrance is bought back by the ride

