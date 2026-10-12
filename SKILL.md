---
name: blue-server-toolkit
description: >-
  Use when operating remote development servers (Ascend NPU blue-zone servers).
  Covers connection checks and stability (SSH multiplexing), code sync, UT execution,
  model downloads, log viewing, container management, and file sync. For advanced
  topics (NPU process cleanup, chip numbering, vLLM service management, PD
  disaggregation bring-up, 950DT fabric identity, Graph debugging, HDK
  installation), see docs/ directory.
  触发方式：提到"服务器""蓝区""SSH""容器""NPU"等远程开发操作场景时。
metadata:
  version: 2.1.0
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
cp scripts/*.sh scripts/*.py "$SKILL_DIR/scripts/" 2>/dev/null
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

## 用户配置与 Skill 本体分离

本仓（公开在 GitHub）只放**通用可复用知识**；用户的**个人环境信息一律放
本地 `~/.blue_server_toolkit/`**，不写入本仓：

| 归属 | 位置 | 内容 |
|------|------|------|
| Skill 本体（git 仓） | 本仓 `SKILL.md` / `docs/` | 命令模板、经验备忘、机型/驱动知识 |
| 用户配置（本地） | `~/.blue_server_toolkit/config.json` | 机器清单（IP/账号/容器）、目录约定、命令限制 |
| 用户笔记（本地） | `~/.blue_server_toolkit/notes/` | 机器档案（磁盘/HBM/共享情况）、权重清单、环境变更历史 |

**红线**：IP、hostname、机器清单、个人路径、任务状态等环境信息禁止写进
本仓。新服务器入册 = 改 `config.json` + 补 `notes/` 档案，**不是**往
`docs/` 写 md。

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
- **容器创建前确认**：执行容器相关操作前，如果上下文中没有明确的镜像 ID
  和容器名，需要向用户询问使用什么镜像、容器名起成什么样。如果用户回复
  "你自己看着办"之类的授权，AI 可自行决定
- **HF-only 权重走 hf-mirror 直连，不用代理**：下权重
  优先 ModelScope；仅 HF 独有的权重才走 HF，且不需要代理隧道——容器内
  `export HF_ENDPOINT=https://hf-mirror.com` 后用 `hf download` 直连即可。
  注意：新版 `hf` CLI 参数是 `--local-dir`（连字符）；宿主机通常没装
  huggingface_hub，在容器里执行。
- **蓝区 pip 先配全局国内源，禁止先试默认源**：pypi.org 直连是长时间挂死
  而非快速报错，"先试一遍默认"每次白等数分钟。容器内装任何包之前先配一次
  `pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/ &&
  pip config set install.trusted-host mirrors.aliyun.com`，之后一切 pip 命令
  （-e 安装、requirements、临时补装小包）自动带源；命令示例里显式写 `-i`
  只是未配全局时的兜底写法。SSH 隧道代理是 git/curl 等小流量的备选，
  不是 pip 的首选。
- **蓝区代理穿透**：蓝区服务器无法直接访问外网 PyPI/docker 等。标准做法
  是用 SSH 反向端口转发，把本地代理（如端口 7897）映射到远端：
  `ssh -R 7897:127.0.0.1:7897 {user}@{host} -f -N`
  建好后在容器内设 `HTTP_PROXY=http://127.0.0.1:7897` 即可走本地代理出网。
  隧道易超时断开，操作前先检查远端端口是否在监听（`ss -tlnp | grep 7897`），
  断了就重建。此方式仅适用于用户本地代理正在运行且能访问目标源；
  适用对象是 git fetch 等小流量，pip 优先走国内镜像源（见上条）。
- **G 区下载三坑（MITM 自签 / NFS 直写卡死 / pkill 自杀）**：仅限 G 区环境
  （深信服 MITM 代理 + NFS 大盘）。Python requests 需关 SSL 校验（pip 能过
  是 trusted-host 所致，不代表没被 MITM）；大文件勿直写 NFS——先下容器本地
  /tmp、循环断点续传、校验字节数后 mv；pkill -f 模式勿与命令行里的路径
  字面量重叠。详见 `~/.blue_server_toolkit/docs/gzone-download.md`
- **SSH 批量短命令间歇超时，用 ControlMaster 复用而非裸重试**：网络抖动窗口只丢
  「新建连接」的 SYN，已建立的长连接不受影响——终端稳、逐命令新建连接的程序
  间歇超时，就是这个差异。`~/.ssh/config` 对目标网段配 `ControlMaster auto` +
  `ControlPersist 8h` + `ServerAliveInterval 30`，首条命令建常驻 master，后续
  ssh/scp/rsync 全复用（单条 ~0.8s → ~0.1s）。维护 `ssh -O check` / `ssh -O exit`；
  master 判死后下条命令自动重拨。详见 `~/.blue_server_toolkit/docs/ssh-connection-stability.md`
- **命令输出重定向到日志文件再看**：长/复杂命令在
  远端执行时，输出重定向到日志文件，然后分段查看（`tail -N`/`grep`）：
  `cmd > <日志路径> 2>&1; echo EXIT=$?` 后再 `tail -40 <日志路径>`。
  日志落点：**用户指定过服务器工作目录的，放该工作目录下**，
  不要丢进 /tmp、~ 等公共位置；未指定工作目录时放 `/tmp/<任务名>/`
  任务子目录（先 `mkdir -p`），与其他任务的日志隔开，不要直接堆在
  /tmp 根下。**不要**用 `| tail -N` 截断 stdout——会丢失错误上下文，
  且管道让 `$?` 失效（pip 失败也显示成功），错误排查全靠猜。
- **一次只做一个动作，不要顺手多做**：缺什么依赖就
  只装什么（如只 `pip install setuptools-rust`），不要"顺手"把相关包全装了
  ——多余动作可能引入网络/版本新失败源，且失败时难以定位。每一步确认
  退出码和结果后再做下一步。
- **rsync 多源会平铺合并**：一条 rsync 命令传多个源目录
  到同一目标时，各源内容**平铺**进目标目录（同名文件互相覆盖，.git 冲突），
  不是各建子目录。每个仓必须单独 rsync 到自己的子目录：
  `rsync -az src1/ host:/dst/src1/ && rsync -az src2/ host:/dst/src2/`。
- **rsync 跨 uid 传代码后容器内必须 chown**：mac 上 rsync
  传过去的文件 owner 是本地 uid（如 501），容器内 git 访问报 `dubious
  ownership`——setuptools_scm（pip -e 装 vllm 时 metadata 失败）、submodule
  fetch（build_aclnn.sh 拉 catlass 失败）全踩。根治：容器内
  `chown -R root:root <code_dir>`（或 `git config --global --add
  safe.directory <repo>` 逐个打补丁，不如 chown 干净）。
- **A3 机型算力判定（560T/752T）**：宿主机一般没装 torch，去任一 vllm 镜像容器
  里跑 `flops-torch.py`（stdin 管道进容器，服务器零落盘，用法见脚本索引）。
  单 die fp16 matmul 峰值：560T 机型实测 ~230-250 TFLOPS；752T 实测 ~297-322
  （阈值 280；752T 侧 2026-08-30 真机标定）。真实压测（数秒、数百瓦），
  die 被占用时勿跑。
- **共享机占用前 wall 声明，动他人容器前逐台记录**：长时间占用 NPU 前先
  `wall` 广播声明（任务 + 联系人）；确需停他人容器时逐台记录容器名/镜像/
  状态留档，只 stop 不 rm，测完按记录恢复。
- **压测类任务每轮唯一 run-id，日志 open('xb') 禁覆盖**：结果目录带唯一
  run-id，日志文件用 `open('xb')`（exclusive create）创建，已存在即报错；
  失败换新目录重跑，不覆盖旧证据。
- **同日多 flavor 同名系镜像以镜像 ID 为准**：同一台机常并存多个名字相近的
  同日构建镜像（不同 OS 底座/flavor），创建容器只认完整镜像 ID，勿按名字
  短前缀猜。

## 命令参考

常见操作及命令模板：

### 连接检查
| 操作 | 命令 |
|------|------|
| SSH 心跳 | `ssh -o ConnectTimeout=5 {user}@{host} "echo OK"` |
| SSH master 状态 | `ssh -O check {user}@{host}`（需已配 ControlMaster，见 docs/ssh-connection-stability.md） |
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
| ModelScope 后台下载（优先） | `ssh {user}@{host} "cd {weights_root} && nohup modelscope download {model_id} --local_dir {target_dir} --max-workers 16 >> {target_dir}/download.log 2>&1 &"` |
| HF 后台下载（仅 HF 独有权重，免代理） | `ssh {user}@{host} "docker exec {container} bash -c 'export HF_ENDPOINT=https://hf-mirror.com && cd {weights_root} && nohup hf download {model_id} --local-dir {target_dir} --max-workers 16 >> {target_dir}/download.log 2>&1 &'"` |
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
| PID 反查容器 | `bash ~/.blue_server_toolkit/scripts/who.sh {host} {user} {pid}` |

### 文件同步
| 操作 | 命令 |
|------|------|
| 上传 | `scp {local_path} {user}@{host}:{remote_path}` |
| 下载 | `scp {user}@{host}:{remote_path} {local_path}` |
| 增量同步 | `rsync -avz {local_dir} {user}@{host}:{remote_dir}` |

## 常用镜像源

vllm-ascend 镜像常用来源（拉大镜像时优先直连/内网源，**禁止**把大流量导到付费外网代理）：

| 源 | 地址 | 说明 |
|----|------|------|
| 官方 | `quay.io/ascend/vllm-ascend` | 海外源，蓝区直连 ~0.2MB/s，不推荐 |
| 南大镜像 | `quay.nju.edu.cn/ascend/vllm-ascend` | 国内镜像，直连 ~18MB/s，**蓝区首选** |
| 华为内网 | `cr.rnd.huawei.com/images/vllm-ascend` | 速度最快（未验证）；需 rnd 内网 DNS/路由，蓝区当前 VPN 不可达 |

```bash
# 南大镜像拉取 + 重打官方 tag
docker pull quay.nju.edu.cn/ascend/vllm-ascend:nightly-main-a3
docker tag quay.nju.edu.cn/ascend/vllm-ascend:nightly-main-a3 quay.io/ascend/vllm-ascend:nightly-main-a3
```

> 注意：docker daemon 若配了 systemd 代理（`/etc/systemd/system/docker.service.d/proxy.conf`），
> 所有 registry 请求都会走代理；改用直连内网源时需要临时调整 NO_PROXY 并重启 dockerd
> （`live-restore=true` 时容器不中断）。详见 `docs/image-mirrors.md`。

## 进阶指南

以下内容需要查阅 `docs/` 目录中的专项文档。每个条目包含触发条件和核心规则，
确保不读 docs 也不会犯致命错误。

### SSH 连接稳定性（ControlMaster 复用）

批量短命令/AI 代理场景的 SSH 间歇超时，根因是抖动窗口丢「新建连接」的 SYN——
用 ControlMaster 把所有命令复用到一条常驻连接上（纯客户端配置，服务器零改动）。
配置模板、master 维护（`-O check`/`-O exit`）、自动重拨语义、MaxSessions
并发上限注意事项、TCP/sshd 分层排查范式。

> 触发场景：ssh/scp/rsync 间歇超时、批量命令频繁重试、AI 代理逐命令建连、网络施工期、终端稳但自动化不稳
> 详见 `~/.blue_server_toolkit/docs/ssh-connection-stability.md`

### NPU 进程清理与 HBM 释放

标准流程：`npu-smi info` 查 PID → `kill -9 <pid>`（精准 PID，执行前需提醒用户）。
禁止 `pkill -9 -f python`（模糊匹配误杀共享服务器上其他用户进程）。
孤儿 HBM（npu-smi 无进程但显存仍占满）→ `docker stop` 容器（stop 后驱动整体回收；
`restart` 立即拉起不给回收窗口，勿用）。
判机空闲须在**宿主机**跑 npu-smi 看 HBM 数值（容器内他人进程名列可能空白，"无进程名"≠空闲），辅以 `ss -tlnp` 查端口；`docker ps` 只用于占用归因和接管清点，不作空闲判据。
清点残留进程用大小写不敏感 grep（`VLLM::` 大写前缀会被 `grep "vllm"` 漏掉），以宿主机 PID 为准。

> 触发场景：HBM 占用异常、服务重启报 Free memory 不足、进程残留、上机前判断机器是否空闲
> 详见 `~/.blue_server_toolkit/docs/npu-process-cleanup.md`

### A3 芯片编号

A3 单卡双芯：8 卡 = 16 chip。`ASCEND_RT_VISIBLE_DEVICES` 用全局 chip ID（0-15），
不是 NPU 卡号（0-7）。换算：chip ID = NPU号 × 2 + 芯片序号。
TP4 需要 4 个 chip（2 张 NPU），TP8 需要 8 个 chip（4 张 NPU）。
950DT（A5）单卡单芯：8 卡 = 8 chip，无 ×2 换算——两代机型的对照表见同文档末节，
混用时先确认机型再套换算。

> 触发场景：配置 ASCEND_RT_VISIBLE_DEVICES、TP 并行度设置、npu-smi 输出解读
> 详见 `~/.blue_server_toolkit/docs/a3-chip-numbering.md`

### NPU 跨机互联检查

多机 PD/MC2 数据面走 NPU RDMA，主机互 ping 通不算数。检查：`hccn_tool -i 0 -vnic -g`
取 IP → `hccn_tool -i 0 -hccs_ping -g address <对端IP>` 实测（A2 用 `-ping`）；TLS 各机一致。
**坑：`-link -g` 报 DOWN 在部分环境失真，勿据此判物理不通；hccs_ping 只覆盖 NPU 网，PD 的 dp-rpc/proxy 走主机 TCP——跨机前每台 `systemctl is-active firewalld`，active 必停（默认 INPUT 只放 22，跨机 TCP 全被 reject；firewalld 状态会漂移，他人操作/重启即可改变，每次跨机前重查，勿沿用历史结论）。**
**坑（2026-10-10 A3 SuperPoD 实测）：判通必须看 `N packets transmitted, N received` 且 recv time 非 0——打不到的目标照样收尾打印 "Cmd executed successfully!"（真实输出 0 packets + not start to send），grep "success" 全是假阳性；同芯片并发跑 hccn_tool 会让 ping 静默不启动，探测必须串行；A3 SuperPoD 每机独立 supernode 域（vnic 192.X 各机不同段，全域扫描仅本机 16 芯真实响应），跨机 hccs_ping 本就不适用，跨机 RDMA 直测 RoCE eth 面（`-ip -g`/`-ping`/iperf，并查 `-gateway -g`）。**

> 触发场景：多机 PD 分离、MC2、跨机 RDMA 连通性验证
> 详见 `~/.blue_server_toolkit/docs/npu-roce-connectivity.md`

### 950DT fabric 身份与 UB 网诊断（A5）

950DT 跨机通信（HCCL / mooncake ascend-direct）依赖三份 fabric 身份配置：
`/etc/hccl_rootinfo.json`（**逐机唯一**，mindcluster-tools 生成，拷别机的必报
EI0016）、`/etc/hixlep/ub_endpoint_npu_*.json`（经环境变量 `ASCEND_LOCAL_COMM_RES`
交给 mooncake——.so 里搜不到文件名，别走弯路）、活网状态（`urma_admin show --brief`）。
静态文件与活网 EID 段号漂移时，跨机传输报 `E19999: Internal error!` 而 python
层只见 `ret=-1`；TCP 探测通 ≠ UB 面通，两个平面独立。

> 触发场景：HCCL EI0004/EI0016、跨机 KV 传输失败 E19999、950DT 部署前 fabric 核验
> 详见 `~/.blue_server_toolkit/docs/a5-950dt-fabric-config.md`

### vLLM 服务管理

后台启动用 `docker exec -d`，健康检查用 `curl localhost:<port>/v1/models`，
停止服务用 `kill -9 <PID>`（从 npu-smi info 获取）。拉起服务的 cwd 不要在
vllm 代码仓内（仓目录与 pip 包重名冲突）。A3 可同时跑 4 个 TP4 服务
（端口 8000-8003，各用独立 chip 组）。**PD 分离验证的请求必须打 load-balance
proxy——直打 D 端口时 D 本地 prefill、P 零请求，链路失真**（vllm-ascend
examples/disaggregated_prefill_v1 自带 proxy 脚本）。**P/D 两端无相互启动依赖：
共享依赖（mooncake master 等）先起后 P/D 并行拉起，失败单侧重拉**；kv 握手端口
撞临时端口范围的偶发 `Address already in use` 重拉即可。

> 触发场景：vLLM 启动/停止/多服务并行、关键参数配置、并发验证、PD 分离链路验证
> 详见 `~/.blue_server_toolkit/docs/vllm-service-guide.md`

### PD 分离拉起与排障

失败类别清单按排查优先级组织：占卡者 → 上游代码缺口 → rootinfo/fabric →
max-model-len 超 KV 显存 → triton 严格模式（`TRITON_ALLOW_NON_CONSTEXPR_GLOBALS=1`）
→ 显存释放竞态（kill 后实测约 15 分钟才回基线）。mooncake P2P 日志解读
（随机握手端口正常、`Delaying free` 含义、`ret=-1` 要下钻 C++ glog 行找真错误码）；
冒烟先 `/v1/models` 核名（served name 从权重路径派生、大小写敏感），proxy 把请求
同时发 P 和 D——**P 的 200 只是 prefill ack，回答来自 D**。

> 触发场景：P/D 分离首次拉起、多轮失败排障、KV 传输链路验证
> 详见 `~/.blue_server_toolkit/docs/pd-disagg-bringup.md`

### vllm-ascend 源码编译

两步：vllm/ 仓根 `VLLM_TARGET_DEVICE=empty pip install -v -e . --no-build-isolation`
（先 `pip uninstall vllm vllm-ascend -y`，版本配套一律查 `.github/vllm-main-verified.commit` 取 commit id，勿按 release tag 配套）；
vllm-ascend/ 仓根同法装；蓝区先配全局 pip 国内源（见经验备忘），所有安装命令统一走源
（未配全局时兜底加 `-i https://mirrors.aliyun.com/pypi/simple/`）。
装前**先查 setuptools**（`--no-build-isolation` 用环境自带版本，过旧是最高频失败点，<77 就升）；
编译纯 CPU，**不需要 NPU 空闲**，过程中不用查 NPU 状态。

> 触发场景：源码安装/升级 vllm-ascend、bisect 切版本、镜像内版本不满足需求
> 详见 `~/.blue_server_toolkit/docs/vllm-ascend-build.md`（命令速查 + 按报错关键字 FAQ）

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

### 服务器配置与存储

`/root` 分区通常较小，大文件放 `/home`；模型缓存可软链迁到大盘
（`ln -s /home/.cache-root ~/.cache`）。哪台机器什么配置、磁盘剩多少、
权重放哪属于**个人环境信息**——查本地 `~/.blue_server_toolkit/config.json`
和 `~/.blue_server_toolkit/notes/server-configs.md`，不写入本仓
（见「用户配置与 Skill 本体分离」）。

> 触发场景：磁盘空间不足、权重路径查询、新服务器入册（改本地 config.json + notes/）

### 镜像源与拉取

> 触发场景：docker pull 慢/失败、蓝区拉镜像、镜像源切换
> 详见 `~/.blue_server_toolkit/docs/image-mirrors.md`

### Docker bind-mount 单文件陷阱

挂载**不存在的宿主机文件**时 docker 自动造出同名空目录，容器内该路径变目录、
配置"读不出来"，症状指向应用层极具迷惑性；修复需 overlay2 UpperDir 手术。
热更新挂载文件必须 `cat >` 原位写（保 inode，运行中容器实时可见）——`cp` 换
inode，容器看到的仍是旧内容。

> 触发场景：单文件挂载（rootinfo/hccn.conf 等）后容器内读取异常、热更新挂载文件
> 详见 `~/.blue_server_toolkit/docs/docker-bind-mount-traps.md`

### G 区大文件下载

> 触发场景：G 区机器下载模型/大文件、Python 报 self-signed certificate、下载中途冻结僵死、pkill 退出码 143
> **仅适用 G 区环境**（深信服 MITM 代理 + NFS 大盘），其他环境勿套用
> 详见 `~/.blue_server_toolkit/docs/gzone-download.md`

## 安全限制

以下命令被禁止或需要确认，定义在 config.json 的 `restrictions` 中：

### 禁止命令（AI 绝不执行）
- `sudo rm -rf /` — 系统级删除
- `reboot` — 重启服务器
- `pkill -9 -f python` — 模糊匹配杀所有 python 进程，误杀风险极高
- `docker system prune` 及一切 prune 变体（`container/image/builder/network/volume prune`）— 批量删除全机 stopped 容器与悬空镜像，他人 stop 后待复用的容器会被连可写层一起删除且**不可恢复**，共享机必伤及无辜

### 磁盘空间不足的处理红线
磁盘不足（df 满/接近满）时 AI 的唯一动作是**阻塞式上报用户并等待处置指示**，禁止自动执行任何清理行为（prune、删日志、删缓存、rm 等）。腾空间只允许"列全量清单逐个指名 + 用户逐项确认"后执行；破坏性命令写进任务书前先假设"撤销指令可能来不及到达"。

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
| flops-torch.py | A3 算力实测并判定机型（单 die fp16 matmul → 560T/752T） | `ssh {user}@{host} "docker exec -i {container} python3 -" < ~/.blue_server_toolkit/scripts/flops-torch.py` |
| who.sh | 宿主机 PID 反查所属 Docker 容器（npu-smi 的 PID → 容器 ID/镜像/名称） | `bash ~/.blue_server_toolkit/scripts/who.sh <host> <user> <pid>` |
| init-config.sh | 初始化配置与安装 | `bash ~/.blue_server_toolkit/scripts/init-config.sh` |
| start-docker-A2.sh | 创建 A2 容器（8 NPU 单芯） | scp 到服务器后 `bash start-docker-A2.sh <image_id> <name>` |
| start-docker-A3.sh | 创建 A3 容器（16 chip 单卡双芯） | scp 到服务器后 `bash start-docker-A3.sh <image_id> <name>` |
| start-docker-A5.sh | 创建 A5 容器（Ascend 950） | scp 到服务器后 `bash start-docker-A5.sh <image_id> <name>` |

## 维护与同步

本 skill 采用**源码仓单一来源 + 软链**策略：改动源码仓即自动同步所有 skill 安装，无需逐份 rsync。

| 位置 | 路径 | 类型 |
|------|------|------|
| 源码 git 仓 | `~/Documents/Code/AgentSkills/blue-server-toolkit` | 唯一源头；commit 带 `-s`；push 等用户指令（本仓偏好高频迭代） |
| Claude Code | `~/.claude/skills/blue-server-toolkit` | 软链 → 源码仓 |
| Codex | `~/.codex/skills/blue-server-toolkit` | 软链 → 源码仓 |
| OpenCode | `~/.config/opencode/skills/blue-server-toolkit` | 软链 → 源码仓 |
| ZCode | `~/.zcode/skills/blue-server-toolkit` | junction → 源码仓（Windows 用 `mklink /J`，勿放实体拷贝防霰弹式修改） |
| 运行时目录 | `~/.blue_server_toolkit/` | config.json 为实体文件（用户配置勿动）；docs/ 更新后 `cp` 同步 |

回退方案：若某个工具不支持软链（现象：技能列表里 blue-server-toolkit 消失），把对应软链换回 rsync 副本即可：

```bash
rm <坏掉的软链路径>
rsync -a --exclude '.git' --exclude '.DS_Store' "$HOME/Documents/Code/AgentSkills/blue-server-toolkit/" <目标路径>/
```

**维护原则**：使用蓝区服务器时，遇到 skill 未覆盖的新情况、合作总结出新经验后，主动写回源码仓（commit 带 `-s`）即完成三处 skill 安装同步；运行时目录 docs/ 顺手 `cp` 更新；新增文档同时在「进阶指南」加索引条目，并 bump frontmatter 的 version。写回前先过「用户配置与 Skill 本体分离」红线——个人环境信息只进本地 config.json / notes/，通用知识才进仓。

## 扩展

要新增文档：加到 `docs/` 目录，在"进阶指南"章节添加索引条目，
然后更新 frontmatter 的 version。
