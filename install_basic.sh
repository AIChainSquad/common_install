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

# 确保 conda 被正确初始化
ensure_conda_initialized() {
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
    if [ -f "$CONDA_EXECUTABLE" ]; then
        eval "$("$CONDA_EXECUTABLE" shell.bash hook)"
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
        
        echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
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
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装，版本: $(node -v)"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs git
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装，版本: $(npm -v)"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装，版本: $(pm2 -v)"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

function install_basic() {
    apt update && apt upgrade -y
    apt install curl sudo git python3-venv zip iptables build-essential wget jq make gcc nano npm vim tmux -y
    install_conda
    ensure_conda_initialized
    install_nodejs_and_npm
    install_pm2
}

# 检查并安装 Docker
function install_docker(){
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
    
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
        cd subtensor
        git checkout main
        git pull
    else
        echo "克隆 Subtensor 仓库..."
        git clone https://github.com/opentensor/subtensor.git
        cd subtensor
        git checkout main
    fi
    
    # 清理之前的链状态
    echo "清理之前的链状态..."
    sudo rm -rf /var/lib/subtensor
    
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

# 主菜单
function main_menu() {
    clear
    echo "=========================Linux基础环境安装======================================="
    echo "请选择要执行的操作:"
    echo "1. 安装基础环境"
    echo "2. 安装docker"
    echo "3. 安装和编译Subtensor节点"
    read -p "请输入选项（1-3）: " OPTION
    case $OPTION in
    1) install_basic ;;
    2) install_docker ;;
    3) install_subtensor ;;
    *) echo "无效选项。" ;;
    esac
}

# 显示主菜单
main_menu
