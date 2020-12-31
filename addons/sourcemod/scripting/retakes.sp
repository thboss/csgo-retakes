#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <smlib>

#include "include/priorityqueue.inc"
#include "include/queue.inc"
#include "include/retakes.inc"

#pragma semicolon 1
#pragma newdecls required


/***********************
 *                     *
 *   Global variables  *
 *                     *
 ***********************/

/**
 * The general way players are put on teams is using a system of
 * "round points". Actions during a round earn points, and at the end of the round,
 * players are put into a priority queue using their rounds as the value.
 */
#define POINTS_KILL 50
#define POINTS_DMG 1
#define POINTS_BOMB 50
#define POINTS_LOSS 5000


/** Client variable arrays **/
int g_RoundPoints[MAXPLAYERS+1];
bool g_PluginTeamSwitch[MAXPLAYERS+1];
int g_Team[MAXPLAYERS+1];

/** Queue Handles **/
ArrayList g_hWaitingQueue;
ArrayList g_hRankingQueue;

/** ConVar handles **/
ConVar g_EnabledCvar;
ConVar g_hAutoTeamsCvar;
ConVar g_hMaxPlayers;
ConVar g_hRatioConstant;
ConVar g_hRoundsToScramble;
ConVar g_hUseRandomTeams;

/** Win-streak data **/
bool g_ScrambleSignal;
int g_WinStreak;
int g_RoundCount;
bool g_HalfTime;

/** Per-round information about the player setup **/
int g_NumCT;
int g_NumT;
int g_ActivePlayers;

/** Forwards **/
Handle g_hOnPostRoundEnqueue;
Handle g_hOnPreRoundEnqueue;
Handle g_hOnTeamSizesSet;
Handle g_hOnTeamsSet;
Handle g_OnRoundWon;

#include "retakes/generic.sp"
#include "retakes/natives.sp"



/***********************
 *                     *
 * Sourcemod functions *
 *                     *
 ***********************/

public Plugin myinfo = {
    name = "CS:GO Retakes",
    author = "splewis",
    description = "CS:GO Retake practice",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/csgo-retakes"
};

