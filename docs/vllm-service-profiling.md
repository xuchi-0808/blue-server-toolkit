# vllm-ascend 服务级 profiling（torch profiler 官方路线）

> 场景：对运行中的 vllm-ascend 服务（单机或多机 PD 分离）采集稳态性能数据并产出分析报告。
> 唯一正路 = vllm-ascend 仓 `docs/source/developer_guide/performance_and_debug/service_profiling_guide.md`
> 的 torch profiler 流程：**拉起服务时配置参数 → curl 启停采集 → 停服核验 → 离线一行命令解析**。
> 与 [pd-disagg-bringup.md](pd-disagg-bringup.md)（拉起排障）、[vllm-service-guide.md](vllm-service-guide.md)（服务生命周期）互补。

## 顺序铁律（违反必返工）

```text
拉起带采集参数的服务 → 采集 run 压到稳态 → curl start → ~3s → curl stop
→ 原始数据落盘确认 → 停全部相关服务 → 核验退出（进程 0/端口关/HBM 回基线，留证）
→ 离线解析（期间禁起任何服务）→ 分析报告 → 才允许下一轮服务
```

服务运行期间**只采原始数据，不解析、不生成报告**；采集 run 不算性能成绩（workload 与正式口径一致即可）。

## 采集配置（拉起时烘焙，改目录=重拉服务）

```bash
# 服务启动参数（每个引擎端口各自独立输出目录）：
--profiler-config.profiler torch \
--profiler-config.torch_profiler_dir "<run>/profiling/raw/port<API端口>"
```

- 不带该参数启动的服务**没有** `/start_profile` 端点（404）——采集能力是启动参数决定的，压测中途想补采只能重拉服务。
- **每端口一个子目录**：各 TP rank 的 trace 文件名跨引擎同名，混在一个目录会互踩覆盖。部署模板里写 `mkdir -p "$PROF_BASE/port$2"` + 目录引用 `$PROF_BASE/port$2`，`$2` 为本引擎 API 端口。
- 输出目录在引擎进程里是**烘焙死**的：换 run 目录必须重新生成模板重拉服务，否则数据静默落到旧路径（事后 mv 要写 provenance 说明）。改目录时**模板与 wrapper 里的目录引用两处必须同改**，只改模板本体数据照样落旧目录。
- 每端口目录下的产物形态：引擎 API 层 trace（`*.async_llm.*.pt.trace.json.gz`）+ 每个 TP rank 一个 `*_ascend_pt/` 子目录（真正的算子数据）。

## 采集时机（独立采集 run）

```bash
curl -s http://<引擎IP>:<端口>/start_profile -X POST   # 发出即开始采集
sleep 3
curl -s -m 120 http://<引擎IP>:<端口>/stop_profile -X POST
```

- **`/start_profile` 本身就是开始采集**——健康探测禁碰它（误触后立即 stop 并删脏目录）；探活一律 `/v1/models` 或 `/metrics`。
- **PD 拓扑下 proxy 不转发采集端点**：必须直连每个引擎自己的 API 端口逐个 curl（多机时各机本地并行发）。
- 窗口对准**正式压测段的稳态 decode**：用 `/metrics` 的 `vllm:generation_tokens_total` 轮询（15s 间隔，**连续 4 次增量 >1000** 才判进正式段——预热突发通常只有 ~25s 且幅度低，单次大增量会误判）；进段后再 sleep 30-60s 才 start，**3s 即 stop**——采长了 trace 撑爆且混入非稳态。
- 多机采集须落在**同一个稳态窗口**：本地编排脚本统一判稳态后 ssh 并行触发各机 capture，并设总超时兜底；两机各自手动触发容易错窗。
- 跨机注意容器钟差（实测可差数分钟）：时间轴对齐以各自机器本地钟为准，跨机比对前先记录两钟差值。

## 停服核验（解析前置条件）

停本次全部 P/D 引擎（只 kill 明确 PID）后核验三件事并存证
（`service_shutdown_verification.txt`：进程清单、`/proc/net/tcp{,6}` 端口态、npu-smi HBM）：

1. 无残留 vllm/worker/transfer 进程；
2. 各 API 端口全部关闭；
3. HBM 回基线（大模型多卡释放是异步的，可等 ~15 分钟；残几 GB 属驱动占用）。

HBM 数值的脚本化抓取（npu-smi 表格双空格对齐，普通 grep 抓不到）见
[npu-process-cleanup.md](npu-process-cleanup.md)。

## 离线解析（torch_npu 一行）

```python
from torch_npu.profiler.profiler import analyse
analyse("<...>/port<端口>/<主机名>_*_ascend_pt/")   # 传入单个 rank 的 ascend_pt 目录
```

- 容器内 **msprof CLI 不可用**（Operation not permitted），不要尝试；`analyse()` 是官方文档指定的离线入口。
- 每个 rank 目录各跑一次；产物落在该目录的 `ASCEND_PROFILER_OUTPUT/`：
  `op_statistic.csv`（算子统计）、`kernel_details.csv`（逐 kernel）、`step_trace_time.csv`
  （步进耗时分桶，字段与口径见下节）、`communication.json`、`trace_view.json`、`analysis.db`。
  **单 rank 成功判据 = 该目录出现 `op_statistic.csv`**，失败目录不产出任何 csv。
- 每 rank 实测约 40s，纯 CPU 不占 NPU——但纪律上仍须停服核验通过后才解析。
- 批量编排：raw 根目录用环境变量（如 `RAW_BASE`）+ argv 端口列表参数化，**禁硬编码路径**；
  `docker exec -d` 逐机后台跑、每机一份日志，grep `done|FAIL|no-output|BATCH_COMPLETE` 判进度。
