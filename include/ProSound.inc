#if defined _pro_sound_included
    #endinput
#endif
#define _pro_sound_included

public SharedPlugin __pl_pro_sound = 
{
    name = "pro_sound",
    file = "ProSound.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_pro_sound_SetNTVOptional() {
    MarkNativeAsOptional("ProSound_HasSound");
    MarkNativeAsOptional("ProSound_PlaySound");
    MarkNativeAsOptional("ProSound_CheckSoundRateLimit");
    MarkNativeAsOptional("ProSound_ShowSoundMenu");
}
#endif


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
}



/**
 * Check if a given sound command exists
 * 
 * @param sound     Sound command (without ! or /)
 * @return          Returns true if the sound exists
 */
native bool ProSound_HasSound(const char[] sound);

/**
 * Play a given sound
 * 
 * @param client     client index
 * @param sound      Sound command (without ! or /)
 * @return           Returns true is successful
 */
native bool ProSound_PlaySound(int client, const char[] sound);

/**
 * Takes a sound command and determines whether the sound can be played given rate limiting
 * 
 * @param sound     Sound command name
 * @return          Returns true if sound can be played given current rate limiting state
 */
native bool ProSound_CheckSoundRateLimit(const char[] sound);

/**
 * Display a menu with a list of sounds to the given player.
 * 
 * @param client     client index
 * @param newest     whether to sort the sounds by newest first
 */
native void ProSound_ShowSoundMenu(int client, bool newest);






