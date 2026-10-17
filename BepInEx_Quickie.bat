@echo off
setlocal EnableExtensions DisableDelayedExpansion

title BepInEx Steam Unity Installer

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "WORK=%TEMP%\BepInExSteamInstaller"
set "SETDIR=%APPDATA%\BepInExSteamInstaller"
set "SETTINGS=%SETDIR%\settings.ini"

if exist "%WORK%" rd /s /q "%WORK%"
mkdir "%WORK%" >nul 2>&1

rem ---- Default settings (1 = ON, 0 = OFF), overridden by the saved settings file ----
set "VERIFY=1"
set "ALLOWPRE=1"
set "CONFIRM=1"
set "KEEPDL=0"
if exist "%SETTINGS%" for /f "usebackq tokens=1,* delims==" %%A in ("%SETTINGS%") do call :loadsetting "%%A" "%%B"

goto :menu


rem ====================================================================
rem  MAIN MENU
rem ====================================================================
:menu
set "MODE="
set "AFTER="
set "ANALYZED="
cls
echo.
echo ================================================
echo          BepInEx Steam Unity Installer
echo ================================================
echo.
echo   1. Install BepInEx
echo   2. Install mods (UnityExplorer, custom files)
echo   3. Settings
echo   4. Exit
echo.
choice /c 1234 /n /m "Select an option: "
if errorlevel 4 goto :quit
if errorlevel 3 goto :settings
if errorlevel 2 set "MODE=mods" & goto :pickgame
set "MODE=bepinex"
goto :pickgame


rem ====================================================================
rem  SETTINGS
rem ====================================================================
:settings
set "T1=OFF"
set "T2=OFF"
set "T3=OFF"
set "T4=OFF"
if "%VERIFY%"=="1" set "T1=ON"
if "%ALLOWPRE%"=="1" set "T2=ON"
if "%CONFIRM%"=="1" set "T3=ON"
if "%KEEPDL%"=="1" set "T4=ON"
cls
echo.
echo ================================================
echo                   Settings
echo ================================================
echo.
echo   1. Verify files ................ [%T1%]
echo        Checks download integrity (SHA-256 and zip check)
echo        and confirms every file was copied correctly.
echo.
echo   2. Allow pre-releases .......... [%T2%]
echo        Required for BepInEx 6 (Unity.Mono / Unity.IL2CPP).
echo        When OFF, Mono games use BepInEx 5 stable.
echo.
echo   3. Confirm before installing ... [%T3%]
echo.
echo   4. Keep downloaded files ....... [%T4%]
echo        Saved to %USERPROFILE%\Downloads\BepInExInstaller
echo.
echo   5. Back to main menu
echo.
choice /c 12345 /n /m "Press 1-4 to toggle a setting, or 5 to go back: "
if errorlevel 5 goto :menu
if errorlevel 4 call :flip KEEPDL & goto :settings
if errorlevel 3 call :flip CONFIRM & goto :settings
if errorlevel 2 call :flip ALLOWPRE & goto :settings
call :flip VERIFY
goto :settings


rem ====================================================================
rem  GAME SELECTION + ANALYSIS (shared by BepInEx and mods)
rem ====================================================================
:pickgame
call :cleantemp
set "GAMEPATH="
set "GAMENAME="
set "ANALYZED="

cls
echo.
echo ================================================
echo          BepInEx Steam Unity Installer
echo ================================================
echo.
echo Scanning Steam libraries...
echo.

if exist "%WORK%\games.txt" del /q "%WORK%\games.txt"

set "STEAM="

for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul') do set "STEAM=%%B"

if not defined STEAM (
    for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul') do set "STEAM=%%B"
)

if not defined STEAM (
    set "ERRMSG=Steam installation was not found."
    goto :fail
)

rem SteamPath is stored with forward slashes
set "STEAM=%STEAM:/=\%"

set "LIBRARYVDF=%STEAM%\steamapps\libraryfolders.vdf"

