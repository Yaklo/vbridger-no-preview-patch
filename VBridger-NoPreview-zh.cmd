@echo off
setlocal
cd /d "%~dp0"

set "PS1=%~dp0Patch-VBridgerNoPreview.ps1"
set "ACT="

if not exist "%PS1%" (
    echo [ERROR] Patch-VBridgerNoPreview.ps1 must sit in this same folder.
    echo [错误]  Patch-VBridgerNoPreview.ps1 必须与本文件放在同一目录。
    pause
    exit /b 2
)

rem 直传参数：check / apply / restore
rem 带参数时不进菜单、不再确认，执行完就退出，并返回脚本自己的退出码，
rem 方便快捷方式、计划任务和批处理调用
if /i "%~1"=="check"   goto :arg_check
if /i "%~1"=="apply"   goto :arg_apply
if /i "%~1"=="restore" goto :arg_restore
if not "%~1"=="" goto :bad_arg

rem 这个文件用 GBK 保存，中文只在 936 代码页下正常显示
set "CP="
for /f "tokens=2 delims=:" %%a in ('chcp') do set "CP=%%a"
if defined CP set "CP=%CP: =%"
if not "%CP%"=="936" (
    echo.
    echo [NOTE] This menu is GBK-encoded and meant for code page 936.
    echo        Your console code page is %CP%, so the Chinese text below may look garbled.
    echo        English menu without this problem: VBridger-NoPreview.cmd
    echo.
    pause
)

:menu
cls
echo ==========================================================
echo    VBridger 3D 预览补丁 / no-preview patch   -  unofficial
echo ==========================================================
echo.
echo    1. 自检    check     - 只检查，不写入文件 / dry run
echo    2. 打补丁  apply     - 改 1 个字节，停止渲染 / patch it
echo    3. 回滚    rollback  - 用备份还原 level2 / restore it
echo    0. 退出    exit
echo.
echo ==========================================================
echo.
set "pick="
set /p "pick=请输入编号 / enter number [0-3]: "
if "%pick%"=="1" goto :check
if "%pick%"=="2" goto :apply
if "%pick%"=="3" goto :restore
if "%pick%"=="0" exit /b 0
echo.
echo 无效输入 / invalid input: "%pick%"
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
echo [错误]  未知参数：%~1
echo         可用参数：check / apply / restore，不带参数则打开菜单。
pause
exit /b 2

:check
cls
echo === 1. 自检 / dry run  -  不写入任何文件 / writes nothing ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Check
if defined ACT exit /b %errorlevel%
goto :back

:apply
cls
echo === 2. 打补丁 / apply patch ===
echo.
echo 先完全退出 VBridger，否则写入可能失败。
echo Close VBridger completely first, or the write may fail.
echo.
if defined ACT goto :do_apply
set "yn="
set /p "yn=确认执行? / continue? (Y/N): "
if /i not "%yn%"=="Y" goto :menu
:do_apply
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
if defined ACT exit /b %errorlevel%
goto :back

:restore
cls
echo === 3. 回滚 / rollback ===
echo.
echo 用最新的 level2.bak_* 备份覆盖当前 level2。
echo The newest level2.bak_* backup is copied back over level2.
echo.
if defined ACT goto :do_restore
set "yn="
set /p "yn=确认执行? / continue? (Y/N): "
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