public void OnPluginStart() {
    LoadTranslations("common.phrases");
    LoadTranslations("retakes.phrases");

    /** ConVars **/
    g_EnabledCvar = CreateConVar("sm_retakes_enabled", "1", "Whether the plugin is enabled");
    g_hAutoTeamsCvar = CreateConVar("sm_retakes_auto_set_teams", "1", "Whether retakes is allowed to automanage team balance");
    g_hMaxPlayers = CreateConVar("sm_retakes_maxplayers", "9", "Maximum number of players allowed in the game at once.", _, true, 2.0);
    g_hRatioConstant = CreateConVar("sm_retakes_ratio_constant", "0.425", "Ratio constant for team sizes.");
    g_hRoundsToScramble = CreateConVar("sm_retakes_scramble_rounds", "10", "Consecutive terrorist wins to cause a team scramble.");
    g_hUseRandomTeams = CreateConVar("sm_retakes_random_teams", "0", "If set to 1, this will randomize the teams every round.");

    /** Create/Execute retakes cvars **/
    AutoExecConfig(true, "retakes", "sourcemod/retakes");

    /** Command hooks **/
    AddCommandListener(Command_JoinTeam, "jointeam");

    /** Admin/editor commands **/
    RegAdminCmd("sm_scramble", Command_ScrambleTeams, ADMFLAG_CHANGEMAP, "Sets teams to scramble on the next round");
    RegAdminCmd("sm_scrambleteams", Command_ScrambleTeams, ADMFLAG_CHANGEMAP, "Sets teams to scramble on the next round");

    /** Event hooks **/
    HookEvent("player_connect_full", Event_PlayerConnectFull);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
    HookEvent("player_hurt", Event_DamageDealt);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("round_prestart", Event_RoundPreStart);
    HookEvent("round_freeze_end", Event_RoundFreezeEnd);
    HookEvent("bomb_defused", Event_Bomb);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("announce_phase_end", Event_HalfTime);

    g_hOnPostRoundEnqueue = CreateGlobalForward("Retakes_OnPostRoundEnqueue", ET_Ignore, Param_Cell, Param_Cell);
    g_hOnPreRoundEnqueue = CreateGlobalForward("Retakes_OnPreRoundEnqueue", ET_Ignore, Param_Cell, Param_Cell);
    g_hOnTeamSizesSet = CreateGlobalForward("Retakes_OnTeamSizesSet", ET_Ignore, Param_CellByRef, Param_CellByRef);
    g_hOnTeamsSet = CreateGlobalForward("Retakes_OnTeamsSet", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_OnRoundWon = CreateGlobalForward("Retakes_OnRoundWon", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

    g_hWaitingQueue = Queue_Init();
    g_hRankingQueue = PQ_Init();
}

public void OnMapStart() {
    PQ_Clear(g_hRankingQueue);
    Queue_Clear(g_hWaitingQueue);
    g_ScrambleSignal = false;
    g_WinStreak = 0;
    g_RoundCount = 0;
    g_HalfTime = false;
}

public void OnClientConnected(int client) {
    ResetClientVariables(client);
}

public void OnClientDisconnect(int client) {
    ResetClientVariables(client);
    CheckRoundDone();
}

/**
 * Helper functions that resets client variables when they join or leave.
 */
public void ResetClientVariables(int client) {
    Queue_Drop(g_hWaitingQueue, client);
    g_Team[client] = CS_TEAM_SPECTATOR;
    g_PluginTeamSwitch[client] = false;
    g_RoundPoints[client] = -POINTS_LOSS;
}

/***********************
 *                     *
 *    Command Hooks    *
 *                     *
 ***********************/

public Action Command_JoinTeam(int client, const char[] command, int argc) {
    if (!g_EnabledCvar.BoolValue || g_hAutoTeamsCvar.IntValue == 0) {
        return Plugin_Continue;
    }

    if (!IsValidClient(client) || argc < 1)
        return Plugin_Handled;

    char arg[4];
    GetCmdArg(1, arg, sizeof(arg));
    int team_to = StringToInt(arg);
    int team_from = GetClientTeam(client);

    // if same team, teamswitch controlled by the plugin
    // note if a player hits autoselect their team_from=team_to=CS_TEAM_NONE
    if ((team_from == team_to && team_from != CS_TEAM_NONE) || g_PluginTeamSwitch[client] || IsFakeClient(client)) {
        return Plugin_Continue;
    } else {
        // ignore switches between T/CT team
        if (   (team_from == CS_TEAM_CT && team_to == CS_TEAM_T )
            || (team_from == CS_TEAM_T  && team_to == CS_TEAM_CT)) {
            return Plugin_Handled;

        } else if (team_to == CS_TEAM_SPECTATOR) {
            // voluntarily joining spectator will not put you in the queue
            SwitchPlayerTeam(client, CS_TEAM_SPECTATOR);
            Queue_Drop(g_hWaitingQueue, client);

            // check if a team is now empty
            CheckRoundDone();

            return Plugin_Handled;
        } else {
            return PlacePlayer(client);
        }
    }
}

public Action Command_ScrambleTeams(int client, int args) {
    if (g_EnabledCvar.BoolValue) {
        g_ScrambleSignal = true;
        Retakes_MessageToAll("%t", "AdminScrambleTeams", client);
    }
}

/**
 * Generic logic for placing a player into the correct team when they join.
 */
public Action PlacePlayer(int client) {
    int tHumanCount=0, ctHumanCount=0, nPlayers=0;
    GetTeamsClientCounts(tHumanCount, ctHumanCount);
    nPlayers = tHumanCount + ctHumanCount;

    if (Retakes_InWarmup() && nPlayers < g_hMaxPlayers.IntValue) {
        return Plugin_Continue;
    }

    if (nPlayers < 2) {
        ChangeClientTeam(client, CS_TEAM_SPECTATOR);
        Queue_Enqueue(g_hWaitingQueue, client);
        CS_TerminateRound(0.0, CSRoundEnd_CTWin);
        return Plugin_Handled;
    }

    ChangeClientTeam(client, CS_TEAM_SPECTATOR);
    Queue_Enqueue(g_hWaitingQueue, client);
    Retakes_Message(client, "%t", "JoinedQueueMessage");
    return Plugin_Handled;
}



/***********************
 *                     *
 *     Event Hooks     *
 *                     *
 ***********************/

/**
 * Called when a player joins a team, silences team join events
 */
public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)  {
    if (!g_EnabledCvar.BoolValue) {
        return Plugin_Continue;
    }

    SetEventBool(event, "silent", true);
    return Plugin_Continue;
}

/**
 * Full connect event right when a player joins.
 * This sets the auto-pick time to a high value because mp_forcepicktime is broken and
 * if a player does not select a team but leaves their mouse over one, they are
 * put on that team and spawned, so we can't allow that.
 */
public Action Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast) {
    if (!g_EnabledCvar.BoolValue) {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    SetEntPropFloat(client, Prop_Send, "m_fForceTeam", 3600.0);
    return Plugin_Continue;
}

/**
 * Called when a player dies - gives points to killer, and does database stuff with the kill.
 */
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    if (!Retakes_Live()) {
        return Plugin_Continue;
    }

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    bool validAttacker = IsValidClient(attacker);
    bool validVictim = IsValidClient(victim);

    if (validAttacker && validVictim) {
        if (HelpfulAttack(attacker, victim)) {
            g_RoundPoints[attacker] += POINTS_KILL;
        } else {
            g_RoundPoints[attacker] -= POINTS_KILL;
        }
    }
    return Plugin_Continue;
}

