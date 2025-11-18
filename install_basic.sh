#!/bin/bash
# Miniconda安装路径
MINICONDA_PATH="$HOME/miniconda"
CONDA_EXECUTABLE="$MINICONDA_PATH/bin/conda"

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 系统兼容性检查
function check_system_compatibility() {
    # 检查操作系统
    if [ ! -f /etc/os-release ]; then
        echo "❌ 无法确定操作系统类型，此脚本仅支持基于 Debian/Ubuntu 的 Linux 系统"
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        echo "⚠️  警告: 检测到非 Ubuntu/Debian 系统 ($ID)，脚本可能无法正常工作，继续执行..."
    fi

    # 检查系统架构
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        echo "⚠️  警告: 检测到非 x86_64 架构 ($ARCH)，Miniconda 下载链接可能需要调整"
    fi

    echo "✅ 系统检查通过: $ID $VERSION_ID ($ARCH)"
}

# 确保 conda 被正确初始化
ensure_conda_initialized() {
    # 直接设置 PATH，确保当前会话可用
    export PATH="$MINICONDA_PATH/bin:$PATH"

    # 如果存在 conda.sh，使用它来初始化
    if [ -f "$MINICONDA_PATH/etc/profile.d/conda.sh" ]; then
        source "$MINICONDA_PATH/etc/profile.d/conda.sh"
    fi

    # 使用 conda hook 来初始化
    if [ -f "$CONDA_EXECUTABLE" ]; then
        eval "$("$CONDA_EXECUTABLE" shell.bash hook)" 2>/dev/null || true
    fi
}

# 检查并安装 Conda
function install_conda() {
    if [ -f "$CONDA_EXECUTABLE" ]; then
        echo "Conda 已安装在 $MINICONDA_PATH"
        ensure_conda_initialized
    else
        echo "Conda 未安装，正在安装..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $MINICONDA_PATH
        rm miniconda.sh
        
        # 初始化 conda
        "$CONDA_EXECUTABLE" init
        ensure_conda_initialized

        # 避免重复添加 PATH
        if ! grep -q 'miniconda/bin' ~/.bashrc; then
            echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
        fi
        source ~/.bashrc
    fi
    
    # 验证 conda 是否可用
    if command -v conda &> /dev/null; then
        echo "Conda 安装成功，版本: $(conda --version)"
    else
        echo "Conda 安装可能成功，但无法在当前会话中使用。"
        echo "请在脚本执行完成后，重新登录或运行 'source ~/.bashrc' 来激活 Conda。"
    fi
}

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    local NVM_DIR="$HOME/.nvm"
    local NODE_VERSION="24"

    # 始终通过 nvm 管理 Node.js 与 npm，避免系统包冲突
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        echo "nvm 未安装，正在安装..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    else
        echo "nvm 已存在，位于 $NVM_DIR"
    fi

    # 加载 nvm 环境，以便当前 shell 能够使用
    export NVM_DIR
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck source=/dev/null
        \. "$NVM_DIR/nvm.sh"
    else
        echo "❌ 未找到 nvm.sh，无法继续安装 Node.js"
        return 1
    fi
    if [ -s "$NVM_DIR/bash_completion" ]; then
        # shellcheck source=/dev/null
        \. "$NVM_DIR/bash_completion"
    fi

    if nvm ls "$NODE_VERSION" > /dev/null 2>&1; then
        echo "Node.js $NODE_VERSION 已通过 nvm 安装，切换使用..."
        nvm use "$NODE_VERSION"
    else
        echo "通过 nvm 安装 Node.js $NODE_VERSION..."
        nvm install "$NODE_VERSION"
    fi
    nvm alias default "$NODE_VERSION"

    echo "Node.js 已安装，版本: $(node -v)"
    echo "npm 已安装，版本: $(npm -v)"
}

