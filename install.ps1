<#
.SYNOPSIS
    pvm installer for Windows
.DESCRIPTION
    Installs pvm (Python Version Manager) on Windows systems.
    Downloads and sets up pvm in the user's home directory.
.NOTES
    Run this script in PowerShell with administrator privileges for best results.
    Usage: irm https://raw.githubusercontent.com/violet27chen/pym/main/install.ps1 | iex
    CDN:   $env:PVM_CDN=1; irm https://cdn.jsdelivr.net/gh/violet27chen/pym@main/install.ps1 | iex
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallDir = '',
    [Parameter()]
    [switch]$CDN
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

$ErrorActionPreference = "Stop"

# Configuration
$PVM_REPO = "https://github.com/violet27chen/pym.git"
$PVM_RAW_BASE = "https://raw.githubusercontent.com/violet27chen/pym/main"
$PVM_CDN_BASE = "https://cdn.jsdelivr.net/gh/violet27chen/pym@main"

# Determine download source priority
# CDN mode: env var, parameter, or auto-detect (when piped via iex -> prioritize CDN)
$useCdn = $CDN -or ($env:PVM_CDN -eq '1')
if (-not $useCdn -and -not $PSScriptRoot) {
    # Script is being piped via iex (no script file path), default to CDN priority
    $useCdn = $true
}

