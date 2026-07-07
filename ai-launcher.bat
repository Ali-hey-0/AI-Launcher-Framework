@echo off
setlocal EnableDelayedExpansion
:: =====================================================================
::  AI Desktop Launcher Framework  (single file, zero dependencies)
:: =====================================================================
::  WHAT THIS IS
::    One portable .bat file that launches isolated, multi-profile
::    instances of several AI desktop/CLI apps. No PowerShell, no
::    Python, no Node, no installer. Copy the .bat (plus the "Launcher"
::    folder it creates next to itself) anywhere and it keeps working.
::
::  HOW IT IS ORGANIZED  (read this before editing anything)
::    1. GLOBAL PATHS      - where state lives on disk
::    2. MAIN MENU         - top level navigation
::    3. APP CONFIG TABLE  - :INIT_APPS  (the ONLY place app metadata
::                            lives; everything else reads from it)
::    4. APP MENU          - pick an app (auto-built from the table)
::    5. DISCOVERY ENGINE  - finds each app's .exe on disk, caches it
::    6. PROFILE ENGINE    - create/select/delete isolated profiles
::    7. LAUNCH ENGINE     - :DISPATCH_LAUNCH + one :LAUNCH_APP_<N> per app
::    8. INSTANCE ENGINE   - tracks running instances, can stop them
::    9. PROFILE MANAGEMENT MENU, LOCATE MENU, SETTINGS MENU
::
::  HOW TO ADD A NEW APP  (the only extensibility contract that matters)
::    1. Add ONE config block in :INIT_APPS (copy an existing one).
::    2. Add ONE :LAUNCH_APP_<N> label near the other launch labels.
::    That's it. Menus, discovery, profiles, caching, and instance
::    tracking all key off the table automatically.
::
::  HONESTY RULE
::    Isolation is only ever implemented using a mechanism that is
::    either officially documented or a stable, widely-used flag/env
::    var for that app. If no such mechanism exists (Gemini Desktop,
::    Custom Executable), we say so on screen and launch normally
::    instead of inventing a flag that might not exist.
:: =====================================================================

:: ---------------------------------------------------------------------
:: 1. GLOBAL PATHS
:: Everything lives under %~dp0Launcher so the tool is fully portable.
:: ---------------------------------------------------------------------
set "ROOT=%~dp0Launcher"
set "PROFILES_ROOT=%ROOT%\Profiles"
set "CACHE_ROOT=%ROOT%\cache"
set "INSTANCES_ROOT=%ROOT%\instances"
set "TEMP_ROOT=%ROOT%\temp"

if not exist "%ROOT%"            mkdir "%ROOT%"            >nul 2>&1
if not exist "%PROFILES_ROOT%"   mkdir "%PROFILES_ROOT%"   >nul 2>&1
if not exist "%CACHE_ROOT%"      mkdir "%CACHE_ROOT%"      >nul 2>&1
if not exist "%INSTANCES_ROOT%"  mkdir "%INSTANCES_ROOT%"  >nul 2>&1
if not exist "%TEMP_ROOT%"       mkdir "%TEMP_ROOT%"       >nul 2>&1

:: Clean up any leftover scratch files from a prior run that crashed
:: or was closed mid-operation, so stale temp files never confuse
:: discovery on this run.
del /q "%TEMP_ROOT%\*.tmp" >nul 2>&1

:: Cosmetic: a calmer default console color scheme (bright text on the
:: user's existing background). If COLOR fails for any reason (e.g.
:: redirected output) we simply continue with default colors -- never
:: fatal.
color 0B >nul 2>&1

call :INIT_APPS

:: =====================================================================
:: 2. MAIN MENU
:: =====================================================================
:MAIN_MENU
cls
echo ===============================================================
echo                 AI Desktop Launcher Framework
echo ===============================================================
echo.
echo   1. Select AI Application ^& Launch
echo   2. Manage Profiles
echo   3. Manage Running Instances
echo   4. Locate / Re-locate Executable
echo   5. Refresh Detection ^(clear cache^)
echo   6. Settings
echo   7. Exit
echo.
echo ===============================================================
set "MM_CHOICE="
set /p "MM_CHOICE=Enter your choice (1-7): "

if "%MM_CHOICE%"=="1" goto APP_MENU
if "%MM_CHOICE%"=="2" goto PROFILE_MENU
if "%MM_CHOICE%"=="3" goto INSTANCE_MENU
if "%MM_CHOICE%"=="4" goto LOCATE_MENU
if "%MM_CHOICE%"=="5" goto REFRESH_ALL
if "%MM_CHOICE%"=="6" goto SETTINGS_MENU
if "%MM_CHOICE%"=="7" goto CONFIRM_EXIT
call :SAY_INVALID
goto MAIN_MENU

:CONFIRM_EXIT
cls
echo ===============================================================
echo   Exit
echo ===============================================================
echo.
set "EXIT_ANY="
for /f %%c in ('dir /b "%INSTANCES_ROOT%\*.instance" 2^>nul ^| find /c /v ""') do set "EXIT_ANY=%%c"
if not "%EXIT_ANY%"=="0" if defined EXIT_ANY (
    echo   Note: there may still be tracked running instances.
    echo   Exiting this launcher will NOT close them.
    echo.
)
set "EXIT_CONFIRM="
set /p "EXIT_CONFIRM=Exit the launcher? (Y/N): "
if /i "%EXIT_CONFIRM%"=="Y" exit /b 0
goto MAIN_MENU


:: =====================================================================
:: 3. APPLICATION CONFIG TABLE
:: ---------------------------------------------------------------------
:: Batch has no structs, so each "app" is a row spread across parallel
:: variables indexed 1..APP_COUNT, named APP_<N>_<FIELD>.
::
:: Fields used by every app:
::   NAME       - display name shown in menus and used as the profile
::                folder name (must be filesystem-safe; keep it simple)
::   ISOLATION  - USERDATA | ENVVAR | NONE   (dispatch key for launching)
::   ENVVAR     - env var name to set, only when ISOLATION=ENVVAR
::   STATUS     - Supported | Experimental   (shown to the user as-is)
::   CLI        - 1 if this is a command-line app that should open in
::                a visible console window instead of "start"-ing silently
::
:: Fields used by the discovery engine (see section 5 for details on
:: what each DISCOVERY method does):
::   DISCOVERY    - APPX | LOCALAPPDATA | PATH | MANUAL
::                  (any app without one of these sees the full
::                  Registry/PATH/Program Files/LocalAppData sweep
::                  in :DISCOVER_MULTI as its fallback automatically)
::   EXE_HINT     - exe filename to search for (used by every method
::                  except APPX and MANUAL)
::   APPX_PATTERN - WindowsApps package folder glob (APPX only)
::   LAD_SUBPATH  - path under %LOCALAPPDATA% (LOCALAPPDATA only)
:: =====================================================================
:INIT_APPS
set APP_COUNT=7

set "APP_1_NAME=OpenAI Codex Desktop"
set "APP_1_EXE_HINT=Codex.exe"
set "APP_1_DISCOVERY=APPX"
set "APP_1_APPX_PATTERN=OpenAI.Codex_*_x64__*"
set "APP_1_ISOLATION=ENVVAR"
set "APP_1_ENVVAR=CODEX_HOME"
set "APP_1_STATUS=Supported"
set "APP_1_CLI=0"

