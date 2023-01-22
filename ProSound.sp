#include <sourcemod>
#include <sdktools>
#include <ProSound.inc>

#undef REQUIRE_PLUGIN
#include <pro_xp/ProXP.inc>
#define REQUIRE_PLUGIN

public Plugin myinfo = { name = "Pro Sounds", author = "Vishus", description = "Custom sounds - without needing to download on server join, and with rate limiting.", version = "0.1.0", url = "" };


/* CVARS

pro_sound_url
    Base url for sounds.  Leave blank to specify full url in database entries, otherwise sound file will be appened to this url (make sure to include a / at the end!)
    default: ""

pro_sound_rate_limiting_enabled
    default: "1"

pro_sound_rate_limit
    Minimum number of seconds between playing one sound and when another sound can be played
    default: "3.0"

pro_sound_max_sounds_per_interval
    Maximum number of sounds that can be played during an interval
    default: "10"

pro_sound_max_points_per_interval
    Maximum number of points (annoyingness factor) that can be played during an interval
    default: "10"

pro_sound_sound_interval
    Length of of interval in seconds
    default: "60"

 */



// used to output a list of sounds to chat - seems to look best to me
#define MAX_LINE_LEN 106


enum struct SoundKV {
    // unique sound id from the database
    int id;
    // command name (without ! or /)
    char command[32];
    // path to sound file
    char sound[256];
    // if ProXP is enabled this field is used to indicate minimum required level to play this sound (otherwise this field is ignored)
    int xplvl;
    // if KIC plugin is enabled and active this field is used to indicate whether this sound can be played (otherwise this field is ignored)
    int kic;
    // volume field is no longer used
    float volume;
    // the cost field is reserved for future use, but not currently used
    int cost;
    // annoyingness factor - used for rate limiting to prevent over-spamming annoying sounds
    int rate_points;
    // whether to register the sound as a command
    bool register_cmd;
}

ConVar cv_rate_limit;
ConVar cv_max_sounds_per_interval;
ConVar cv_max_points_per_interval;
ConVar cv_sound_interval;
ConVar cv_rate_limiting;
ConVar cv_sound_url;
ConVar cv_kic;

ArrayList sounds; // all of the available sounds
ArrayList soundsnewest; // sounds sorted by newest first
ArrayList sound_list; // a list of the sound command names - used for the !soundlist command
StringMap sound_cmds; // maps a sound command name to an index in the sounds array

Database SoundDB;


// used internally to determine whether sounds can be played or if rate limiting is in effect
bool can_play_sounds = true;

// variables used to track rate limiting
int sounds_played = 0;
int sound_points = 0;

// format string for the sound url
char sound_url_fmt[256];

// whether ProXP is installed and currently loaded
bool pro_xp = false;

/* CVAR CACHING */
bool rate_limiting_enabled = true;  // pro_sound_rate_limiting
float rate_limit;                   // pro_sound_rate_limit
int max_sounds_per_interval;        // pro_sound_max_sounds_per_interval
int max_points_per_interval;        // pro_sound_max_points_per_interval
float sound_interval;               // pro_sound_sound_interval



public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    RegPluginLibrary("pro_sound");
    CreateNative("ProSound_HasSound", Native_HasSound);
    CreateNative("ProSound_ShowSoundMenu", Native_ShowSoundMenu);
    CreateNative("ProSound_PlaySound", Native_PlaySound);
    CreateNative("ProSound_CheckSoundRateLimit", Native_CheckSoundRateLimit);
    return APLRes_Success;
}


