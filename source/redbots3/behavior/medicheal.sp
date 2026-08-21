/* The medic heals the patient this mod picked, rather than the one the game picked

PreferredPatient works out who the beam belongs on and nothing acted on it, because acting on it
meant writing the patient into a field inside one of the game's own actions and that segfaulted
the server. So the mod stops trying to change the game's mind and does the healing itself: this
action owns the walking, the aim and the button for as long as there is somebody worth healing.

What it does not own is the charge, the revive and the resistance switching. Those were written
against the game's heal action and they are called from here unchanged, because suspending that
action means its own update no longer runs.

The patient is the biggest body in range, which names the Heavy without a class table and follows
the health the team buys. He is re-asked every couple of seconds and only changes for somebody
clearly worse off, since a beam that picks again every frame heals nobody. */

//Inside the medigun's reach with room to spare, so a step either way does not break the beam
#define MEDIC_HEAL_FOLLOW_RANGE	250.0

//Chest height, because a beam aimed at a man's feet is a beam aimed at the floor behind him
#define MEDIC_HEAL_AIM_HEIGHT	45.0

//A beam that picks again every frame heals nobody, so the question is asked on a clock
#define MEDIC_HEAL_ASK_INTERVAL	2.0

static int m_iMedicPatient[MAXPLAYERS + 1];
static float m_ctMedicPatientCheck[MAXPLAYERS + 1];

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
	m_iMedicPatient[actor] = -1;
	m_ctMedicPatientCheck[actor] = 0.0;
	
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
	
	int patient = MedicPatient(actor);
	
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
	
	m_iMedicPatient[actor] = -1;
}

//Who the beam is on, re-asked on the interval and only moved for a clearly better patient
static int MedicPatient(int actor)
{
	int held = m_iMedicPatient[actor];
	
	if (held > 0 && (!IsClientInGame(held) || !IsPlayerAlive(held)))
		held = -1;
	
	if (m_ctMedicPatientCheck[actor] > GetGameTime())
		return held;
	
	m_ctMedicPatientCheck[actor] = GetGameTime() + MEDIC_HEAL_ASK_INTERVAL;
	
	int wanted = PreferredPatient(actor);
	
	if (wanted > 0 && IsBetterPatient(wanted, held))
		held = wanted;
	
	m_iMedicPatient[actor] = held;
	
	return held;
}