/**
 * Called when a player deals damage to another player - ads round points if needed.
 */
public Action Event_DamageDealt(Event event, const char[] name, bool dontBroadcast) {
    if (!Retakes_Live()) {
        return Plugin_Continue;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    bool validAttacker = IsValidClient(attacker);
    bool validVictim = IsValidClient(victim);

    if (validAttacker && validVictim && HelpfulAttack(attacker, victim) ) {
        int damage = event.GetInt("dmg_PlayerHealth");
        g_RoundPoints[attacker] += (damage * POINTS_DMG);
    }
    return Plugin_Continue;
}

/**
 * Called when the bomb explodes or is defused, gives ponts to the one that planted/defused it.
 */
public Action Event_Bomb(Event event, const char[] name, bool dontBroadcast) {
    if (!Retakes_Live()) {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) {
        g_RoundPoints[client] += POINTS_BOMB;
    }
    return Plugin_Continue;
}

/**
 * Called when a player spawns.
 * Gives default weapons. (better than mp_ct_default_primary since it gives the player the correct skin)
 */
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    if (!g_EnabledCvar.BoolValue) {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || !IsOnTeam(client) || Retakes_InWarmup())
        return Plugin_Continue;

    SwitchPlayerTeam(client, g_Team[client]);
    return Plugin_Continue;
}

/**
 * Called before any other round start events. This is the best place to change teams
 * since it should happen before respawns.
 */
public Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast) {
    if (!Retakes_Live()) {
        return Plugin_Continue;
    }

    RoundEndUpdates();
    UpdateTeams();
    g_HalfTime = false;
    return Plugin_Continue;
}

/**
 * Round freezetime end, resets the round points and unfreezes the players.
 */
public Action Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
    if (!g_EnabledCvar.BoolValue) {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++) {
        g_RoundPoints[i] = 0;
    }
    return Plugin_Continue;
}