if not exist "%LIBRARYVDF%" (
    set "ERRMSG=Steam library configuration was not found."
    goto :fail
)

rem Extract library paths (unescaping the doubled backslashes used in the VDF)
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:LIBRARYVDF); [regex]::Matches($t,'\x22path\x22\s+\x22([^\x22]+)\x22') | ForEach-Object { $_.Groups[1].Value.Replace('\\','\') }" > "%WORK%\libraries.txt"

if errorlevel 1 (
    set "ERRMSG=Failed to read the Steam library list."
    goto :fail
)

set /a GAMECOUNT=0

for /f "usebackq delims=" %%L in ("%WORK%\libraries.txt") do call :scanlib "%%~L"

if %GAMECOUNT% EQU 0 (
    set "ERRMSG=No Unity games were found in your Steam libraries."
    goto :fail
)

cls

echo.
echo ================================================
echo                 Unity Games
echo ================================================
echo.

for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%WORK%\games.txt") do echo %%A. %%C

echo.
echo 0. Back to main menu
echo.
set "CHOICE="
set /p "CHOICE=Select a game: "

if "%CHOICE%"=="0" goto :menu

for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%WORK%\games.txt") do if "%%A"=="%CHOICE%" set "GAMEPATH=%%B" & set "GAMENAME=%%C"

if not defined GAMEPATH (
    set "ERRMSG=Invalid selection."
    goto :fail
)

cls

echo.
echo ================================================
echo              Analyzing Unity Game
echo ================================================
echo.
echo Game: %GAMENAME%
echo Location: %GAMEPATH%
echo.

if not exist "%GAMEPATH%\UnityPlayer.dll" (
    set "ERRMSG=UnityPlayer.dll was not found. This does not appear to be a standard Unity Windows game."
    goto :fail
)

set "UNITYDATA="

for /d %%D in ("%GAMEPATH%\*_Data") do (
    if exist "%%D\globalgamemanagers" set "UNITYDATA=%%D"
    if exist "%%D\data.unity3d" set "UNITYDATA=%%D"
)

if not defined UNITYDATA (
    set "ERRMSG=Unity data directory could not be identified."
    goto :fail
)

rem ---- Runtime (Mono / IL2CPP) ----
set "RUNTIME=Unknown"

if exist "%UNITYDATA%\Managed" set "RUNTIME=Mono"
if exist "%GAMEPATH%\GameAssembly.dll" set "RUNTIME=IL2CPP"
if exist "%UNITYDATA%\il2cpp_data" set "RUNTIME=IL2CPP"

rem ---- Architecture (read from the PE header of the game executable) ----
set "ARCH=Unknown"
set "GAMEEXE="

rem Prefer <DataFolderName minus _Data>.exe, otherwise the first exe that is not a crash handler
for %%D in ("%UNITYDATA%") do set "DATANAME=%%~nxD"
if exist "%GAMEPATH%\%DATANAME:~0,-5%.exe" set "GAMEEXE=%DATANAME:~0,-5%.exe"

if not defined GAMEEXE for /f "delims=" %%A in ('dir /b /a-d "%GAMEPATH%\*.exe" 2^>nul ^| findstr /v /i "UnityCrashHandler"') do if not defined GAMEEXE set "GAMEEXE=%%A"

if not defined GAMEEXE (
    set "ERRMSG=Unity executable could not be identified."
    goto :fail
)

set "GAMEEXEPATH=%GAMEPATH%\%GAMEEXE%"

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::OpenRead($env:GAMEEXEPATH); try{$b=New-Object byte[] 4096; [void]$f.Read($b,0,4096)}finally{$f.Close()}; $e=[BitConverter]::ToInt32($b,60); $m=[BitConverter]::ToUInt16($b,$e+4); if($m -eq 0x14c){exit 32}; if($m -eq 0x8664){exit 64}; exit 0"

set "RC=%ERRORLEVEL%"
if "%RC%"=="32" set "ARCH=x86"
if "%RC%"=="64" set "ARCH=x64"

rem ---- Unity version ----
set "UNITYVERSION=Unknown"

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$v='Unknown'; $g=Join-Path $env:UNITYDATA 'globalgamemanagers'; if(Test-Path -LiteralPath $g){$f=[IO.File]::OpenRead($g); $b=New-Object byte[] 1048576; $n=$f.Read($b,0,$b.Length); $f.Close(); $s=[Text.Encoding]::GetEncoding(28591).GetString($b,0,$n); $m=[regex]::Match($s,'\d{1,4}\.\d+\.\d+[abfpc]\d+'); if($m.Success){$v=$m.Value}}; if($v -eq 'Unknown'){$fv=(Get-Item -LiteralPath ($env:GAMEPATH+'\UnityPlayer.dll')).VersionInfo.FileVersion; if($fv){$v=$fv}}; $v" > "%WORK%\unityversion.txt"

if exist "%WORK%\unityversion.txt" set /p "UNITYVERSION="<"%WORK%\unityversion.txt"

set "BEPINEX=Not installed"
if exist "%GAMEPATH%\BepInEx" set "BEPINEX=Installed"

echo Unity data:
echo %UNITYDATA%
echo.
echo Unity version:
echo %UNITYVERSION%
echo.
echo Runtime:
echo %RUNTIME%
echo.
echo Architecture:
echo %ARCH%
echo.
echo Existing BepInEx:
echo %BEPINEX%
echo.

if "%RUNTIME%"=="Unknown" (
    set "ERRMSG=Could not determine whether this game uses Mono or IL2CPP. Cancelled to prevent installing the wrong package."
    goto :fail
)

if "%ARCH%"=="Unknown" (
    set "ERRMSG=Could not determine whether this game is x86 or x64. Cancelled to prevent installing the wrong package."
    goto :fail
)

set "ANALYZED=1"

if "%MODE%"=="mods" goto :modsmenu
goto :bepinex


rem ====================================================================
rem  INSTALL BEPINEX
rem ====================================================================
:bepinex
call :cleantemp

if "%BEPINEX%"=="Installed" (
    echo BepInEx already appears to be installed.
    echo.
    choice /c YN /n /m "Reinstall BepInEx? [Y/N]: "
    if errorlevel 2 goto :menu
    goto :bepinex_go
)

call :confirm
if errorlevel 1 goto :menu

:bepinex_go
rem ---- Pick the matching package ----
set "ASSETFILTER="
set "RELREGEX="
set "RELREGEX2="

if "%RUNTIME%"=="Mono" if "%ARCH%"=="x64" set "ASSETFILTER=Unity.Mono-win-x64"
if "%RUNTIME%"=="Mono" if "%ARCH%"=="x86" set "ASSETFILTER=Unity.Mono-win-x86"
if "%RUNTIME%"=="IL2CPP" if "%ARCH%"=="x64" set "ASSETFILTER=Unity.IL2CPP-win-x64"
if "%RUNTIME%"=="IL2CPP" if "%ARCH%"=="x86" set "ASSETFILTER=Unity.IL2CPP-win-x86"

if not defined ASSETFILTER (
    set "ERRMSG=No compatible BepInEx package was identified."
    goto :fail
)

set "RELREGEX=%ASSETFILTER:.=\.%.*\.zip$"

rem Fallback for Mono games: BepInEx 5 stable
if "%RUNTIME%"=="Mono" if "%ARCH%"=="x64" set "RELREGEX2=^BepInEx_(win_)?x64_.*\.zip$"
if "%RUNTIME%"=="Mono" if "%ARCH%"=="x86" set "RELREGEX2=^BepInEx_(win_)?x86_.*\.zip$"

echo.
echo ================================================
echo             Compatible Package
echo ================================================
echo.
echo Runtime: %RUNTIME%
echo Architecture: %ARCH%
echo Package: %ASSETFILTER%
echo.
echo Checking latest BepInEx release...
echo.

set "RELREPO=BepInEx/BepInEx"
call :findrelease

if not exist "%WORK%\download.txt" (
    set "ERRMSG=No compatible BepInEx release was found."
    if "%ALLOWPRE%"=="0" set "ERRMSG=No stable BepInEx release was found for this game. Enable pre-releases in Settings and try again."
    goto :fail
)

call :readrelease
set "BEPINEXFILE=%RELFILE%"

echo Selected:
echo %BEPINEXFILE%
echo.

set "DLFILE=%WORK%\bepinex.zip"
call :download
if errorlevel 1 (
    set "ERRMSG=Download failed or did not pass verification."
    goto :fail
)

set "INSTALLKIND=bepinex"
set "MODNAME="
call :extractinstall
if errorlevel 1 goto :fail

if not exist "%GAMEPATH%\BepInEx\core" (
    set "ERRMSG=BepInEx installation failed."
    goto :fail
)

echo.
echo ================================================
echo              Installation Complete
echo ================================================
echo.
echo Game:
echo %GAMENAME%
echo.
echo Unity:
echo %UNITYVERSION%
echo.
echo Runtime:
echo %RUNTIME%
echo.
echo Architecture:
echo %ARCH%
echo.
echo BepInEx:
echo %BEPINEXFILE%
echo.
echo Installed to:
echo %GAMEPATH%
echo.
echo Launch the game once to initialize BepInEx.
echo.

if "%AFTER%"=="mods" set "AFTER=" & goto :modsmenu
goto :done


rem ====================================================================
rem  MODS
rem ====================================================================
:modsmenu
if not exist "%GAMEPATH%\BepInEx\core" (
    echo Mods require BepInEx, which is not installed for this game.
    echo.
    choice /c YN /n /m "Install BepInEx now? [Y/N]: "
    if errorlevel 2 goto :menu
    set "AFTER=mods"
    set "BEPINEX=Not installed"
    goto :bepinex
)

cls
echo.
echo ================================================
echo                 Install Mods
echo ================================================
echo.
echo Game: %GAMENAME%
echo.
echo   1. UnityExplorer  (in-game inspector, toggle with F7)
echo   2. Install a local .zip or .dll file
echo   3. Install from a direct URL (.zip or .dll)
echo   4. Open the plugins folder
echo   5. Back to main menu
echo.
choice /c 12345 /n /m "Select an option: "
if errorlevel 5 goto :menu
if errorlevel 4 goto :mod_open
if errorlevel 3 goto :mod_url
if errorlevel 2 goto :mod_local
goto :mod_unityexplorer


:mod_open
if not exist "%GAMEPATH%\BepInEx\plugins" mkdir "%GAMEPATH%\BepInEx\plugins" >nul 2>&1
start "" explorer "%GAMEPATH%\BepInEx\plugins"
goto :modsmenu


:mod_unityexplorer
call :cleantemp
set "MODNAME=UnityExplorer"
set "INSTALLKIND=mod"

rem Detect which BepInEx generation is installed (5 = BepInEx.dll, 6 = BepInEx.Core.dll / Unity.*)
set "BEPVER=5"
if exist "%GAMEPATH%\BepInEx\core\BepInEx.Core.dll" set "BEPVER=6"
if exist "%GAMEPATH%\BepInEx\core\BepInEx.Unity.Mono.dll" set "BEPVER=6"
if exist "%GAMEPATH%\BepInEx\core\BepInEx.Unity.IL2CPP.dll" set "BEPVER=6"

set "RELREGEX="
set "RELREGEX2="
if "%RUNTIME%"=="Mono" if "%BEPVER%"=="5" set "RELREGEX=^UnityExplorer\.BepInEx5\.Mono.*\.zip$"
if "%RUNTIME%"=="Mono" if "%BEPVER%"=="6" set "RELREGEX=^UnityExplorer\.BepInEx(\.Unity)?\.Mono.*\.zip$"
if "%RUNTIME%"=="IL2CPP" set "RELREGEX=^UnityExplorer\.BepInEx(\.Unity)?\.IL2CPP\.CoreCLR.*\.zip$"
if "%RUNTIME%"=="IL2CPP" set "RELREGEX2=^UnityExplorer\.BepInEx.*IL2CPP.*\.zip$"

if not defined RELREGEX (
    set "ERRMSG=Could not work out which UnityExplorer build matches this game."
    goto :fail
)

echo.
echo Runtime: %RUNTIME%   BepInEx: %BEPVER%.x
echo.
call :confirm
if errorlevel 1 goto :modsmenu

echo Checking latest UnityExplorer release...
echo.

for %%R in ("yukieiji/UnityExplorer" "aldelaro5/UnityExplorer" "sinai-dev/UnityExplorer") do if not exist "%WORK%\download.txt" call :tryrepo "%%~R"

if not exist "%WORK%\download.txt" (
    set "ERRMSG=No matching UnityExplorer release was found for this game and BepInEx version."
    goto :fail
)

call :readrelease
echo Selected:
echo %RELFILE%
echo.

set "DLFILE=%WORK%\mod.zip"
call :download
if errorlevel 1 (
    set "ERRMSG=Download failed or did not pass verification."
    goto :fail
)

call :extractinstall
if errorlevel 1 goto :fail

echo.
echo ================================================
echo           UnityExplorer Installed
echo ================================================
echo.
echo Installed to:
echo %DEST%
echo.
echo Launch the game and press F7 to open UnityExplorer.
echo.
goto :done


:mod_local
call :cleantemp
set "LOCALFILE="
set "RELFILE="
echo.
echo Drag a .zip or .dll file onto this window (or type the full path).
echo Leave empty to cancel.
echo.
set /p "LOCALFILE=File: "
if not defined LOCALFILE goto :modsmenu
set "LOCALFILE=%LOCALFILE:"=%"

if not exist "%LOCALFILE%" (
    set "ERRMSG=File not found."
    goto :fail
)

for %%F in ("%LOCALFILE%") do set "MODNAME=%%~nF" & set "MODEXT=%%~xF"

call :confirm
if errorlevel 1 goto :modsmenu

set "INSTALLKIND=mod"
if /i "%MODEXT%"==".dll" goto :mod_install_dll
if /i "%MODEXT%"==".zip" goto :mod_install_zip

set "ERRMSG=Only .zip and .dll files are supported."
goto :fail


:mod_install_zip
set "DLFILE=%LOCALFILE%"
call :extractinstall
if errorlevel 1 goto :fail
goto :mod_finished


:mod_install_dll
if not exist "%GAMEPATH%\BepInEx\plugins" mkdir "%GAMEPATH%\BepInEx\plugins" >nul 2>&1
set "DEST=%GAMEPATH%\BepInEx\plugins"
echo Installing...
copy /y "%LOCALFILE%" "%DEST%\" >nul
if errorlevel 1 (
    set "ERRMSG=Installation failed. Make sure the game is closed and try again."
    goto :fail
)
if "%VERIFY%"=="1" (
    echo Verifying installed files...
    fc /b "%LOCALFILE%" "%DEST%\%MODNAME%%MODEXT%" >nul
    if errorlevel 1 (
        set "ERRMSG=File verification failed - the copied file does not match the original."
        goto :fail
    )
)
goto :mod_finished


:mod_url
call :cleantemp
set "MODURL="
set "RELFILE="
set "EXPECTEDHASH="
echo.
echo Paste a direct download link to a .zip or .dll file.
echo Only install mods from sources you trust.
echo Leave empty to cancel.
echo.
set /p "MODURL=URL: "
if not defined MODURL goto :modsmenu

call :confirm
if errorlevel 1 goto :modsmenu

set "INSTALLKIND=mod"
set "DOWNLOADURL=%MODURL%"
set "DLFILE=%WORK%\mod.bin"
call :download
if errorlevel 1 (
    set "ERRMSG=Download failed or did not pass verification."
    goto :fail
)

rem Work out whether the download is a zip ("PK") or a dll ("MZ") and what to call it
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:WORK+'\mod.bin'; $b=[IO.File]::ReadAllBytes($p); $n=[IO.Path]::GetFileNameWithoutExtension(([Uri]$env:DOWNLOADURL).AbsolutePath); if(-not $n){$n='CustomMod'}; [IO.File]::WriteAllText($env:WORK+'\modname.txt',$n); if($b.Length -gt 1 -and $b[0] -eq 0x50 -and $b[1] -eq 0x4B){Move-Item -LiteralPath $p -Destination ($env:WORK+'\mod.zip') -Force} elseif($b.Length -gt 1 -and $b[0] -eq 0x4D -and $b[1] -eq 0x5A){Move-Item -LiteralPath $p -Destination ($env:WORK+'\mod.dll') -Force} else {exit 2}"

if errorlevel 1 (
    set "ERRMSG=The downloaded file is not a .zip or .dll."
    goto :fail
)

set "MODNAME=CustomMod"
if exist "%WORK%\modname.txt" set /p "MODNAME="<"%WORK%\modname.txt"

if exist "%WORK%\mod.zip" (
    set "DLFILE=%WORK%\mod.zip"
    call :extractinstall
    if errorlevel 1 goto :fail
    goto :mod_finished
)

if not exist "%GAMEPATH%\BepInEx\plugins" mkdir "%GAMEPATH%\BepInEx\plugins" >nul 2>&1
set "DEST=%GAMEPATH%\BepInEx\plugins"
echo Installing...
copy /y "%WORK%\mod.dll" "%DEST%\%MODNAME%.dll" >nul
if errorlevel 1 (
    set "ERRMSG=Installation failed. Make sure the game is closed and try again."
    goto :fail
)
if "%VERIFY%"=="1" (
    echo Verifying installed files...
    fc /b "%WORK%\mod.dll" "%DEST%\%MODNAME%.dll" >nul
    if errorlevel 1 (
        set "ERRMSG=File verification failed - the copied file does not match the download."
        goto :fail
    )
)
goto :mod_finished


:mod_finished
echo.
echo ================================================
echo               Mod Installed
echo ================================================
echo.
echo Mod:
echo %MODNAME%
echo.
echo Installed to:
echo %DEST%
echo.
goto :done


rem ====================================================================
rem  END OF RUN: return to the start (or exit)
rem ====================================================================
:fail
echo.
echo [!] %ERRMSG%
echo.
goto :done

:done
echo.
if "%MODE%"=="mods" if defined ANALYZED goto :done_mods
choice /c MX /n /m "Press M to return to the main menu, or X to exit: "
if errorlevel 2 goto :quit
goto :menu

:done_mods
choice /c MBX /n /m "Press M for the main menu, B for the mods menu, or X to exit: "
if errorlevel 3 goto :quit
if errorlevel 2 goto :modsmenu
goto :menu

:quit
if exist "%WORK%" rd /s /q "%WORK%"
endlocal
exit /b 0


rem ====================================================================
rem  SUBROUTINES
rem ====================================================================

:scanlib
if not exist "%~1\steamapps\common" goto :eof
for /d %%G in ("%~1\steamapps\common\*") do call :addgame "%%~G"
goto :eof

:addgame
if not exist "%~1\UnityPlayer.dll" goto :eof
set /a GAMECOUNT+=1
>>"%WORK%\games.txt" <nul set /p "=%GAMECOUNT%|%~1|%~nx1"
>>"%WORK%\games.txt" echo.
goto :eof

:loadsetting
if /i "%~1"=="VERIFY" set "VERIFY=%~2"
if /i "%~1"=="ALLOWPRE" set "ALLOWPRE=%~2"
if /i "%~1"=="CONFIRM" set "CONFIRM=%~2"
if /i "%~1"=="KEEPDL" set "KEEPDL=%~2"
goto :eof

:savesettings
if not exist "%SETDIR%" mkdir "%SETDIR%" >nul 2>&1
(
    echo VERIFY=%VERIFY%
    echo ALLOWPRE=%ALLOWPRE%
    echo CONFIRM=%CONFIRM%
    echo KEEPDL=%KEEPDL%
) > "%SETTINGS%"
goto :eof

:flip
rem Toggle the 0/1 setting whose name is passed as %1, then save
call set "CUR=%%%~1%%"
if "%CUR%"=="1" (set "%~1=0") else (set "%~1=1")
call :savesettings
goto :eof

:confirm
if not "%CONFIRM%"=="1" exit /b 0
choice /c YN /n /m "Continue with the installation? [Y/N]: "
if errorlevel 2 exit /b 1
exit /b 0

:cleantemp
del /q "%WORK%\download.txt" "%WORK%\version.txt" "%WORK%\hash.txt" "%WORK%\bepinex.zip" "%WORK%\mod.zip" "%WORK%\mod.dll" "%WORK%\mod.bin" "%WORK%\modname.txt" 2>nul
if exist "%WORK%\extract" rd /s /q "%WORK%\extract"
goto :eof

:tryrepo
set "RELREPO=%~1"
call :findrelease
goto :eof

rem Looks through a GitHub repo's releases. Uses RELREPO, RELREGEX, RELREGEX2 and ALLOWPRE.
rem Stable releases are preferred; pre-releases are only used when ALLOWPRE=1.
rem Writes download.txt, version.txt and hash.txt (SHA-256 if GitHub provides one).
:findrelease
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "try{ [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $r=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$env:RELREPO+'/releases?per_page=30') -Headers @{Accept='application/vnd.github+json';'User-Agent'='BepInExSteamInstaller'}; $found=$null; $passes=@(1); if($env:ALLOWPRE -eq '1'){$passes=@(1,2)}; foreach($regex in @($env:RELREGEX,$env:RELREGEX2)){ if(-not $regex){continue}; foreach($pass in $passes){ foreach($rel in $r){ if($rel.draft){continue}; if($pass -eq 1 -and $rel.prerelease){continue}; $found=$rel.assets | Where-Object { $_.name -match $regex } | Select-Object -First 1; if($found){break} }; if($found){break} }; if($found){break} }; if($found){ $d=''; if($found.digest -and $found.digest -like 'sha256:*'){$d=$found.digest.Substring(7)}; [IO.File]::WriteAllText($env:WORK+'\download.txt',$found.browser_download_url); [IO.File]::WriteAllText($env:WORK+'\version.txt',$found.name); [IO.File]::WriteAllText($env:WORK+'\hash.txt',$d) } }catch{ Write-Host ('GitHub lookup failed: '+$_.Exception.Message) }"
goto :eof

:readrelease
set "DOWNLOADURL="
set "RELFILE="
set "EXPECTEDHASH="
set /p "DOWNLOADURL="<"%WORK%\download.txt"
set /p "RELFILE="<"%WORK%\version.txt"
if exist "%WORK%\hash.txt" set /p "EXPECTEDHASH="<"%WORK%\hash.txt"
goto :eof

rem Downloads DOWNLOADURL to DLFILE. With VERIFY=1 it also checks the file is non-empty,
rem matches EXPECTEDHASH (SHA-256) when known, and opens correctly when it is a zip.
:download
if "%VERIFY%"=="1" (echo Downloading and verifying...) else (echo Downloading...)
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; if($env:DOWNLOADURL -notmatch '^https?://'){throw 'URL must start with http:// or https://'}; Invoke-WebRequest -UseBasicParsing -Uri $env:DOWNLOADURL -OutFile $env:DLFILE; if($env:VERIFY -eq '1'){ if((Get-Item -LiteralPath $env:DLFILE).Length -lt 1){throw 'Downloaded file is empty'}; if($env:EXPECTEDHASH){ $h=(Get-FileHash -LiteralPath $env:DLFILE -Algorithm SHA256).Hash; if($h -ne $env:EXPECTEDHASH){throw 'Checksum mismatch'} }; if($env:DLFILE -like '*.zip'){ Add-Type -AssemblyName System.IO.Compression.FileSystem; $z=[IO.Compression.ZipFile]::OpenRead($env:DLFILE); $z.Dispose() } }"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" if "%KEEPDL%"=="1" call :keepdl
exit /b %RC%

:keepdl
set "KEEPDIR=%USERPROFILE%\Downloads\BepInExInstaller"
if not exist "%KEEPDIR%" mkdir "%KEEPDIR%" >nul 2>&1
set "KEEPNAME=%RELFILE%"
if not defined KEEPNAME for %%F in ("%DLFILE%") do set "KEEPNAME=%%~nxF"
copy /y "%DLFILE%" "%KEEPDIR%\%KEEPNAME%" >nul
goto :eof

rem Extracts DLFILE and copies it into place. Sets DEST. Returns 1 (with ERRMSG set) on failure.
rem   INSTALLKIND=bepinex : contents go into the game folder
rem   INSTALLKIND=mod     : BepInEx\ -> game folder, plugins\ -> BepInEx\, anything else -> BepInEx\plugins\MODNAME
:extractinstall
if exist "%WORK%\extract" rd /s /q "%WORK%\extract"
mkdir "%WORK%\extract" >nul 2>&1

echo Extracting...

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath $env:DLFILE -DestinationPath ($env:WORK+'\extract') -Force"
if errorlevel 1 (
    set "ERRMSG=Extraction failed."
    exit /b 1
)

rem The zip is normally flat; handle a single wrapper folder just in case
set "SOURCE=%WORK%\extract"
if not exist "%SOURCE%\BepInEx" if not exist "%SOURCE%\plugins" for /d %%D in ("%WORK%\extract\*") do if exist "%%D\BepInEx" set "SOURCE=%%D"
if not exist "%SOURCE%\BepInEx" if not exist "%SOURCE%\plugins" for /d %%D in ("%WORK%\extract\*") do if exist "%%D\plugins" set "SOURCE=%%D"

set "DEST=%GAMEPATH%\BepInEx\plugins\%MODNAME%"
if exist "%SOURCE%\plugins" set "DEST=%GAMEPATH%\BepInEx"
if exist "%SOURCE%\BepInEx" set "DEST=%GAMEPATH%"
if "%INSTALLKIND%"=="bepinex" set "DEST=%GAMEPATH%"

if not exist "%DEST%" mkdir "%DEST%" >nul 2>&1

echo Installing...

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Get-ChildItem -LiteralPath $env:SOURCE -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $env:DEST -Recurse -Force }"
if errorlevel 1 (
    set "ERRMSG=Installation failed. Make sure the game is closed and try again."
    exit /b 1
)

if not "%VERIFY%"=="1" exit /b 0

echo Verifying installed files...

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$s=$env:SOURCE.TrimEnd('\'); $bad=0; Get-ChildItem -LiteralPath $s -Recurse -File -Force | ForEach-Object { $rel=$_.FullName.Substring($s.Length).TrimStart('\'); $t=Join-Path $env:DEST $rel; if(-not (Test-Path -LiteralPath $t) -or ((Get-FileHash -LiteralPath $t).Hash -ne (Get-FileHash -LiteralPath $_.FullName).Hash)){$bad++} }; if($bad -gt 0){Write-Host ($bad.ToString()+' file(s) failed verification'); exit 1}"
if errorlevel 1 (
    set "ERRMSG=File verification failed - some files did not copy correctly."
    exit /b 1
)

exit /b 0