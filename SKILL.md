---
name: blue-server-toolkit
description: >-
  Use when operating remote development servers (Ascend NPU blue-zone servers).
  Covers connection checks, code sync, UT execution, model downloads, log viewing,
  container management, and file sync. For advanced topics (NPU process cleanup,
  A3 chip numbering, vLLM service management, Graph debugging, HDK installation,
  MindIE compilation), see docs/ directory.
  触发方式：提到"服务器""蓝区""SSH""容器""NPU"等远程开发操作场景时。
metadata:
  version: 1.0
---

# Blue Server Toolkit

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

检查 `~/.blue_server_toolkit/config.json`。存在则读取，不存在则向用户
询问基本信息（host、user）并创建。`container` 字段可选。

如果脚本或文档还没安装，从本仓复制到 `~/.blue_server_toolkit/`：

```bash
# 如果 skill 源码仓在本地可用（用户已 clone）
SKILL_DIR="$HOME/.blue_server_toolkit"
mkdir -p "$SKILL_DIR/scripts" "$SKILL_DIR/docs"
cp scripts/*.sh "$SKILL_DIR/scripts/"
cp docs/*.md "$SKILL_DIR/docs/"
echo "✅ scripts/ 和 docs/ 已安装到 $SKILL_DIR"
```

如果源码仓不在本地，从 SKILL.md 中的脚本索引章节提取脚本（首次激活
不再嵌入源码，需从仓中复制）。

## 配置说明

配置文件位于 `~/.blue_server_toolkit/config.json`，结构如下：