# 检查并安装 PM2
function install_pm2() {
    # 确保 npm 可用
    if ! command -v npm > /dev/null 2>&1; then
        echo "❌ npm 未找到，无法安装 PM2"
        echo "请先确保 Node.js 和 npm 已正确安装"
        return 1
    fi

    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装，版本: $(pm2 -v)"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g || { echo "❌ PM2 安装失败"; return 1; }
        echo "PM2 安装成功，版本: $(pm2 -v)"
    fi
}

function install_basic() {
    check_system_compatibility
    apt update && apt upgrade -y
    apt install curl sudo git python3-venv zip iptables build-essential wget jq make gcc nano vim tmux -y
    install_conda
    ensure_conda_initialized
    install_nodejs_and_npm
    install_pm2
    echo "基础环境已安装，继续安装 Docker..."
    install_docker
}

# 检查并安装 Docker
function install_docker(){
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done
    
    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

    # 显示 Docker 版本，方便确认安装结果
    if command -v docker > /dev/null 2>&1; then
        echo "Docker 安装完成，版本: $(docker --version)"
    else
        echo "Docker 安装已完成，但当前会话无法直接调用。请重新登录后执行 'docker --version' 进行确认。"
    fi
}

# 安装和编译 Subtensor 节点
function install_subtensor(){
    echo "开始安装 Subtensor 节点..."
    
    # 安装基础包 (根据官方文档)
    echo "安装基础包..."
    sudo apt-get update
    sudo apt install -y build-essential clang curl git make libssl-dev llvm libudev-dev protobuf-compiler pkg-config
    
    # 检查并安装 Rust
    if command -v rustc > /dev/null 2>&1; then
        echo "Rust 已安装，版本: $(rustc --version)"
    else
        echo "安装 Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source ~/.cargo/env
        
        # 安装 Rust 工具链
        rustup default stable
        rustup update
        rustup target add wasm32-unknown-unknown
        rustup toolchain install nightly
        rustup target add --toolchain nightly wasm32-unknown-unknown
    fi
    
    # 确保 Rust 环境可用
    source ~/.cargo/env
    
    # 克隆 Subtensor 仓库
    if [ -d "subtensor" ]; then
        echo "Subtensor 目录已存在，正在更新..."
        cd subtensor || { echo "❌ 无法进入 subtensor 目录"; return 1; }
        git checkout main || { echo "❌ git checkout 失败"; cd ..; return 1; }
        git pull || { echo "❌ git pull 失败"; cd ..; return 1; }
    else
        echo "克隆 Subtensor 仓库..."
        git clone https://github.com/opentensor/subtensor.git || { echo "❌ 克隆仓库失败"; return 1; }
        cd subtensor || { echo "❌ 无法进入 subtensor 目录"; return 1; }
        git checkout main || { echo "❌ git checkout 失败"; cd ..; return 1; }
    fi
    
    # 清理之前的链状态
    if [ -d "/var/lib/subtensor" ]; then
        echo "检测到已存在的 Subtensor 链状态目录，正在清理..."
        sudo rm -rf /var/lib/subtensor
    fi
    
    # 编译 Subtensor
    echo "开始编译 Subtensor (这可能需要一些时间)..."
    cargo build -p node-subtensor --profile=production --features=metadata-hash
    
    if [ $? -eq 0 ]; then
        echo "✅ Subtensor 编译成功！"
        echo "编译后的二进制文件位于: $(pwd)/target/production/node-subtensor"
        echo "您可以使用以下命令运行节点:"
        echo "  - Lite 节点 (主网): ./target/production/node-subtensor --chain ./chainspecs/raw_spec_finney.json --base-path /var/lib/subtensor --sync=warp ..."
        echo "  - Archive 节点 (主网): ./target/production/node-subtensor --chain ./chainspecs/raw_spec_finney.json --base-path /var/lib/subtensor --sync=full --pruning archive ..."
        echo "  - 详细运行说明请参考: https://docs.learnbittensor.org/subtensor-nodes/using-source"
    else
        echo "❌ Subtensor 编译失败，请检查错误信息"
        exit 1
    fi
    
    cd ..
}

