#Requires -RunAsAdministrator

param (
    [string]$ScanPath = "C:\"
)

function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title = "File Ownership Scan"
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

function Start-OwnershipScan {
    # Get current user
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Host "Current logged-in user: $currentUser"

    # Initial dialog
    Show-MessageBox -Message "The script will now scan for files and folders not owned by '$currentUser' under the path '$ScanPath'. This might take a long time depending on the size of the directory. Click OK to start." -Title "Starting Scan"

    $filesNotOwned = [System.Collections.Generic.List[string]]::new()
    $processedCount = 0
    $startTime = Get-Date
    $spinnerChars = @('|','/','-','\')
    $spinnerIndex = 0

    Write-Host "Starting scan in directory: $ScanPath. This may take a long time."
    Write-Host "Please wait..."

    # Determine output path
    try {
        $picturesFolder = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyPictures)
        if (-not ([string]::IsNullOrWhiteSpace($picturesFolder)) -and (Test-Path $picturesFolder)) {
            $dateString = Get-Date -Format "yyyyMMdd"
            $outputFileName = "opti_$($dateString).txt"
            $outputPath = Join-Path -Path $picturesFolder -ChildPath $outputFileName
        } else {
            Write-Warning "Could not determine the Pictures folder. Saving output to script directory instead."
            $dateString = Get-Date -Format "yyyyMMdd"
            $outputFileName = "opti_$($dateString).txt" # Keep consistent naming
            $outputPath = Join-Path -Path $PSScriptRoot -ChildPath $outputFileName
        }
        Write-Host "Output will be saved to: $outputPath"
    }
    catch {
        Write-Warning "Error determining Pictures folder path: $($_.Exception.Message). Saving output to script directory."
        $dateString = Get-Date -Format "yyyyMMdd"
        $outputFileName = "opti_$($dateString).txt" # Keep consistent naming
        $outputPath = Join-Path -Path $PSScriptRoot -ChildPath $outputFileName
        Write-Host "Output will be saved to: $outputPath"
    }


    try {
        # Get all items (files and directories)
        # Using -PipelineVariable to process items as they come in, which can be more memory efficient
        # However, for a simple spinner, iterating after Get-ChildItem completes is fine.
        # For very large directories, consider advanced techniques if performance becomes an issue.
        $items = Get-ChildItem -Path $ScanPath -Recurse -Force -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            $processedCount++
            if ($processedCount % 200 -eq 0) { # Update spinner more frequently
                Write-Host "`rScanning... $($spinnerChars[$spinnerIndex]) (Processed: $processedCount)" -NoNewline
                $spinnerIndex = ($spinnerIndex + 1) % $spinnerChars.Length
                # Add a small delay if updates are too fast to be visible, though Get-FileOwner will likely add enough delay
                # Start-Sleep -Milliseconds 50
            }

            $owner = Get-FileOwner -Path $item.FullName
            if ($owner -and $owner -ne $currentUser) {
                $filesNotOwned.Add("Path: $($item.FullName) - Owner: $owner")
            }
        }

        # $outputPath is now determined before this try block
        $filesNotOwned | Set-Content -Path $outputPath

        # Clear the spinner line
        Write-Host "`r" + (" " * 50) + "`r"
        $endTime = Get-Date
        $duration = $endTime - $startTime
        Write-Host "Scan completed. Processed $processedCount items."
        Write-Host "Total duration: $($duration.ToString('hh\:mm\:ss'))"

        if ($filesNotOwned.Count -gt 0) {
            Show-MessageBox -Message "Scan complete. Found $($filesNotOwned.Count) files/folders not owned by $currentUser. Results saved to '$outputPath'." -Title "Scan Finished"
        } else {
            Show-MessageBox -Message "Scan complete. All files/folders checked are owned by $currentUser. Results file '$outputPath' created (it will be empty or only contain warnings)." -Title "Scan Finished"
        }
    }
    catch {
        $errorMessage = "An error occurred during the scan: $($_.Exception.Message)"
        Write-Error $errorMessage
        Show-MessageBox -Message "$errorMessage`nPlease check the console for more details." -Title "Scan Failed"
    }
}

# --- Script Entry Point ---
# Check if running as Administrator
$currentUserPrincipal = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUserPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script needs to be run as Administrator to access all file ownership information."
    if ($Host.UI.RawUI -is [System.Management.Automation.Host.InternalHostRawUserInterface]) {
        # Console host, add a pause if not admin
        Read-Host "Press Enter to acknowledge this message and see the pop-up dialog."
    }
    Show-MessageBox -Message "This script needs to be run as Administrator to access all file ownership information. Please re-run as Administrator." -Title "Administrator Privileges Required"
    exit 1
}

Start-OwnershipScan
