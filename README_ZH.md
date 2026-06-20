# pvm - Python 版本管理器

[**English**](README_EN.md) | [返回 README](README.md)

---

**pvm** 是一个简单的跨平台 Python 版本管理工具，灵感来自 [nvm](https://github.com/nvm-sh/nvm)。它可以让你轻松安装、切换和管理系统上的多个 Python 版本。

## 特性

- 并行安装多个 Python 版本
- 一条命令切换 Python 版本
- 版本号模糊匹配（例如 `pvm install 3.13` 自动解析为 `3.13.2`）
- nvm 风格的 shim 机制，实现即时版本切换
- 卸载不再需要的 Python 版本
- 支持 Windows (PowerShell/CMD)
- 支持 Linux/macOS (Bash)
- 支持国内镜像加速下载

## 安装

### Windows (PowerShell)

```powershell
# 标准安装（GitHub）
irm https://raw.githubusercontent.com/violet27chen/pym/main/install.ps1 | iex

# CDN 加速安装（全过程使用 jsDelivr CDN）
$env:PVM_CDN=1; irm https://cdn.jsdelivr.net/gh/violet27chen/pym@main/install.ps1 | iex
```

或手动安装：

```powershell
git clone https://github.com/violet27chen/pym.git
cd pym
.\install.ps1
```

### Windows (CMD)

安装完成后，可以直接在 CMD 中使用 `pvm` 命令：

```cmd
pvm --help
pvm list available
pvm install 3.12.4
```

### Linux/macOS

```bash
# 标准安装（GitHub）
curl -fsSL https://raw.githubusercontent.com/violet27chen/pym/main/install.sh | bash

# CDN 加速安装（全过程使用 jsDelivr CDN）
PVM_CDN=1 curl -fsSL https://cdn.jsdelivr.net/gh/violet27chen/pym@main/install.sh | bash
```

或手动安装：

```bash
git clone https://github.com/violet27chen/pym.git
cd pym
./install.sh
```

> **CDN 加速说明**：使用 `PVM_CDN=1` 或通过 `iex`/`curl | bash` 管道安装时，安装器会自动优先使用 jsDelivr CDN 下载**所有**文件（安装脚本、pvm 核心等），确保整个安装过程都被加速。

## 使用方法

```bash
# 列出已安装的 Python 版本
pvm list

# 列出可下载的 Python 版本
pvm list available

# 安装指定版本的 Python（完整版本号）
pvm install 3.12.4

# 使用部分版本号安装（自动解析为最新匹配版本）
pvm install 3.13      # -> 安装 3.13.2（最新 3.13.x）
pvm install 3         # -> 安装 3.13.2（最新 3.x）

# 切换到指定版本
pvm use 3.12.4

# 使用部分版本号切换（自动解析为已安装的最新匹配版本）
pvm use 3.13          # -> 切换到已安装的 3.13.x

# 显示当前使用的版本
pvm current

# 卸载指定版本
pvm uninstall 3.11.9

# 显示帮助
pvm --help
```

## 配置

pvm 默认将数据存储在 `~/.pvm` (Unix) 或 `%USERPROFILE%\.pvm` (Windows)。

首次使用时，pvm 会提示你选择数据存储目录。按 Enter 接受默认路径，或输入自定义路径。选择会保存到 `~/.pvmhome`，后续使用不再提示。

还可以通过以下方式自定义数据目录：

### `--home` 参数（单次命令覆盖）

```bash
pvm install 3.12 --home D:\pvm
pvm use 3.12 --home /custom/path/.pvm
```

### `PVM_HOME` 环境变量

```powershell
# Windows (PowerShell) - 永久设置
[Environment]::SetEnvironmentVariable("PVM_HOME", "D:\pvm", "User")

# Windows (PowerShell) - 仅当前会话
$env:PVM_HOME = "D:\pvm"
```

```bash
# Linux/macOS - 添加到 shell 配置文件（~/.bashrc 或 ~/.zshrc）
export PVM_HOME="/custom/path/.pvm"
```

### 目录结构

```
$PVM_HOME/
├── versions/      # 已安装的 Python 版本
├── shims/         # nvm 风格的 shim 脚本（python.cmd、pip.cmd 等）
├── current        # 当前激活的版本
└── settings.json  # 配置文件（镜像源等）
```

### 镜像配置

使用 `config` 命令快速配置镜像源：

```bash
# 使用清华源（推荐）
pvm config tsinghua

# 使用华为云镜像
pvm config huawei

# 使用阿里云镜像
pvm config aliyun

# 使用官方源
pvm config default

# 查看当前配置
pvm config
```

可用预设：
- `tsinghua` / `qinghua` - 清华大学
- `huawei` - 华为云
- `aliyun` - 阿里云
- `default` - python.org（官方）

## 卸载

### Windows (PowerShell)

```powershell
# 交互式卸载（有确认提示）
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.pvm\uninstall.ps1"

# 静默卸载（无确认提示）
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.pvm\uninstall.ps1" -Force
```

将移除以下内容：
- 所有已安装的 Python 版本
- pvm 配置和 shim 文件
- PATH 中的 pvm 相关条目
- 可选：pip 镜像配置

### Linux/macOS

```bash
# 交互式卸载（有确认提示）
bash ~/.pvm/uninstall.sh

# 静默卸载（无确认提示）
bash ~/.pvm/uninstall.sh --force
```

将移除以下内容：
- 所有已安装的 Python 版本
- pvm 配置和 shim 文件
- Shell 配置文件中的 pvm 相关条目（`~/.bashrc`、`~/.zshrc` 等）
- 可选：pip 镜像配置

## 许可证

Apache License 2.0 - 详见 [LICENSE](LICENSE)
