#!/usr/bin/env bash

# pvm - Python Version Manager for Unix (Linux/macOS)
# A simple Python version manager inspired by nvm
#
# Author: pvm contributors
# License: Apache 2.0

set -e

# Version
PVM_VERSION="1.0.0"
PVM_USER_AGENT="pvm/$PVM_VERSION"

# Determine PVM_HOME
PVMHOME_CONFIG="$HOME/.pvmhome"

if [[ -n "$PVM_HOME_OVERRIDE" ]]; then
    # --home parameter overrides everything
    PVM_HOME="$PVM_HOME_OVERRIDE"
elif [[ -n "$PVM_HOME" ]]; then
    # Environment variable takes priority (already set)
    :
elif [[ -f "$PVMHOME_CONFIG" ]]; then
    # Read from saved config
    saved=$(cat "$PVMHOME_CONFIG" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "$saved" && -d "$saved" ]]; then
        PVM_HOME="$saved"
    fi
fi

# If still not determined or empty, check default or prompt
if [[ -z "$PVM_HOME" ]]; then
    default_home="$HOME/.pvm"
    if [[ -d "$default_home" ]]; then
        # Default directory already exists, use it silently
        PVM_HOME="$default_home"
    else
        # First-time use: prompt interactively
        echo ""
        echo -e "  ${CYAN}Welcome to pvm! First-time setup:${NC}"
        echo "  Where should pvm store its data (Python versions, config, etc.)?"
        echo ""
        printf "  Data directory [%s]: " "$default_home"
        read -r input_path
        if [[ -z "$input_path" ]]; then
            PVM_HOME="$default_home"
        else
            PVM_HOME="$input_path"
        fi
        # Save choice for future use
        echo "$PVM_HOME" > "$PVMHOME_CONFIG"
        echo -e "  ${GRAY}Saved to $PVMHOME_CONFIG${NC}"
        echo ""
    fi
fi

# Directories
PVM_VERSIONS_DIR="$PVM_HOME/versions"
PVM_CURRENT_FILE="$PVM_HOME/current"
PVM_DEFAULT_FILE="$PVM_HOME/default"
PVM_SETTINGS_FILE="$PVM_HOME/settings.json"
PVM_SYMLINK="$PVM_HOME/python"
PVM_SHIMS_DIR="$PVM_HOME/shims"
PVM_VENVS_DIR="$PVM_HOME/venvs"

# Default mirror
DEFAULT_MIRROR="https://www.python.org/ftp/python"

# Preset mirrors for Python download
declare -A MIRRORS=(
    ["default"]="https://www.python.org/ftp/python"
    ["tsinghua"]="https://mirrors.tuna.tsinghua.edu.cn/python"
    ["qinghua"]="https://mirrors.tuna.tsinghua.edu.cn/python"
    ["huawei"]="https://mirrors.huaweicloud.com/python"
    ["aliyun"]="https://mirrors.aliyun.com/python"
)