public void OnPluginStart() {
    Database.Connect(DbConnCallback, "pro_sounds");
    
    sounds = new ArrayList(sizeof(SoundKV));
    sound_cmds = new StringMap();
    sound_list = new ArrayList(32);
    
    
    cv_sound_url = CreateConVar("pro_sound_url", "", "Base url for sounds.  Leave blank to specify full url in database entries, otherwise sound file will be appened to this url (make sure to include a / at the end!)");
    cv_rate_limiting = CreateConVar("pro_sound_rate_limiting_enabled", "1");
    cv_rate_limit = CreateConVar("pro_sound_rate_limit", "3.0", "Minimum number of seconds between playing one sound and when another sound can be played");
    cv_max_sounds_per_interval = CreateConVar("pro_sound_max_sounds_per_interval", "10", "Maximum number of sounds that can be played during an interval");
    cv_max_points_per_interval = CreateConVar("pro_sound_max_points_per_interval", "10", "Maximum number of points (annoyingness factor) that can be played during an interval");
    cv_sound_interval = CreateConVar("pro_sound_sound_interval", "60", "Length of of interval in seconds");
    
    rate_limiting_enabled = GetConVarBool(cv_rate_limiting);
    rate_limit = GetConVarFloat(cv_rate_limit);
    max_sounds_per_interval = GetConVarInt(cv_max_sounds_per_interval);
    max_points_per_interval = GetConVarInt(cv_max_points_per_interval);
    sound_interval = GetConVarFloat(cv_sound_interval);
    GetConVarString(cv_sound_url, sound_url_fmt, sizeof(sound_url_fmt));
    Format(sound_url_fmt, sizeof(sound_url_fmt), "%s%%s", sound_url_fmt);
    
    HookConVarChange(cv_rate_limiting, CvarChangedRateLimitEnabled);
    HookConVarChange(cv_rate_limit, CvarChangedRateLimit);
    HookConVarChange(cv_max_sounds_per_interval, CvarChangedMaxSoundsPerInterval);
    HookConVarChange(cv_max_points_per_interval, CvarChangedMaxPointsPerInterval);
    HookConVarChange(cv_sound_interval, CvarChangedSoundInterval);
    HookConVarChange(cv_sound_url, CvarChangedUrl);
    
    
    cv_kic = FindConVar("keep_it_clean");
    // if another plugin defines this use that, otherwise create a new convar
    if(!cv_kic) {
        cv_kic = CreateConVar("keep_it_clean", "0", "Whether Keep It Clean rules are in effect.  0=off 1=on");
    }
    
    
    RegConsoleCmd("say", Command_Say);
    RegConsoleCmd("say_team", Command_TeamSay);
    RegConsoleCmd("listsounds", Command_ListSounds);
    RegConsoleCmd("sounds", Command_SoundsMenu);
    RegConsoleCmd("newsounds", Command_NewSoundsMenu);
    
    RegAdminCmd("reloadsounds", Command_ReloadSounds, ADMFLAG_BAN, "Reload sounds from database");
    
}


public void OnAllPluginsLoaded() {
    pro_xp = LibraryExists("pro_xp");
}


public void OnLibraryRemoved(const char[] name) {
    if (StrEqual(name, "pro_xp")) {
        pro_xp = false;
    }
}


public void OnLibraryAdded(const char[] name) {
    if (StrEqual(name, "pro_xp")) {
        pro_xp = true;
    }
}


public void CvarChangedRateLimit(ConVar convar, const char[] oldValue, const char[] newValue) {
    rate_limit = GetConVarFloat(cv_rate_limit);
}


public void CvarChangedMaxSoundsPerInterval(ConVar convar, const char[] oldValue, const char[] newValue) {
    max_sounds_per_interval = GetConVarInt(cv_max_sounds_per_interval);
}


public void CvarChangedMaxPointsPerInterval(ConVar convar, const char[] oldValue, const char[] newValue) {
    max_points_per_interval = GetConVarInt(cv_max_points_per_interval);
}


public void CvarChangedSoundInterval(ConVar convar, const char[] oldValue, const char[] newValue) {
    sound_interval = GetConVarFloat(cv_sound_interval);
}


public void CvarChangedRateLimitEnabled(ConVar convar, const char[] oldValue, const char[] newValue) {
    if(StrEqual(newValue, "0")) {
        ResetRateLimits();
        rate_limiting_enabled = false;
    } else if(StrEqual(newValue, "1")) {
        rate_limiting_enabled = true;
    }
}


public void CvarChangedUrl(ConVar convar, const char[] oldValue, const char[] newValue) {
    int len = strlen(newValue);
    if(len > 0 && newValue[len-1] != '\0') {
        // sound_url is a format string so append an additional %s at the end for the placement of the sound name
        FormatEx(sound_url_fmt, sizeof(sound_url_fmt), "%s%%s", newValue);
    }
}


public Action Command_ReloadSounds(int client, int args) {
    LoadSounds(true);
    ReplyToCommand(client, "Sounds reloaded - %i entries", sounds.Length);
    return Plugin_Continue;
}


public void DbConnCallback(Database db, const char[] error, any data) {
    if(strlen(error) > 0 || db == null) {
        LogAction(-1, -1, "DbConnCallback: could not connect to sound database: %s", error);
        SetFailState("Could not connect to database");
        return;
    }
    SoundDB = db;
    LoadSounds(true);
}


