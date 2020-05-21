#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <ttt>

#pragma newdecls required

//the sound for the radiojammer
#define SOUND_JAMMER "ttt_clwo/Smoke Grenade Sound Effect.mp3"

int g_iActiveBoxes = 0;

enum struct PlayerData 
{
    int ClientBox;
    float BoxPosition[3];

    //bools
    bool InRange;
    bool foggedByBox;
    bool BoxStoppped;
    bool InRangeAllBoxes[MAXPLAYERS + 1];
    bool fogged;

    //timers
    Handle hBoxEnd;
    Handle hLoopSound;
}

PlayerData g_iPlayer[MAXPLAYERS + 1];

//plugin convars
ConVar g_cRangeEnabled = null;
ConVar g_cFogRange = null;
ConVar g_cCeaseTime = null;
 
public Plugin myinfo =
{
    name = "Black Box Of Death",
    author = "MarsTwix & C0rp3n",
    description = "This plugin fogs people who are in range, exclusive to the ones that are immune to the fog",
    version = "1.0.0",
    url = "clwo.eu"
};
 
public void OnPluginStart()
{
    g_cRangeEnabled = AutoExecConfig_CreateConVar("ttt_box_range_enable", "1", "Sets whether range of the radio jammer is enabled");
    g_cFogRange = AutoExecConfig_CreateConVar("ttt_box_mute_range", "1000", "The range within a player get fogged by the radio jammer");
    g_cCeaseTime = AutoExecConfig_CreateConVar("ttt_box_cease_time", "10.0", "The time the radio jammer stops working");
    RegConsoleCmd("sm_spawnbox", Command_SpawnBox, "Spawns a Black Box Of Death");
    HookEvent("round_prestart", Event_RoundStartPre, EventHookMode_Pre);
}

public void OnMapStart()
{
    PrecacheSound(SOUND_JAMMER);

    LoopClients(i)
    {
        SetFlag(g_iActiveBoxes, i, false);
        g_iPlayer[i].foggedByBox = false;
        g_iPlayer[i].BoxStoppped = false;
    }
}

public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
    AllClientReset();
}

public Action Event_RoundStartPre(Event event, const char[] name, bool dontBroadcast)
{
    AllClientReset();
}

Action Command_SpawnBox(int client, int args)
{
    CreateBox(client);
}

public void OnClientPutInServer(int client)
{
    g_iPlayer[client].hBoxEnd = INVALID_HANDLE;
    g_iPlayer[client].hLoopSound = INVALID_HANDLE;
    ClientReset(client);
}

