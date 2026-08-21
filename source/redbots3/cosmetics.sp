/* Hats, unusual effects and weapon skins on the defender bots, for the look of the thing

None of this changes how a bot plays. What the team looks like now is six bare-headed mercenaries
with the same three weapons, and a run built out of a randomiser is more fun to watch when they
look like six strangers who met on the way in.

The three pools come from the game's own item schema through tf_econ_data, never from a table of
numbers in this file. A table of item definition indexes is a guess that goes stale on the next
update, and the schema is what the client renders from anyway. Each pool costs one walk of the
schema, once, and is then kept.

The attribute numbers are the schema's own: 134 attaches a particle, 834 names a war paint and
725 says how worn it is. Read out of scripts/items/items_game.txt rather than copied from a
forum post.

Defender bots only, and never the invading robots: a wave is read by silhouette, and a robot in a
hat is a robot somebody shoots a moment later than they should. */

//The quality a client expects on an item before it will draw either of these
#define TF_QUALITY_UNIQUE		6
#define TF_QUALITY_UNUSUAL		5
#define TF_QUALITY_DECORATED	15

#define ATTRIB_ATTACH_PARTICLE	134
#define ATTRIB_PAINTKIT			834
#define ATTRIB_TEXTURE_WEAR		725

//Factory New to Battle Scarred, which is the whole of what a war paint can look like
static const float WEAR_LEVELS[] = {0.2, 0.4, 0.6, 0.8, 1.0};

//One pool per class, because a hat one class can wear another cannot. Index 0 is TFClass_Unknown
static ArrayList g_adtHats[view_as<int>(TFClass_Engineer) + 1];
static ArrayList g_adtHatEffects;
static ArrayList g_adtPaintKits;

/* What one bot wears, drawn once and worn for the rest of the mission

Drawn once and not per life, because the hat is how a player tells one bot from another. A team
of six that comes back from the respawn room in six new hats is a team nobody can follow, and
following them is most of what there is to do while they play.

The class is part of it: a bot that changes class between waves cannot wear what it drew, so it
draws again. The weapon slots are here for the same reason, since the weapons change with the
class. */
enum struct Wardrobe
{
	bool drawn;
	TFClassType playerClass;
	int hatItem;
	int hatEffect;
	int paintKit[3];
	float paintWear[3];
}

static Wardrobe g_wardrobe[MAXPLAYERS + 1];

//The hat entity itself, which the game destroys on every respawn and this puts back
static int g_iBotHat[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};

//Whether a bot is already waiting to be dressed, so it is dressed once
static bool g_bCosmeticsPending[MAXPLAYERS + 1];

/* Half a second after the bot spawns, not the moment it does

The game gives its own items on spawn, and the custom loadout replaces them a tenth of a second
later. Painting a weapon that is about to be thrown away paints nothing.

Once per spawn, however many times it is asked. A bot's first spawn asks twice: the spawn that
identifies it as ours, and the respawn that applies its loadout, which is close enough behind to
be the same moment. Without the flag that is a hat created, worn and taken off again for every
bot at the start of every wave. */
void GiveBotCosmeticsSoon(int client)
{
	if (!redbots_manager_bot_hats.BoolValue && !redbots_manager_bot_weapon_skins.BoolValue)
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
	
	if (redbots_manager_bot_weapon_skins.BoolValue)
		PaintCarriedWeapons(client);
	
	return Plugin_Stop;
}

/* What this bot is going to wear for the rest of the mission, drawn once

Everything is drawn together, hat and weapons, so that one class change redraws the lot and
nothing is left over from the class before. */
static void DrawWardrobe(int client)
{
	TFClassType playerClass = TF2_GetPlayerClass(client);
	
	if (g_wardrobe[client].drawn && g_wardrobe[client].playerClass == playerClass)
		return;
	
	ArrayList hats = HatPoolForClass(playerClass);
	ArrayList paintKits = PaintKitPool();
	
	g_wardrobe[client].drawn = true;
	g_wardrobe[client].playerClass = playerClass;
	g_wardrobe[client].hatItem = hats != null && hats.Length > 0 ? hats.Get(GetRandomInt(0, hats.Length - 1)) : 0;
	g_wardrobe[client].hatEffect = redbots_manager_bot_hat_effects.BoolValue ? RandomHatEffect() : 0;
	
	for (int slot = 0; slot < sizeof(g_wardrobe[].paintKit); slot++)
	{
		g_wardrobe[client].paintKit[slot] = paintKits != null && paintKits.Length > 0 ? paintKits.Get(GetRandomInt(0, paintKits.Length - 1)) : 0;
		g_wardrobe[client].paintWear[slot] = WEAR_LEVELS[GetRandomInt(0, sizeof(WEAR_LEVELS) - 1)];
	}
	
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
	TF2Util_EquipPlayerWearable(client, hat);
	
	g_iBotHat[client] = EntIndexToEntRef(hat);
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

/* A bot that has left takes its hat with it

Nothing to remove, then: the game clears a player's wearables when the player goes, and a
reference to an entity that is gone reads as no entity. Only what is remembered here is left. */
void ForgetBotCosmetics(int client)
{
	g_iBotHat[client] = INVALID_ENT_REFERENCE;
	g_bCosmeticsPending[client] = false;
	
	//The next bot in this seat is a different bot, and dresses itself
	g_wardrobe[client].drawn = false;
}

//The three the player sees in a teammate's hands. The rest are pdas and buildings nobody paints
static void PaintCarriedWeapons(int client)
{
	for (int slot = TFWeaponSlot_Primary; slot <= TFWeaponSlot_Melee; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		
		if (weapon == -1 || g_wardrobe[client].paintKit[slot] < 1)
			continue;
		
		TF2Attrib_SetByDefIndex(weapon, ATTRIB_PAINTKIT, float(g_wardrobe[client].paintKit[slot]));
		TF2Attrib_SetByDefIndex(weapon, ATTRIB_TEXTURE_WEAR, g_wardrobe[client].paintWear[slot]);
		SetEntProp(weapon, Prop_Send, "m_iEntityQuality", TF_QUALITY_DECORATED);
	}
}

static int RandomHatEffect()
{
	if (g_adtHatEffects == null)
		g_adtHatEffects = TF2Econ_GetParticleAttributeList(ParticleSet_CosmeticUnusualEffects);
	
	if (g_adtHatEffects == null || g_adtHatEffects.Length < 1)
		return 0;
	
	return g_adtHatEffects.Get(GetRandomInt(0, g_adtHatEffects.Length - 1));
}

static ArrayList PaintKitPool()
{
	if (g_adtPaintKits == null)
		g_adtPaintKits = TF2Econ_GetPaintKitDefinitionList();
	
	return g_adtPaintKits;
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
