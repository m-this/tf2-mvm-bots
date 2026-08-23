/* What each medic is doing, which is all that is left of this file

It used to hold CTFBotDefenderMedicHeal: an action that took the walking, the aim and the button
away from the game's own medic behaviour so the mod could choose the patient itself. Choosing the
patient was the point and the walking was the price, and the price turned out to be the whole
medic.

The mod walked by setting a goal on esPluginBot and trusting PluginBot_SimulateFrame. A refused
path computation leaves the path object holding the last one that worked, so the failure reads as a
healthy path from every angle, and the bot falls through to NudgeTowardsGoal and its 120 unit steps.
Measured on Decoy: the medic reported a path 10400 units long, constant to within fifty units over
eighty seconds, while his nearest teammate stood four hundred units away. He was not walking. He was
being nudged, and he never arrived.

Against the game's own behaviour, on Coaltown:

  beam connected            5-17%   ->  61% of samples
  movement between samples  0-70    -> 337 units
  path computations failed  most    ->   0, it does not use ours

So the action is gone and the game does the healing again. The mod keeps the parts that were
actually improvements and do not touch locomotion: the uber and resistance handling, the revive,
and holding the hatch instead of fetching the bomb when there is nobody to heal. All of those live
in CTFBotMedicHeal_UpdatePost.

What went with it is the patient ranking, which is a real loss: the game picks whoever it likes and
the mod picked the biggest body. Getting that back means changing the game's mind about its patient
rather than replacing it, and the last attempt at that wrote into the action's own field and
segfaulted the server. It is worth another try; it is not worth this. */

/* Where each medic is, who he is beaming and how far that is from the bomb

The bomb is the fight: a medic a little behind his patient is a medic doing his job, and one much
further from the bomb than the man he is healing has stopped following anybody.

Who he is beaming is read off the medigun rather than asked of the mod, because the mod no longer
has an opinion and the medigun is the only thing that knows. */
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

		char stack[512]; ActionStackOf(i, stack, sizeof(stack));

		int medigun = GetPlayerWeaponSlot(i, TFWeaponSlot_Secondary);
		int patient = -1;

		if (medigun != -1 && HasEntProp(medigun, Prop_Send, "m_hHealingTarget"))
			patient = GetEntPropEnt(medigun, Prop_Send, "m_hHealingTarget");

		if (patient <= 0 || patient > MaxClients || !IsClientInGame(patient))
		{
			ReplyToCommand(client, "%N: beam on nobody, %.0f from the bomb, %s", i, fromBomb, stack);

			continue;
		}

		float theirs[3]; theirs = GetAbsOrigin(patient);

		ReplyToCommand(client, "%N: healing %N, %.0f behind him, %.0f from the bomb, he is %.0f from it, %s",
			i, patient, GetVectorDistance(mine, theirs), fromBomb,
			haveBomb ? GetVectorDistance(theirs, bomb.vPosition) : -1.0, stack);
	}

	return Plugin_Handled;
}