set "APP_2_NAME=Claude Desktop"
set "APP_2_EXE_HINT=Claude.exe"
set "APP_2_DISCOVERY=LOCALAPPDATA"
set "APP_2_LAD_SUBPATH=AnthropicClaude\Claude.exe"
set "APP_2_ISOLATION=USERDATA"
set "APP_2_STATUS=Supported"
set "APP_2_CLI=0"

set "APP_3_NAME=Claude Code"
set "APP_3_EXE_HINT=claude.exe"
set "APP_3_DISCOVERY=PATH"
set "APP_3_ISOLATION=ENVVAR"
set "APP_3_ENVVAR=CLAUDE_CONFIG_DIR"
set "APP_3_STATUS=Supported"
set "APP_3_CLI=1"

set "APP_4_NAME=Cursor"
set "APP_4_EXE_HINT=Cursor.exe"
set "APP_4_DISCOVERY=LOCALAPPDATA"
set "APP_4_LAD_SUBPATH=Programs\cursor\Cursor.exe"
set "APP_4_ISOLATION=USERDATA"
set "APP_4_STATUS=Supported"
set "APP_4_CLI=0"

set "APP_5_NAME=Windsurf"
set "APP_5_EXE_HINT=Windsurf.exe"
set "APP_5_DISCOVERY=LOCALAPPDATA"
set "APP_5_LAD_SUBPATH=Programs\Windsurf\Windsurf.exe"
set "APP_5_ISOLATION=USERDATA"
set "APP_5_STATUS=Supported"
set "APP_5_CLI=0"

set "APP_6_NAME=Gemini Desktop"
set "APP_6_EXE_HINT=Gemini.exe"
set "APP_6_DISCOVERY=LOCALAPPDATA"
set "APP_6_LAD_SUBPATH=Gemini\Gemini.exe"
set "APP_6_ISOLATION=NONE"
set "APP_6_STATUS=Experimental"
set "APP_6_CLI=0"
:: No officially documented or widely-verified isolation mechanism has
:: been confirmed for Gemini Desktop. We do not invent a flag for it.
:: It launches normally (single shared profile) and the user is told
:: this on screen. If a real mechanism is later confirmed, change
:: ISOLATION to USERDATA/ENVVAR and STATUS to Supported -- nothing
:: else needs to change.

set "APP_7_NAME=Custom Executable"
set "APP_7_EXE_HINT="
set "APP_7_DISCOVERY=MANUAL"
set "APP_7_ISOLATION=NONE"
set "APP_7_STATUS=Supported"
set "APP_7_CLI=0"
:: Always-available fallback for any app not in this table. No
:: isolation is assumed since the target app is unknown; the user
:: still gets an organized profile folder, but no launch flag is
:: guessed or faked.

goto :eof

:: =====================================================================
:: 4. APP SELECTION MENU
:: Built entirely from the config table -- add a row in :INIT_APPS and
:: it appears here automatically. Nothing here needs editing.
:: =====================================================================
:APP_MENU
cls
echo ===============================================================
echo   Select AI Application
echo ===============================================================
echo.
for /l %%i in (1,1,%APP_COUNT%) do (
    echo   %%i. !APP_%%i_NAME!   [!APP_%%i_STATUS!]
)
echo   0. Back to Main Menu
echo.
echo ===============================================================
set "APP_CHOICE="
set /p "APP_CHOICE=Enter choice: "

if "%APP_CHOICE%"=="0" goto MAIN_MENU

set "VALID="
for /l %%i in (1,1,%APP_COUNT%) do (
    if "%APP_CHOICE%"=="%%i" set "VALID=1"
)
if not defined VALID (
    call :SAY_INVALID
    goto APP_MENU
)

set "SEL_APP=%APP_CHOICE%"
call set "SEL_NAME=%%APP_%SEL_APP%_NAME%%"
call set "SEL_STATUS=%%APP_%SEL_APP%_STATUS%%"
call set "SEL_ISOLATION=%%APP_%SEL_APP%_ISOLATION%%"

if /i "%SEL_STATUS%"=="Experimental" (
    echo.
    echo   [!] %SEL_NAME% is marked EXPERIMENTAL: no confirmed profile
    echo       isolation mechanism exists for this app yet. It will run
    echo       with its normal, single shared login/profile regardless
    echo       of which profile you pick below.
    echo.
    pause
)

goto RESOLVE_EXE


:: =====================================================================
:: 5. DISCOVERY ENGINE
:: ---------------------------------------------------------------------
:: Resolves SEL_APP's executable path into EXE_PATH.
::
:: Search order (per spec):
::   1. Existing cached path (fast path; skipped if stale/missing)
::   2. WindowsApps (APPX packages)
::   3. Registry (App Paths / uninstall keys)
::   4. PATH
::   5. LocalAppData
::   6. Program Files
::   7. Program Files (x86)
::   8. Known vendor folders (folded into LOCALAPPDATA/PROGRAMFILES
::      subpaths already defined per app in the config table)
::   9. Manual entry, only if every automatic method fails
::
:: A cache file at %CACHE_ROOT%\app_<N>.txt stores the resolved path so
:: we do not rescan disk on every single launch. The cache is treated
:: as invalid (and silently rebuilt) the moment the path in it no
:: longer exists on disk -- that alone covers "executable missing" and
:: "executable moved". Version-change invalidation is handled by
:: comparing the exe's file timestamp against a sidecar .ver file; if
:: they differ, the cache entry is discarded and rediscovered.
:: =====================================================================
:RESOLVE_EXE
set "CACHE_FILE=%CACHE_ROOT%\app_%SEL_APP%.txt"
set "VER_FILE=%CACHE_ROOT%\app_%SEL_APP%.ver"
set "EXE_PATH="

if exist "%CACHE_FILE%" (
    set /p EXE_PATH=<"%CACHE_FILE%"
    if defined EXE_PATH (
        if exist "!EXE_PATH!" (
            call :CHECK_CACHE_FRESH "!EXE_PATH!" "%VER_FILE%"
            if "!CACHE_FRESH!"=="1" goto EXE_FOUND
        )
    )
    set "EXE_PATH="
)

call set "DISC_METHOD=%%APP_%SEL_APP%_DISCOVERY%%"

if /i "%DISC_METHOD%"=="MANUAL" goto DISCOVER_MANUAL
if /i "%DISC_METHOD%"=="APPX" goto DISCOVER_APPX
if /i "%DISC_METHOD%"=="LOCALAPPDATA" goto DISCOVER_LOCALAPPDATA
if /i "%DISC_METHOD%"=="PATH" goto DISCOVER_PATH
goto DISCOVER_MULTI


:: ---- Compares an exe's current last-modified stamp against a cached
:: ---- .ver sidecar file. Sets CACHE_FRESH=1 if unchanged/unknown,
:: ---- CACHE_FRESH=0 if the exe's timestamp changed since we cached it.
:: ---- (Batch cannot read a real version resource without external
:: ---- tools, so last-modified time is the honest, dependency-free
:: ---- signal we use for "version changed if detectable".)
:CHECK_CACHE_FRESH
set "CACHE_FRESH=1"
set "CF_EXE=%~1"
set "CF_VERFILE=%~2"
for %%f in (%CF_EXE%) do set "CF_STAMP=%%~tf"
if exist "%CF_VERFILE%" (
    set /p CF_OLDSTAMP=<"%CF_VERFILE%"
    if not "%CF_OLDSTAMP%"=="%CF_STAMP%" set "CACHE_FRESH=0"
) else (
    > "%CF_VERFILE%" echo %CF_STAMP%
)
exit /b 0


