/* Bend a mission when few people turned up, by taking the robots down

Valve tunes every wave for six defenders. Fewer than six is a harder mission than the one the map
was built for, and the answer this mod has had until now is to fill the empty seats with bots and
hope their AI is good enough. This is the other lever: leave the seats empty and make the robots
weaker instead.

Three of them, because nobody knows yet which one matters:

	damage  what a robot's hit takes off a defender
	health  what a robot is worth killing
	speed   how fast it walks the bomb in

Speed is the one to watch. A slower robot is not simply a weaker one: it changes how long a wave
takes, how far the bomb travels between deaths, and how much money is on the field at once. It may
be the strongest lever here or the one that ruins the pacing, and only a run will say.

Each convar is the scale at one human, and the scale rises to 1.0 at a full team. So 0.7 means a
lone player fights robots at seven tenths, three players at about six sevenths, and six players
fight the mission Valve wrote. Set to 1.0 the lever is off, which is the default and what every
existing server keeps.

The convar is the switch, so the two arms of an A/B are the same build with one number different.
There is no feature flag beside it: 1.0 already means off, and a second switch that also has to be
on would be two ways to say one thing. What is set gets written into the run's results, so a file
of numbers says which arm produced it.

See docs/testbed-metrics.md: none of this ships on until a run says it helped. */

ConVar redbots_manager_blu_damage_scale;
ConVar redbots_manager_blu_health_scale;
ConVar redbots_manager_blu_speed_scale;

//The team size the scales are written against, which is the team every MvM wave is tuned for
#define BLU_ASSIST_FULL_TEAM 6.0

void BluAssist_Init()
{
	redbots_manager_blu_damage_scale = CreateConVar("sm_redbots_manager_blu_damage_scale", "1.0",
		"What a robot's damage is multiplied by when one human is on RED. Rises to 1.0 at six. 1.0 is off.",
		FCVAR_NOTIFY, true, 0.1, true, 1.0);

	redbots_manager_blu_health_scale = CreateConVar("sm_redbots_manager_blu_health_scale", "1.0",
		"What a robot's health is multiplied by when one human is on RED. Rises to 1.0 at six. 1.0 is off.",
		FCVAR_NOTIFY, true, 0.1, true, 1.0);

	redbots_manager_blu_speed_scale = CreateConVar("sm_redbots_manager_blu_speed_scale", "1.0",
		"What a robot's speed is multiplied by when one human is on RED. Rises to 1.0 at six. 1.0 is off.",
		FCVAR_NOTIFY, true, 0.1, true, 1.0);
}

//How many people who are not bots are playing on RED right now
int BluAssist_HumansOnRed()
{
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i) && TF2_GetClientTeam(i) == TFTeam_Red)
			count++;

	return count;
}

/* The multiplier one of the three levers is at, for the people currently on RED

Straight line from the convar at one human to 1.0 at six, so the assist fades as the team fills
rather than switching off at some threshold nobody can feel. An empty RED is treated as one player:
a server between rounds is not a reason to make the wave hardest.

Returns 1.0 when the convar is 1.0, which is the whole of the switch being off */
static float BluAssistScale(ConVar convar)
{
	float atOne = convar.FloatValue;

	if (atOne >= 1.0)
		return 1.0;

	float humans = float(BluAssist_HumansOnRed());

	if (humans < 1.0)
		humans = 1.0;

	if (humans >= BLU_ASSIST_FULL_TEAM)
		return 1.0;

	return atOne + (1.0 - atOne) * ((humans - 1.0) / (BLU_ASSIST_FULL_TEAM - 1.0));
}

float BluAssist_DamageScale()
{
	return BluAssistScale(redbots_manager_blu_damage_scale);
}

float BluAssist_HealthScale()
{
	return BluAssistScale(redbots_manager_blu_health_scale);
}

float BluAssist_SpeedScale()
{
	return BluAssistScale(redbots_manager_blu_speed_scale);
}

/* Add what the three levers are set to, for the line that says what was
different about this run

Nothing is added when all three are off, which is every run until somebody sets
one, so the string reads exactly as it did before this existed */
void BluAssist_Describe(char[] buffer, int maxlength)
{
	ConVar levers[3]; levers[0] = redbots_manager_blu_damage_scale;
	levers[1] = redbots_manager_blu_health_scale;
	levers[2] = redbots_manager_blu_speed_scale;

	static const char names[3][] = { "blu_damage", "blu_health", "blu_speed" };

	for (int i = 0; i < 3; i++)
	{
		if (levers[i] == null || levers[i].FloatValue >= 1.0)
			continue;

		if (buffer[0] != '\0')
			StrCat(buffer, maxlength, ",");

		char entry[32]; Format(entry, sizeof(entry), "%s=%.2f", names[i], levers[i].FloatValue);
		StrCat(buffer, maxlength, entry);
	}
}

/* Scale a robot's health and speed as it spawns

Health is set rather than added to, because the popfile has just decided what this robot is worth
and that number is the one to bend. Both the current and the maximum move, or a robot spawns hurt
instead of smaller.

A giant scales the same way a common does. The alternative is a lever per robot size, which is
three more numbers to measure before anybody knows whether the first three matter */
void BluAssist_OnRobotSpawn(int client)
{
	float health = BluAssist_HealthScale();

	if (health < 1.0)
	{
		int wanted = RoundToCeil(float(GetEntProp(client, Prop_Data, "m_iMaxHealth")) * health);

		if (wanted < 1)
			wanted = 1;

		SetEntProp(client, Prop_Data, "m_iMaxHealth", wanted);
		SetEntityHealth(client, wanted);
	}

	float speed = BluAssist_SpeedScale();

	if (speed < 1.0)
		TF2Attrib_SetByName(client, "move speed bonus", speed);
}

/* What a robot's hit takes off a defender

Hooked on the defender rather than on the robot: a player is hooked once when he joins and the
robots arrive by the hundred. */
public Action BluAssist_TakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
		return Plugin_Continue;

	if (TF2_GetClientTeam(attacker) != TFTeam_Blue)
		return Plugin_Continue;

	float scale = BluAssist_DamageScale();

	if (scale >= 1.0)
		return Plugin_Continue;

	damage *= scale;

	return Plugin_Changed;
}
