---
name: blue-server-handler
description: >-
  操作远程开发服务器（蓝区服务器）时使用。提供 SSH 连接检查、代码同步、
  UT 运行、模型下载、日志查看、容器管理等常见操作的模式参考和辅助脚本。
metadata:
  version: 0.9
---

# Blue Server Handler

## Overview

一个远程开发服务器操作参考。提供常见操作的命令模式和辅助脚本。
**配置和脚本是工具，不是规则**——用得上就用，用不上不用。

使用此 skill 的前提是能通过 SSH 访问目标服务器。如果用户还没配好 SSH
key，可以主动帮用户生成密钥对，并告知公钥放在服务器的哪个位置。这不是
必经步骤，但顺滑的首次连接会让后续体验好很多。

**容器包装模式**——部分操作需要进入 Docker 容器执行。需要时在命令外层
套上这个模式：

```
ssh {user}@{host} "docker exec {container} bash -c '{command}'"
```

## First Activation

检查 `~/.blue_server_handler/config.json`。存在则读取，不存在则向用户
询问基本信息（host、user）并创建。`container` 字段可选。

如果脚本还没安装，从下方 Scripts 章节提取到 `~/.blue_server_handler/scripts/`。

## 配置说明

配置文件位于 `~/.blue_server_handler/config.json`，结构如下：

```json
{
  "version": "0.9",
  "servers": [
    {
      "alias": "s1",
      "host": "192.168.1.100",
      "user": "developer",
      "port": 22,
      "container": "dev_container",
      "desc": "主开发服务器"
    }
  ],
  "default_server": "s1",
  "workspaces": {
    "task_root": "/home/developer/Tasks",
    "weights_root": "/home/developer/weights",
    "code_root": "/home/developer/Code"
  },
  "restrictions": {
    "forbidden_commands": ["sudo rm -rf /", "reboot"],
    "confirm_required": ["rm -rf", "docker rm", "kill -9"]
  }
}
```

- `servers[].container` 可选——不设或 null 表示不用容器
- `workspaces` 可选——服务器上的目录约定
- `restrictions` 可选——`forbidden_commands` AI 绝不执行，
  `confirm_required` 需要用户确认后才执行

所有字段都可以随时修改（用户自己改或告诉 AI 代改）。`version` 字段
用来追踪和 SKILL.md 的版本匹配。

## 经验备忘

以下是从实际使用中积累的注意事项。AI 可参考这些信息优化决策，但不要
当作必须遵循的规则——具体情况以用户的实际环境和反馈为准。

- **SSH 连不上**：先问 VPN 是否已连接，再逐层排查 ping → BMC 虚拟控制台
  → sshd_config
- **目录权限**：服务器上的 `/home/{user}/Tasks/` 等目录可能是 root 属主，
  `mkdir -p` 失败时可用 `sudo mkdir -p`
- **大文件传输**：打包（tar/zip）后上传比散传快很多；传输前提醒用户关闭
  PC 休眠防止中断
- **首次登录**：密码含特殊符号时须用英文半角输入法；新账号创建后等 2-3
  分钟再登录；首次登录须改密码

## 命令参考

常见操作及命令模板：

### 连接检查
| 操作 | 命令 |
|------|------|
| SSH 心跳 | `ssh -o ConnectTimeout=5 {user}@{host} "echo OK"` |
| NPU 状态 | `bash ~/.blue_server_handler/scripts/check-npu.sh {host} {user} [{container}]` |
| 磁盘空间 | `ssh {user}@{host} "df -h"` |

### 代码操作
| 操作 | 命令 |
|------|------|
| 创建目录 | `ssh {user}@{host} "mkdir -p {target_dir}"` |
| 克隆仓库 | `ssh {user}@{host} "git clone {repo_url} {target_dir}"` |
| 强制拉取 | `ssh {user}@{host} "cd {repo_dir} && git fetch origin && git reset --hard origin/{branch}"` |
| 切换分支 | `ssh {user}@{host} "cd {repo_dir} && git checkout {branch}"` |
| 查看状态 | `ssh {user}@{host} "cd {repo_dir} && git status"` |

