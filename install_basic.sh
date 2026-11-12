#!/bin/bash
# ============================================================================
# Linux 服务器安装与配置脚本（Ubuntu / Debian，需要 root）
#
# 用法：bash install_basic.sh，然后按菜单选择。每次运行只执行一项。
#
# 文件结构（按功能分组，菜单编号与分组一一对应）：
#   〇、配置项                 版本号、端口等，要改先看这里
#   一、通用工具               root 检查、系统检查
#   二、基础环境               菜单 1、2   常用工具、Conda、Node.js、PM2、Docker
#   三、Subtensor 节点         菜单 3      从官方仓库编译节点
#   四、Bittensor Python 环境  菜单 4      Conda 环境 try + bittensor
#   五、节点服务器配置         菜单 5、6   系统配置、防火墙（两项互相独立）
#   六、主菜单
# ============================================================================


# ============================================================================
# 〇、配置项
# ============================================================================

# Conda
MINICONDA_PATH="$HOME/miniconda"
CONDA_EXECUTABLE="$MINICONDA_PATH/bin/conda"

# Node.js
NVM_VERSION="v0.40.3"
NODE_VERSION="24"

# 节点服务器
NOFILE_LIMIT=1048576                 # 文件句柄上限
P2P_PORT=30333                       # 节点 P2P 端口：防火墙对所有人放行
PRIVATE_PORTS="9944 50051 9615"      # RPC、gRPC、Prometheus：防火墙只对指定 IP 放行


# ============================================================================
# 一、通用工具
# ============================================================================

# 检查是否以 root 用户运行
function require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "此脚本需要以root用户权限运行。"
        echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
        exit 1
    fi
}

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


# ============================================================================
# 二、基础环境（菜单 1、2）
# ============================================================================

# ---- Conda ----

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

# ---- Node.js / PM2 ----

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    local NVM_DIR="$HOME/.nvm"

    # 始终通过 nvm 管理 Node.js 与 npm，避免系统包冲突
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        echo "nvm 未安装，正在安装..."
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
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

# ---- Docker（菜单 2）----

# 检查并安装 Docker
function install_docker(){
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    # Docker 的软件源按发行版区分，Debian 不能用 ubuntu 的源
    local DOCKER_DISTRO
    DOCKER_DISTRO=$(. /etc/os-release && echo "$ID")
    [[ "$DOCKER_DISTRO" == "debian" ]] || DOCKER_DISTRO="ubuntu"
    sudo curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_DISTRO} \
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

# ---- 组合（菜单 1）：常用工具 + Conda + Node.js + PM2 + Docker ----

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


# ============================================================================
# 三、Subtensor 节点（菜单 3）
# ============================================================================

# 安装和编译 Subtensor 节点（官方仓库 main 分支，在当前目录下克隆）
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
        echo "⚠️  检测到已存在的 Subtensor 链状态目录 /var/lib/subtensor（$(du -sh /var/lib/subtensor 2>/dev/null | cut -f1)）"
        echo "    删除后节点需要重新同步。如果有节点正在使用这个目录，不要删除。"
        read -r -p "是否删除？输入 yes 确认，其他任意输入保留: " CONFIRM_RM
        if [ "$CONFIRM_RM" = "yes" ]; then
            sudo rm -rf /var/lib/subtensor
            echo "已删除 /var/lib/subtensor"
        else
            echo "保留 /var/lib/subtensor"
        fi
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


# ============================================================================
# 四、Bittensor Python 环境（菜单 4）
# ============================================================================

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
    # bittensor 11 起是一个包：自带 SDK、btcli 和钱包（依赖 bittensor-core）。
    # 不要再装 bittensor-cli / bittensor-wallet：它们是 10.x 时代的独立包，
    # bittensor-cli 会覆盖掉 bittensor 自带的 btcli 命令。
    "$ENV_PY" -m pip install --upgrade pip setuptools wheel
    "$ENV_PY" -m pip install bittensor==11.3.2
    "$ENV_PY" -m pip install pytz==2026.6
    "$ENV_PY" -m pip install redis==8.1.0
    "$ENV_PY" -m pip install cryptography==50.0.2
    "$ENV_PY" -m pip install coincurve==21.0.0
    "$ENV_PY" -m pip install secp256k1==0.14.0
    "$ENV_PY" -m pip install python-dotenv==1.2.4

    # 简要校验
    "$ENV_PY" -c "import sys; print('Python:', sys.version.split()[0])" || true
    "$ENV_PY" - <<'PY'
