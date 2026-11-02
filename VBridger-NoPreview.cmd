@echo off
setlocal
cd /d "%~dp0"

set "PS1=%~dp0Patch-VBridgerNoPreview.ps1"
set "ACT="

if not exist "%PS1%" (
    echo [ERROR] Patch-VBridgerNoPreview.ps1 must sit in this same folder.
    pause
    exit /b 2
)

rem Direct arguments: check / apply / restore.
rem They run once - no menu, no confirmation - and exit with the script's own
rem exit code, so a shortcut, a scheduled task or another batch file can rely
rem on both the result and the code.
if /i "%~1"=="check"   goto :arg_check
if /i "%~1"=="apply"   goto :arg_apply
if /i "%~1"=="restore" goto :arg_restore
if not "%~1"=="" goto :bad_arg

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

:arg_check
set "ACT=check"
goto :check

:arg_apply
set "ACT=apply"
goto :apply

:arg_restore
set "ACT=restore"
goto :restore

:bad_arg
echo [ERROR] unknown argument: %~1
echo         use check, apply or restore, or run without arguments for the menu.
pause
exit /b 2

:check
cls
echo === 1. check / dry run  -  writes nothing ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -DryRun
if defined ACT exit /b %errorlevel%
goto :back

:apply
cls
echo === 2. apply patch ===
echo.
echo Close VBridger completely first, or the patch is refused.
echo.
if defined ACT goto :do_apply
set "yn="
set /p "yn=continue? (Y/N): "
if /i not "%yn%"=="Y" goto :menu
:do_apply
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
if defined ACT exit /b %errorlevel%
goto :back

:restore
cls
echo === 3. rollback ===
echo.
echo The newest level2.bak_* backup is copied back over level2.
echo.
if defined ACT goto :do_restore
set "yn="
set /p "yn=continue? (Y/N): "
if /i not "%yn%"=="Y" goto :menu
:do_restore
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Restore
if defined ACT exit /b %errorlevel%
goto :back

:back
echo.
pause
goto :menu
