#define SENTRY_WATCH_BOMB_RANGE	400.0

float m_ctSentrySafe[MAXPLAYERS + 1];
float m_ctSentryCooldown[MAXPLAYERS + 1];

float m_ctDispenserSafe[MAXPLAYERS + 1]; 
float m_ctDispenserCooldown[MAXPLAYERS + 1];

float m_ctFindNestHint[MAXPLAYERS + 1]; 
float m_ctAdvanceNestSpot[MAXPLAYERS + 1]; 

float m_ctRecomputePathMvMEngiIdle[MAXPLAYERS + 1];

bool g_bGoingToGrabBuilding[MAXPLAYERS + 1];
int m_hBuildingToGrab[MAXPLAYERS + 1];

BehaviorAction CTFBotMvMEngineerIdle()
{
	BehaviorAction action = ActionsManager.Create("DefenderEngineerIdle");
	
	action.OnStart = CTFBotMvMEngineerIdle_OnStart;
	action.Update = CTFBotMvMEngineerIdle_Update;
	action.OnEnd = CTFBotMvMEngineerIdle_OnEnd;
	action.OnMoveToSuccess = CTFBotMvMEngineerIdle_OnMoveToSuccess;
	
	return action;
}

static Action CTFBotMvMEngineerIdle_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	CTFBotMvMEngineerIdle_ResetProperties(actor);
	
	return action.Continue();
}

