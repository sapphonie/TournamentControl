#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <color_literals>
#include <sdktools>
#include <tf2_stocks>
#undef REQUIRE_PLUGIN
#include <updater>

// what
#define NO  0
#define YES 1
#define RED 2
#define BLU 3
#define BOTH -1

#define PLUGIN_NAME         "[TF2] Tournament Control"
#define PLUGIN_AUTHOR       "stephanie"
#define PLUGIN_DESC         "Allows server admins to control tournament variables, like team readystate and team name."
#define PLUGIN_VERSION      "0.0.3"
#define PLUGIN_CONTACT      "https://steph.anie.dev/"

#define UPDATE_URL          "https://raw.githubusercontent.com/sapphonie/TournamentControl/master/updatefile.txt"

Handle g_hNoRace;

public Plugin myinfo =
{
    name                    = PLUGIN_NAME,
    author                  = PLUGIN_AUTHOR,
    description             = PLUGIN_DESC,
    version                 = PLUGIN_VERSION,
    url                     = PLUGIN_CONTACT
};

// shoutouts to https://github.com/VSES/SourceEngine2007/blob/master/se2007/game/shared/teamplayroundbased_gamerules.cpp

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */

public void OnPluginStart()
{
    RegAdminCmd("sm_rup", ForceRupState, ADMFLAG_SLAY, "Force ready up team in tournament mode.\nUsage: sm_rup <red/blu/all>");
    RegAdminCmd("sm_unrup", ForceRupState, ADMFLAG_SLAY, "Force un ready up teams in tournament mode.\nUsage: sm_unrup <red/blu/all>");
    RegAdminCmd("sm_renameteam", ForceRename, ADMFLAG_SLAY, "Force team name change in tournament mode.\nUsage: sm_renameteam <red/blu/all> <teamname>\nTeam names must be 6 chars or less!");
    RegAdminCmd("sm_renameteams", ForceRename, ADMFLAG_SLAY, "Force team name change in tournament mode.\nUsage: sm_renameteam <red/blu/all> <teamname>\nTeam names must be 6 chars or less!");
    // resets ready states on lateload
    ServerCommand("mp_tournament_restart");
    //CreateTimer(0.5, SpewInfo, _, TIMER_REPEAT); // debug
}

