/* Ways of playing that can be switched off, so two of them can be compared

Every behaviour in this mod is an argument until somebody measures it, and measuring one means
running the same mission twice with one thing different. That was being done by building two
copies of the mod and keeping them in two directories, which is slow, easy to get wrong, and
impossible to tell apart afterwards from the results alone.

A feature is a named switch with a default. It becomes a convar, so a mission can turn it off in
one line of a config, and the set that was on is written into the wave results, so a file of
numbers says which mod produced it without anybody having to remember.

Adding one is a line in FEATURES and a call to Feature() where the behaviour lives. Removing one
is deleting both, which is the point: a switch that nobody has turned off in a month is a
behaviour, and it should stop being a switch. */

enum
{
	FEATURE_THREAT_PRIORITY = 0,
	FEATURE_DISPENSER_GUARD,
	FEATURE_SPY_GLANCE,
	FEATURE_STICKY_STACK,
	FEATURE_NEST_ZONES,
	FEATURE_READY_WHEN_PREPARED,
	FEATURE_WAVE_RESISTANCES,
	FEATURE_COUNT
}

enum struct FeatureInfo
{
	char name[32];
	bool on;
	char what[160];
}

static FeatureInfo g_arrFeatures[FEATURE_COUNT];
static ConVar g_arrFeatureConVars[FEATURE_COUNT];
static ConVar g_cvFeaturesActive;

static void DefineFeature(int id, const char[] name, bool on, const char[] what)
{
	strcopy(g_arrFeatures[id].name, sizeof(g_arrFeatures[].name), name);
	strcopy(g_arrFeatures[id].what, sizeof(g_arrFeatures[].what), what);
	g_arrFeatures[id].on = on;
}

void LoadFeatures()
{
	DefineFeature(FEATURE_THREAT_PRIORITY, "threat_priority", true,
		"Shoot the Medic, then the Sniper and Engineer, then giants, rather than whatever is nearest.");
	DefineFeature(FEATURE_DISPENSER_GUARD, "dispenser_guard", true,
		"A hurt or dry bot holds the bomb from a friendly dispenser instead of leaving to find a health pack.");
	DefineFeature(FEATURE_SPY_GLANCE, "spy_glance", true,
		"Bots look behind themselves while the team knows a Spy is about.");
	DefineFeature(FEATURE_STICKY_STACK, "sticky_stack", true,
		"Sticky traps stack on one spot for a giant rather than carpeting ground for a crowd.");
	DefineFeature(FEATURE_NEST_ZONES, "nest_zones", true,
		"Engineers spread across the zones a map names, so one holds inside and one holds out.");
	DefineFeature(FEATURE_READY_WHEN_PREPARED, "ready_when_prepared", true,
		"An engineer readies at a level three nest and a medic at a full charge, not before.");
	DefineFeature(FEATURE_WAVE_RESISTANCES, "wave_resistances", true,
		"Buy the resistance the coming wave's robots call for, rather than ranking resistances last.");

	char name[64];

	for (int i = 0; i < FEATURE_COUNT; i++)
	{
		Format(name, sizeof(name), "sm_redbots_feature_%s", g_arrFeatures[i].name);

		g_arrFeatureConVars[i] = CreateConVar(name, g_arrFeatures[i].on ? "1" : "0",
			g_arrFeatures[i].what, FCVAR_NOTIFY);
	}

	/* What is on, as one string, for whoever reads the results later

	Written rather than read: nothing in the mod uses it. It exists so the statistics plugin can
	put it in the file, because a run whose settings are not recorded is a run that cannot be
	compared with anything. */
	g_cvFeaturesActive = CreateConVar("sm_redbots_features_active", "",
		"The features that are on, comma separated. Set by the mod, not by you.", FCVAR_NOTIFY);
}

//A feature nobody switched is its default, so a config that names none of them gets the mod as shipped
bool Feature(int id)
{
	if (id < 0 || id >= FEATURE_COUNT)
		return true;

	if (g_arrFeatureConVars[id] == null)
		return g_arrFeatures[id].on;

	return g_arrFeatureConVars[id].BoolValue;
}

/* Publish the set that is on, once, when a map has settled

Late because a config file executes after the convars exist, and the answer before it runs is the
defaults rather than what the server was asked for. */
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

		StrCat(list, sizeof(list), g_arrFeatures[i].name);
	}

	g_cvFeaturesActive.SetString(list);

	LogMessage("Features on: %s", list[0] == '\0' ? "none" : list);
}