static Action CTFBotMvMEngineerIdle_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	int sentry    = GetObjectOfType(actor, TFObject_Sentry);
	int dispenser = GetObjectOfType(actor, TFObject_Dispenser);
	
	bool bShouldAdvance = CTFBotMvMEngineerIdle_ShouldAdvanceNestSpot(actor);
	
	if (bShouldAdvance && !g_bGoingToGrabBuilding[actor])
	{
		//DetonateObjectOfType(actor, TFObject_Sentry);
		//DetonateObjectOfType(actor, TFObject_Dispenser);
		
		if (redbots_manager_debug_actions.BoolValue)
			PrintToServer("CTFBotMvMEngineerIdle_Update: ADVANCE");
		
		//RIGHT NOW
		CTFBotMvMEngineerIdle_ResetProperties(actor);
		
		m_aNestArea[actor] = PickBuildArea(actor);
		
		if (sentry != INVALID_ENT_REFERENCE && m_aNestArea[actor] != NULL_AREA)
		{
			g_bGoingToGrabBuilding[actor] = true;
			
			m_hBuildingToGrab[actor] = EntIndexToEntRef(sentry);
			
			g_arrPluginBot[actor].SetPathGoalEntity(sentry);
		}
	}
	
	INextBot myNextbot = CBaseNPC_GetNextBotOfEntity(actor);
	IBody myBody = myNextbot.GetBodyInterface();
	ILocomotion myLoco = myNextbot.GetLocomotionInterface();
	
	if (g_bGoingToGrabBuilding[actor])
	{
		int building = EntRefToEntIndex(m_hBuildingToGrab[actor]);
		
		if (building == INVALID_ENT_REFERENCE)
		{
			g_bGoingToGrabBuilding[actor] = false;
			m_hBuildingToGrab[actor] = INVALID_ENT_REFERENCE;
			
			if (redbots_manager_debug_actions.BoolValue)
				PrintToServer("CTFBotMvMEngineerIdle_Update: g_bGoingToGrabBuilding : building %i | m_aNestArea %x", building, m_aNestArea[actor]);
			
			DetonateObjectOfType(actor, TFObject_Sentry);
			DetonateObjectOfType(actor, TFObject_Dispenser);
			
			g_arrPluginBot[actor].bPathing = false;
			return action.Continue();
		}
		
		UpdateLookAroundForEnemies(actor, false);
		
		if (!TF2_IsCarryingObject(actor))
		{
			float flDistanceToBuilding = GetVectorDistance(GetAbsOrigin(actor), GetAbsOrigin(building));
			
			if (flDistanceToBuilding < 90.0)
			{
				EquipWeaponSlot(actor, TFWeaponSlot_Melee);
				
				AimHeadTowards(myBody, WorldSpaceCenter(building), CRITICAL, 1.0, _, "Grab building");
				VS_PressAltFireButton(actor);
				
				//PrintToServer("Grab");
			}
		}
		else
		{
			if (m_aNestArea[actor] != NULL_AREA)
			{
				float center[3]; m_aNestArea[actor].GetCenter(center);
				g_arrPluginBot[actor].SetPathGoalVector(center);
				
				float flDistanceToGoal = GetVectorDistance(GetAbsOrigin(actor), center);
				
				if (flDistanceToGoal < 200.0)
				{
					//Crouch when closer than 200 hu
					if (!myLoco.IsStuck())
					{
						g_arrExtraButtons[actor].PressButtons(IN_DUCK, 0.1);
					}
					
					if (flDistanceToGoal < 70.0)
					{
						//Try placing building when closer than 70 hu
						int objBeingBuilt = TF2_GetCarriedObject(actor);
						
						if (objBeingBuilt == -1)
							return action.Continue();
						
						bool m_bPlacementOK = IsPlacementOK(objBeingBuilt);
						
						VS_PressFireButton(actor);
						
						if (!m_bPlacementOK && myBody.IsHeadAimingOnTarget() && myBody.GetHeadSteadyDuration() > 0.6)
						{
							//That spot was no good.
							//Time to pick a new spot.
							m_aNestArea[actor] = PickBuildArea(actor);
						}
						else
						{
							g_bGoingToGrabBuilding[actor] = false;
							m_hBuildingToGrab[actor] = INVALID_ENT_REFERENCE;
							
							g_arrPluginBot[actor].bPathing = false;
						}
					}
				}
				
				//PrintToServer("Travel");
			}
		}
		
		g_arrPluginBot[actor].bPathing = true;
		
		return action.Continue();
	}
	
	if ((m_aNestArea[actor] == NULL_AREA || bShouldAdvance) || sentry == INVALID_ENT_REFERENCE)
	{
		//HasStarted && !IsElapsed
		if (m_ctFindNestHint[actor] > 0.0 && m_ctFindNestHint[actor] > GetGameTime())
		{
			return action.Continue();
		}
		
		//Start
		m_ctFindNestHint[actor] = GetGameTime() + (GetRandomFloat(1.0, 2.0));
		
		m_aNestArea[actor] = PickBuildArea(actor);
	}
	
	if (bShouldAdvance)
		return action.Continue();
	
	if (sentry != -1 && dispenser != -1)
	{
		if (m_ctSentrySafe[actor] > GetGameTime() && !g_bGoingToGrabBuilding[actor])
		{
			int mySecondary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
			
			if (mySecondary != -1 && TF2Util_GetWeaponID(mySecondary) == TF_WEAPON_LASER_POINTER && myNextbot.IsRangeLessThan(sentry, 180.0))
			{
				CKnownEntity threat = myNextbot.GetVisionInterface().GetPrimaryKnownThreat(false);
				
				if (threat)
				{
					int iThreat = threat.GetEntity();
					
					if (GetVectorDistance(GetAbsOrigin(sentry), GetAbsOrigin(iThreat)) > SENTRY_MAX_RANGE && IsLineOfFireClearEntity(actor, GetEyePosition(actor), iThreat))
					{
						AimHeadTowards(myBody, WorldSpaceCenter(iThreat), MANDATORY, 0.1, _, "Aiming!");
						TF2Util_SetPlayerActiveWeapon(actor, mySecondary);
						
						if (myBody.IsHeadAimingOnTarget() && GetEntProp(sentry, Prop_Send, "m_bPlayerControlled"))
						{
							OSLib_RunScriptCode(actor, _, _, "self.PressFireButton(0.1);self.PressAltFireButton(0.1)");
						}
						
						g_arrPluginBot[actor].bPathing = false;
						
						return action.Continue();
					}
				}
			}
		}
	}
	
	if (m_aNestArea[actor] != NULL_AREA)
	{
		if (sentry != INVALID_ENT_REFERENCE)
		{
			if (BaseEntity_GetHealth(sentry) >= TF2Util_GetEntityMaxHealth(sentry)
			&& !TF2_IsBuilding(sentry)
			&& (TF2_IsMiniBuilding(sentry) || TF2_GetUpgradeLevel(sentry) >= 3)
			&& GetEntProp(sentry, Prop_Send, "m_iAmmoShells") > 50)
			{
				m_ctSentrySafe[actor] = GetGameTime() + 3.0;
			}
			
			m_ctSentryCooldown[actor] = GetGameTime() + 3.0;
		}
		else 
		{
			/* do not have a sentry; retreat for a few seconds if we had a
			 * sentry before this; then build a new sentry */
			if (m_ctSentryCooldown[actor] < GetGameTime()) 
			{
				m_ctSentryCooldown[actor] = GetGameTime() + 3.0;
				
				return action.SuspendFor(CTFBotMvMEngineerBuildSentrygun(), "No sentry - building a new one");
			}
		}
		
		//Don't build a dispenser if we don't have a sentry...
		if (sentry != INVALID_ENT_REFERENCE)
		{
			if (dispenser != INVALID_ENT_REFERENCE)
			{
				//sentry is not safe.
				if (m_ctSentrySafe[actor] < GetGameTime())
				{
					m_ctDispenserCooldown[actor] = GetGameTime() + 3.0;
				}
				
				//m_ctDispenserCooldown[actor] = GetGameTime() + 3.0;	
			}
			else 
			{
				/* do not have a dispenser; retreat for a few seconds if we had a
				 * dispenser before this; then build a new dispenser */
				if (m_ctDispenserCooldown[actor] < GetGameTime() && m_ctSentrySafe[actor] > GetGameTime())
				{
					m_ctDispenserCooldown[actor] = GetGameTime() + 3.0;
					
					return action.SuspendFor(CTFBotMvMEngineerBuildDispenser(), "Sentry safe, No dispenser - building one");
				}
			}
		}
	}
	
	/* The nest is standing and the wave has not started, so there is time for a teleporter
	Nothing below this point is skipped by it: the action gives up the moment the wave starts or
	the sentry stops standing, and the engineer goes straight back to the nest */
	if (m_ctSentrySafe[actor] > GetGameTime() && !g_bGoingToGrabBuilding[actor] && ShouldBuildTeleporter(actor))
		return action.SuspendFor(CTFBotMvMEngineerBuildTeleporter(), "Nest is up, building a teleporter");
	
	if (dispenser != INVALID_ENT_REFERENCE && m_ctSentrySafe[actor] > GetGameTime())
	{
		if (TF2_GetUpgradeLevel(dispenser) < 3 || BaseEntity_GetHealth(dispenser) < TF2Util_GetEntityMaxHealth(dispenser))
		{
			float dist = GetVectorDistance(GetAbsOrigin(actor), GetAbsOrigin(dispenser));
			
			if (m_ctRecomputePathMvMEngiIdle[actor] < GetGameTime()) 
			{
				m_ctRecomputePathMvMEngiIdle[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
				
				float dir[3];
				SubtractVectors(GetAbsAngles(dispenser), GetAbsOrigin(actor), dir);
				NormalizeVector(dir, dir);
				
				float goal[3]; goal = GetAbsOrigin(dispenser);
				goal[0] -= (50.0 * dir[0]);
				goal[1] -= (50.0 * dir[1]);
				goal[2] -= (50.0 * dir[2]);
				
				if (IsPathToVectorPossible(actor, goal, _))
				{
					g_arrPluginBot[actor].SetPathGoalVector(goal);
				}
				else
				{
					g_arrPluginBot[actor].SetPathGoalEntity(sentry);
				}
				
				g_arrPluginBot[actor].bPathing = true;
			}
			
			if (dist < 90.0) 
			{
				if (!myLoco.IsStuck())
				{
					g_arrExtraButtons[actor].PressButtons(IN_DUCK, 0.1);
				}
				
				EquipWeaponSlot(actor, TFWeaponSlot_Melee);
				
				UpdateLookAroundForEnemies(actor, false);
				
				AimHeadTowards(myBody, WorldSpaceCenter(dispenser), CRITICAL, 1.0, _, "Work on my Dispenser");
				VS_PressFireButton(actor);
			}
			
			return action.Continue();
		}
	}
	
	if (sentry != INVALID_ENT_REFERENCE) 
	{
		float dist = GetVectorDistance(GetAbsOrigin(actor), GetAbsOrigin(sentry));
		
		/* A finished sentry is not a job
		The wrench does nothing to a level three at full health and full shells, and the engineer
		swinging it is an engineer not shooting at the robots walking into his nest */
		if (!SentryNeedsMetal(sentry))
		{
			EquipWeaponSlot(actor, TFWeaponSlot_Primary);
			
			UpdateLookAroundForEnemies(actor, true);
		}
		else if (CanRepairFromRange(actor, sentry, dist))
		{
			//The Rescue Ranger repairs from behind cover, which is the whole reason to carry it
			EquipWeaponSlot(actor, TFWeaponSlot_Primary);
			
			AimHeadTowards(myBody, WorldSpaceCenter(sentry), CRITICAL, 1.0, _, "Repair my Sentry from here");
			
			if (myBody.IsHeadAimingOnTarget())
				VS_PressFireButton(actor);
			
			g_arrPluginBot[actor].bPathing = false;
			
			return action.Continue();
		}
		
		if (m_ctRecomputePathMvMEngiIdle[actor] < GetGameTime()) 
		{
			m_ctRecomputePathMvMEngiIdle[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
			
			float vTurretAngles[3]; GetTurretAngles(sentry, vTurretAngles);
			float dir[3];
			GetAngleVectors(vTurretAngles, dir, NULL_VECTOR, NULL_VECTOR);
			
			float goal[3]; goal = GetAbsOrigin(sentry);
			goal[0] -= (50.0 * dir[0]);
			goal[1] -= (50.0 * dir[1]);
			goal[2] -= (50.0 * dir[2]);
			
			if (IsPathToVectorPossible(actor, goal))
			{
				g_arrPluginBot[actor].SetPathGoalVector(goal);
			}
			else
			{
				g_arrPluginBot[actor].SetPathGoalEntity(sentry);
			}
			
			g_arrPluginBot[actor].bPathing = true;
		}
		
		if (dist < 90.0 && SentryNeedsMetal(sentry)) 
		{
			if (!myLoco.IsStuck())
			{
				g_arrExtraButtons[actor].PressButtons(IN_DUCK, 0.1);
			}
			
			EquipWeaponSlot(actor, TFWeaponSlot_Melee);
			
			UpdateLookAroundForEnemies(actor, false);
			
			AimHeadTowards(myBody, WorldSpaceCenter(sentry), CRITICAL, 1.0, _, "Work on my Sentry");
			VS_PressFireButton(actor);
		}
	}
	
	return action.Continue();
}

/* Whether there is anything the wrench can still do for this sentry

A mini sentry cannot be upgraded and is rebuilt rather than nursed, so for a Gunslinger this is
only ever about damage taken. Shells are counted because a sentry out of ammo is a sentry that
does nothing while it looks perfectly healthy */
bool SentryNeedsMetal(int sentry)
{
	if (TF2_IsBuilding(sentry))
		return true;
	
	if (BaseEntity_GetHealth(sentry) < TF2Util_GetEntityMaxHealth(sentry))
		return true;
	
	if (!TF2_IsMiniBuilding(sentry) && TF2_GetUpgradeLevel(sentry) < 3)
		return true;
	
	return GetEntProp(sentry, Prop_Send, "m_iAmmoShells") < 100;
}

//A Rescue Ranger bolt repairs at range, so its engineer does not walk into the open to hold a nest
bool CanRepairFromRange(int actor, int sentry, float dist)
{
	if (!TF2_IsRescueRangerEquipped(actor))
		return false;
	
	//Close enough to swing at, and the wrench repairs faster
	if (dist < 200.0)
		return false;
	
	if (dist > SENTRY_MAX_RANGE)
		return false;
	
	if (GetEntProp(actor, Prop_Data, "m_iAmmo", _, 3) < 30)
		return false;
	
	return IsLineOfFireClearEntity(actor, GetEyePosition(actor), sentry);
}

static void CTFBotMvMEngineerIdle_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	//NOTE: engineer should only truly leave this behavior when he dies, it should otherwise be impossible
	g_arrPluginBot[actor].bPathing = false;
}

