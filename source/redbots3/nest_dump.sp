/* The nest dump command, which the generator cannot write yet

The rest of engineeridle.sp is generated from internal/action/engineeridle. This is what did not
come with it: it formats into buffers it declares and prints them, and one of those buffers is
handed to EngineerTeleporter_LastResult, which takes the length from its caller. A generated
function fills a buffer with the size of its own declaration and has no way to name a caller's.

mvm-z83 carries the gap. When it closes this goes away.

The comments below are the ones the original carried. */

/* What each engineer has actually got standing, and where

An engineer who never finishes a building looks the same from outside as one who never started,
and a teleporter half of a pair looks the same as none. This says which, and where each piece
ended up, so a spot that refuses everything can be walked to with sm_dump_spot. */
public Action Command_DumpNest(int client, int args)
{
	/* How many areas a nest decision walks, which is the size of everything else here

	PickBuildArea and GetBombInfo both walk the whole mesh, so this number is the unit that any
	"why did the frame take that long" answer is counted in. */
	ReplyToCommand(client, "%d nav areas on this map", TheNavAreas.Count);

	/* Every building standing, and who the game says owns it

	Asked for because a play-test found two dispensers with one engineer on the team, which is a
	thing the game does not let a player do: an engineer placing a second one has his first taken
	down for him. So one of them belongs to somebody else, or to nobody, and the per-engineer
	listing below cannot show either. This walks the entities instead of the players. */
	int building = -1;
	int standing = 0;

	while ((building = FindEntityByClassname(building, "obj_*")) != -1)
	{
		char class[64]; GetEntityClassname(building, class, sizeof(class));

		int owner = GetEntPropEnt(building, Prop_Send, "m_hBuilder");
		float at[3]; at = GetAbsOrigin(building);

		char whose[64];
		
		if (owner > 0 && owner <= MaxClients && IsClientInGame(owner))
			Format(whose, sizeof(whose), "%N", owner);
		else
			Format(whose, sizeof(whose), "nobody (orphan, owner index %d)", owner);
		
		ReplyToCommand(client, "%s #%d at %.0f %.0f %.0f, built by %s", class, building, at[0], at[1], at[2], whose);

		standing++;
	}

	ReplyToCommand(client, "%d buildings standing", standing);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || TF2_GetPlayerClass(i) != TFClass_Engineer)
			continue;

		float nest[3]; NestBuildPosition(m_aNestArea[i], nest);

		ReplyToCommand(client, "%N: nest %.0f %.0f %.0f", i, nest[0], nest[1], nest[2]);

		DumpBuilding(client, "sentry", GetObjectOfType(i, TFObject_Sentry));
		DumpBuilding(client, "dispenser", GetObjectOfType(i, TFObject_Dispenser));
		DumpBuilding(client, "entrance", GetObjectOfType(i, TFObject_Teleporter, TFObjectMode_Entrance));
		DumpBuilding(client, "exit", GetObjectOfType(i, TFObject_Teleporter, TFObjectMode_Exit));

		//Asking moves the engineer's pending teleporter target, which the idle action recomputes anyway
		bool wants = ShouldBuildTeleporter(i);

		char lastResult[64]; EngineerTeleporter_LastResult(i, lastResult, sizeof(lastResult));

		ReplyToCommand(client, "  teleporter: round %d, sentry safe %s, gave up %s, wants %s%s, last \"%s\"",
			GameRules_GetRoundState(),
			m_ctSentrySafe[i] > GetGameTime() ? "yes" : "no",
			EngineerTeleporter_HasGivenUp(i) ? "yes" : "no",
			wants ? "yes" : "no",
			ActionsManager.LookupEntityActionByName(i, "DefenderBuildTeleporter") != INVALID_ACTION ? ", building one now" : "",
			lastResult);

		if (wants)
		{
			float spot[3]; EngineerTeleporter_Spot(i, spot);

			ReplyToCommand(client, "  teleporter target: mode %d at %.0f %.0f %.0f",
				EngineerTeleporter_Mode(i), spot[0], spot[1], spot[2]);
		}
	}

	return Plugin_Handled;
}

static void DumpBuilding(int client, const char[] what, int building)
{
	if (building == INVALID_ENT_REFERENCE)
	{
		ReplyToCommand(client, "  %s: none", what);

		return;
	}

	float origin[3]; origin = GetAbsOrigin(building);

	ReplyToCommand(client, "  %s: level %d, %d of %d health, at %.0f %.0f %.0f%s",
		what, TF2_GetUpgradeLevel(building), BaseEntity_GetHealth(building),
		TF2Util_GetEntityMaxHealth(building), origin[0], origin[1], origin[2],
		TF2_IsBuilding(building) ? ", still going up" : "");
}
