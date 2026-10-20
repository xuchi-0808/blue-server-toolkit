---
name: blue-npu-ops
description: >-
  Use for single-server NPU ops: npu-smi reading, HBM usage and orphan
  release, killing leftover processes (precise PID, never pkill -f python),
  idle checks, chip numbering, FLOPS measurement.
  触发：npu-smi、HBM 占用/不释放、显存占满、杀进程、进程残留、机器空不空、
  chip 编号、VISIBLE_DEVICES、算力实测。Not for 跨机 fabric/RoCE
  (blue-npu-fabric)、vLLM 生命周期 (blue-vllm-service)、装驱动
  (blue-server-provisioning)。
---

# Blue NPU Ops（单机 NPU 资源）

> 本 skill 只覆盖单机 NPU 的查询、清理与选卡；日常操作或其他专项问题 → hub（blue-server-toolkit，总入口）路由表。

<!-- BEGIN blue-skill-contract -->
> **运行时契约**（全部 blue-* skill 共享；唯一定义处 templates/skill-contract.md）
>
> 1. 机器信息只读 `~/.blue_server_toolkit/config.json`（host/user/container）与
>    `notes/`；个人环境信息（IP、机器清单、任务状态）禁止写回本仓。
> 2. 容器内执行统一 `ssh {user}@{host} "docker exec {container} bash -c '{command}'"`；
>    蓝区装任何包之前先配全局源
>    `pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/`。
> 3. 长命令输出重定向日志再分段看：`cmd > <日志路径> 2>&1; echo EXIT=$?` 后
>    `tail`/`grep`；禁止 `| tail` 截断 stdout（管道后 `$?` 反映的是 tail 的
>    退出码）。日志放用户指定的工作目录，未指定时放 `/tmp/<任务名>/`。
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

判断机器是否空闲须在**宿主机**跑 npu-smi 看 HBM 数值（容器内 npu-smi 里他人
进程的进程名一栏可能空白，"无进程名"≠空闲），辅以 `ss -tlnp` 查端口；
`docker ps` 只用于追查占用来源和接管前清点，不作空闲判据。清点残留进程用
大小写不敏感 grep（`VLLM::` 大写前缀会被 `grep "vllm"` 漏掉），以宿主机 PID
为准。

宿主机上用管道 kill 容器内 PID 会**静默失败**（ps 在容器里跑、kill 在宿主机
跑）——批量清理用 `docker exec -i <container> bash -s <<'EOF'` 整段放进容器；
脚本里抓 HBM 数值时注意 npu-smi 表格是双空格对齐
（`grep -oE "[0-9]+ */ *98304"`，分母按机型替换）。

> 详见 `~/.blue_server_toolkit/docs/npu-process-cleanup.md`

## A3 芯片编号

A3 单卡双芯：8 卡 = 16 chip。`ASCEND_RT_VISIBLE_DEVICES` 用全局 chip ID
（0-15），不是 NPU 卡号（0-7）。换算：chip ID = NPU号 × 2 + 芯片序号。TP4
需要 4 个 chip（2 张 NPU），TP8 需要 8 个 chip（4 张 NPU）。950DT（A5）单卡
单芯：8 卡 = 8 chip，无 ×2 换算——两代机型对照表见同文档末节，混用时先确认
机型再套用换算。

> 详见 `~/.blue_server_toolkit/docs/a3-chip-numbering.md`

## 算力判定（560T/752T）

宿主机一般没装 torch，去任一 vllm 镜像容器里跑 `flops-torch.py`（用 stdin
管道送进容器，服务器上不落盘，用法见下方脚本表）。单 die fp16 matmul 峰值：
560T 机型 ~230-250 TFLOPS；752T ~297-322（阈值 280）。真实压测（数秒、数百
瓦），die 被占用时勿跑。

## 脚本用法

| 脚本 | 用法 |
|------|------|
| check-npu.sh | `bash ~/.blue_server_toolkit/scripts/check-npu.sh <host> <user> [container]` |
| who.sh | `bash ~/.blue_server_toolkit/scripts/who.sh <host> <user> <pid>`（npu-smi PID → 容器 ID/镜像/名称） |
| flops-torch.py | `ssh {user}@{host} "docker exec -i {container} python3 -" < ~/.blue_server_toolkit/scripts/flops-torch.py` |

## 相关文档

| 症状 | 去向 |
|------|------|
| 服务重启报 Free memory 不足、kill 后显存长时间不回 | `~/.blue_server_toolkit/docs/npu-process-cleanup.md` |
| 跨机 EI0004/EI0016/E19999、hccs_ping | `~/.blue_server_toolkit/docs/npu-roce-connectivity.md` 与 `~/.blue_server_toolkit/docs/a5-950dt-fabric-config.md`（属 blue-npu-fabric） |
| 停 vllm 服务的完整流程 | blue-vllm-service（kill 前需先确认，见上方红线） |
