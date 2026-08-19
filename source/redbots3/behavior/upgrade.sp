#define BUY_UPGRADES_MAX_TIME	30.0
#define BUY_UPGRADES_FAST_MAX_TIME	3.0

static int MAX_INT = 99999999;
static int MIN_INT = -99999999;

JSONArray CTFPlayerUpgrades[MAXPLAYERS + 1];
float m_flNextUpgrade[MAXPLAYERS + 1];
int m_nPurchasedUpgrades[MAXPLAYERS + 1];
float m_flUpgradingTime[MAXPLAYERS + 1];

BehaviorAction CTFBotUpgrade()
{
	BehaviorAction action = ActionsManager.Create("DefenderUpgrade");
	
	action.OnStart = CTFBotUpgrade_OnStart;
	action.Update = CTFBotUpgrade_Update;
	action.OnEnd = CTFBotUpgrade_OnEnd;
	
	return action;
}

public Action CTFBotUpgrade_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	if (!TF2_IsInUpgradeZone(actor)) 
		return action.ChangeTo(CTFBotGotoUpgrade(), "Not standing at an upgrade station!");
	
	CollectUpgrades(actor);
	
	KV_MvM_UpgradesBegin(actor);
	
	m_flNextUpgrade[actor] = GetGameTime() + GetUpgradeInterval();
	
	bool isRoundActive = GameRules_GetRoundState() == RoundState_RoundRunning;
	
	//How long should it take us to buy upgrades?
	if (g_bHasUpgraded[actor] == false && isRoundActive)
	{
		//We probably just joined during an active game
		m_flUpgradingTime[actor] = GetGameTime() + 15.0;
	}
	else
	{
		//spend less time upgrading during the round, normal otherwise
		m_flUpgradingTime[actor] = GetGameTime() + (isRoundActive ? BUY_UPGRADES_FAST_MAX_TIME : BUY_UPGRADES_MAX_TIME);
	}
	
	// UpdateLookAroundForEnemies(actor, false);
	
	return action.Continue();
}

public Action CTFBotUpgrade_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!TF2_IsInUpgradeZone(actor)) 
		return action.ChangeTo(CTFBotGotoUpgrade(), "Not standing at an upgrade station!");
	
	if (m_flUpgradingTime[actor] <= GetGameTime())
	{
		//It shouldn't take us this long to upgrade...
		
		SetPlayerReady(actor, true);
		
		if (redbots_manager_debug_actions.BoolValue)
			PrintToChatAll("%N upgrade for long with %d credits left!", actor, TF2_GetCurrency(actor));
		
		return GetUpgradePostAction(actor, action);
	}
	
	float flNextTime = m_flNextUpgrade[actor] - GetGameTime();
	
	if (flNextTime <= 0.0)
	{
		m_flNextUpgrade[actor] = GetGameTime() + GetUpgradeInterval();
		
		JSONObject info = CTFBotPurchaseUpgrades_ChooseUpgrade(actor);
		
		if (info != null) 
		{
			CTFBotPurchaseUpgrades_PurchaseUpgrade(actor, info);
			
			if (redbots_manager_debug_actions.BoolValue)
				PrintToChatAll("Currenct left for %N: %d", actor, TF2_GetCurrency(actor));
		}
		else 
		{
			// g_flNextUpdate[actor] = 0.0;
			
			SetPlayerReady(actor, true);
			
			delete info;
			
			return GetUpgradePostAction(actor, action);
		}
		
		delete info;
	}
	
	if (TF2_GetPlayerClass(actor) == TFClass_Medic)
	{
		int secondary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
		
		if (secondary != -1 && TF2Util_GetWeaponID(secondary) == TF_WEAPON_MEDIGUN)
		{
			int teammate = GerNearestTeammate(actor, WEAPON_MEDIGUN_RANGE);
			
			if (teammate != -1)
			{
				//Heal a nearby teammate so we build up uber
				TF2Util_SetPlayerActiveWeapon(actor, secondary);
				SnapViewToPosition(actor, WorldSpaceCenter(teammate));
				VS_PressFireButton(actor);
			}
		}
	}
	
	return action.Continue();
}

