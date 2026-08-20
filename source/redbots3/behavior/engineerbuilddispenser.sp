#define DISPENSER_SPOT_TAKEN_RANGE	150.0

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
	
	float areaCenter[3];
	
	if (!ConfiguredDispenserSpot(actor, areaCenter))
		CNavArea_GetRandomPoint(m_aNestArea[actor], areaCenter);
	
	float range_to_hint = GetVectorDistance(GetAbsOrigin(actor), areaCenter);
	
	if (range_to_hint < 200.0) 
	{
		//Start building a dispenser
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, "build 0");
		
		//Look in "random" directions in an attempt to find a place to fit a dispenser.
		g_arrExtraButtons[actor].PressButtons(IN_RIGHT, 0.1);
		g_arrExtraButtons[actor].flKeySpeed = 5.0;
		
	//	if(g_flNextLookTime[actor] > GetGameTime())
	//		return false;
		
	//	g_flNextLookTime[actor] = GetGameTime() + GetRandomFloat(0.3, 1.0);
		
		//NOTE: we do not look around for incoming enemies cause all we care about is finding somewhere to place this dispenser
		
		//BotAim(actor).AimHeadTowards(areaCenter, OVERRIDE_ALL, 0.1, "Placing sentry");
	}
	
	if (range_to_hint > 70.0)
	{
		//PrintToServer("%f %f %f", areaCenter[0], areaCenter[1], areaCenter[2]);
		
		g_arrPluginBot[actor].SetPathGoalVector(areaCenter);
		g_arrPluginBot[actor].bPathing = true;
		
		//if(range_to_hint > 300.0)
		//{
			//Fuck em up.
			//EquipWeaponSlot(actor, TFWeaponSlot_Melee);
		//}
		
		return action.Continue();
	}
	
	g_arrPluginBot[actor].bPathing = false;
	
	VS_PressFireButton(actor);
	
	int sentry = GetObjectOfType(actor, TFObject_Dispenser);
	
	if (sentry == INVALID_ENT_REFERENCE)
		return action.Continue();
	
	SetPlayerReady(actor, true);
	
	return action.Done("Built a dispenser");
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
	
	ArrayList free = new ArrayList(3);
	
	for (int i = 0; i < spots.Length; i++)
	{
		float candidate[3]; spots.GetArray(i, candidate);
		
		if (!IsDispenserSpotTaken(actor, candidate))
			free.PushArray(candidate);
	}
	
	float nest[3]; m_aNestArea[actor].GetCenter(nest);
	
	bool found = NearestConfiguredSpot(free, nest, spot);
	
	delete free;
	
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
