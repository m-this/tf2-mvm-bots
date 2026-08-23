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
	
	//His own shopping is the one thing that comes before healing
	if (GameRules_GetRoundState() == RoundState_BetweenRounds && !g_bShoppedThisBreak[actor])
		return action.Done("Shopping comes first");
	
	int patient = PreferredPatient(actor);
	
	if (patient <= 0)
		return action.Done("Nobody to heal");
	
	//The beam is only his while the medigun is in his hands
	EquipWeaponSlot(actor, TFWeaponSlot_Secondary);
	
	float theirOrigin[3]; GetClientAbsOrigin(patient, theirOrigin);
	
	/* He follows whoever he is beaming, wherever that is, and three attempts to qualify that lost
	
	The medic spending a wave in the respawn room beside a man who has just come back is real and
	was measured. Three ways of stopping it were tried over thirty six waves:
	
	  excluding him as a patient      healing 13566 -> 10592, and more time in the spawn, not less
	  ranking him last as a patient   healing  9089 ->  6901, time on target 43% -> 15%
	  not walking in there after him  time on target 46% -> 26%, healing unchanged
	
	The first two end the heal action, which hands the bot to the game's own medic code. The third
	keeps the action and takes away the walk, and a medic who does not walk does not close, so the
	beam that was going to connect never does.
	
	And the number that matters barely moved: 11159 against 11312. The wave he spends in the spawn
	costs less than any of the cures. */
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

/* Where each medic is, who he is beaming and how far that is from the bomb

The complaint this answers is that he stands somewhere the wave is not, and where a bot stands is
not something an opinion should decide. The bomb is the fight: a medic a little behind his patient
is a medic doing his job, and one much further from the bomb than the man he is healing has
stopped following anybody. */
public Action Command_DumpMedic(int client, int args)
{
	BombInfo_t bomb;
	bool haveBomb = GetBombInfo(bomb);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || TF2_GetPlayerClass(i) != TFClass_Medic)
			continue;

		float mine[3]; mine = GetAbsOrigin(i);
		float fromBomb = haveBomb ? GetVectorDistance(mine, bomb.vPosition) : -1.0;

		int patient = PreferredPatient(i);

		char stack[512]; ActionStackOf(i, stack, sizeof(stack));

		if (patient <= 0)
		{
			ReplyToCommand(client, "%N: nobody to heal, %.0f from the bomb, %s", i, fromBomb, stack);

			continue;
		}

		float theirs[3]; theirs = GetAbsOrigin(patient);

		/* The path itself, because "he is not moving" and "he has nowhere to walk" look the same
		
		A medic parked in the middle of Coaltown for thirty five seconds with a patient two
		thousand units away is either refusing to walk or being told there is no way there, and
		nothing printed so far could tell those apart. */
		float pathLength = m_pPath[i].GetLength();
		
		ReplyToCommand(client, "%N: healing %N, %.0f behind him, %.0f from the bomb, he is %.0f from it, %s, path %.0f long, %s",
			i, patient, GetVectorDistance(mine, theirs), fromBomb,
			haveBomb ? GetVectorDistance(theirs, bomb.vPosition) : -1.0,
			g_arrPluginBot[i].bPathing ? "walking" : "stood still", pathLength, stack);
	}

	return Plugin_Handled;
}

public void CTFBotDefenderMedicHeal_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	g_arrPluginBot[actor].bPathing = false;
}