public void CTFBotUpgrade_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	//Lastly, try to purchase any canteens we can afford
	PurchaseAffordableCanteens(actor);
	
	KV_MvM_UpgradesDone(actor);
	
	if (TF2_GetPlayerClass(actor) == TFClass_Engineer && GameRules_GetRoundState() == RoundState_BetweenRounds)
	{
		DetonateObjectOfType(actor, TFObject_Sentry);
		DetonateObjectOfType(actor, TFObject_Dispenser);
	}
	
	// UpdateLookAroundForEnemies(actor, true);
	
	if (IsPlayerAlive(actor))
	{
		//Remember this bot's upgrades
		Command_BoughtUpgrades(actor, 0);
		
		//First upgrade session upon joining, give everything as if we prepared beforehand
		//Mainly for use with MANAGER_MODE_AUTO_BOTS
		if (GameRules_GetRoundState() == RoundState_RoundRunning && g_bHasUpgraded[actor] == false)
			UpgradeMidRoundPostActivity(actor);
		
		g_bHasUpgraded[actor] = true;
		g_iBuyUpgradesNumber[actor] = 0;
		
		TF2_SetInUpgradeZone(actor, false);
	}
}

void CollectUpgrades(int client)
{
	if (CTFPlayerUpgrades[client] != null)
		delete CTFPlayerUpgrades[client];
		
	CTFPlayerUpgrades[client] = new JSONArray();
	
	ArrayList iArraySlots = new ArrayList();
	
	iArraySlots.Push(-1); //Always buy player upgrades
	
	bool bDemoKnight = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary) == -1;
	bool bEngineer = TF2_GetPlayerClass(client) == TFClass_Engineer;
	
	if (bEngineer)
	{
		iArraySlots.Push(TF_LOADOUT_SLOT_MELEE);
		iArraySlots.Push(TF_LOADOUT_SLOT_BUILDING);
		iArraySlots.Push(TF_LOADOUT_SLOT_PDA);
	}
	else
	{
		if (TF2_GetPlayerClass(client) == TFClass_Sniper)
		{
			iArraySlots.Push(TF_LOADOUT_SLOT_PRIMARY);
			iArraySlots.Push(TF_LOADOUT_SLOT_MELEE);
		}
		else if (TF2_GetPlayerClass(client) == TFClass_Medic)
		{
			//Buy upgrades for our medigun
			iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
		}
		else if (TF2_GetPlayerClass(client) == TFClass_Spy)
		{
			//Buy upgrades for our sapper and knife
			iArraySlots.Push(TF_LOADOUT_SLOT_BUILDING);
			iArraySlots.Push(TF_LOADOUT_SLOT_MELEE);
		}

		//Demoknight doesn't buy primary weapon upgrades.
		iArraySlots.Push(bDemoKnight ? TF_LOADOUT_SLOT_MELEE : TF_LOADOUT_SLOT_PRIMARY);
		
		if (TF2_IsShieldEquipped(client))
		{
			iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
		}
		else
		{
			int secondary = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
			int weaponID = secondary != -1 ? TF2Util_GetWeaponID(secondary) : -1;
			
			switch (weaponID)
			{
				case TF_WEAPON_JAR, TF_WEAPON_JAR_MILK, TF_WEAPON_BUFF_ITEM, TF_WEAPON_JAR_GAS:
				{
					//Secondary items that have some use
					iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
				}
				case TF_WEAPON_PIPEBOMBLAUNCHER:
				{
					//If we don't have an actual primary, then we rely on our secondary
					if (bDemoKnight)
						iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
				}
			}
		}
	}

	for (int i = 0; i < iArraySlots.Length; i++)
	{
		int slot = iArraySlots.Get(i);
	
		for (int index = 0; index < MAX_UPGRADES; index++)
		{
			CMannVsMachineUpgrades upgrades = CMannVsMachineUpgradeManager().GetUpgradeByIndex(index);
			
			if (upgrades.m_iUIGroup() == UIGROUP_UPGRADE_ATTACHED_TO_PLAYER && slot != -1) 
				continue;
			
			CEconItemAttributeDefinition attr = CEIAD_GetAttributeDefinitionByName(upgrades.m_szAttribute());
			if (attr.Address == Address_Null)
				continue;
			
			if (!CanUpgradeWithAttrib(client, slot, attr.GetIndex(), upgrades.Address))
				continue;
			
			JSONObject UpgradeInfo = new JSONObject();
			UpgradeInfo.SetInt("pclass", view_as<int>(TF2_GetPlayerClass(client)));
			UpgradeInfo.SetInt("slot", slot);
			UpgradeInfo.SetInt("index", index);
			UpgradeInfo.SetInt("random", GetRandomInt(MIN_INT, MAX_INT));
			UpgradeInfo.SetInt("priority", GetUpgradePriority(client, UpgradeInfo));
			
			CTFPlayerUpgrades[client].Push(UpgradeInfo);
			
			delete UpgradeInfo;
		}
	}
	
	delete iArraySlots;
	
	/*PrintToServer("Unsorted upgrades for #%d \"%N\": %i total\n", client, client, CTFPlayerUpgrades[client].Length);
	PrintToServer("%3s %4s %-5s %-8s\n", "#", "SLOT", "INDEX", "PRIORITY");
	
	for (int i = 0; i < CTFPlayerUpgrades[client].Length; i++) 
	{
		JSONObject UpgradeInfo = view_as<JSONObject>(CTFPlayerUpgrades[client].Get(i));
		
		PrintToServer("%3d %4d %-5d %-8d", i, UpgradeInfo.GetInt("slot"), UpgradeInfo.GetInt("index"), UpgradeInfo.GetInt("priority"));
		
		delete UpgradeInfo;
	}*/
	
	
	//NEW!
	JSONArray new_json = new JSONArray();
	/////
	
	while (CTFPlayerUpgrades[client].Length > 0)
	{	
		JSONObject mObj = view_as<JSONObject>(CTFPlayerUpgrades[client].Get(0));
		int minimum = mObj.GetInt("priority"); // arbitrary number in list
		
		//NEW!
		JSONObject tempObj = new JSONObject();
		tempObj.SetInt("pclass",   mObj.GetInt("pclass"));
		tempObj.SetInt("slot",     mObj.GetInt("slot"));
		tempObj.SetInt("index",    mObj.GetInt("index"));
		tempObj.SetInt("random",   mObj.GetInt("random"));
		tempObj.SetInt("priority", mObj.GetInt("priority"));
		/////
		
		delete mObj;
		
		for (int x = 0; x < CTFPlayerUpgrades[client].Length; x++)
		{
			JSONObject xObj = view_as<JSONObject>(CTFPlayerUpgrades[client].Get(x)); // arbitrary number in list
			
			if (xObj.GetInt("priority") > minimum)
			{
				minimum = xObj.GetInt("priority");
				
				//NEW!
				tempObj.SetInt("pclass",   xObj.GetInt("pclass"));
				tempObj.SetInt("slot",     xObj.GetInt("slot"));
				tempObj.SetInt("index",    xObj.GetInt("index"));
				tempObj.SetInt("random",   xObj.GetInt("random"));
				tempObj.SetInt("priority", xObj.GetInt("priority"));
				/////
			}

			delete xObj;
		}
		
		//NEW!
		new_json.Push(tempObj);
		delete tempObj;
		/////
		
		int index = FindPriorityIndex(CTFPlayerUpgrades[client], "priority", minimum);
		CTFPlayerUpgrades[client].Remove(index);
	}
    
	if (redbots_manager_debug_actions.BoolValue)
	{
		PrintToServer("\nPreferred upgrades for #%d \"%N\"\n", client, client);
		PrintToServer("%3s %4s %4s %5s %-64s\n", "#", "SLOT", "COST", "INDEX", "ATTRIBUTE");
	}
	
	for (int i = 0; i < new_json.Length; i++) 
	{
		JSONObject info = view_as<JSONObject>(new_json.Get(i));
		CTFPlayerUpgrades[client].Push(info);
		
		if (redbots_manager_debug_actions.BoolValue)
		{
			CMannVsMachineUpgradeManager manager = CMannVsMachineUpgradeManager();
			int cost = GetCostForUpgrade(manager.GetUpgradeByIndex(info.GetInt("index")).Address, info.GetInt("slot"), info.GetInt("pclass"), client);
			PrintToServer("%3d %4d %4d %5d %-64s", i, info.GetInt("slot"), cost, info.GetInt("index"), manager.GetUpgradeByIndex(info.GetInt("index")).m_szAttribute());
		}
		
		delete info;
	}
	
	delete new_json;
}

