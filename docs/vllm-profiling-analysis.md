# vllm-ascend profiling 分析判读（从聚合数据到瓶颈结论）

> 场景：profiling 已按 [vllm-service-profiling.md](vllm-service-profiling.md) 完成
> 采集、解析、聚合，拿到 step_trace_time / op_statistic / kernel_details /
> communication 数据，要定位瓶颈、对比拓扑优劣。本文只讲「数据 → 结论」的判读
> 方法与误区；采集解析管线、聚合口径见上篇。

## 判读总纲：先锚定结构，再分解，后归因

1. **先建 forward 结构锚点**：总层数、稀疏/全注意力层各多少、draft 步数、每 seq
   每 forward 的投机 token 数（实测例：62 层 = 56 稀疏注意力 + 6 全注意力 + 3 draft
   步；投机 token 每 seq 每 forward 4 个，批 14 个 seq 时每 forward 56 个）。锚点按
   所用模型配置核实，勿沿用其他任务的数字——没有结构锚点，逐项对比无从谈起。
2. **对比用 per-forward 分解的 p50 中位数**：把每 forward 耗时按维度出中位数表
   （period / qk / full_attn / MoE a2a / MoE GEMM / 普通 GEMM / other / 通信），两拓扑
   逐项相减定位差异（实测例：周期 87.7 vs 76.4ms，Δ11.3ms 里 11.0ms 落在 kernel
   执行时间上）。总量/均值会被偶发停等拉偏，p50 不会。
3. **归因到单算子才算收工**：占比只是线索，结论必须落到「哪个算子 + 什么瓶颈
   （算力 / 访存 / 通信 / 等待）」，用 kernel_details 的 ratio 字段佐证（见下节）。

## step_trace_time：占比会骗人

- 分桶字段与「通信占比用 Not Overlapped」口径见 vllm-service-profiling.md
  「聚合与判读口径」。
- **Free 桶不能直接当空闲/停等证据**：它是聚合口径，单引擎一次偶发长停等
  （实测一例 4.2s）就能把全组 Free 占比抬高十几个百分点，制造「该拓扑空闲多」的
  假象——曾据此得出后来被推翻的结论。
- 判「算 vs 等」用 kernel_details 自算：**多流 union busy 率 + 全流静默 idle**
  （一个 forward 周期内所有流都无 kernel 的时间才是真 idle）。实测两拓扑 busy 均
  ~96%、静默 idle 同为 ~3.4ms 级——与 Free 占比给出的印象相反。

## kernel_details.csv：逐算子瓶颈判读

字段：`Start Time(us)` / `Duration(us)` / `Stream ID` / `Input Shapes` /
`Wait Time(us)` / `aic_mac_ratio` / `aiv_vec_ratio` / `aiv_mte2_ratio` /
`cube_utilization(%)`。

- **Duration 含调度等待**（profiler 工具自身口径），解读 reduceScatter 等同步类算子时
  勿当纯执行时间，结合 Wait Time 一起看。
- **AIV 算子瓶颈三分**（vec = 计算效率，mte2 = HBM→UB 搬运效率）：
  - vec 低 + mte2 低 → 访存**延迟**受限（散页访问等待，既非带宽也非算力）：实测
    `_decode_qk_score_kernel` vec ~14%、mte2 ~0.2%；
  - vec 高（~50% 级）→ 算力型：实测 `_minimax_qknorm_rope_cache_kernel` vec 46-55%；
  - mte2 高 → 访存**带宽**受限（搬运占大头）。
- **Input Shapes 直接核验维度假设**：o_proj / MoE GEMM 的维度应等于 hidden_size、
  gate_up 为其 2 倍——拿 GEMM shape 反查配置比翻配置文件快。

## 通信归因：算子名对不上机制，方向就错

- **per-layer reduceScatter ≠ MoE 归约**：同名集合通信算子可能来自不同机制（实测一例
  是 FlashComm 序列并行 sp_reduce_scatter，挂在 o_proj 后而非 MoE 后）。归因前查当前
  栈的实现确认接线，别按直觉把 reduceScatter 全记到 MoE 头上。
- **MoE a2a**：`MoeDistributeDispatchV3 / MoeDistributeCombineV3` 按 per-call 时长 ×
  次数计费；EP 跨机时每机多引擎并发争跨机链路——引擎数多的拓扑 a2a 反而更贵
  （实测 +1.8ms/forward），勿默认「并发切小引擎通信就更省」。
- **巨型 allGather 类 AICPU kernel（百 ms～秒级）= 失步症状**：AICPU 内等 peer，
  两种拓扑都会有，不是性能差异来源，对比时剔除。
- **per-call 时长连 payload 一起看**：实测 reduceScatter per-call TP4 62us/payload
  258KB vs TP2 28us/98KB——单看时长会误判集合通信退步。
- **跨分支谱系横比无效**：通信接线随代码分支变，同配置在不同谱系可能退化成别的
  集合通信路径。横比前先确认两栈同谱系（结合 run 根的 README-provenance）。

## 机制性归因条目（结论式，持续补充）

格式：现象 → 机制解释 → 优化含义。

- **qk 打分核按引擎 token 数线性计费（实测 ~10.8us/token），TP 切头零收益**：
  index-K cache 无头轴、TP 组内切分被实现显式禁用（每 rank 全量重算）、split-K 把
  program 数钉在 AI core 数——加 token 只拉长串行页扫描；减该项耗时只能减每引擎
  token 数或改索引结构，加 TP 头数无用。

## 已知坑 / 误区清单

| 症状 / 做法 | 为什么错 | 正解 |
|---|---|---|
| Free 占比高 → 判「空闲浪费大」 | 聚合口径 + 偶发停等假象 | kernel_details 自算 union busy / 静默 idle |
| 拿 Duration 当纯执行时间 | 含调度等待 | 同步类算子结合 Wait Time 判读 |
| 跨分支 / 跨谱系横比通信 | 接线随分支变 | 先核谱系（README-provenance） |
| 按算子名前缀猜着 grep | 实际注册名带实现后缀 | 先查 csv 里的实际全名再统计 |
| 解析产物里个别 txt 空文件 → 判解析失败 | 部分输出文件可为空 | 成败只看 op_statistic.csv |
| 总量 / 均值对比两拓扑 | 偶发停等拉偏结论 | per-forward 分解 p50 逐项比 |
| reduceScatter 一律记到 MoE 头上 | 可能是序列并行等其他接线 | 查当前栈实现确认机制再归属 |