:: ---- AppX / WindowsApps packages (e.g. Microsoft Store installs) -----
:DISCOVER_APPX
call set "PATTERN=%%APP_%SEL_APP%_APPX_PATTERN%%"
call set "HINT=%%APP_%SEL_APP%_EXE_HINT%%"
set "FOUND_LIST=%TEMP_ROOT%\_found_%SEL_APP%.tmp"
if exist "%FOUND_LIST%" del "%FOUND_LIST%" >nul 2>&1

if exist "C:\Program Files\WindowsApps\" (
    for /f "tokens=*" %%d in ('dir /b /ad "C:\Program Files\WindowsApps\%PATTERN%" 2^>nul') do (
        if exist "C:\Program Files\WindowsApps\%%d\app\%HINT%" (
            echo C:\Program Files\WindowsApps\%%d\app\%HINT%>>"%FOUND_LIST%"
        )
        if exist "C:\Program Files\WindowsApps\%%d\%HINT%" (
            echo C:\Program Files\WindowsApps\%%d\%HINT%>>"%FOUND_LIST%"
        )
    )
)
:: WindowsApps can be access-restricted; if nothing turned up there,
:: fall through to the remaining automatic methods rather than giving
:: up immediately.
if not exist "%FOUND_LIST%" goto DISCOVER_MULTI
goto DISCOVER_COLLECT_RESULTS


:: ---- LocalAppData (most modern desktop installers, incl. Electron) ---
:DISCOVER_LOCALAPPDATA
call set "SUBPATH=%%APP_%SEL_APP%_LAD_SUBPATH%%"
set "FOUND_LIST=%TEMP_ROOT%\_found_%SEL_APP%.tmp"
if exist "%FOUND_LIST%" del "%FOUND_LIST%" >nul 2>&1
if exist "%LOCALAPPDATA%\%SUBPATH%" echo %LOCALAPPDATA%\%SUBPATH%>>"%FOUND_LIST%"
if not exist "%FOUND_LIST%" goto DISCOVER_MULTI
goto DISCOVER_COLLECT_RESULTS


:: ---- PATH (CLI tools like Claude Code) --------------------------------
:DISCOVER_PATH
call set "HINT=%%APP_%SEL_APP%_EXE_HINT%%"
set "FOUND_LIST=%TEMP_ROOT%\_found_%SEL_APP%.tmp"
if exist "%FOUND_LIST%" del "%FOUND_LIST%" >nul 2>&1
for %%p in ("%HINT%") do (
    if exist "%%~$PATH:p" echo %%~$PATH:p>>"%FOUND_LIST%"
)
if not exist "%FOUND_LIST%" goto DISCOVER_MULTI
goto DISCOVER_COLLECT_RESULTS


:: ---- Manual only (Custom Executable entry) ----------------------------
:DISCOVER_MANUAL
goto MANUAL_PATH_ENTRY


:: ---- Multi-method sweep: Registry -> PATH -> Program Files -> (x86) --
:: ---- -> LocalAppData\Programs. Used as the fallback for any app whose
:: ---- primary DISCOVERY method above found nothing, and as the whole
:: ---- strategy for apps without a more specific method configured.
:DISCOVER_MULTI
call set "HINT=%%APP_%SEL_APP%_EXE_HINT%%"
set "FOUND_LIST=%TEMP_ROOT%\_found_%SEL_APP%.tmp"
if exist "%FOUND_LIST%" del "%FOUND_LIST%" >nul 2>&1

if "%HINT%"=="" goto DISCOVER_COLLECT_RESULTS

:: -- Registry: App Paths key, the standard location Windows installers
:: -- register a launchable exe's full path under.
for /f "tokens=2,*" %%a in (
    'reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\%HINT%" /ve 2^>nul ^| findstr /i "REG_SZ"'
) do (
    if exist "%%b" echo %%b>>"%FOUND_LIST%"
)
for /f "tokens=2,*" %%a in (
    'reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\%HINT%" /ve 2^>nul ^| findstr /i "REG_SZ"'
) do (
    if exist "%%b" echo %%b>>"%FOUND_LIST%"
)

:: -- PATH, in case it wasn't already the primary method for this app.
for %%p in ("%HINT%") do (
    if exist "%%~$PATH:p" echo %%~$PATH:p>>"%FOUND_LIST%"
)

:: -- Program Files, Program Files (x86), LocalAppData\Programs.
for %%r in ("%ProgramFiles%" "%ProgramFiles(x86)%" "%LOCALAPPDATA%\Programs") do (
    if exist "%%~r\" (
        for /f "tokens=*" %%f in ('dir /b /s "%%~r\%HINT%" 2^>nul') do (
            echo %%f>>"%FOUND_LIST%"
        )
    )
)

goto DISCOVER_COLLECT_RESULTS


:: ---- Collect + de-duplicate + present results from FOUND_LIST -------
:DISCOVER_COLLECT_RESULTS
if not exist "%FOUND_LIST%" goto DISCOVER_NONE_FOUND

set /a FCOUNT=0
for /f "usebackq delims=" %%l in ("%FOUND_LIST%") do (
    set "DUP="
    for /l %%j in (1,1,!FCOUNT!) do (
        if /i "!FOUND_%%j!"=="%%l" set "DUP=1"
    )
    if not defined DUP (
        set /a FCOUNT+=1
        set "FOUND_!FCOUNT!=%%l"
    )
)
del "%FOUND_LIST%" >nul 2>&1

if %FCOUNT% EQU 0 goto DISCOVER_NONE_FOUND

if %FCOUNT% EQU 1 (
    set "EXE_PATH=!FOUND_1!"
    > "%CACHE_FILE%" echo !EXE_PATH!
    for %%f in ("!EXE_PATH!") do > "%VER_FILE%" echo %%~tf
    goto EXE_FOUND
)

:: Multiple candidates found -- let the user pick, per spec. This label
:: also serves as its own "redraw" target on an invalid pick, since
:: FOUND_LIST/FCOUNT stay populated in memory -- no disk rescan needed.
:DISCOVER_PICK_RESULT
cls
echo ===============================================================
echo   Multiple installations found for %SEL_NAME%
echo ===============================================================
echo.
for /l %%i in (1,1,%FCOUNT%) do (
    echo   %%i. !FOUND_%%i!
)
set /a CUSTOM_OPT=%FCOUNT%+1
echo   !CUSTOM_OPT!. Enter a custom path instead
echo.
echo ===============================================================
set "PICK="
set /p "PICK=Choose installation (1-!CUSTOM_OPT!): "

if "%PICK%"=="!CUSTOM_OPT!" goto MANUAL_PATH_ENTRY
set "EXE_PATH="
if "%PICK%" GEQ "1" if "%PICK%" LEQ "%FCOUNT%" set "EXE_PATH=!FOUND_%PICK%!"
if not defined EXE_PATH (
    call :SAY_INVALID
    goto DISCOVER_PICK_RESULT
)
> "%CACHE_FILE%" echo !EXE_PATH!
for %%f in ("!EXE_PATH!") do > "%VER_FILE%" echo %%~tf
goto EXE_FOUND