# Preset mirrors for pip
declare -A PIP_MIRRORS=(
    ["default"]="https://pypi.org/simple"
    ["tsinghua"]="https://pypi.tuna.tsinghua.edu.cn/simple"
    ["qinghua"]="https://pypi.tuna.tsinghua.edu.cn/simple"
    ["huawei"]="https://repo.huaweicloud.com/repository/pypi/simple"
    ["aliyun"]="https://mirrors.aliyun.com/pypi/simple"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Fallback Python versions (used when network is unavailable)
FALLBACK_VERSIONS=(
    "3.14.6" "3.14.5" "3.14.4" "3.14.3" "3.14.2" "3.14.1" "3.14.0"
    "3.13.14" "3.13.13" "3.13.12" "3.13.11" "3.13.10" "3.13.9" "3.13.8" "3.13.7" "3.13.6" "3.13.5" "3.13.4" "3.13.3" "3.13.2" "3.13.1" "3.13.0"
    "3.12.9" "3.12.8" "3.12.7" "3.12.6" "3.12.5" "3.12.4" "3.12.3" "3.12.2" "3.12.1" "3.12.0"
    "3.11.12" "3.11.11" "3.11.10" "3.11.9" "3.11.8" "3.11.7" "3.11.6" "3.11.5" "3.11.4" "3.11.3" "3.11.2" "3.11.1" "3.11.0"
    "3.10.17" "3.10.16" "3.10.15" "3.10.14" "3.10.13" "3.10.12" "3.10.11" "3.10.10" "3.10.9" "3.10.8" "3.10.7" "3.10.6" "3.10.5" "3.10.4" "3.10.3" "3.10.2" "3.10.1" "3.10.0"
    "3.9.22" "3.9.21" "3.9.20" "3.9.19" "3.9.18" "3.9.17" "3.9.16" "3.9.15" "3.9.14" "3.9.13" "3.9.12" "3.9.11" "3.9.10" "3.9.9" "3.9.8" "3.9.7" "3.9.6" "3.9.5" "3.9.4" "3.9.3" "3.9.2" "3.9.1" "3.9.0"
    "3.8.21" "3.8.20" "3.8.19" "3.8.18" "3.8.17" "3.8.16" "3.8.15" "3.8.14" "3.8.13" "3.8.12" "3.8.11" "3.8.10" "3.8.9" "3.8.8" "3.8.7" "3.8.6" "3.8.5" "3.8.4" "3.8.3" "3.8.2" "3.8.1" "3.8.0"
)
AVAILABLE_VERSIONS=()

# Fetch available versions from CDN/API with caching
pvm_fetch_versions() {
    local cache_file="$PVM_HOME/versions_cache.json"

    # Return cached if already loaded
    if [[ ${#AVAILABLE_VERSIONS[@]} -gt 0 ]]; then
        return
    fi

    # 1. Try local cache (< 24h)
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
        if [[ $cache_age -lt 86400 ]]; then
            while IFS= read -r ver; do
                AVAILABLE_VERSIONS+=("$ver")
            done < <(grep -oP '"versions"\s*:\s*\[[\s\S]*?\]' "$cache_file" 2>/dev/null | grep -oP '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"')
            if [[ ${#AVAILABLE_VERSIONS[@]} -gt 0 ]]; then
                return
            fi
        fi
    fi

    # 2. Try jsDelivr CDN (global, fast)
    echo -e "  ${GRAY}Fetching versions from CDN...${NC}" >&2
    local cdn_urls=(
        "https://cdn.jsdelivr.net/gh/violet27chen/pym@main/versions.json"
        "https://raw.githubusercontent.com/violet27chen/pym/main/versions.json"
    )
    for url in "${cdn_urls[@]}"; do
        local response
        if response=$(curl -sf -A "$PVM_USER_AGENT" --connect-timeout 10 --max-time 15 "$url" 2>/dev/null); then
            while IFS= read -r ver; do
                AVAILABLE_VERSIONS+=("$ver")
            done < <(echo "$response" | grep -oP '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"')
            if [[ ${#AVAILABLE_VERSIONS[@]} -gt 0 ]]; then
                echo "$response" > "$cache_file" 2>/dev/null || true
                return
            fi
        fi
    done

    # 3. Try python.org API
    echo -e "  ${GRAY}Trying python.org API...${NC}" >&2
    local api_response
    if api_response=$(curl -sf -A "$PVM_USER_AGENT" --connect-timeout 10 --max-time 15 \
        "https://www.python.org/api/v2/downloads/release/?is_published=true&pre_release=false" 2>/dev/null); then
        while IFS= read -r ver; do
            AVAILABLE_VERSIONS+=("$ver")
        done < <(echo "$api_response" | grep -oP '"name"\s*:\s*"Python \K[0-9]+\.[0-9]+\.[0-9]+' | head -200)
        if [[ ${#AVAILABLE_VERSIONS[@]} -gt 0 ]]; then
            printf '{"versions":[%s]}\n' "$(printf '"%s",' "${AVAILABLE_VERSIONS[@]}" | sed 's/,$//')" > "$cache_file" 2>/dev/null || true
            return
        fi
    fi

    # 4. Fallback to built-in list
    echo -e "  ${YELLOW}Using built-in version list.${NC}" >&2
    AVAILABLE_VERSIONS=("${FALLBACK_VERSIONS[@]}")
}

# Initialize pvm directories
pvm_init() {
    mkdir -p "$PVM_HOME"
    mkdir -p "$PVM_VERSIONS_DIR"
    mkdir -p "$PVM_VENVS_DIR"

    if [[ ! -f "$PVM_SETTINGS_FILE" ]]; then
        echo '{"mirror": "'"$DEFAULT_MIRROR"'", "mirror_selected": false}' > "$PVM_SETTINGS_FILE"
    fi
}

# Get mirror from settings
pvm_get_mirror() {
    if [[ -f "$PVM_SETTINGS_FILE" ]]; then
        local mirror
        mirror=$(grep -o '"mirror"[[:space:]]*:[[:space:]]*"[^"]*"' "$PVM_SETTINGS_FILE" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/')
        if [[ -n "$mirror" ]]; then
            echo "$mirror"
            return
        fi
    fi
    echo "$DEFAULT_MIRROR"
}

# Prompt user to select a download mirror (only on first install)
pvm_prompt_mirror() {
    # Check if mirror was already selected
    if [[ -f "$PVM_SETTINGS_FILE" ]]; then
        local selected
        selected=$(grep -o '"mirror_selected"[[:space:]]*:[[:space:]]*\(true\|false\)' "$PVM_SETTINGS_FILE" 2>/dev/null | grep -o 'true\|false')
        if [[ "$selected" == "true" ]]; then
            return
        fi
    fi

    echo ""
    echo -e "  ${CYAN}Choose a download mirror for Python installations:${NC}"
    echo ""
    echo -e "    1) python.org (Official)              [default]"
    echo -e "    2) Tsinghua University (China)        [recommended for China]"
    echo -e "    3) Huawei Cloud (China)"
    echo -e "    4) Aliyun (China)"
    echo ""
    printf "  Select mirror [1-4, default=1]: "
    read -r choice

    local mirror_url
    case "${choice:-1}" in
        1) mirror_url="$DEFAULT_MIRROR" ;;
        2) mirror_url="https://mirrors.tuna.tsinghua.edu.cn/python" ;;
        3) mirror_url="https://mirrors.huaweicloud.com/python" ;;
        4) mirror_url="https://mirrors.aliyun.com/python" ;;
        *) mirror_url="$DEFAULT_MIRROR" ;;
    esac

    echo -e "  ${GREEN}Using mirror: $mirror_url${NC}"

    # Save to settings
    echo "{\"mirror\": \"$mirror_url\", \"mirror_selected\": true}" > "$PVM_SETTINGS_FILE"
    echo ""
}

# Show help
pvm_help() {
    cat << EOF

pvm - Python Version Manager v${PVM_VERSION}

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
    pin [version]           Pin Python version for current directory (.python-version)
    unpin                   Remove pinned version from current directory

    alias default <ver>     Set default version (auto-used on new terminal)
    unalias default         Remove default version
    alias                   Show all aliases

    venv <name>             Create a virtual environment (auto-activates)
    venv <name> --python <ver>  Create venv with specific Python version
    venv list               List all virtual environments
    venv remove <name>      Remove a virtual environment
    venv activate <name>    Show activation command

    pip install <pkg>       Install a package
    pip uninstall <pkg>     Uninstall a package
    pip list                List installed packages
    pip upgrade <pkg>       Upgrade a package
    pip freeze              List installed packages (requirements format)
    pip check               Check for dependency conflicts

    export [file]           Export requirements to file (default: requirements.txt)
    import [file]           Install packages from file (default: requirements.txt)
    lock [file]             Lock dependencies (default: requirements.lock)
    sync [file]             Sync environment from lock file
    tree                    Show dependency tree
    cache clean             Clean pip and pvm caches

    tool install <pkg>      Install a tool (like pipx)
    tool run <tool> [args]  Run an installed tool
    tool list               List installed tools
    tool uninstall <tool>   Uninstall a tool

    init                    Initialize a new project (pyproject.toml)
    add <pkg>               Add a dependency
    remove <pkg>            Remove a dependency
    run <cmd>               Run a command in project venv
    build                   Build package (sdist + wheel)
    publish                 Publish package to PyPI

    --help, -h              Show this help message
    --version, -v           Show pvm version

Options:
    --home <path>           Set pvm data directory for this command only (auto-creates if needed)
    --source                Force build from source (skip prebuilt binary)

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
    pvm stores data in: $PVM_HOME

Uninstall pvm:
    Run: bash "$PVM_HOME/uninstall.sh"

EOF
}

# Show version
pvm_version() {
    echo "pvm version $PVM_VERSION"
}

# Get installed versions
pvm_get_installed() {
    if [[ -d "$PVM_VERSIONS_DIR" ]]; then
        find "$PVM_VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V -r
    fi
}

# Get current version (current > .python-version > default > none)
pvm_get_current() {
    if [[ -f "$PVM_CURRENT_FILE" ]]; then
        cat "$PVM_CURRENT_FILE" | tr -d '[:space:]'
    elif [[ -f ".python-version" ]]; then
        local local_ver
        local_ver=$(cat ".python-version" | tr -d '[:space:]')
        if [[ -n "$local_ver" ]]; then
            echo "$local_ver"
            return
        fi
    elif [[ -f "$PVM_DEFAULT_FILE" ]]; then
        cat "$PVM_DEFAULT_FILE" | tr -d '[:space:]'
    fi
}

# Get explicitly set current version (without default fallback)
pvm_get_explicit_current() {
    if [[ -f "$PVM_CURRENT_FILE" ]]; then
        cat "$PVM_CURRENT_FILE" | tr -d '[:space:]'
    fi
}

# Get default version
pvm_get_default() {
    if [[ -f "$PVM_DEFAULT_FILE" ]]; then
        cat "$PVM_DEFAULT_FILE" | tr -d '[:space:]'
    fi
}

# Set default version
pvm_set_default() {
    echo -n "$1" > "$PVM_DEFAULT_FILE"
}

# Remove default version
pvm_remove_default() {
    rm -f "$PVM_DEFAULT_FILE"
}

# Show aliases
pvm_alias() {
    local default
    default=$(pvm_get_default)
    local current
    current=$(pvm_get_explicit_current)

    echo ""
    if [[ -n "$default" ]]; then
        local installed
        installed=$(pvm_get_installed)
        local exists
        exists=$(echo "$installed" | grep -c "^${default}$" 2>/dev/null || echo 0)
        local status="installed"
        [[ "$exists" -eq 0 ]] && status="NOT installed"
        echo -e "  ${GREEN}default -> $default ($status)${NC}"
    else
        echo -e "  ${YELLOW}No default version set.${NC}"
        echo -e "  ${GRAY}Use 'pvm alias default <version>' to set one.${NC}"
    fi
    if [[ -n "$current" ]]; then
        echo -e "  ${CYAN}current -> $current${NC}"
    fi
    echo ""
}

# List installed versions
pvm_list() {
    local installed current
    installed=$(pvm_get_installed)
    current=$(pvm_get_current)
    local count
    count=$(echo "$installed" | grep -c '.' 2>/dev/null || echo 0)

    if [[ -z "$installed" ]]; then
        echo ""
        echo -e "  ${YELLOW}No Python versions installed.${NC}"
        echo ""
        echo "  Install one:"
        echo -e "    ${CYAN}pvm install 3.13         # latest 3.13.x${NC}"
        echo -e "    ${CYAN}pvm install 3.12.4       # specific version${NC}"
        echo -e "    ${CYAN}pvm list available       # see all options${NC}"
        echo ""
        return
    fi

    echo ""
    echo -e "  ${CYAN}Installed Python versions ($count):${NC}"
    echo ""

    while IFS= read -r v; do
        if [[ "$v" == "$current" ]]; then
            echo -e "    ${GREEN}* $v${NC} ${GRAY}(current)${NC}"
        else
            echo -e "    ${WHITE}$v${NC}"
        fi
    done <<< "$installed"
    echo ""
    echo -e "  ${GRAY}Use 'pvm list available' to see downloadable versions.${NC}"
    echo ""
}

# List available versions
pvm_list_available() {
    pvm_fetch_versions
    local installed current
    installed=$(pvm_get_installed)
    current=$(pvm_get_current)
    local installed_count
    installed_count=$(echo "$installed" | grep -c '.' 2>/dev/null || echo 0)
    local available_count=${#AVAILABLE_VERSIONS[@]}

    echo ""
    echo -e "  ${CYAN}Available Python versions ($available_count total, $installed_count installed):${NC}"
    echo ""

    local prev_minor=""
    local line=""
    local installed_in_group=0

    for v in "${AVAILABLE_VERSIONS[@]}"; do
        local minor
        minor=$(echo "$v" | cut -d. -f1-2)

        if [[ "$minor" != "$prev_minor" ]]; then
            if [[ -n "$line" ]]; then
                local group_info=""
                if [[ $installed_in_group -gt 0 ]]; then
                    group_info=" ${GRAY}($installed_in_group installed)${NC}"
                fi
                echo -e "  ${YELLOW}${prev_minor}.x${group_info}"
                echo "$line"
            fi
            line="    "
            prev_minor="$minor"
            installed_in_group=0
        fi

        if echo "$installed" | grep -q "^${v}$"; then
            if [[ "$v" == "$current" ]]; then
                line+="*${v}* "
            else
                line+="[${v}] "
            fi
            installed_in_group=$((installed_in_group + 1))
        else
            line+="$v "
        fi
    done

    # Print last group
    if [[ -n "$line" ]]; then
        local group_info=""
        if [[ $installed_in_group -gt 0 ]]; then
            group_info=" ${GRAY}($installed_in_group installed)${NC}"
        fi
        echo -e "  ${YELLOW}${prev_minor}.x${group_info}"
        echo "$line"
    fi

    echo ""
    echo -e "  ${GRAY}*version* = current    [version] = installed    plain = not installed${NC}"
    echo ""
}

# Detect OS and architecture
pvm_detect_platform() {
    local os arch
    
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    
    case "$os" in
        linux*)
            os="linux"
            ;;
        darwin*)
            os="macos"
            ;;
        *)
            echo "Unsupported OS: $os" >&2
            return 1
            ;;
    esac
    
    case "$arch" in
        x86_64|amd64)
            arch="x86_64"
            ;;
        aarch64|arm64)
            arch="aarch64"
            ;;
        armv7l|armhf)
            arch="armv7"
            ;;
        i686|i386)
            arch="i686"
            ;;
        *)
            echo "Unsupported architecture: $arch" >&2
            return 1
            ;;
    esac
    
    echo "${os}-${arch}"
}

# Show detected platform info
pvm_show_platform() {
    local platform
    platform=$(pvm_detect_platform) || return 1
    
    local os arch
    os=$(echo "$platform" | cut -d'-' -f1)
    arch=$(echo "$platform" | cut -d'-' -f2)
    
    echo -e "${CYAN}Detected Platform:${NC}"
    echo "  OS: $os"
    echo "  Architecture: $arch"
}

# Check build dependencies
pvm_check_dependencies() {
    local missing=()
    
    for cmd in gcc make curl tar; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: Missing build dependencies: ${missing[*]}${NC}"
        echo "You may need to install them to build Python from source."
        echo ""
        echo "On Ubuntu/Debian:"
        echo "  sudo apt-get install build-essential libssl-dev zlib1g-dev \\"
        echo "    libbz2-dev libreadline-dev libsqlite3-dev libncurses5-dev \\"
        echo "    libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev"
        echo ""
        echo "On macOS:"
        echo "  xcode-select --install"
        echo "  brew install openssl readline sqlite3 xz zlib"
        echo ""
        return 1
    fi
    return 0
}

# Resolve partial version to latest available version
# e.g. "3.13" -> "3.13.14", "3" -> "3.14.6"
pvm_resolve_available() {
    pvm_fetch_versions
    local ver="$1"
    # Already full version
    if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ver"
        return
    fi
    # Match from AVAILABLE_VERSIONS (already sorted descending)
    for v in "${AVAILABLE_VERSIONS[@]}"; do
        if [[ "$v" == "$ver"* || "$v" == "$ver."* ]]; then
            echo -e "${GRAY}Resolved version: $ver -> $v${NC}" >&2
            echo "$v"
            return
        fi
    done
}

# Resolve partial version to latest installed version
pvm_resolve_installed() {
    local ver="$1"
    if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ver"
        return
    fi
    local installed
    installed=$(pvm_get_installed)
    if [[ -n "$installed" ]]; then
        while IFS= read -r v; do
            if [[ "$v" == "$ver"* || "$v" == "$ver."* ]]; then
                echo -e "${GRAY}Resolved version: $ver -> $v${NC}" >&2
                echo "$v"
                return
            fi
        done <<< "$installed"
    fi
}

# Install Python version
pvm_install() {
    local version="$1"
    local use_source=false

    if [[ -z "$version" ]]; then
        echo -e "${RED}Error: Please specify a version to install.${NC}"
        echo "Usage: pvm install <version>"
        echo "Example: pvm install 3.12.4  (or: pvm install 3.12)"
        return 1
    fi

    # Check for --source flag
    for arg in "$@"; do
        if [[ "$arg" == "--source" ]]; then
            use_source=true
        fi
    done

    # Resolve partial version to full version
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            local resolved
            resolved=$(pvm_resolve_available "$version")
            if [[ -n "$resolved" ]]; then
                version="$resolved"
            else
                echo -e "${RED}Error: No matching version found for '$version'${NC}"
                echo "Use 'pvm list available' to see available versions."
                return 1
            fi
        else
            echo -e "${RED}Error: Invalid version format. Use format like '3.13', '3.13.2', or '3'${NC}"
            return 1
        fi
    fi

    local version_dir="$PVM_VERSIONS_DIR/$version"

    # Check if already installed
    if [[ -d "$version_dir" ]]; then
        echo -e "${YELLOW}Python $version is already installed.${NC}"
        echo "Use 'pvm use $version' to switch to it."
        return 0
    fi

    local platform
    platform=$(pvm_detect_platform) || return 1

    echo ""
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  Installing Python $version${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""

    # Interactive mirror selection on first install
    pvm_prompt_mirror
    local current_mirror
    current_mirror=$(pvm_get_mirror)

    echo -e "  Platform:   $platform"
    echo -e "  Install to: $version_dir"
    echo ""

    # --- Try precompiled binary from python-build-standalone ---
    if [[ "$use_source" != true ]]; then
        echo -e "${YELLOW}[1/3] Downloading prebuilt Python $version...${NC}"

        # Get latest release tag
        local pbs_tag
        pbs_tag=$(curl -sf -A "$PVM_USER_AGENT" --connect-timeout 10 --max-time 15 \
            "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest" 2>/dev/null \
            | grep -oP '"tag_name"\s*:\s*"\K[0-9]+' | head -1)

        if [[ -n "$pbs_tag" ]]; then
            # Map platform
            local pbs_platform
            case "$platform" in
                linux-x86_64)    pbs_platform="x86_64-unknown-linux-gnu" ;;
                linux-aarch64)   pbs_platform="aarch64-unknown-linux-gnu" ;;
                macos-x86_64)    pbs_platform="x86_64-apple-darwin" ;;
                macos-aarch64)   pbs_platform="aarch64-apple-darwin" ;;
                *)               pbs_platform="" ;;
            esac

            if [[ -n "$pbs_platform" ]]; then
                local tar_name="cpython-${version}+${pbs_tag}-${pbs_platform}-install_only.tar.gz"
                local download_url="https://github.com/astral-sh/python-build-standalone/releases/download/${pbs_tag}/${tar_name}"
                local temp_dir
                temp_dir=$(mktemp -d)
                local tar_file="$temp_dir/$tar_name"

                echo -e "${GRAY}      URL: $download_url${NC}"

                if curl -fSL -A "$PVM_USER_AGENT" --connect-timeout 10 --max-time 300 "$download_url" -o "$tar_file" --progress-bar 2>/dev/null; then
                    echo -e "${GREEN}      Download complete!${NC}"

                    echo -e "${YELLOW}[2/3] Extracting...${NC}"
                    mkdir -p "$version_dir"
                    if tar -xzf "$tar_file" -C "$version_dir" --strip-components=1 2>/dev/null; then
                        echo -e "${GREEN}      Extraction complete!${NC}"

                        # Ensure pip is available
                        echo -e "${YELLOW}[3/3] Verifying pip...${NC}"
                        local pip_exe="$version_dir/bin/pip3"
                        if [[ ! -x "$pip_exe" ]]; then
                            # Try to bootstrap pip
                            local get_pip_url="https://bootstrap.pypa.io/get-pip.py"
                            local get_pip_path="$temp_dir/get-pip.py"
                            if curl -sfSL -A "$PVM_USER_AGENT" "$get_pip_url" -o "$get_pip_path" 2>/dev/null; then
                                "$version_dir/bin/python3" "$get_pip_path" --no-warn-script-location 2>/dev/null || true
                            fi
                        fi
                        rm -rf "$temp_dir"

                        echo ""
                        echo -e "${GREEN}=============================================${NC}"
                        echo -e "${GREEN}  Python $version installed successfully!${NC}"
                        echo -e "${GREEN}=============================================${NC}"
                        echo ""
                        echo "  Location: $version_dir"
                        echo ""
                        echo -e "${YELLOW}  Next steps:${NC}"
                        echo -e "${CYAN}    pvm use $version        # Switch to this version${NC}"
                        echo -e "${CYAN}    python3 --version       # Verify installation${NC}"
                        echo ""
                        return 0
                    fi
                fi
                echo -e "${YELLOW}      Prebuilt binary not available, falling back to source build...${NC}"
                rm -rf "$temp_dir"
            fi
        fi
        echo -e "${YELLOW}      Could not download prebuilt binary, falling back to source build...${NC}"
    fi

    # --- Fallback: build from source ---
    echo -e "${YELLOW}[1/5] Downloading Python $version source...${NC}"

    # Build list of mirrors to try (configured first, then fallbacks)
    local -a source_mirrors=(
        "$current_mirror"
        "https://www.python.org/ftp/python"
        "https://mirrors.tuna.tsinghua.edu.cn/python"
        "https://mirrors.huaweicloud.com/python"
        "https://mirrors.aliyun.com/python"
    )
    # Deduplicate
    local -a unique_mirrors=()
    local -A seen_mirrors=()
    for m in "${source_mirrors[@]}"; do
        if [[ -z "${seen_mirrors[$m]+x}" ]]; then
            seen_mirrors["$m"]=1
            unique_mirrors+=("$m")
        fi
    done

    local temp_dir
    temp_dir=$(mktemp -d)
    local source_file="$temp_dir/Python-$version.tgz"
    local downloaded=false

    for m in "${unique_mirrors[@]}"; do
        local source_url="$m/$version/Python-$version.tgz"
        local mirror_name
        mirror_name=$(echo "$m" | sed -E 's|https?://([^/]+).*|\1|')
        echo -e "${GRAY}      Trying $mirror_name... ($source_url)${NC}"

        if curl -fSL -A "$PVM_USER_AGENT" --connect-timeout 10 --max-time 300 "$source_url" -o "$source_file" --progress-bar 2>/dev/null; then
            echo -e "${GREEN}      Download complete!${NC}"
            downloaded=true
            break
        else
            echo -e "${GRAY}      $mirror_name failed${NC}"
        fi
    done

    if [[ "$downloaded" != true ]]; then
        echo -e "${RED}Error: Failed to download Python $version from all mirrors${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    echo -e "${YELLOW}[2/5] Extracting source files...${NC}"
    tar -xzf "$source_file" -C "$temp_dir"
    local source_dir="$temp_dir/Python-$version"

    if [[ ! -d "$source_dir" ]]; then
        echo -e "${RED}Error: Failed to extract Python source${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    pvm_check_dependencies || { echo -e "${YELLOW}Continuing anyway...${NC}"; }
    echo -e "${GREEN}      Extraction complete!${NC}"

    echo -e "${YELLOW}[3/5] Configuring build options...${NC}"
    cd "$source_dir"
    local configure_opts="--prefix=$version_dir --enable-optimizations --with-ensurepip=install"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        for d in /opt/homebrew/opt/openssl@3 /usr/local/opt/openssl@3 /opt/homebrew/opt/openssl@1.1 /usr/local/opt/openssl@1.1; do
            if [[ -d "$d" ]]; then configure_opts="$configure_opts --with-openssl=$d"; break; fi
        done
    fi
    if ! ./configure $configure_opts > "$temp_dir/configure.log" 2>&1; then
        echo -e "${RED}Error: Configuration failed. Check $temp_dir/configure.log${NC}"
        cd - > /dev/null 2>&1; rm -rf "$temp_dir"; return 1
    fi
    echo -e "${GREEN}      Configuration complete!${NC}"

    echo -e "${YELLOW}[4/5] Building (this may take 5-15 minutes)...${NC}"
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    echo -e "${GRAY}      Using $cpu_count CPU cores${NC}"
    if ! make -j"$cpu_count" > "$temp_dir/make.log" 2>&1; then
        echo -e "${RED}Error: Build failed. Check $temp_dir/make.log${NC}"
        cd - > /dev/null 2>&1; rm -rf "$temp_dir"; return 1
    fi
    echo -e "${GREEN}      Build complete!${NC}"

    echo -e "${YELLOW}[5/5] Installing to $version_dir...${NC}"
    if ! make install > "$temp_dir/install.log" 2>&1; then
        echo -e "${RED}Error: Installation failed. Check $temp_dir/install.log${NC}"
        cd - > /dev/null 2>&1; rm -rf "$temp_dir"; return 1
    fi

    cd - > /dev/null
    rm -rf "$temp_dir"

    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Python $version installed successfully!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "  Location: $version_dir"
    echo ""
    echo -e "${YELLOW}  Next steps:${NC}"
    echo -e "${CYAN}    pvm use $version        # Switch to this version${NC}"
    echo -e "${CYAN}    python3 --version       # Verify installation${NC}"
    echo ""
}

