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

//How many times a bot may draw again when what it drew has no model to wear
#define HAT_DRAW_TRIES			4


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
	
	/* Spread across a second rather than all landing on the same frame
	
	A team spawns together, so six of these used to be scheduled for the same tenth of a second and
	fired on one frame. Dressing a bot creates an entity and precaches a model, and a precache
	that has to go to disk is not a thing to do six times inside one tick of a server that is also
	starting a wave. The half second is what it was; the rest is one bot after another. */
	float when = 0.5 + 0.15 * float(client % 8);
	
	CreateTimer(when, Timer_GiveBotCosmetics, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

static Action Timer_GiveBotCosmetics(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (client < 1)
		return Plugin_Stop;
	
	g_bCosmeticsPending[client] = false;
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || !g_bIsDefenderBot[client])
		return Plugin_Stop;
	
	/* Draw again when what the bot drew turns out not to be wearable, up to a few times

	A hat the schema has no model for is dropped from the pool and the bot was left bare until its
	next respawn, which for a defender that does not die is the rest of the mission. Every failure
	takes that item out of the pool, so the tries cannot chase the same bad one twice. */
	for (int attempt = 0; attempt < HAT_DRAW_TRIES; attempt++)
	{
		DrawWardrobe(client);
		
		if (!redbots_manager_bot_hats.BoolValue || WearHat(client))
			break;
	}
	
	return Plugin_Stop;
}

/* Put the drawn hat back on

/* Wearables the game refused, standing in the world with nobody wearing them
 *
 * TF2Util_EquipPlayerWearable asserts that the wearable ended up attached, and throws when the
 * game declined it. A thrown native takes the rest of the callback with it, so the hat entity that
 * was created a few lines earlier is never cleaned up and never worn: it just stays. Seen in the
 * error log dozens of times across a mission, and a server that leaks an edict per bot per respawn
 * eventually runs out of them.
 *
 * The equip cannot be tested in advance, so the leak is swept instead of prevented. Anything of
 * ours whose owner is not a player in the game is nobody's hat.
 */
/* Take the hat off the way the game does it

/* The model this class wears this hat with

/* A bot that has left takes its hat with it

/* What every defender bot is actually wearing, entity by entity

A hat that does not show up is one of four things and they look the same from the outside: never
drawn, drawn and refused a model, worn by an entity the game threw away, or worn by an entity with
no model index on it. This says which. */
public Action Command_DumpHats(int client, int args)
{
	for (int playerClass = 1; playerClass < sizeof(g_adtHats); playerClass++)
	{
		ArrayList pool = HatPoolForClass(view_as<TFClassType>(playerClass));

		ReplyToCommand(client, "class %d: %d hats in the pool", playerClass, pool == null ? -1 : pool.Length);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !g_bIsDefenderBot[i])
			continue;

		int hat = EntRefToEntIndex(g_iBotHat[i]);

		if (hat == INVALID_ENT_REFERENCE)
		{
			ReplyToCommand(client, "%N: class %d, drew item %d, effect %d, wearing nothing",
				i, g_wardrobe[i].PlayerClass, g_wardrobe[i].HatItem, g_wardrobe[i].HatEffect);

			continue;
		}

		char model[PLATFORM_MAX_PATH]; GetEntPropString(hat, Prop_Data, "m_ModelName", model, sizeof(model));

		ReplyToCommand(client, "%N: class %d, item %d, effect %d, entity %d, owner %d, modelindex %d, model %s",
			i, g_wardrobe[i].PlayerClass, g_wardrobe[i].HatItem, g_wardrobe[i].HatEffect, hat,
			GetEntPropEnt(hat, Prop_Send, "m_hOwnerEntity"),
			GetEntProp(hat, Prop_Send, "m_nModelIndex"), model);
	}

	return Plugin_Handled;
}

/* Every cosmetic this class may wear, asked of the schema once

Not the medals. What the bots actually drew, almost every time, was a UGC participation medal or
an ozfortress season badge: a postage stamp on the chest that reads in game as a bot wearing
nothing at all, while anything with a particle on it still drew the particle, which is why the
effects looked like the only part that worked. There are far more tournament medals in the schema
than there are cosmetics, so drawing uniformly from the slot is drawing a medal.

Filed by equip region rather than by slot, because the slot cannot tell them apart: the head slot
is the game's old single-hat one and no modern item reports it, so every cosmetic and every medal
alike comes back as misc. The medals are the ones the schema puts in the "medal" region, which is
one string off a prefab they all share.