:: ---- Nothing auto-discovered -------------------------------------------
:DISCOVER_NONE_FOUND
echo.
echo   No installation of %SEL_NAME% was found automatically.
echo   ^(Searched WindowsApps / Registry / PATH / LocalAppData /
echo    Program Files / Program Files ^(x86^) as applicable.^)
echo.
goto MANUAL_PATH_ENTRY


:: ---- Manual path entry (also reachable directly from Locate menu) -----
:MANUAL_PATH_ENTRY
echo.
set "MANUAL_EXE="
set /p "MANUAL_EXE=Enter full path to the executable (or blank to cancel): "
if "%MANUAL_EXE%"=="" goto APP_MENU
:: Strip surrounding quotes if the user pasted a quoted path, since we
:: re-quote consistently ourselves everywhere EXE_PATH is used.
set "MANUAL_EXE=%MANUAL_EXE:"=%"
if not exist "%MANUAL_EXE%" (
    echo   That path does not exist. Please try again.
    pause
    goto MANUAL_PATH_ENTRY
)
set "EXE_PATH=%MANUAL_EXE%"
> "%CACHE_FILE%" echo !EXE_PATH!
for %%f in ("!EXE_PATH!") do > "%VER_FILE%" echo %%~tf
goto EXE_FOUND


:EXE_FOUND
goto PROFILE_SELECT_FOR_LAUNCH

:: =====================================================================
:: 6. PROFILE ENGINE -- selection for launch
:: ---------------------------------------------------------------------
:: A profile is a folder: Profiles\<AppName>\<ProfileName>\
:: Inside it we keep a small "profile.info" text file with metadata
:: (creation time, last launch time) purely for display -- it is never
:: required for the app itself to function, so a missing/corrupt info
:: file never blocks a launch. Deleting one profile folder can never
:: affect any other profile folder; they are fully independent.
:: =====================================================================
:PROFILE_SELECT_FOR_LAUNCH
set "APP_PROFILE_DIR=%PROFILES_ROOT%\%SEL_NAME%"
if not exist "%APP_PROFILE_DIR%" mkdir "%APP_PROFILE_DIR%" >nul 2>&1

set /a PCOUNT=0
for /f "tokens=*" %%p in ('dir /b /ad /o:n "%APP_PROFILE_DIR%" 2^>nul') do (
    set /a PCOUNT+=1
    set "PROF_!PCOUNT!=%%p"
)

cls
echo ===============================================================
echo   Profiles for %SEL_NAME%
echo ===============================================================
echo.
if %PCOUNT% EQU 0 (
    echo   ^(no profiles yet^)
) else (
    for /l %%i in (1,1,%PCOUNT%) do (
        call :GET_PROFILE_INFO "%APP_PROFILE_DIR%\!PROF_%%i!" "PI_CREATED" "PI_LASTLAUNCH"
        echo   %%i. !PROF_%%i!   ^(created: !PI_CREATED!, last launch: !PI_LASTLAUNCH!^)
    )
)
set /a NEWP=%PCOUNT%+1
echo.
echo   !NEWP!. Create a new profile
echo   0. Back
echo.
echo ===============================================================
set "PSEL="
set /p "PSEL=Choose profile: "

if "%PSEL%"=="0" goto APP_MENU
if "%PSEL%"=="!NEWP!" goto CREATE_PROFILE_INLINE

set "SEL_PROFILE="
if "%PSEL%" GEQ "1" if "%PSEL%" LEQ "%PCOUNT%" set "SEL_PROFILE=!PROF_%PSEL%!"
if not defined SEL_PROFILE (
    call :SAY_INVALID
    goto PROFILE_SELECT_FOR_LAUNCH
)
goto INSTANCE_COUNT_PROMPT


:CREATE_PROFILE_INLINE
set "NEWPROFNAME="
set /p "NEWPROFNAME=New profile name: "
if "%NEWPROFNAME%"=="" goto PROFILE_SELECT_FOR_LAUNCH
call :SANITIZE_NAME "%NEWPROFNAME%"
set "NEWPROFNAME=%SANITIZED%"
if exist "%APP_PROFILE_DIR%\%NEWPROFNAME%" (
    echo.
    echo   [!] A profile named "%NEWPROFNAME%" already exists.
    pause
    goto PROFILE_SELECT_FOR_LAUNCH
)
mkdir "%APP_PROFILE_DIR%\%NEWPROFNAME%" >nul 2>&1
call :WRITE_PROFILE_CREATED "%APP_PROFILE_DIR%\%NEWPROFNAME%"
set "SEL_PROFILE=%NEWPROFNAME%"
goto INSTANCE_COUNT_PROMPT


:: ---- Helper: sanitize a user-typed name into a safe folder name ------
:: Strips path separators and quotes so the value is always safe to use
:: as a single path segment, regardless of what the user typed. Also
:: strips cmd.exe metacharacters ( & ^ % ! ( ) = ), because the profile
:: name later flows -- via PROFILE_PATH -- into a constructed `cmd /k
:: "set VAR=... && ..."` command line for CLI apps (:LAUNCH_CLI). Without
:: this, a profile name containing e.g. "&" could inject an extra
:: command into that spawned console window.
:SANITIZE_NAME
set "SANITIZED=%~1"
set "SANITIZED=%SANITIZED:/=-%"
set "SANITIZED=%SANITIZED:\=-%"
set "SANITIZED=%SANITIZED::=-%"
set "SANITIZED=%SANITIZED:*=-%"
set "SANITIZED=%SANITIZED:?=-%"
set "SANITIZED=%SANITIZED:"=%"
set "SANITIZED=%SANITIZED:<=-%"
set "SANITIZED=%SANITIZED:>=-%"
set "SANITIZED=%SANITIZED:|=-%"
set "SANITIZED=%SANITIZED:&=-%"
set "SANITIZED=%SANITIZED:^^=-%"
set "SANITIZED=%SANITIZED:%%=-%"
set "SANITIZED=%SANITIZED:(=-%"
set "SANITIZED=%SANITIZED:)=-%"
set "SANITIZED=%SANITIZED:==-%"
:: A literal "!" is consumed by the parser on ANY line once delayed
:: expansion is active (a well-known gotcha, not limited to ()-blocks),
:: so it cannot be matched via %SANITIZED:!=-% the way the other
:: characters above are. Toggle delayed expansion off for just this one
:: substitution so "!" is treated as a literal character instead of an
:: expansion marker.
setlocal DisableDelayedExpansion
set "SANITIZED=%SANITIZED:!=-%"
endlocal & set "SANITIZED=%SANITIZED%"
exit /b 0


:: ---- Helper: read profile.info (creation/last-launch) for display ----
:: %1=profile folder  %2=out var name for created  %3=out var name for
:: last launch. Missing/corrupt info file just shows "unknown" -- it
:: never blocks anything.
:GET_PROFILE_INFO
set "GPI_DIR=%~1"
set "%~2=unknown"
set "%~3=never"
if exist "%GPI_DIR%\profile.info" (
    for /f "usebackq tokens=1,* delims==" %%k in ("%GPI_DIR%\profile.info") do (
        if /i "%%k"=="created" set "%~2=%%l"
        if /i "%%k"=="lastlaunch" set "%~3=%%l"
    )
)
exit /b 0


