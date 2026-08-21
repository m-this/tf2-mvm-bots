#define DISPENSER_SPOT_TAKEN_RANGE	150.0

/* How far from the nest a named spot may be and still be this nest's dispenser spot

The pairing was whichever named spot was nearest the nest in a straight line, with no ceiling on
it, so a map that names three nests and three spots can hand a nest a spot that belongs to another
one. Coaltown does: the nest above the track at z 496 is 415 units from the spot on the floor at
z 273, which is nearer than any spot on its own level, and the engineer walked off looking for it,
failed to place anything for the whole reach deadline and dropped the dispenser where he stood.

The height is a separate test from the distance because two floors are close in plan and a
staircase apart in fact. Past either, the nest area itself is the better answer: a dispenser beside
the sentry is the point of the thing. */
#define DISPENSER_NEST_RANGE	400.0
#define DISPENSER_NEST_HEIGHT	120.0

/* How long an engineer may spend walking to where the dispenser goes

Reported on Rottenburg: engineers stuck on a rock trying to build one. The action pathed to a
spot and, if the geometry would not let it arrive, asked again next frame forever. A nav mesh
says ground is connected; it does not promise a bot can squeeze past a boulder to reach the
middle of it.

Past the deadline the dispenser goes down where the engineer is standing. A dispenser two metres
from the intended spot is worth all of one that never gets built, and the engineer is back in the
wave instead of walking into a rock for the rest of it. */
#define DISPENSER_REACH_TIME	12.0

/* Where he stands to put a dispenser on the spot, which is not the spot

A building goes down in front of the man, never under him. Walking onto the coordinate and
pressing fire aims the dispenser at whatever is a build's reach beyond it, which on Coaltown is
the wall on the right: the placement never comes up green, and the engineer stands on the spot
holding the toolbox until the wave starts without him.

So he stops a reach short of the spot and looks at it. The old code turned him on the spot
instead, a tenth of a second of IN_RIGHT at a time, which cannot help: the direction he faces is
the direction the dispenser goes, so turning moves the problem rather than solving it.

When the game still says no, he walks to the next point around the spot and looks at it from
there. Eight of them, which is a look from every side at forty five degrees. */
#define DISPENSER_BUILD_REACH	90.0
#define DISPENSER_TRY_POINTS	8
#define DISPENSER_TRY_TIME		2.0

/* How long he may spend on the whole business before he goes back to the wave

The readiness gate holds a wave until the engineer's nest is finished, and a nest is not finished
without a dispenser. An engineer who can never place one is an engineer holding every wave for
the length of that grace, which is what a spot with no room around it costs. */
#define DISPENSER_BUILD_TIME	25.0

static float m_ctDispenserReachDeadline[MAXPLAYERS + 1];
static float m_ctDispenserGiveUpTime[MAXPLAYERS + 1];
static float m_ctDispenserTryDeadline[MAXPLAYERS + 1];
static int m_iDispenserTry[MAXPLAYERS + 1];
static float m_vDispenserSpot[MAXPLAYERS + 1][3];
static float m_vDispenserStand[MAXPLAYERS + 1][3];

BehaviorAction CTFBotMvMEngineerBuildDispenser()
{
	BehaviorAction action = ActionsManager.Create("DefenderBuildDispenser");
	
	action.OnStart = CTFBotMvMEngineerBuildDispenser_OnStart;
	action.Update = CTFBotMvMEngineerBuildDispenser_Update;
	action.OnEnd = CTFBotMvMEngineerBuildDispenser_OnEnd;
	
	return action;
}

