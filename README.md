# common_install

新服务器的一键安装与配置脚本（Ubuntu / Debian，需要 root）。

```bash
wget -O install_basic.sh https://raw.githubusercontent.com/AIChainSquad/common_install/refs/heads/main/install_basic.sh && chmod +x install_basic.sh && ./install_basic.sh
```

运行后按菜单选择，每次运行只执行一项。

## 菜单

| 分组 | 编号 | 内容 |
|---|---|---|
| 基础环境 | 1 | 常用工具 + Conda + uv + Node.js + PM2 + Docker |
| 基础环境 | 2 | 仅安装 Docker |
| Subtensor 节点 | 3 | 从官方仓库 main 分支克隆并编译节点 |
| Bittensor Python 环境 | 4 | 创建 Conda 环境 `try` 并安装 bittensor 等依赖 |
| 节点服务器配置 | 5 | 系统配置：chrony 对时、文件句柄上限、CPU 调频固定为 performance |
| 节点服务器配置 | 6 | 防火墙：默认拒绝入站，放行 SSH 和 P2P(30333)；RPC(9944)、gRPC(50051)、监控(9615) 只对输入的 IP 开放 |

## 说明

- 第 5 项和第 6 项互相独立。第 5 项不会改动防火墙。
- 第 6 项启用前会列出规则，输入 `yes` 才生效；重复执行可以追加允许的 IP。启用后先另开一个终端确认还能 SSH 登录，再关闭当前会话。
- 第 3 项如果发现 `/var/lib/subtensor` 已存在，会先询问是否删除，不会直接删。
- 版本号、端口、句柄上限等集中在脚本开头的"配置项"里。

## 常见用法

- 只跑节点的服务器：先 5，再 6。
- 开发或跑程序的服务器：1，需要 bittensor 环境再跑 4。
