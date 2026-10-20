---
name: blue-vllm-profiling
description: >-
  Use for vLLM-on-Ascend profiling capture and interpretation: launch flags,
  /start_profile /stop_profile, steady-state windows, per-rank analyse(),
  step_trace_time buckets, operator attribution, bottleneck triage.
  触发：profiling、性能采集、start_profile 404、稳态窗口、trace、算子占比、
  通信占比、step_trace、瓶颈归因、TPOT 不达标、拓扑对比。Not for 起服务
  (blue-vllm-service)、编译 (blue-vllm-ascend-build)。
---

# Blue vLLM Profiling（采集与判读）

> 本 skill 只覆盖 profiling 采集流程与数据判读；服务拉起 → blue-vllm-service，日常操作 → hub（blue-server-toolkit）路由表。

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

## 采集流程（torch profiler 官方路线）

唯一正确的路线是 vllm-ascend 的 service_profiling_guide：**拉起时加
`--profiler-config.profiler torch --profiler-config.torch_profiler_dir`（每个
引擎端口的输出放独立子目录，防止各 rank 同名文件互相覆盖）→ 压到稳态后直连
各引擎端口 curl `/start_profile` → 约 3 秒 → `/stop_profile`（proxy 不转发
采集端点；`/start_profile` 一发出就在采集，不要当健康探测用）→ 停服后核验
（进程/端口/HBM）→ 离线用 `torch_npu.profiler.profiler.analyse(<ascend_pt
目录>)` 逐 rank 解析（msprof CLI 不可用；共享盘多机解析须按机器+端口分片）**。
采集窗口的定位用 `/metrics` 的 generation_tokens_total：连续 4 次大增量即判定
进入正式稳态段，只采约 3 秒的稳态 decode。服务运行期间只采集原始数据、不做
解析。单次完整流程 60-90 分钟（采集本身仅 3 秒，大头是拉起/稳态/停服/解析）。

> 详见 `~/.blue_server_toolkit/docs/vllm-service-profiling.md`

## 分析判读（数据 → 结论）

先建立 forward 结构基准（层数/稀疏与全注意力配比/draft 步数/投机 token 数）→
按每次 forward 分解、取 p50 中位数逐项对比 → 归因到单个算子
（`aiv_vec_ratio`/`aiv_mte2_ratio` 把瓶颈分成算力、访存延迟、访存带宽三类）。
核心陷阱：**step_trace_time 的 Free 桶是聚合口径，不能直接当空闲证据**（含偶发
停等造成的假象），判断「在算还是在等」用 kernel_details 自行计算多流 union
busy 率；reduceScatter 先查接的是哪套实现再归因（可能是序列并行而非 MoE）；
巨型 allGather 类 AICPU kernel 是失步的症状、不是差异的来源；不同代码分支/构建
之间横向对比通信数据无效。解读前必读 run 目录下的 README-provenance（镜像补丁
清单）。

> 详见 `~/.blue_server_toolkit/docs/vllm-profiling-analysis.md`

## 压测结果留存规则

结果目录带唯一的 run-id，日志文件用 `open('xb')`（exclusive create，已存在即
报错）创建；失败换新目录重跑，不覆盖旧结果。

## 相关文档

| 症状 | 去向 |
|------|------|
| 停服后核验的 kill 确认、HBM 回到基线判定 | `~/.blue_server_toolkit/docs/npu-process-cleanup.md`（属 blue-npu-ops） |
| 带 profiler 参数的完整拉起命令 | `~/.blue_server_toolkit/docs/vllm-service-guide.md`（属 blue-vllm-service） |
