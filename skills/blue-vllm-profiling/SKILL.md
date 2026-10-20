---
name: blue-vllm-profiling
description: >-
  Use for vLLM-on-Ascend profiling capture and interpretation: torch profiler
  launch flags, /start_profile /stop_profile mechanics, steady-state windows,
  stop-serve verification, analyse() per rank, step_trace_time buckets,
  per-operator attribution, bottleneck triage.
  触发：profiling、性能采集、start_profile 404、稳态窗口、trace、算子占比、
  通信占比、step_trace、瓶颈归因、TPOT 不达标、拓扑对比。Not for 起服务
  (blue-vllm-service)、编译 (blue-vllm-ascend-build)。
---

# Blue vLLM Profiling（采集与判读）

> 本 skill 只覆盖 profiling 采集管线与数据判读；服务拉起 → blue-vllm-service，日常操作 → hub 路由表。

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

## 采集管线（torch profiler 官方路线）

唯一正路 = vllm-ascend service_profiling_guide：**拉起时
`--profiler-config.profiler torch --profiler-config.torch_profiler_dir`（每引擎
端口独立子目录，防 rank 同名互踩）→ 压到稳态后直连各引擎端口 curl
`/start_profile` → ~3s → `/stop_profile`（proxy 不转发采集端点；
`/start_profile` 发出即采集，禁当健康探测）→ 停服核验（进程/端口/HBM）→ 离线
`torch_npu.profiler.profiler.analyse(<ascend_pt 目录>)` 逐 rank 解析（msprof CLI
不可用；共享盘多机解析须按机器+端口分片）**。窗口对准用 `/metrics`
generation_tokens_total 连续 4 次大增量判进正式稳态段，只采 ~3s 稳态 decode。
服务运行期只采原始不解析。单份闭环 60-90 分钟（采集仅 3s，大头是拉起/稳态/
停服/解析）。

> 详见 `~/.blue_server_toolkit/docs/vllm-service-profiling.md`

## 分析判读（数据 → 结论）

先建 forward 结构锚点（层数/稀疏与全注意力配比/draft 步数/投机 token 数）→
per-forward 分解 p50 中位数逐项对比 → 归因到单算子（`aiv_vec_ratio`/
`aiv_mte2_ratio` 三分算力/访存延迟/访存带宽瓶颈）。核心陷阱：
**step_trace_time 的 Free 桶是聚合口径，不能直接当空闲证据**（偶发停等假象），
判「算 vs 等」用 kernel_details 自算多流 union busy 率；reduceScatter 先查实现
接线再归属（可能是序列并行而非 MoE）；巨型 allGather 类 AICPU kernel 是失步
症状非差异来源；跨分支谱系横比通信无效。解读前必读 run 根 README-provenance
（镜像补丁清单）。

> 详见 `~/.blue_server_toolkit/docs/vllm-profiling-analysis.md`

## 压测证据纪律

结果目录带唯一 run-id，日志文件用 `open('xb')`（exclusive create）创建，已存在
即报错；失败换新目录重跑，不覆盖旧证据。

## 下钻表

| 症状 | 去向 |
|------|------|
| 停服核验的 kill 确认、HBM 回基线判定 | `~/.blue_server_toolkit/docs/npu-process-cleanup.md`（blue-npu-ops 域） |
| 带 profiler 参数的完整拉起命令 | `~/.blue_server_toolkit/docs/vllm-service-guide.md`（blue-vllm-service 域） |