### UT 运行
| 操作 | 命令 |
|------|------|
| 单文件 | `ssh {user}@{host} "cd {repo_dir} && python3 -m pytest {test_file} -v"` |
| 批量文件 | `ssh {user}@{host} "cd {repo_dir} && python3 -m pytest {file1} {file2} -v"` |
| 覆盖率 | `ssh {user}@{host} "cd {repo_dir} && coverage run -m pytest {test_file} -v && coverage report -m"` |

### 模型下载
| 操作 | 命令 |
|------|------|
| 后台下载 | `ssh {user}@{host} "cd {weights_root} && nohup modelscope download {model_id} --max-workers 16 >> download.log 2>&1 &"` |
| 查看进度 | `ssh {user}@{host} "tail -f {weights_root}/download.log"` |
| 已完成大小 | `ssh {user}@{host} "du -sh {weights_root}/{model_name}"` |

### 日志查看
| 操作 | 命令 |
|------|------|
| 查看文件 | `ssh {user}@{host} "cat {log_file}"` |
| 尾部 N 行 | `ssh {user}@{host} "tail -n 100 {log_file}"` |
| 关键字搜索 | `ssh {user}@{host} "grep -n {keyword} {log_file}"` |
| 容器日志 | `ssh {user}@{host} "docker logs {container}"` |

### 容器管理
| 操作 | 命令 |
|------|------|
| 创建容器 | `ssh {user}@{host} "docker run -itd --name {container} --net=host --shm-size=128g --privileged=true -v /data:/data {image} bash -c 'sleep infinity'"` |
| 查看状态 | `ssh {user}@{host} "docker ps -a \| grep {container}"` |
| 启动 | `ssh {user}@{host} "docker start {container}"` |
| 交互式进入 | `ssh -t {user}@{host} "docker exec -it {container} bash"` |
| 执行命令 | `ssh {user}@{host} "docker exec {container} bash -c '{command}'"` |

### 文件同步
| 操作 | 命令 |
|------|------|
| 上传 | `scp {local_path} {user}@{host}:{remote_path}` |
| 下载 | `scp {user}@{host}:{remote_path} {local_path}` |
| 增量同步 | `rsync -avz {local_dir} {user}@{host}:{remote_dir}` |

## 脚本

首次激活时提取到 `~/.blue_server_handler/scripts/`。它们处理特定的
高频操作——用得上就用，用不上直接自己拼命令也行。

### check-npu.sh

```bash
#!/bin/bash
# blue_server_handler - NPU Status Check
# Version: 0.9
# Usage: bash check-npu.sh <host> <user> [container]

HOST=$1
USER=$2
CONTAINER=$3

if [ $# -lt 2 ]; then
  echo "Usage: bash check-npu.sh <host> <user> [container]"
  exit 1
fi

if [ -n "$CONTAINER" ]; then
  ssh "$USER@$HOST" "docker exec $CONTAINER npu-smi info" 2>&1
else
  ssh "$USER@$HOST" "npu-smi info" 2>&1
fi
```

### init-config.sh

```bash
#!/bin/bash
# blue_server_handler - Initialize Configuration
# Version: 0.9
# Usage: bash init-config.sh

CONFIG_DIR="$HOME/.blue_server_handler"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "0.9",
  "servers": [
    {
      "alias": "s1",
      "host": "__your_host__",
      "user": "__your_user__",
      "port": 22,
      "container": null,
      "desc": "主开发服务器"
    }
  ],
  "default_server": "s1"
}
EOF
  echo "Template config created at $CONFIG_FILE. Fill in your server info, or ask AI to help."
else
  echo "Config already exists at $CONFIG_FILE"
fi
```

## 扩展

要新增脚本：加到 `scripts/` 目录，同时在 Scripts 章节嵌入代码块
（内容必须一致），然后更新 frontmatter 的 version。
