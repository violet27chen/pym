#!/usr/bin/env bash

# pvm uninstaller for Unix (Linux/macOS)
# Completely removes pvm (Python Version Manager) from the system.
#
# Usage:
#   bash uninstall.sh
#   bash uninstall.sh --force    # skip confirmation

set -e

# Configuration
PVM_HOME="${PVM_HOME:-$HOME/.pvm}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

FORCE=false
if [[ "$1" == "--force" || "$1" == "-f" ]]; then
    FORCE=true
fi

# Detect shell profile
detect_shell() {
    if [[ -n "$ZSH_VERSION" ]]; then
        echo "zsh"
    elif [[ -n "$BASH_VERSION" ]]; then
        echo "bash"
    else
        echo "sh"
    fi
}

get_profile() {
    local shell_name
    shell_name=$(detect_shell)

    case "$shell_name" in
        zsh)
            if [[ -f "$HOME/.zshrc" ]]; then echo "$HOME/.zshrc"
            else echo "$HOME/.zprofile"; fi
            ;;
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then echo "$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then echo "$HOME/.bash_profile"
            else echo "$HOME/.profile"; fi
            ;;
        *)
            echo "$HOME/.profile"
            ;;
    esac
}

# Main uninstall
uninstall_pvm() {
    echo ""
    echo -e "${CYAN}==================================${NC}"
    echo -e "${CYAN}  pvm - Python Version Manager${NC}"
    echo -e "${CYAN}  Unix Uninstaller${NC}"
    echo -e "${CYAN}==================================${NC}"
    echo ""

    # Check if pvm is installed
    if [[ ! -d "$PVM_HOME" ]]; then
        echo -e "${YELLOW}pvm is not installed at: $PVM_HOME${NC}"
        echo "Nothing to uninstall."
        echo ""
        return
    fi

    # List installed Python versions
    local versions=()
    if [[ -d "$PVM_HOME/versions" ]]; then
        while IFS= read -r d; do
            versions+=("$(basename "$d")")
        done < <(find "$PVM_HOME/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    fi

    # Show what will be removed
    echo -e "${YELLOW}This will completely remove pvm from your system:${NC}"
    echo ""
    echo "  Installation directory:"
    echo -e "    ${CYAN}$PVM_HOME${NC}"
    echo ""

    if [[ ${#versions[@]} -gt 0 ]]; then
        echo "  Python versions to be removed:"
        for v in "${versions[@]}"; do
            echo -e "    ${CYAN}- $v${NC}"
        done
        echo ""
    fi

    echo "  PATH entries to be removed:"
    echo -e "    ${GRAY}- \$PVM_HOME/python/bin${NC}"
    echo -e "    ${GRAY}- \$PVM_HOME/shims${NC}"
    echo ""

    local profile
    profile=$(get_profile)
    if grep -q "PVM_HOME" "$profile" 2>/dev/null; then
        echo "  Shell profile entries to be removed:"
        echo -e "    ${GRAY}$profile${NC}"
        echo ""
    fi

    local pip_config="$HOME/.pip/pip.conf"
    if [[ -f "$pip_config" ]]; then
        echo "  pip mirror config (may be removed):"
        echo -e "    ${GRAY}$pip_config${NC}"
        echo ""
    fi

    # Confirm unless --force
    if [[ "$FORCE" != true ]]; then
        echo ""
        read -r -p "Are you sure you want to uninstall pvm? (y/N) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "yes" && "$confirm" != "Yes" ]]; then
            echo -e "${YELLOW}Uninstall cancelled.${NC}"
            echo ""
            return
        fi
    fi

    echo ""

    # Step 1: Remove shell profile entries
    echo -e "${YELLOW}[1/4] Cleaning shell profile...${NC}"
    if grep -q "PVM_HOME" "$profile" 2>/dev/null; then
        # Remove pvm-related lines from profile
        local tmp_profile="${profile}.pvm-backup"
        cp "$profile" "$tmp_profile"

        # Remove lines containing pvm markers
        sed -i.bak '/# pvm - Python Version Manager/d' "$profile" 2>/dev/null || true
        sed -i.bak '/PVM_HOME/d' "$profile" 2>/dev/null || true
        sed -i.bak '/pvm\.sh/d' "$profile" 2>/dev/null || true
        sed -i.bak '/pvm\/shims/d' "$profile" 2>/dev/null || true

        # Remove any resulting blank lines (collapse multiple blanks)
        sed -i.bak '/^$/N;/^\n$/d' "$profile" 2>/dev/null || true

        # Clean up sed backup files
        rm -f "${profile}.bak" 2>/dev/null || true

        echo -e "      Shell profile cleaned: ${GREEN}$profile${NC}"
        echo -e "      Backup saved to: ${GRAY}$tmp_profile${NC}"
    else
        echo -e "      ${GRAY}No pvm entries found in shell profile.${NC}"
    fi

    # Step 2: Ask about pip config
    echo -e "${YELLOW}[2/4] Checking pip configuration...${NC}"
    if [[ -f "$pip_config" ]]; then
        local remove_pip=false
        if [[ "$FORCE" != true ]]; then
            echo ""
            read -r -p "Remove pip mirror config ($pip_config)? (y/N) " pip_confirm
            if [[ "$pip_confirm" == "y" || "$pip_confirm" == "Y" || "$pip_confirm" == "yes" || "$pip_confirm" == "Yes" ]]; then
                remove_pip=true
            fi
        else
            remove_pip=true
        fi

        if [[ "$remove_pip" == true ]]; then
            rm -f "$pip_config"
            # Remove pip config directory if empty
            local pip_dir
            pip_dir=$(dirname "$pip_config")
            if [[ -d "$pip_dir" ]] && [[ -z "$(ls -A "$pip_dir" 2>/dev/null)" ]]; then
                rmdir "$pip_dir" 2>/dev/null || true
            fi
            echo -e "      ${GREEN}pip config removed.${NC}"
        else
            echo -e "      ${GRAY}pip config kept.${NC}"
        fi
    else
        echo -e "      ${GRAY}No pip config found, skipping.${NC}"
    fi

    # Step 3: Remove the .pvm directory
    echo -e "${YELLOW}[3/4] Removing pvm installation directory...${NC}"

    # Remove symlink first to avoid issues
    local symlink_path="$PVM_HOME/python"
    if [[ -L "$symlink_path" ]]; then
        rm -f "$symlink_path"
    fi

    rm -rf "$PVM_HOME"
    echo -e "      ${GREEN}Directory removed: $PVM_HOME${NC}"

    # Step 4: Summary
    echo -e "${YELLOW}[4/4] Cleanup complete.${NC}"

    echo ""
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}  pvm has been uninstalled successfully!${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo ""
    echo "  Removed:"
    echo -e "    ${GRAY}- pvm installation directory${NC}"
    if [[ ${#versions[@]} -gt 0 ]]; then
        echo -e "    ${GRAY}- ${#versions[@]} Python version(s)${NC}"
    fi
    echo -e "    ${GRAY}- Shell profile entries${NC}"
    echo ""
    echo -e "  ${YELLOW}Note: Open a new terminal or run 'source $profile' for changes to take effect.${NC}"
    echo ""
}

# Run uninstaller
uninstall_pvm
