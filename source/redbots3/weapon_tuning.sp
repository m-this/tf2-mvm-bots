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

/* How close a Demoman gets before he settles, and how far away he will still throw a pipe

Two different numbers and it took a measurement to learn which one was the problem.

Closing in was tried first, on the reasoning that a pipe thrown from six hundred units is half a
second in the air and a walking robot has moved a hundred and forty by the time it lands. Three
fifty instead of six hundred, six waves a side on three maps:

  settles at 600   1403, 2096, 1305 damage a wave on Coaltown, Decoy, Mannworks
  settles at 350    929, 1274, 1238

Down on all three. Walking in is time not shooting, and in this mode the robots are walking to him
anyway, so the ground he gives up to reach them is ground he has to cross again.

The number that was wrong is the other one. maxRange is where the bot stops firing at all, and at
fourteen hundred units a pipe is well over a second in the air and lands wherever the robot is
not. The bot fires the whole way in from there, which is a clip and a reload spent on nothing, and
it is what "the Demomen shoot from too far away" looks like from outside. The stock launcher was
worse: absent from this table, it fell through to no limit at all and threw pipes across the map.

Nine hundred still covers the approach: he settles at six hundred, so there is room to fire while
closing without firing at a rumour. */
/* Where a Soldier fights, when he is allowed to choose it
 *
 * Between the Beggar's six hundred and the twelve fifty the stock launcher used to sit at. Far
 * enough that his own blast does not reach him, near enough that a rocket arrives before the robot
 * it was aimed at has walked out of the splash.
 */
#define SOLDIER_ROCKET_SETTLE	750.0

#define DEMO_PIPE_SETTLE		600.0
#define DEMO_PIPE_HOLD_FIRE		900.0
#define DEMO_PIPE_FIRE_ANYWAY	1400.0

/* Which of the two, so the pair get played against each other rather than argued about
 *
 * Worth re-reading now there are numbers for where he actually fights. The telemetry puts his
 * median distance to the nearest robot between 1044 and 1258 units on the two maps measured, so
 * holding fire past 900 is holding fire for most of a wave. The pair last played each other before
 * anything counted the range.
 */
stock float DemoPipeMaxRange()
{
	return Feature(FEATURE_DEMO_HOLD_FIRE) ? DEMO_PIPE_HOLD_FIRE : DEMO_PIPE_FIRE_ANYWAY;
}

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
		/* The stock shotgun, which was absent and took the five hundred unit default
		
		Five hundred is minigun ground. Every other shotgun in this table sits between two and
		three hundred, because that is where the pellets are worth anything, and the one four
		classes actually carry was the one nobody had written down. */
		case 199: //Shotgun
		{
			desired = 280.0;
			maxRange = 700.0;
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
			desired = DEMO_PIPE_SETTLE;
			maxRange = DemoPipeMaxRange();
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
