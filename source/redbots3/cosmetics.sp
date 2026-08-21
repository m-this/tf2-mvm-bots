/* Hats and unusual effects on the defender bots, for the look of the thing

None of this changes how a bot plays. What the team looks like now is six bare-headed mercenaries
with the same three weapons, and a run built out of a randomiser is more fun to watch when they
look like six strangers who met on the way in.

Both pools come from the game's own item schema through tf_econ_data, never from a table of
numbers in this file. A table of item definition indexes is a guess that goes stale on the next
update, and the schema is what the client renders from anyway. Each pool costs one walk of the
schema, once, and is then kept.

Attribute 134 attaches the particle, read out of scripts/items/items_game.txt rather than copied
from a forum post.

War paints on the weapons were here too and are gone: they are attributes on the entity the
upgrade station rewrites all wave, and they were not worth one more thing to blame a crash on.

Defender bots only, and never the invading robots: a wave is read by silhouette, and a robot in a
hat is a robot somebody shoots a moment later than they should. */

//The quality a client expects on an item before it will draw an effect on it
#define TF_QUALITY_UNIQUE		6
#define TF_QUALITY_UNUSUAL		5

#define ATTRIB_ATTACH_PARTICLE	134

//One pool per class, because a hat one class can wear another cannot. Index 0 is TFClass_Unknown
static ArrayList g_adtHats[view_as<int>(TFClass_Engineer) + 1];
static ArrayList g_adtHatEffects;

/* What one bot wears, drawn once and worn for the rest of the mission

Drawn once and not per life, because the hat is how a player tells one bot from another. A team
of six that comes back from the respawn room in six new hats is a team nobody can follow, and
following them is most of what there is to do while they play.

The class is part of it: a bot that changes class between waves cannot wear what it drew, so it
draws again. */
enum struct Wardrobe
{
	bool drawn;
	TFClassType playerClass;
	int hatItem;
	int hatEffect;
}

static Wardrobe g_wardrobe[MAXPLAYERS + 1];

//The hat entity itself, which the game destroys on every respawn and this puts back
static int g_iBotHat[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};

//Whether a bot is already waiting to be dressed, so it is dressed once
static bool g_bCosmeticsPending[MAXPLAYERS + 1];

/* The item a bot is in the middle of putting on, and nothing the rest of the time

Equipping throws when the game refuses an item, and a thrown native takes the callback with it,
so there is no line after the call that can notice. What is left behind is this: an item still
written here on the next spawn is an item the game would not attach, and it comes out of the
pool rather than being drawn again for the rest of the map. */
static int g_iEquipping[MAXPLAYERS + 1];

