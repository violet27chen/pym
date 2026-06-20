# pvm - Python Version Manager

[**中文文档**](README_ZH.md)

---

**pvm** is a simple, cross-platform Python version manager inspired by [nvm](https://github.com/nvm-sh/nvm). It allows you to easily install, switch between, and manage multiple Python versions on your system.

## Quick Install

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/violet27chen/pym/main/install.ps1 | iex
```

**Linux/macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/violet27chen/pym/main/install.sh | bash
```

### CDN Accelerated Install

Use jsDelivr CDN for faster downloads in regions where GitHub is slow. The entire installation (scripts + dependencies) is accelerated:

**Windows (PowerShell):**
```powershell
$env:PVM_CDN=1; irm https://cdn.jsdelivr.net/gh/violet27chen/pym@main/install.ps1 | iex
```

**Linux/macOS:**
```bash
PVM_CDN=1 curl -fsSL https://cdn.jsdelivr.net/gh/violet27chen/pym@main/install.sh | bash
```

> Note: When piped via `iex` or `curl | bash`, the installer auto-detects the source and prioritizes it for all downloads. You can also use `$env:PVM_CDN=1` (PowerShell) or `PVM_CDN=1` (Bash) to force CDN mode.

---

## Features

- **Dynamic version list** - Fetches available versions from python.org (no manual updates needed)
- **Precompiled binaries** - Linux/macOS uses python-build-standalone prebuilt binaries (no gcc/make required)
- Install multiple Python versions side by side
- Switch between Python versions with a single command
- Partial version matching (e.g. `pvm install 3.13` auto-resolves to latest 3.13.x)
- nvm-style shim mechanism for instant version switching
- Uninstall Python versions you no longer need
- **Virtual environment management** (`pvm venv`)
- **Package management** (`pvm pip`)
- **Project management** (`pvm init`, `pvm add`, `pvm run`)
- Windows support (PowerShell/CMD)
- Linux/macOS support (Bash)
- Mirror support for faster downloads in China

## Installation

### Windows (PowerShell)

```powershell
# Standard install (GitHub)
irm https://raw.githubusercontent.com/violet27chen/pym/main/install.ps1 | iex

# CDN accelerated install (entire process uses jsDelivr CDN)
$env:PVM_CDN=1; irm https://cdn.jsdelivr.net/gh/violet27chen/pym@main/install.ps1 | iex
```

Or manually:

```powershell
git clone https://github.com/violet27chen/pym.git
cd pym
.\install.ps1
```

### Windows (CMD)

After installation, you can use `pvm` command directly in CMD:

```cmd
pvm --help
pvm list available
pvm install 3.12.4
```

### Linux/macOS

```bash
# Standard install (GitHub)
curl -fsSL https://raw.githubusercontent.com/violet27chen/pym/main/install.sh | bash

# CDN accelerated install (entire process uses jsDelivr CDN)
PVM_CDN=1 curl -fsSL https://cdn.jsdelivr.net/gh/violet27chen/pym@main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/violet27chen/pym.git
cd pym
./install.sh
```

> **CDN acceleration**: When using `PVM_CDN=1` (or when piped via `iex`/`curl | bash`), the installer automatically prioritizes jsDelivr CDN for **all** downloads (install scripts, pvm core, etc.), ensuring the entire installation is accelerated.

## Usage

### Version Management

```bash
# List installed Python versions
pvm list

# List available Python versions for download (fetched from python.org)
pvm list available

# Install a specific Python version (full version)
pvm install 3.12.4

# Install with partial version (auto-resolves to latest matching version)
pvm install 3.13      # -> installs latest 3.13.x
pvm install 3         # -> installs latest 3.x

# Force build from source (skip precompiled binary)
pvm install 3.12.4 --source

# Use a specific Python version
pvm use 3.12.4

# Use partial version (auto-resolves to installed matching version)
pvm use 3.13          # -> switches to installed 3.13.x

# Show currently active Python version
pvm current

# Uninstall a Python version
pvm uninstall 3.11.9
```

### Virtual Environment Management

```bash
# Create a virtual environment
pvm venv myenv

# List all virtual environments
pvm venv list

# Show activation command
pvm venv activate myenv

# Remove a virtual environment
pvm venv remove myenv
```

### Package Management

```bash
# Install a package
pvm pip install requests

# Install with version constraint
pvm pip install "django>=4.0"

# Uninstall a package
pvm pip uninstall requests

# List installed packages
pvm pip list

# Upgrade a package
pvm pip upgrade requests
```

### Project Management

```bash
# Initialize a new project (creates pyproject.toml + .pvm-venv)
pvm init

# Add a dependency
pvm add requests

# Remove a dependency
pvm remove requests

# Run a command in the project virtual environment
pvm run python main.py
pvm run pytest
```

## Configuration

pvm stores its data in `~/.pvm` (Unix) or `%USERPROFILE%\.pvm` (Windows) by default.

On first use, pvm will prompt you to choose a data directory. Press Enter to accept the default, or type a custom path. The choice is saved to `~/.pvmhome` for future sessions.

You can also customize the data directory in other ways:

### `--home` flag (per-command override)

Only affects the current command. The directory is auto-created if it doesn't exist.

```bash
pvm install 3.12 --home D:\pvm       # Install to D:\pvm (creates dir if needed)
pvm use 3.12 --home /custom/path     # Use version from /custom/path
pvm list --home D:\pvm               # List versions in D:\pvm
# The next command without --home uses the default PVM_HOME again
```

### `PVM_HOME` environment variable

```powershell
# Windows (PowerShell) - set permanently
[Environment]::SetEnvironmentVariable("PVM_HOME", "D:\pvm", "User")

# Windows (PowerShell) - set for current session only
$env:PVM_HOME = "D:\pvm"
```

```bash
# Linux/macOS - add to your shell profile (~/.bashrc or ~/.zshrc)
export PVM_HOME="/custom/path/.pvm"
```

### Directory Structure

```
$PVM_HOME/
├── versions/      # Installed Python versions
├── shims/         # nvm-style shim scripts (python.cmd, pip.cmd, etc.)
├── current        # Currently active version
└── settings.json  # Configuration (mirrors, etc.)
```

### Mirror Configuration

Use the `config` command to quickly configure mirrors:

```bash
# Use Tsinghua mirror (recommended for China)
pvm config tsinghua

# Use Huawei Cloud mirror
pvm config huawei

# Use Aliyun mirror
pvm config aliyun

# Use official python.org
pvm config default

# Show current config
pvm config
```

Available presets:
- `tsinghua` / `qinghua` - Tsinghua University
- `huawei` - Huawei Cloud
- `aliyun` - Aliyun
- `default` - python.org (Official)

## Uninstall

### Windows (PowerShell)

```powershell
# Interactive uninstall (with confirmation)
& "$env:PVM_HOME\uninstall.ps1"

# Silent uninstall (no confirmation)
& "$env:PVM_HOME\uninstall.ps1" -Force

# If PVM_HOME is not set, use the default path
& "$env:USERPROFILE\.pvm\uninstall.ps1"
```

### Windows (CMD)

```cmd
:: Interactive uninstall (with confirmation)
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.pvm\uninstall.ps1"

:: Silent uninstall (no confirmation)
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.pvm\uninstall.ps1" -Force

:: If PVM_HOME is not the default path, replace with the actual path
:: e.g.: powershell -ExecutionPolicy Bypass -File "D:\pvm\uninstall.ps1"
```

This will remove:
- All installed Python versions
- pvm configuration and shims
- pvm entries from PATH
- Optionally: pip mirror configuration

### Linux/macOS

```bash
# Interactive uninstall (with confirmation)
bash "$PVM_HOME/uninstall.sh"

# Silent uninstall (no confirmation)
bash "$PVM_HOME/uninstall.sh" --force

# If PVM_HOME is not set, use the default path
bash ~/.pvm/uninstall.sh
```

This will remove:
- All installed Python versions
- pvm configuration and shims
- pvm entries from shell profile (`~/.bashrc`, `~/.zshrc`, etc.)
- Optionally: pip mirror configuration

## License

Apache License 2.0 - see [LICENSE](LICENSE)
