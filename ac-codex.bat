@echo off
:menu
cls
echo =====================================
echo       Codex Account Selector        
echo =====================================
echo  1. Run Account 1
echo  2. Run Account 2
echo  3. Run Account 3
echo  4. Run Account 4
echo  5. Exit
echo =====================================
set /p choice="Enter your choice (1-5): "

if "%choice%"=="1" set "ACC_NAME=Acc1" & goto launch
if "%choice%"=="2" set "ACC_NAME=Acc2" & goto launch
if "%choice%"=="3" set "ACC_NAME=Acc3" & goto launch
if "%choice%"=="4" set "ACC_NAME=Acc4" & goto launch
if "%choice%"=="5" exit
goto menu

:launch
echo.
echo Starting Codex for %ACC_NAME%...
echo =====================================

:: تنظیم مسیر داینامیک بر اساس اکانت انتخاب شده
set "CODEX_HOME=%USERPROFILE%\CodexProfiles\%ACC_NAME%"

:: پیدا کردن خودکار مسیر فایل اجرایی
set "APP_DIR="
for /f "tokens=*" %%i in ('dir /b /ad "C:\Program Files\WindowsApps\OpenAI.Codex_*_x64__2p2nqsd0c76g0" 2^>nul') do (
    set "APP_DIR=C:\Program Files\WindowsApps\%%i\app\Codex.exe"
)

:: اجرای برنامه
if defined APP_DIR (
    start "" "%APP_DIR%" --user-data-dir="%CODEX_HOME%"
) else (
    echo Error: Codex installation directory not found.
    pause
)
