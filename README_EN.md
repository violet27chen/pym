# pvm - Python Version Manager

[Back to README](README.md) | **[中文文档](README_ZH.md)**

---

**pvm** is a simple, cross-platform Python version manager inspired by [nvm](https://github.com/nvm-sh/nvm). It allows you to easily install, switch between, and manage multiple Python versions on your system.

## Features

- Install multiple Python versions side by side
- Switch between Python versions with a single command
- Partial version matching (e.g. `pvm install 3.13` auto-resolves to `3.13.2`)
- nvm-style shim mechanism for instant version switching
- Uninstall Python versions you no longer need
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

```bash
# List installed Python versions
pvm list

# List available Python versions for download
pvm list available

# Install a specific Python version (full version)
pvm install 3.12.4

# Install with partial version (auto-resolves to latest matching version)
pvm install 3.13      # -> installs 3.13.2 (latest 3.13.x)
pvm install 3         # -> installs 3.13.2 (latest 3.x)

# Use a specific Python version
pvm use 3.12.4

# Use partial version (auto-resolves to installed matching version)
pvm use 3.13          # -> switches to installed 3.13.x

# Show currently active Python version
pvm current

# Uninstall a Python version
pvm uninstall 3.11.9

# Show help
pvm --help
```

## Configuration

pvm stores its data in `~/.pvm` (Unix) or `%USERPROFILE%\.pvm` (Windows).

You can customize the data directory by setting the `PVM_HOME` environment variable:

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
powershell -ExecutionPolicy Bypass -File uninstall.ps1

# Silent uninstall (no confirmation)
powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Force
```

This will remove:
- All installed Python versions
- pvm configuration and shims
- pvm entries from PATH
- Optionally: pip mirror configuration

### Linux/macOS

```bash
# Interactive uninstall (with confirmation)
bash uninstall.sh

# Silent uninstall (no confirmation)
bash uninstall.sh --force
```

This will remove:
- All installed Python versions
- pvm configuration and shims
- pvm entries from shell profile (`~/.bashrc`, `~/.zshrc`, etc.)
- Optionally: pip mirror configuration

## License

Apache License 2.0 - see [LICENSE](LICENSE)
