/* Does a sale come back when the money did not come from the game?
 *
 * tf2-archipelago hands out Cash Bundles by writing m_nCurrency straight onto a
 * player, because the currency pack the game itself uses cannot be told what it
 * is worth on this server. That money is real on the screen and absent from the
 * game's own record of the wave. Two play-test reports look like they come from
 * that gap: a refund that hands back the standard 400 after 1200 was spent, and
 * an upgrade that stays bought when it is sold again.
 *
 * The second one is the question here, and it did not need a play session. A
 * defender bot buys through FakeClientCommandKeyValues("MVM_Upgrade"), which is
 * the same command the upgrade station sends for a human, so a bot is a fair
 * subject. This drives one: buy an upgrade, sell it back, and write down whether
 * the credits returned. Once with money the game handed out, once with money
 * written on top of it the way a bundle is.
 *
 * If only the second fails, the sale is not a Valve bug and fixing the bundle
 * accounting fixes both. If both fail, the bundle is innocent. Either answer is
 * worth more than another evening of somebody playing.
 *
 * A test-bed plugin. It writes to the game on purpose, which is why it is not
 * in the statistics plugin, and it belongs on a test server and nowhere else.
 */

#include <sourcemod>
#include <tf2_stocks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "MvM Defender Bots: refund probe",
	author = "m-this",
	description = "Buys and sells an upgrade on a bot, with and without money the game never recorded",
	version = "1.0.0",
	url = "https://github.com/m-this/tf2-mvm-bots"
};

/* How many upgrade indexes to offer before giving up on a class
 *
 * The probe does not know which upgrades this bot's class and weapon accept, and asking the item
 * schema for that is a much larger plugin. So it offers them in order and watches the credits: the
 * game turns down one it does not want by not charging for it, which is the same test the mod's own
 * purchase path makes. The cap is here because every loop needs one, not because 40 is meaningful.
 */
#define PROBE_UPGRADE_LIMIT	40

//Weapon slots to try, in the order the station lists them. -1 is the player, which is where resistances live.
static const int ProbeSlots[] = {-1, 0, 1, 2};

public void OnPluginStart()
{
	RegServerCmd("mvmbots_refund_probe", Command_Probe,
		"Buy and sell an upgrade. Arguments: credits to write on first (0 for none), then host or bot.");
}

/* The bot to experiment on
 *
 * A fake client on RED that is alive and has a class. The test-bed's own host is a fake client on
 * RED too and it is a statue with no money and no loadout, so it is skipped by name rather than by
 * guessing from its state.
 */
/* The test-bed host, which is the only body on this server holding money the game itself issued
 *
 * Every credit a defender bot has was written onto m_nCurrency from outside: the mod pays them with
 * TF2_SetCurrency, which is SetEntProp on that same property, which is what tf2-archipelago does for
 * a Cash Bundle. So a bot cannot be the control leg of this experiment. There is no game-recorded
 * money on one to compare against.
 *
 * The host joined the way a player joins and the game handed it the mission's starting currency. It
 * is a statue with no AI, which is a problem solved below rather than here.
 */
static int ProbeHost()
{
	char host[MAX_NAME_LENGTH];
	ConVar hostName = FindConVar("mvmbots_host_name");
	if (hostName != null)
		hostName.GetString(host, sizeof(host));
	if (host[0] == '\0')
		return -1;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;
		char name[MAX_NAME_LENGTH]; GetClientName(client, name, sizeof(name));
		if (StrEqual(name, host))
			return client;
	}
	return -1;
}

/* Standing in the upgrade station, because the game checks
 *
 * MvM refuses a purchase from somebody who is not inside a func_upgradestation, and the host never
 * walks anywhere. That is why it accepted nothing at 400 credits on the first run: not a refusal
 * worth reporting, just a body in the wrong place.
 *
 * The position is put back afterwards. A probe that leaves the host somewhere else has changed the
 * run it was measuring.
 */
static bool MoveToStation(int client, float back[3])
{
	int station = FindEntityByClassname(-1, "func_upgradestation");
	if (station == -1)
		return false;

	float centre[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", back);
	GetEntPropVector(station, Prop_Send, "m_vecOrigin", centre);
	TeleportEntity(client, centre, NULL_VECTOR, NULL_VECTOR);
	return true;
}

static int ProbeSubject()
{
	/* Looked up here rather than at plugin start, because at plugin start it does not exist yet.
	 * SourceMod loads plugins in directory order, this one sorts before mvmbots_host, and a
	 * FindConVar for a convar the host plugin has not created returns null. That null read as
	 * "no host to skip", so the probe cheerfully experimented on the statue: 400 credits, no
	 * loadout, and nothing it was offered was ever going to be accepted. */
	char host[MAX_NAME_LENGTH];
	ConVar hostName = FindConVar("mvmbots_host_name");
	if (hostName != null)
		hostName.GetString(host, sizeof(host));

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsFakeClient(client))
			continue;
		if (GetClientTeam(client) != view_as<int>(TFTeam_Red) || !IsPlayerAlive(client))
			continue;
		if (TF2_GetPlayerClass(client) == TFClass_Unknown)
			continue;

		char name[MAX_NAME_LENGTH]; GetClientName(client, name, sizeof(name));
		if (host[0] != '\0' && StrEqual(name, host))
			continue;

		return client;
	}
	return -1;
}

