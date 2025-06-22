#Requires -RunAsAdministrator

param (
    [string]$ScanPathOrMode = "ALL_LOCAL_FIXED" # Default to scan all local fixed drives
)

function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title = "System Optimization" # Generic Title
    )
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

function Get-FileOwner {
    param (
        [string]$Path
    )
    try {
        $acl = Get-Acl -Path $Path -ErrorAction Stop
        return $acl.Owner
    }
    catch {
        Write-Warning "Could not retrieve owner for $Path. Error: $($_.Exception.Message)"
        return $null
    }
}

# Refactored core scanning logic for a single path
function Invoke-PathScan {
    param (
        [Parameter(Mandatory=$true)]
        [string]$CurrentScanPath,
        [Parameter(Mandatory=$true)]
        [string]$CurrentLoggedInUser
    )

    $filesNotOwned = [System.Collections.Generic.List[PSObject]]::new()
    $processedCount = 0
    $startTime = Get-Date
    $spinnerChars = @('|','/','-','\')
    $spinnerIndex = 0

    Write-Host "Starting system optimization process for path: $CurrentScanPath. This may take some time."
    Write-Host "Please wait..."

    # Determine output path and filename for CSV
    $dateString = Get-Date -Format "yyyyMMdd"
    $sanitizedScanPathPart = $CurrentScanPath -replace ':', '' -replace '\\', '_' -replace '/', '_'
    if ($sanitizedScanPathPart.EndsWith('_')) {
        $sanitizedScanPathPart = $sanitizedScanPathPart.Substring(0, $sanitizedScanPathPart.Length -1)
    }
    if ($sanitizedScanPathPart -eq ($CurrentScanPath -replace ':', '').Split('\')[0] -and $CurrentScanPath.Contains(":\")) { # Root path like C_ or D_
         # Check if it's a root path like C:\, D:\ etc.
        if ($CurrentScanPath -match '^[A-Za-z]:\\?$') {
            $sanitizedScanPathPart = ($CurrentScanPath -replace ':', '').Substring(0,1) + "_ROOT"
        }
    }
    $outputFileName = "opti_$($dateString)_$($sanitizedScanPathPart).csv"
    $outputPath = Join-Path -Path $PSScriptRoot -ChildPath $outputFileName

    try {
        $items = Get-ChildItem -Path $CurrentScanPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Found $($items.Count) items to process for $CurrentScanPath..."

        foreach ($item in $items) {
            $processedCount++
            if ($processedCount % 200 -eq 0) {
                Write-Host "`rProcessing $CurrentScanPath`: Item $processedCount of $($items.Count)... $($spinnerChars[$spinnerIndex])" -NoNewline
                $spinnerIndex = ($spinnerIndex + 1) % $spinnerChars.Length
            }

            $owner = Get-FileOwner -Path $item.FullName
            if ($owner -and $owner -ne $CurrentLoggedInUser) {
                $obj = [PSCustomObject]@{
                    Path = $item.FullName
                    Owner = $owner
                }
                $filesNotOwned.Add($obj)
            }
        }

        if ($filesNotOwned.Count -gt 0) {
            $filesNotOwned | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        } else {
            $emptyCsvHeaders = """Path"",""Owner"""
            Set-Content -Path $outputPath -Value $emptyCsvHeaders -Encoding UTF8
        }

        Write-Host "`r" + (" " * (Write-Host "" -NoNewline | Measure-Object -Character).Characters) + "`r" # Clear line
        $endTime = Get-Date
        $duration = $endTime - $startTime
        Write-Host "Optimization process completed for $CurrentScanPath. Processed $processedCount items. Log: $outputFileName"
        Write-Host "Total duration: $($duration.ToString('hh\:mm\:ss'))"

        # This message box is per-path. An overall one will be outside the loop.
        # Show-MessageBox -Message "The system optimization task has completed for $CurrentScanPath. Details logged to $outputFileName." -Title "Optimization Complete"
    }
    catch {
        $exceptionMessageText = $_.Exception.Message # Store message
        $errorMessage = 'An error occurred during the optimization task for {0}: {1}' -f $CurrentScanPath, $exceptionMessageText
        Write-Error $errorMessage
        # Show-MessageBox -Message ('An error occurred during the optimization task for {0}: {1}`nPlease check the console for more details.' -f $CurrentScanPath, $exceptionMessageText) -Title "Optimization Task Failed"
    }
}

# --- Script Entry Point ---
# Check if running as Administrator
$currentUserPrincipal = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUserPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This process requires Administrator privileges to function correctly."
    if ($Host.UI.RawUI -is [System.Management.Automation.Host.InternalHostRawUserInterface]) {
        Read-Host "Press Enter to acknowledge this message and see the pop-up dialog."
    }
    Show-MessageBox -Message "This process requires Administrator privileges to run. Please re-run as Administrator." -Title "Administrator Privileges Required"
    exit 1
}

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$pathsToScan = [System.Collections.Generic.List[string]]::new()
$operationDescription = ""
$statusLogFile = Join-Path -Path $PSScriptRoot -ChildPath "_optimization_status.log"
$completedPaths = [System.Collections.Generic.List[string]]::new()

# Load completed paths if status log exists
if (Test-Path $statusLogFile) {
    Get-Content $statusLogFile | ForEach-Object { $completedPaths.Add($_) }
    Write-Host "Loaded $($completedPaths.Count) previously completed paths from $statusLogFile"
}

if ($ScanPathOrMode -eq "ALL_LOCAL_FIXED" -or [string]::IsNullOrWhiteSpace($ScanPathOrMode)) {
    $operationDescription = "all local fixed drives"
    Write-Host "Identifying all local fixed drives for optimization using Get-Volume..." # Updated message

    # Use Get-Volume for more robust drive detection
    $volumes = Get-Volume | Where-Object {
        ($_.DriveLetter -ne $null) -and
        ($_.FileSystem -ne $null) -and
        ($_.FileSystem -ne 'Unknown') -and
        ($_.HealthStatus -eq 'Healthy') -and
        ($_.DriveType -eq 'Fixed')
    }
    # Transform to the expected object structure with Name and Root properties
    $allFixedDrives = $volumes | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.DriveLetter; # This is just the letter, e.g., C
            Root = "$($_.DriveLetter):\" # This constructs C:\, D:\ etc.
        }
    }

    if ($allFixedDrives.Count -eq 0) {
        Show-MessageBox -Message "No suitable local fixed drives found to process. Ensure drives are healthy, formatted, and reported as 'Fixed' type by Get-Volume." -Title "System Optimization" # Updated message
        exit
    }

    foreach ($drive in $allFixedDrives) {
        $driveRoot = $drive.Root # e.g., C:\
        if ($completedPaths.Contains($driveRoot)) {
            Write-Host "Skipping already completed drive: $driveRoot"
        } else {
            $pathsToScan.Add($driveRoot)
        }
    }
    if ($pathsToScan.Count -eq 0 -and $allFixedDrives.Count -gt 0) { # All drives were previously completed
         Show-MessageBox -Message "All local fixed drives were already processed in previous sessions. To re-run, delete the '$statusLogFile' file from the script directory." -Title "System Optimization"
         exit
    }
} else { # Specific path mode
    if (Test-Path -LiteralPath $ScanPathOrMode) {
        $pathsToScan.Add($ScanPathOrMode)
        $operationDescription = "the specified path: $ScanPathOrMode"
        # In specific path mode, we don't skip based on status log, always process.
    } else {
        Show-MessageBox -Message "The specified ScanPath '$ScanPathOrMode' is invalid or not found." -Title "Configuration Error"
        exit
    }
}

