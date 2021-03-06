#pragma semicolon 1

/* SM Includes */
#include <sourcemod>
#include <socket>
#include <smac>
#undef REQUIRE_PLUGIN
#tryinclude <updater>

/* Plugin Info */
public Plugin:myinfo =
{
	name = "SMAC ESEA Global Banlist",
	author = SMAC_AUTHOR,
	description = "Kicks players on the E-Sports Entertainment banlist",
	version = SMAC_VERSION,
	url = "www.ESEA.net"
};

/* Globals */
#define UPDATE_URL	"http://smac.sx/updater/smac_esea_banlist.txt"

#define ESEA_HOSTNAME	"play.esea.net"
#define ESEA_QUERY		"index.php?s=support&d=ban_list&type=1&format=csv"

new Handle:g_hCvarKick = INVALID_HANDLE;
new Handle:g_hBanlist = INVALID_HANDLE;

/* Plugin Functions */
public OnPluginStart()
{
	LoadTranslations("smac.phrases");

	// Convars.
	g_hCvarKick = SMAC_CreateConVar("smac_esea_kick", "1", "Automatically kick players on the ESEA banlist.", FCVAR_NONE, true, 0.0, true, 1.0);

	// Initialize.
	g_hBanlist = CreateTrie();

	ESEA_DownloadBanlist();

#if defined _updater_included
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
#endif
}

public OnLibraryAdded(const String:name[])
{
#if defined _updater_included
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
#endif
}

public OnClientAuthorized(client, const String:auth[])
{
	if (IsFakeClient(client))
		return;

	// Workaround for universe digit change on L4D+ engines.
	decl String:sAuthID[MAX_AUTHID_LENGTH];
	FormatEx(sAuthID, sizeof(sAuthID), "STEAM_0:%s", auth[8]);

	decl bool:bShouldLog;

	if (GetTrieValue(g_hBanlist, sAuthID, bShouldLog) && SMAC_CheatDetected(client, Detection_GlobalBanned_ESEA, INVALID_HANDLE) == Plugin_Continue)
	{
		if (bShouldLog)
		{
			SMAC_PrintAdminNotice("%N | %s | ESEA Ban", client, sAuthID);
			SetTrieValue(g_hBanlist, sAuthID, 0);
		}

		if (GetConVarBool(g_hCvarKick))
		{
			if (bShouldLog)
			{
				SMAC_LogAction(client, "was kicked.");
			}

			KickClient(client, "%t", "SMAC_GlobalBanned", "ESEA", "www.ESEA.net");
		}
		else if (bShouldLog)
		{
			SMAC_LogAction(client, "is on the banlist.");
		}
	}
}

ESEA_DownloadBanlist()
{
	// Begin downloading the banlist in memory.
	new Handle:socket = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketSetOption(socket, ConcatenateCallbacks, 8192);
	SocketConnect(socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, ESEA_HOSTNAME, 80);
}

ESEA_ParseBan(String:baninfo[])
{
	if (baninfo[0] != '"')
		return;

	// Parse one line of the CSV banlist.
	decl String:sAuthID[MAX_AUTHID_LENGTH];

	new length = FindCharInString(baninfo[3], '"') + 9;
	FormatEx(sAuthID, length, "STEAM_0:%s", baninfo[3]);

	SetTrieValue(g_hBanlist, sAuthID, 1);
}

public OnSocketConnected(Handle:socket, any:arg)
{
	decl String:sRequest[256];

	FormatEx(sRequest,
		sizeof(sRequest),
		"GET /%s HTTP/1.0\r\nHost: %s\r\nCookie: viewed_welcome_page=1\r\nConnection: close\r\n\r\n",
		ESEA_QUERY,
		ESEA_HOSTNAME);

	SocketSend(socket, sRequest);
}

public OnSocketReceive(Handle:socket, String:data[], const size, any:arg)
{
	// Parse raw data as it's received.
	static bool:bParsedHeader, bool:bSplitData, String:sBuffer[256];
	new idx, length;

	if (!bParsedHeader)
	{
		// Parse and skip header data.
		if ((idx = StrContains(data, "\r\n\r\n")) == -1)
			return;

		idx += 4;

		// Skip the first line as well (column names).
		new offset = FindCharInString(data[idx], '\n');

		if (offset == -1)
			return;

		idx += offset + 1;
		bParsedHeader = true;
	}

	// Check if we had split data from the previous callback.
	if (bSplitData)
	{
		length = FindCharInString(data[idx], '\n');

		if (length == -1)
			return;

		length += 1;
		new maxsize = strlen(sBuffer) + length;

		if (maxsize <= sizeof(sBuffer))
		{
			Format(sBuffer, maxsize, "%s%s", sBuffer, data[idx]);
			ESEA_ParseBan(sBuffer);
		}

		idx += length;
		bSplitData = false;
	}

	// Parse incoming data.
	while (idx < size)
	{
		length = FindCharInString(data[idx], '\n');

		if (length == -1)
		{
			FormatEx(sBuffer, sizeof(sBuffer), "%s", data[idx]);

			bSplitData = true;
			return;
		}
		else if (length < sizeof(sBuffer))
		{
			length += 1;

			FormatEx(sBuffer, length, "%s", data[idx]);
			ESEA_ParseBan(sBuffer);

			idx += length;
		}
	}
}

public OnSocketDisconnected(Handle:socket, any:arg)
{
	CloseHandle(socket);

	// Check all players against the new list.
	decl String:sAuthID[MAX_AUTHID_LENGTH];

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientAuthorized(i) && GetClientAuthString(i, sAuthID, sizeof(sAuthID), false))
		{
			OnClientAuthorized(i, sAuthID);
		}
	}
}

public OnSocketError(Handle:socket, const errorType, const errorNum, any:arg)
{
	CloseHandle(socket);
}
