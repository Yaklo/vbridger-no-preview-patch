@echo off
setlocal
cd /d "%~dp0"

set "PS1=%~dp0Patch-VBridgerNoPreview.ps1"

if not exist "%PS1%" (
    echo [ERROR] Patch-VBridgerNoPreview.ps1 must sit in this same folder.
    pause
    exit /b 2
)

rem Direct arguments: check / apply / restore
if /i "%~1"=="check"   goto :check
if /i "%~1"=="apply"   goto :apply
if /i "%~1"=="restore" goto :restore

:menu
cls
echo ==========================================================
echo    VBridger no-preview patch   -  unofficial
echo ==========================================================
echo.
echo    1. check     - dry run, writes nothing
echo    2. apply     - flip 1 byte, stop rendering
echo    3. rollback  - restore level2 from the newest backup
echo    0. exit
echo.
echo    Chinese menu: VBridger-NoPreview-zh.cmd
echo ==========================================================
echo.
set "pick="
set /p "pick=enter number [0-3]: "
if "%pick%"=="1" goto :check
if "%pick%"=="2" goto :apply
if "%pick%"=="3" goto :restore
if "%pick%"=="0" exit /b 0
echo.
echo invalid input: "%pick%"
timeout /t 2 >nul
goto :menu

:check
cls
echo === 1. check / dry run  -  writes nothing ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -DryRun
goto :back

:apply
cls
echo === 2. apply patch ===
echo.
echo Close VBridger completely first, or the patch is refused.
echo.
set "yn="
set /p "yn=continue? (Y/N): "
if /i not "%yn%"=="Y" goto :menu
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
goto :back

:restore
cls
echo === 3. rollback ===
echo.
echo The newest level2.bak_* backup is copied back over level2.
echo.
set "yn="
set /p "yn=continue? (Y/N): "
if /i not "%yn%"=="Y" goto :menu
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Restore
goto :back

:back
echo.
pause
goto :menu
