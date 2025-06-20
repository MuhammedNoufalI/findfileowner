@echo off
REM Get the directory where the batch file is located
set SCRIPT_DIR=%~dp0

REM PowerShell script name
set POWERSHELL_SCRIPT_NAME=Scan-FileOwnership.ps1
set POWERSHELL_SCRIPT_PATH=%SCRIPT_DIR%%POWERSHELL_SCRIPT_NAME%

echo ========================================================================
echo =                 System Optimization Utility                        =
echo ========================================================================
echo.
echo This utility will perform a system optimization task.
echo.
echo IMPORTANT: For the process to work correctly, this utility
echo            should be run as Administrator.
echo            If you haven't already, please right-click this .bat file
echo            and choose "Run as administrator".
echo.

REM Check if PowerShell script exists
if not exist "%POWERSHELL_SCRIPT_PATH%" (
    echo ERROR: Main component not found at %POWERSHELL_SCRIPT_PATH%
    echo Please ensure '%POWERSHELL_SCRIPT_NAME%' is in the same directory as this batch file.
    pause
    exit /b 1
)

echo Attempting to run the system optimization process...
echo If the process does not run or you see errors related to execution policy,
echo please ensure your system allows PowerShell script execution or that this
echo utility has successfully bypassed it.
echo.

REM The -ExecutionPolicy Bypass flag is used to allow the script to run even if the policy is restricted.
REM The -NoProfile flag speeds up PowerShell startup.
REM The -File parameter specifies the script file to run.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%POWERSHELL_SCRIPT_PATH%"

echo.
echo ========================================================================
echo System optimization process finished.
echo The process should have displayed dialog boxes with the status.
echo If details were logged, the log file is in the same directory as this utility.
echo ========================================================================
echo.
pause