/* What a bot buys at the upgrade station, highest number first

Every upgrade it can afford is sorted by this and the top one is bought, so this function is the
whole of a bot's shopping. It used to return GetRandomInt(50, 100) for everything except a Spy's
knife, which is why a Heavy would buy jump height while its minigun stayed stock.

The bands:

  300+  the upgrade that is the reason to carry this exact weapon
  200+  the class's own damage, which for an Engineer is the sentry and for a Medic the medigun
  100+  keeping that damage going: clip, ammo, reload
   50+  worth having once the damage is bought
    0+  staying alive, which a bot that respawns every wave needs least
  -10   canteens, which a bot never learns to use well

Nothing here caps anything. CanUpgradeWithAttrib already refuses an upgrade at its ceiling, so a
maxed damage bonus falls through to the next line on its own.

The attribute strings are the ones in scripts/items/mvm_upgrades.txt. An upgrade this table has
not met is ranked at random between 50 and 100, which is what the mod did with every upgrade
before this existed.

That fallback is the point. A Team Fortress 2 update that renames an attribute, or a mission that
adds one, would otherwise give every upgrade the same number: the sort would then be stable rather
than sensible, and every bot would buy the same wrong thing in the same order forever. Ranking the
unknown at random degrades to the old behaviour one upgrade at a time instead, and leaves the ones
this table does know still ahead of the resistances */
int GetUpgradePriority(int client, JSONObject info)
{
	int slot = info.GetInt("slot");
	
	//A canteen is worth less to a bot than anything it can shoot with
	if (slot == TF_LOADOUT_SLOT_ACTION)
		return -10;
	
	CMannVsMachineUpgrades upgrade = CMannVsMachineUpgradeManager().GetUpgradeByIndex(info.GetInt("index"));
	
	//Nothing to rank it on, so rank it the way the mod used to rank everything
	if (upgrade.Address == Address_Null)
		return UnrankedUpgradePriority();
	
	char attribute[MAX_ATTRIBUTE_DESCRIPTION_LENGTH]; attribute = upgrade.m_szAttribute();
	
	if (attribute[0] == '\0')
		return UnrankedUpgradePriority();
	
	int priority = LoadoutUpgradePriority(client, slot, attribute);
	
	if (priority > 0)
		return priority;
	
	priority = ClassUpgradePriority(view_as<TFClassType>(info.GetInt("pclass")), slot, attribute);
	
	if (priority > 0)
		return priority;
	
	return GeneralUpgradePriority(attribute);
}

