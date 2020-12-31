#tryinclude "manual_version.sp"
#if !defined PLUGIN_VERSION
#define PLUGIN_VERSION "0.3.4"
#endif

#include <cstrike>
#include <smlib>

char g_ColorNames[][] = {"{NORMAL}", "{DARK_RED}", "{PURPLE}", "{GREEN}", "{MOSS_GREEN}", "{LIGHT_GREEN}", "{LIGHT_RED}", "{GRAY}", "{ORANGE}", "{LIGHT_BLUE}", "{DARK_BLUE}", "{PURPLE}"};
char g_ColorCodes[][] =    {"\x01",     "\x02",      "\x03",   "\x04",         "\x05",     "\x06",          "\x07",        "\x08",   "\x09",     "\x0B",         "\x0C",        "\x0E"};

/**
 * Switches a player to a new team.
 */
stock void SwitchPlayerTeam(int client, int team) {
    if (GetClientTeam(client) == team)
        return;

    g_PluginTeamSwitch[client] = true;
    if (team > CS_TEAM_SPECTATOR) {
        CS_SwitchTeam(client, team);
        CS_UpdateClientModel(client);
    } else {
        ChangeClientTeam(client, team);
    }
    g_PluginTeamSwitch[client] = false;
}

/**
 * Returns if the 2 players should be fighting each other.
 * Returns false on friendly fire/suicides.
 */
stock bool HelpfulAttack(int attacker, int victim) {
    if (!IsValidClient(attacker) || !IsValidClient(victim)) {
        return false;
    }
    int ateam = GetClientTeam(attacker); // Get attacker's team
    int vteam = GetClientTeam(victim);   // Get the victim's team
    return ateam != vteam && attacker != victim;
}

/**
 * Returns the Human counts of the T & CT Teams.
 * Use this function for optimization if you have to get the counts of both teams,
 */
stock void GetTeamsClientCounts(int &tHumanCount, int &ctHumanCount) {
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientConnected(client) && IsClientInGame(client)) {
            if (GetClientTeam(client) == CS_TEAM_T)
                tHumanCount++;

            else if (GetClientTeam(client) == CS_TEAM_CT)
                ctHumanCount++;
        }
    }
}

/**
 * Returns if a player is on an active/player team.
 */
stock bool IsOnTeam(int client) {
    int team = GetClientTeam(client);
    return (team == CS_TEAM_CT) || (team == CS_TEAM_T);
}

/**
 * Function to identify if a client is valid and in game.
 */
stock bool IsValidClient(int client) {
    if (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client))
        return true;
    return false;
}

/**
 * Function to identify if a client is valid and in game.
 */
stock bool IsPlayer(int client) {
    return IsValidClient(client) && !IsFakeClient(client);
}

/**
 * Applies colorized characters across a string to replace color tags.
 */
stock void Colorize(char[] msg, int size, bool strip=false) {
    for (int i = 0; i < sizeof(g_ColorNames); i ++) {
        if (strip) {
            ReplaceString(msg, size, g_ColorNames[i], "\x01");
        } else {
            ReplaceString(msg, size, g_ColorNames[i], g_ColorCodes[i]);
        }
    }
}