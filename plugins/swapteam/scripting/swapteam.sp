#include <sourcemod>
#include <sdktools_functions>
#pragma semicolon 1

#define PLUGIN_VERSION "1.2"

public Plugin:myinfo =
{
	name = "Team Swap",
	author = "Stevo.TVR",
	description = "Swaps players' team",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org/"
}


public OnPluginStart()
{
	CreateConVar("sm_teamswap_version", PLUGIN_VERSION, "Team Swap version", FCVAR_REPLICATED|FCVAR_NOTIFY);
	RegAdminCmd("sm_teamswap", CommandTeamSwap, ADMFLAG_KICK, "Swaps player's team");
	RegAdminCmd("sm_swap", CommandTeamSwap, ADMFLAG_KICK, "Swaps player's team");
	RegAdminCmd("sm_swapteam", CommandTeamSwap, ADMFLAG_KICK, "Swaps player's team");
	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");
}

public Action:CommandTeamSwap(client, args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_teamswap <#userid|name>");
		return Plugin_Handled;
	}

	new String:target[64], String:target_name[MAX_TARGET_LENGTH];
	new targetArray[MAXPLAYERS];
	new numtargets;
	new bool:tn_is_ml;

	GetCmdArg(1, target, sizeof(target));

	numtargets = ProcessTargetString(target, client, targetArray, MAXPLAYERS, 0, target_name, sizeof(target_name), tn_is_ml);

	if(numtargets <= 0)
	{
		ReplyToTargetError(client, numtargets);
		return Plugin_Handled;
	}

	for(new i = 0; i < numtargets; i++)
	{
		if(IsClientInGame(targetArray[i]))
			switchPlayerTeam(client, targetArray[i]);
	}
	return Plugin_Handled;
}

public switchPlayerTeam(client, target)
{
	LogAction(client, target, "\"%L\" swapped team of \"%L\"", client, target);
	ShowActivity(client, "swapped team of %N", target);
	new team = GetClientTeam(target);

	if (team == 2 || team == 3) {
		ChangeClientTeam(target, (5 - team));
	}

	DispatchSpawn(target);
}