try:
    import bittensor as bt
    print('bittensor ok', bt.__version__)
except Exception as e:
    print('bittensor 校验跳过/失败:', e)

for module_name in ("coincurve", "secp256k1"):
    try:
        __import__(module_name)
        print(f"{module_name} ok")
    except Exception as e:
        print(f"{module_name} 校验跳过/失败:", e)
PY

    echo "✅ Conda 环境 try 配置完成。使用: 'source $MINICONDA_PATH/etc/profile.d/conda.sh && conda activate try'"
}


# ============================================================================
# 五、节点服务器配置（菜单 5、6）
#     只做系统层面的配置，不安装也不启动节点。各项都可以重复执行。
#     菜单 5（系统配置）和菜单 6（防火墙）互相独立，互不调用。
# ============================================================================

# ---- 对时 ----
# 多台机器之间比较毫秒级时间戳需要 chrony（安装后会替代 systemd-timesyncd）
function setup_time_sync() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y chrony || { echo "❌ chrony 安装失败"; return 1; }
    systemctl enable --now chrony >/dev/null 2>&1 || echo "⚠️  chrony 启动失败，请手动检查: systemctl status chrony"
    echo "✅ 对时: $(chronyc tracking 2>/dev/null | grep 'System time' | sed 's/^ *//')"
}

# ---- 文件句柄上限 ----
# 节点有上千个 P2P 连接，再加数据库文件（root 要单独写，* 不包含 root）
function setup_nofile_limit() {
    printf '%s\n' \
        "*    soft nofile $NOFILE_LIMIT" \
        "*    hard nofile $NOFILE_LIMIT" \
        "root soft nofile $NOFILE_LIMIT" \
        "root hard nofile $NOFILE_LIMIT" > /etc/security/limits.d/90-node.conf
    echo "✅ 文件句柄上限已写入 /etc/security/limits.d/90-node.conf（重新登录后生效；systemd 服务要另外设置 LimitNOFILE）"
}

# ---- CPU 调频 ----
# 固定为 performance，避免低负载时降频；通过 systemd 服务在开机时自动设置
function setup_cpu_governor() {
    if ! ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1; then
        echo "⚠️  这台机器没有暴露 CPU 调频接口，跳过（可能由 BIOS 控制）"
        return 0
    fi

    # systemd 会展开 ExecStart 里的 $变量，所以 shell 变量写成 $$f
    printf '%s\n' \
        '[Unit]' \
        'Description=Set CPU frequency governor to performance' \
        'After=multi-user.target' \
        '' \
        '[Service]' \
        'Type=oneshot' \
        "ExecStart=/bin/sh -c 'for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > \"\$\$f\"; done'" \
        'RemainAfterExit=yes' \
        '' \
        '[Install]' \
        'WantedBy=multi-user.target' > /etc/systemd/system/cpu-performance.service
    systemctl daemon-reload
    systemctl enable --now cpu-performance.service >/dev/null 2>&1
    echo "✅ CPU 调频: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)（开机自动设置）"
}

# ---- 组合（菜单 5）：常用工具 + 对时 + 文件句柄 + CPU 调频 ----
# 不动防火墙
function setup_node_server() {
    echo "开始配置节点服务器..."

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget git tmux jq || { echo "❌ 基础包安装失败"; return 1; }

    setup_time_sync
    setup_nofile_limit
    setup_cpu_governor

    echo "✅ 节点服务器基础配置完成（未改动防火墙，需要的话单独执行菜单第 6 项）。"
}