if ($useCdn) {
    $downloadSources = @(
        @{ Name = "jsDelivr CDN"; Base = $PVM_CDN_BASE },
        @{ Name = "GitHub"; Base = $PVM_RAW_BASE }
    )
}
else {
    $downloadSources = @(
        @{ Name = "GitHub"; Base = $PVM_RAW_BASE },
        @{ Name = "jsDelivr CDN"; Base = $PVM_CDN_BASE }
    )
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# UTF-8 without BOM writer (avoids BOM issues with .cmd/.ps1 files)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false
function Write-FileNoBom {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}
function Write-FileAscii {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

# Reliable HTTP client (WebClient handles User-Agent correctly in PS 5.1)
function Get-UrlText {
    param([string]$Url)
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "pvm-installer/1.0.0")
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.DownloadString($Url)
}

function Install-Pvm {
    Write-ColorOutput "`n==================================" "Cyan"
    Write-ColorOutput "  pvm - Python Version Manager" "Cyan"
    Write-ColorOutput "  Windows Installer" "Cyan"
    Write-ColorOutput "==================================`n" "Cyan"

    # Show download source priority
    $primarySource = $downloadSources[0].Name
    Write-ColorOutput "Download source: $primarySource (fallback: $($downloadSources[1].Name))" "DarkGray"

    # Create installation directory
    Write-ColorOutput "Installing pvm to: $InstallDir" "Yellow"
    
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Create subdirectories
    $versionsDir = Join-Path $InstallDir "versions"
    if (-not (Test-Path $versionsDir)) {
        New-Item -ItemType Directory -Path $versionsDir -Force | Out-Null
    }

    # Download pvm files
    Write-ColorOutput "Downloading pvm scripts..." "Yellow"
    
    $windowsDir = Join-Path $InstallDir "windows"
    if (-not (Test-Path $windowsDir)) {
        New-Item -ItemType Directory -Path $windowsDir -Force | Out-Null
    }

    $downloaded = $false

    foreach ($source in $downloadSources) {
        if ($downloaded) { break }
        try {
            Write-ColorOutput "  Trying $($source.Name)..." "DarkGray"
            $ps1Content = Get-UrlText -Url "$($source.Base)/windows/pvm.ps1"
            Write-FileNoBom (Join-Path $windowsDir "pvm.ps1") $ps1Content

            $cmdContent = Get-UrlText -Url "$($source.Base)/windows/pvm.cmd"
            Write-FileAscii (Join-Path $windowsDir "pvm.cmd") $cmdContent

            $elevateContent = Get-UrlText -Url "$($source.Base)/windows/elevate.cmd"
            Write-FileAscii (Join-Path $windowsDir "elevate.cmd") $elevateContent

            # Download uninstall script
            $uninstallContent = Get-UrlText -Url "$($source.Base)/uninstall.ps1"
            Write-FileNoBom (Join-Path $InstallDir "uninstall.ps1") $uninstallContent

            Write-ColorOutput "  Downloaded from $($source.Name)." "Green"
            $downloaded = $true
        }
        catch {
            Write-ColorOutput "  $($source.Name) failed: $($_.Exception.Message)" "DarkGray"
        }
    }

    if (-not $downloaded) {
        Write-ColorOutput "Remote download failed. Trying local files..." "Yellow"
        
        # If running from cloned repo, copy local files
        $scriptDir = $null
        if ($PSScriptRoot) {
            $scriptDir = $PSScriptRoot
        }
        elseif ($MyInvocation.MyCommand.Path) {
            $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        elseif (Test-Path "$PWD\windows\pvm.ps1") {
            $scriptDir = $PWD.Path
        }
        
        if ($scriptDir -and (Test-Path (Join-Path $scriptDir "windows\pvm.ps1"))) {
            Copy-Item -Path (Join-Path $scriptDir "windows\*") -Destination $windowsDir -Force
            # Copy uninstall script
            if (Test-Path (Join-Path $scriptDir "uninstall.ps1")) {
                Copy-Item -Path (Join-Path $scriptDir "uninstall.ps1") -Destination $InstallDir -Force
            }
            Write-ColorOutput "Local files copied successfully." "Green"
        }
        else {
            throw "Failed to download pvm scripts and no local files found. Please run install.ps1 from the pvm repository directory."
        }
    }

    # Create root pvm.cmd wrapper
    $rootCmdPath = Join-Path $InstallDir "pvm.cmd"
    $rootCmdContent = @"
@echo off
"%~dp0windows\pvm.cmd" %*
"@
    Write-FileAscii $rootCmdPath $rootCmdContent

    # Create default settings
    $settingsPath = Join-Path $InstallDir "settings.json"
    if (-not (Test-Path $settingsPath)) {
        $defaultSettings = @{
            mirror = "https://www.python.org/ftp/python"
            mirror_selected = $false
        } | ConvertTo-Json
        Write-FileNoBom $settingsPath $defaultSettings
    }

    # Add to PATH
    Write-ColorOutput "Configuring PATH..." "Yellow"
    
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $pvmPath = $InstallDir
    $pvmPythonPath = Join-Path $InstallDir "python"
    $pvmPythonScriptsPath = Join-Path $pvmPythonPath "Scripts"
    $pvmShimsPath = Join-Path $InstallDir "shims"

    $pathsToAdd = @($pvmPath, $pvmShimsPath, $pvmPythonPath, $pvmPythonScriptsPath)
    $pathModified = $false

    foreach ($pathToAdd in $pathsToAdd) {
        if ($userPath -notlike "*$pathToAdd*") {
            $userPath = "$pathToAdd;$userPath"
            $pathModified = $true
        }
    }

    if ($pathModified) {
        try {
            [Environment]::SetEnvironmentVariable("PATH", $userPath, "User")
            # Refresh current session: merge User PATH + System PATH (no duplicates)
            $systemPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            $env:Path = $userPath + ';' + $systemPath
            Write-ColorOutput "PATH updated successfully." "Green"
        }
        catch {
            Write-ColorOutput "Warning: Could not update PATH automatically." "Yellow"
            Write-ColorOutput "Please add the following to your PATH manually:" "Yellow"
            foreach ($p in $pathsToAdd) {
                Write-ColorOutput "  $p" "Cyan"
            }
        }
    }
    else {
        Write-ColorOutput "PATH already configured." "Green"
    }

    # Create PowerShell profile integration (optional)
    $profileDir = Split-Path $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Success message
    Write-ColorOutput "`n==============================================" "Green"
    Write-ColorOutput "  pvm installed successfully!" "Green"
    Write-ColorOutput "==============================================`n" "Green"

    Write-ColorOutput "IMPORTANT: To activate pvm, do ONE of the following:" "Yellow"
    Write-ColorOutput ""
    Write-ColorOutput "  Option 1 - Refresh PATH in current session:" "White"
    Write-ColorOutput "    `$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + `$env:Path" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  Option 2 - Open a new PowerShell/CMD window" "White"
    Write-ColorOutput ""

    Write-ColorOutput "----------------------------------------------" "White"
    Write-ColorOutput "Quick Start Guide:" "White"
    Write-ColorOutput "----------------------------------------------" "White"
    Write-ColorOutput ""
    Write-ColorOutput "  1. Check available versions:" "White"
    Write-ColorOutput "     pvm list available" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  2. Configure mirror (China users recommended):" "White"
    Write-ColorOutput "     pvm config tsinghua    # Tsinghua mirror" "Cyan"
    Write-ColorOutput "     pvm config huawei      # Huawei Cloud mirror" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  3. Install Python:" "White"
    Write-ColorOutput "     pvm install 3.12.4" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  4. Switch Python version:" "White"
    Write-ColorOutput "     pvm use 3.12.4" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "  5. Verify installation:" "White"
    Write-ColorOutput "     python --version" "Cyan"
    Write-ColorOutput ""

    Write-ColorOutput "----------------------------------------------" "White"
    Write-ColorOutput "All Commands:" "White"
    Write-ColorOutput "----------------------------------------------" "White"
    Write-ColorOutput "  pvm list              - List installed versions" "White"
    Write-ColorOutput "  pvm list available    - List downloadable versions" "White"
    Write-ColorOutput "  pvm install <ver>     - Install a version" "White"
    Write-ColorOutput "  pvm use <ver>         - Switch to a version" "White"
    Write-ColorOutput "  pvm uninstall <ver>   - Remove a version" "White"
    Write-ColorOutput "  pvm current           - Show current version" "White"
    Write-ColorOutput "  pvm which             - Show Python path" "White"
    Write-ColorOutput "  pvm config [mirror]   - Configure download mirror" "White"
    Write-ColorOutput "  pvm arch              - Show system architecture" "White"
    Write-ColorOutput "  pvm --help            - Show help" "White"
    Write-ColorOutput ""
    Write-ColorOutput "  To uninstall pvm:     & `"$InstallDir\uninstall.ps1`"" "DarkGray"
    Write-ColorOutput ""

    Write-ColorOutput "Installation path: $InstallDir" "Green"
    Write-ColorOutput ""
}

# Run installer
Install-Pvm

