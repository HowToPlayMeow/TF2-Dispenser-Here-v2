#pragma semicolon 1;

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "2.0"
#define MAX_ENTITY 2048

public Plugin myinfo =
{
    name = "Dispenser Here v2",
    author = "svaugrasn, fixed HowToPlayMeow",
    description = "Spawn Model (dispenser/sentry/teleporter) when pressing voicemenu",
    version = PLUGIN_VERSION,
    url = ""
};

new LastUsed[MAXPLAYERS+1];            // Prevent Spam
new BuildingProp[MAXPLAYERS+1];        // Count the number of buildings created by players
new BlueprintProp[MAXPLAYERS+1];       // Count the number of Blueprints created by players
new PropOwner[MAX_ENTITY+1];           // Which entity belongs to which player

// List of Buildings and Blueprints per player
ArrayList g_ClientBuilding[MAXPLAYERS+1];
ArrayList g_ClientBlueprints[MAXPLAYERS+1];

ConVar g_building;
ConVar g_blueprint;
ConVar g_restriction;
ConVar g_remove;
ConVar g_limit;
ConVar g_flag;

public OnPluginStart()
{
    RegConsoleCmd("voicemenu", Command_Voicemenu);

    CreateConVar("sm_disp_version", PLUGIN_VERSION, "Version of Dispenser Here", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_building    = CreateConVar("sm_disp_building", "1", "Enable/Disable spawn the model building");
    g_blueprint   = CreateConVar("sm_disp_blueprint", "1", "Enable/Disable spawn the model blueprint");
    g_restriction = CreateConVar("sm_disp_time", "1", "Time between spawn the model");
    g_remove      = CreateConVar("sm_disp_remove", "10.0", "Time to remove the model");
    g_limit       = CreateConVar("sm_disp_limit", "1", "Building per person");
    g_flag        = CreateConVar("sm_disp_flag", "", "Admin flag required to use Dispenser Here");

    for (int i = 1; i <= MaxClients; i++)
    {
        g_ClientBuilding[i] = new ArrayList();
        g_ClientBlueprints[i] = new ArrayList();
    }
}

public OnMapStart()
{
    // precache model
    PrecacheModel("models/buildables/teleporter.mdl");
    PrecacheModel("models/buildables/dispenser_lvl3.mdl");
    PrecacheModel("models/buildables/sentry3.mdl");

    PrecacheModel("models/buildables/teleporter_blueprint_enter.mdl");
    PrecacheModel("models/buildables/dispenser_blueprint.mdl");
    PrecacheModel("models/buildables/sentry1_blueprint.mdl");

    // Reset all players' Buildings and Blueprints
    for (int i = 1; i <= MaxClients; i++)
    {
        BuildingProp[i] = 0;
        BlueprintProp[i] = 0;
    }

    // Prevent entity from being stuck, from the previous map
    for (int e = 0; e < sizeof(PropOwner); e++)
    {
        PropOwner[e] = 0;
    }
}

public Action Command_Voicemenu(int client, int args)
{
    if (IsClientInGame(client) && IsPlayerAlive(client))
    {
        // Players Press Voicemenu.
        char arg1[4], arg2[4];
        GetCmdArg(1, arg1, sizeof(arg1));
        GetCmdArg(2, arg2, sizeof(arg2));

        // Verify that this is desired voicemenu (Dispenser Here)
        if (StringToInt(arg1) == 1)
        {
            int type = StringToInt(arg2);
            if (type >= 3 && type <= 5)
            {
                // Call function Building / Blueprint
                Command_Prop(client, type - 3);
                return Plugin_Continue;
            }
        }
    }
    return Plugin_Continue;
}

public Action Command_Prop(int client, int args)
{
    // Prevent Spam
    int currentTime = GetTime();
    if (currentTime - LastUsed[client] < GetConVarInt(g_restriction)) return Plugin_Handled;
    LastUsed[client] = currentTime;

    // admin flag
    if (!CanUseDisp(client)) return Plugin_Handled;

    // Model Building / Blueprint
    char Prop_Model_Building[64];
    char Prop_Model_Blueprint[64];
    if (args == 0) // teleporter
    {
        strcopy(Prop_Model_Building, sizeof(Prop_Model_Building), "models/buildables/teleporter.mdl");
        strcopy(Prop_Model_Blueprint, sizeof(Prop_Model_Blueprint), "models/buildables/teleporter_blueprint_enter.mdl");
    }
    else if (args == 1) // dispenser
    {
        strcopy(Prop_Model_Building, sizeof(Prop_Model_Building), "models/buildables/dispenser_lvl3.mdl");
        strcopy(Prop_Model_Blueprint, sizeof(Prop_Model_Blueprint), "models/buildables/dispenser_blueprint.mdl");
    }
    else if (args == 2) // sentry
    {
        strcopy(Prop_Model_Building, sizeof(Prop_Model_Building), "models/buildables/sentry3.mdl");
        strcopy(Prop_Model_Blueprint, sizeof(Prop_Model_Blueprint), "models/buildables/sentry1_blueprint.mdl");
    }

    int team = GetClientTeam(client);     // Player Team
    int limit = GetConVarInt(g_limit);    // Limit number allowed

    if (GetConVarBool(g_building)) // sm_disp_building
    {
        if (limit > 0 && BuildingProp[client] >= limit)
        {
            // If it exceeds the limit, delete old building
            if (g_ClientBuilding[client].Length > 0)
            {
                int oldEnt = g_ClientBuilding[client].Get(0);
                g_ClientBuilding[client].Erase(0);
                if (IsValidEntity(oldEnt))
                {
                    PropOwner[oldEnt] = 0;
                    AcceptEntityInput(oldEnt, "Kill");
                }
                BuildingProp[client]--;
            }
        }

        // Spawn Building (prop_physics)
        int prop = CreateEntityByName("prop_physics_override");
        if (IsValidEntity(prop))
        {
            SetEntityModel(prop, Prop_Model_Building); // Model Building
            SetEntProp(prop, Prop_Send, "m_CollisionGroup", 1);
            SetEntProp(prop, Prop_Send, "m_usSolidFlags", 16);

            // Set colors by team
            if (team == 2) SetEntProp(prop, Prop_Send, "m_nSkin", 0);
            else if (team == 3) SetEntProp(prop, Prop_Send, "m_nSkin", 1);

            DispatchSpawn(prop); // Spawn entity

            // Spawn Building is positioned above the player's head and floats
            float pos[3], vel[3];
            GetClientAbsOrigin(client, pos);
            pos[2] += 30.0;
            vel[0] = vel[1] = 0.0; vel[2] = 500.0;
            TeleportEntity(prop, pos, NULL_VECTOR, vel);

            PropOwner[prop] = client; // Keep track of who owns it
            SDKHook(prop, SDKHook_SetTransmit, Prop_SetTransmit);

            // When time is up, sm_disp_remove calls RemoveEnt
            CreateTimer(GetConVarFloat(g_remove), RemoveEnt, EntIndexToEntRef(prop));

            BuildingProp[client]++;
            g_ClientBuilding[client].Push(prop);
        }
    }

    if (GetConVarBool(g_blueprint)) // sm_disp_blueprint
    {
        if (limit > 0 && BlueprintProp[client] >= limit)
        {
            // If it exceeds the limit, delete old building
            if (g_ClientBlueprints[client].Length > 0)
            {
                int oldEnt = g_ClientBlueprints[client].Get(0);
                g_ClientBlueprints[client].Erase(0);
                if (IsValidEntity(oldEnt))
                {
                    PropOwner[oldEnt] = 0;
                    AcceptEntityInput(oldEnt, "Kill");
                }
                BlueprintProp[client]--;
            }
        }

        // Spawn Blueprint (prop_dynamic)
        int prop2 = CreateEntityByName("prop_dynamic_override");
        if (IsValidEntity(prop2))
        {
            SetEntityModel(prop2, Prop_Model_Blueprint); // Model Blueprint

            // Set colors by team
            if (team == 2) SetEntProp(prop2, Prop_Send, "m_nSkin", 0);
            else if (team == 3) SetEntProp(prop2, Prop_Send, "m_nSkin", 1);

            DispatchSpawn(prop2); // Spawn entity

            // Spawn Blueprint at player position
            float pos2[3];
            GetClientAbsOrigin(client, pos2);
            TeleportEntity(prop2, pos2, NULL_VECTOR, NULL_VECTOR);

            PropOwner[prop2] = client; // Keep track of who owns it
            SDKHook(prop2, SDKHook_SetTransmit, Prop_SetTransmit);

            // When time is up, sm_disp_remove calls RemoveEnt
            CreateTimer(GetConVarFloat(g_remove), RemoveEnt, EntIndexToEntRef(prop2));

            BlueprintProp[client]++;
            g_ClientBlueprints[client].Push(prop2);
        }
    }

    return Plugin_Handled;
}

public Action RemoveEnt(Handle timer, any entid)
{
    int ent = EntRefToEntIndex(entid);
    if (ent > MaxClients && IsValidEntity(ent))
    {
        int owner = PropOwner[ent];
        if (owner > 0 && owner <= MaxClients)
        {
            // remove from list
            int idx = g_ClientBuilding[owner].FindValue(ent);
            if (idx != -1)
            {
                g_ClientBuilding[owner].Erase(idx);
                if (BuildingProp[owner] > 0) BuildingProp[owner]--;
            }
            else
            {
                idx = g_ClientBlueprints[owner].FindValue(ent);
                if (idx != -1)
                {
                    g_ClientBlueprints[owner].Erase(idx);
                    if (BlueprintProp[owner] > 0) BlueprintProp[owner]--;
                }
            }
        }
        PropOwner[ent] = 0;
        AcceptEntityInput(ent, "Kill"); // remove entity
    }
    return Plugin_Stop;
}

public Action Prop_SetTransmit(int entity, int client)
{
    if (!IsClientInGame(client)) return Plugin_Continue;

    // If you are not on the same team, you will not see it
    int skin = GetEntProp(entity, Prop_Send, "m_nSkin");
    int ownerTeam = (skin == 0) ? 2 : 3;

    if (GetClientTeam(client) != ownerTeam)
    {
        return Plugin_Handled; 
    }
    return Plugin_Continue;
}

// admin flag
bool CanUseDisp(int client)
{
    char flagStr[4];
    GetConVarString(g_flag, flagStr, sizeof(flagStr));

    // If there is no ConVar = default to everyone
    if (flagStr[0] == '\0')
    {
        return true;
    }

    // root
    if (GetUserFlagBits(client) & ADMFLAG_ROOT)
    {
        return true;
    }

    AdminFlag flag;
    if (FindFlagByChar(flagStr[0], flag))
    {
        AdminId id = GetUserAdmin(client);
        if (id != INVALID_ADMIN_ID)
        {
            return GetAdminFlag(id, flag);
        }
        return false;
    }

    return true; // If flag is incorrect = default to everyone
}
