/* The health and ammo search, which the generator cannot write yet

The rest of getammo.sp is generated from internal/action/getammo. This is what did not come with
it: the search reads a table of class names and hands its sort a function, and the Go subset has
neither a string table nor a function value. mvm-z83 carries that gap; when it closes this file
goes away and these two move into the package with the rest.

The comments below are the ones the original carried. */

static char g_strHealthAndAmmoEntities[][] = 
{
	"func_regenerate",
	"item_ammopack*",
	"item_health*",
	"obj_dispenser",
	"tf_ammo_pack"
};

/* The health and ammo this bot could actually walk to, and how far each one really is

Two costs hide in this and both were paid per candidate: a nav mesh search, and a JSON object on
the heap. MvM floors are covered in candidates, because tf_ammo_pack is what a dead robot leaves
behind and a wave leaves hundreds of them.

So the cheap question goes first. Straight-line distance costs a subtraction and orders the
candidates; the search is run only for the nearest few, because the nearest few are where the
answer is and the rest were never going to win. A pack behind a wall now loses its place to the
next one along instead of costing a search of its own.

The list is entity index and travel distance, in pairs, and the caller takes the shortest. */
#define HEALTH_CANDIDATES_MAX	64
#define HEALTH_PATHS_MAX		AMMO_CANDIDATES_MAX

void ComputeHealthAndAmmoVectors(int client, ArrayList found, float max_range)
{
	ArrayList nearby = new ArrayList(2);
	
	float myCentre[3]; myCentre = WorldSpaceCenter(client);
	
	for (int i = 0; i < sizeof(g_strHealthAndAmmoEntities); i++)
	{
		int ammo = -1;
		
		while ((ammo = FindEntityByClassname(ammo, g_strHealthAndAmmoEntities[i])) != -1)
		{
			//A wave leaves more of these on the floor than anybody is going to walk to
			if (nearby.Length >= HEALTH_CANDIDATES_MAX)
				break;
			
			if (BaseEntity_GetTeamNumber(ammo) == view_as<int>(GetPlayerEnemyTeam(client)))
				continue;
			
			float range = GetVectorDistance(myCentre, WorldSpaceCenter(ammo));
			
			if (range > max_range)
				continue;
			
			if (BaseEntity_IsBaseObject(ammo))
			{
				//Can't get anything from still building buildings.
				if (TF2_IsBuilding(ammo))
					continue;
				
				//Skip empty dispenser.
				if (TF2_GetObjectType(ammo) == TFObject_Dispenser && GetEntProp(ammo, Prop_Send, "m_iAmmoMetal") <= 0)
					continue;
			}
			
			int at = nearby.Push(range);
			nearby.Set(at, ammo, 1);
		}
	}
	
	nearby.SortCustom(SortByStraightLineRange);
	
	int searches = 0;
	
	for (int i = 0; i < nearby.Length && searches < HEALTH_PATHS_MAX; i++)
	{
		int ammo = nearby.Get(i, 1);
		float length;
		
		searches++;
		
		if (!IsPathToVectorPossible(client, WorldSpaceCenter(ammo), length))
			continue;
		
		if (length > max_range)
			continue;
		
		int at = found.Push(ammo);
		found.Set(at, length, 1);
	}
	
	delete nearby;
}

static int SortByStraightLineRange(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList list = view_as<ArrayList>(array);
	
	float first = view_as<float>(list.Get(index1, 0));
	float second = view_as<float>(list.Get(index2, 0));
	
	if (first < second)
		return -1;
	
	return first > second ? 1 : 0;
}