static Action CTFBotMvMEngineerIdle_OnMoveToSuccess(BehaviorAction action, int actor, any path, ActionDesiredResult result)
{
	//Because of our constant pathing, we are not stuck once we arrive to our desired position
	CBaseNPC_GetNextBotOfEntity(actor).GetLocomotionInterface().ClearStuckStatus("Arrived at goal");
	
	return action.TryContinue();
}

static void CTFBotMvMEngineerIdle_ResetProperties(int actor)
{
	m_hBuildingToGrab[actor] = INVALID_ENT_REFERENCE;
	g_bGoingToGrabBuilding[actor] = false;
	
	m_ctRecomputePathMvMEngiIdle[actor] = -1.0;
	
	m_ctSentrySafe[actor] = -1.0;
	m_ctSentryCooldown[actor] = -1.0;
	
	m_ctDispenserSafe[actor] = -1.0;
	m_ctDispenserCooldown[actor] = -1.0;

	m_ctFindNestHint[actor] = -1.0;
	m_ctAdvanceNestSpot[actor] = -1.0;
	
	g_arrPluginBot[actor].bPathing = true;
}

bool CTFBotMvMEngineerIdle_ShouldAdvanceNestSpot(int actor)
{
	if (m_aNestArea[actor] == NULL_AREA)
		return false;
	
	if (m_ctAdvanceNestSpot[actor] <= 0.0)
	{
		m_ctAdvanceNestSpot[actor] = GetGameTime() + 5.0;
		return false;
	}
	
	int obj = GetObjectOfType(actor, TFObject_Sentry);
	
	if (obj != INVALID_ENT_REFERENCE && BaseEntity_GetHealth(obj) < TF2Util_GetEntityMaxHealth(obj))
	{
		m_ctAdvanceNestSpot[actor] = GetGameTime() + 5.0;
		return false;
	}
	
	//IsElapsed
	if (GetGameTime() > m_ctAdvanceNestSpot[actor])
	{
		m_ctAdvanceNestSpot[actor] = -1.0;
	}
	
	BombInfo_t bombinfo;
	
	if (!GetBombInfo(bombinfo)) 
	{
		return false;
	}
	
	float m_flBombTargetDistance = GetTravelDistanceToBombTarget(m_aNestArea[actor]);
	
	//No point in advancing now.
	if (m_flBombTargetDistance <= 1000.0)
	{
		return false;
	}
	
	bool bigger = (m_flBombTargetDistance > bombinfo.flMaxBattleFront);
	
	//PrintToServer("m_flBombTargetDistance %f > bombinfo.hatch_dist_back %f = %s", m_flBombTargetDistance, bombinfo.GetFloat("hatch_dist_back"), bigger ? "Yes" : "No");
	
	return bigger;
}