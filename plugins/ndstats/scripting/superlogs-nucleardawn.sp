/**
 * HLstatsX Community Edition - SourceMod plugin to generate advanced weapon logging
 * http://www.hlxcommunity.com
 * Copyright (C) 2009 Nicholas Hastings (psychonic)
 * Copyright (C) 2007-2008 TTS Oetzel & Goerz GmbH
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#define NAME "SuperLogs: Nuclear Dawn"
#define VERSION "1.3"


#define MAX_LOG_WEAPONS 28
#define IGNORE_SHOTS_START 16
#define MAX_WEAPON_LEN 20

#define BUNKER_DAMAGE_TIMES 10

#define ND_TEAM_EMP 3
#define ND_TEAM_CT 2

int g_weapon_stats[MAXPLAYERS+1][MAX_LOG_WEAPONS][15];
new const String:g_weapon_list[MAX_LOG_WEAPONS][MAX_WEAPON_LEN] = {
									"avenger",
									"bag90",
									"chaingun",
									"daisy cutter",
									"f2000",
									"grenade launcher",
									"m95",
									"mp500",
									"mp7",
									"nx300",
									"p900",
									"paladin",
									"pp22",
									"psg",
									"shotgun",
									"sp5",
									"x01",
									"medpack",
									"armblade",
									"mine",
									"emp grenade",
									"p12 grenade",
									"remote grenade",
									"repair tool",
									"svr grenade",
									"u23 grenade",
									"armknives",
									"frag grenade"
								};

#include <loghelper>
#include <wstatshelper>


bool g_bReadyToShoot[MAXPLAYERS+1] = {false,...};
int g_iBunkerAttacked[2] = {0,...};
int counter = 0;
any:PRM;

public Plugin:myinfo = {
	name = NAME,
	author = "Peace-Maker",
	description = "Advanced logging. Generates auxilary logging for use with log parsers such as HLstatsX and Psychostats",
	version = VERSION,
	url = "http://www.hlxcommunity.com"
};


public OnPluginStart()
{
	CreatePopulateWeaponTrie();
	CreateConVar("ndixtats_version", VERSION, NAME, FCVAR_REPLICATED|FCVAR_NOTIFY);

	HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	HookEvent("promoted_to_commander", Event_PromotedToCommander);
	HookEvent("resource_captured", Event_ResourceCaptured);
	//HookEvent("structure_damage_sparse", Event_StructureDamageSparse);
	HookEvent("structure_death", Event_StructureDeath);
	HookEvent("player_team", Event_ChangeTeam);

	// wstats
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("round_win", Event_RoundWin);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	//HookEvent("commander_start_structure_build", Event_StructureBuild);
	//HookEvent("structure_built", Event_StructureBuild);

	GetTeams();
	// GetTeamName gets #ND_Consortium and #ND_Empire in release version -.-. Game logs with CONSORTIUM and EMPIRE translated
	strcopy(g_team_list[ND_TEAM_CT], sizeof(g_team_list[]), "CONSORTIUM");
	strcopy(g_team_list[ND_TEAM_EMP], sizeof(g_team_list[]), "EMPIRE");

}

public OnMapStart()
{
	GetTeams();
	// GetTeamName gets #ND_Consortium and #ND_Empire in release version -.-. Game logs with CONSORTIUM and EMPIRE translated
	strcopy(g_team_list[ND_TEAM_CT], sizeof(g_team_list[]), "CONSORTIUM");
	strcopy(g_team_list[ND_TEAM_EMP], sizeof(g_team_list[]), "EMPIRE");

	g_iBunkerAttacked[0] = 0;
	g_iBunkerAttacked[1] = 0;

	PRM = GetPlayerResourceEntity();
}

public OnEntityCreated(entity, const String:classname[]){
    if (strncmp(classname, "struct_", 7) == 0) {
        CreateTimer(0.1, LogStructureBuilt, entity);
        //SDKHook(entity, SDKHook_SpawnPost, CheckBorders);
    }
}

public Action:LogStructureBuilt(Handle timer, any entity)
{
	float pos[3];
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", pos);
	char position[196];

	char strModel[96];
	GetEntPropString(entity, Prop_Data, "m_iClassname", strModel, sizeof(strModel));
	Format(position, sizeof(position), " <%d> <%s> <%f %f %f>", entity, strModel, pos[0], pos[1], pos[2]);

	int team = GetEntProp(entity, Prop_Data, "m_iTeamNum");
	LogTeamEvent(team, "triggered", "structure_built", position);
}


/*
public OnClientPutInServer(client)
{
	g_bReadyToShoot[client] = false;
	SDKHook(client, SDKHook_TraceAttackPost, Hook_TraceAttackPost);
	SDKHook(client, SDKHook_PostThink, Hook_PostThink);
	SDKHook(client, SDKHook_PostThinkPost, Hook_PostThinkPost);
	reset_player_stats(client);
}
*/

