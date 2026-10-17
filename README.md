# BepInEx Quickie

A single `.bat` file that sets up BepInEx for your Steam Unity games. No manual downloads, no digging through GitHub releases, no guessing which build you need. Run it, pick a game, done.

## Features

**Finds your games for you**
It reads your Steam install and every library folder you've set up (including secondary drives), then lists only the Unity games. No browsing for folders.

**Figures out the right BepInEx build**
Before installing anything, it looks at the game and works out whether it runs on Mono or IL2CPP, whether the exe is 32-bit or 64-bit (read straight from the PE header), which Unity version it was built with, and whether BepInEx is already there.

It then grabs the matching package from the official BepInEx releases. If it can't tell what the game is, it stops instead of installing the wrong thing.

**Mod installing built in**
UnityExplorer is downloaded in the build that matches your game's runtime and BepInEx version (5 or 6). Press F7 in game to open it.

You can also install a local `.zip` or `.dll` by pointing the installer at it or dragging it onto the window, or paste a direct download link and it will check whether the file is a zip or a dll and put it where it belongs. There's also a shortcut that opens `BepInEx\plugins` in Explorer.

If you try to install a mod without BepInEx, it offers to install BepInEx first and carries on afterward.

**Careful about what it downloads**
With verification on, it checks SHA-256 hashes when GitHub provides them, makes sure zips actually open, and compares every copied file against the original after install. Only `http(s)` links are accepted.

**Settings that stick**
Your choices are saved between runs.

Verify files: integrity checks on downloads and installs.
Allow pre-releases: needed for BepInEx 6 builds. When off, Mono games use BepInEx 5 stable.
Confirm before installing: a quick Y/N before anything is changed.
Keep downloaded files: saves copies to `Downloads\BepInExInstaller`.

**Stays out of the way**
No installer, no admin rights, no dependencies. It uses the PowerShell that ships with Windows. Temp files live in `%TEMP%` and are cleaned up when you exit. Settings are stored in `%APPDATA%\BepInExSteamInstaller`.

## Usage

1. Download the `.bat` file.
2. Double-click it.
3. Choose **Install BepInEx** or **Install mods**, then pick your game.
4. Launch the game once so BepInEx can set itself up.

## Requirements

Windows with PowerShell 5.1 (included by default), Steam with the game installed, and an internet connection to fetch releases from GitHub.

## Notes

Close the game before installing, otherwise files may be locked.

Only install mods from sources you trust. The installer can't tell you whether a mod is safe.

Games that aren't standard Unity Windows builds (no `UnityPlayer.dll`) won't show up.