:: ---- Helper: stamp a brand-new profile with its creation time --------
:WRITE_PROFILE_CREATED
set "WPC_DIR=%~1"
> "%WPC_DIR%\profile.info" echo created=%date% %time%
exit /b 0


:: ---- Helper: update a profile's last-launch stamp --------------------
:: Preserves the existing "created" line and rewrites "lastlaunch".
:TOUCH_PROFILE_LAUNCHED
set "TPL_DIR=%~1"
set "TPL_CREATED=unknown"
if exist "%TPL_DIR%\profile.info" (
    for /f "usebackq tokens=1,* delims==" %%k in ("%TPL_DIR%\profile.info") do (
        if /i "%%k"=="created" set "TPL_CREATED=%%l"
    )
)
> "%TPL_DIR%\profile.info" echo created=%TPL_CREATED%
>> "%TPL_DIR%\profile.info" echo lastlaunch=%date% %time%
exit /b 0


:: =====================================================================
:: INSTANCE COUNT
:: No artificial cap. Any positive whole number is accepted; we loop
:: that many times when launching. Multi-instance support (or lack of
:: it) is left entirely up to the target application.
:: =====================================================================
:INSTANCE_COUNT_PROMPT
set "INSTANCES="
set /p "INSTANCES=How many instances to launch? [1]: "
if "%INSTANCES%"=="" set "INSTANCES=1"
echo %INSTANCES%| findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo   Please enter a positive whole number.
    pause
    goto INSTANCE_COUNT_PROMPT
)
:: Defense-in-depth: this path is always interactive, so make sure a
:: leftover SILENT_MODE flag can never suppress the normal pause/summary.
set "SILENT_MODE="
goto DISPATCH_LAUNCH


:: =====================================================================
:: 7. LAUNCH DISPATCH
:: Routes to the per-app launch label. Mirrors the table in :INIT_APPS.
:: This is the one line you add when adding a new app.
:: =====================================================================
:DISPATCH_LAUNCH
if "%SEL_APP%"=="1" goto LAUNCH_APP_1
if "%SEL_APP%"=="2" goto LAUNCH_APP_2
if "%SEL_APP%"=="3" goto LAUNCH_APP_3
if "%SEL_APP%"=="4" goto LAUNCH_APP_4
if "%SEL_APP%"=="5" goto LAUNCH_APP_5
if "%SEL_APP%"=="6" goto LAUNCH_APP_6
if "%SEL_APP%"=="7" goto LAUNCH_APP_7
goto MAIN_MENU


:: ---- 1: OpenAI Codex Desktop -------------------------------------------
:: Isolation: CODEX_HOME env var, pointed at the profile folder.
:LAUNCH_APP_1
set "PROFILE_PATH=%APP_PROFILE_DIR%\%SEL_PROFILE%"
if not exist "%PROFILE_PATH%" mkdir "%PROFILE_PATH%" >nul 2>&1
set "CODEX_HOME=%PROFILE_PATH%"
for /l %%i in (1,1,%INSTANCES%) do (
    call :LAUNCH_GUI "%EXE_PATH%" ""
)
goto LAUNCH_DONE

:: ---- 2: Claude Desktop --------------------------------------------------
:: Isolation: Electron --user-data-dir flag.
:LAUNCH_APP_2
set "PROFILE_PATH=%APP_PROFILE_DIR%\%SEL_PROFILE%"
if not exist "%PROFILE_PATH%" mkdir "%PROFILE_PATH%" >nul 2>&1
for /l %%i in (1,1,%INSTANCES%) do (
    call :LAUNCH_GUI "%EXE_PATH%" "--user-data-dir=\"%PROFILE_PATH%\""
)
goto LAUNCH_DONE

:: ---- 3: Claude Code -------------------------------------------------------
:: Isolation: CLAUDE_CONFIG_DIR env var. This is a CLI, so each instance
:: opens in its own visible console window rather than launching silently.
:LAUNCH_APP_3
set "PROFILE_PATH=%APP_PROFILE_DIR%\%SEL_PROFILE%"
if not exist "%PROFILE_PATH%" mkdir "%PROFILE_PATH%" >nul 2>&1
for /l %%i in (1,1,%INSTANCES%) do (
    call :LAUNCH_CLI "%EXE_PATH%" "Claude Code - %SEL_PROFILE%" "CLAUDE_CONFIG_DIR=%PROFILE_PATH%"
)
goto LAUNCH_DONE

:: ---- 4: Cursor -------------------------------------------------------------
:: Isolation: VS-Code-standard --user-data-dir + --extensions-dir.
:LAUNCH_APP_4
set "PROFILE_PATH=%APP_PROFILE_DIR%\%SEL_PROFILE%"
if not exist "%PROFILE_PATH%" mkdir "%PROFILE_PATH%" >nul 2>&1
if not exist "%PROFILE_PATH%\extensions" mkdir "%PROFILE_PATH%\extensions" >nul 2>&1
for /l %%i in (1,1,%INSTANCES%) do (
    call :LAUNCH_GUI "%EXE_PATH%" "--user-data-dir=\"%PROFILE_PATH%\" --extensions-dir=\"%PROFILE_PATH%\extensions\""
)
goto LAUNCH_DONE

:: ---- 5: Windsurf -----------------------------------------------------------
:: Isolation: same VS-Code-standard flags as Cursor.
:LAUNCH_APP_5
set "PROFILE_PATH=%APP_PROFILE_DIR%\%SEL_PROFILE%"
if not exist "%PROFILE_PATH%" mkdir "%PROFILE_PATH%" >nul 2>&1
if not exist "%PROFILE_PATH%\extensions" mkdir "%PROFILE_PATH%\extensions" >nul 2>&1
for /l %%i in (1,1,%INSTANCES%) do (
    call :LAUNCH_GUI "%EXE_PATH%" "--user-data-dir=\"%PROFILE_PATH%\" --extensions-dir=\"%PROFILE_PATH%\extensions\""
)
goto LAUNCH_DONE

:: ---- 6: Gemini Desktop ------------------------------------------------------
:: Isolation: NONE confirmed. Launch plainly; the profile folder still
:: exists for organizational consistency, but it is not wired into the
:: app because no real isolation mechanism has been verified for it.
:LAUNCH_APP_6
set "PROFILE_PATH=%APP_PROFILE_DIR%\%SEL_PROFILE%"
if not exist "%PROFILE_PATH%" mkdir "%PROFILE_PATH%" >nul 2>&1
echo.
echo   [!] No isolation mechanism applied -- Gemini Desktop will use its
echo       normal shared profile regardless of the profile name chosen.
for /l %%i in (1,1,%INSTANCES%) do (
    call :LAUNCH_GUI "%EXE_PATH%" ""
)
goto LAUNCH_DONE

:: ---- 7: Custom Executable ----------------------------------------------
:: Isolation: NONE by design -- the target app is unknown, so we never
:: guess a data-dir flag for it.
:LAUNCH_APP_7
set "PROFILE_PATH=%APP_PROFILE_DIR%\%SEL_PROFILE%"
if not exist "%PROFILE_PATH%" mkdir "%PROFILE_PATH%" >nul 2>&1
for /l %%i in (1,1,%INSTANCES%) do (
    call :LAUNCH_GUI "%EXE_PATH%" ""
)
goto LAUNCH_DONE