public OnMapStart() {
    if(SoundDB != null) {
        LoadSounds(true);
    }
    ResetRateLimits();
}


public void LoadSounds(bool register_commands) {
    char query[] = "SELECT id, cmd, path, xp, kic, volume, cost, rate_points, register_cmd FROM pro_sounds WHERE enabled = 1 ORDER BY path";
    SoundDB.Query(CallbackLoadSounds, query, register_commands);
}


public void CallbackLoadSounds(Database db, DBResultSet result, const char[] error, bool register_commands) {
    if(result == null) {
        return;
    }
    sounds.Clear();
    sound_cmds.Clear();
    sound_list.Clear();
    char cmd[128];

    while(result.FetchRow()) {
        SoundKV cur_sound;
        cur_sound.id = result.FetchInt(0);
        result.FetchString(1, cur_sound.command, 128);
        result.FetchString(2, cur_sound.sound, 128);
        cur_sound.xplvl = result.FetchInt(3);
        cur_sound.kic = result.FetchInt(4);
        cur_sound.volume = result.FetchFloat(5);
        cur_sound.cost = result.FetchInt(6);
        cur_sound.rate_points = result.FetchInt(7);
        cur_sound.register_cmd = result.FetchInt(8) != 0;
        
        if(!PrecacheSound(cur_sound.sound, true)) {
            LogAction(-1, -1, "Failed to prefetch sound %s: %s", cur_sound.command, cur_sound.sound);
            continue;
        }
        
        sounds.PushArray(cur_sound);
        sound_cmds.SetValue(cur_sound.command, sounds.Length-1);
        sound_list.PushString(cur_sound.command);
        
        // if register_commands is true register a command for each sound - only registers the command if the command does not already exist
        if(register_commands && cur_sound.register_cmd) {
            Format(cmd, sizeof(cmd), "sm_%s", cur_sound.command);
            if(!CommandExists(cmd))
                RegConsoleCmd(cmd, SoundCommand);
        }
    }
    
    
    soundsnewest = sounds.Clone();
    soundsnewest.SortCustom(SortNewest);
    
    LogAction(-1, -1, "Sounds: loaded %i entries", sounds.Length);
}


// this is the main sound funciton to call.  returns false if rate limiting prevented the sound from playing
bool PlaySound(int client, const char[] sound_cmd) {
    int index = -1;
    if(sound_cmds.GetValue(sound_cmd, index)) {
            SoundKV cur_sound;
            if(index != -1 && index < sounds.Length && sounds.GetArray(index, cur_sound)) {
                int player_lvl;
                if(pro_xp) player_lvl = ProXP_GetPlayerLevel(client);
                if((rate_limiting_enabled && !CanPlaySound(cur_sound.rate_points)) || (pro_xp && cur_sound.xplvl > player_lvl)) {
                    SoundPlayFailReply(client, cur_sound.rate_points, cur_sound.xplvl);
                    return false;
                }

                char arg1[128];
                
                new Handle:setup = CreateKeyValues("data");
	
                KvSetString(setup, "title", "Musicspam");
                KvSetString(setup, "type", "2");
                Format(arg1,sizeof(arg1), sound_url_fmt, cur_sound.sound);
                KvSetString(setup, "msg", arg1);
                
                for (new i = 1; i <= MaxClients; i++)
                {
                    if (IsClientInGame(i) && !IsFakeClient(i))
                    {
                        ShowVGUIPanel(i, "info", setup, false); 
                    }
                }
                
                CloseHandle(setup);

                IncRateLimit(cur_sound.rate_points);
                return true;
            }
    }
    return false;
}


bool CanPlaySound(int rate_points) {
    return !rate_limiting_enabled || can_play_sounds && sound_points + rate_points <= max_points_per_interval;
}


void ResetRateLimits() {
    can_play_sounds = true;
    sounds_played = 0;
    sound_points = 0;
}