//start spawning radiojammer
public void CreateBox(int client)
{
    char model[PLATFORM_MAX_PATH] = "models/props/cs_office/projector.mdl";
    DataPack data;

    LoopClients(i)
    {
        if (g_cRangeEnabled.BoolValue == true)
        {
            g_iPlayer[i].InRange = false;
        }
    }

    float vPos[3];
    GetClientAbsOrigin(client, vPos);

    if (!HasFlag(g_iActiveBoxes, client))
    {
        int entity = CreateEntityByName("prop_physics_multiplayer");

        PrecacheModel(model);  

        SetEntityModel(entity, model);
        SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
        SetEntityRenderColor(entity, 0, 0, 0);

        SetEntProp(entity, Prop_Send, "m_nSolidType", 6);

        SetEntProp(entity, Prop_Data, "m_takedamage", 2);
        SetEntProp(entity, Prop_Data, "m_iHealth", 1);
    
        DispatchKeyValue(entity, "Physics Mode", "1");

        g_iPlayer[client].ClientBox = entity;

        DispatchSpawn(entity);

        vPos[0] += 40.0;
        TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
        EmitSoundToAll(SOUND_JAMMER, entity);

        SetFlag(g_iActiveBoxes, client, true);
        g_iPlayer[client].BoxStoppped = false;
        g_iPlayer[client].BoxPosition = vPos;

        int SmokeIndex = CreateEntityByName("env_particlesmokegrenade" );
        SetEntProp(SmokeIndex, Prop_Send, "m_CurrentStage", 1);
        SetEntPropFloat(SmokeIndex, Prop_Send, "m_FadeStartTime", 0.0);
        SetEntPropFloat(SmokeIndex, Prop_Send, "m_FadeEndTime", (g_cCeaseTime.FloatValue+5.0));
        DispatchSpawn(SmokeIndex);
        ActivateEntity(SmokeIndex);
        TeleportEntity(SmokeIndex, g_iPlayer[client].BoxPosition, NULL_VECTOR, NULL_VECTOR);

        if (g_cRangeEnabled.BoolValue == false)
        {
            LoopValidClients(i)
            {
                if (IsPlayerAlive(i) /* && (!BaseComm_IsClientMuted(i) || SourceComms_GetClientMuteType(i) != bNot)*/)
                {
                    //SetClientListeningFlags(i, VOICE_MUTED);
                    g_iPlayer[i].foggedByBox = true;
                    PrintToChat(i, "You are fogged!");
                }
            }
        }   
        PrintToChatAll("There has been a radio jammer been placed!");

        g_iPlayer[client].hBoxEnd = CreateDataTimer(g_cCeaseTime.FloatValue, Timer_JammerEnd, data);
        data.WriteCell(client);
        data.WriteCell(entity);

        if (g_cCeaseTime.FloatValue > 28.0)
        {
            
            g_iPlayer[client].hLoopSound = CreateTimer(28.0, Timer_LoophLoopSound, entity, TIMER_REPEAT);
            
        }
    }
    else
    {
        PrintToChat(client, "You already have a mute jammer running!");
    }
}

//unmuting everybody again, when the radio got destroyed
public void OnEntityDestroyed(int entity)
{
    LoopClients(i)
    {
        if(g_iPlayer[i].ClientBox == entity && g_iPlayer[i].BoxStoppped == false)
        {
            TTT_ClearTimer(g_iPlayer[i].hBoxEnd);
            TTT_ClearTimer(g_iPlayer[i].hLoopSound);
            StopSound(entity, SNDCHAN_AUTO, SOUND_JAMMER);
            PrintToChatAll("The radio jammer has been destroyed!");
            SetFlag(g_iActiveBoxes, i, false);
            LoopValidClients(x)
            {
                if (g_iPlayer[x].foggedByBox == true && g_iActiveBoxes == 0)
                {
                    SetClientListeningFlags(x, VOICE_NORMAL);
                    g_iPlayer[x].foggedByBox = false;
                    PrintToChat(x, "You are unfogged!");
                }
            } 
        }
    }      
}

//if the radio survives an amount of time, it will unmute everybody again
public Action Timer_JammerEnd(Handle timer, DataPack data)
{
    int client;
    int entity;
    
    data.Reset();
    client = data.ReadCell();
    entity = data.ReadCell();

    TTT_ClearTimer(g_iPlayer[client].hLoopSound);

    PrintToChatAll("The jamming has been stopped!");
    SetFlag(g_iActiveBoxes, client, false);
    PrintToChatAll("test: %i", g_iActiveBoxes);
    StopSound(entity, SNDCHAN_AUTO, SOUND_JAMMER);
    g_iPlayer[client].BoxStoppped = true;
    LoopValidClients(i)
    {
        if (g_iPlayer[i].foggedByBox == true && g_iActiveBoxes == 0)
        {
            SetClientListeningFlags(i, VOICE_NORMAL);
            g_iPlayer[i].foggedByBox = false;
            PrintToChat(i, "You are unfogged!");
        }
    }
}

