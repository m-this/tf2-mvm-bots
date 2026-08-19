/* Engagement ranges per weapon, by item definition index

The bot's ranges come from the weapon's ID, so every minigun is one weapon and every shotgun is
another. That is the wrong grain for a server that hands out loadouts. A Brass Beast cannot
reposition once it is spun up and wants to already be close; a Tomislav spins up fast enough to
hold a lane. A Heavy who pulled the shotgun is standing at minigun distance with a weapon that
does nothing there. The item definition index is the only thing that tells any of them apart.

desired is the distance the bot closes to before it settles. It is what moves a bot, so it is the
one worth setting: attack.sp walks the bot in whenever the target is further away than this.

maxRange is where the bot stops firing at all. It stays 0.0, "no opinion", for almost everything,
because a bot that refuses to shoot is worse than one that shoots for little damage. It is set
only where the shot is genuinely wasted, or where firing point blank hurts the bot itself.

Every index here is a stock TF2 item definition. A weapon absent from the table keeps the answer
its weapon ID already gave, so this file only ever narrows behaviour that was previously flat. */

//No opinion: the caller keeps the range its weapon ID produced.
#define RANGE_TUNING_NONE 0.0

/* Ranges for one weapon. False when the table says nothing about it, and neither output is
touched, so a caller can pass values it already computed */
stock bool GetTunedWeaponRanges(int weapon, float &desired, float &maxRange)
{
	if (!IsValidEntity(weapon) || !HasEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
		return false;

	switch (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
	{
		//--- Scatterguns. Knockback and damage both want the bot in the target's face
		case 45: //Force-A-Nature
		{
			desired = 180.0;
			maxRange = 600.0;
		}
		case 448: //Soda Popper
		{
			desired = 250.0;
			maxRange = 650.0;
		}

		//--- Shotguns. Past a few hundred units the pellets are worth nothing
		case 425: //Family Business
		{
			desired = 280.0;
			maxRange = 700.0;
		}
		case 1153: //Panic Attack
		{
			desired = 250.0;
			maxRange = 650.0;
		}
		case 527: //Widowmaker
		{
			desired = 300.0;
			maxRange = 750.0;
		}

		//--- Miniguns. The difference is whether the bot can afford to be caught out of position
		case 312: //Brass Beast
		{
			desired = 350.0;
			maxRange = RANGE_TUNING_NONE;
		}
		case 424: //Tomislav
		{
			desired = 500.0;
			maxRange = RANGE_TUNING_NONE;
		}

		//--- Explosives. Far enough out that the blast does not catch the bot
		case 996: //Loose Cannon
		{
			desired = 650.0;
			maxRange = 1500.0;
		}
		case 1151: //Iron Bomber
		{
			desired = 600.0;
			maxRange = 1400.0;
		}
		case 730: //Beggar's Bazooka
		{
			//Shorter than a stock rocket launcher: the rockets spread as they load
			desired = 600.0;
			maxRange = 1500.0;
		}

		//--- Weapons that want the bot to hold its distance
		case 997: //Rescue Ranger
		{
			desired = 800.0;
			maxRange = RANGE_TUNING_NONE;
		}
		case 305: //Crusader's Crossbow
		{
			desired = 900.0;
			maxRange = RANGE_TUNING_NONE;
		}
		case 61: //Ambassador
		{
			desired = 700.0;
			maxRange = RANGE_TUNING_NONE;
		}
		case 412: //Overdose
		{
			//A syringe gun is a close weapon on a class that should not be there
			desired = 300.0;
			maxRange = 800.0;
		}
		default:
		{
			return false;
		}
	}

	return true;
}
