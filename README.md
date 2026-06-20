# pvm - Python Version Manager

A simple, cross-platform Python version manager inspired by [nvm](https://github.com/nvm-sh/nvm).

**[English Documentation](README_EN.md)** | **[中文文档](README_ZH.md)**

---

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

## License

Apache License 2.0 - see [LICENSE](LICENSE)