//checks if a client is in range and will mute the client
public void OnGameFrame()
{
    if (g_cRangeEnabled.BoolValue == true)
    {
        float cPos[3];
        LoopValidClients(y)
        {
            GetClientAbsOrigin(y, cPos);
            LoopValidClients(x)
            {
                if (HasFlag(g_iActiveBoxes, x))
                {
                    float Distance = GetVectorDistance(cPos, g_iPlayer[x].BoxPosition);
                    if (Distance <= g_cFogRange.IntValue)
                    {
                        g_iPlayer[y].InRangeAllBoxes[x] = true;
                    }

                    else if (Distance >= g_cFogRange.IntValue)
                    {
                        g_iPlayer[y].InRangeAllBoxes[x] = false;
                    }
                }
            }
        }
        LoopValidClients(a)
        {
            LoopValidClients(b)
            {
                if (g_iPlayer[a].InRangeAllBoxes[b] == true)
                {
                    g_iPlayer[a].InRange = true;
                    break;
                }

                else
                {
                    g_iPlayer[a].InRange = false;
                }
            }
        }

        LoopValidClients(i)
        {
            if (g_iPlayer[i].foggedByBox == false && IsPlayerAlive(i) && g_iPlayer[i].InRange == true /*&& !BaseComm_IsClientMuted(i)  && SourceComms_GetClientMuteType(i) != bNot*/ )
            {
                SetClientListeningFlags(i, VOICE_MUTED);
                g_iPlayer[i].foggedByBox = true;
                PrintToChat(i, "You are fogged!");
                PrintToChat(i, "You are in the range of the radio jammer!");
                break;
            }

            else if (g_iPlayer[i].foggedByBox == true && g_iPlayer[i].InRange == false && g_iPlayer[i].foggedByBox == true)
            {
                SetClientListeningFlags(i, VOICE_NORMAL);
                g_iPlayer[i].foggedByBox = false;
                PrintToChat(i, "You are unfogged!");
                PrintToChat(i, "You are out the range of the radio jammer!");
            }
        }
    }
}

//will keep the sound playing if the timer is longer than 28 seconds
public Action Timer_LoophLoopSound(Handle timer, int entity)
{
    EmitSoundToAll(SOUND_JAMMER, entity);
}

//If there is no range, this will unmute people if they've died
public Action TTT_OnClientDeathPre(int client)
{
    if (g_iPlayer[client].foggedByBox == true)
    {
        SetClientListeningFlags(client, VOICE_NORMAL);
        g_iPlayer[client].foggedByBox = false;
        PrintToChat(client, "You are unfogged!");
    }
}

void ClientReset(int client)
{
    //if (!BaseComm_IsClientMuted(i)/* || SourceComms_GetClientMuteType(i) != bNot*/)
    //{
    //  SetClientListeningFlags(i, VOICE_NORMAL);
    //}

    TTT_ClearTimer(g_iPlayer[client].hBoxEnd);
    TTT_ClearTimer(g_iPlayer[client].hLoopSound);

    g_iPlayer[client].foggedByBox = false;
    SetFlag(g_iActiveBoxes, client, false);
    g_iPlayer[client].BoxStoppped = true;
}

void AllClientReset()
{
    LoopValidClients(i)
    {
        //if (!BaseComm_IsClientMuted(i)/* || SourceComms_GetClientMuteType(i) != bNot*/)
        //{
        //SetClientListeningFlags(i, VOICE_NORMAL);
        //}

        TTT_ClearTimer(g_iPlayer[i].hBoxEnd);
        TTT_ClearTimer(g_iPlayer[i].hLoopSound);

        g_iPlayer[i].foggedByBox = false;
        SetFlag(g_iActiveBoxes, i, false);
        g_iPlayer[i].BoxStoppped = true;
    }
}

/*
~ MAYBE BEING USED IN THE FUTURE

void DestroyBox(int client)
{
    AcceptEntityInput(g_iPlayer[client].ClientBox, "Kill");

    ClientReset(client);

    StopSound(g_iPlayer[client].ClientBox, SNDCHAN_AUTO, SOUND_JAMMER);
    PrintToChatAll("The radio jammer has been Removed!");

}
*/

bool HasFlag(int flag, int index)
{
    return flag & (1 << index) != 0;
}

bool SetFlag(int &flag, int index, bool value)
{
    if (value)
    {
        flag |= (1 << index);
    }
    else
    {
        flag &= ~(1 << index);
    }
}

public int Native_CreateBox(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!TTT_IsClientValid(client))
    {
        PrintToServer("Invalid client (%d)", client);
        return;
    }
    CreateBox(client);
}