# ---- 防火墙（菜单 6）----
# 默认拒绝入站，只放行 SSH 和 P2P；RPC/gRPC/监控端口只对指定 IP 开放。
# 启用前会列出规则并要求确认；重复执行可以追加 IP。
function setup_firewall() {
    local SSH_PORTS PORT IP ALLOW_IPS VALID_IPS="" CONFIRM_FW

    if ! command -v ufw > /dev/null 2>&1; then
        echo "ufw 未安装，正在安装..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y ufw || { echo "❌ ufw 安装失败"; return 1; }
    fi

    SSH_PORTS=$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | tr '\n' ' ')
    # 当前这次 SSH 登录实际用的端口也放行，避免把自己关在外面
    if [ -n "$SSH_CONNECTION" ]; then SSH_PORTS="$SSH_PORTS ${SSH_CONNECTION##* }"; fi
    SSH_PORTS=$(echo "${SSH_PORTS:-22}" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')
    [ -n "$SSH_PORTS" ] || SSH_PORTS="22"

    echo ""
    echo "防火墙规则: 默认拒绝入站；对所有人开放 SSH($SSH_PORTS) 和 P2P($P2P_PORT)。"
    echo "RPC/gRPC/监控端口($PRIVATE_PORTS) 默认不对外开放，本机访问不受影响。"
    read -r -p "允许访问 RPC/gRPC/监控端口的 IP（空格分隔，可带 /掩码；留空表示都不允许）: " ALLOW_IPS
    for IP in $ALLOW_IPS; do
        if [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
            VALID_IPS="$VALID_IPS $IP"
        else
            echo "⚠️  忽略格式不对的地址: $IP"
        fi
    done

    echo "将要应用: 放行 SSH [$SSH_PORTS]、P2P [$P2P_PORT]；允许 [${VALID_IPS:- 无}] 访问 [$PRIVATE_PORTS]"
    if command -v docker > /dev/null 2>&1; then
        echo "⚠️  检测到 Docker：容器通过 -p 映射出去的端口不受 ufw 限制"
    fi
    read -r -p "确认启用防火墙？输入 yes 确认，其他任意输入跳过: " CONFIRM_FW
    if [ "$CONFIRM_FW" != "yes" ]; then
        echo "已跳过防火墙配置。"
    else
        ufw default deny incoming >/dev/null
        ufw default allow outgoing >/dev/null
        for PORT in $SSH_PORTS; do ufw allow "$PORT/tcp" comment 'ssh' >/dev/null; done
        ufw allow "$P2P_PORT/tcp" comment 'subtensor p2p' >/dev/null
        for IP in $VALID_IPS; do
            for PORT in $PRIVATE_PORTS; do
                ufw allow from "$IP" to any port "$PORT" proto tcp comment 'node rpc/grpc/metrics' >/dev/null
            done
        done
        ufw --force enable
        ufw status verbose
        echo "✅ 防火墙已启用。请另开一个终端确认还能 SSH 登录，再关闭当前会话。"
    fi
}


# ============================================================================
# 六、主菜单
# ============================================================================

function main_menu() {
    clear
    echo "===================== Linux 服务器安装与配置 ====================="
    echo ""
    echo "【基础环境】"
    echo "  1. 安装基础环境（常用工具 + Conda + Node.js + PM2 + Docker）"
    echo "  2. 仅安装 Docker"
    echo ""
    echo "【Subtensor 节点】"
    echo "  3. 安装并编译 Subtensor 节点（官方仓库 main 分支）"
    echo ""
    echo "【Bittensor Python 环境】"
    echo "  4. 一键安装 Conda 环境(try) 并配置 bittensor"
    echo ""
    echo "【节点服务器配置】"
    echo "  5. 系统配置（对时、文件句柄、CPU 调频）"
    echo "  6. 防火墙（单独执行，启用前会确认）"
    echo ""
    read -p "请输入选项（1-6）: " OPTION
    case $OPTION in
    1) install_basic ;;
    2) install_docker ;;
    3) install_subtensor ;;
    4) install_conda_env_try ;;
    5) setup_node_server ;;
    6) setup_firewall ;;
    *) echo "无效选项。" ;;
    esac
}

require_root
main_menu
