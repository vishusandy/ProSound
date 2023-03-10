# ProSound

A Sourcemod plugin to play sound clips without users having to download the sounds when joining the server.  Supports ratelimiting.

## Features

- Does not require sounds to be downloaded when joining the server.  This is accomplished by loading the sound urls in an invisible VGUI panel.
- Customizable database of sounds
- Each sound can, optionally, be registered as its own command
- Rate limiting (enabled by default but is optional)
    - only allows a sound to be played every X seconds (default is 3)
    - only allows X sounds (default is 10) to be played every interval (default interval is 60 seconds)
    - each sound can have a point value, representing its annoyingness factor, and will only allow X points to accumulate (default is 10) every interval
- Optionally integrates with [ProXP](https://github.com/vishusandy/ProXP) to limit sounds based on level.  ProXP does not need to be installed to use this plugin - it is just an added feature for servers running ProXP.

## Installing

1. Add the following to your `/cstrike/addons/sourcemod/configs/databases.cfg`

    ```
        "pro_sounds"
        {
            "driver"			"default"
            "host"				"<hostname>"
            "database"			"<databasename>"
            "user"				"<dbusername>"
            "pass"				"<dbpassword>"
        }
    ```

2. Create the sounds table by executing the following in a MySQL database:

    ```
    CREATE TABLE `pro_sounds` (
    `id` int(11) NOT NULL,
    `cmd` char(50) NOT NULL,
    `path` char(250) NOT NULL,
    `xp` int(11) DEFAULT '5',
    `kic` int(11) DEFAULT '0',
    `rate_points` int(11) NOT NULL DEFAULT '1',
    `enabled` tinyint(1) NOT NULL DEFAULT '1',
    `register_cmd` tinyint(1) NOT NULL DEFAULT '1'
    ) ENGINE=InnoDB DEFAULT CHARSET=latin1 ROW_FORMAT=COMPACT;

    ALTER TABLE `pro_sounds`
    ADD PRIMARY KEY (`id`) USING BTREE;

    ALTER TABLE `pro_sounds`
    MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=1;
    COMMIT;
    ```

3. Upload the .smx file

## Sound Entries

Each sound has the following fields:
- `cmd` - the name of the sound, and the name to register as a command if register_cmd is true
- `path` - the path and filename of the sound.  If the cvar `pro_sound_url` is empty this will be the full url of the sound, otherwise it will be `pro_sound_url` with the `path` field appened (ensure `pro_sound_url` ends in a '/' because that is not automatically added)
- `xp` - level required to use the sound - only used if ProXP is installed, ignored otherwise
- `kic` - a non-zero value indicates the sound cannot be played when the cvar `keep_it_clean` is a non-zero value.  This is intended to be used by another plugin, but can be used without one.
- `rate_points` - the number of points, or annoyingness factor, of the sound.  See cvars for rate limiting configuration.
- `enabled` - if this is 0 the sound will not be available, and will just be skipped.
- `register_cmd` - registers the sound as a command using the `cmd` field.  Example: to play a sound named 'doh' a user would type `!doh` in chat.

## Configuration

The following cvars can be used to configure the plugin's behavior:

```
pro_sound_url
    Base url for sounds.  Leave blank to specify full url in database entries, otherwise sound file will be appened to this url (make sure to include a / at the end!)
    default: ""

pro_sound_rate_limiting_enabled
    default: "1"

pro_sound_rate_limit
    Minimum number of seconds between playing one sound and when another sound can be played.
    default: "3.0"

pro_sound_max_sounds_per_interval
    Maximum number of sounds that can be played during an interval.  Must be an integer value.
    default: "10"

pro_sound_max_points_per_interval
    Maximum number of points (annoyingness factor) that can be played during an interval.  Must be an integer value.
    default: "10"

pro_sound_sound_interval
    Length of of interval in seconds.
    default: "60.0"
```
