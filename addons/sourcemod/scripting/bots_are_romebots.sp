#include <sourcemod>
#include <tf2items>
#include <tf2>
#include <tf2_stocks>
#include <readgamesounds>
#include <tf2attributes>
#include <sdkhooks>

#define VERSION "1.0"

#define MODEL_PATH "models/bots/"

#define PYROVISION (1<<0)
#define HALLOWEENVISION (1<<1)
#define ROMEVISION (1<<2)

new Handle:g_hGameConf;
new Handle:g_hEquipWearable;
new Handle:g_Cvar_Enabled;

new bool:g_bPlayerIsRobot[MAXPLAYERS+1];
new String:g_ClassNames[][] = { "unknown", "scout", "sniper", "soldier", "demo", "medic", "heavy", "pyro", "spy", "engineer" };
new g_ItemBase[] = {30161, 30153, 30155, 30157, 30143, 30149, 30147, 30151, 30159, 30145};
new Handle:g_ItemHandles[TFClassType][2];

new bool:g_bLate = false;

public Plugin:myinfo = 
{
	name = "[TF2] Bots are Romebots",
	author = "Powerlord",
	description = "Turns bots into Romebots",
	version = VERSION,
	url = ""
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	if (GetEngineVersion() != Engine_TF2)
	{
		strcopy(error, err_max, "This plugin only works on TF2.");
	}
	g_bLate = late;
}

public OnPluginStart()
{
	g_hGameConf = LoadGameConfigFile("tf2items.randomizer.txt");
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Virtual, "CTFPlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hEquipWearable = EndPrepSDKCall();
	
	CreateConVar("botsareromebots_version", VERSION, "Bots are Romebots version", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_PLUGIN|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("botsareromebots_enabled", "1.0", "Bots are Romebots is enabled", FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
//	HookEvent("player_spawn", Event_Player_Spawn);
	HookEvent("post_inventory_application", Event_Post_Inventory_Application);
	
	AddNormalSoundHook(RobotSoundHook);
}

public OnAllPluginsLoaded()
{
	// Initialize the item handles in advance
	for (new i = 1; i < sizeof(g_ItemHandles); i++)
	{
		for (new j = 1; j <= 2; j++)
		{
			g_ItemHandles[i][j] = TF2Items_CreateItem(OVERRIDE_ALL);
			TF2Items_SetClassname(g_ItemHandles[i][j], "tf_wearable");
			TF2Items_SetLevel(g_ItemHandles[i][j], 1);
			TF2Items_SetQuality(g_ItemHandles[i][j], 1);
			TF2Items_SetNumAttributes(g_ItemHandles[i][j], 0);
			TF2Items_SetItemIndex(g_ItemHandles[i][j], g_ItemBase[i] + (j - 1));
		}
	}
}

public OnConfigsExecuted()
{
	if (g_bLate && GetConVarBool(g_Cvar_Enabled))
	{
		for (new i = 1; i <= MaxClients; ++i)
		{
			if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i))
			{
				new TFClassType:class = TF2_GetPlayerClass(i);
				SetRobotModel(i, class);
				SetRobotBotCosmetics(i, class);
			}
		}
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_TakeDamage);
}

public OnClientDisconnect(client)
{
	g_bPlayerIsRobot[client] = false;
}

SetRobotModel(client, TFClassType:class)
{
	if (class == TFClass_Unknown)
	{
		return;
	}
	
	new String:model[PLATFORM_MAX_PATH];
	
	Format(model, sizeof(model), "bots/%s/bot_%s.mdl", g_ClassNames[class], g_ClassNames[class]);
	SetVariantString(model);
	AcceptEntityInput(client, "SetCustomModel");
	g_bPlayerIsRobot[client] = true;
}

SetRobotBotCosmetics(client, TFClassType:class)
{
	if (class == TFClass_Unknown)
	{
		return;
	}
	
	for (new j = 0; j < sizeof(g_ItemHandles[]); ++j)
	{
		new equipped = TF2Items_GiveNamedItem(client, g_ItemHandles[class][j]);
		if (equipped > MaxClients && IsValidEntity(equipped))
		{
			SDKCall(g_hEquipWearable, client, equipped);
		}
	}
}

