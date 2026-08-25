/* The sentry, which is the whole of the engineer's job and was the last building still guessing

The dispenser and the teleporter both learned the same lesson and this had not: a building goes
down in front of the man and never under him, so walking onto the spot and pressing fire aims the
sentry at whatever is a build's reach beyond it. The old code walked to the nest point, stood on
it, and aimed at its own feet. Between rounds that mostly worked, because the engineer is
teleported onto the point and the ground under a nest hint is usually clear; in the middle of a
wave, having walked there, it did not.

There was also no clock on any of it. No reach deadline, no give-up: an engineer who could not
place a sentry stayed in this action for the rest of the wave, which is what a test-bed run of
Bigrock's first wave looked like from outside. Eight minutes, no sentry, and nothing in the logs
saying why. Everything here has a limit now, and running out of one hands the engineer back to the
idle action, which tries again three seconds later with a freshly scored nest. */

//A build's reach short of the spot, with the spot in front of him, same as the other two
#define SENTRY_BUILD_REACH	90.0

/* Eight looks at the spot, one from each side, before the spot itself is the thing in question

A sentry refused from one side is usually a sentry with a wall behind it rather than a sentry on
bad ground, and the answer to that is to stand somewhere else. Re-scoring the nest on the first
refusal, which is what this did, threw away a good spot for a bad reason and cost a full pass over
the nav mesh every time it happened. */
#define SENTRY_TRY_POINTS	8
#define SENTRY_TRY_TIME		1.5

/* How long the walk and the whole business may take

The walk is priced by its length, because "the walk is inside the nest" stopped being true the
moment he started every one of them at the upgrade station. Past the build time he goes back to
the idle action rather than settling for where he stands: a sentry is not a dispenser, and one
pointed at a wall is worse than three more seconds spent finding somewhere it can see from.

The settle range is the important one. Running out of clock used to mean building beside himself
wherever he had got to, with no distance test of any kind: that is a sentry at a random place on
the map, reported from play on Coaltown, and this file's own comment admits to one 625 units from
its nest on Decoy. Two build reaches is close enough that what he settles for still sees what the
nest was chosen to see. Further out he keeps walking, and the give-up clock hands him back to the
idle action, which scores a nest again and tries afresh. */
#define SENTRY_REACH_TIME	12.0
#define SENTRY_SETTLE_RANGE	200.0
#define SENTRY_BUILD_TIME	45.0

static float m_ctSentryReachDeadline[MAXPLAYERS + 1];
static float m_ctSentryGiveUpTime[MAXPLAYERS + 1];
static float m_ctSentryTryDeadline[MAXPLAYERS + 1];
static int m_iSentryTry[MAXPLAYERS + 1];
static float m_vSentrySpot[MAXPLAYERS + 1][3];
static float m_vSentryStand[MAXPLAYERS + 1][3];

BehaviorAction CTFBotMvMEngineerBuildSentrygun()
{
	BehaviorAction action = ActionsManager.Create("DefenderBuildSentrygun");
	
	action.OnStart = CTFBotMvMEngineerBuildSentrygun_OnStart;
	action.Update = CTFBotMvMEngineerBuildSentrygun_Update;
	action.OnEnd = CTFBotMvMEngineerBuildSentrygun_OnEnd;
	
	return action;
}

public Action CTFBotMvMEngineerBuildSentrygun_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
	
	m_ctSentryGiveUpTime[actor] = GetGameTime() + SENTRY_BUILD_TIME;
	m_ctSentryTryDeadline[actor] = GetGameTime() + SENTRY_TRY_TIME;
	m_iSentryTry[actor] = 0;
	
	if (GameRules_GetRoundState() == RoundState_BetweenRounds)
	{
		if (m_aNestArea[actor])
		{
			//Teleport ourselves to the nest area for a faster setup
			float vNestPosition[3]; NestBuildPosition(m_aNestArea[actor], vNestPosition);
			vNestPosition[2] += TFBOT_STEP_HEIGHT;
			CBaseEntity(actor).SetAbsOrigin(vNestPosition);
		}
	}
	
	SentryStandPoint(actor);
	
	//After the teleport above, so a between-rounds walk is priced from where he actually starts it
	m_ctSentryReachDeadline[actor] = GetGameTime() + BuildReachTime(GetAbsOrigin(actor), m_vSentryStand[actor]);
	
	LogBuildFailure(actor, "sentry", "started");
	
	return action.Continue();
}