- **共享文件系统上多机并发解析同一批目录会互踩**（内部 parser 任务相互失败）：
  批处理脚本必须按机器+端口分片（argv 传端口列表），且重跑前先清掉 `ASCEND_PROFILER_OUTPUT`。

## 聚合与判读口径

多 rank（十几个 rank 起）逐个解析后**先聚合再下结论**，手读单个 rank 会以偏概全。
聚合产物（如 `parsed/aggregated_summary.json`）应含：每 rank 分桶耗时、每 rank top 算子表、
rank 计算失衡、api_statistic top N、communication 汇总。

- **step_trace_time 分桶（每 rank 一行）**：`Computing` / `Communication` /
  `Communication(Not Overlapped)` / `Overlapped` / `Free`，`Stage` 为行总计。
  恒等式 **Stage ≈ Computing + Communication(Not Overlapped) + Free**——Overlapped 的
  通信时间已含在 Computing 里，不单独构成瓶颈；**「通信占比」口径一律用
  Communication(Not Overlapped)**，勿用 Communication 总量。
- **注意力占比口径**：`op_statistic.csv` 里 `FusedInferAttentionScore +
  _decode_qk_score_kernel（+ SparseAttentionScore）` 的 total 之和 ÷ 单 rank 全算子 total。
- **rank 计算失衡**：Computing 的 min/max/mean/imbalance_pct（个位数百分比内算均衡）。
- **communication 汇总**：`communication.json` 按 `"Communication Time Info/Elapse Time(ms)"` 累加。
- **窗口代表性校验**（下结论前必做）：采集窗 TPOT/TPS 与同配置独立专测值对照（偏差在
  个位数百分比内才可信），且采集时间戳落在正式段稳态 decode 时间轴内。
- **跨机对比须知**：两机引擎步数差是系统性偏移（实测可 ~3%），跨机/跨拓扑对比结论必须
  声明该偏移，3% 以内的差不作数。

## 分析报告必含维度

算子（top 表带次数/总时长）、计算-通信-空闲占比（step_trace_time 分桶，口径见上节）、
rank 间计算失衡、引擎间负载（token 数）失衡、KV 传输延迟分布（P/D 日志或 communication）、
CPU 调度/同步等待。结论必须引用具体数值/时间段；证据不足写成待验证假设。
分析维度口诀：**算子、通信、空闲、调度、同步、KV 传输、负载不均衡**。

## 产物目录与 provenance

- run 目录固定两级 `profiling/{raw, parsed}`：`raw/port<端口>/` 收引擎落盘的原始 trace，
  解析与聚合产物归集到 `parsed/`（含 `aggregated_summary.json`）。
- run 根放 `README-provenance.md`，必记三件事：**镜像标识**、**镜像内 site-packages 已打的
  补丁清单**（补丁脚本/备份文件名/打在哪个引擎侧）、**目录 mv 记录**（烘焙目录失误的事后补救）。
- 解读数据前先读 provenance：镜像内就地打的补丁会改变算子行为与占比结构，
  不知晓补丁状态就无法归因异常数据。

## 成本预估（实测口径，排期用）

采集本身只有 ~3s，大头全是脚手架——单份闭环实测约 **60-90 分钟**：

| 阶段 | 实测约 |
|---|---|
| 引擎拉起 | 7-10 min |
| 稳态流量（含预热、排空） | ~10 min |
| 停服核验（HBM 异步释放） | ~10 min |
| 逐 rank 解析（16 rank 双机并行） | 20-40 min |
| 聚合 + 分析报告 | 15-30 min |

原始 trace 实测每端口约 150-290MB，run 目录预留数 GB。

## 踩坑速查

| # | 坑 | 症状 | 规则 |
|---|---|---|---|
| 1 | 服务未带 `--profiler-config` 启动 | `/start_profile` 404 | 采集能力启动时烘焙；想采必须拉起前配好 |
| 2 | 拿 `/start_profile` 当健康探测 | 脏 trace 落盘 | 探活只用 /v1/models、/metrics |
| 3 | 多引擎共用一个输出目录 | rank 文件同名互踩 | 每端口独立子目录（模板 `port$2`） |
| 4 | 输出目录指向旧 run | 数据落错地方/找不到 | 换 run 重生成模板重拉；或事后 mv+provenance |
| 5 | 采集打在预热/排空段 | trace 混非稳态 | generation_tokens_total 连续 4 次大增量判进段，再等 30-60s |
| 6 | 采集过长 | trace 巨大、解析慢 | 稳态 decode 只采 ~3s |
| 7 | 用 msprof CLI 解析 | Operation not permitted | 唯一离线路 = `torch_npu analyse()` |
| 8 | 多机并发 analyse 同目录 | parser 内部任务失败 | 按机器+端口分片；重跑前清 ASCEND_PROFILER_OUTPUT |
| 9 | 服务未停就解析 | 数据不全/违反纪律 | 顺序铁律：落盘→停服→核验→解析 |
| 10 | 跨机时间戳对不上 | 时间轴错位 | 先测各机容器钟差再对齐 |
| 11 | 压测工具建 run 目录与预建目录冲突 | 工具拒建（禁覆盖设计） | 采集目录规划进工具流程；冲突时先挪开再建再挪回 |
| 12 | 改输出目录只 sed 部署模板本体 | 数据仍落旧目录 | 模板与 wrapper 两处目录引用同改（见「采集配置」） |
| 13 | 批处理脚本硬编码 raw 路径 | 换 run 重跑即失败 | 路径一律 env+argv 参数化 |
| 14 | 镜像内补丁未记 provenance | 异常占比无法归因 | provenance 必列补丁清单；解读前先读 |