:LAUNCH_DONE
call :TOUCH_PROFILE_LAUNCHED "%PROFILE_PATH%"
if "%SILENT_MODE%"=="1" (
    echo   - %SEL_NAME%: launched ^(profile: %SEL_PROFILE%^)
    exit /b 0
)
echo.
echo   Launched %INSTANCES% instance^(s^) of %SEL_NAME% ^(profile: %SEL_PROFILE%^).
pause
goto MAIN_MENU


:: ---- Helper: launch a GUI app and record it in the instance registry --
:: %1 = quoted exe path   %2 = extra args (already individually quoted,
:: may be an empty string). Uses "start" so the launcher itself never
:: blocks waiting for the child to exit.
:LAUNCH_GUI
set "LG_EXE=%~1"
set "LG_ARGS=%~2"
start "" "%LG_EXE%" %LG_ARGS%
call :RECORD_INSTANCE "%LG_EXE%"
exit /b 0


:: ---- Helper: launch a CLI app in its own visible console window ------
:: %1 = quoted exe path   %2 = window title   %3 = "VARNAME=value" to
:: export inside that window before running the exe.
:LAUNCH_CLI
set "LC_EXE=%~1"
set "LC_TITLE=%~2"
set "LC_ENVSET=%~3"
start "%LC_TITLE%" cmd /k "set %LC_ENVSET% && "%LC_EXE%""
call :RECORD_INSTANCE "%LC_EXE%"
exit /b 0


:: ---- Helper: append a record to the instance registry so the Instance
:: ---- Management menu can show it as Running, with launch time and a
:: ---- best-effort PID. One file per app+profile combination; the app
:: ---- and profile names are stored INSIDE each record line (not
:: ---- encoded into the filename) so a profile name containing an
:: ---- underscore or other punctuation can never be mis-split later.
:RECORD_INSTANCE
set "RI_EXE=%~1"
call :SANITIZE_NAME "%SEL_NAME%__%SEL_PROFILE%"
set "RI_FILE=%INSTANCES_ROOT%\%SANITIZED%.instance"
set "RI_PID=unknown"
:: Best-effort PID lookup: newest process matching this exe's image
:: name. Not perfectly reliable if many copies of the same exe are
:: starting at once, but it never blocks or fails the launch if it
:: can't find one.
for /f "tokens=2 delims=," %%p in ('tasklist /fi "IMAGENAME eq %~nx1" /fo csv /nh 2^>nul') do (
    set "RI_PID=%%~p"
)
>> "%RI_FILE%" echo %date% %time%^|%RI_PID%^|%SEL_NAME%^|%SEL_PROFILE%^|%RI_EXE%
exit /b 0

:: =====================================================================
:: 8. INSTANCE MANAGEMENT MENU
:: ---------------------------------------------------------------------
:: Every launch appends a line to Launcher\instances\<App>__<Profile>.
:: instance ("timestamp|pid|exepath"). This menu reads those files back,
:: checks whether the recorded PID is still alive via tasklist, and
:: lets the user stop one profile's instances or everything at once.
:: A PID that is no longer running is simply reported as Stopped; we
:: never fail or crash on a stale record.
:: =====================================================================
:INSTANCE_MENU
cls
echo ===============================================================
echo   Running Instances
echo ===============================================================
echo.
:: Clear any row-to-filename mappings from a previous render of this
:: menu so a shorter list never leaves a stale, unreachable mapping
:: that could be selected by number in :INSTANCE_STOP_ONE.
for /f "tokens=1 delims==" %%v in ('set IMR_ROWFILE_ 2^>nul') do set "%%v="
set /a IM_COUNT=0
for /f "delims=" %%f in ('dir /b "%INSTANCES_ROOT%\*.instance" 2^>nul') do (
    call :INSTANCE_MENU_ROW "%%f"
)
if %IM_COUNT% EQU 0 (
    echo   ^(no launches recorded yet^)
)
echo.
echo -----------------------------------------------------------------
echo   S. Stop a specific profile's instances
echo   A. Stop ALL tracked instances
echo   L. Launch All ^(one instance of every Supported app, default profile^)
echo   R. Refresh this list
echo   0. Back to Main Menu
echo -----------------------------------------------------------------
set "IM_ACTION="
set /p "IM_ACTION=Choice: "

if "%IM_ACTION%"=="0" goto MAIN_MENU
if /i "%IM_ACTION%"=="R" goto INSTANCE_MENU
if /i "%IM_ACTION%"=="S" goto INSTANCE_STOP_ONE
if /i "%IM_ACTION%"=="A" goto INSTANCE_STOP_ALL
if /i "%IM_ACTION%"=="L" goto LAUNCH_ALL
call :SAY_INVALID
goto INSTANCE_MENU


:: ---- Helper: render one row of the instance list. %1 = filename ------
:: (Launcher\instances\*.instance). Reads the LAST line of the file
:: (most recent launch record for that app+profile combo) and reports
:: Running/Stopped based on whether that PID still exists. App and
:: profile names come from fields inside the record, not the filename.
:INSTANCE_MENU_ROW
set "IMR_FILE=%~1"
set "IMR_LAST="
for /f "usebackq delims=" %%l in ("%INSTANCES_ROOT%\%IMR_FILE%") do set "IMR_LAST=%%l"
for /f "tokens=1,2,3,4 delims=|" %%a in ("!IMR_LAST!") do (
    set "IMR_TIME=%%a"
    set "IMR_PID=%%b"
    set "IMR_APP=%%c"
    set "IMR_PROFILE=%%d"
)
set "IMR_STATE=Stopped"
if not "!IMR_PID!"=="unknown" (
    tasklist /fi "PID eq !IMR_PID!" 2>nul | findstr /r /c:"!IMR_PID!" >nul
    if not errorlevel 1 set "IMR_STATE=Running"
)
set /a IM_COUNT+=1
set "IMR_ROWFILE_%IM_COUNT%=%IMR_FILE%"
echo   %IM_COUNT%. !IMR_APP! / !IMR_PROFILE!  -  !IMR_STATE!  ^(launched !IMR_TIME!, PID !IMR_PID!^)
exit /b 0


:: ---- Stop a single tracked instance, chosen by its list number --------
:INSTANCE_STOP_ONE
if %IM_COUNT% EQU 0 (
    echo.
    echo   ^(nothing to stop^)
    pause
    goto INSTANCE_MENU
)
set "IS_IDX="
set /p "IS_IDX=Which number from the list above? "
set "IS_FILE="
if "%IS_IDX%" GEQ "1" if "%IS_IDX%" LEQ "%IM_COUNT%" call set "IS_FILE=%%IMR_ROWFILE_%IS_IDX%%%"
if not defined IS_FILE (
    call :SAY_INVALID
    goto INSTANCE_MENU
)
set "IS_LAST="
for /f "usebackq delims=" %%l in ("%INSTANCES_ROOT%\%IS_FILE%") do set "IS_LAST=%%l"
set "IS_PID="
set "IS_APPNAME="
set "IS_PROFNAME="
for /f "tokens=1,2,3,4 delims=|" %%a in ("!IS_LAST!") do (
    set "IS_PID=%%b"
    set "IS_APPNAME=%%c"
    set "IS_PROFNAME=%%d"
)
if "%IS_PID%"=="unknown" (
    echo.
    echo   [!] No PID was captured for this instance; it cannot be stopped
    echo       automatically. Please close it manually if it is running.
    pause
    goto INSTANCE_MENU
)
taskkill /pid %IS_PID% /f >nul 2>&1
if errorlevel 1 (
    echo.
    echo   [!] Could not stop PID %IS_PID% -- it may already be closed,
    echo       or you may not have permission to stop it.
) else (
    echo.
    echo   Stopped %IS_APPNAME% / %IS_PROFNAME% ^(PID %IS_PID%^).
)
pause
goto INSTANCE_MENU


