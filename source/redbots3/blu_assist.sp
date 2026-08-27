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

//Counts the robots a bend has been applied to this map, for the sampled log line below
static int m_iBluAssistSeen;

//The same, for hits a robot landed on a defender
static int m_iBluAssistHits;

void BluAssist_Init()
{
	m_iBluAssistSeen = 0;
	m_iBluAssistHits = 0;

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

Applied a frame after player_spawn. The popfile finishes building the robot inside the spawn frame:
it gives the template's items, fires post_inventory_application, then writes the health and the
attributes the mission wants. Anything written from the event itself is overwritten by that, which
is why health and speed did nothing while damage, scaled on the hit rather than on the robot, did.

Health goes through "max health additive bonus" as well as m_iMaxHealth, because TF2 recomputes the
maximum from the attributes and would otherwise put the popfile's number back. The delta is added
to what the popfile already set, so a giant stays a giant, scaled.

Speed multiplies the template's own move speed bonus rather than replacing it, or a fast robot and
a normal one would come out walking at the same speed.

A giant scales the same way a common does. The alternative is a lever per robot size, which is
three more numbers to measure before anybody knows whether the first three matter */
void BluAssist_OnRobotSpawn(int client)
{
	if (BluAssist_HealthScale() >= 1.0 && BluAssist_SpeedScale() >= 1.0)
		return;

	RequestFrame(BluAssistApplyToRobot, GetClientUserId(client));
}

static void BluAssistApplyToRobot(int userid)
{
	int client = GetClientOfUserId(userid);

	if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
		return;

	if (TF2_GetClientTeam(client) != TFTeam_Blue || !IsFakeClient(client))
		return;

	float health = BluAssist_HealthScale();

	if (health < 1.0)
	{
		int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
		int wanted = RoundToCeil(float(maxHealth) * health);

		if (wanted < 1)
			wanted = 1;

		BluAssistBendAttrib(client, "max health additive bonus", 0.0, float(wanted - maxHealth));

		SetEntProp(client, Prop_Data, "m_iMaxHealth", wanted);
		SetEntityHealth(client, wanted);
	}

	float speed = BluAssist_SpeedScale();

	if (speed < 1.0)
		BluAssistBendAttrib(client, "move speed bonus", 1.0, 0.0, speed);

	BluAssistSay(client, health, speed);
}

/* Write down what a bend actually did to one robot in every BLU_ASSIST_SAMPLE

The levers are read off wave outcomes otherwise, and a wave outcome cannot tell a lever that did
nothing from a lever that did something too small to win with. This says what the robot was worth
before and after, which is the question.

Sampled rather than every robot: a wave brings them by the hundred and a line per robot is a line
nobody reads. */
#define BLU_ASSIST_SAMPLE	25

static void BluAssistSay(int client, float health, float speed)
{
	if (health >= 1.0 && speed >= 1.0)
		return;

	if (++m_iBluAssistSeen % BLU_ASSIST_SAMPLE != 0)
		return;

	Address moveAttrib = TF2Attrib_GetByName(client, "move speed bonus");

	LogMessage("BluAssist: robot %d of the wave, health %d of %d wanted x%.2f, move speed bonus %.2f wanted x%.2f, on the ground %.0f",
		m_iBluAssistSeen,
		GetClientHealth(client), GetEntProp(client, Prop_Data, "m_iMaxHealth"), health,
		moveAttrib == Address_Null ? 1.0 : TF2Attrib_GetValue(moveAttrib), speed,
		GetEntPropFloat(client, Prop_Data, "m_flMaxspeed"));
}

/* Bend an attribute the popfile may already have set, from its neutral value when it has not

Both bends compose with the mission rather than replacing it: the delta for a health bonus that is
additive, the scale for a speed bonus that is a multiplier. */
static void BluAssistBendAttrib(int client, const char[] name, float neutral, float delta, float scale = 1.0)
{
	Address attrib = TF2Attrib_GetByName(client, name);
	float current = attrib == Address_Null ? neutral : TF2Attrib_GetValue(attrib);

	TF2Attrib_SetByName(client, name, current * scale + delta);
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

	float before = damage;

	damage *= scale;

	/* Same sampling as the spawn bends, and for the same reason: a wave outcome cannot tell a
	   damage lever that is not applying from one that is applying and not enough. */
	if (++m_iBluAssistHits % BLU_ASSIST_SAMPLE == 0)
		LogMessage("BluAssist: hit %d of the wave, %.0f became %.0f, wanted x%.2f",
			m_iBluAssistHits, before, damage, scale);

	return Plugin_Changed;
}