public Action:Event_PlayerDeathPre(Handle event, const char[] name, bool dontBroadcast)
{
	int victim   = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	char weapon[MAX_WEAPON_LEN];
	GetEventString(event, "weapon", weapon, sizeof(weapon));

	if (attacker <= 0 || victim <= 0)
	{
		return Plugin_Continue;
	}

	// Which commander ability?!
	if(StrEqual(weapon, "commander ability"))
	{
		int damagebits = GetEventInt(event, "damagebits");
		if(damagebits & DMG_ENERGYBEAM)
		{
			Format(weapon, sizeof(weapon), "commander poison");
			SetEventString(event, "weapon", weapon);
		}
		else if(damagebits & DMG_BLAST)
		{
			Format(weapon, sizeof(weapon), "commander damage");
			SetEventString(event, "weapon", weapon);
		}
	}

	if(attacker != victim)
	{
		// Check if victim was commander?
		if(GameRules_GetPropEnt("m_hCommanders", ND_TEAM_CT-2) == victim || GameRules_GetPropEnt("m_hCommanders", ND_TEAM_EMP-2) == victim)
			LogPlayerEvent(attacker, "triggered", "killed_commander");
	}

	/*
	int weapon_index = get_weapon_index(weapon);
	if (weapon_index > -1)
	{
		g_weapon_stats[attacker][weapon_index][LOG_HIT_KILLS]++;
		g_weapon_stats[victim][weapon_index][LOG_HIT_DEATHS]++;
		if (GetClientTeam(attacker) == GetClientTeam(victim))
		{
			g_weapon_stats[attacker][weapon_index][LOG_HIT_TEAMKILLS]++;
		}
		dump_player_stats(victim, PRM);
	}
	*/


	LogKill(attacker, victim, weapon, true);
	return Plugin_Continue;
}

/*
public Hook_PostThink(client)
{
	if(!IsPlayerAlive(client))
		return;

	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(iWeapon == -1 || !IsValidEdict(iWeapon))
	{
		g_bReadyToShoot[client] = false;
		return;
	}

	char sWeapon[32];
	GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
	if(StrContains(sWeapon, "weapon_", false) != 0)
		return;

	float flNextAttackTime = GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack");
	if(flNextAttackTime <= GetGameTime() && GetEntProp(iWeapon, Prop_Send, "m_iClip1") > 0)
		g_bReadyToShoot[client] = true;
	else
		g_bReadyToShoot[client] = false;
}


public Hook_PostThinkPost(client)
{
	if(!IsPlayerAlive(client))
		return;

	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(iWeapon == -1 || !IsValidEdict(iWeapon))
		return;

	decl String:sWeapon[30];
	GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
	if(StrContains(sWeapon, "weapon_", false) != 0)
		return;

	ReplaceString(sWeapon, sizeof(sWeapon), "weapon_", "", false);
	FixWeaponLoggingName(sWeapon, sizeof(sWeapon));

	float flNextAttackTime = GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack");
	if(g_bReadyToShoot[client] && flNextAttackTime > GetGameTime())
	{
		new weapon_index = get_weapon_index(sWeapon);
		if (weapon_index > -1 && weapon_index < IGNORE_SHOTS_START)
		{
			g_weapon_stats[client][weapon_index][LOG_HIT_SHOTS]++;
		}
		g_bReadyToShoot[client] = false;
	}
}


public Hook_TraceAttackPost(victim, attacker, inflictor, float damage, damagetype, ammotype, hitbox, hitgroup)
{
	if(IsClientInGame(victim))
	{
		if(1 <= attacker <= MaxClients && IsClientInGame(attacker))
		{
			new iWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
			new String:sWeapon[64];
			if(iWeapon > 0)
				GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));

			ReplaceString(sWeapon, sizeof(sWeapon), "weapon_", "", false);
			FixWeaponLoggingName(sWeapon, sizeof(sWeapon));

			new weapon_index = get_weapon_index(sWeapon);

			// player_death
			if((GetClientHealth(victim) - RoundToCeil(damage)) < 0)
			{
				if (hitgroup == HITGROUP_HEAD)
				{
					LogPlayerEvent(attacker, "triggered", "headshot");
					if (weapon_index > -1)
						g_weapon_stats[attacker][weapon_index][LOG_HIT_HEADSHOTS]++;
				}
			}
			// player_hurt
			else
			{
				if (weapon_index > -1)
				{
					g_weapon_stats[attacker][weapon_index][LOG_HIT_HITS]++;
					g_weapon_stats[attacker][weapon_index][LOG_HIT_DAMAGE] += RoundToCeil(damage);
					if (hitgroup < 8)
					{
						g_weapon_stats[attacker][weapon_index][hitgroup + LOG_HIT_OFFSET]++;
					}
				}
			}
		}
	}
}
*/

public Event_PlayerSpawn(Handle event, const String:name[], bool dontBroadcast)
{
	// "userid"        "short"         // user ID on server

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0)
	{
		reset_player_stats(client);
	}
}

public Action:Event_PlayerDisconnect(Handle event, const String:name[], bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	OnPlayerDisconnect(client, PRM);
	return Plugin_Continue;
}