:: ---- Stop every tracked instance across every app/profile -------------
:INSTANCE_STOP_ALL
echo.
set "IA_CONFIRM="
set /p "IA_CONFIRM=Stop ALL tracked instances? Type YES to confirm: "
if /i not "%IA_CONFIRM%"=="YES" (
    echo   Cancelled.
    pause
    goto INSTANCE_MENU
)
set /a IA_STOPPED=0
for /f "delims=" %%f in ('dir /b "%INSTANCES_ROOT%\*.instance" 2^>nul') do (
    set "IA_LAST="
    for /f "usebackq delims=" %%l in ("%INSTANCES_ROOT%\%%f") do set "IA_LAST=%%l"
    set "IA_PID="
    for /f "tokens=1,2 delims=|" %%a in ("!IA_LAST!") do set "IA_PID=%%b"
    if not "!IA_PID!"=="unknown" (
        taskkill /pid !IA_PID! /f >nul 2>&1
        if not errorlevel 1 set /a IA_STOPPED+=1
    )
)
echo.
echo   Stopped %IA_STOPPED% instance^(s^).
pause
goto INSTANCE_MENU


:: ---- Launch one instance of every Supported app using each app's ------
:: ---- "default" profile (created automatically if it doesn't exist).
:: ---- Experimental apps are skipped automatically since they have no
:: ---- real isolation to demonstrate; Custom Executable is skipped
:: ---- since it has no known exe to resolve without user input.
:LAUNCH_ALL
echo.
echo   Launching default profile for every Supported app...
echo.
for /l %%i in (1,1,%APP_COUNT%) do (
    call set "LA_STATUS=%%APP_%%i_STATUS%%"
    call set "LA_DISC=%%APP_%%i_DISCOVERY%%"
    if /i "!LA_STATUS!"=="Supported" if /i not "!LA_DISC!"=="MANUAL" (
        call :LAUNCH_ALL_ONE %%i
    )
)
echo.
pause
goto INSTANCE_MENU


:: ---- Helper used by Launch All: resolves + launches app index %1 on
:: ---- its "default" profile, without going through the interactive
:: ---- menus (so Launch All never stops to ask questions).
:LAUNCH_ALL_ONE
setlocal
set "SEL_APP=%~1"
call set "SEL_NAME=%%APP_%SEL_APP%_NAME%%"
set "CACHE_FILE=%CACHE_ROOT%\app_%SEL_APP%.txt"
set "EXE_PATH="
if exist "%CACHE_FILE%" set /p EXE_PATH=<"%CACHE_FILE%"
if not defined EXE_PATH (
    echo   - !SEL_NAME!: skipped ^(not yet located; use Locate menu first^)
    endlocal
    exit /b 0
)
if not exist "%EXE_PATH%" (
    echo   - !SEL_NAME!: skipped ^(cached path no longer exists^)
    endlocal
    exit /b 0
)
set "APP_PROFILE_DIR=%PROFILES_ROOT%\%SEL_NAME%"
set "SEL_PROFILE=default"
set "PROFILE_PATH=%APP_PROFILE_DIR%\default"
if not exist "%PROFILE_PATH%" (
    mkdir "%PROFILE_PATH%" >nul 2>&1
    call :WRITE_PROFILE_CREATED "%PROFILE_PATH%"
)
set "INSTANCES=1"
set "SILENT_MODE=1"
call :DISPATCH_LAUNCH
endlocal
exit /b 0


:: Launch All reuses the exact same :DISPATCH_LAUNCH / :LAUNCH_APP_N /
:: :LAUNCH_DONE labels as an interactive launch -- there is no separate
:: copy of the per-app launch logic to maintain. It sets SILENT_MODE=1
:: beforehand so :LAUNCH_DONE prints one summary line and returns
:: instead of pausing and jumping to the main menu.


:: =====================================================================
:: 9. PROFILE MANAGEMENT MENU
:: Standalone profile CRUD, independent from the launch flow -- useful
:: for cleaning up without launching anything.
:: =====================================================================
:PROFILE_MENU
cls
echo ===============================================================
echo   Manage Profiles
echo ===============================================================
echo.
for /l %%i in (1,1,%APP_COUNT%) do (
    echo   %%i. !APP_%%i_NAME!
)
echo   0. Back to Main Menu
echo.
echo ===============================================================
set "PM_APP="
set /p "PM_APP=Select application: "
if "%PM_APP%"=="0" goto MAIN_MENU
set "VALID="
for /l %%i in (1,1,%APP_COUNT%) do if "%PM_APP%"=="%%i" set "VALID=1"
if not defined VALID (
    call :SAY_INVALID
    goto PROFILE_MENU
)
call set "PM_NAME=%%APP_%PM_APP%_NAME%%"
set "PM_DIR=%PROFILES_ROOT%\%PM_NAME%"
if not exist "%PM_DIR%" mkdir "%PM_DIR%" >nul 2>&1

:PROFILE_MENU_ACTIONS
cls
echo ===============================================================
echo   Profiles: %PM_NAME%
echo ===============================================================
echo.
set /a PM_COUNT=0
for /f "tokens=*" %%p in ('dir /b /ad /o:n "%PM_DIR%" 2^>nul') do (
    set /a PM_COUNT+=1
    set "PM_PROF_!PM_COUNT!=%%p"
)
if %PM_COUNT% EQU 0 (
    echo   ^(no profiles yet^)
) else (
    for /l %%i in (1,1,%PM_COUNT%) do (
        call :GET_PROFILE_INFO "%PM_DIR%\!PM_PROF_%%i!" "PI_CREATED" "PI_LASTLAUNCH"
        echo   %%i. !PM_PROF_%%i!   ^(created: !PI_CREATED!, last launch: !PI_LASTLAUNCH!^)
    )
)
echo.
echo -----------------------------------------------------------------
echo   C. Create new profile
echo   D. Delete a profile
echo   O. Open a profile's folder
echo   0. Back
echo -----------------------------------------------------------------
set "PM_ACTION="
set /p "PM_ACTION=Choice: "

if /i "%PM_ACTION%"=="0" goto PROFILE_MENU
if /i "%PM_ACTION%"=="C" goto PROFILE_MENU_CREATE
if /i "%PM_ACTION%"=="D" goto PROFILE_MENU_DELETE
if /i "%PM_ACTION%"=="O" goto PROFILE_MENU_OPEN
call :SAY_INVALID
goto PROFILE_MENU_ACTIONS


:PROFILE_MENU_CREATE
set "PM_NEWNAME="
set /p "PM_NEWNAME=New profile name: "
if "%PM_NEWNAME%"=="" goto PROFILE_MENU_ACTIONS
call :SANITIZE_NAME "%PM_NEWNAME%"
set "PM_NEWNAME=%SANITIZED%"
if exist "%PM_DIR%\%PM_NEWNAME%" (
    echo.
    echo   [!] A profile named "%PM_NEWNAME%" already exists.
    pause
    goto PROFILE_MENU_ACTIONS
)
mkdir "%PM_DIR%\%PM_NEWNAME%" >nul 2>&1
call :WRITE_PROFILE_CREATED "%PM_DIR%\%PM_NEWNAME%"
echo   Created.
pause
goto PROFILE_MENU_ACTIONS


:PROFILE_MENU_DELETE
if %PM_COUNT% EQU 0 (
    echo   ^(nothing to delete^)
    pause
    goto PROFILE_MENU_ACTIONS
)
set "PM_DELIDX="
set /p "PM_DELIDX=Which profile number to delete? "
set "PM_TARGET="
if "%PM_DELIDX%" GEQ "1" if "%PM_DELIDX%" LEQ "%PM_COUNT%" set "PM_TARGET=!PM_PROF_%PM_DELIDX%!"
if not defined PM_TARGET (
    call :SAY_INVALID
    pause
    goto PROFILE_MENU_ACTIONS
)
echo.
echo   WARNING: this permanently deletes "%PM_DIR%\!PM_TARGET!"
echo   including any saved login state for that profile. Other
echo   profiles for this app are completely unaffected.
set "PM_CONFIRM="
set /p "PM_CONFIRM=Type YES to confirm: "
if /i "%PM_CONFIRM%"=="YES" (
    rmdir /s /q "%PM_DIR%\!PM_TARGET!" 2>nul
    if exist "%PM_DIR%\!PM_TARGET!" (
        echo   [!] Could not fully delete the profile -- it may be in use.
    ) else (
        echo   Deleted.
    )
) else (
    echo   Cancelled.
)
pause
goto PROFILE_MENU_ACTIONS


:PROFILE_MENU_OPEN
if %PM_COUNT% EQU 0 (
    echo   ^(no profiles to open^)
    pause
    goto PROFILE_MENU_ACTIONS
)
set "PM_OPENIDX="
set /p "PM_OPENIDX=Which profile number to open? "
set "PM_TARGET="
if "%PM_OPENIDX%" GEQ "1" if "%PM_OPENIDX%" LEQ "%PM_COUNT%" set "PM_TARGET=!PM_PROF_%PM_OPENIDX%!"
if not defined PM_TARGET (
    call :SAY_INVALID
    pause
    goto PROFILE_MENU_ACTIONS
)
start "" explorer "%PM_DIR%\!PM_TARGET!"
goto PROFILE_MENU_ACTIONS


:: =====================================================================
:: LOCATE / RE-LOCATE EXECUTABLE
:: Lets the user force a manual path for an app (overwrites cache) --
:: useful when auto-discovery picks the wrong install, or for a
:: portable copy discovery can't find on its own.
:: =====================================================================
:LOCATE_MENU
cls
echo ===============================================================
echo   Locate / Re-locate Executable
echo ===============================================================
echo.
for /l %%i in (1,1,%APP_COUNT%) do (
    echo   %%i. !APP_%%i_NAME!
)
echo   0. Back
echo.
echo ===============================================================
set "LOC_APP="
set /p "LOC_APP=Select application: "
if "%LOC_APP%"=="0" goto MAIN_MENU
set "VALID="
for /l %%i in (1,1,%APP_COUNT%) do if "%LOC_APP%"=="%%i" set "VALID=1"
if not defined VALID (
    call :SAY_INVALID
    goto LOCATE_MENU
)
call set "LOC_NAME=%%APP_%LOC_APP%_NAME%%"
set "LOC_PATH="
set /p "LOC_PATH=Enter full path to %LOC_NAME%'s executable: "
if "%LOC_PATH%"=="" goto LOCATE_MENU
set "LOC_PATH=%LOC_PATH:"=%"
if not exist "%LOC_PATH%" (
    echo   That path does not exist.
    pause
    goto LOCATE_MENU
)
> "%CACHE_ROOT%\app_%LOC_APP%.txt" echo %LOC_PATH%
for %%f in ("%LOC_PATH%") do > "%CACHE_ROOT%\app_%LOC_APP%.ver" echo %%~tf
echo   Saved. %LOC_NAME% will use this path from now on.
pause
goto MAIN_MENU


:: =====================================================================
:: REFRESH DETECTION
:: Wipes the discovery cache (and version stamps) so every app is
:: rediscovered from scratch on next selection. Does NOT touch profiles.
:: =====================================================================
:REFRESH_ALL
cls
echo ===============================================================
echo   Refresh Detection
echo ===============================================================
echo.
echo   This clears cached executable paths for ALL applications.
echo   Profiles and saved logins are not affected.
echo.
set "REFRESH_CONFIRM="
set /p "REFRESH_CONFIRM=Continue? (Y/N): "
if /i not "%REFRESH_CONFIRM%"=="Y" goto MAIN_MENU
del /q "%CACHE_ROOT%\*.txt" >nul 2>&1
del /q "%CACHE_ROOT%\*.ver" >nul 2>&1
echo.
echo   Detection cache cleared. Apps will be rediscovered on next launch.
pause
goto MAIN_MENU


:: =====================================================================
:: SETTINGS
:: =====================================================================
:SETTINGS_MENU
cls
echo ===============================================================
echo   Settings
echo ===============================================================
echo.
echo   1. Open Profiles root folder
echo   2. Open cache folder
echo   3. Show current executable paths
echo   4. Clear Cache ^(same as Refresh Detection^)
echo   0. Back
echo.
echo ===============================================================
set "SET_CHOICE="
set /p "SET_CHOICE=Choice: "
if "%SET_CHOICE%"=="0" goto MAIN_MENU
if "%SET_CHOICE%"=="1" (
    start "" explorer "%PROFILES_ROOT%"
    goto SETTINGS_MENU
)
if "%SET_CHOICE%"=="2" (
    start "" explorer "%CACHE_ROOT%"
    goto SETTINGS_MENU
)
if "%SET_CHOICE%"=="3" (
    cls
    echo   Current cached executable paths:
    echo -----------------------------------------------------------------
    for /l %%i in (1,1,%APP_COUNT%) do (
        set "SN=!APP_%%i_NAME!"
        if exist "%CACHE_ROOT%\app_%%i.txt" (
            set /p SP=<"%CACHE_ROOT%\app_%%i.txt"
        ) else (
            set "SP=(not yet located)"
        )
        echo   !SN!: !SP!
    )
    echo -----------------------------------------------------------------
    pause
    goto SETTINGS_MENU
)
if "%SET_CHOICE%"=="4" goto REFRESH_ALL
call :SAY_INVALID
goto SETTINGS_MENU


:: =====================================================================
:: SHARED HELPERS
:: =====================================================================

:: ---- Friendly, consistent "invalid choice" message + pause -----------
:SAY_INVALID
echo.
echo   [!] Invalid selection. Please try again.
echo.
pause
exit /b 0