/**
 * Round end event, calls the appropriate winner (T/CT) unction and sets the scores.
 */
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    if (!Retakes_Live()) {
        return Plugin_Continue;
    }

    if (g_ActivePlayers >= 2) {
        g_RoundCount++;
        int winner = event.GetInt("winner");

        ArrayList ts = new ArrayList();
        ArrayList cts = new ArrayList();

        for (int i = 1; i <= MaxClients; i++) {
            if (IsPlayer(i)) {
                if (GetClientTeam(i) == CS_TEAM_CT)
                    cts.Push(i);
                else if (GetClientTeam(i) == CS_TEAM_T)
                    ts.Push(i);
            }
        }

        Call_StartForward(g_OnRoundWon);
        Call_PushCell(winner);
        Call_PushCell(ts);
        Call_PushCell(cts);
        Call_Finish();

        delete ts;
        delete cts;

        for (int i = 1; i <= MaxClients; i++) {
            if (IsPlayer(i) && GetClientTeam(i) != winner) {
                g_RoundPoints[i] -= POINTS_LOSS;
            }
        }

        if (winner == CS_TEAM_T) {
            TerroristsWon();
        } else if (winner == CS_TEAM_CT) {
            CounterTerroristsWon();
        }
    }
    return Plugin_Continue;
}

public Action Event_HalfTime(Event event, const char[] name, bool dontBroadcast)
{
    g_HalfTime = true;
}

/***********************
 *                     *
 *    Retakes logic    *
 *                     *
 ***********************/

/**
 * Called at the end of the round - puts all the players into a priority queue by
 * their score for placing them next round.
 */
public void RoundEndUpdates() {
    PQ_Clear(g_hRankingQueue);

    Call_StartForward(g_hOnPreRoundEnqueue);
    Call_PushCell(g_hRankingQueue);
    Call_PushCell(g_hWaitingQueue);
    Call_Finish();

    for (int client = 1; client <= MaxClients; client++) {
        if (IsPlayer(client) && IsOnTeam(client)) {
            PQ_Enqueue(g_hRankingQueue, client, g_RoundPoints[client]);
        }
    }

    while (!Queue_IsEmpty(g_hWaitingQueue) && PQ_GetSize(g_hRankingQueue) < g_hMaxPlayers.IntValue) {
        int client = Queue_Dequeue(g_hWaitingQueue);
        if (IsPlayer(client)) {
            PQ_Enqueue(g_hRankingQueue, client, -POINTS_LOSS);
        } else {
            break;
        }
    }

    if (g_hAutoTeamsCvar.IntValue == 0) {
        PQ_Clear(g_hRankingQueue);
    }

    Call_StartForward(g_hOnPostRoundEnqueue);
    Call_PushCell(g_hRankingQueue);
    Call_PushCell(g_hWaitingQueue);
    Call_Finish();
}

/**
 * Places players onto the correct team.
 * This assumes the priority queue has already been built (e.g. by RoundEndUpdates).
 */