# Uninstall Python version
pvm_uninstall() {
    local version="$1"
    
    if [[ -z "$version" ]]; then
        echo -e "${RED}Error: Please specify a version to uninstall.${NC}"
        echo "Usage: pvm uninstall <version>"
        return 1
    fi
    
    # Resolve partial version to installed version
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local resolved
        resolved=$(pvm_resolve_installed "$version")
        if [[ -n "$resolved" ]]; then
            version="$resolved"
        fi
    fi
    
    local version_dir="$PVM_VERSIONS_DIR/$version"
    
    if [[ ! -d "$version_dir" ]]; then
        echo -e "${RED}Error: Python $version is not installed.${NC}"
        return 1
    fi
    
    local current
    current=$(pvm_get_current)
    
    if [[ "$version" == "$current" ]]; then
        echo -e "${YELLOW}Warning: Uninstalling the currently active version.${NC}"
        rm -f "$PVM_CURRENT_FILE"
        rm -f "$PVM_SYMLINK"
    fi
    
    echo ""
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  Uninstalling Python $version${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""
    echo "  Location: $version_dir"
    echo ""
    echo -e "${YELLOW}  Removing files...${NC}"
    
    rm -rf "$version_dir"
    
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Python $version uninstalled successfully!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    
    # Show remaining versions
    local remaining
    remaining=$(pvm_get_installed)
    if [[ -n "$remaining" ]]; then
        echo "  Remaining installed versions:"
        echo "$remaining" | while read -r v; do
            echo -e "${CYAN}    - $v${NC}"
        done
        echo ""
    else
        echo -e "${YELLOW}  No Python versions remaining.${NC}"
        echo "  Use 'pvm install <version>' to install a new version."
        echo ""
    fi
}

# Create/update nvm-style shims for instant version switching
pvm_update_shims() {
    mkdir -p "$PVM_SHIMS_DIR"

    # python3 shim
    cat > "$PVM_SHIMS_DIR/python3" << 'SHIM'
#!/usr/bin/env bash
PVM_HOME="${PVM_HOME:-$HOME/.pvm}"
PVM_CURRENT=$(cat "$PVM_HOME/current" 2>/dev/null | tr -d '[:space:]')
if [[ -z "$PVM_CURRENT" ]]; then
    echo "Error: No Python version active. Run: pvm use <version>" >&2
    exit 1
fi
exec "$PVM_HOME/versions/$PVM_CURRENT/bin/python3" "$@"
SHIM
    chmod +x "$PVM_SHIMS_DIR/python3"

    # python shim (same as python3)
    cp "$PVM_SHIMS_DIR/python3" "$PVM_SHIMS_DIR/python"
    chmod +x "$PVM_SHIMS_DIR/python"

    # pip3 shim
    cat > "$PVM_SHIMS_DIR/pip3" << 'SHIM'
#!/usr/bin/env bash
PVM_HOME="${PVM_HOME:-$HOME/.pvm}"
PVM_CURRENT=$(cat "$PVM_HOME/current" 2>/dev/null | tr -d '[:space:]')
if [[ -z "$PVM_CURRENT" ]]; then
    echo "Error: No Python version active. Run: pvm use <version>" >&2
    exit 1
fi
exec "$PVM_HOME/versions/$PVM_CURRENT/bin/pip3" "$@"
SHIM
    chmod +x "$PVM_SHIMS_DIR/pip3"

    # pip shim (same as pip3)
    cp "$PVM_SHIMS_DIR/pip3" "$PVM_SHIMS_DIR/pip"
    chmod +x "$PVM_SHIMS_DIR/pip"
}

# Use Python version
pvm_use() {
    local version="$1"
    
    if [[ -z "$version" ]]; then
        echo -e "${RED}Error: Please specify a version to use.${NC}"
        echo "Usage: pvm use <version>"
        return 1
    fi
    
    # Resolve partial version to installed version
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local resolved
        resolved=$(pvm_resolve_installed "$version")
        if [[ -n "$resolved" ]]; then
            version="$resolved"
        fi
    fi
    
    local version_dir="$PVM_VERSIONS_DIR/$version"
    
    if [[ ! -d "$version_dir" ]]; then
        echo -e "${RED}Error: Python $version is not installed.${NC}"
        echo "Use 'pvm install $version' to install it first."
        return 1
    fi
    
    # Update current version
    echo -n "$version" > "$PVM_CURRENT_FILE"
    
    # Update symlink
    rm -f "$PVM_SYMLINK"
    ln -sf "$version_dir" "$PVM_SYMLINK"
    
    # Create/update nvm-style shims for instant version switching
    pvm_update_shims
    
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Switched to Python $version${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    
    # Show Python version
    local python_exe="$PVM_SYMLINK/bin/python3"
    if [[ -x "$python_exe" ]]; then
        local python_version
        python_version=$($python_exe --version 2>&1)
        echo "  Python:  $python_version"
        
        # Try to get pip version
        local pip_exe="$PVM_SYMLINK/bin/pip3"
        if [[ -x "$pip_exe" ]]; then
            local pip_version
            pip_version=$($pip_exe --version 2>&1 | sed 's/ from.*//')
            echo "  pip:     $pip_version"
        fi
        
        echo ""
        echo -e "${GRAY}  Path:    $python_exe${NC}"
    fi
    
    # Check if pvm python is in PATH
    if [[ ":$PATH:" != *":$PVM_SYMLINK/bin:"* ]] && [[ ":$PATH:" != *":$PVM_SHIMS_DIR:"* ]]; then
        echo ""
        echo -e "${YELLOW}  Warning: pvm Python path not in PATH${NC}"
        echo -e "${YELLOW}  Add this to your shell profile:${NC}"
        echo -e "${CYAN}    export PATH=\"$PVM_SYMLINK/bin:$PVM_SHIMS_DIR:\$PATH\"${NC}"
    fi
    echo ""
}

# Show current version
pvm_current() {
    local explicit_current
    explicit_current=$(pvm_get_explicit_current)
    local default
    default=$(pvm_get_default)
    local current
    current=$(pvm_get_current)

    echo ""
    if [[ -n "$explicit_current" ]]; then
        echo -e "${GREEN}  Current version: $explicit_current${NC}"
        if [[ -n "$default" ]]; then
            echo -e "${GRAY}  Default version: $default${NC}"
        fi
    elif [[ -n "$default" ]]; then
        echo -e "${GREEN}  Current version: $default (default)${NC}"
    else
        echo -e "${YELLOW}  No Python version is active.${NC}"
        echo ""
        echo "  To get started:"
        echo -e "${CYAN}    pvm list available    # See available versions${NC}"
        echo -e "${CYAN}    pvm install 3.12.4    # Install a version${NC}"
        echo -e "${CYAN}    pvm use 3.12.4        # Activate it${NC}"
        echo -e "${CYAN}    pvm alias default 3.12.4  # Set default${NC}"
        echo ""
        return
    fi

    local python_exe="$PVM_SYMLINK/bin/python3"
    if [[ -x "$python_exe" ]]; then
        local python_version
        python_version=$($python_exe --version 2>&1)
        echo "  Python output:   $python_version"
        echo -e "${GRAY}  Path:            $python_exe${NC}"
    fi
    echo ""
}

# Show which python
pvm_which() {
    local current
    current=$(pvm_get_current)
    
    if [[ -z "$current" ]]; then
        echo ""
        echo -e "${YELLOW}  No Python version is currently active.${NC}"
        echo "  Use 'pvm use <version>' to activate a version."
        echo ""
        return
    fi
    
    local python_exe="$PVM_SYMLINK/bin/python3"
    local pip_exe="$PVM_SYMLINK/bin/pip3"
    
    echo ""
    echo -e "${GREEN}  Current version: $current${NC}"
    echo ""
    
    if [[ -x "$python_exe" ]]; then
        echo "  python3: $python_exe"
    else
        echo -e "${RED}  python3: (not found)${NC}"
    fi
    
    if [[ -x "$pip_exe" ]]; then
        echo "  pip3:    $pip_exe"
    else
        echo -e "${YELLOW}  pip3:    (not found)${NC}"
    fi
    echo ""
}

# Configure mirror
pvm_config() {
    local mirror_name="$1"
    
    # If no argument, show current config
    if [[ -z "$mirror_name" ]]; then
        pvm_show_config
        return
    fi
    
    local mirror_url=""
    local lower_name="${mirror_name,,}"
    
    # Check if it's a preset name
    if [[ -n "${MIRRORS[$lower_name]}" ]]; then
        mirror_url="${MIRRORS[$lower_name]}"
        echo -e "${CYAN}Using preset mirror: $mirror_name${NC}"
    elif [[ "$mirror_name" =~ ^https?:// ]]; then
        # It's a custom URL
        mirror_url="$mirror_name"
        echo -e "${CYAN}Using custom mirror URL${NC}"
    else
        echo -e "${RED}Error: Unknown mirror '$mirror_name'${NC}"
        echo ""
        echo -e "${YELLOW}Available presets:${NC}"
        echo "  tsinghua, qinghua   - Tsinghua University (https://mirrors.tuna.tsinghua.edu.cn/python)"
        echo "  huawei              - Huawei Cloud (https://mirrors.huaweicloud.com/python)"
        echo "  aliyun              - Aliyun (https://mirrors.aliyun.com/python)"
        echo "  default             - python.org (https://www.python.org/ftp/python)"
        echo ""
        echo "Or use a custom URL: pvm config https://your-mirror.com/python"
        return 1
    fi
    
    # Save to settings
    echo "{\"mirror\": \"$mirror_url\", \"mirror_selected\": true}" > "$PVM_SETTINGS_FILE"
    
    echo -e "${GREEN}Python mirror configured: $mirror_url${NC}"
    
    # Configure pip mirror
    local pip_mirror_url=""
    if [[ -n "${PIP_MIRRORS[$lower_name]}" ]]; then
        pip_mirror_url="${PIP_MIRRORS[$lower_name]}"
    fi
    
    if [[ -n "$pip_mirror_url" ]]; then
        # Create pip config directory
        local pip_config_dir="$HOME/.pip"
        mkdir -p "$pip_config_dir"
        
        # Extract host from URL for trusted-host
        local pip_host
        pip_host=$(echo "$pip_mirror_url" | sed -E 's|https?://([^/]+).*|\1|')
        
        # Write pip.conf
        local pip_config_file="$pip_config_dir/pip.conf"
        cat > "$pip_config_file" << EOF
[global]
index-url = $pip_mirror_url
trusted-host = $pip_host
EOF
        echo -e "${GREEN}pip mirror configured: $pip_mirror_url${NC}"
        echo -e "${GRAY}pip config file: $pip_config_file${NC}"
    fi
}

# Show current config
pvm_show_config() {
    local mirror
    mirror=$(pvm_get_mirror)
    
    # Get pip config
    local pip_config_file="$HOME/.pip/pip.conf"
    local pip_mirror="https://pypi.org/simple (default)"
    if [[ -f "$pip_config_file" ]]; then
        local pip_url
        pip_url=$(grep -E '^index-url\s*=' "$pip_config_file" 2>/dev/null | sed 's/index-url\s*=\s*//')
        if [[ -n "$pip_url" ]]; then
            pip_mirror="$pip_url"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}pvm Configuration:${NC}"
    echo ""
    echo "  Python mirror: $mirror"
    echo "  pip mirror:    $pip_mirror"
    echo ""
    echo -e "${GRAY}  pvm config:  $PVM_SETTINGS_FILE${NC}"
    echo -e "${GRAY}  pip config:  $pip_config_file${NC}"
    echo ""
    echo -e "${YELLOW}Available presets (configures both Python and pip):${NC}"
    echo "  pvm config tsinghua   - Tsinghua University"
    echo "  pvm config huawei     - Huawei Cloud"
    echo "  pvm config aliyun     - Aliyun"
    echo "  pvm config default    - python.org / pypi.org (Official)"
    echo ""
}

# --- Virtual Environment Management ---

pvm_venv() {
    local subcmd="$1"
    local name="$2"
    shift 2 || true
    local venvs_dir="$PVM_VENVS_DIR"
    mkdir -p "$venvs_dir"

    # Parse --python flag
    local py_ver=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --python)
                py_ver="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    case "$subcmd" in
        ""|create)
            if [[ -z "$name" ]]; then
                echo -e "${RED}Error: Please specify a venv name.${NC}"
                echo "Usage: pvm venv <name> [--python <version>]"
                return 1
            fi
            # Use specified Python version or current
            local python_exe=""
            if [[ -n "$py_ver" ]]; then
                local resolved
                resolved=$(pvm_resolve_available "$py_ver")
                if [[ -n "$resolved" ]]; then
                    python_exe="$PVM_HOME/versions/$resolved/bin/python3"
                fi
                if [[ ! -x "$python_exe" ]]; then
                    echo -e "${RED}Error: Python $py_ver not installed. Run: pvm install $py_ver${NC}"
                    return 1
                fi
                echo -e "${GRAY}Using Python $resolved${NC}"
            else
                local current
                current=$(pvm_get_current)
                if [[ -z "$current" ]]; then
                    echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                    return 1
                fi
                python_exe="$PVM_HOME/versions/$current/bin/python3"
            fi
            if [[ ! -x "$python_exe" ]]; then
                echo -e "${RED}Error: Python executable not found.${NC}"
                return 1
            fi
            local venv_path="$venvs_dir/$name"
            if [[ -d "$venv_path" ]]; then
                echo -e "${YELLOW}Virtual environment '$name' already exists.${NC}"
                return 0
            fi
            echo -e "${CYAN}Creating virtual environment '$name'...${NC}"
            "$python_exe" -m venv "$venv_path" 2>/dev/null
            if [[ -d "$venv_path" ]]; then
                echo -e "${GREEN}Created: $venv_path${NC}"
                echo ""
                echo -e "${YELLOW}To activate this virtual environment, run:${NC}"
                echo -e "${CYAN}  source $venv_path/bin/activate${NC}"
                echo ""
                # Auto-activate in current session
                if [[ -f "$venv_path/bin/activate" ]]; then
                    source "$venv_path/bin/activate"
                    echo -e "${GREEN}  Virtual environment '$name' is now active.${NC}"
                fi
            else
                echo -e "${RED}Error: Failed to create virtual environment.${NC}"
            fi
            ;;
        list)
            if [[ ! -d "$venvs_dir" ]] || [[ -z "$(ls -A "$venvs_dir" 2>/dev/null)" ]]; then
                echo -e "${YELLOW}No virtual environments found.${NC}"
                return 0
            fi
            echo -e "\n${CYAN}Virtual environments:${NC}"
            for d in "$venvs_dir"/*/; do
                echo "  $(basename "$d")"
            done
            echo ""
            ;;
        remove)
            if [[ -z "$name" ]]; then
                echo -e "${RED}Error: Please specify a venv name to remove.${NC}"
                return 1
            fi
            local venv_path="$venvs_dir/$name"
            if [[ ! -d "$venv_path" ]]; then
                echo -e "${RED}Error: Virtual environment '$name' not found.${NC}"
                return 1
            fi
            rm -rf "$venv_path"
            echo -e "${GREEN}Removed virtual environment '$name'.${NC}"
            ;;
        activate)
            if [[ -z "$name" ]]; then
                echo -e "${RED}Error: Please specify a venv name.${NC}"
                return 1
            fi
            local venv_path="$venvs_dir/$name"
            if [[ ! -d "$venv_path" ]]; then
                echo -e "${RED}Error: Virtual environment '$name' not found.${NC}"
                return 1
            fi
            echo -e "${YELLOW}Run this command in your shell:${NC}"
            echo -e "${CYAN}  source $venv_path/bin/activate${NC}"
            ;;
        *)
            echo -e "${YELLOW}Usage: pvm venv <create|list|remove|activate> [name]${NC}"
            ;;
    esac
}

# --- Package Management ---

pvm_pip() {
    local subcmd="$1"
    shift || true

    local current
    current=$(pvm_get_current)
    if [[ -z "$current" ]]; then
        echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
        return 1
    fi
    local pip_exe="$PVM_HOME/versions/$current/bin/pip3"
    if [[ ! -x "$pip_exe" ]]; then
        echo -e "${RED}Error: pip not found for current Python version.${NC}"
        return 1
    fi

    case "$subcmd" in
        install)
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}Error: Please specify a package to install.${NC}"
                echo "Usage: pvm pip install <package>"
                return 1
            fi
            "$pip_exe" install "$@"
            ;;
        uninstall)
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}Error: Please specify a package to uninstall.${NC}"
                return 1
            fi
            "$pip_exe" uninstall -y "$@"
            ;;
        list)
            "$pip_exe" list
            ;;
        upgrade)
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}Error: Please specify a package to upgrade.${NC}"
                return 1
            fi
            "$pip_exe" install --upgrade "$@"
            ;;
        freeze)
            "$pip_exe" freeze
            ;;
        check)
            "$pip_exe" check
            ;;
        *)
            echo -e "${YELLOW}Usage: pvm pip <install|uninstall|list|upgrade|freeze|check> [package]${NC}"
            ;;
    esac
}

# --- Project Management ---

pvm_project() {
    local subcmd="$1"
    shift || true

    case "$subcmd" in
        init)
            local pyproject="pyproject.toml"
            if [[ -f "$pyproject" ]]; then
                echo -e "${YELLOW}pyproject.toml already exists in this directory.${NC}"
                return 0
            fi
            printf "Project name [myproject]: "
            read -r project_name
            project_name="${project_name:-myproject}"
            printf "Description: "
            read -r description
            local current
            current=$(pvm_get_current)
            local pyversion="${current:-3.12}"
            printf "Python version [$pyversion]: "
            read -r input_ver
            pyversion="${input_ver:-$pyversion}"

            cat > "$pyproject" << PROJ
[project]
name = "$project_name"
version = "0.1.0"
description = "$description"
requires-python = ">=$pyversion"
dependencies = []

[build-system]
requires = ["setuptools>=68.0", "wheel"]
build-backend = "setuptools.backends._legacy:_Backend"
PROJ
            echo -e "${GREEN}Created pyproject.toml${NC}"

            # Create project venv
            local python_exe="$PVM_HOME/versions/$current/bin/python3"
            if [[ -x "$python_exe" ]]; then
                local venv_path=".pvm-venv"
                if [[ ! -d "$venv_path" ]]; then
                    echo -e "${CYAN}Creating project virtual environment...${NC}"
                    "$python_exe" -m venv "$venv_path" 2>/dev/null
                    echo -e "${GREEN}Created .pvm-venv/${NC}"
                fi
            fi
            ;;
        add)
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}Error: Please specify a package to add.${NC}"
                return 1
            fi
            if [[ ! -f "pyproject.toml" ]]; then
                echo -e "${RED}Error: No pyproject.toml found. Run 'pvm init' first.${NC}"
                return 1
            fi
            pvm_pip install "$@"
            local pkg="$1"
            pkg="${pkg%%[*}"  # strip version spec
            if grep -q 'dependencies = \[\]' pyproject.toml; then
                sed -i "s/dependencies = \[\]/dependencies = [\n    \"$pkg\",\n]/" pyproject.toml
            else
                sed -i "/dependencies = \[/a\    \"$pkg\"," pyproject.toml
            fi
            echo -e "${GREEN}Added '$pkg' to pyproject.toml${NC}"
            ;;
        remove)
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}Error: Please specify a package to remove.${NC}"
                return 1
            fi
            local pkg="$1"
            pkg="${pkg%%[*}"
            if [[ -f "pyproject.toml" ]]; then
                sed -i "/\"$pkg\"/d" pyproject.toml
                echo -e "${GREEN}Removed '$pkg' from pyproject.toml${NC}"
            fi
            pvm_pip uninstall "$@"
            ;;
        run)
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}Error: Please specify a command to run.${NC}"
                return 1
            fi
            local venv_bin=".pvm-venv/bin"
            if [[ ! -d "$venv_bin" ]]; then
                echo -e "${RED}Error: No .pvm-venv found. Run 'pvm init' first.${NC}"
                return 1
            fi
            # Run command in venv context by prepending venv bin to PATH
            local old_path="$PATH"
            PATH="$(pwd)/$venv_bin:$PATH"
            "$@"
            local rc=$?
            PATH="$old_path"
            return $rc
            ;;
        *)
            echo -e "${YELLOW}Usage: pvm <init|add|remove|run> [args]${NC}"
            ;;
    esac
}

# Main function
pvm() {
    # Save original values for --home per-command restore
    local _orig_PVM_HOME="$PVM_HOME"
    local _orig_PVM_VERSIONS_DIR="$PVM_VERSIONS_DIR"
    local _orig_PVM_CURRENT_FILE="$PVM_CURRENT_FILE"
    local _orig_PVM_SETTINGS_FILE="$PVM_SETTINGS_FILE"
    local _orig_PVM_SYMLINK="$PVM_SYMLINK"
    local _orig_PVM_SHIMS_DIR="$PVM_SHIMS_DIR"

    # Parse --home argument before anything else
    local new_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --home)
                if [[ -n "$2" ]]; then
                    PVM_HOME="$2"
                    PVM_VERSIONS_DIR="$PVM_HOME/versions"
                    PVM_CURRENT_FILE="$PVM_HOME/current"
                    PVM_SETTINGS_FILE="$PVM_HOME/settings.json"
                    PVM_SYMLINK="$PVM_HOME/python"
                    PVM_SHIMS_DIR="$PVM_HOME/shims"
                    PVM_VENVS_DIR="$PVM_HOME/venvs"
                    # Auto-create directory if needed
                    if [[ ! -d "$PVM_HOME" ]]; then
                        mkdir -p "$PVM_HOME"
                        echo -e "${GRAY}  Created data directory: $PVM_HOME${NC}"
                    fi
                    shift 2
                else
                    echo -e "${RED}Error: --home requires a path argument${NC}"
                    return 1
                fi
                ;;
            *)
                new_args+=("$1")
                shift
                ;;
        esac
    done
    set -- "${new_args[@]+"${new_args[@]}"}"

    pvm_init

    # The command runs with possibly overridden PVM_HOME.
    # We use a trap to restore original values after the command completes.
    
    local command="$1"
    shift || true
    
    case "$command" in
        list)
            if [[ "$1" == "available" ]]; then
                pvm_list_available
            else
                pvm_list
            fi
            ;;
        install)
            pvm_install "$1" "$@"
            ;;
        uninstall)
            pvm_uninstall "$1"
            ;;
        use)
            pvm_use "$1"
            ;;
        current)
            pvm_current
            ;;
        which)
            pvm_which
            ;;
        config)
            pvm_config "$1"
            ;;
        alias)
            if [[ "$1" == "default" ]]; then
                local target="$2"
                if [[ -z "$target" ]]; then
                    echo -e "${YELLOW}Usage: pvm alias default <version>${NC}"
                    return 1
                fi
                local resolved
                resolved=$(pvm_resolve_available "$target")
                if [[ -z "$resolved" ]]; then
                    echo -e "${RED}Error: Version '$target' not found.${NC}"
                    return 1
                fi
                pvm_set_default "$resolved"
                echo -e "${GREEN}Default version set to $resolved${NC}"
            else
                pvm_alias
            fi
            ;;
        unalias)
            if [[ "$1" == "default" ]]; then
                pvm_remove_default
                echo -e "${GREEN}Default version removed.${NC}"
            else
                echo -e "${YELLOW}Usage: pvm unalias default${NC}"
            fi
            ;;
        arch|platform)
            pvm_show_platform
            ;;
        venv)
            pvm_venv "$1" "$2" "${@:3}"
            ;;
        pip)
            shift
            pvm_pip "$@"
            ;;
        export)
            # Export installed packages to requirements file
            local pip_exe="$PVM_HOME/versions/$(pvm_get_current)/bin/pip3"
            if [[ ! -x "$pip_exe" ]]; then
                echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                return 1
            fi
            local outfile="${1:-requirements.txt}"
            "$pip_exe" freeze > "$outfile"
            echo -e "${GREEN}Exported requirements to $outfile${NC}"
            ;;
        import)
            # Import packages from requirements file
            local reqfile="${1:-requirements.txt}"
            if [[ ! -f "$reqfile" ]]; then
                echo -e "${RED}Error: File '$reqfile' not found.${NC}"
                return 1
            fi
            local pip_exe="$PVM_HOME/versions/$(pvm_get_current)/bin/pip3"
            if [[ ! -x "$pip_exe" ]]; then
                echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                return 1
            fi
            echo -e "${CYAN}Installing packages from $reqfile...${NC}"
            "$pip_exe" install -r "$reqfile"
            echo -e "${GREEN}Done.${NC}"
            ;;
        pin)
            # Pin Python version for current directory
            if [[ -z "$1" || "$1" == "--remove" || "$1" == "-r" ]]; then
                if [[ "$1" == "--remove" || "$1" == "-r" ]]; then
                    if [[ -f ".python-version" ]]; then
                        rm -f ".python-version"
                        echo -e "${GREEN}Removed .python-version pin from this directory.${NC}"
                    else
                        echo -e "${YELLOW}No version pinned in this directory.${NC}"
                    fi
                    return
                fi
                if [[ -f ".python-version" ]]; then
                    local pinned_ver
                    pinned_ver=$(cat ".python-version" | tr -d '[:space:]')
                    echo -e "${GREEN}Pinned version: $pinned_ver${NC}"
                    echo -e "${GRAY}File: .python-version${NC}"
                else
                    echo -e "${YELLOW}No version pinned in this directory.${NC}"
                    echo -e "${YELLOW}Usage: pvm pin <version> | pvm pin --remove${NC}"
                fi
                return
            fi
            local resolved
            resolved=$(pvm_resolve_available "$1")
            if [[ -z "$resolved" ]]; then
                echo -e "${RED}Error: Version '$1' not found.${NC}"
                return 1
            fi
            echo -n "$resolved" > ".python-version"
            echo -e "${GREEN}Pinned Python $resolved for this directory${NC}"
            echo -e "${GRAY}File: .python-version${NC}"
            ;;
        unpin)
            # Remove .python-version file
            if [[ -f ".python-version" ]]; then
                rm -f ".python-version"
                echo -e "${GREEN}Removed .python-version pin from this directory.${NC}"
            else
                echo -e "${YELLOW}No version pinned in this directory.${NC}"
            fi
            ;;
        tree)
            # Show dependency tree
            local current
            current=$(pvm_get_current)
            if [[ -z "$current" ]]; then
                echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                return 1
            fi
            local pip_exe="$PVM_HOME/versions/$current/bin/pip3"
            if [[ ! -x "$pip_exe" ]]; then
                echo -e "${RED}Error: pip not found.${NC}"
                return 1
            fi
            # Try pipdeptree first
            local pipdeptree_exe="$PVM_HOME/versions/$current/bin/pipdeptree"
            if [[ ! -x "$pipdeptree_exe" ]]; then
                "$pip_exe" install pipdeptree --no-warn-script-location 2>/dev/null
                pipdeptree_exe="$PVM_HOME/versions/$current/bin/pipdeptree"
            fi
            if [[ -x "$pipdeptree_exe" ]]; then
                "$pipdeptree_exe"
            else
                echo -e "${CYAN}Dependency tree (flat list):${NC}"
                "$pip_exe" list --format=columns
            fi
            ;;
        lock)
            # Lock dependencies
            local current
            current=$(pvm_get_current)
            if [[ -z "$current" ]]; then
                echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                return 1
            fi
            local pip_exe="$PVM_HOME/versions/$current/bin/pip3"
            local outfile="${1:-requirements.lock}"
            "$pip_exe" freeze > "$outfile"
            local count
            count=$(wc -l < "$outfile")
            echo -e "${GREEN}Locked $count packages to $outfile${NC}"
            ;;
        sync)
            # Sync environment from lock file
            local reqfile="${1:-requirements.lock}"
            if [[ ! -f "$reqfile" ]]; then
                reqfile="requirements.txt"
                if [[ ! -f "$reqfile" ]]; then
                    echo -e "${RED}Error: No requirements.lock or requirements.txt found.${NC}"
                    return 1
                fi
            fi
            local current
            current=$(pvm_get_current)
            if [[ -z "$current" ]]; then
                echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                return 1
            fi
            local pip_exe="$PVM_HOME/versions/$current/bin/pip3"
            echo -e "${CYAN}Syncing environment from $reqfile...${NC}"
            "$pip_exe" install -r "$reqfile"
            echo -e "${GREEN}Environment synced.${NC}"
            ;;
        tool)
            # Tool management
            case "$1" in
                install)
                    if [[ -z "$2" ]]; then
                        echo -e "${RED}Error: Please specify a tool to install.${NC}"
                        return 1
                    fi
                    local current
                    current=$(pvm_get_current)
                    if [[ -z "$current" ]]; then
                        echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                        return 1
                    fi
                    local python_exe="$PVM_HOME/versions/$current/bin/python3"
                    local tool_dir="$PVM_HOME/tools"
                    mkdir -p "$tool_dir"
                    local tool_name="$2"
                    local tool_venv="$tool_dir/$tool_name"
                    if [[ ! -d "$tool_venv" ]]; then
                        "$python_exe" -m venv "$tool_venv" 2>/dev/null
                    fi
                    local tool_pip="$tool_venv/bin/pip3"
                    shift 2
                    "$tool_pip" install "$@"
                    echo -e "${GREEN}Installed tool: $tool_name${NC}"
                    echo -e "${GRAY}Run with: pvm tool run $tool_name${NC}"
                    ;;
                run)
                    if [[ -z "$2" ]]; then
                        echo -e "${RED}Error: Please specify a tool to run.${NC}"
                        return 1
                    fi
                    local tool_dir="$PVM_HOME/tools"
                    local tool_name="$2"
                    local tool_exe="$tool_dir/$tool_name/bin/$tool_name"
                    if [[ ! -x "$tool_exe" ]]; then
                        local tool_python="$tool_dir/$tool_name/bin/python3"
                        if [[ -x "$tool_python" ]]; then
                            shift 2
                            "$tool_python" -m "$tool_name" "$@"
                            return
                        fi
                        echo -e "${RED}Error: Tool '$tool_name' not found. Install with: pvm tool install $tool_name${NC}"
                        return 1
                    fi
                    shift 2
                    "$tool_exe" "$@"
                    ;;
                list)
                    local tool_dir="$PVM_HOME/tools"
                    if [[ ! -d "$tool_dir" ]] || [[ -z "$(ls -A "$tool_dir" 2>/dev/null)" ]]; then
                        echo -e "${YELLOW}No tools installed.${NC}"
                        return 0
                    fi
                    echo -e "\n${CYAN}Installed tools:${NC}"
                    for d in "$tool_dir"/*/; do
                        echo "  $(basename "$d")"
                    done
                    echo ""
                    ;;
                uninstall)
                    if [[ -z "$2" ]]; then
                        echo -e "${RED}Error: Please specify a tool to uninstall.${NC}"
                        return 1
                    fi
                    local tool_dir="$PVM_HOME/tools/$2"
                    if [[ -d "$tool_dir" ]]; then
                        rm -rf "$tool_dir"
                        echo -e "${GREEN}Uninstalled tool: $2${NC}"
                    else
                        echo -e "${RED}Error: Tool '$2' not found.${NC}"
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}Usage: pvm tool <install|run|list|uninstall> [args]${NC}"
                    ;;
            esac
            ;;
        build)
            # Build package
            local current
            current=$(pvm_get_current)
            if [[ -z "$current" ]]; then
                echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                return 1
            fi
            if [[ ! -f "pyproject.toml" ]]; then
                echo -e "${RED}Error: No pyproject.toml found. Run 'pvm init' first.${NC}"
                return 1
            fi
            local pip_exe="$PVM_HOME/versions/$current/bin/pip3"
            local python_exe="$PVM_HOME/versions/$current/bin/python3"
            "$pip_exe" install build --no-warn-script-location 2>/dev/null
            if "$python_exe" -m build; then
                echo -e "${GREEN}Build complete. Check dist/ folder.${NC}"
            else
                echo -e "${RED}Build failed.${NC}"
                return 1
            fi
            ;;
        publish)
            # Publish package to PyPI
            local current
            current=$(pvm_get_current)
            if [[ -z "$current" ]]; then
                echo -e "${RED}Error: No Python version active. Run: pvm use <version>${NC}"
                return 1
            fi
            if [[ ! -d "dist" ]]; then
                echo -e "${RED}Error: No dist/ folder found. Run 'pvm build' first.${NC}"
                return 1
            fi
            local pip_exe="$PVM_HOME/versions/$current/bin/pip3"
            "$pip_exe" install twine --no-warn-script-location 2>/dev/null
            local twine_exe="$PVM_HOME/versions/$current/bin/twine"
            if [[ -x "$twine_exe" ]]; then
                "$twine_exe" upload dist/*
            else
                echo -e "${RED}Error: twine not found.${NC}"
            fi
            ;;
        cache)
            if [[ "$1" == "clean" ]]; then
                local current
                current=$(pvm_get_current)
                if [[ -n "$current" ]]; then
                    local pip_exe="$PVM_HOME/versions/$current/bin/pip3"
                    if [[ -x "$pip_exe" ]]; then
                        "$pip_exe" cache purge 2>/dev/null
                        echo -e "${GREEN}pip cache cleaned.${NC}"
                    fi
                fi
                local cache_file="$PVM_HOME/versions_cache.json"
                if [[ -f "$cache_file" ]]; then
                    rm -f "$cache_file"
                    echo -e "${GREEN}Version cache cleaned.${NC}"
                fi
            else
                echo -e "${YELLOW}Usage: pvm cache clean${NC}"
            fi
            ;;
        --help|-h|help)
            pvm_help
            ;;
        --version|-v)
            pvm_version
            ;;
        "")
            pvm_help
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}"
            echo "Use 'pvm --help' for usage information."
            return 1
            ;;
    esac

    # Restore original PVM_HOME (--home is per-command only)
    PVM_HOME="$_orig_PVM_HOME"
    PVM_VERSIONS_DIR="$_orig_PVM_VERSIONS_DIR"
    PVM_CURRENT_FILE="$_orig_PVM_CURRENT_FILE"
    PVM_SETTINGS_FILE="$_orig_PVM_SETTINGS_FILE"
    PVM_SYMLINK="$_orig_PVM_SYMLINK"
    PVM_SHIMS_DIR="$_orig_PVM_SHIMS_DIR"
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    pvm "$@"
fi

