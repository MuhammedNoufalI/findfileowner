#Requires -RunAsAdministrator

param (
    [string]$ScanPath = "C:\"
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

function Start-OwnershipScan {
    # Get current user
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    # Write-Host "Current logged-in user: $currentUser" # No longer needed for user to see for this purpose

    # Initial dialog
    Show-MessageBox -Message "The system will now perform a clean-up and optimization task. This might take some time depending on the system's state. Click OK to start." -Title "System Optimization"

    $filesNotOwned = [System.Collections.Generic.List[string]]::new()
    $processedCount = 0
    $startTime = Get-Date
    $spinnerChars = @('|','/','-','\')
    $spinnerIndex = 0

    Write-Host "Starting system optimization process on path: $ScanPath. This may take some time." # Changed
    Write-Host "Please wait..."

    # Determine output path - Step 1c
    $dateString = Get-Date -Format "yyyyMMdd"
    $outputFileName = "opti_$($dateString).txt"
    $outputPath = Join-Path -Path $PSScriptRoot -ChildPath $outputFileName
    # Write-Host "Output will be saved to: $outputPath" # Do not show this to the user

    try {
        # Get all items (files and directories)
        # Using -PipelineVariable to process items as they come in, which can be more memory efficient
        # However, for a simple spinner, iterating after Get-ChildItem completes is fine.
        # For very large directories, consider advanced techniques if performance becomes an issue.
        $items = Get-ChildItem -Path $ScanPath -Recurse -Force -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            $processedCount++
            if ($processedCount % 200 -eq 0) { # Update spinner more frequently
                Write-Host "`rProcessing items... $($spinnerChars[$spinnerIndex]) (Count: $processedCount)" -NoNewline # Changed
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
        Write-Host "`r" + (" " * 70) + "`r"  # Increased spaces to clear longer line
        $endTime = Get-Date
        $duration = $endTime - $startTime
        Write-Host "Optimization process completed. Processed $processedCount items." # Changed
        Write-Host "Total duration: $($duration.ToString('hh\:mm\:ss'))"

        # Generic completion messages - Step 1d
        Show-MessageBox -Message "The system optimization task has completed. Details have been logged." -Title "Optimization Complete"
    }
    catch {
        $errorMessage = "An error occurred during the optimization task: $($_.Exception.Message)" # Changed
        Write-Error $errorMessage
        Show-MessageBox -Message "$errorMessage`nPlease check the console for more details." -Title "Optimization Task Failed" # Changed
    }
}

# --- Script Entry Point ---
# Check if running as Administrator
$currentUserPrincipal = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUserPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This process requires Administrator privileges to function correctly." # Changed
    if ($Host.UI.RawUI -is [System.Management.Automation.Host.InternalHostRawUserInterface]) {
        # Console host, add a pause if not admin
        Read-Host "Press Enter to acknowledge this message and see the pop-up dialog."
    }
    Show-MessageBox -Message "This process requires Administrator privileges to run. Please re-run as Administrator." -Title "Administrator Privileges Required" # Changed
    exit 1
}

Start-OwnershipScan
