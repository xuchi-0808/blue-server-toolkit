---
name: blue-vllm-ascend-build
description: >-
  Use when building or upgrading vllm-ascend from source: editable two-step
  install, version pairing via vllm-main-verified.commit, setuptools>=77,
  pip mirror setup, rsync-then-chown, error-keyword FAQ. Pure CPU.
  触发：编译 vllm、装/升级 vllm-ascend、pip install -e、换版本、bisect、
  setuptools、pip 卡在 Downloading、Metadata generation failed。Not for
  起服务 (blue-vllm-service)、profiling (blue-vllm-profiling)。
---

# Blue vLLM-Ascend Build（源码编译安装）

> 本 skill 只覆盖源码编译与升级 vllm-ascend；装完起服务 → blue-vllm-service，日常操作 → hub（blue-server-toolkit）路由表。

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

## 两步安装与版本配套

1. vllm/ 仓根 `VLLM_TARGET_DEVICE=empty pip install -v -e . --no-build-isolation`
   （先 `pip uninstall vllm vllm-ascend -y`）
2. vllm-ascend/ 仓根用同样命令安装

版本配套一律查 `.github/vllm-main-verified.commit` 取 commit id，**勿按 release
tag 配套**。蓝区先配全局 pip 国内源（运行时契约第 2 条），所有安装命令统一
走源。

装前**先查 setuptools**（`--no-build-isolation` 用环境自带版本，过旧是最高频
失败点，<77 就升级）。编译纯 CPU，**不需要 NPU 空闲**，过程中不用查 NPU 状态。

> 命令速查 + 按报错关键字索引的 FAQ：
> `~/.blue_server_toolkit/docs/vllm-ascend-build.md`

## rsync 跨 uid 传代码后容器内必须 chown

mac 上 rsync 传过去的文件 owner 是本地 uid（如 501），容器内 git 访问报
`dubious ownership`——setuptools_scm（pip -e 装 vllm 时 metadata 失败）、
submodule fetch（build_aclnn.sh 拉 catlass 失败）都会踩到。**注意与"升
setuptools 重试"的 FAQ 区分**：metadata generation failed 在 rsync 传代码的
场景下优先查 chown。根治：容器内 `chown -R root:root <code_dir>`（或
`git config --global --add safe.directory <repo>` 逐个补登记，不如 chown
干净）。

## pip 卡在 Downloading

不是网络慢，是 pypi.org 直连挂死——配全局源（契约第 2 条）后重跑；命令示例里
显式写 `-i` 只是未配全局源时的兜底写法。FAQ 全表见上方文档。