//public Event_Player_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
public Event_Post_Inventory_Application(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarBool(g_Cvar_Enabled))
	{
		return;
	}
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (client == 0 || !IsClientInGame(client) || IsClientReplay(client) || IsClientSourceTV(client))
	{
		return;
	}
	
	//new TFClassType:class = TFClassType:GetEventInt(event, "class");
	new TFClassType:class = TF2_GetPlayerClass(client);
	
	if (class == TFClass_Unknown)
	{
		return;
	}
	
	if (IsFakeClient(client))
	{
		SetRobotModel(client, class);
		SetRobotBotCosmetics(client, class);
	}
	else
	{
		new visionFlags = 0;
		new Address:visionAddress = TF2Attrib_GetByName(client, "vision opt in flags");
		if (visionAddress != Address_Null)
		{
			visionFlags = RoundFloat(TF2Attrib_GetValue(visionAddress));
		}
		visionFlags |= ROMEVISION;
		TF2Attrib_SetByName(client, "vision opt in flags", float(visionFlags));
	}
}

public Action:Hook_TakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon,
		Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	if (!GetConVarBool(g_Cvar_Enabled) || victim < 1 || victim > MaxClients || !g_bPlayerIsRobot[victim])
	{
		return Plugin_Continue;
	}
	
	if (damagetype & DMG_BULLET && damage > 0)
	{
		EmitGameSoundToAll("MVM_Robot.BulletImpact", victim);
	}
	return Plugin_Continue;
}
		
public Action:RobotSoundHook(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
	if (!GetConVarBool(g_Cvar_Enabled) || entity <= 0 || entity > MaxClients || !g_bPlayerIsRobot[entity])
	{
		return Plugin_Continue;
	}
	
	if (StrContains(sample, "vo/", false) != -1)
	{
		ReplaceString(sample, sizeof(sample), "vo/", "vo/mvm/norm/");
		PrecacheSound(sample);
		return Plugin_Changed;
	}
	else if (StrContains(sample, "footsteps/", false) != -1)
	{
		if (GetGameSoundParams("MVM.BotStep", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			if (TF2_GetPlayerClass(entity) == TFClass_Medic)
			{
				return Plugin_Stop;
			}
			else
			{
				PrecacheSound(sample);
				return Plugin_Changed;
			}
		}
	}
	// Fall damage
	else if (StrContains(sample, "player/pl_fallpain", false) != -1)
	{
		if (GetGameSoundParams("MVM.FallDamageBots", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Pyro Axes
	else if (StrContains(sample, "weapons/axe_hit_flesh", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_FireAxe.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Third degree
	else if (StrContains(sample, "weapons\3rd_degree_hit_0", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_3rd_degree.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Sandman
	else if (StrContains(sample, "weapons/bat_baseball_hit_flesh", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_BaseballBat.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Spy knives
	else if (StrContains(sample, "weapons/blade_hit", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Knife.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Equalizer, Swords
	else if (StrContains(sample, "weapons/blade_slice_", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_PickAxe.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Bottle
	else if (StrContains(sample, "weapons/bottle_hit_flesh", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Bottle.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}	
	else if (StrContains(sample, "weapons/bottle_intact_hit_flesh", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Bottle.IntactHitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	else if (StrContains(sample, "weapons/bottle_broken_hit_flesh", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Bottle.BrokenHitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Generic melee (Kukri, Fist, Bonesaw, Wrench)
	else if (StrContains(sample, "weapons/cbar_hitbod", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Crowbar.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Stock bat
	else if (StrContains(sample, "weapons/bat_hit", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Bat.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	//Eviction Notice
	else if (StrContains(sample, "weapons\eviction_notice_0", false) != -1)
	{
		if (StrContains(sample, "crit", false) != -1)
		{
			if (GetGameSoundParams("MVM_EvictionNotice.ImpactCrit", channel, level, volume, pitch, sample, sizeof(sample), entity))
			{
				PrecacheSound(sample);
				return Plugin_Changed;
			}
		}
		else
		{
			if (GetGameSoundParams("MVM_EvictionNotice.Impact", channel, level, volume, pitch, sample, sizeof(sample), entity))
			{
				PrecacheSound(sample);
				return Plugin_Changed;
			}
		}
	}
	// Fists of Steel
	else if (StrContains(sample, "weapons/metal_gloves_hit_flesh", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_MetalGloves.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	else if (StrContains(sample, "weapons/metal_gloves_hit_crit", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_MetalGloves.CritHit", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	//Sharp Dresser
	else if (StrContains(sample, "weapons\\spy_assassin_knife_impact_", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Assassin_Knife.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	else if (StrContains(sample, "weapons\\spy_assassin_knife_bckstb", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Assassin_Knife.Backstab", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Huntsman / Crusader's Crossbow arrows
	else if (StrContains(sample, "weapons/fx/rics/arrow_impact_flesh", false) != -1)
	{
		if (GetGameSoundParams("MVM_Weapon_Arrow.ImpactFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	// Frying Pan
	else if (StrContains(sample, "weapons/pan/melee_frying_pan", false) != -1)
	{
		if (GetGameSoundParams("MVM_FryingPan.HitFlesh", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}