<#
.SYNOPSIS
    pvm - Python Version Manager for Windows
.DESCRIPTION
    A simple Python version manager that allows you to install, switch between,
    and manage multiple Python versions on Windows.
.NOTES
    Author: pvm contributors
    License: Apache 2.0
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,
    
    [Parameter(Position = 1)]
    [string]$Version,
    
    [Parameter()]
    [ValidateSet('32', '64', 'arm64')]
    [string]$Arch = '',
    
    [Parameter()]
    [Alias('Home')]
    [string]$PvmHomePath = '',
    
    [Parameter()]
    [switch]$Help
)

# Set console output encoding to UTF-8 to prevent encoding issues
if ($PSVersionTable.PSVersion.Major -ge 6) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
} else {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
$OutputEncoding = [System.Text.Encoding]::UTF8

# Configuration
$script:PVM_VERSION = "1.0.0"
$script:PVMHOME_CONFIG = Join-Path $env:USERPROFILE ".pvmhome"

# Determine PVM_HOME
$script:PVM_HOME = $null
if ($PvmHomePath) {
    # --home parameter overrides everything
    $script:PVM_HOME = $PvmHomePath
}
elseif ($env:PVM_HOME) {
    # Environment variable takes priority
    $script:PVM_HOME = $env:PVM_HOME
}
elseif (Test-Path $script:PVMHOME_CONFIG) {
    # Read from saved config
    $saved = Get-Content $script:PVMHOME_CONFIG -Raw | ForEach-Object { $_.Trim() }
    if ($saved -and (Test-Path $saved)) {
        $script:PVM_HOME = $saved
    }
}

# If still not determined, check default or prompt
if (-not $script:PVM_HOME) {
    $defaultHome = Join-Path $env:USERPROFILE ".pvm"
    if (Test-Path $defaultHome) {
        # Default directory already exists, use it silently
        $script:PVM_HOME = $defaultHome
    }
    else {
        # First-time use: prompt interactively
        Write-Host ""
        Write-Host "  Welcome to pvm! First-time setup:" -ForegroundColor Cyan
        Write-Host "  Where should pvm store its data (Python versions, config, etc.)?"
        Write-Host ""
        $input_path = Read-Host "  Data directory [$defaultHome]"
        if ([string]::IsNullOrWhiteSpace($input_path)) {
            $script:PVM_HOME = $defaultHome
        }
        else {
            $script:PVM_HOME = $input_path
        }
        # Save choice for future use
        Set-Content -Path $script:PVMHOME_CONFIG -Value $script:PVM_HOME -Encoding UTF8
        Write-Host "  Saved to $($script:PVMHOME_CONFIG)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# Set all derived paths
$script:PVM_VERSIONS_DIR = Join-Path $script:PVM_HOME "versions"
$script:PVM_CURRENT_FILE = Join-Path $script:PVM_HOME "current"
$script:PVM_SETTINGS_FILE = Join-Path $script:PVM_HOME "settings.json"
$script:PVM_SYMLINK = Join-Path $script:PVM_HOME "python"
$script:PVM_SHIMS_DIR = Join-Path $script:PVM_HOME "shims"
$script:PVM_VENVS_DIR = Join-Path $script:PVM_HOME "venvs"

# Auto-create --home directory if it doesn't exist
if (-not (Test-Path $script:PVM_HOME)) {
    New-Item -ItemType Directory -Path $script:PVM_HOME -Force | Out-Null
    Write-Host "  Created data directory: $($script:PVM_HOME)" -ForegroundColor DarkGray
}

# HTTP User-Agent (avoids CDN 403 errors)
$script:HttpHeaders = @{ "User-Agent" = "pvm/$($script:PVM_VERSION)" }

# Reliable HTTP client (WebClient handles User-Agent correctly in PS 5.1)
function Get-UrlText {
    param([string]$Url, [int]$TimeoutSec = 15)
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", $script:HttpHeaders["User-Agent"])
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.DownloadString($Url)
}

function Save-UrlFile {
    param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 300)
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", $script:HttpHeaders["User-Agent"])
    $wc.DownloadFile($Url, $OutFile)
}

# Default Python download mirror
$script:DEFAULT_MIRROR = "https://www.python.org/ftp/python"

# Preset mirrors for Python download
$script:MIRRORS = @{
    "default"   = "https://www.python.org/ftp/python"
    "tsinghua"  = "https://mirrors.tuna.tsinghua.edu.cn/python"
    "qinghua"   = "https://mirrors.tuna.tsinghua.edu.cn/python"
    "huawei"    = "https://mirrors.huaweicloud.com/python"
    "aliyun"    = "https://mirrors.aliyun.com/python"
}

# Preset mirrors for pip
$script:PIP_MIRRORS = @{
    "default"   = "https://pypi.org/simple"
    "tsinghua"  = "https://pypi.tuna.tsinghua.edu.cn/simple"
    "qinghua"   = "https://pypi.tuna.tsinghua.edu.cn/simple"
    "huawei"    = "https://repo.huaweicloud.com/repository/pypi/simple"
    "aliyun"    = "https://mirrors.aliyun.com/pypi/simple"
}

# Fallback Python versions (used when network is unavailable)
$script:FALLBACK_VERSIONS = @(
    "3.14.6", "3.14.5", "3.14.4", "3.14.3", "3.14.2", "3.14.1", "3.14.0",
    "3.13.14", "3.13.13", "3.13.12", "3.13.11", "3.13.10", "3.13.9", "3.13.8", "3.13.7", "3.13.6", "3.13.5", "3.13.4", "3.13.3", "3.13.2", "3.13.1", "3.13.0",
    "3.12.9", "3.12.8", "3.12.7", "3.12.6", "3.12.5", "3.12.4", "3.12.3", "3.12.2", "3.12.1", "3.12.0",
    "3.11.12", "3.11.11", "3.11.10", "3.11.9", "3.11.8", "3.11.7", "3.11.6", "3.11.5", "3.11.4", "3.11.3", "3.11.2", "3.11.1", "3.11.0",
    "3.10.17", "3.10.16", "3.10.15", "3.10.14", "3.10.13", "3.10.12", "3.10.11", "3.10.10", "3.10.9", "3.10.8", "3.10.7", "3.10.6", "3.10.5", "3.10.4", "3.10.3", "3.10.2", "3.10.1", "3.10.0",
    "3.9.22", "3.9.21", "3.9.20", "3.9.19", "3.9.18", "3.9.17", "3.9.16", "3.9.15", "3.9.14", "3.9.13", "3.9.12", "3.9.11", "3.9.10", "3.9.9", "3.9.8", "3.9.7", "3.9.6", "3.9.5", "3.9.4", "3.9.3", "3.9.2", "3.9.1", "3.9.0",
    "3.8.21", "3.8.20", "3.8.19", "3.8.18", "3.8.17", "3.8.16", "3.8.15", "3.8.14", "3.8.13", "3.8.12", "3.8.11", "3.8.10", "3.8.9", "3.8.8", "3.8.7", "3.8.6", "3.8.5", "3.8.4", "3.8.3", "3.8.2", "3.8.1", "3.8.0"
)
$script:AVAILABLE_VERSIONS = $null  # Populated lazily from python.org API

function Get-AvailableVersions {
    <#
    .SYNOPSIS
        Fetch available Python versions. Priority: CDN versions.json -> python.org API -> fallback list.
    #>
    if ($script:AVAILABLE_VERSIONS -and $script:AVAILABLE_VERSIONS.Count -gt 0) {
        return $script:AVAILABLE_VERSIONS
    }

    $cacheFile = Join-Path $script:PVM_HOME "versions_cache.json"

    # 1. Try local cache (< 24h)
    if (Test-Path $cacheFile) {
        $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($cacheAge.TotalHours -lt 24) {
            try {
                $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
                if ($cached.versions -and $cached.versions.Count -gt 0) {
                    $script:AVAILABLE_VERSIONS = @($cached.versions)
                    return $script:AVAILABLE_VERSIONS
                }
            }
            catch { }
        }
    }

    # 2. Try jsDelivr CDN (global, fast)
    Write-Host "  Fetching versions from CDN..." -ForegroundColor DarkGray
    $cdnUrls = @(
        "https://cdn.jsdelivr.net/gh/violet27chen/pym@main/versions.json",
        "https://raw.githubusercontent.com/violet27chen/pym/main/versions.json"
    )
    foreach ($url in $cdnUrls) {
        try {
            $responseText = Get-UrlText -Url $url -TimeoutSec 10
            $data = $responseText | ConvertFrom-Json
            if ($data.versions -and $data.versions.Count -gt 0) {
                $script:AVAILABLE_VERSIONS = @($data.versions)
                # Cache locally
                $data | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8
                return $script:AVAILABLE_VERSIONS
            }
        }
        catch { }
    }

    # 3. Try python.org API
    Write-Host "  Trying python.org API..." -ForegroundColor DarkGray
    try {
        $apiText = Get-UrlText -Url "https://www.python.org/api/v2/downloads/release/?is_published=true&pre_release=false" -TimeoutSec 15
        $releases = $apiText | ConvertFrom-Json
        $versions = @()
        foreach ($release in $releases) {
            if ($release.name -match 'Python\s+([\d]+\.[\d]+\.[\d]+)') {
                $versions += $matches[1]
            }
        }
        $versions = $versions | Sort-Object { [version]$_ } -Descending
        if ($versions.Count -gt 0) {
            $script:AVAILABLE_VERSIONS = $versions
            @{ versions = $versions } | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8
            return $script:AVAILABLE_VERSIONS
        }
    }
    catch { }

    # 4. Fallback to built-in list
    Write-Host "  Using built-in version list." -ForegroundColor Yellow
    $script:AVAILABLE_VERSIONS = $script:FALLBACK_VERSIONS
    return $script:AVAILABLE_VERSIONS
}

function Initialize-Pvm {
    <#
    .SYNOPSIS
        Initialize pvm directories and configuration
    #>
    if (-not (Test-Path $script:PVM_HOME)) {
        New-Item -ItemType Directory -Path $script:PVM_HOME -Force | Out-Null
    }
    if (-not (Test-Path $script:PVM_VERSIONS_DIR)) {
        New-Item -ItemType Directory -Path $script:PVM_VERSIONS_DIR -Force | Out-Null
    }
    if (-not (Test-Path $script:PVM_SHIMS_DIR)) {
        New-Item -ItemType Directory -Path $script:PVM_SHIMS_DIR -Force | Out-Null
    }
    if (-not (Test-Path $script:PVM_SETTINGS_FILE)) {
        $defaultSettings = @{
            mirror = $script:DEFAULT_MIRROR
            mirror_selected = $false
        } | ConvertTo-Json
        Set-Content -Path $script:PVM_SETTINGS_FILE -Value $defaultSettings -Encoding UTF8
    }
}

function Get-PvmSettings {
    <#
    .SYNOPSIS
        Get pvm settings from configuration file
    #>
    if (Test-Path $script:PVM_SETTINGS_FILE) {
        try {
            return Get-Content $script:PVM_SETTINGS_FILE -Raw | ConvertFrom-Json
        }
        catch {
            return @{ mirror = $script:DEFAULT_MIRROR }
        }
    }
    return @{ mirror = $script:DEFAULT_MIRROR }
}

function Get-Mirror {
    <#
    .SYNOPSIS
        Get the configured mirror URL
    #>
    $settings = Get-PvmSettings
    if ($settings.mirror) {
        return $settings.mirror
    }
    return $script:DEFAULT_MIRROR
}

function Prompt-MirrorSelection {
    <#
    .SYNOPSIS
        On first install, prompt user to choose a download mirror. Only prompts once.
    #>
    $settings = Get-PvmSettings
    # Already selected a mirror before
    if ($settings.mirror_selected) {
        return
    }

    Write-Host ""
    Write-Host "  Choose a download mirror for Python installations:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    1) python.org (Official)              [default]" -ForegroundColor White
    Write-Host "    2) Tsinghua University (China)        [recommended for China]" -ForegroundColor White
    Write-Host "    3) Huawei Cloud (China)" -ForegroundColor White
    Write-Host "    4) Aliyun (China)" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "  Select mirror [1-4, default=1]"

    $mirrorMap = @{
        "1" = "default"
        "2" = "tsinghua"
        "3" = "huawei"
        "4" = "aliyun"
        ""  = "default"
    }

    $selected = $mirrorMap[$choice]
    if (-not $selected) {
        $selected = "default"
    }

    $mirrorUrl = $script:MIRRORS[$selected]
    Write-Host "  Using mirror: $selected ($mirrorUrl)" -ForegroundColor Green

    # Save to settings
    $settings | Add-Member -NotePropertyName "mirror" -NotePropertyValue $mirrorUrl -Force
    $settings | Add-Member -NotePropertyName "mirror_selected" -NotePropertyValue $true -Force
    $settings | ConvertTo-Json | Set-Content -Path $script:PVM_SETTINGS_FILE -Encoding UTF8
    Write-Host ""
}

function Show-Help {
    <#
    .SYNOPSIS
        Display help information
    #>
    $helpText = @"

pvm - Python Version Manager v$($script:PVM_VERSION)

Usage:
    pvm <command> [options]

Commands:
    list                    List installed Python versions
    list available          List available Python versions for download
    install <version>       Install a specific Python version
    uninstall <version>     Uninstall a specific Python version
    use <version>           Switch to a specific Python version
    current                 Show the currently active Python version
    which                   Show the path to the current Python executable
    config [mirror]         Configure mirror (show current if no argument)
    arch                    Show detected system architecture

    venv <name>             Create a virtual environment
    venv list               List all virtual environments
    venv remove <name>      Remove a virtual environment
    venv activate <name>    Show activation command

    pip install <pkg>       Install a package
    pip uninstall <pkg>     Uninstall a package
    pip list                List installed packages
    pip upgrade <pkg>       Upgrade a package

    init                    Initialize a new project (pyproject.toml)
    add <pkg>               Add a dependency
    remove <pkg>            Remove a dependency
    run <cmd>               Run a command in project venv

    --help, -h              Show this help message
    --version, -v           Show pvm version

Options:
    --arch <32|64|arm64>    Architecture for install (auto-detect if not specified)
    --home <path>           Set pvm data directory for this command only (auto-creates if needed)

Mirror Presets:
    tsinghua, qinghua       Tsinghua University (China)
    huawei                  Huawei Cloud (China)
    aliyun                  Aliyun (China)
    default                 python.org (Official)

Examples:
    pvm install 3.12.4           Install Python 3.12.4
    pvm use 3.12.4               Switch to Python 3.12.4
    pvm venv myenv               Create a virtual environment
    pvm pip install requests     Install a package
    pvm init                     Initialize a project
    pvm config tsinghua          Use Tsinghua mirror

Configuration:
    pvm stores data in: $($script:PVM_HOME)

Uninstall pvm:
    Run: & "$($script:PVM_HOME)\uninstall.ps1"

"@
    Write-Host $helpText
}

function Show-Version {
    Write-Host "pvm version $($script:PVM_VERSION)"
}

function Get-InstalledVersions {
    <#
    .SYNOPSIS
        Get list of installed Python versions
    #>
    $versions = @()
    if (Test-Path $script:PVM_VERSIONS_DIR) {
        $dirs = Get-ChildItem -Path $script:PVM_VERSIONS_DIR -Directory
        foreach ($dir in $dirs) {
            $versions += $dir.Name
        }
    }
    return $versions | Sort-Object { [version]($_ -replace '-.*', '') } -Descending
}

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Get the currently active Python version
    #>
    if (Test-Path $script:PVM_CURRENT_FILE) {
        return (Get-Content $script:PVM_CURRENT_FILE -Raw).Trim()
    }
    return $null
}

function Show-InstalledVersions {
    <#
    .SYNOPSIS
        Display installed Python versions
    #>
    $versions = Get-InstalledVersions
    $current = Get-CurrentVersion

    if ($versions.Count -eq 0) {
        Write-Host ""
        Write-Host "  No Python versions installed." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Install one:" -ForegroundColor White
        Write-Host "    pvm install 3.13         # latest 3.13.x" -ForegroundColor Cyan
        Write-Host "    pvm install 3.12.4       # specific version" -ForegroundColor Cyan
        Write-Host "    pvm list available       # see all options" -ForegroundColor Cyan
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "  Installed Python versions ($($versions.Count)):" -ForegroundColor Cyan
    Write-Host ""
    foreach ($v in $versions) {
        if ($v -eq $current) {
            Write-Host "    * $v" -ForegroundColor Green -NoNewline
            Write-Host " (current)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "    $v" -ForegroundColor White
        }
    }
    Write-Host ""
    Write-Host "  Use 'pvm list available' to see downloadable versions." -ForegroundColor DarkGray
    Write-Host ""
}

function Show-AvailableVersions {
    <#
    .SYNOPSIS
        Display available Python versions for download
    #>
    $installed = Get-InstalledVersions
    $available = Get-AvailableVersions
    $current = Get-CurrentVersion

    Write-Host ""
    Write-Host "  Available Python versions ($($available.Count) total, $($installed.Count) installed):" -ForegroundColor Cyan
    Write-Host ""

    $grouped = $available | Group-Object { $_.Split('.')[0..1] -join '.' }

    foreach ($group in $grouped | Sort-Object { [version]$_.Name } -Descending) {
        $installedInGroup = ($group.Group | Where-Object { $installed -contains $_ }).Count
        $marker = if ($installedInGroup -gt 0) { " ($installedInGroup installed)" } else { "" }
        Write-Host "  $($group.Name).x$marker" -ForegroundColor Yellow
        $line = "    "
        foreach ($v in $group.Group) {
            $isInstalled = $installed -contains $v
            $isCurrent = $v -eq $current
            if ($isCurrent) {
                $line += "*$v* "
            }
            elseif ($isInstalled) {
                $line += "[$v] "
            }
            else {
                $line += "$v "
            }
        }
        Write-Host $line
    }
    Write-Host ""
    Write-Host "  *version* = current    [version] = installed    plain = not installed" -ForegroundColor DarkGray
    Write-Host ""
}

function Get-SystemArchitecture {
    <#
    .SYNOPSIS
        Detect system architecture
    #>
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch) {
        'AMD64' { return '64' }
        'x86' { return '32' }
        'ARM64' { return 'arm64' }
        default { return '64' }
    }
}

function Resolve-PythonVersion {
    <#
    .SYNOPSIS
        Resolve a partial version string to the latest full version.
        e.g. "3.13" -> "3.13.14", "3" -> "3.14.6"
        On Windows, skips versions that don't have embeddable packages.
    #>
    param([string]$Version)

    # Already a full version
    if ($Version -match '^\d+\.\d+\.\d+$') {
        return $Version
    }

    # Partial version: match from available versions (already sorted descending)
    $available = Get-AvailableVersions
    $candidates = $available | Where-Object { $_ -like "$Version*" -or $_ -like "$Version.*" }

    foreach ($v in $candidates) {
        # On Windows, verify embeddable package exists before resolving
        if ($env:OS -eq 'Windows_NT') {
            $testUrl = "https://www.python.org/ftp/python/$v/python-$v-embed-amd64.zip"
            try {
                $request = [System.Net.HttpWebRequest]::Create($testUrl)
                $request.UserAgent = "pvm/$($script:PVM_VERSION)"
                $request.Method = "HEAD"
                $request.Timeout = 5000
                $response = $request.GetResponse()
                $response.Close()
                Write-Host "Resolved version: $Version -> $v" -ForegroundColor DarkGray
                return $v
            }
            catch {
                Write-Host "  Skipping $v (no Windows embeddable package)" -ForegroundColor DarkGray
            }
        }
        else {
            # Linux/macOS: always valid (uses python-build-standalone)
            Write-Host "Resolved version: $Version -> $v" -ForegroundColor DarkGray
            return $v
        }
    }

    # Fallback: return first match without checking
    if ($candidates) {
        Write-Host "Resolved version: $Version -> $($candidates[0])" -ForegroundColor DarkGray
        return $candidates[0]
    }

    return $null
}

function Show-PlatformInfo {
    $arch = Get-SystemArchitecture
    $archDisplay = switch ($arch) {
        '64' { 'x86_64 (64-bit)' }
        '32' { 'x86 (32-bit)' }
        'arm64' { 'ARM64' }
    }
    Write-Host ""
    Write-Host "Detected Platform:" -ForegroundColor Cyan
    Write-Host "  OS: Windows"
    Write-Host "  Architecture: $archDisplay"
    Write-Host ""
}

function Get-PresetName {
    <#
    .SYNOPSIS
        Get a human-readable name for a mirror URL
    #>
    param([string]$Url)
    if ($Url -match 'tsinghua') { return 'Tsinghua' }
    if ($Url -match 'huaweicloud') { return 'Huawei' }
    if ($Url -match 'aliyun') { return 'Aliyun' }
    if ($Url -match 'python\.org') { return 'python.org' }
    return 'Custom'
}

function Install-PythonVersion {
    <#
    .SYNOPSIS
        Install a specific Python version
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [string]$Architecture = ''
    )
    
    # Auto-detect architecture if not specified
    if ([string]::IsNullOrEmpty($Architecture)) {
        $Architecture = Get-SystemArchitecture
        Write-Host "Detected architecture: $Architecture" -ForegroundColor DarkGray
    }
    
    # Resolve partial version to full version
    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        if ($Version -match '^\d+(\.\d+)?$') {
            $resolved = Resolve-PythonVersion -Version $Version
            if ($resolved) {
                $Version = $resolved
            }
            else {
                Write-Host "Error: No matching version found for '$Version'" -ForegroundColor Red
                Write-Host "Use 'pvm list available' to see available versions."
                return $false
            }
        }
        else {
            Write-Host "Error: Invalid version format. Use format like '3.13', '3.13.2', or '3'" -ForegroundColor Red
            return $false
        }
    }
    
    # Check if already installed
    $versionDir = Join-Path $script:PVM_VERSIONS_DIR $Version
    if (Test-Path $versionDir) {
        Write-Host "Python $Version is already installed." -ForegroundColor Yellow
        Write-Host "Use 'pvm use $Version' to switch to it."
        return $true
    }
    
    # Determine architecture suffix
    $archSuffix = switch ($Architecture) {
        '32' { 'win32' }
        'arm64' { 'arm64' }
        default { 'amd64' }
    }
    
    $archDisplay = if ($Architecture -eq 'arm64') { 'ARM64' } else { "$Architecture-bit" }

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  Installing Python $Version ($archDisplay)" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""

    # Interactive mirror selection on first install
    Prompt-MirrorSelection
    $mirror = Get-Mirror
    $zipName = "python-$Version-embed-$archSuffix.zip"

    # Build list of mirrors to try (configured first, then fallbacks)
    $allMirrors = @(
        @{ Name = (Get-PresetName $mirror); Url = $mirror },
        @{ Name = "python.org"; Url = "https://www.python.org/ftp/python" },
        @{ Name = "Tsinghua"; Url = "https://mirrors.tuna.tsinghua.edu.cn/python" },
        @{ Name = "Huawei"; Url = "https://mirrors.huaweicloud.com/python" },
        @{ Name = "Aliyun"; Url = "https://mirrors.aliyun.com/python" }
    )
    # Deduplicate: keep first occurrence of each URL
    $seenUrls = @()
    $mirrorsToTry = @()
    foreach ($m in $allMirrors) {
        if ($seenUrls -notcontains $m.Url) {
            $seenUrls += $m.Url
            $mirrorsToTry += $m
        }
    }

    Write-Host "  Package:      $zipName" -ForegroundColor DarkGray
    Write-Host "  Install to:   $versionDir" -ForegroundColor DarkGray
    Write-Host ""
    
    # Create temp directory
    $tempDir = Join-Path $env:TEMP "pvm-install-$Version"
    $zipPath = Join-Path $tempDir $zipName
    
    try {
        # Create temp directory
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        # Download Python embeddable package with mirror fallback
        Write-Host "[1/3] Downloading Python $Version..." -ForegroundColor Yellow

        $downloaded = $false
        foreach ($m in $mirrorsToTry) {
            $url = "$($m.Url)/$Version/$zipName"
            Write-Host "  Trying $($m.Name)... ($url)" -ForegroundColor DarkGray

            try {
                # Use streaming download with progress bar
                $ProgressPreference = 'SilentlyContinue'
                $request = [System.Net.HttpWebRequest]::Create($url)
                $request.UserAgent = "pvm/$($script:PVM_VERSION)"
                $request.Timeout = 300000
                $request.AllowAutoRedirect = $true
                $response = $request.GetResponse()
                $totalBytes = $response.ContentLength
                $stream = $response.GetResponseStream()
                $fileStream = [System.IO.File]::Create($zipPath)
                $buffer = New-Object byte[] 8192
                $totalRead = 0
                $lastProgressTime = [DateTime]::Now

                while ($true) {
                    $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                    if ($bytesRead -eq 0) { break }
                    $fileStream.Write($buffer, 0, $bytesRead)
                    $totalRead += $bytesRead

                    # Update progress every 500ms
                    $now = [DateTime]::Now
                    if (($now - $lastProgressTime).TotalMilliseconds -gt 500) {
                        $lastProgressTime = $now
                        if ($totalBytes -gt 0) {
                            $pct = [math]::Round(($totalRead / $totalBytes) * 100, 1)
                            $mb = [math]::Round($totalRead / 1MB, 1)
                            $totalMb = [math]::Round($totalBytes / 1MB, 1)
                            Write-Host "`r      Downloading: $pct% ($mb / $totalMb MB)  " -NoNewline -ForegroundColor Cyan
                        }
                        else {
                            $mb = [math]::Round($totalRead / 1MB, 1)
                            Write-Host "`r      Downloading: $mb MB  " -NoNewline -ForegroundColor Cyan
                        }
                    }
                }

                $fileStream.Close()
                $stream.Close()
                $response.Close()
                $ProgressPreference = 'Continue'

                Write-Host "`r      Download complete!                    " -ForegroundColor Green
                $downloaded = $true
                break
            }
            catch {
                $ProgressPreference = 'Continue'
                # Close streams to avoid resource leak
                if ($fileStream) { try { $fileStream.Close() } catch { } }
                if ($stream) { try { $stream.Close() } catch { } }
                if ($response) { try { $response.Close() } catch { } }
                Write-Host "`r      $($m.Name) failed: $($_.Exception.Message)          " -ForegroundColor DarkGray
                if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue }
            }
        }

        if (-not $downloaded) {
            Write-Host "Error: Failed to download Python $Version from all mirrors." -ForegroundColor Red
            Write-Host "This version may not be available for $Architecture-bit architecture." -ForegroundColor Yellow
            return $false
        }
        
        # Extract
        Write-Host "[2/3] Extracting files..." -ForegroundColor Yellow
        Expand-Archive -Path $zipPath -DestinationPath $versionDir -Force
        
        # Enable pip by modifying python*._pth file
        $pthFiles = Get-ChildItem -Path $versionDir -Filter "python*._pth"
        foreach ($pthFile in $pthFiles) {
            $content = Get-Content $pthFile.FullName
            $newContent = $content -replace '#import site', 'import site'
            Set-Content -Path $pthFile.FullName -Value $newContent
        }
        
        Write-Host "      Extraction complete!" -ForegroundColor Green
        
        # Download get-pip.py and install pip
        Write-Host "[3/3] Installing pip..." -ForegroundColor Yellow
        $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
        $getPipPath = Join-Path $versionDir "get-pip.py"
        
        try {
            Save-UrlFile -Url $getPipUrl -OutFile $getPipPath
            
            $pythonExe = Join-Path $versionDir "python.exe"
            & $pythonExe $getPipPath --no-warn-script-location 2>&1 | Out-Null
            
            # Install/upgrade setuptools and wheel for a complete environment
            $pipExe = Join-Path $versionDir "Scripts\pip.exe"
            if (Test-Path $pipExe) {
                & $pipExe install --upgrade setuptools wheel --no-warn-script-location 2>&1 | Out-Null
            }
            
            Remove-Item -Path $getPipPath -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Warning: Could not install pip. You may need to install it manually." -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "=============================================" -ForegroundColor Green
        Write-Host "  Python $Version installed successfully!" -ForegroundColor Green
        Write-Host "=============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Location: $versionDir" -ForegroundColor White
        Write-Host ""
        Write-Host "  Next steps:" -ForegroundColor Yellow
        Write-Host "    pvm use $Version        # Switch to this version" -ForegroundColor Cyan
        Write-Host "    python --version        # Verify installation" -ForegroundColor Cyan
        Write-Host ""
        
        return $true
    }
    catch {
        Write-Host "Error: Installation failed - $_" -ForegroundColor Red
        if (Test-Path $versionDir) {
            Remove-Item -Path $versionDir -Recurse -Force
        }
        return $false
    }
    finally {
        # Cleanup temp directory
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Uninstall-PythonVersion {
    <#
    .SYNOPSIS
        Uninstall a specific Python version
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    
    # Resolve partial version to installed version
    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        $resolved = Resolve-InstalledVersion -Version $Version
        if ($resolved) {
            $Version = $resolved
        }
    }
    
    $versionDir = Join-Path $script:PVM_VERSIONS_DIR $Version
    
    if (-not (Test-Path $versionDir)) {
        Write-Host "Error: Python $Version is not installed." -ForegroundColor Red
        return $false
    }
    
    $current = Get-CurrentVersion
    if ($Version -eq $current) {
        Write-Host "Warning: Uninstalling the currently active version." -ForegroundColor Yellow
        # Remove current marker
        if (Test-Path $script:PVM_CURRENT_FILE) {
            Remove-Item -Path $script:PVM_CURRENT_FILE -Force
        }
        # Remove symlink
        if (Test-Path $script:PVM_SYMLINK) {
            $symItem = Get-Item $script:PVM_SYMLINK -Force -ErrorAction SilentlyContinue
            if ($symItem -and $symItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $symItem.Delete()
            }
            else {
                Remove-Item -Path $script:PVM_SYMLINK -Force -Recurse
            }
        }
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  Uninstalling Python $Version" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Location: $versionDir" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Removing files..." -ForegroundColor Yellow
    
    try {
        Remove-Item -Path $versionDir -Recurse -Force
        Write-Host ""
        Write-Host "=============================================" -ForegroundColor Green
        Write-Host "  Python $Version uninstalled successfully!" -ForegroundColor Green
        Write-Host "=============================================" -ForegroundColor Green
        Write-Host ""
        
        # Show remaining versions
        $remaining = Get-InstalledVersions
        if ($remaining.Count -gt 0) {
            Write-Host "  Remaining installed versions:" -ForegroundColor White
            foreach ($v in $remaining) {
                Write-Host "    - $v" -ForegroundColor Cyan
            }
            Write-Host ""
        }
        else {
            Write-Host "  No Python versions remaining." -ForegroundColor Yellow
            Write-Host "  Use 'pvm install <version>' to install a new version." -ForegroundColor White
            Write-Host ""
        }
        
        return $true
    }
    catch {
        Write-Host "Error: Failed to uninstall - $_" -ForegroundColor Red
        return $false
    }
}

function Update-PvmShims {
    <#
    .SYNOPSIS
        Create/update nvm-style shim scripts for instant version switching.
        Shims read the current version file at runtime and forward to the
        correct Python executable, so switching takes effect immediately
        without restarting the terminal.
    #>
    if (-not (Test-Path $script:PVM_SHIMS_DIR)) {
        New-Item -ItemType Directory -Path $script:PVM_SHIMS_DIR -Force | Out-Null
    }

    # --- python.cmd shim ---
    $pythonShim = Join-Path $script:PVM_SHIMS_DIR "python.cmd"
    $pythonShimContent = @'
@echo off
setlocal EnableDelayedExpansion
if defined PVM_HOME (
    set "PVM_H=%PVM_HOME%"
) else (
    set "PVM_H=%USERPROFILE%\.pvm"
)
set /p PVM_CURRENT=<"!PVM_H!\current"
if "!PVM_CURRENT!"=="" (
    echo Error: No Python version active. Run: pvm use ^<version^> 1>&2
    exit /b 1
)
set "PVM_PYTHON=!PVM_H!\versions\!PVM_CURRENT!\python.exe"
if not exist "!PVM_PYTHON!" (
    echo Error: Python !PVM_CURRENT! executable not found. 1>&2
    exit /b 1
)
"!PVM_PYTHON!" %*
exit /b %errorlevel%
'@
    Set-Content -Path $pythonShim -Value $pythonShimContent -Encoding ASCII

    # --- python3.cmd shim ---
    $python3Shim = Join-Path $script:PVM_SHIMS_DIR "python3.cmd"
    Copy-Item -Path $pythonShim -Destination $python3Shim -Force

    # --- pip.cmd shim ---
    $pipShim = Join-Path $script:PVM_SHIMS_DIR "pip.cmd"
    $pipShimContent = @'
@echo off
setlocal EnableDelayedExpansion
if defined PVM_HOME (
    set "PVM_H=%PVM_HOME%"
) else (
    set "PVM_H=%USERPROFILE%\.pvm"
)
set /p PVM_CURRENT=<"!PVM_H!\current"
if "!PVM_CURRENT!"=="" (
    echo Error: No Python version active. Run: pvm use ^<version^> 1>&2
    exit /b 1
)
set "PVM_PIP=!PVM_H!\versions\!PVM_CURRENT!\Scripts\pip.exe"
if not exist "!PVM_PIP!" (
    echo Error: pip not found for Python !PVM_CURRENT!. 1>&2
    exit /b 1
)
"!PVM_PIP!" %*
exit /b %errorlevel%
'@
    Set-Content -Path $pipShim -Value $pipShimContent -Encoding ASCII

    # --- pip3.cmd shim ---
    $pip3Shim = Join-Path $script:PVM_SHIMS_DIR "pip3.cmd"
    Copy-Item -Path $pipShim -Destination $pip3Shim -Force
}

function Resolve-InstalledVersion {
    <#
    .SYNOPSIS
        Resolve a partial version to the latest installed version.
        e.g. "3.13" -> "3.13.2" (if 3.13.2 is installed)
    #>
    param([string]$Version)

    # Already a full version
    if ($Version -match '^\d+\.\d+\.\d+$') {
        return $Version
    }

    # Match from installed versions
    $installed = Get-InstalledVersions
    $matches = $installed | Where-Object { $_ -like "$Version*" -or $_ -like "$Version.*" }
    if ($matches) {
        $resolved = $matches[0]
        Write-Host "Resolved version: $Version -> $resolved" -ForegroundColor DarkGray
        return $resolved
    }

    return $null
}

function Use-PythonVersion {
    <#
    .SYNOPSIS
        Switch to a specific Python version
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    
    # Resolve partial version to installed version
    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        $resolved = Resolve-InstalledVersion -Version $Version
        if ($resolved) {
            $Version = $resolved
        }
    }
    
    $versionDir = Join-Path $script:PVM_VERSIONS_DIR $Version
    
    if (-not (Test-Path $versionDir)) {
        Write-Host "Error: Python $Version is not installed." -ForegroundColor Red
        Write-Host "Use 'pvm install $Version' to install it first."
        return $false
    }
    
    # Update current version file
    Set-Content -Path $script:PVM_CURRENT_FILE -Value $Version -NoNewline
    
    # Create/update symlink
    if (Test-Path $script:PVM_SYMLINK) {
        $item = Get-Item $script:PVM_SYMLINK -Force -ErrorAction SilentlyContinue
        if ($item -and $item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # Junction/symlink: remove without -Recurse to avoid deleting target contents
            $item.Delete()
        }
        else {
            # Regular directory (fallback copy): remove with -Recurse
            Remove-Item -Path $script:PVM_SYMLINK -Force -Recurse
        }
    }
    
    # Try to create symlink (requires admin or developer mode)
    try {
        New-Item -ItemType Junction -Path $script:PVM_SYMLINK -Target $versionDir -Force | Out-Null
    }
    catch {
        # Fallback: copy files (less efficient but works without admin)
        Copy-Item -Path $versionDir -Destination $script:PVM_SYMLINK -Recurse -Force
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "  Switched to Python $Version" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host ""
    
    # Create/update nvm-style shims for instant version switching
    Update-PvmShims
    
    # Show Python version
    $pythonExe = Join-Path $script:PVM_SYMLINK "python.exe"
    if (Test-Path $pythonExe) {
        $versionOutput = & $pythonExe --version 2>&1
        Write-Host "  Python:  $versionOutput" -ForegroundColor White
        
        # Try to get pip version
        $pipExe = Join-Path $script:PVM_SYMLINK "Scripts\pip.exe"
        if (Test-Path $pipExe) {
            try {
                $pipVersion = & $pipExe --version 2>&1
                $pipVersion = $pipVersion -replace ' from.*', ''
                Write-Host "  pip:     $pipVersion" -ForegroundColor White
            }
            catch { }
        }
        
        Write-Host ""
        Write-Host "  Path:    $pythonExe" -ForegroundColor DarkGray
    }
    
    # Check if shims dir or pvm\python is in PATH
    $pvmPythonPath = $script:PVM_SYMLINK
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $shimsInPath = $currentPath -like "*$($script:PVM_SHIMS_DIR)*"
    $pythonInPath = $currentPath -like "*$($script:PVM_SYMLINK)*"
    
    if (-not $shimsInPath -and -not $pythonInPath) {
        Write-Host ""
        Write-Host "  Warning: pvm paths not in PATH" -ForegroundColor Yellow
        Write-Host "  Add these paths to use pvm-managed Python:" -ForegroundColor Yellow
        Write-Host "    $($script:PVM_SHIMS_DIR)" -ForegroundColor Cyan
        Write-Host "    $pvmPythonPath" -ForegroundColor Cyan
        Write-Host "    $pvmPythonPath\Scripts" -ForegroundColor Cyan
    }
    
    Write-Host ""
    return $true
}

function Show-CurrentVersion {
    <#
    .SYNOPSIS
        Show the currently active Python version
    #>
    $current = Get-CurrentVersion
    
    if ($null -eq $current -or $current -eq '') {
        Write-Host ""
        Write-Host "  No Python version is currently active." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  To get started:" -ForegroundColor White
        Write-Host "    pvm list available    # See available versions" -ForegroundColor Cyan
        Write-Host "    pvm install 3.12.4    # Install a version" -ForegroundColor Cyan
        Write-Host "    pvm use 3.12.4        # Activate it" -ForegroundColor Cyan
        Write-Host ""
        return
    }
    
    Write-Host ""
    Write-Host "  Current version: $current" -ForegroundColor Green
    
    $pythonExe = Join-Path $script:PVM_SYMLINK "python.exe"
    if (Test-Path $pythonExe) {
        $versionOutput = & $pythonExe --version 2>&1
        Write-Host "  Python output:   $versionOutput" -ForegroundColor White
        Write-Host "  Path:            $pythonExe" -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Show-WhichPython {
    <#
    .SYNOPSIS
        Show the path to the current Python executable
    #>
    $current = Get-CurrentVersion
    
    if ($null -eq $current -or $current -eq '') {
        Write-Host ""
        Write-Host "  No Python version is currently active." -ForegroundColor Yellow
        Write-Host "  Use 'pvm use <version>' to activate a version." -ForegroundColor White
        Write-Host ""
        return
    }
    
    $pythonExe = Join-Path $script:PVM_SYMLINK "python.exe"
    $pipExe = Join-Path $script:PVM_SYMLINK "Scripts\pip.exe"
    
    Write-Host ""
    Write-Host "  Current version: $current" -ForegroundColor Green
    Write-Host ""
    
    if (Test-Path $pythonExe) {
        Write-Host "  python:  $pythonExe" -ForegroundColor White
    }
    else {
        Write-Host "  python:  (not found)" -ForegroundColor Red
    }
    
    if (Test-Path $pipExe) {
        Write-Host "  pip:     $pipExe" -ForegroundColor White
    }
    else {
        Write-Host "  pip:     (not found)" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

function Set-PvmConfig {
    <#
    .SYNOPSIS
        Configure pvm settings (mirror)
    #>
    param(
        [string]$MirrorName
    )
    
    # If no argument, show current config
    if ([string]::IsNullOrEmpty($MirrorName)) {
        Show-PvmConfig
        return
    }
    
    # Check if it's a preset name
    $mirrorUrl = $null
    if ($script:MIRRORS.ContainsKey($MirrorName.ToLower())) {
        $mirrorUrl = $script:MIRRORS[$MirrorName.ToLower()]
        Write-Host "Using preset mirror: $MirrorName" -ForegroundColor Cyan
    }
    elseif ($MirrorName -match '^https?://') {
        # It's a custom URL
        $mirrorUrl = $MirrorName
        Write-Host "Using custom mirror URL" -ForegroundColor Cyan
    }
    else {
        Write-Host "Error: Unknown mirror '$MirrorName'" -ForegroundColor Red
        Write-Host ""
        Write-Host "Available presets:" -ForegroundColor Yellow
        Write-Host "  tsinghua, qinghua   - Tsinghua University (https://mirrors.tuna.tsinghua.edu.cn/python)"
        Write-Host "  huawei              - Huawei Cloud (https://mirrors.huaweicloud.com/python)"
        Write-Host "  aliyun              - Aliyun (https://mirrors.aliyun.com/python)"
        Write-Host "  default             - python.org (https://www.python.org/ftp/python)"
        Write-Host ""
        Write-Host "Or use a custom URL: pvm config https://your-mirror.com/python"
        return
    }
    
    # Save to settings
    $settings = @{
        mirror = $mirrorUrl
        mirror_selected = $true
    }
    $settings | ConvertTo-Json | Set-Content -Path $script:PVM_SETTINGS_FILE -Encoding UTF8
    
    Write-Host "Python mirror configured: $mirrorUrl" -ForegroundColor Green
    
    # Configure pip mirror
    $pipMirrorUrl = $null
    if ($script:PIP_MIRRORS.ContainsKey($MirrorName.ToLower())) {
        $pipMirrorUrl = $script:PIP_MIRRORS[$MirrorName.ToLower()]
    }
    
    if ($pipMirrorUrl) {
        # Create pip config directory
        $pipConfigDir = Join-Path $env:APPDATA "pip"
        if (-not (Test-Path $pipConfigDir)) {
            New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null
        }
        
        # Write pip.ini (without BOM)
        $pipConfigFile = Join-Path $pipConfigDir "pip.ini"
        $pipConfig = @"
[global]
index-url = $pipMirrorUrl
trusted-host = $([System.Uri]::new($pipMirrorUrl).Host)
"@
        [System.IO.File]::WriteAllBytes($pipConfigFile, [System.Text.Encoding]::UTF8.GetBytes($pipConfig))
        Write-Host "pip mirror configured: $pipMirrorUrl" -ForegroundColor Green
        Write-Host "pip config file: $pipConfigFile" -ForegroundColor DarkGray
    }
}

function Show-PvmConfig {
    <#
    .SYNOPSIS
        Show current pvm configuration
    #>
    $settings = Get-PvmSettings
    $mirror = if ($settings.mirror) { $settings.mirror } else { $script:DEFAULT_MIRROR }

    # Get pip config
    $pipConfigFile = Join-Path $env:APPDATA "pip\pip.ini"
    $pipMirror = "https://pypi.org/simple (default)"
    if (Test-Path $pipConfigFile) {
        $pipContent = Get-Content $pipConfigFile -Raw
        if ($pipContent -match 'index-url\s*=\s*(.+)') {
            $pipMirror = $matches[1].Trim()
        }
    }

    Write-Host ""
    Write-Host "pvm Configuration:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Python mirror: $mirror" -ForegroundColor White
    Write-Host "  pip mirror:    $pipMirror" -ForegroundColor White
    Write-Host ""
    Write-Host "  pvm config:  $($script:PVM_SETTINGS_FILE)" -ForegroundColor DarkGray
    Write-Host "  pip config:  $pipConfigFile" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Available presets (configures both Python and pip):" -ForegroundColor Yellow
    Write-Host "  pvm config tsinghua   - Tsinghua University"
    Write-Host "  pvm config huawei     - Huawei Cloud"
    Write-Host "  pvm config aliyun     - Aliyun"
    Write-Host "  pvm config default    - python.org / pypi.org (Official)"
    Write-Host ""
}

# --- Virtual Environment Management ---

function Get-CurrentPythonExe {
    $current = Get-CurrentVersion
    if (-not $current) { return $null }
    $exe = Join-Path $script:PVM_VERSIONS_DIR "$current\python.exe"
    if (Test-Path $exe) { return $exe }
    return $null
}

function Invoke-PvmVenv {
    param([string]$SubCommand, [string]$Name)

    $venvsDir = $script:PVM_VENVS_DIR
    if (-not (Test-Path $venvsDir)) {
        New-Item -ItemType Directory -Path $venvsDir -Force | Out-Null
    }

    switch ($SubCommand) {
        { $_ -eq '' -or $_ -eq 'create' } {
            if ([string]::IsNullOrEmpty($Name)) {
                Write-Host "Error: Please specify a venv name." -ForegroundColor Red
                Write-Host "Usage: pvm venv <name>"
                return
            }
            $pythonExe = Get-CurrentPythonExe
            if (-not $pythonExe) {
                Write-Host "Error: No Python version active. Run: pvm use <version>" -ForegroundColor Red
                return
            }
            $venvPath = Join-Path $venvsDir $Name
            if (Test-Path $venvPath) {
                Write-Host "Virtual environment '$Name' already exists." -ForegroundColor Yellow
                return
            }
            Write-Host "Creating virtual environment '$Name'..." -ForegroundColor Cyan
            & $pythonExe -m venv $venvPath 2>&1 | Out-Null
            if (Test-Path $venvPath) {
                Write-Host "Created: $venvPath" -ForegroundColor Green
                Write-Host "Activate: & `"$venvPath\Scripts\Activate.ps1`"" -ForegroundColor DarkGray
            }
            else {
                Write-Host "Error: Failed to create virtual environment." -ForegroundColor Red
            }
        }
        'list' {
            if (-not (Test-Path $venvsDir) -or (Get-ChildItem -Path $venvsDir -Directory -ErrorAction SilentlyContinue).Count -eq 0) {
                Write-Host "No virtual environments found." -ForegroundColor Yellow
                return
            }
            Write-Host "`nVirtual environments:" -ForegroundColor Cyan
            Get-ChildItem -Path $venvsDir -Directory | ForEach-Object {
                Write-Host "  $($_.Name)" -ForegroundColor White
            }
            Write-Host ""
        }
        'remove' {
            if ([string]::IsNullOrEmpty($Name)) {
                Write-Host "Error: Please specify a venv name to remove." -ForegroundColor Red
                return
            }
            $venvPath = Join-Path $venvsDir $Name
            if (-not (Test-Path $venvPath)) {
                Write-Host "Error: Virtual environment '$Name' not found." -ForegroundColor Red
                return
            }
            Remove-Item -Path $venvPath -Recurse -Force
            Write-Host "Removed virtual environment '$Name'." -ForegroundColor Green
        }
        'activate' {
            if ([string]::IsNullOrEmpty($Name)) {
                Write-Host "Error: Please specify a venv name." -ForegroundColor Red
                return
            }
            $venvPath = Join-Path $venvsDir $Name
            if (-not (Test-Path $venvPath)) {
                Write-Host "Error: Virtual environment '$Name' not found." -ForegroundColor Red
                return
            }
            Write-Host "Run this command in your PowerShell session:" -ForegroundColor Yellow
            Write-Host "  & `"$venvPath\Scripts\Activate.ps1`"" -ForegroundColor Cyan
        }
        default {
            Write-Host "Usage: pvm venv <create|list|remove|activate> [name]" -ForegroundColor Yellow
        }
    }
}

# --- Package Management ---

function Invoke-PvmPip {
    param([string]$SubCommand, [string[]]$ExtraArgs)

    $pythonExe = Get-CurrentPythonExe
    if (-not $pythonExe) {
        Write-Host "Error: No Python version active. Run: pvm use <version>" -ForegroundColor Red
        return
    }
    $versionDir = Split-Path $pythonExe
    $pipExe = Join-Path $versionDir "Scripts\pip.exe"
    if (-not (Test-Path $pipExe)) {
        Write-Host "Error: pip not found for current Python version." -ForegroundColor Red
        return
    }

    switch ($SubCommand) {
        'install' {
            if ($ExtraArgs.Count -eq 0) {
                Write-Host "Error: Please specify a package to install." -ForegroundColor Red
                Write-Host "Usage: pvm pip install <package>"
                return
            }
            & $pipExe install @ExtraArgs
        }
        'uninstall' {
            if ($ExtraArgs.Count -eq 0) {
                Write-Host "Error: Please specify a package to uninstall." -ForegroundColor Red
                return
            }
            & $pipExe uninstall -y @ExtraArgs
        }
        'list' {
            & $pipExe list
        }
        'upgrade' {
            if ($ExtraArgs.Count -eq 0) {
                Write-Host "Error: Please specify a package to upgrade." -ForegroundColor Red
                return
            }
            & $pipExe install --upgrade @ExtraArgs
        }
        default {
            Write-Host "Usage: pvm pip <install|uninstall|list|upgrade> [package]" -ForegroundColor Yellow
        }
    }
}

# --- Project Management ---

function Invoke-PvmProject {
    param([string]$SubCommand, [string[]]$ExtraArgs)

    switch ($SubCommand) {
        'init' {
            $pyprojectFile = Join-Path (Get-Location) "pyproject.toml"
            if (Test-Path $pyprojectFile) {
                Write-Host "pyproject.toml already exists in this directory." -ForegroundColor Yellow
                return
            }
            $projectName = Read-Host "Project name [myproject]"
            if ([string]::IsNullOrWhiteSpace($projectName)) { $projectName = "myproject" }
            $description = Read-Host "Description"
            $current = Get-CurrentVersion
            $pyversion = if ($current) { $current } else { "3.12" }
            $pyversion = Read-Host "Python version [$pyversion]"
            if ([string]::IsNullOrWhiteSpace($pyversion)) { $pyversion = if ($current) { $current } else { "3.12" } }

            $template = @"
[project]
name = "$projectName"
version = "0.1.0"
description = "$description"
requires-python = ">=$pyversion"
dependencies = []

[build-system]
requires = ["setuptools>=68.0", "wheel"]
build-backend = "setuptools.backends._legacy:_Backend"
"@
            Set-Content -Path $pyprojectFile -Value $template -Encoding UTF8
            Write-Host "Created pyproject.toml" -ForegroundColor Green

            # Create project venv
            $pythonExe = Get-CurrentPythonExe
            if ($pythonExe) {
                $venvPath = Join-Path (Get-Location) ".pvm-venv"
                if (-not (Test-Path $venvPath)) {
                    Write-Host "Creating project virtual environment..." -ForegroundColor Cyan
                    & $pythonExe -m venv $venvPath 2>&1 | Out-Null
                    Write-Host "Created .pvm-venv/" -ForegroundColor Green
                }
            }
        }
        'add' {
            if ($ExtraArgs.Count -eq 0) {
                Write-Host "Error: Please specify a package to add." -ForegroundColor Red
                return
            }
            $pyprojectFile = Join-Path (Get-Location) "pyproject.toml"
            if (-not (Test-Path $pyprojectFile)) {
                Write-Host "Error: No pyproject.toml found. Run 'pvm init' first." -ForegroundColor Red
                return
            }
            # Install the package
            Invoke-PvmPip -SubCommand "install" -ExtraArgs $ExtraArgs
            # Add to pyproject.toml dependencies
            $content = Get-Content $pyprojectFile -Raw
            $pkg = $ExtraArgs[0] -replace '[\[].*[\]]', ''  # strip version spec
            if ($content -match 'dependencies\s*=\s*\[\s*\]') {
                $content = $content -replace 'dependencies\s*=\s*\[\s*\]', "dependencies = [`n    `"$pkg`"`n]"
            }
            elseif ($content -match 'dependencies\s*=\s*\[') {
                $content = $content -replace '(dependencies\s*=\s*\[)', "`$1`n    `"$pkg`","
            }
            Set-Content -Path $pyprojectFile -Value $content -Encoding UTF8
            Write-Host "Added '$pkg' to pyproject.toml" -ForegroundColor Green
        }
        'remove' {
            if ($ExtraArgs.Count -eq 0) {
                Write-Host "Error: Please specify a package to remove." -ForegroundColor Red
                return
            }
            $pyprojectFile = Join-Path (Get-Location) "pyproject.toml"
            if (Test-Path $pyprojectFile) {
                $pkg = $ExtraArgs[0] -replace '[\[].*[\]]', ''
                $content = Get-Content $pyprojectFile -Raw
                $content = $content -replace "    `"$pkg`",?\r?\n?", ""
                $content = $content -replace "    `"$pkg`"", ""
                Set-Content -Path $pyprojectFile -Value $content -Encoding UTF8
                Write-Host "Removed '$pkg' from pyproject.toml" -ForegroundColor Green
            }
            Invoke-PvmPip -SubCommand "uninstall" -ExtraArgs $ExtraArgs
        }
        'run' {
            if ($ExtraArgs.Count -eq 0) {
                Write-Host "Error: Please specify a command to run." -ForegroundColor Red
                return
            }
            $venvPath = Join-Path (Get-Location) ".pvm-venv"
            $venvScripts = Join-Path $venvPath "Scripts"
            if (-not (Test-Path (Join-Path $venvScripts "python.exe"))) {
                Write-Host "Error: No .pvm-venv found. Run 'pvm init' first." -ForegroundColor Red
                return
            }
            # Run command in venv context by prepending venv paths to PATH
            $oldPath = $env:Path
            $env:Path = "$venvScripts;$venvPath;$env:Path"
            try {
                & $ExtraArgs[0] $ExtraArgs[1..($ExtraArgs.Count - 1)]
            }
            finally {
                $env:Path = $oldPath
            }
        }
        default {
            Write-Host "Usage: pvm <init|add|remove|run> [args]" -ForegroundColor Yellow
        }
    }
}

# Main execution
# Manual --home parsing (handles: pvm install 3.12 --home D:\pvm)
if (-not $PvmHomePath) {
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -eq '--home' -and ($i + 1) -lt $args.Count) {
            $PvmHomePath = $args[$i + 1]
            # Re-derive paths
            $script:PVM_HOME = $PvmHomePath
            $script:PVM_VERSIONS_DIR = Join-Path $script:PVM_HOME "versions"
            $script:PVM_CURRENT_FILE = Join-Path $script:PVM_HOME "current"
            $script:PVM_SETTINGS_FILE = Join-Path $script:PVM_HOME "settings.json"
            $script:PVM_SYMLINK = Join-Path $script:PVM_HOME "python"
            $script:PVM_SHIMS_DIR = Join-Path $script:PVM_HOME "shims"
            $script:PVM_VENVS_DIR = Join-Path $script:PVM_HOME "venvs"
            break
        }
    }
}
Initialize-Pvm

# Handle help flags
if ($Help -or $Command -eq '--help' -or $Command -eq '-h') {
    Show-Help
    exit 0
}

# Handle version flag
if ($Command -eq '--version' -or $Command -eq '-v') {
    Show-Version
    exit 0
}

# Handle commands
switch ($Command) {
    'list' {
        if ($Version -eq 'available') {
            Show-AvailableVersions
        }
        else {
            Show-InstalledVersions
        }
    }
    'install' {
        if ([string]::IsNullOrEmpty($Version)) {
            Write-Host "Error: Please specify a version to install." -ForegroundColor Red
            Write-Host "Usage: pvm install <version>"
            Write-Host "Example: pvm install 3.12.4"
            exit 1
        }
        $result = Install-PythonVersion -Version $Version -Architecture $Arch
        if (-not $result) { exit 1 }
    }
    'uninstall' {
        if ([string]::IsNullOrEmpty($Version)) {
            Write-Host "Error: Please specify a version to uninstall." -ForegroundColor Red
            Write-Host "Usage: pvm uninstall <version>"
            exit 1
        }
        $result = Uninstall-PythonVersion -Version $Version
        if (-not $result) { exit 1 }
    }
    'use' {
        if ([string]::IsNullOrEmpty($Version)) {
            Write-Host "Error: Please specify a version to use." -ForegroundColor Red
            Write-Host "Usage: pvm use <version>"
            exit 1
        }
        $result = Use-PythonVersion -Version $Version
        if (-not $result) { exit 1 }
    }
    'current' {
        Show-CurrentVersion
    }
    'which' {
        Show-WhichPython
    }
    'config' {
        Set-PvmConfig -MirrorName $Version
    }
    'arch' { Show-PlatformInfo }
    'platform' { Show-PlatformInfo }
    'venv' {
        # Collect remaining args as: pvm venv <subcommand> [name]
        $subCmd = $Version  # Position 1 maps to subcommand
        $remainingArgs = $args
        $subName = if ($remainingArgs.Count -gt 0) { $remainingArgs[0] } else { '' }
        Invoke-PvmVenv -SubCommand $subCmd -Name $subName
    }
    'pip' {
        $subCmd = $Version
        $remainingArgs = $args
        Invoke-PvmPip -SubCommand $subCmd -ExtraArgs $remainingArgs
    }
    'init' {
        Invoke-PvmProject -SubCommand "init"
    }
    'add' {
        $remainingArgs = $args
        if ([string]::IsNullOrEmpty($Version) -and $remainingArgs.Count -gt 0) {
            $Version = $remainingArgs[0]
            $remainingArgs = $remainingArgs[1..($remainingArgs.Count - 1)]
        }
        $pkgArgs = @($Version) + $remainingArgs | Where-Object { $_ }
        Invoke-PvmProject -SubCommand "add" -ExtraArgs $pkgArgs
    }
    'remove' {
        $remainingArgs = $args
        if ([string]::IsNullOrEmpty($Version) -and $remainingArgs.Count -gt 0) {
            $Version = $remainingArgs[0]
            $remainingArgs = $remainingArgs[1..($remainingArgs.Count - 1)]
        }
        $pkgArgs = @($Version) + $remainingArgs | Where-Object { $_ }
        Invoke-PvmProject -SubCommand "remove" -ExtraArgs $pkgArgs
    }
    'run' {
        $remainingArgs = @($Version) + $args | Where-Object { $_ }
        Invoke-PvmProject -SubCommand "run" -ExtraArgs $remainingArgs
    }
    default {
        if ([string]::IsNullOrEmpty($Command)) {
            Show-Help
        }
        else {
            Write-Host "Error: Unknown command '$Command'" -ForegroundColor Red
            Write-Host "Use 'pvm --help' for usage information."
            exit 1
        }
    }
}

