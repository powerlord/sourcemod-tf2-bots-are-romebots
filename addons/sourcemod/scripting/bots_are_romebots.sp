#include <sourcemod>
#include <tf2items>
#include <tf2>
#include <tf2_stocks>
#include <readgamesounds>

#define VERSION "1.0"

#define MODEL_PATH "models/bots/"

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
	g_Cvar_Enabled = CreateConVar("botsarerobots_enabled", "1.0", "Bots are Romebots is enabled", FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
	HookEvent("player_spawn", Event_Player_Spawn);
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

public Event_Player_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarBool(g_Cvar_Enabled))
	{
		return;
	}
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new TFClassType:class = TFClassType:GetEventInt(event, "class");
	
	if (IsClientInGame(client) && IsFakeClient(client) && class != TFClass_Unknown)
	{
		SetRobotModel(client, class);
		SetRobotBotCosmetics(client, class);
	}
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
		if (TF2_GetPlayerClass(entity) != TFClass_Medic && GetGameSoundParams("MVM.BotStep", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	else if (StrContains(sample, "player/pl_fallpain", false) != -1)
	{
		if (GetGameSoundParams("MVM.FallDamageBots", channel, level, volume, pitch, sample, sizeof(sample), entity))
		{
			PrecacheSound(sample);
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}