## ProSound

A Sourcemod plugin to play sound clips without users having to download the sounds when joining the server.

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

1. Upload the .smx file

2. Add the following to your `/cstrike/addons/sourcemod/configs/databases.cfg`

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

3. Create the sounds table by executing the following in a MySQL database:

    ```
    CREATE TABLE `pro_sounds` (
    `id` int(11) NOT NULL,
    `cmd` char(50) NOT NULL,
    `path` char(250) NOT NULL,
    `xp` int(11) DEFAULT '5',
    `kic` int(11) DEFAULT '0',
    `volume` float DEFAULT '1',
    `cost` int(11) DEFAULT '1',
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

## Configuration

The following cvars can be used to configure its behavior

```
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
    default: "60.0"
```
