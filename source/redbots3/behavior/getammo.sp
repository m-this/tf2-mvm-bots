static char g_strHealthAndAmmoEntities[][] = 
{
	"func_regenerate",
	"item_ammopack*",
	"item_health*",
	"obj_dispenser",
	"tf_ammo_pack"
};

int m_iAmmoPack[MAXPLAYERS + 1];

BehaviorAction CTFBotGetAmmo()
{
	BehaviorAction action = ActionsManager.Create("DefenderGetAmmo");
	
	action.OnStart = CTFBotGetAmmo_OnStart;
	action.Update = CTFBotGetAmmo_Update;
	action.OnEnd = CTFBotGetAmmo_OnEnd;
	action.ShouldHurry = CTFBotGetAmmo_ShouldHurry;
	action.ShouldAttack = CTFBotGetAmmo_ShouldAttack;
	
	return action;
}

public Action CTFBotGetAmmo_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	ArrayList ammo = new ArrayList(2);
	ComputeHealthAndAmmoVectors(actor, ammo, tf_bot_ammo_search_range.FloatValue);
	
	if (ammo.Length <= 0)
	{
		delete ammo;
		return action.Done("No ammo");
	}
	
	float flSmallestDistance = 99999.0;
	
	for (int i = 0; i < ammo.Length; i++)
	{
		int entity = ammo.Get(i, 0);
		
		if (!IsValidAmmo(entity))
			continue;
		
		float flDistance = view_as<float>(ammo.Get(i, 1));
		
		if (flDistance <= flSmallestDistance)
		{
			m_iAmmoPack[actor] = entity;
			flSmallestDistance = flDistance;
		}
	}
	
	delete ammo;
	
	if (m_iAmmoPack[actor] != -1)
	{
		if (TF2_GetPlayerClass(actor) == TFClass_Engineer)
			UpdateLookAroundForEnemies(actor, true);
		
		BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_DISPENSERHERE);
		return action.Continue();
	}
	
	// UpdateLookAroundForEnemies(actor, true);
	return action.Done("Could not find ammo");
}

public Action CTFBotGetAmmo_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidAmmo(m_iAmmoPack[actor]))
		return action.Done("ammo is not valid");
	
	if (IsAmmoFull(actor))
		return action.Done("Ammo is full");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.9, 1.0);
		m_pPath[actor].ComputeToPos(myBot, WorldSpaceCenter(m_iAmmoPack[actor]));
	}
	
	m_pPath[actor].Update(myBot);
	
	CKnownEntity threat = myBot.GetVisionInterface().GetPrimaryKnownThreat(false);
	
	if (threat)
		EquipBestWeaponForThreat(actor, threat);
	
	return action.Continue();
}

public void CTFBotGetAmmo_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iAmmoPack[actor] = -1;
}

public Action CTFBotGetAmmo_ShouldHurry(BehaviorAction action, INextBot nextbot, QueryResultType& result)
{
	//Disables dodging and we won't spin the minigun after recently seeing threats
	result = ANSWER_YES;
	return Plugin_Handled;
}

public Action CTFBotGetAmmo_ShouldAttack(BehaviorAction action, INextBot nextbot, CKnownEntity knownEntity, QueryResultType& result)
{
	int me = action.Actor;
	
	if (TF2_GetPlayerClass(me) == TFClass_Spy)
	{
		int iThreat = knownEntity.GetEntity();
		
		if (BaseEntity_IsPlayer(iThreat) && GetClientHealth(iThreat) > 360 && !TF2_IsCritBoosted(me))
		{
			//Don't attack if we can't possibly kill them with our revolver (360 from 6 shots with max damage)
			result = ANSWER_NO;
			return Plugin_Changed;
		}
		else if (GetNearestEnemyCount(me, 1000.0) > 1)
		{
			//There's too many enemies nearby, it'd be better to redisguise so they'll forget about us
			result = ANSWER_NO;
			return Plugin_Changed;
		}
	}
	
	result = ANSWER_UNDEFINED;
	return Plugin_Changed;
}

/* The health and ammo this bot could actually walk to, and how far each one really is

Two costs hide in this and both were paid per candidate: a nav mesh search, and a JSON object on
the heap. MvM floors are covered in candidates, because tf_ammo_pack is what a dead robot leaves
behind and a wave leaves hundreds of them.

So the cheap question goes first. Straight-line distance costs a subtraction and orders the
candidates; the search is run only for the nearest few, because the nearest few are where the
answer is and the rest were never going to win. A pack behind a wall now loses its place to the
next one along instead of costing a search of its own.

The list is entity index and travel distance, in pairs, and the caller takes the shortest. */
#define HEALTH_CANDIDATES_MAX	64
#define HEALTH_PATHS_MAX		4