if ($pathsToScan.Count -eq 0) {
    Show-MessageBox -Message "No paths identified for processing." -Title "System Optimization"
    exit
}

# Initial dialog based on what will be scanned
$scanCountDescription = if ($pathsToScan.Count -eq 1) { $pathsToScan[0] } else { "$($pathsToScan.Count) paths/drives" }
Show-MessageBox -Message "The system will now perform a clean-up and optimization task for $scanCountDescription (overall scope: $operationDescription). This might take some time. Click OK to start." -Title "System Optimization"

$overallStartTime = Get-Date
Write-Host "Overall optimization process started at $overallStartTime for $operationDescription (targeting: $($pathsToScan -join ', '))"

$allScansSuccessful = $true
foreach ($path in $pathsToScan) {
    try {
        Invoke-PathScan -CurrentScanPath $path -CurrentLoggedInUser $currentUser
        # If Invoke-PathScan was successful and we are in ALL_LOCAL_FIXED mode, log completion
        if (($ScanPathOrMode -eq "ALL_LOCAL_FIXED" -or [string]::IsNullOrWhiteSpace($ScanPathOrMode))) {
            if (-not $completedPaths.Contains($path)) { # Add if not already (e.g. from current session if script ran for a very long time)
                Add-Content -Path $statusLogFile -Value $path
                $completedPaths.Add($path) # Keep runtime list updated
                Write-Host "Successfully processed and marked $path as complete in $statusLogFile."
            }
        }
    }
    catch {
        # Error from Invoke-PathScan itself (though it has its own internal try-catch for Get-Acl)
        # This catch is more for unexpected errors in Invoke-PathScan or if it re-throws
        $exceptionMessageText = $_.Exception.Message # Store message
        Write-Error ('A critical error occurred while processing {0}: {1}' -f $path, $exceptionMessageText)
        $allScansSuccessful = $false
        Show-MessageBox -Message ('A critical error occurred processing {0} ({1}). Check console. Subsequent paths may be skipped or processed.' -f $path, $exceptionMessageText) -Title "Critical Error"
        # Depending on severity, might want to break or continue
    }
}

$overallEndTime = Get-Date
$overallDuration = $overallEndTime - $overallStartTime
$completionMessage = "The system optimization task for $operationDescription has completed."
if (-not $allScansSuccessful) {
    $completionMessage += " Some paths may have encountered errors."
}
$completionMessage += " Details have been logged to respective CSV files in the script's directory."
if (($ScanPathOrMode -eq "ALL_LOCAL_FIXED" -or [string]::IsNullOrWhiteSpace($ScanPathOrMode))) {
    $completionMessage += " To re-process completed drives, delete '$statusLogFile'."
}

Write-Host "Overall optimization process finished at $overallEndTime. Total duration: $($overallDuration.ToString('hh\:mm\:ss'))"
Show-MessageBox -Message $completionMessage -Title "Optimization Complete"