/* The upgrade that is the reason to carry this weapon at all, by item definition index

Zero when the weapon in that slot has no opinion, which is most of them: this only names the few
where the loadout, not the class, decides what to buy first */
static int LoadoutUpgradePriority(int client, int slot, const char[] attribute)
{
	if (slot < TF_LOADOUT_SLOT_PRIMARY || slot > TF_LOADOUT_SLOT_MELEE)
		return 0;
	
	int weapon = GetPlayerWeaponSlot(client, slot);
	
	if (weapon < 1 || !HasEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
		return 0;
	
	switch (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
	{
		case 594: //Phlogistinator: its taunt fills from damage dealt, and all of its damage burns
		{
			if (StrEqual(attribute, "weapon burn dmg increased")) return 320;
			if (StrEqual(attribute, "weapon burn time increased")) return 300;
		}
		case 35: //Kritzkrieg: the crits are the weapon, so the meter is what matters
		{
			if (StrEqual(attribute, "ubercharge rate bonus")) return 330;
		}
		case 411: //Quick-Fix: it heals rather than saves, so it should heal faster
		{
			if (StrEqual(attribute, "healing mastery")) return 330;
			if (StrEqual(attribute, "ubercharge rate bonus")) return 300;
		}
		case 312: //Brass Beast: the damage minigun, and it cannot reposition to make up for less
		{
			if (StrEqual(attribute, "damage bonus")) return 320;
		}
		case 424: //Tomislav: it already fires fast, so damage per bullet beats more bullets
		{
			if (StrEqual(attribute, "damage bonus")) return 300;
		}
		case 752: //Hitman's Heatmaker: reach the shot sooner
		{
			if (StrEqual(attribute, "SRifle Charge rate increased")) return 300;
		}
		case 526: //Machina: every shot is a charged one, so damage rides on all of them
		{
			if (StrEqual(attribute, "damage bonus")) return 300;
		}
		case 996: //Loose Cannon: a faster cannonball is one a bot can actually land
		{
			if (StrEqual(attribute, "Projectile speed increased")) return 300;
		}
		case 997: //Rescue Ranger: every shot and every repair at range costs metal
		{
			if (StrEqual(attribute, "metal regen")) return 300;
			if (StrEqual(attribute, "maxammo metal increased")) return 290;
		}
	}
	
	return 0;
}

/* What this class contributes with, which is not always the weapon in its hands */
static int ClassUpgradePriority(TFClassType pclass, int slot, const char[] attribute)
{
	switch (pclass)
	{
		case TFClass_Engineer:
		{
			//The sentry is the damage. The shotgun only defends it
			if (StrEqual(attribute, "engy sentry fire rate increased")) return 320;
			if (StrEqual(attribute, "engy building health bonus")) return 260;
			if (StrEqual(attribute, "engy disposable sentries")) return 230;
			if (StrEqual(attribute, "metal regen")) return 220;
			if (StrEqual(attribute, "maxammo metal increased")) return 210;
			if (StrEqual(attribute, "engy dispenser radius increased")) return 90;
		}
		case TFClass_Medic:
		{
			//A Medic that shoots is a Medic not healing, so its own damage comes last
			if (StrEqual(attribute, "generate rage on heal")) return 320;
			if (StrEqual(attribute, "ubercharge rate bonus")) return 300;
			if (StrEqual(attribute, "healing mastery")) return 280;
			if (StrEqual(attribute, "uber duration bonus")) return 230;
			if (StrEqual(attribute, "overheal expert")) return 210;
			if (StrEqual(attribute, "damage bonus")) return 40;
			if (StrEqual(attribute, "fire rate bonus")) return 40;
		}
		case TFClass_Sniper:
		{
			//One shot through a line of robots, which is what a Sniper is for here
			if (StrEqual(attribute, "explosive sniper shot")) return 330;
			if (StrEqual(attribute, "SRifle Charge rate increased")) return 240;
		}
		case TFClass_Spy:
		{
			if (slot == TF_LOADOUT_SLOT_MELEE)
			{
				//A backstab through a giant's armour is the whole class in this mode
				if (StrEqual(attribute, "armor piercing")) return 330;
				if (StrEqual(attribute, "melee attack rate bonus")) return 280;
				if (StrEqual(attribute, "robo sapper")) return 240;
			}
		}
		case TFClass_Pyro:
		{
			//Reflecting what is aimed at the team beats burning a little harder
			if (StrEqual(attribute, "attack projectiles")) return 250;
			if (StrEqual(attribute, "weapon burn dmg increased")) return 240;
			if (StrEqual(attribute, "weapon burn time increased")) return 220;
		}
		case TFClass_Soldier:
		{
			if (StrEqual(attribute, "rocket specialist")) return 240;
		}
		case TFClass_Heavy:
		{
			//Shooting down the rockets aimed at the team
			if (StrEqual(attribute, "attack projectiles")) return 230;
		}
		case TFClass_Scout:
		{
			//Milk marks a wave for the whole team, which is worth more than what one Scout shoots
			if (StrEqual(attribute, "applies snare effect")) return 250;
			if (StrEqual(attribute, "mad milk syringes")) return 200;
			//Money is the Scout's job here and it needs the legs to do it
			if (StrEqual(attribute, "move speed bonus")) return 190;
		}
	}
	
	return 0;
}

/* Damage first, then what keeps it firing. What a bot buys when nothing above had an opinion */
static int GeneralUpgradePriority(const char[] attribute)
{
	//--- The damage itself
	if (StrEqual(attribute, "damage bonus")) return 260;
	if (StrEqual(attribute, "fire rate bonus")) return 250;
	if (StrEqual(attribute, "melee attack rate bonus")) return 200;
	if (StrEqual(attribute, "projectile penetration")) return 190;
	if (StrEqual(attribute, "projectile penetration heavy")) return 190;
	if (StrEqual(attribute, "critboost on kill")) return 180;
	
	//--- Keeping it firing
	if (StrEqual(attribute, "clip size upgrade atomic")) return 170;
	if (StrEqual(attribute, "clip size bonus upgrade")) return 170;
	if (StrEqual(attribute, "faster reload rate")) return 160;
	if (StrEqual(attribute, "maxammo primary increased")) return 150;
	if (StrEqual(attribute, "Projectile speed increased")) return 130;
	if (StrEqual(attribute, "maxammo secondary increased")) return 120;
	
	//--- Worth having once the damage is bought
	if (StrEqual(attribute, "heal on kill")) return 110;
	if (StrEqual(attribute, "mark for death")) return 90;
	if (StrEqual(attribute, "armor piercing")) return 85;
	if (StrEqual(attribute, "attack projectiles")) return 80;
	if (StrEqual(attribute, "increase buff duration")) return 75;
	if (StrEqual(attribute, "effect bar recharge rate increased")) return 70;
	if (StrEqual(attribute, "charge recharge rate increased")) return 70;
	if (StrEqual(attribute, "generate rage on damage")) return 60;
	if (StrEqual(attribute, "bleeding duration")) return 55;
	
	//--- A bot respawns every wave, so staying alive is what it needs least
	if (StrEqual(attribute, "move speed bonus")) return 45;
	if (StrEqual(attribute, "health regen")) return 40;
	if (StrEqual(attribute, "dmg taken from bullets reduced")) return 35;
	if (StrEqual(attribute, "dmg taken from blast reduced")) return 35;
	if (StrEqual(attribute, "dmg taken from fire reduced")) return 30;
	if (StrEqual(attribute, "dmg taken from crit reduced")) return 30;
	if (StrEqual(attribute, "damage force reduction")) return 25;
	if (StrEqual(attribute, "increased jump height")) return 10;
	
	return UnrankedUpgradePriority();
}

/* An upgrade no table above recognised

The mod's own answer for every upgrade, kept for the ones this file does not name. It has to
stay random: a constant would tie every unknown upgrade, and a tie is broken by whichever the
game listed first, so a bot would buy the same wrong thing every wave of every mission */
static int UnrankedUpgradePriority()
{
	return GetRandomInt(50, 100);
}

int FindPriorityIndex(JSONArray array, const char[] key, int value)
{
	int index = -1;
	
	for (int i = 0; i < array.Length; i++)
	{
		JSONObject iObj = view_as<JSONObject>(array.Get(i));
		if (value == iObj.GetInt(key))
		{
			index = i;
			
			delete iObj;
			break;
		}
		
		delete iObj;
	}
	
	return index;
}

void KV_MvM_UpgradesBegin(int client)
{
	m_nPurchasedUpgrades[client] = 0;

	KeyValues kv = new KeyValues("MvM_UpgradesBegin");
	FakeClientCommandKeyValues(client, kv);
	delete kv;
}

float GetUpgradeInterval()
{
	float customInterval = redbots_manager_bot_upgrade_interval.FloatValue;
	
	if (customInterval >= 0.0)
		return customInterval;
	
	//Upgrading during an active round, buy upgrades fast
	if (GameRules_GetRoundState() == RoundState_RoundRunning)
		return GetRandomFloat(0.1, 0.75);
	
	const float interval = 1.25;
	const float variance = 0.3;
	
	return GetRandomFloat(interval - variance, interval + variance);
}

JSONObject CTFBotPurchaseUpgrades_ChooseUpgrade(int actor)
{
	int currency = TF2_GetCurrency(actor);
	
	CollectUpgrades(actor);
	
	for (int i = 0; i < CTFPlayerUpgrades[actor].Length; i++) 
	{
		JSONObject info = view_as<JSONObject>(CTFPlayerUpgrades[actor].Get(i));
		
		CMannVsMachineUpgrades upgrades = CMannVsMachineUpgradeManager().GetUpgradeByIndex(info.GetInt("index"));
		if (upgrades.Address == Address_Null)
		{
			if (redbots_manager_debug_actions.BoolValue)
				PrintToServer("CMannVsMachineUpgrades is NULL");
			
			delete info;
			return null;
		}
		
		char attrib[MAX_ATTRIBUTE_DESCRIPTION_LENGTH]; attrib = upgrades.m_szAttribute();
		CEconItemAttributeDefinition attr = CEIAD_GetAttributeDefinitionByName(attrib);
		if (attr.Address == Address_Null)
			continue;
		
		int iAttribIndex = attr.GetIndex();
		if (!CanUpgradeWithAttrib(actor, info.GetInt("slot"), iAttribIndex, upgrades.Address))
		{
			//PrintToServer("upgrade %d/%d: cannot be upgraded with", info.GetInt("slot"), info.GetInt("index"));
			delete info;
			continue;
		}
		
		int iCost = GetCostForUpgrade(upgrades.Address, info.GetInt("slot"), info.GetInt("pclass"), actor);
		if (iCost > currency)
		{
			//PrintToServer("upgrade %d/%d: cost $%d > $%d", info.GetInt("slot"), info.GetInt("index"), iCost, currency);
			
			delete info;
			continue;
		}
	
		int tier = GetUpgradeTier(info.GetInt("index"));
		if (tier != 0) 
		{
			if (!IsUpgradeTierEnabled(actor, info.GetInt("slot"), tier))
			{
				//PrintToServer("upgrade %d/%d: tier %d isn't enabled", info.GetInt("slot"), info.GetInt("index"), tier);
				
				delete info;
				continue;
			}
		}
		
		return info;
	}
	
	return null;
}

void CTFBotPurchaseUpgrades_PurchaseUpgrade(int actor, JSONObject info)
{
	KV_MVM_Upgrade(actor, 1, info.GetInt("slot"), info.GetInt("index"));
	++m_nPurchasedUpgrades[actor];
}

void KV_MVM_Upgrade(int client, int count, int slot, int index)
{
	KeyValues kv = new KeyValues("MVM_Upgrade");
	kv.JumpToKey("upgrade", true);
	kv.SetNum("itemslot", slot);
	kv.SetNum("upgrade", index);
	kv.SetNum("count", count);
	FakeClientCommandKeyValues(client, kv);
	delete kv;
}

void KV_MvM_UpgradesDone(int client)
{
	KeyValues kv = new KeyValues("MvM_UpgradesDone");
	kv.SetNum("num_upgrades", m_nPurchasedUpgrades[client]);
	FakeClientCommandKeyValues(client, kv);
	delete kv;
}

void UpgradeMidRoundPostActivity(int client)
{
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_Medic:
		{
			int secondary = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
			
			if (secondary != -1)
				SetEntPropFloat(secondary, Prop_Send, "m_flChargeLevel", 1.0);
			
			SetEntPropFloat(client, Prop_Send, "m_flRageMeter", 100.0);
		}
	}
}