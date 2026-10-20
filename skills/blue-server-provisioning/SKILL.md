---
name: blue-server-provisioning
description: >-
  Use for fresh Ascend server and container bring-up: bare-metal HDK
  driver+firmware install (tar precondition, kernel-devel match, HwHiAiUser,
  driver-before-firmware), start-docker-A2/A3/A5.sh container creation,
  image-ID discipline for same-day same-name builds.
  触发：新服务器、裸机、装驱动、固件、HDK、npu-smi 不可用、建容器、
  start-docker、镜像 ID。Not for 日常 docker start/exec/logs
  (blue-server-toolkit)、NPU 进程问题 (blue-npu-ops)、拉镜像 (hub 镜像源节)。
---

# Blue Server Provisioning（裸机装机与建容器）

> 本 skill 只覆盖装机与容器创建；日常容器操作 → hub（blue-server-toolkit），拉镜像 → hub 镜像源节。

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

## 裸机驱动安装（HDK）

从空白 Atlas 800I A3 装到 `npu-smi info` 可用。关键顺序：先装基础工具（含
tar）→ 创建 HwHiAiUser → 下载驱动+固件 → **先驱动后固件**。驱动装好后，
start-docker 脚本映射所需的 4 类设备文件全部自动生成。

> 详见 `~/.blue_server_toolkit/docs/hdk-installation.md`

## 建容器（start-docker-A2/A3/A5）

脚本安装后位于 `~/.blue_server_toolkit/scripts/`，scp 到服务器执行：

| 脚本 | 机型 | 用法 |
|------|------|------|
| start-docker-A2.sh | A2（8 NPU 单芯） | `bash start-docker-A2.sh <image_id> <name>` |
| start-docker-A3.sh | A3（16 chip 单卡双芯） | `bash start-docker-A3.sh <image_id> <name>` |
| start-docker-A5.sh | A5（Ascend 950） | `bash start-docker-A5.sh <image_id> <name>` |

**容器创建前确认**：上下文中没有明确镜像 ID 和容器名时，先向用户询问用什么
镜像、容器名起什么；用户授权"你自己看着办"后才自行决定。

**同日多 flavor 同名系镜像以镜像 ID 为准**：同一台机常并存多个名字相近的同日
构建镜像（不同 OS 底座/flavor），创建容器只认完整镜像 ID，勿按名字短前缀猜。

## 下钻表

| 症状 | 去向 |
|------|------|
| 装完驱动后的日常容器操作（start/exec/logs） | hub（blue-server-toolkit）命令参考 |
| docker pull 慢、镜像源选择 | hub「常用镜像源」节 |
| 建容器后挂载身份文件读不到 | hub「Docker bind-mount 陷阱」节 |
