# csgoautorecord
Automatically records a demo of every match of *Counter-Strike: Global Offensive* you play. Why this isn't an option in the game itself like in *Team Fortress 2* is beyond me.

**This doesn't yet support Counter-Strike 2.** I would like to support it, but the client's RCON server stops responding when connected to a non-listen server. I don't know how to work around this.

This is just a little toy project of mine. **No support will be provided.** This is not the most well written code. My git commit descriptions are not up to my usual standards. I don't care.

This probably won't get you VAC banned, as it just uses RCON and does not tamper with the game process or executables. However, use at your own risk anyway.

## Usage
1. Generate a long unpredictable password. One way to do this is with `pwgen -s 50 1`. The RCON server can be accessed by anyone on your local network.
2. Add this to your launch options: `-usercon +rcon_password YOUR_PASSWORD_HERE`.
3. Run the script with `./init.lua --password YOUR_PASSWORD_HERE autorecord --path "$HOME/.steam/steam/steamapps/common/Counter-Strike Global Offensive/game/csgo" --gzip` (exact parameters you should use varies depending on personal preference; do `./init.lua --help` for documentation).

## License
Written in 2023 by x4fx77x4f

To the extent possible under law, the author(s) have dedicated all copyright and related and neighboring rights to this software to the public domain worldwide. This software is distributed without any warranty.

A copy of the CC0 legalcode is in [`LICENSE`](./LICENSE).