public Action CTFBotMvMEngineerBuildDispenser_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
	
	m_ctDispenserReachDeadline[actor] = GetGameTime() + DISPENSER_REACH_TIME;
	m_ctDispenserGiveUpTime[actor] = GetGameTime() + DISPENSER_BUILD_TIME;
	m_ctDispenserTryDeadline[actor] = GetGameTime() + DISPENSER_TRY_TIME;
	m_iDispenserTry[actor] = 0;
	
	//Once, here, because the Update runs every tick and a path computation does not belong there
	if (!ConfiguredDispenserSpot(actor, m_vDispenserSpot[actor]))
	{
		if (m_aNestArea[actor] != NULL_AREA)
			CNavArea_GetRandomPoint(m_aNestArea[actor], m_vDispenserSpot[actor]);
		else
			m_vDispenserSpot[actor] = GetAbsOrigin(actor);
	}
	
	DispenserStandPoint(actor, m_iDispenserTry[actor], m_vDispenserStand[actor]);
	
	return action.Continue();
}

public Action CTFBotMvMEngineerBuildDispenser_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (m_aNestArea[actor] == NULL_AREA) 
	{
		return action.Done("No hint entity");
	}
	
	if (GetObjectOfType(actor, TFObject_Sentry) == INVALID_ENT_REFERENCE)
	{
		//Fuck you.
		
		return action.Done("No sentry");
	}
	else
	{
		//sentry is not safe.
		if (m_ctSentrySafe[actor] < GetGameTime())
		{
			return action.Done("Sentry not safe");
		}
	}
	
	if (CTFBotMvMEngineerIdle_ShouldAdvanceNestSpot(actor))
	{
		//Fuck you too.
		
		return action.Done("Need to advance nest");
	}
	
	/* The spot is chosen once, not every frame

	Choosing it here used to mean a path computation per configured spot per tick per engineer,
	which is how the server's watchdog came to fire inside NavAreaBuildPath. A spot that was
	reachable when the action started is reachable a second later, and if it is not, the deadline
	below is what answers for it. */
	//Every side of the spot refused him, and a wave held for one dispenser is the worse trade
	if (GetGameTime() > m_ctDispenserGiveUpTime[actor])
		return action.Done("Nowhere to put a dispenser");
	
	float spot[3]; spot = m_vDispenserSpot[actor];
	float stand[3]; stand = m_vDispenserStand[actor];
	
	//The walk ran out of time, so he builds from where he stands and aims at the spot anyway
	bool outOfTime = m_ctDispenserReachDeadline[actor] > 0.0 && GetGameTime() > m_ctDispenserReachDeadline[actor];
	
	if (outOfTime)
		stand = GetAbsOrigin(actor);
	
	float range_to_stand = GetVectorDistance(GetAbsOrigin(actor), stand);
	
	INextBot myNextbot = CBaseNPC_GetNextBotOfEntity(actor);
	IBody myBody = myNextbot.GetBodyInterface();
	
	if (range_to_stand < 200.0) 
	{
		//Start building a dispenser
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, "build 0");
		
		//It goes where he looks, so he looks at the spot. Turning on the spot only turns the problem
		AimHeadTowards(myBody, spot, MANDATORY, 0.1, _, "Placing dispenser");
		
		//NOTE: we do not look around for incoming enemies cause all we care about is placing this dispenser
	}
	
	if (range_to_stand > 70.0)
	{
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
		
		/* The game says no from here, so try looking at it from the next side
		
		Only once he is actually looking at the spot: the answer while his head is still coming
		round is the answer for wherever it was pointing, which is not this spot. */
		if (!IsPlacementOK(objBeingBuilt) && !outOfTime
			&& myBody.IsHeadAimingOnTarget() && GetGameTime() > m_ctDispenserTryDeadline[actor])
		{
			NextDispenserStandPoint(actor);
			
			return action.Continue();
		}
	}
	
	VS_PressFireButton(actor);
	
	int dispenser = GetObjectOfType(actor, TFObject_Dispenser);
	
	if (dispenser == INVALID_ENT_REFERENCE)
		return action.Continue();
	
	SetPlayerReady(actor, true);
	
	return action.Done("Built a dispenser");
}