public Action:Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	char map[64];
	GetCurrentMap(map, sizeof(map));
	LogToGame("World triggered \"map_changed\" <%s>", map);
	LogToGame("World triggered \"round_start\"");

	int team = 0;
	LOOP_CLIENTS(client, CLIENTFILTER_INGAME | CLIENTFILTER_NOBOTS) {
		team = GetClientTeam(client);
		LogTeamChange(client, team);
	}

	return Plugin_Continue;
}

public Event_RoundWin(Handle event, const String:name[], bool dontBroadcast)
{
	int team = GetEventInt(event, "team");
	if(team >= 2)
	{
		LogTeamEvent(team, "triggered", "round_win");
		LogTeamEvent(GetOtherTeam(team), "triggered", "round_lose");
	}

	g_iBunkerAttacked[0] = 0;
	g_iBunkerAttacked[1] = 0;
	WstatsDumpAll(PRM);

	LogToGame("World triggered \"round_end\"");
	counter += 1;
}

public Event_PromotedToCommander(Handle event, const String:name[], bool dontBroadcast)
{
	LogPlayerEvent(GetClientOfUserId(GetEventInt(event, "userid")), "triggered", "promoted_to_commander");
}

public Event_ResourceCaptured(Handle event, const String:name[], bool dontBroadcast)
{
	int team = GetEventInt(event, "team");
	if(team >= 2) {
		LogTeamEvent(team, "triggered", "resource_captured");
	}
}

/*
public Event_StructureDamageSparse(Handle event, const String:name[], bool dontBroadcast)
{
	if(!GetEventBool(event, "bunker"))
		return;
	int team = GetEventInt(event, "ownerteam");
	if(team >= 2)
	{
		g_iBunkerAttacked[team-2]++;

		if(g_iBunkerAttacked[team-2] == BUNKER_DAMAGE_TIMES)
		{
			LogTeamEvent(GetOtherTeam(team), "triggered", "damaged_opposite_bunker");
			g_iBunkerAttacked[team-2] = 0;
		}
	}
}
*/

public Event_ChangeTeam(Handle event, const String:name[], bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int new_team = GetEventInt(event, "team");
	LogTeamChange(client, new_team);
}


public Event_StructureDeath(Handle event, const String:name[], bool dontBroadcast)
{
	int iEnt = GetEventInt(event, "entindex");
	int iAttacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if(iAttacker > 0 && iAttacker <= MaxClients && iEnt != -1 && IsValidEntity(iEnt))
	{
		char sBuffer[32];
		GetEdictClassname(iEnt, sBuffer, sizeof(sBuffer));

		if(StrEqual(sBuffer, "struct_armoury"))
		{
			LogPlayerEvent(iAttacker, "triggered", "armoury_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_artillery_explosion"))
		{
			LogPlayerEvent(iAttacker, "triggered", "artillery_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_assembler"))
		{
			LogPlayerEvent(iAttacker, "triggered", "assembler_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_flamethrower_turret"))
		{
			LogPlayerEvent(iAttacker, "triggered", "flamethrowerturret_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_fusion_reactor"))
		{
			LogPlayerEvent(iAttacker, "triggered", "wirelessrepeater_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_power_station"))
		{
			LogPlayerEvent(iAttacker, "triggered", "powerstation_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_radar"))
		{
			LogPlayerEvent(iAttacker, "triggered", "radar_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_power_relay"))
		{
			LogPlayerEvent(iAttacker, "triggered", "powerrelay_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_rocket_turret"))
		{
			LogPlayerEvent(iAttacker, "triggered", "rocketturret_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_sonic_turret"))
		{
			LogPlayerEvent(iAttacker, "triggered", "sonicturret_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_support_station"))
		{
			LogPlayerEvent(iAttacker, "triggered", "supply_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_transport_gate"))
		{
			LogPlayerEvent(iAttacker, "triggered", "transportgate_destroyed");
		}
		else if(StrEqual(sBuffer, "struct_machinegun_turret"))
		{
			LogPlayerEvent(iAttacker, "triggered", "machineguneturret_destroyed");
		}
	}
}

stock GetOtherTeam(team)
{
	if(team == 2)
		return 3;
	else if(team == 3)
		return 2;

	return team;
}

stock FixWeaponLoggingName(String:sWeapon[], maxlength)
{
	if(StrEqual(sWeapon, "daisycutter"))
		strcopy(sWeapon, maxlength, "daisy cutter");
	else if(StrEqual(sWeapon, "emp_grenade"))
		strcopy(sWeapon, maxlength, "emp grenade");
	else if(StrEqual(sWeapon, "frag_grenade"))
		strcopy(sWeapon, maxlength, "frag grenade");
	else if(StrEqual(sWeapon, "grenade_launcher"))
		strcopy(sWeapon, maxlength, "grenade launcher");
	else if(StrEqual(sWeapon, "p12_grenade"))
		strcopy(sWeapon, maxlength, "p12 grenade");
	else if(StrEqual(sWeapon, "remote_grenade"))
		strcopy(sWeapon, maxlength, "remote grenade");
	//else if(StrEqual(sWeapon, "repair_tool"))
	//	strcopy(sWeapon, maxlength, "repair tool");
	else if(StrEqual(sWeapon, "u23_grenade"))
		strcopy(sWeapon, maxlength, "u23 grenade");
}