```json
{
  "version": "1.0",
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
    "forbidden_commands": ["sudo rm -rf /", "reboot", "pkill -9 -f python"],
    "confirm_required": ["rm -rf", "docker rm", "docker stop", "kill -9", "npu-smi set -t reset"]
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
- **VPN 断连**：长下载场景每 10 分钟发 heartbeat 保活，断连后重连即可，
  nohup 后台任务不受影响
- **响应超时**：服务器命令默认等待不超过 10 秒，超时立刻上报
- **长耗时操作**：编译、拉镜像、下载模型等每 10 秒检查进度日志
- **进度查看**：用 `du -sh` 看目录大小或 `tail -n 5` 看最后几行，
  不要 `cat` 全量日志（会撑爆 AI 上下文窗口）
- **存储布局**：`/root` 分区通常较小，大文件放 `/home`；
  模型缓存可通过软链迁移：`ln -s /home/.cache-root ~/.cache`

## 命令参考

常见操作及命令模板：

### 连接检查
| 操作 | 命令 |
|------|------|
| SSH 心跳 | `ssh -o ConnectTimeout=5 {user}@{host} "echo OK"` |
| NPU 状态 | `bash ~/.blue_server_toolkit/scripts/check-npu.sh {host} {user} [{container}]` |
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
| 覆盖率 | `ssh {user}@{host} "cd {repo_dir} && coverage run -m pytest {test_file} -q && coverage report -m"` |

### 模型下载
| 操作 | 命令 |
|------|------|
| 后台下载 | `ssh {user}@{host} "cd {weights_root} && nohup modelscope download {model_id} --local_dir {target_dir} --max-workers 16 >> {target_dir}/download.log 2>&1 &"` |
| 查看进度 | `ssh {user}@{host} "tail -n 5 {target_dir}/download.log"` |
| 已完成大小 | `ssh {user}@{host} "du -sh {target_dir}/{model_name}"` |

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
| 创建容器 | scp 对应机型脚本到服务器后执行，见下方脚本索引 |
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

## 进阶指南

以下内容需要查阅 `docs/` 目录中的专项文档。每个条目包含触发条件和核心规则，
确保不读 docs 也不会犯致命错误。

### NPU 进程清理与 HBM 释放

标准流程：`npu-smi info` 查 PID → `kill -9 <pid>`（精准 PID，执行前需提醒用户）。
禁止 `pkill -9 -f python`（模糊匹配误杀共享服务器上其他用户进程）。
孤儿 HBM（npu-smi 无进程但显存仍占满）→ `docker restart` 容器。

> 触发场景：HBM 占用异常、服务重启报 Free memory 不足、进程残留
> 详见 `~/.blue_server_toolkit/docs/npu-process-cleanup.md`

### A3 芯片编号

A3 单卡双芯：8 卡 = 16 chip。`ASCEND_RT_VISIBLE_DEVICES` 用全局 chip ID（0-15），
不是 NPU 卡号（0-7）。换算：chip ID = NPU号 × 2 + 芯片序号。
TP4 需要 4 个 chip（2 张 NPU），TP8 需要 8 个 chip（4 张 NPU）。

> 触发场景：配置 ASCEND_RT_VISIBLE_DEVICES、TP 并行度设置、npu-smi 输出解读
> 详见 `~/.blue_server_toolkit/docs/a3-chip-numbering.md`

### vLLM 服务管理

后台启动用 `docker exec -d`，健康检查用 `curl localhost:<port>/v1/models`，
停止服务用 `kill -9 <PID>`（从 npu-smi info 获取）。A3 可同时跑 4 个 TP4 服务
（端口 8000-8003，各用独立 chip 组）。

> 触发场景：vLLM 启动/停止/多服务并行、关键参数配置、并发验证
> 详见 `~/.blue_server_toolkit/docs/vllm-service-guide.md`

### Graph 模式调试

精度/行为异常时，先加 `--enforce-eager` 排除 graph capture 影响：
问题消失 → graph 相关（如 Python property 被静态化）；问题仍在 → 非 graph。
aclgraph 下打印 tensor 用 `torch_npu.print_npugraph_tensor()`。

> 触发场景：精度异常、cudagraph 相关报错、需要观察图模式中间 tensor
> 详见 `~/.blue_server_toolkit/docs/graph-debugging.md`

### 裸机驱动安装

从空白 Atlas 800I A3 装到 `npu-smi info` 可用。关键顺序：先装基础工具（含 tar）
→ 创建 HwHiAiUser → 下载驱动+固件 → 先驱动后固件。

> 触发场景：新服务器初始化、npu-smi 不可用、驱动/固件安装
> 详见 `~/.blue_server_toolkit/docs/hdk-installation.md`

### MindIE-LLM 编译

从源码编译 .whl 包：`bash build.sh 3rd` → 设环境变量 → `pip wheel .` → 安装。
快速迭代：删除旧 .whl 和 build 目录后重新编译 + `--force-reinstall`。

> 触发场景：MindIE-LLM 源码编译、ATB_Models 安装
> 详见 `~/.blue_server_toolkit/docs/mindie-compile.md`

### 服务器配置与存储

`/root` 分区通常较小（S1: 69G），大文件放 `/home`。模型缓存已迁移到
`/home/.cache-root/`（通过软链）。S3/S4 为 A3 机器（16 chip），S1/S2 为 A2（8 NPU）。

> 触发场景：磁盘空间不足、权重路径查询、新服务器入册
> 详见 `~/.blue_server_toolkit/docs/server-configs.md`

## 安全限制

以下命令被禁止或需要确认，定义在 config.json 的 `restrictions` 中：

### 禁止命令（AI 绝不执行）
- `sudo rm -rf /` — 系统级删除
- `reboot` — 重启服务器
- `pkill -9 -f python` — 模糊匹配杀所有 python 进程，误杀风险极高

### 需确认命令（执行前需提醒用户）
- `rm -rf` — 递归删除
- `docker rm` — 删除容器
- `docker stop` — 停止运行中容器
- `kill -9` — NPU 进程清理的标准流程，但需提醒用户
- `npu-smi set -t reset` — 芯片重置，影响该 NPU 上所有进程

## 脚本索引

安装后位于 `~/.blue_server_toolkit/scripts/`。

| 脚本 | 用途 | 用法 |
|------|------|------|
| check-npu.sh | NPU 状态检查 | `bash ~/.blue_server_toolkit/scripts/check-npu.sh <host> <user> [container]` |
| init-config.sh | 初始化配置与安装 | `bash ~/.blue_server_toolkit/scripts/init-config.sh` |
| start-docker-A2.sh | 创建 A2 容器（8 NPU 单芯） | scp 到服务器后 `bash start-docker-A2.sh <image_id> <name>` |
| start-docker-A3.sh | 创建 A3 容器（16 chip 单卡双芯） | scp 到服务器后 `bash start-docker-A3.sh <image_id> <name>` |
| start-docker-A5.sh | 创建 A5 容器（Ascend 950） | scp 到服务器后 `bash start-docker-A5.sh <image_id> <name>` |

## 扩展

要新增文档：加到 `docs/` 目录，在"进阶指南"章节添加索引条目，
然后更新 frontmatter 的 version。
