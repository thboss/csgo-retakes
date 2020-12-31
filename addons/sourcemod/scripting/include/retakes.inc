#if defined _retakes_included
  #endinput
#endif
#define _retakes_included

/**
 * Called right before players get put onto teams for the next round.
 * This is the best place to decide who goes onto what team if you want
 * to change the default behavior.
 *
 * @param rankingQueue a priority queue (see include/priorityqueue.inc)
 * @param waitingQueue a queue of the players waiting to join (see include/queue.inc)
 * @noreturn
 */
forward void Retakes_OnPreRoundEnqueue(ArrayList rankingQueue, ArrayList waitingQueue);

/**
 * Called after active players have been placed into the priority scoring queue
 * for the next round. This is a convenient place to change their scores by
 * editing the ranking priority queue itself.
 * (rather than using the Retakes_SetRoundPoints native)
 *
 * @param rankingQueue a priority queue (see include/priorityqueue.inc)
 * @param waitingQueue a queue of the players waiting to join (see include/queue.inc)
 * @noreturn
 */
forward void Retakes_OnPostRoundEnqueue(ArrayList rankingQueue, ArrayList waitingQueue);

/**
 * Called when the team sizes are set for the round.
 *
 * @param tCount the number of terrorists that will play the round
 * @param ctcount the number of counter-terrorists that will play the round
 * @noreturn
 */
forward void Retakes_OnTeamSizesSet(int& tCount, int& ctCount);

/**
 * Called when a team wins a round.
 *
 * @param winner the winning team (CS_TEAM_T or CS_TEAM_CT)
 * @param tPlayers an ArrayList of the players on the terrorist team
 * @param ctPlayers an ArrayList of the players on the counter-terrorist team
 * @noreturn
 */
forward void Retakes_OnRoundWon(int winner, ArrayList tPlayers, ArrayList ctPlayers);

/**
 * Called after teams have been determined for the round.
 *
 * @param tPlayers an ArrayList of the players on the terrorist team
 * @param ctPlayers an ArrayList of the players on the counter-terrorist team
 * @noreturn
 */
forward void Retakes_OnTeamsSet(ArrayList tPlayers, ArrayList ctPlayers);

/**
 * Returns if a player has joined the game, i.e., if they are on T/Ct or in the waiting queue.
 *
 * @param client a player
 * @return if the player has joined
 */
native bool Retakes_IsJoined(int client);

/**
 * Returns if a player is in the waiting queue.
 *
 * @param client a player
 * @return if the player is in the waiting queue
 */
native bool Retakes_IsInQueue(int client);

/**
 * Sends a retake formatted message to a client.
 *
 * @param client a player
 * @param format string message
 * @noreturn
 */
native void Retakes_Message(int client, const char[] format, any ...);

/**
 * Sends a retake formatted message to all clients.
 *
 * @param format string message
 * @noreturn
 */
native void Retakes_MessageToAll(const char[] format, any ...);

/**
 * Returns the number of terrorists for the current round.
 */
native int Retakes_GetNumActiveTs();

/**
 * Returns the number of terrorists for the current round.
 */
native int Retakes_GetNumActiveCTs();

/**
 * Returns the number of active players (t+ct) for the current round.
 */
native int Retakes_GetNumActivePlayers();

/**
 * Returns the round points for a client in the current round.
 */
native int Retakes_GetRoundPoints(int client);

/**
 * Sets the round points for a client in the current round.
 */
native int Retakes_SetRoundPoints(int client, int points);

/**
 * Changes the round points for a client in the current round.
 */
native void Retakes_ChangeRoundPoints(int client, int dp);

/**
 * Returns the total number of live rounds played on the current map.
 */
native int Retakes_GetRetakeRoundsPlayed();

/**
 * Returns if the game is currently in a warmup phase.
 */
native bool Retakes_InWarmup();

/**
 * Returns if the plugin is enabled.
 */
native bool Retakes_Enabled();

/**
 * Returns if the plugin is enabled and not in warmup.
 */
stock bool Retakes_Live() {
    return Retakes_Enabled() && !Retakes_InWarmup();
}

/**
 * Returns the maximum number of players allowed into the game.
 */
native int Retakes_GetMaxPlayers();

public SharedPlugin __pl_retakes = {
    name = "retakes",
    file = "retakes.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_retakes_SetNTVOptional() {
    MarkNativeAsOptional("Retakes_IsJoined");
    MarkNativeAsOptional("Retakes_IsInQueue");
    MarkNativeAsOptional("Retakes_Message");
    MarkNativeAsOptional("Retakes_MessageToAll");
    MarkNativeAsOptional("Retakes_GetNumActiveTs");
    MarkNativeAsOptional("Retakes_GetNumActiveCTs");
    MarkNativeAsOptional("Retakes_GetNumActivePlayers");
    MarkNativeAsOptional("Retakes_GetRoundPoints");
    MarkNativeAsOptional("Retakes_SetRoundPoints");
    MarkNativeAsOptional("Retakes_ChangeRoundPoints");
    MarkNativeAsOptional("Retakes_GetRetakeRoundsPlayed");
    MarkNativeAsOptional("Retakes_InWarmup");
    MarkNativeAsOptional("Retakes_Enabled");
    MarkNativeAsOptional("Retakes_GetMaxPlayers");
}
#endif