void ComputeHealthAndAmmoVectors(int client, ArrayList found, float max_range)
{
	ArrayList nearby = new ArrayList(2);
	
	float myCentre[3]; myCentre = WorldSpaceCenter(client);
	
	for (int i = 0; i < sizeof(g_strHealthAndAmmoEntities); i++)
	{
		int ammo = -1;
		
		while ((ammo = FindEntityByClassname(ammo, g_strHealthAndAmmoEntities[i])) != -1)
		{
			//A wave leaves more of these on the floor than anybody is going to walk to
			if (nearby.Length >= HEALTH_CANDIDATES_MAX)
				break;
			
			if (BaseEntity_GetTeamNumber(ammo) == view_as<int>(GetPlayerEnemyTeam(client)))
				continue;
			
			float range = GetVectorDistance(myCentre, WorldSpaceCenter(ammo));
			
			if (range > max_range)
				continue;
			
			if (BaseEntity_IsBaseObject(ammo))
			{
				//Can't get anything from still building buildings.
				if (TF2_IsBuilding(ammo))
					continue;
				
				//Skip empty dispenser.
				if (TF2_GetObjectType(ammo) == TFObject_Dispenser && GetEntProp(ammo, Prop_Send, "m_iAmmoMetal") <= 0)
					continue;
			}
			
			int at = nearby.Push(range);
			nearby.Set(at, ammo, 1);
		}
	}
	
	nearby.SortCustom(SortByStraightLineRange);
	
	int searches = 0;
	
	for (int i = 0; i < nearby.Length && searches < HEALTH_PATHS_MAX; i++)
	{
		int ammo = nearby.Get(i, 1);
		float length;
		
		searches++;
		
		if (!IsPathToVectorPossible(client, WorldSpaceCenter(ammo), length))
			continue;
		
		if (length > max_range)
			continue;
		
		int at = found.Push(ammo);
		found.Set(at, length, 1);
	}
	
	delete nearby;
}

static int SortByStraightLineRange(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList list = view_as<ArrayList>(array);
	
	float first = view_as<float>(list.Get(index1, 0));
	float second = view_as<float>(list.Get(index2, 0));
	
	if (first < second)
		return -1;
	
	return first > second ? 1 : 0;
}

bool IsValidAmmo(int pack)
{
	if (!IsValidEntity(pack))
		return false;

	if (!HasEntProp(pack, Prop_Send, "m_fEffects"))
		return false;

	//It has been taken.
	if (GetEntProp(pack, Prop_Send, "m_fEffects") != 0)
		return false;

	char class[64]; GetEntityClassname(pack, class, sizeof(class));
	
	if (StrContains(class, "tf_ammo_pack", false) == -1 
	&& StrContains(class, "item_ammo", false) == -1 
	&& StrContains(class, "obj_dispenser", false) == -1
	&& StrContains(class, "func_regen", false) == -1)
	{
		return false;
	}
	
	//Can't use a disabled dispenser
	if (StrContains(class, "obj_dispenser", false) != -1 && TF2_HasSapper(pack))
		return false;
	
	return true;
}

/* Whether there is ammo worth walking to, kept for a moment after it is worked out

The tactical monitor asks this every frame, for every bot, and a bot that is low on ammo with
nothing reachable takes the slow path on every one of those frames. The slow path is a nav mesh
search. Six bots doing that at sixty-six frames a second, on a floor covered in what the dead
robots dropped, is thousands of searches a second for an answer that was no last frame and is no
this frame.

Half a second, which is a bot walking about a hundred and fifty units. Nothing that matters
appears inside that. */
#define AMMO_ASK_INTERVAL	0.5

static float m_ctAmmoAsk[MAXPLAYERS + 1];
static bool m_bAmmoPossible[MAXPLAYERS + 1];

bool CTFBotGetAmmo_IsPossible(int actor)
{
	//Skip lag.
	if (m_iAmmoPack[actor] != -1 && IsValidAmmo(m_iAmmoPack[actor]))
		return true;

	if (m_ctAmmoAsk[actor] > GetGameTime())
		return m_bAmmoPossible[actor];

	m_ctAmmoAsk[actor] = GetGameTime() + AMMO_ASK_INTERVAL;

	ArrayList ammo = new ArrayList(2);
	ComputeHealthAndAmmoVectors(actor, ammo, tf_bot_ammo_search_range.FloatValue);

	bool bPossible = false;
	
	for (int i = 0; i < ammo.Length; i++)
	{
		if (!IsValidAmmo(ammo.Get(i, 0)))
			continue;
		
		bPossible = true;
		break;
	}
	
	delete ammo;

	m_bAmmoPossible[actor] = bPossible;

	return bPossible;
}