/* One build's reach short of the spot, on the side the try asks for

Try zero is the side he is walking in from, so the first look costs him no walking at all. Each
one after it is forty five degrees round from there. */
static void DispenserStandPoint(int actor, int attempt, float stand[3])
{
	float spot[3]; spot = m_vDispenserSpot[actor];
	float fromSpot[3]; SubtractVectors(GetAbsOrigin(actor), spot, fromSpot);
	
	fromSpot[2] = 0.0;
	
	//Standing on it himself, so any side will do to start from
	if (NormalizeVector(fromSpot, fromSpot) < 1.0)
	{
		fromSpot[0] = 1.0;
		fromSpot[1] = 0.0;
	}
	
	float yaw = ArcTangent2(fromSpot[1], fromSpot[0]) + DegToRad(360.0 / DISPENSER_TRY_POINTS * attempt);
	
	stand[0] = spot[0] + Cosine(yaw) * DISPENSER_BUILD_REACH;
	stand[1] = spot[1] + Sine(yaw) * DISPENSER_BUILD_REACH;
	stand[2] = spot[2];
}

//The next side of the spot, or the end of them, which is when he takes whatever he can get
static void NextDispenserStandPoint(int actor)
{
	m_iDispenserTry[actor]++;
	
	if (m_iDispenserTry[actor] >= DISPENSER_TRY_POINTS)
	{
		//A dispenser two metres from the spot beats an engineer who never builds one
		m_ctDispenserReachDeadline[actor] = GetGameTime();
		
		return;
	}
	
	DispenserStandPoint(actor, m_iDispenserTry[actor], m_vDispenserStand[actor]);
	
	m_ctDispenserTryDeadline[actor] = GetGameTime() + DISPENSER_TRY_TIME;
}

public void CTFBotMvMEngineerBuildDispenser_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
}

/* The dispenser spot the map configuration asks for, false when it asks for nothing

Nearest to the nest rather than to the engineer, because he walks back to the nest anyway and the
dispenser is there to feed the sentry */
bool ConfiguredDispenserSpot(int actor, float spot[3])
{
	ArrayList spots = g_arrMapConfig.adtDispenserLocation;
	
	if (spots.Length == 0)
		return false;
	
	float nest[3]; m_aNestArea[actor].GetCenter(nest);
	
	ArrayList free = new ArrayList(3);
	
	for (int i = 0; i < spots.Length; i++)
	{
		float candidate[3]; spots.GetArray(i, candidate);
		
		//Somebody else's nest named this one
		if (GetVectorDistance(nest, candidate) > DISPENSER_NEST_RANGE
			|| FloatAbs(candidate[2] - nest[2]) > DISPENSER_NEST_HEIGHT)
			continue;
		
		//A spot the engineer cannot walk to is not a spot. Rottenburg has a rock in front of one
		if (IsDispenserSpotTaken(actor, candidate) || !IsPathToVectorPossible(actor, candidate))
			continue;
		
		free.PushArray(candidate);
	}
	
	bool found = NearestConfiguredSpot(free, nest, spot);
	
	delete free;
	
	if (redbots_manager_debug.BoolValue)
	{
		if (found)
			PrintToServer("ConfiguredDispenserSpot: %N takes the named spot %.0f %.0f %.0f", actor, spot[0], spot[1], spot[2]);
		else
			PrintToServer("ConfiguredDispenserSpot: %N has no named spot for the nest at %.0f %.0f %.0f", actor, nest[0], nest[1], nest[2]);
	}
	
	return found;
}

//Spreads several engineers over the spots the map names instead of stacking them on the nearest one
bool IsDispenserSpotTaken(int actor, const float spot[3])
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == actor || !IsClientInGame(i))
			continue;
		
		int dispenser = GetObjectOfType(i, TFObject_Dispenser);
		
		if (dispenser == INVALID_ENT_REFERENCE)
			continue;
		
		if (GetVectorDistance(spot, GetAbsOrigin(dispenser)) < DISPENSER_SPOT_TAKEN_RANGE)
			return true;
	}
	
	return false;
}
