<#
.SYNOPSIS
    pvm uninstaller for Windows
.DESCRIPTION
    Completely removes pvm (Python Version Manager) from the system,
    including all installed Python versions, configuration, PATH entries,
    and pip mirror settings.
.NOTES
    Run this script in PowerShell.
    Usage: powershell -ExecutionPolicy Bypass -File uninstall.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallDir = '',
    [Parameter()]
    [switch]$Force
)

# Determine install directory: parameter > PVM_HOME env var > default
if ([string]::IsNullOrEmpty($InstallDir)) {
    if ($env:PVM_HOME) {
        $InstallDir = $env:PVM_HOME
    }
    else {
        $InstallDir = Join-Path $env:USERPROFILE ".pvm"
    }
}

# Configuration
$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Uninstall-Pvm {
    Write-ColorOutput "" "Cyan"
    Write-ColorOutput "==================================" "Cyan"
    Write-ColorOutput "  pvm - Python Version Manager" "Cyan"
    Write-ColorOutput "  Windows Uninstaller" "Cyan"
    Write-ColorOutput "==================================" "Cyan"
    Write-ColorOutput "" "Cyan"

    # Check if pvm is installed
    if (-not (Test-Path $InstallDir)) {
        Write-ColorOutput "pvm is not installed at: $InstallDir" "Yellow"
        Write-ColorOutput "Nothing to uninstall." "Yellow"
        Write-ColorOutput "" "White"
        return
    }

    # List what will be removed
    $versionsDir = Join-Path $InstallDir "versions"
    $installedVersions = @()
    if (Test-Path $versionsDir) {
        $installedVersions = Get-ChildItem -Path $versionsDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    }

    Write-ColorOutput "This will completely remove pvm from your system:" "Yellow"
    Write-ColorOutput "" "White"
    Write-ColorOutput "  Installation directory:" "White"
    Write-ColorOutput "    $InstallDir" "Cyan"
    Write-ColorOutput "" "White"

    if ($installedVersions.Count -gt 0) {
        Write-ColorOutput "  Python versions to be removed:" "White"
        foreach ($v in $installedVersions) {
            Write-ColorOutput "    - $v" "Cyan"
        }
        Write-ColorOutput "" "White"
    }

    Write-ColorOutput "  PATH entries to be removed:" "White"
    $pvmPaths = @(
        $InstallDir,
        (Join-Path $InstallDir "shims"),
        (Join-Path $InstallDir "python"),
        (Join-Path $InstallDir "python\Scripts")
    )
    foreach ($p in $pvmPaths) {
        Write-ColorOutput "    - $p" "DarkGray"
    }
    Write-ColorOutput "" "White"

    if ($env:PVM_HOME) {
        Write-ColorOutput "  Environment variables to be removed:" "White"
        Write-ColorOutput "    - PVM_HOME = $env:PVM_HOME" "DarkGray"
        Write-ColorOutput "" "White"
    }

    $pipConfigFile = Join-Path $env:APPDATA "pip\pip.ini"
    if (Test-Path $pipConfigFile) {
        Write-ColorOutput "  pip mirror config (may be removed):" "White"
        Write-ColorOutput "    $pipConfigFile" "DarkGray"
        Write-ColorOutput "" "White"
    }

    # Confirm unless -Force
    if (-not $Force) {
        Write-Host ""
        $confirm = Read-Host "Are you sure you want to uninstall pvm? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y' -and $confirm -ne 'yes' -and $confirm -ne 'Yes') {
            Write-ColorOutput "Uninstall cancelled." "Yellow"
            Write-ColorOutput "" "White"
            return
        }
    }

    Write-ColorOutput "" "White"

    # Step 1: Remove pvm paths from user PATH
    Write-ColorOutput "[1/4] Removing PATH entries..." "Yellow"
    try {
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($userPath) {
            $pathParts = $userPath -split ';' | Where-Object { $_ -ne '' }
            $filteredParts = $pathParts | Where-Object {
                $part = $_.TrimEnd('\')
                $keep = $true
                foreach ($pvmP in $pvmPaths) {
                    if ($part -eq $pvmP.TrimEnd('\')) {
                        $keep = $false
                        break
                    }
                }
                $keep
            }
            $newPath = ($filteredParts -join ';')
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            Write-ColorOutput "      PATH cleaned successfully." "Green"
        }
    }
    catch {
        Write-ColorOutput "      Warning: Could not clean PATH automatically." "Yellow"
        Write-ColorOutput "      Please remove these paths manually:" "Yellow"
        foreach ($p in $pvmPaths) {
            Write-ColorOutput "        $p" "Cyan"
        }
    }

    # Also clean current process PATH so the change is visible immediately
    $procPath = $env:Path
    if ($procPath) {
        $procParts = $procPath -split ';' | Where-Object { $_ -ne '' }
        $procFiltered = $procParts | Where-Object {
            $part = $_.TrimEnd('\')
            $keep = $true
            foreach ($pvmP in $pvmPaths) {
                if ($part -eq $pvmP.TrimEnd('\')) {
                    $keep = $false
                    break
                }
            }
            $keep
        }
        $env:Path = ($procFiltered -join ';')
    }

    # Remove PVM_HOME environment variable
    try {
        $currentPvmHome = [Environment]::GetEnvironmentVariable("PVM_HOME", "User")
        if ($currentPvmHome) {
            [Environment]::SetEnvironmentVariable("PVM_HOME", $null, "User")
            $env:PVM_HOME = $null
            Write-ColorOutput "      PVM_HOME environment variable removed." "Green"
        }
    }
    catch {
        Write-ColorOutput "      Warning: Could not remove PVM_HOME environment variable." "Yellow"
    }

    # Step 2: Ask about pip config
    Write-ColorOutput "[2/4] Checking pip configuration..." "Yellow"
    if (Test-Path $pipConfigFile) {
        $removePip = $false
        if (-not $Force) {
            Write-Host ""
            $pipConfirm = Read-Host "Remove pip mirror config ($pipConfigFile)? (y/N)"
            if ($pipConfirm -eq 'y' -or $pipConfirm -eq 'Y' -or $pipConfirm -eq 'yes' -or $pipConfirm -eq 'Yes') {
                $removePip = $true
            }
        }
        else {
            $removePip = $true
        }

        if ($removePip) {
            try {
                Remove-Item -Path $pipConfigFile -Force
                # Remove pip config directory if empty
                $pipConfigDir = Split-Path $pipConfigFile -Parent
                $remaining = Get-ChildItem -Path $pipConfigDir -ErrorAction SilentlyContinue
                if ($remaining.Count -eq 0) {
                    Remove-Item -Path $pipConfigDir -Force
                }
                Write-ColorOutput "      pip config removed." "Green"
            }
            catch {
                Write-ColorOutput "      Warning: Could not remove pip config." "Yellow"
            }
        }
        else {
            Write-ColorOutput "      pip config kept." "DarkGray"
        }
    }
    else {
        Write-ColorOutput "      No pip config found, skipping." "DarkGray"
    }

    # Step 3: Remove the .pvm directory
    Write-ColorOutput "[3/4] Removing pvm installation directory..." "Yellow"
    try {
        # Remove junction/symlink first to avoid issues
        $symlinkPath = Join-Path $InstallDir "python"
        if (Test-Path $symlinkPath) {
            $symItem = Get-Item $symlinkPath -Force -ErrorAction SilentlyContinue
            if ($symItem -and $symItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $symItem.Delete()
            }
            else {
                Remove-Item -Path $symlinkPath -Force -Recurse -ErrorAction SilentlyContinue
            }
        }

        Remove-Item -Path $InstallDir -Recurse -Force
        Write-ColorOutput "      Directory removed: $InstallDir" "Green"
    }
    catch {
        Write-ColorOutput "      Error: Could not fully remove $InstallDir" "Red"
        Write-ColorOutput "      $_" "Red"
        Write-ColorOutput "      You may need to remove it manually." "Yellow"
    }

    # Step 4: Summary
    Write-ColorOutput "[4/4] Cleanup complete." "Yellow"

    Write-ColorOutput "" "White"
    Write-ColorOutput "==============================================" "Green"
    Write-ColorOutput "  pvm has been uninstalled successfully!" "Green"
    Write-ColorOutput "==============================================" "Green"
    Write-ColorOutput "" "White"
    Write-ColorOutput "  Removed:" "White"
    Write-ColorOutput "    - pvm installation directory" "DarkGray"
    if ($installedVersions.Count -gt 0) {
        Write-ColorOutput "    - $($installedVersions.Count) Python version(s)" "DarkGray"
    }
    Write-ColorOutput "    - PATH entries" "DarkGray"
    Write-ColorOutput "    - PVM_HOME environment variable" "DarkGray"
    Write-ColorOutput "" "White"
    Write-ColorOutput "  Note: Open a new terminal window for changes to take effect." "Yellow"
    Write-ColorOutput "" "White"
}

# Run uninstaller
Uninstall-Pvm