public void OnLibraryAdded(const char[] libname)
{
    if (StrEqual(libname, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public Action ForceRename(int client, int args)
{
    if (GameRules_GetProp("m_iRoundState") == 1 || GameRules_GetProp("m_iRoundState") == 3)
    {
        ReplyToCommand(client, "Can not touch tournament states in preround! Wait a couple seconds.");
        return Plugin_Handled;
    }
    // handle for sending events
    Handle g_eTourney = CreateEvent("tournament_stateupdate", true);
    // get args from trigger/sm command
    char arg1[32];
    char arg2[8];

    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    TrimString(arg2);
    StripQuotes(arg2);

    if (strlen(arg2) == 0 || strlen(arg2) > 6 || args >= 3)
    {
        ReplyToCommand(client, "Usage: sm_renameteam / sm_renameteams <red/blu/all> <teamname>\nNote that team names must be 6 chars or less and CANNOT contain spaces!");
    }
    else
    {
        // set up info to fire event
        // namechange events return readystate false regardless of what it actually is, they use a seperate event for rup/unrupping
        SetEventInt(g_eTourney, "readystate", NO);
        SetEventInt(g_eTourney, "userid", client);
        SetEventBool(g_eTourney, "namechange", true);
        SetEventString(g_eTourney, "newname", arg2);

        if (StrContains(arg1, "red") != -1)
        {
            SetConVarString(FindConVar("mp_tournament_redteamname"), arg2);
            FireEvent(g_eTourney);
            ReplyToCommand(client, "-> Renamed RED to '%s'.", arg2);
            PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force-changed team name of " ... COLOR_RED ... "RED " ... COLOR_WHITE ... "team to '" ... COLOR_RED ... "%s" ... COLOR_WHITE ... "'", client, arg2);

        }
        else if (StrContains(arg1, "blu") != -1)
        {
            SetConVarString(FindConVar("mp_tournament_blueteamname"), arg2);
            FireEvent(g_eTourney);
            ReplyToCommand(client, "-> Renamed BLU to '%s'.", arg2);
            PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force-changed team name of " ... COLOR_BLUE ... "BLU " ... COLOR_WHITE ... "team to '" ... COLOR_BLUE ... "%s" ... COLOR_WHITE ... "'", client, arg2);

        }
        else if (StrContains(arg1, "all") != -1 || StrContains(arg1, "both") != -1)
        {
            SetConVarString(FindConVar("mp_tournament_redteamname"), arg2);
            FireEvent(g_eTourney);
            g_eTourney = CreateEvent("tournament_stateupdate", true);
            // firing the event means we have to reset the handle
            // and set all the event info again
            SetConVarString(FindConVar("mp_tournament_blueteamname"), arg2);
            SetEventInt(g_eTourney, "readystate", NO);
            SetEventInt(g_eTourney, "userid", client);
            SetEventBool(g_eTourney, "namechange", true);
            SetEventString(g_eTourney, "newname", arg2);
            FireEvent(g_eTourney);
            ReplyToCommand(client, "-> Renamed ALL TEAMS to '%s'.", arg2);
            PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force-changed team name of " ... COLOR_MEDIUMPURPLE ... "BOTH " ... COLOR_WHITE ... "teams to '" ... COLOR_MEDIUMPURPLE ... "%s" ... COLOR_WHITE ... "'", client, arg2);
        }
    }
    return Plugin_Handled;
}

public Action ForceRupState(int client, int args)
{
    if (GameRules_GetProp("m_iRoundState") == 1 || GameRules_GetProp("m_iRoundState") == 3)
    {
        ReplyToCommand(client, "-> Can not touch tournament states in preround! Join a team or wait a couple seconds if players are on teams.");
        return Plugin_Handled;
    }
    // handle for sending events
    Handle g_eTourney = CreateEvent("tournament_stateupdate", true);
    // team color intbool
    int team;
    // rup state intbool
    int readystate;
    // get args from trigger/sm command
    char arg0[32];
    char arg1[32];
    // teamstate int
    int redstate;
    int bluestate;

    GetCmdArg(0, arg0, sizeof(arg0));
    GetCmdArg(1, arg1, sizeof(arg1));

    if (args >= 2 || strlen(arg1) < 3 || strlen(arg1) > 4 )
    {
        ReplyToCommand(client, "-> Usage: sm_rup / sm_unrup <red/blu/all>");
        return Plugin_Handled;
    }
    else
    {
        if (StrContains(arg0, "sm_rup") != -1)
        {
            if (StrContains(arg1, "red") != -1)
            {
                team = RED;
                ReplyToCommand(client, "-> Force-readied red team.");
                PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force readied up the " ... COLOR_RED ... "RED " ... COLOR_WHITE ... "team!", client);
            }
            else if (StrContains(arg1, "blu") != -1)
            {
                team = BLU;
                ReplyToCommand(client, "-> Force-readied blu team.");
                PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force readied up the " ... COLOR_BLUE ... "BLU " ... COLOR_WHITE ... "team!", client);
            }
            else if (StrContains(arg1, "all") != -1 || StrContains(arg1, "both") != -1)
            {
                team = BOTH;
                ReplyToCommand(client, "-> Force-readied ALL teams.");
                PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force readied up " ... COLOR_MEDIUMPURPLE ... "BOTH " ... COLOR_WHITE ... "teams!", client);
            }
            readystate = YES;
        }
        else if (StrContains(arg0, "sm_unrup") != -1)
        {
            if (StrContains(arg1, "red") != -1)
            {
                team = RED;
                ReplyToCommand(client, "-> Force-unreadied red team.");
                PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force unreadied the " ... COLOR_RED ... "RED " ... COLOR_WHITE ... "team!", client);
            }
            else if (StrContains(arg1, "blu") != -1)
            {
                team = BLU;
                ReplyToCommand(client, "-> Force-unreadied blu team.");
                PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force unreadied the " ... COLOR_BLUE ... "BLU " ... COLOR_WHITE ... "team!", client);

            }
            else if (StrContains(arg1, "all") != -1 || StrContains(arg1, "both") != -1)
            {
                team = BOTH;
                ReplyToCommand(client, "-> Force-unreadied ALL teams.");
                PrintColoredChatAll(COLOR_PALEGREEN ... "%N" ... COLOR_WHITE ... " force unreadied " ... COLOR_MEDIUMPURPLE ... "BOTH " ... COLOR_WHITE ... "teams!", client);
            }
            readystate = NO;
        }
        // set event info to fire later
        SetEventInt(g_eTourney, "userid", client);
        SetEventBool(g_eTourney, "namechange", false);
        SetEventInt(g_eTourney, "readystate", readystate);
        if (team == BOTH)
        {
            FireEvent(g_eTourney);
            GameRules_SetProp("m_bTeamReady", readystate, .element=RED);
            // firing the event means we have to reset the handle and set all the event info again
            g_eTourney = CreateEvent("tournament_stateupdate", true);
            SetEventInt(g_eTourney, "readystate", readystate);
            SetEventInt(g_eTourney, "userid", client);
            SetEventBool(g_eTourney, "namechange", false);
            GameRules_SetProp("m_bTeamReady", readystate, .element=BLU);
            FireEvent(g_eTourney);
        }
        else
        {
            GameRules_SetProp("m_bTeamReady", readystate, .element=team);
            FireEvent(g_eTourney);
        }

        redstate = GameRules_GetProp("m_bTeamReady", 1, .element=RED);
        bluestate = GameRules_GetProp("m_bTeamReady", 1, .element=BLU);

        if (redstate == YES && bluestate == YES)
        {
            delete g_hNoRace;
            g_hNoRace = CreateTimer(0.1, NoRaceConditionsHereLol, TIMER_FLAG_NO_MAPCHANGE);
        }
        else if (redstate == NO || bluestate == NO)
        {
            // resets countdown if active, fixes broken ready states
            GameRules_SetProp("m_bAwaitingReadyRestart", YES);
            GameRules_SetPropFloat("m_flRestartRoundTime", -1.0);
        }
    }
    return Plugin_Handled;
}

public Action NoRaceConditionsHereLol(Handle Timer)
{
    GameRules_SetProp("m_bAwaitingReadyRestart", NO);
    g_hNoRace = null;
}

//public Action SpewInfo(Handle Timer)
//{
//    new AwaitingReadyRestart    = GameRules_GetProp("m_bAwaitingReadyRestart");
//    new Float:RestartRoundTime  = GameRules_GetPropFloat("m_flRestartRoundTime");
//    new Float:MapResetTime      = GameRules_GetPropFloat("m_flMapResetTime");
//    new iRoundState             = GameRules_GetProp("m_iRoundState");
//    LogMessage("m_bAwaitingReadyRestart: %i", AwaitingReadyRestart);
//    LogMessage("m_flRestartRoundTime: %f", RestartRoundTime);
//    LogMessage("m_flMapResetTime: %f", MapResetTime);
//    LogMessage("m_iRoundState: %i", iRoundState);
//}