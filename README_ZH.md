# pvm - Python 版本管理器

[**English**](README.md)

---

**pvm** 是一个简单的跨平台 Python 版本管理工具，灵感来自 [nvm](https://github.com/nvm-sh/nvm)。它可以让你轻松安装、切换和管理系统上的多个 Python 版本。

## 特性

- **动态版本列表** - 从 python.org 自动获取可用版本（无需手动更新）
- **预编译二进制** - Linux/macOS 使用 python-build-standalone 预编译包（无需 gcc/make）
- 并行安装多个 Python 版本
- 一条命令切换 Python 版本
- 版本号模糊匹配（例如 `pvm install 3.13` 自动解析为最新 3.13.x）
- nvm 风格的 shim 机制，实现即时版本切换
- 卸载不再需要的 Python 版本
- **虚拟环境管理** (`pvm venv`)
- **包管理** (`pvm pip`)
- **项目管理** (`pvm init`、`pvm add`、`pvm run`)
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

### 版本管理

```bash
# 列出已安装的 Python 版本
pvm list

# 列出可下载的 Python 版本（从 python.org 动态获取）
pvm list available

# 安装指定版本的 Python（完整版本号）
pvm install 3.12.4

# 使用部分版本号安装（自动解析为最新匹配版本）
pvm install 3.13      # -> 安装最新 3.13.x
pvm install 3         # -> 安装最新 3.x

# 强制从源码编译（跳过预编译二进制）
pvm install 3.12.4 --source

# 切换到指定版本
pvm use 3.12.4

# 使用部分版本号切换（自动解析为已安装的最新匹配版本）
pvm use 3.13          # -> 切换到已安装的 3.13.x

# 显示当前使用的版本
pvm current

# 卸载指定版本
pvm uninstall 3.11.9
```

### 虚拟环境管理

```bash
# 创建虚拟环境
pvm venv myenv

# 列出所有虚拟环境
pvm venv list

# 显示激活命令
pvm venv activate myenv

# 删除虚拟环境
pvm venv remove myenv
```

### 包管理

```bash
# 安装包
pvm pip install requests

# 安装指定版本
pvm pip install "django>=4.0"

# 卸载包
pvm pip uninstall requests

# 列出已安装的包
pvm pip list

# 升级包
pvm pip upgrade requests
```

### 项目管理

```bash
# 初始化新项目（创建 pyproject.toml + .pvm-venv）
pvm init

# 添加依赖
pvm add requests

# 移除依赖
pvm remove requests

# 在项目虚拟环境中运行命令
pvm run python main.py
pvm run pytest
```

## 配置

pvm 默认将数据存储在 `~/.pvm` (Unix) 或 `%USERPROFILE%\.pvm` (Windows)。

首次使用时，pvm 会提示你选择数据存储目录。按 Enter 接受默认路径，或输入自定义路径。选择会保存到 `~/.pvmhome`，后续使用不再提示。

还可以通过以下方式自定义数据目录：

### `--home` 参数（仅当次命令生效）

仅对当前命令生效，不会影响后续命令。目录不存在时会自动创建。

```bash
pvm install 3.12 --home D:\pvm       # 安装到 D:\pvm（不存在则自动创建）
pvm use 3.12 --home /custom/path     # 从 /custom/path 切换版本
pvm list --home D:\pvm               # 列出 D:\pvm 中的版本
# 下一条不带 --home 的命令恢复使用默认 PVM_HOME
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
& "$env:PVM_HOME\uninstall.ps1"

# 静默卸载（无确认提示）
& "$env:PVM_HOME\uninstall.ps1" -Force

# 如果未设置 PVM_HOME，使用默认路径
& "$env:USERPROFILE\.pvm\uninstall.ps1"
```

### Windows (CMD)

```cmd
:: 交互式卸载（有确认提示）
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.pvm\uninstall.ps1"

:: 静默卸载（无确认提示）
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.pvm\uninstall.ps1" -Force

:: 如果 PVM_HOME 不是默认路径，请替换为实际路径
:: 例如：powershell -ExecutionPolicy Bypass -File "D:\pvm\uninstall.ps1"
```

将移除以下内容：
- 所有已安装的 Python 版本
- pvm 配置和 shim 文件
- PATH 中的 pvm 相关条目
- 可选：pip 镜像配置

### Linux/macOS

```bash
# 交互式卸载（有确认提示）
bash "$PVM_HOME/uninstall.sh"

# 静默卸载（无确认提示）
bash "$PVM_HOME/uninstall.sh" --force

# 如果未设置 PVM_HOME，使用默认路径
bash ~/.pvm/uninstall.sh
```

将移除以下内容：
- 所有已安装的 Python 版本
- pvm 配置和 shim 文件
- Shell 配置文件中的 pvm 相关条目（`~/.bashrc`、`~/.zshrc` 等）
- 可选：pip 镜像配置

## 许可证

Apache License 2.0 - 详见 [LICENSE](LICENSE)
