---
name: blue-npu-ops
description: >-
  Use for single-server NPU ops: npu-smi reading, HBM usage and orphan
  release, killing leftover processes (precise PID, never pkill -f python),
  idle checks, chip numbering, TP-to-chip planning, FLOPS measurement.
  触发：npu-smi、HBM 占用/不释放、显存占满、杀进程、进程残留、机器空不空、
  chip 编号、VISIBLE_DEVICES、算力实测。Not for 跨机 fabric/RoCE
  (blue-npu-fabric)、vLLM 生命周期 (blue-vllm-service)、装驱动
  (blue-server-provisioning)。
---

# Blue NPU Ops（单机 NPU 资源）

> 本 skill 只覆盖单机 NPU 查/清/选卡；日常操作或其他域 → hub（blue-server-toolkit）路由表。

<!-- BEGIN blue-skill-contract -->
> **运行时契约**（全部 blue-* skill 共享；单点定义于 templates/skill-contract.md）
>
> 1. 机器信息只读 `~/.blue_server_toolkit/config.json`（host/user/container）与
>    `notes/`；个人环境信息（IP、机器清单、任务状态）禁止写回本仓。
> 2. 容器内执行统一 `ssh {user}@{host} "docker exec {container} bash -c '{command}'"`；
>    蓝区装任何包之前先配全局源
>    `pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/`。
> 3. 长命令输出重定向日志再分段看：`cmd > <日志路径> 2>&1; echo EXIT=$?` 后
>    `tail`/`grep`；禁止 `| tail` 截断 stdout（管道使 `$?` 失真）。日志放用户
>    指定的工作目录，未指定时放 `/tmp/<任务名>/`。
> 4. 共享机礼仪：长时间占用 NPU 先 `wall` 广播声明；确需动他人容器，逐台记录
>    （容器名/镜像/状态），只 stop 不 rm，测完按记录恢复。

**安全红线**

禁止命令（AI 绝不执行）：

- `sudo rm -rf /` — 系统级删除
- `reboot` — 重启服务器
- `pkill -9 -f python` — 模糊匹配杀所有 python 进程，误杀风险极高
- `docker system prune` 及一切 prune 变体（container/image/builder/network/volume
  prune）— 批量删除全机 stopped 容器与悬空镜像，他人 stop 后待复用的容器会被连
  可写层一起删除且**不可恢复**，共享机必伤及无辜

磁盘空间不足红线：磁盘满/接近满时唯一动作是**阻塞式上报用户并等待处置指示**，
禁止自动执行任何清理行为（prune、删日志、删缓存、rm 等）。腾空间只允许"列全量
清单逐个指名 + 用户逐项确认"后执行。

需确认命令（执行前提醒用户）：

- `rm -rf` — 递归删除
- `docker rm` — 删除容器
- `docker stop` — 停止运行中容器
- `kill -9` — NPU 进程清理的标准流程，但需提醒用户
- `npu-smi set -t reset` — 芯片重置，影响该 NPU 上所有进程
<!-- END blue-skill-contract -->

## NPU 进程清理与 HBM 释放

标准流程：`npu-smi info` 查 PID → `kill -9 <pid>`（精准 PID，执行前提醒用户）。
禁止 `pkill -9 -f python`（模糊匹配误杀共享服务器上其他用户进程）。
孤儿 HBM（npu-smi 无进程但显存仍占满）→ `docker stop` 容器（stop 后驱动整体
回收；`restart` 立即拉起不给回收窗口，勿用）。

判机空闲须在**宿主机**跑 npu-smi 看 HBM 数值（容器内他人进程名列可能空白，
"无进程名"≠空闲），辅以 `ss -tlnp` 查端口；`docker ps` 只用于占用归因和接管
清点，不作空闲判据。清点残留进程用大小写不敏感 grep（`VLLM::` 大写前缀会被
`grep "vllm"` 漏掉），以宿主机 PID 为准。

宿主机管道里 kill 容器内 PID 是**静默失败**（ps 在容器跑、kill 在宿主机跑）——
批量清理用 `docker exec -i <container> bash -s <<'EOF'` 整段放进容器；脚本抓
HBM 数值注意表格双空格对齐（`grep -oE "[0-9]+ */ *98304"`，分母按机型替换）。

> 详见 `~/.blue_server_toolkit/docs/npu-process-cleanup.md`

## A3 芯片编号

A3 单卡双芯：8 卡 = 16 chip。`ASCEND_RT_VISIBLE_DEVICES` 用全局 chip ID（0-15），
不是 NPU 卡号（0-7）。换算：chip ID = NPU号 × 2 + 芯片序号。TP4 需要 4 个 chip
（2 张 NPU），TP8 需要 8 个 chip（4 张 NPU）。950DT（A5）单卡单芯：8 卡 = 8
chip，无 ×2 换算——两代机型对照表见同文档末节，混用时先确认机型再套换算。

> 详见 `~/.blue_server_toolkit/docs/a3-chip-numbering.md`

## 算力判定（560T/752T）

宿主机一般没装 torch，去任一 vllm 镜像容器里跑 `flops-torch.py`（stdin 管道进
容器，服务器零落盘，用法见下方脚本表）。单 die fp16 matmul 峰值：560T 机型
~230-250 TFLOPS；752T ~297-322（阈值 280）。真实压测（数秒、数百瓦），die 被
占用时勿跑。

## 脚本用法

| 脚本 | 用法 |
|------|------|
| check-npu.sh | `bash ~/.blue_server_toolkit/scripts/check-npu.sh <host> <user> [container]` |
| who.sh | `bash ~/.blue_server_toolkit/scripts/who.sh <host> <user> <pid>`（npu-smi PID → 容器 ID/镜像/名称） |
| flops-torch.py | `ssh {user}@{host} "docker exec -i {container} python3 -" < ~/.blue_server_toolkit/scripts/flops-torch.py` |

## 下钻表

| 症状 | 去向 |
|------|------|
| 服务重启报 Free memory 不足、kill 后显存长时间不回 | `~/.blue_server_toolkit/docs/npu-process-cleanup.md` |
| 跨机 EI0004/EI0016/E19999、hccs_ping | `~/.blue_server_toolkit/docs/npu-roce-connectivity.md` 与 `a5-950dt-fabric-config.md`（blue-npu-fabric 域） |
| 停 vllm 服务的完整流程 | blue-vllm-service（kill 前置确认见上方红线） |