static int Credits(int client)
{
	return HasEntProp(client, Prop_Send, "m_nCurrency")
		? GetEntProp(client, Prop_Send, "m_nCurrency")
		: -1;
}

//The station's own command, which is how a bot buys and how a human buys. A negative count sells.
static void SendUpgrade(int client, int slot, int index, int count)
{
	KeyValues kv = new KeyValues("MVM_Upgrade");
	kv.JumpToKey("upgrade", true);
	kv.SetNum("itemslot", slot);
	kv.SetNum("upgrade", index);
	kv.SetNum("count", count);
	FakeClientCommandKeyValues(client, kv);
	delete kv;
}

/* An upgrade this bot will actually buy, bought
 *
 * Returns what it cost, 0 when nothing was accepted. The slot and index that worked are written
 * back so the sale can name the same one: selling a different upgrade would answer a different
 * question.
 */
static int BuyAnything(int client, int &slotOut, int &indexOut)
{
	for (int s = 0; s < sizeof(ProbeSlots); s++)
	{
		for (int index = 0; index < PROBE_UPGRADE_LIMIT; index++)
		{
			int before = Credits(client);
			SendUpgrade(client, ProbeSlots[s], index, 1);
			int spent = before - Credits(client);
			if (spent > 0)
			{
				slotOut = ProbeSlots[s];
				indexOut = index;
				return spent;
			}
		}
	}
	return 0;
}

public Action Command_Probe(int argc)
{
	if (GameRules_GetRoundState() != RoundState_BetweenRounds)
	{
		PrintToServer("[refund-probe] not between waves, so the upgrade station is shut. Nothing done.");
		return Plugin_Handled;
	}

	char who[16] = "bot";
	if (argc >= 2)
		GetCmdArg(2, who, sizeof(who));

	bool onHost = StrEqual(who, "host", false);
	int client = onHost ? ProbeHost() : ProbeSubject();
	if (client == -1)
	{
		PrintToServer("[refund-probe] no %s alive to experiment on. Nothing done.", onHost ? "host" : "defender bot");
		return Plugin_Handled;
	}

	float back[3];
	bool moved = MoveToStation(client, back);
	if (!moved)
		PrintToServer("[refund-probe] no func_upgradestation on this map, so a refusal here means nothing.");
	if (Credits(client) == -1)
	{
		PrintToServer("[refund-probe] this server has no m_nCurrency. Nothing done.");
		return Plugin_Handled;
	}

	int bundle = 0;
	if (argc >= 1)
	{
		char arg[16]; GetCmdArg(1, arg, sizeof(arg));
		bundle = StringToInt(arg);
	}

	int started = Credits(client);
	// The bundle, written exactly the way tf2-archipelago writes one: on top of the balance, with
	// the game's record of the wave left saying what it said before.
	if (bundle > 0)
		SetEntProp(client, Prop_Send, "m_nCurrency", started + bundle);
	int held = Credits(client);

	int slot = 0, index = 0;
	int spent = BuyAnything(client, slot, index);
	if (spent <= 0)
	{
		if (moved)
			TeleportEntity(client, back, NULL_VECTOR, NULL_VECTOR);
		PrintToServer("[refund-probe] %N bought nothing: %d credits and no upgrade accepted. Nothing to sell.",
			client, held);
		return Plugin_Handled;
	}

	int afterBuy = Credits(client);
	SendUpgrade(client, slot, index, -1);
	int afterSell = Credits(client);
	int returned = afterSell - afterBuy;

	if (moved)
		TeleportEntity(client, back, NULL_VECTOR, NULL_VECTOR);

	// One line, the same shape as the statistics plugin's, so two probes diff against each other.
	PrintToServer("[refund-probe] {\"subject\":\"%s\",\"bundle\":%d,\"started\":%d,\"held\":%d,\"slot\":%d,\"upgrade\":%d,\"spent\":%d,\"after_buy\":%d,\"after_sell\":%d,\"returned\":%d,\"sale_took\":%s}",
		onHost ? "host" : "bot", bundle, started, held, slot, index, spent, afterBuy, afterSell, returned,
		returned == spent ? "true" : "false");

	if (returned == spent)
		PrintToServer("[refund-probe] the sale came back in full.");
	else if (returned == 0)
		PrintToServer("[refund-probe] the sale returned nothing: the upgrade stayed bought and the credits stayed spent.");
	else
		PrintToServer("[refund-probe] the sale returned %d of %d, which is neither answer and wants looking at.", returned, spent);

	return Plugin_Handled;
}
