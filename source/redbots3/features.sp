/* Ways of playing that can be switched off, so two of them can be compared

Every behaviour in this mod is an argument until somebody measures it, and measuring one means
running the same mission twice with one thing different. That was being done by building two
copies of the mod and keeping them in two directories, which is slow, easy to get wrong, and
impossible to tell apart afterwards from the results alone.

A feature is a named switch with a default. It becomes a convar, so a mission can turn it off in
one line of a config, and the set that was on is written into the wave results, so a file of
numbers says which mod produced it without anybody having to remember.

Adding one is a line in LoadFeatures and a call to Feature() where the behaviour lives. Removing
one is deleting both, which is the point: a switch nobody has turned off in a month is a
behaviour, and it should stop being a switch.

The names live in one array of fixed strings and nothing copies them about. The first version of
this kept a description per feature in an enum struct and copied both in with strcopy, which is
three ways to get a length wrong for no gain: the description is only ever handed straight to
CreateConVar, so it can be written where it is used. */

enum
{
	FEATURE_THREAT_PRIORITY = 0,
	FEATURE_DISPENSER_GUARD,
	FEATURE_SPY_GLANCE,
	FEATURE_STICKY_STACK,
	FEATURE_NEST_ZONES,
	FEATURE_READY_WHEN_PREPARED,
	FEATURE_WAVE_RESISTANCES,
	FEATURE_DEMO_HOLD_FIRE,
	FEATURE_ATTACK_STRAFE,
	FEATURE_SOLDIER_CLOSES_IN,
	FEATURE_ATTACK_PATH_NUDGE,
	FEATURE_EXPLOSIVE_MIN_RANGE,
	FEATURE_BLAST_RESIST_SELF,
	FEATURE_COUNT
}

//Same order as the enum above, and the compiler checks the count matches
static const char FEATURE_NAME[FEATURE_COUNT][] =
{
	"threat_priority",
	"dispenser_guard",
	"spy_glance",
	"sticky_stack",
	"nest_zones",
	"ready_when_prepared",
	"wave_resistances",
	"demo_hold_fire",
	"attack_strafe",
	"soldier_closes_in",
	"attack_path_nudge",
	"explosive_min_range",
	"blast_resist_self"
};

static ConVar g_arrFeatureConVars[FEATURE_COUNT];
static ConVar g_cvFeaturesActive;

static ConVar MakeFeature(int id, const char[] description)
{
	char name[64]; Format(name, sizeof(name), "sm_redbots_feature_%s", FEATURE_NAME[id]);

	//Every feature ships on. A switch exists to turn something off and measure the difference
	return CreateConVar(name, "1", description, FCVAR_NOTIFY);
}

void LoadFeatures()
{
	g_arrFeatureConVars[FEATURE_THREAT_PRIORITY] = MakeFeature(FEATURE_THREAT_PRIORITY,
		"Shoot the Medic, then the Sniper and Engineer, then giants, rather than whatever is nearest.");

	g_arrFeatureConVars[FEATURE_DISPENSER_GUARD] = MakeFeature(FEATURE_DISPENSER_GUARD,
		"A hurt or dry bot holds the bomb from a friendly dispenser instead of leaving to find a health pack.");

	g_arrFeatureConVars[FEATURE_SPY_GLANCE] = MakeFeature(FEATURE_SPY_GLANCE,
		"Bots look behind themselves while the team knows a Spy is about.");

	g_arrFeatureConVars[FEATURE_STICKY_STACK] = MakeFeature(FEATURE_STICKY_STACK,
		"Sticky traps stack on one spot for a giant rather than carpeting ground for a crowd.");

	g_arrFeatureConVars[FEATURE_NEST_ZONES] = MakeFeature(FEATURE_NEST_ZONES,
		"Engineers spread across the zones a map names, so one holds inside and one holds out.");

	g_arrFeatureConVars[FEATURE_READY_WHEN_PREPARED] = MakeFeature(FEATURE_READY_WHEN_PREPARED,
		"An engineer readies at a level three nest and a medic at a full charge, not before.");

	g_arrFeatureConVars[FEATURE_WAVE_RESISTANCES] = MakeFeature(FEATURE_WAVE_RESISTANCES,
		"Buy the resistance the coming wave's robots call for, rather than ranking resistances last.");

	g_arrFeatureConVars[FEATURE_DEMO_HOLD_FIRE] = MakeFeature(FEATURE_DEMO_HOLD_FIRE,
		"The Demoman holds his pipes until the target is near enough for one to arrive.");

	g_arrFeatureConVars[FEATURE_BLAST_RESIST_SELF] = MakeFeature(FEATURE_BLAST_RESIST_SELF,
		"Blast resistance is worth buying to a Soldier or Demoman whatever the wave carries, because he explodes himself.");

	g_arrFeatureConVars[FEATURE_EXPLOSIVE_MIN_RANGE] = MakeFeature(FEATURE_EXPLOSIVE_MIN_RANGE,
		"A robot inside his own blast is shot with something that does not explode.");

	g_arrFeatureConVars[FEATURE_ATTACK_PATH_NUDGE] = MakeFeature(FEATURE_ATTACK_PATH_NUDGE,
		"A fighter the nav mesh will not path steps toward its target instead of standing still.");

	g_arrFeatureConVars[FEATURE_SOLDIER_CLOSES_IN] = MakeFeature(FEATURE_SOLDIER_CLOSES_IN,
		"A rocket is fought at a grenade's distance rather than twelve hundred units out.");

	g_arrFeatureConVars[FEATURE_ATTACK_STRAFE] = MakeFeature(FEATURE_ATTACK_STRAFE,
		"A bot that has arrived at its firing position keeps sidestepping instead of standing still.");

	/* What is on, as one string, for whoever reads the results later

	Written rather than read: nothing in the mod uses it. It exists so the statistics plugin can
	put it in the file, because a run whose settings are not recorded is a run that cannot be
	compared with anything. */
	g_cvFeaturesActive = CreateConVar("sm_redbots_features_active", "",
		"The features that are on, comma separated. Set by the mod, not by you.", FCVAR_NONE);
}

//A feature nobody switched is on, so a config that names none of them gets the mod as shipped
bool Feature(int id)
{
	if (id < 0 || id >= FEATURE_COUNT || g_arrFeatureConVars[id] == null)
		return true;

	return g_arrFeatureConVars[id].BoolValue;
}

/* Publish the set that is on

Called when a wave begins rather than once at map start: a config file executes at its own pace
and a late loaded plugin misses it entirely, so the answer earlier than this is the defaults
rather than what the server was asked for. */
void PublishActiveFeatures()
{
	if (g_cvFeaturesActive == null)
		return;

	char list[512];

	for (int i = 0; i < FEATURE_COUNT; i++)
	{
		if (!Feature(i))
			continue;

		if (list[0] != '\0')
			StrCat(list, sizeof(list), ",");

		StrCat(list, sizeof(list), FEATURE_NAME[i]);
	}

	g_cvFeaturesActive.SetString(list);
}