# 一键创建并配置 Conda 环境（try）
function install_conda_env_try(){
    echo "开始创建并配置 Conda 环境: try"

    # 确保 Conda 已安装并可用
    install_conda
    ensure_conda_initialized
    if [ -f "$MINICONDA_PATH/etc/profile.d/conda.sh" ]; then
        source "$MINICONDA_PATH/etc/profile.d/conda.sh"
    fi
    eval "$("$CONDA_EXECUTABLE" shell.bash hook)"

    # 处理 Anaconda ToS（非交互环境需要先接受）
    # 参考错误提示：CondaToSNonInteractiveError
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main >/dev/null 2>&1 || true
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r >/dev/null 2>&1 || true

    # 创建环境（若不存在）
    if conda env list | awk '{print $1}' | grep -qx "try"; then
        echo "Conda 环境 try 已存在，跳过创建"
    else
        echo "创建 Conda 环境 try（python=3.12）..."
        if ! conda create -n try -y python=3.12; then
            echo "首次创建环境失败，尝试移除需 ToS 的渠道并使用 conda-forge 重试..."
            # 回退方案：移除 anaconda 官方渠道，改用 conda-forge
            conda config --remove channels https://repo.anaconda.com/pkgs/main >/dev/null 2>&1 || true
            conda config --remove channels https://repo.anaconda.com/pkgs/r >/dev/null 2>&1 || true
            conda config --add channels conda-forge >/dev/null 2>&1 || true
            conda config --set channel_priority flexible >/dev/null 2>&1 || true
            conda create -n try -y -c conda-forge python=3.12 || { echo "❌ 创建 Conda 环境 try 仍然失败，请手动检查 conda 渠道与 ToS 状态。"; return 1; }
        fi
    fi

    # 激活环境（供用户后续使用）；安装时使用显式 python 路径以避免激活失败导致装到 base
    conda activate try || true
    ENV_PREFIX="$MINICONDA_PATH/envs/try"
    ENV_PY="$ENV_PREFIX/bin/python"
    if [ ! -x "$ENV_PY" ]; then
        echo "❌ 未找到环境 Python: $ENV_PY"
        return 1
    fi

    # 安装依赖
    "$ENV_PY" -m pip install --upgrade pip setuptools wheel
    "$ENV_PY" -m pip install bittensor
    "$ENV_PY" -m pip install bittensor-cli
    "$ENV_PY" -m pip install pytz
    "$ENV_PY" -m pip install redis
    "$ENV_PY" -m pip install "git+https://github.com/rayonlabs/fiber.git@2.5.0"
    "$ENV_PY" -m pip uninstall -y async-substrate-interface || true
    "$ENV_PY" -m pip install -U async-substrate-interface

    # 简要校验
    "$ENV_PY" -c "import sys; print('Python:', sys.version.split()[0])" || true
    "$ENV_PY" - <<'PY'
try:
    import bittensor as bt
    print('bittensor ok')
except Exception as e:
    print('bittensor 校验跳过/失败:', e)
PY

    echo "✅ Conda 环境 try 配置完成。使用: 'source $MINICONDA_PATH/etc/profile.d/conda.sh && conda activate try'"
}

# 主菜单
function main_menu() {
    clear
    echo "=========================Linux基础环境安装======================================="
    echo "请选择要执行的操作:"
    echo "1. 安装基础环境"
    echo "2. 安装docker"
    echo "3. 安装和编译Subtensor节点"
    echo "4. 一键安装Conda环境(try)并配置bittensor"
    read -p "请输入选项（1-4）: " OPTION
    case $OPTION in
    1) install_basic ;;
    2) install_docker ;;
    3) install_subtensor ;;
    4) install_conda_env_try ;;
    *) echo "无效选项。" ;;
    esac
}

# 显示主菜单
main_menu