public void UpdateTeams() {
    g_ActivePlayers = PQ_GetSize(g_hRankingQueue);
    if (g_ActivePlayers > g_hMaxPlayers.IntValue)
        g_ActivePlayers = g_hMaxPlayers.IntValue;

    g_NumT = RoundToNearest(g_hRatioConstant.FloatValue * float(g_ActivePlayers));
    if (g_NumT < 1)
        g_NumT = 1;

    g_NumCT = g_ActivePlayers - g_NumT;

    Call_StartForward(g_hOnTeamSizesSet);
    Call_PushCellRef(g_NumT);
    Call_PushCellRef(g_NumCT);
    Call_Finish();

    if (g_ScrambleSignal || g_hUseRandomTeams.IntValue != 0) {
        int n = g_hRankingQueue.Length;
        for (int i = 0; i < n; i++) {
            int value = GetRandomInt(1, 1000);
            g_hRankingQueue.Set(i, value, 1);
        }
        g_ScrambleSignal = false;
    }

    ArrayList ts = new ArrayList();
    ArrayList cts = new ArrayList();

    if (g_hAutoTeamsCvar.IntValue != 0) {
        // Ordinary team switching by retakes
        for (int i = 0; i < g_NumT; i++) {
            int client = PQ_Dequeue(g_hRankingQueue);
            if (IsValidClient(client)) {
                ts.Push(client);
            }
        }

        for (int i = 0; i < g_NumCT; i++) {
            int client = PQ_Dequeue(g_hRankingQueue);
            if (IsValidClient(client)) {
                cts.Push(client);
            }
        }
    } else {
        // Use the already set teams
        for (int i = 1; i <= MaxClients; i++) {
            if (IsValidClient(i)) {
                bool ct = GetClientTeam(i) == CS_TEAM_CT;
                bool t = GetClientTeam(i) == CS_TEAM_T;
                if ((ct && !g_HalfTime) || (t && g_HalfTime))
                    cts.Push(i);
                else if ((t && !g_HalfTime) || (ct && g_HalfTime))
                    ts.Push(i);
            }
        }
        g_NumCT = cts.Length;
        g_NumT = ts.Length;
        g_ActivePlayers = g_NumCT + g_NumT;
    }

    Call_StartForward(g_hOnTeamsSet);
    Call_PushCell(ts);
    Call_PushCell(cts);
    Call_Finish();

    for (int i = 0; i < ts.Length; i++) {
        int client = ts.Get(i);
        if (IsValidClient(client)) {
            SwitchPlayerTeam(client, CS_TEAM_T);
            g_Team[client] = CS_TEAM_T;
        }
    }

    for (int i = 0; i < cts.Length; i++) {
        int client = cts.Get(i);
        if (IsValidClient(client)) {
            SwitchPlayerTeam(client, CS_TEAM_CT);
            g_Team[client] = CS_TEAM_CT;
        }
    }

    // if somebody didn't get put in, put them back into the waiting queue
    while (!PQ_IsEmpty(g_hRankingQueue)) {
        int client = PQ_Dequeue(g_hRankingQueue);
        if (IsPlayer(client)) {
            Queue_EnqueueFront(g_hWaitingQueue, client);
        }
    }

    int length = Queue_Length(g_hWaitingQueue);
    for (int i = 0; i < length; i++) {
        int client = g_hWaitingQueue.Get(i);
        if (IsValidClient(client)) {
            Retakes_Message(client, "%t", "WaitingQueueMessage", g_hMaxPlayers.IntValue);
        }
    }

    delete ts;
    delete cts;
}

static bool ScramblesEnabled() {
    return g_hRoundsToScramble.IntValue >= 1;
}

public void TerroristsWon() {
    int toScramble = g_hRoundsToScramble.IntValue;
    g_WinStreak++;

    if (g_WinStreak >= toScramble) {
        if (ScramblesEnabled()) {
            g_ScrambleSignal = true;
            Retakes_MessageToAll("%t", "ScrambleMessage", g_WinStreak);
        }
        g_WinStreak = 0;
    } else if (g_WinStreak >= toScramble - 3 && ScramblesEnabled()) {
        Retakes_MessageToAll("%t", "WinStreakAlmostToScramble", g_WinStreak, toScramble - g_WinStreak);
    } else if (g_WinStreak >= 3) {
        Retakes_MessageToAll("%t", "WinStreak", g_WinStreak);
    }
}

public void CounterTerroristsWon() {
    if (g_WinStreak >= 3) {
        Retakes_MessageToAll("%t", "WinStreakOver", g_WinStreak);
    }

    g_WinStreak = 0;
}

void CheckRoundDone() {
    int tHumanCount=0, ctHumanCount=0;
    GetTeamsClientCounts(tHumanCount, ctHumanCount);
    if (tHumanCount == 0 || ctHumanCount == 0) {
        CS_TerminateRound(0.1, CSRoundEnd_TerroristWin);
    }
}

public int GetOtherTeam(int team) {
    return (team == CS_TEAM_CT) ? CS_TEAM_T : CS_TEAM_CT;
}