public Action CTFBotMvMEngineerBuildSentrygun_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (m_aNestArea[actor] == NULL_AREA) 
	{
		LogBuildFailure(actor, "sentry", "no nest area");
		return action.Done("No hint entity");
	}
	
	if (CTFBotMvMEngineerIdle_ShouldAdvanceNestSpot(actor))
	{
		//And you.
		
		LogBuildFailure(actor, "sentry", "told to advance the nest");
		return action.Done("No sentry");
	}
	
	//Every side of this spot refused him and the walk is not getting shorter. The idle action retries
	if (GetGameTime() > m_ctSentryGiveUpTime[actor])
	{
		LogBuildFailure(actor, "sentry", "every side of the spot refused him");
		
		return action.Done("Nowhere here will take a sentry");
	}
	
	float spot[3]; spot = m_vSentrySpot[actor];
	float stand[3]; stand = m_vSentryStand[actor];
	
	/* The walk ran out, so he builds from where he got to rather than into whatever stopped him
	
	And he puts it beside himself rather than pointing it at the nest he could not reach. Aiming at
	the nest from three metres short of it is the same thing; aiming at it from twenty metres short
	puts the sentry twenty metres from where anybody wanted it, facing a direction chosen by where
	he happened to get stuck. Decoy produced one 625 units from its own nest that way. */
	bool outOfTime = GetGameTime() > m_ctSentryReachDeadline[actor]
		&& GetVectorDistance(GetAbsOrigin(actor), m_vSentrySpot[actor]) < SENTRY_SETTLE_RANGE;
	
	if (outOfTime)
	{
		stand = GetAbsOrigin(actor);
		
		BuildStandPoint(stand, m_vSentrySpot[actor], m_iSentryTry[actor],
			SENTRY_TRY_POINTS, SENTRY_BUILD_REACH, spot);
	}
	
	float range_to_stand = GetVectorDistance(GetAbsOrigin(actor), stand);
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);
	INextBot myNextbot = CBaseNPC_GetNextBotOfEntity(actor);
	IBody myBody = myNextbot.GetBodyInterface();
	ILocomotion myLoco = myNextbot.GetLocomotionInterface();
	
	if (range_to_stand < 200.0) 
	{
		//Start building a sentry
		if (!IsBuilderSetTo(actor, TFObject_Sentry))
			FakeClientCommandThrottled(actor, "build 2");
		
		UpdateLookAroundForEnemies(actor, false);
		
		if (!myLoco.IsStuck())
		{
			g_arrExtraButtons[actor].PressButtons(IN_DUCK, 0.1);
		}
		
		//It goes where he looks, so he looks at the spot rather than at the ground under himself
		AimHeadTowards(myBody, spot, MANDATORY, 0.1, _, "Placing sentry");
	}
	
	if (range_to_stand > 70.0)
	{
		//The clock on this attempt starts when he arrives: the walk to it is not a look at it
		m_ctSentryTryDeadline[actor] = GetGameTime() + SENTRY_TRY_TIME;
		
		g_arrPluginBot[actor].SetPathGoalVector(stand);
		g_arrPluginBot[actor].bPathing = true;
		
		if (range_to_stand > 300.0)
		{
			//Fuck em up.
			EquipWeaponSlot(actor, TFWeaponSlot_Primary);
		}
		
		UpdateLookAroundForEnemies(actor, true);
		
		return action.Continue();
	}
	
	g_arrPluginBot[actor].bPathing = false;
	
	if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_BUILDER)
	{
		int objBeingBuilt = GetEntPropEnt(myWeapon, Prop_Send, "m_hObjectBeingBuilt");
		
		if (objBeingBuilt == -1)
			return action.Continue();
		
		VS_PressFireButton(actor);
		
		/* The game says no from here, so try looking at it from the next side round
		
		Only once he is actually looking at it: the answer while his head is still coming round is
		the answer for wherever it was pointing, which is not this spot. */
		if (!IsPlacementOK(objBeingBuilt) && myBody.IsHeadAimingOnTarget()
			&& GetGameTime() > m_ctSentryTryDeadline[actor])
		{
			m_iSentryTry[actor]++;
			
			/* Every side refused him, so now the spot itself is the thing in question
			
			This is where the nest gets re-scored, and not before: a pass over the nav mesh is the
			expensive answer and it was being given to a wall behind the man. */
			if (m_iSentryTry[actor] >= SENTRY_TRY_POINTS)
			{
				m_aNestArea[actor] = PickBuildArea(actor);
				m_iSentryTry[actor] = 0;
			}
			
			SentryStandPoint(actor);
			
			m_ctSentryTryDeadline[actor] = GetGameTime() + SENTRY_TRY_TIME;
			m_ctSentryReachDeadline[actor] = GetGameTime() + SENTRY_REACH_TIME;
			
			return action.Continue();
		}
	}
	
	int sentry = GetObjectOfType(actor, TFObject_Sentry);
	
	if (sentry == INVALID_ENT_REFERENCE)
		return action.Continue();
	
	SetPlayerReady(actor, true);
	
	LogBuildFailure(actor, "sentry", "built one");
	
	return action.Done("Built a sentry");
}

/* Where the sentry goes and where he stands to put it there, on a side he can stand on

Sides with nothing walkable under them are skipped rather than walked at: a nest on raised ground
has thin air around it, and pathing at a coordinate in mid-air puts the engineer on the floor below
holding the toolbox until a clock saves him. Bounded by the number of sides there are. */
static void SentryStandPoint(int actor)
{
	NestBuildPosition(m_aNestArea[actor], m_vSentrySpot[actor]);
	
	for (int skipped = 0; skipped < SENTRY_TRY_POINTS; skipped++)
	{
		if (BuildStandPoint(m_vSentrySpot[actor], GetAbsOrigin(actor), m_iSentryTry[actor],
			SENTRY_TRY_POINTS, SENTRY_BUILD_REACH, m_vSentryStand[actor]))
			return;
		
		m_iSentryTry[actor] = (m_iSentryTry[actor] + 1) % SENTRY_TRY_POINTS;
	}
}

public void CTFBotMvMEngineerBuildSentrygun_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	g_arrPluginBot[actor].bPathing = false;
	
	UpdateLookAroundForEnemies(actor, true);
	
	/* Every way out of this action, including the ones nobody wrote a branch for
	
	The Done branches above name why they gave up, and a session produced far more starts than
	endings that said anything. Asking the result for its reason here printed nothing at all, which
	is what a thrown native looks like from the outside: it takes the callback with it. So this says
	only what is certainly true, which is that the attempt is over and whether it left a sentry. */
	LogBuildFailure(actor, "sentry",
		GetObjectOfType(actor, TFObject_Sentry) != INVALID_ENT_REFERENCE ? "ended with a sentry" : "ended with nothing");
}