void IncRateLimit(int rate_points) {
    CreateTimer(rate_limit, TimerSingleRateLimit, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(sound_interval, TimerIntervalRateLimit, rate_points, TIMER_FLAG_NO_MAPCHANGE);
    sounds_played += 1;
    sound_points += rate_points;
    can_play_sounds = false;
}


public Action TimerSingleRateLimit(Handle timer) {
    CheckRateLimit();
    return Plugin_Continue;
}


public Action TimerIntervalRateLimit(Handle timer, int rate_points) {
    sounds_played -= 1;
    sound_points -= rate_points;
    CheckRateLimit();
    return Plugin_Continue;
}


void CheckRateLimit() {
    if(sounds_played < max_sounds_per_interval) {
        can_play_sounds = true;
    }
}


public void SoundPlayFailReply(int client, int rate_points, int level_required) {
    int player_level;
    if(pro_xp) player_level = ProXP_GetPlayerLevel(client);
    if(pro_xp && level_required > player_level) {
        ReplyToCommand(client, "You need to be level %i to play this sound", level_required);
    } else if(sounds_played == max_sounds_per_interval) {
        ReplyToCommand(client, "Only %i sounds can be played every %.1f seconds", max_sounds_per_interval, sound_interval);
    } else if(sound_points + rate_points > max_points_per_interval) {
        ReplyToCommand(client, "Too many loud or \"annoying\" sounds have been played; try again later.  Or don't.");
    } else {
        ReplyToCommand(client, "Sounds can only be played every %.1f seconds", rate_limit); // sound command was registered in a console command but not found in the SoundCmds hashmap
    }
}


public Action Command_ListSounds(client, args) {
    CreateTimer(0.1, TimerListSoundsPrivate, client);
    return Plugin_Continue;
}


public Action Command_SoundsMenu(client, args) {
    CreateTimer(0.1, TimerSoundsMenu, client);
    return Plugin_Continue;
}


public Action Command_NewSoundsMenu(client, args) {
    CreateTimer(0.1, TimerSoundsMenuNewest, client);
    return Plugin_Continue;
}


// allow users to type in sounds and get a list of available sound commands
public Action Command_Say(client, args) {
    return ProcessSay(client);
}


// allow users to type in sounds and get a list of available sound commands
public Action Command_TeamSay(client, args) {
    return ProcessSay(client);
}


// This is the console command that is registered with each of the sound commands in SoundCmds.
// It works by getting argument 0 (the command name) and sending that (minus the sm_ prefix) to the PlaySoundCommand function
public Action SoundCommand(int client, int args) {
    char cmd[32];
    GetCmdArg(0, cmd, sizeof(cmd));
    PlaySound(client, cmd[3]);
    return Plugin_Continue;
}


public Action ProcessSay(int client) {
    if (client == 0 || IsFakeClient(client)) {
        return Plugin_Handled;
    }
    
    char text[256];
    GetCmdArg(1, text, sizeof(text));
    
    if (StrEqual(text, "listsounds", false)) {
        CreateTimer(0.1, TimerListSoundsPrivate, client);
        return Plugin_Handled;
    } else if (StrEqual(text, "sounds", false)) {
        CreateTimer(0.1, TimerSoundsMenu, client);
        return Plugin_Handled;
    } else if (StrEqual(text, "newsounds", false)) {
        CreateTimer(0.1, TimerSoundsMenuNewest, client);
        return Plugin_Handled;
    } else {
        return Plugin_Continue;
    }
}


// show available sounds in chat to all players
public Action TimerListSoundsPublic(Handle timer, int client) {
    ListSounds(client, true);
    return Plugin_Continue;
}


// show available sounds in chat only to the specified client
public Action TimerListSoundsPrivate(Handle timer, int client) {
    ListSounds(client, false);
    return Plugin_Continue;
}


// show sounds menu by newest
public Action TimerSoundsMenuNewest(Handle timer, int client) {
    SoundMenu(client, true);
    return Plugin_Continue;
}


// show sounds menu
public Action TimerSoundsMenu(Handle timer, int client) {
    SoundMenu(client, false);
    return Plugin_Continue;
}



// Send a list of all sound commands to chat
void ListSounds(int client, bool show) {
    char buffer[MAX_LINE_LEN+4];
    char command[32];
    if(show) {
        PrintToChatAll("Sound commands:");
    } else {
        PrintToChat(client, "Sound commands:");
    }
    for(int i=0; i < sound_list.Length; i++) {
        sound_list.GetString(i, command, sizeof(command));
        if(strlen(buffer) + strlen(command) + 3 < MAX_LINE_LEN) {
            if(i == 0)
                StrCat(buffer, sizeof(buffer), "!");
            else
                StrCat(buffer, sizeof(buffer), ", !");
        } else {
            if(show) {
                PrintToChatAll("%s", buffer);
            } else {
                PrintToChat(client, "%s", buffer);
            }
            buffer[0] = '!';
            buffer[1] = '\0';
        }
        StrCat(buffer, sizeof(buffer), command);
    }
    if(show) {
        PrintToChatAll("%s", buffer);
    } else {
        PrintToChat(client, "%s", buffer);
    }
}


public void SoundMenu(int client, bool newest) {
    ArrayList s = (newest)? soundsnewest: sounds;
    
    Menu menu = (newest)? new Menu(SoundMenu_CallbackNewest): new Menu(SoundMenu_Callback);
    menu.SetTitle((newest)? "Sounds - Newest": "Sounds");
    
    char entry[64];
    char value[16];
    SoundKV sound;
    
    for(int i=0; i < s.Length; i++) {
        s.GetArray(i, sound);
        FormatEx(value, sizeof(value), "%i", i);
        if(pro_xp)
            FormatEx(entry, sizeof(entry), "%s (lvl %i", sound.command, sound.xplvl);
        else
            FormatEx(entry, sizeof(entry), "%s ", sound.command);
        
        if(pro_xp && ProXP_GetPlayerLevel(client) < sound.xplvl) {
            menu.AddItem(value, entry, ITEMDRAW_DISABLED);
        } else {
            menu.AddItem(value, entry);
        }
        
        menu.ExitButton = true;
        menu.Display(client, MENU_TIME_FOREVER);
    }
}


public int SoundMenu_Callback(Menu menu, MenuAction action, int client, int param2) {
    char item[64];
    menu.GetItem(param2, item, sizeof(item));
    
    if(action == MenuAction_Select) {
        SoundKV sound;
        int index = StringToInt(item);
        sounds.GetArray(index, sound);
        if(cv_kic && GetConVarInt(cv_kic) == 1 && sound.kic == 1) {
            ReplyToCommand(client, "That sound cannot be used when KIC is active.");
        } else if(PlaySound(client, sound.command)) {
            PrintToChatAll("%N played !%s", client, sound.command);
            return 0;
        }
    }
    return 1;
}


public int SoundMenu_CallbackNewest(Menu menu, MenuAction action, int client, int param2) {
    char item[64];
    menu.GetItem(param2, item, sizeof(item));
    
    if(action == MenuAction_Select) {
        SoundKV sound;
        int index = StringToInt(item);
        soundsnewest.GetArray(index, sound);
        if(cv_kic && GetConVarInt(cv_kic) == 1 && sound.kic == 1) {
            ReplyToCommand(client, "That sound cannot be used when KIC is active.");
        } else if(PlaySound(client, sound.command)) {
            PrintToChatAll("%N played !%s", client, sound.command);
            return 0;
        }
    }
    return 1;
}







public int Native_SoundList(Handle plugin, int numParams) {
    Handle new_handle = CloneHandle(sounds, plugin);
    return view_as<int>(new_handle);
}

public int Native_SoundListByNewest(Handle plugin, int numParams) {
    Handle new_handle = CloneHandle(soundsnewest, plugin);
    return view_as<int>(new_handle);
}

int SortNewest(int index1, int index2, Handle array, Handle hndl) {
    SoundKV a;
    SoundKV b;
    
    GetArrayArray(array, index1, a, sizeof(a));
    GetArrayArray(array, index2, b, sizeof(b));
    
    return b.id - a.id;
    
}


public int Native_HasSound(Handle plugin, int numParams) {
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) { return 0; }
    char[] cmd = new char[len+1];
    GetNativeString(1, cmd, len+1);
    char buff[2];
    return sound_cmds.GetString(cmd, buff, sizeof(buff));
}

public int Native_PlaySound(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int len;
    if(GetNativeStringLength(2, len) != SP_ERROR_NONE || len == 0) { return false; }
    char[] cmd = new char[len+1];
    GetNativeString(2, cmd, len+1);
    
    if(PlaySound(client, cmd)) {
        PrintToChatAll("%N played !%s", client, cmd);
        return true;
    }
    return false;
}

public int Native_ShowSoundMenu(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    bool newest = GetNativeCell(2);
    SoundMenu(client, newest);
    return 0;
}

public int Native_CheckSoundRateLimit(Handle plugin, int numParams) {
    int len;
    if(GetNativeStringLength(1, len) != SP_ERROR_NONE || len == 0) { return false; }
    char[] cmd = new char[len+1];
    GetNativeString(1, cmd, len+1);
    
    int index = -1;
    if(!sound_cmds.GetValue(cmd, index) || index == -1 || index >= sounds.Length) {
        return false;
    }
    
    SoundKV cur_sound;
    if(!sounds.GetArray(index, cur_sound)) {
        return false;
    }
    
    return !rate_limiting_enabled || CanPlaySound(cur_sound.rate_points);
}

