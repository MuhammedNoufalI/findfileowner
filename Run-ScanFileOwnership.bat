@echo off
REM Get the directory where the batch file is located
set SCRIPT_DIR=%~dp0

REM PowerShell script name
set POWERSHELL_SCRIPT_NAME=Scan-FileOwnership.ps1
set POWERSHELL_SCRIPT_PATH=%SCRIPT_DIR%%POWERSHELL_SCRIPT_NAME%

echo ========================================================================
echo =                 File Ownership Scanner Utility                       =
echo ========================================================================
echo.
echo This batch file will run the PowerShell script to scan for files and
echo folders not owned by the current user.
echo.
echo IMPORTANT: For the script to work correctly and access all file
echo            information, this batch file should be run as Administrator.
echo            If you haven't already, please right-click this .bat file
echo            and choose "Run as administrator".
echo.

REM Check if PowerShell script exists
if not exist "%POWERSHELL_SCRIPT_PATH%" (
    echo ERROR: PowerShell script not found at %POWERSHELL_SCRIPT_PATH%
    echo Please ensure '%POWERSHELL_SCRIPT_NAME%' is in the same directory as this batch file.
    pause
    exit /b 1
)

echo Attempting to run the PowerShell script: %POWERSHELL_SCRIPT_PATH%
echo If the script does not run or you see errors related to execution policy,
echo ensure your system allows PowerShell script execution or that this
echo batch file has successfully bypassed it.
echo.

REM The -ExecutionPolicy Bypass flag is used to allow the script to run even if the policy is restricted.
REM The -NoProfile flag speeds up PowerShell startup.
REM The -File parameter specifies the script file to run.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%POWERSHELL_SCRIPT_PATH%"

echo.
echo ========================================================================
echo Script execution finished.
echo The PowerShell script should have displayed dialog boxes with the status.
echo If an output file was generated, check your Pictures folder (or the script's
echo directory if the Pictures folder was not found).
echo ========================================================================
echo.
pause
