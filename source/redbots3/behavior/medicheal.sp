/* The medic heals the patient this mod picked, rather than the one the game picked

PreferredPatient works out who the beam belongs on and nothing acted on it, because acting on it
meant writing the patient into a field inside one of the game's own actions and that segfaulted
the server. So the mod stops trying to change the game's mind and does the healing itself: this
action owns the walking, the aim and the button for as long as there is somebody worth healing.

What it does not own is the charge, the revive and the resistance switching. Those were written
against the game's heal action and they are called from here unchanged, because suspending that
action means its own update no longer runs.

Who the patient is comes from PreferredPatient and nowhere else, so the answer that decides
whether this action runs is the same answer that decides where the beam goes. Asking it twice, in
two places, on two clocks, is two answers that disagree and a medic who walks to one man and heals
another. */

//Inside the medigun's reach with room to spare, so a step either way does not break the beam
#define MEDIC_HEAL_FOLLOW_RANGE	250.0

//Chest height, because a beam aimed at a man's feet is a beam aimed at the floor behind him
#define MEDIC_HEAL_AIM_HEIGHT	45.0

BehaviorAction CTFBotDefenderMedicHeal()
{
	BehaviorAction action = ActionsManager.Create("DefenderMedicHeal");
	
	action.OnStart = CTFBotDefenderMedicHeal_OnStart;
	action.Update = CTFBotDefenderMedicHeal_Update;
	action.OnEnd = CTFBotDefenderMedicHeal_OnEnd;
	
	return action;
}

public Action CTFBotDefenderMedicHeal_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	return action.Continue();
}

public Action CTFBotDefenderMedicHeal_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	int medigun = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
	
	if (medigun == -1 || TF2Util_GetWeaponID(medigun) != TF_WEAPON_MEDIGUN)
		return action.Done("No medigun");
	
	//Both of these belong to the game's heal action, whose update does not run while this one does
	if (CTFBotAttackUber_IsPossible(actor, medigun))
		return action.SuspendFor(CTFBotAttackUber(), "Seek uber");
	
	if (CTFBotMedicRevive_IsPossible(actor))
		return action.SuspendFor(CTFBotMedicRevive(), "Revive teammate");
	
	int patient = PreferredPatient(actor);
	
	if (patient <= 0)
		return action.Done("Nobody to heal");
	
	//The beam is only his while the medigun is in his hands
	EquipWeaponSlot(actor, TFWeaponSlot_Secondary);
	
	float theirOrigin[3]; GetClientAbsOrigin(patient, theirOrigin);
	
	if (GetVectorDistance(GetAbsOrigin(actor), theirOrigin) > MEDIC_HEAL_FOLLOW_RANGE)
	{
		g_arrPluginBot[actor].SetPathGoalEntity(patient);
		g_arrPluginBot[actor].bPathing = true;
	}
	else
	{
		g_arrPluginBot[actor].bPathing = false;
	}
	
	theirOrigin[2] += MEDIC_HEAL_AIM_HEIGHT;
	
	/* The beam follows the eyes, not the action
	
	The medigun traces from where the medic is looking when the button is held, which is why this
	works at all without touching the field that crashed: look at the man and hold fire. */
	INextBot myNextbot = CBaseNPC_GetNextBotOfEntity(actor);
	IBody myBody = myNextbot.GetBodyInterface();
	
	AimHeadTowards(myBody, theirOrigin, MANDATORY, 0.3, _, "Healing the biggest body");
	
	VS_PressFireButton(actor);
	
	MedicUberAndResist(actor, medigun, GetEntPropEnt(medigun, Prop_Send, "m_hHealingTarget"));
	
	return action.Continue();
}

public void CTFBotDefenderMedicHeal_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	g_arrPluginBot[actor].bPathing = false;
}