/* Half a second after the bot spawns, not the moment it does

The game gives its own items on spawn, and the custom loadout replaces them a tenth of a second
later, and a hat handed to a bot in the middle of that is a hat the game throws away.

Once per spawn, however many times it is asked. A bot's first spawn asks twice: the spawn that
identifies it as ours, and the respawn that applies its loadout, which is close enough behind to
be the same moment. Without the flag that is a hat created, worn and taken off again for every
bot at the start of every wave. */
void GiveBotCosmeticsSoon(int client)
{
	if (!redbots_manager_bot_hats.BoolValue)
		return;
	
	if (g_bCosmeticsPending[client])
		return;
	
	g_bCosmeticsPending[client] = true;
	
	CreateTimer(0.5, Timer_GiveBotCosmetics, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

static Action Timer_GiveBotCosmetics(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (client < 1)
		return Plugin_Stop;
	
	g_bCosmeticsPending[client] = false;
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || !g_bIsDefenderBot[client])
		return Plugin_Stop;
	
	DrawWardrobe(client);
	
	if (redbots_manager_bot_hats.BoolValue)
		WearHat(client);
	
	return Plugin_Stop;
}

//What this bot is going to wear for the rest of the mission, drawn once
static void DrawWardrobe(int client)
{
	TFClassType playerClass = TF2_GetPlayerClass(client);
	
	if (g_iEquipping[client] != 0)
	{
		DropHatFromPool(g_wardrobe[client].playerClass, g_iEquipping[client]);
		g_iEquipping[client] = 0;
		g_wardrobe[client].drawn = false;
	}
	
	if (g_wardrobe[client].drawn && g_wardrobe[client].playerClass == playerClass)
		return;
	
	ArrayList hats = HatPoolForClass(playerClass);
	
	g_wardrobe[client].drawn = true;
	g_wardrobe[client].playerClass = playerClass;
	g_wardrobe[client].hatItem = hats != null && hats.Length > 0 ? hats.Get(GetRandomInt(0, hats.Length - 1)) : 0;
	g_wardrobe[client].hatEffect = redbots_manager_bot_hat_effects.BoolValue ? RandomHatEffect() : 0;
	
	if (redbots_manager_debug.BoolValue)
		LogMessage("[DrawWardrobe] %N drew item %d with effect %d", client, g_wardrobe[client].hatItem, g_wardrobe[client].hatEffect);
}

/* Put the drawn hat back on

The game clears a player's wearables every time it gives it its items, which is every respawn, so
the same hat has to be handed back rather than merely remembered. */
static void WearHat(int client)
{
	RemoveBotHat(client);
	
	int itemDefinition = g_wardrobe[client].hatItem;
	int effect = g_wardrobe[client].hatEffect;
	
	if (itemDefinition < 1)
		return;
	
	int hat = CreateEntityByName("tf_wearable");
	
	if (hat == -1)
		return;
	
	SetEntProp(hat, Prop_Send, "m_iItemDefinitionIndex", itemDefinition);
	SetEntProp(hat, Prop_Send, "m_bInitialized", 1);
	SetEntProp(hat, Prop_Send, "m_iEntityQuality", effect > 0 ? TF_QUALITY_UNUSUAL : TF_QUALITY_UNIQUE);
	SetEntProp(hat, Prop_Send, "m_iEntityLevel", 1);
	SetEntProp(hat, Prop_Send, "m_iTeamNum", GetClientTeam(client));
	
	DispatchSpawn(hat);
	
	if (effect > 0)
		TF2Attrib_SetByDefIndex(hat, ATTRIB_ATTACH_PARTICLE, float(effect));
	
	//The game throws out a wearable whose item it thinks the wearer does not own, and a bot owns nothing
	TF2Util_SetWearableAlwaysValid(hat, true);
	
	/* Written down before the equip and not after, both of them
	
	The entity so that a refused one is taken away on the next spawn rather than standing in the
	world with nobody wearing it, and the item so that the refusal is noticed at all. */
	g_iBotHat[client] = EntIndexToEntRef(hat);
	g_iEquipping[client] = itemDefinition;
	
	TF2Util_EquipPlayerWearable(client, hat);
	
	g_iEquipping[client] = 0;
	
	if (redbots_manager_debug.BoolValue)
		LogMessage("[WearHat] %N puts item %d back on", client, itemDefinition);
}

/* Take the hat off the way the game does it

Deleting the entity is not the same thing. The player holds a handle to every wearable it is
wearing, and an entity removed out from under that list leaves the game following a pointer to
something that is not there any more. */
static void RemoveBotHat(int client)
{
	int hat = EntRefToEntIndex(g_iBotHat[client]);
	
	g_iBotHat[client] = INVALID_ENT_REFERENCE;
	
	if (hat != INVALID_ENT_REFERENCE && IsClientInGame(client))
		TF2_RemoveWearable(client, hat);
}

//An item the game will not attach, gone for the rest of the map so nobody draws it twice
static void DropHatFromPool(TFClassType playerClass, int itemDefinition)
{
	ArrayList pool = HatPoolForClass(playerClass);
	
	if (pool == null)
		return;
	
	int at = pool.FindValue(itemDefinition);
	
	if (at != -1)
		pool.Erase(at);
	
	LogMessage("Item %d cannot be worn by class %d and has been dropped from the hat pool", itemDefinition, playerClass);
}

/* A bot that has left takes its hat with it

Nothing to remove, then: the game clears a player's wearables when the player goes, and a
reference to an entity that is gone reads as no entity. Only what is remembered here is left. */
void ForgetBotCosmetics(int client)
{
	g_iBotHat[client] = INVALID_ENT_REFERENCE;
	g_bCosmeticsPending[client] = false;
	g_iEquipping[client] = 0;
	
	//The next bot in this seat is a different bot, and dresses itself
	g_wardrobe[client].drawn = false;
}

static int RandomHatEffect()
{
	if (g_adtHatEffects == null)
		g_adtHatEffects = TF2Econ_GetParticleAttributeList(ParticleSet_CosmeticUnusualEffects);
	
	if (g_adtHatEffects == null || g_adtHatEffects.Length < 1)
		return 0;
	
	return g_adtHatEffects.Get(GetRandomInt(0, g_adtHatEffects.Length - 1));
}

static ArrayList HatPoolForClass(TFClassType playerClass)
{
	int index = view_as<int>(playerClass);
	
	if (index < 1 || index >= sizeof(g_adtHats))
		return null;
	
	if (g_adtHats[index] == null)
		g_adtHats[index] = BuildHatPool(playerClass);
	
	return g_adtHats[index];
}

/* Every misc item this class may wear, asked of the schema once

The class filter is the schema's own: an item a class cannot equip has no loadout slot for that
class. The classname filter keeps out the wearables that are really weapons, the demoman's shield
and the like, which have a misc slot and are not hats. */
static ArrayList BuildHatPool(TFClassType playerClass)
{
	ArrayList pool = new ArrayList();
	ArrayList items = TF2Econ_GetItemList();
	
	if (items == null)
		return pool;
	
	int miscSlot = TF2Econ_TranslateLoadoutSlotNameToIndex("misc");
	
	for (int i = 0; i < items.Length; i++)
	{
		int itemDefinition = items.Get(i);
		
		if (TF2Econ_GetItemLoadoutSlot(itemDefinition, playerClass) != miscSlot)
			continue;
		
		char className[64];
		
		if (!TF2Econ_GetItemClassName(itemDefinition, className, sizeof(className)))
			continue;
		
		if (!StrEqual(className, "tf_wearable"))
			continue;
		
		pool.Push(itemDefinition);
	}
	
	delete items;
	
	return pool;
}
