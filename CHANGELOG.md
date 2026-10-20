# Changelog

遵循语义化版本。历史版本（1.x）的详细变更见 `git log`。

## 3.0.0 (2026-10-20)

架构重构：单 skill 仓 → **一仓一插件、7 个按任务领域拆分的 skill**（大版本，含
破坏性布局变更）。

- **skills/**：新增 7 个 skill——`blue-server-toolkit`（hub：日常操作+路由表+
  红线）、`blue-npu-ops`（进程清理/A3 编号/算力）、`blue-npu-fabric`
  （RoCE/950DT fabric，按 EI 错误码字面量路由）、`blue-vllm-service`
  （服务/PD/graph/TP 速查）、`blue-vllm-ascend-build`（编译+rsync-chown 备忘）、
  `blue-vllm-profiling`（采集+判读）、`blue-server-provisioning`
  （HDK/建容器/镜像 ID）；原 SKILL.md 进阶指南的 16 段专题摘要重新安置：
  15 段随所属 skill 迁移，「服务器配置与存储」并入 hub 经验备忘；hub 改为
  路由表 + 保留 4 个专题节（SSH 稳定性/镜像源/bind-mount/G 区）
- **.claude-plugin/**：新增唯一插件清单 plugin.json + marketplace.json（ZCode
  也能识别 `.claude-plugin/`，无需第二份清单）；版本号以 plugin.json 为唯一
  来源，README H1 与 CHANGELOG 最新条目同步同一版本号，各 skill 不再带独立
  版本号
- **templates/skill-contract.md**：运行时契约与安全红线以该文件为单一来源，
  全文复制进全部 7 个 skill（不再压缩成摘要）
- **运行时约定**：`~/.blue_server_toolkit/` 统一安装保留，新增
  `.assets-version` 版本标记文件 + hub 首次激活时比对并自动同步（解决运行时
  docs 手动 cp 导致的版本漂移）；SKILL.md 正文对 docs/scripts 的引用一律写
  绝对路径、禁止 `../`、docs 不内联进 skill 正文（一律经运行时目录按需读取）
- **工程**：新增 `link-dev.sh`（为四个工具逐 skill 建软链，含
  --check/--unlink/--prune-old；开发软链与插件安装互斥）与 `check-repo.sh`
  合并前检查（契约块一致性/版本号三处一致/行数上限 hub≤400、专项 skill≤120/
  description 合计 ≤50 行且触发词在前 250 字符内）；新增
  `docs/routing-acceptance.md` 路由验收题目清单（21 条，修改 description 后
  重跑）
- **README**：全文重写（两种安装方式/skills 表/内容增长复查/专项 skill 升格
  条件/路由验收标准）
- **范围说明**：语言清理覆盖 skills/、README、templates、两个脚本与本条目；
  docs/ 其余 15 篇正文与 2.x 历史条目保留原文，不做追溯清理

## 2.5.0 (2026-10-20)

收录准备：LICENSE 版权行署名补全。

- **LICENSE**：版权行补名 `xuchi-0808`，满足 awesome-mindie-skills 目录收录的
  "维护者与许可证明确"审阅要求
- **SKILL.md**：version 2.5.0

## 2.4.2 (2026-10-18)

仓库卫生修正：历史环境信息清理与注释订正。

- **历史重写**：移除早期已废弃的 `docs/server-configs.md` 与 `docs/site-notes/`
  （全历史），环境专属信息统一占位化；README 示例路径中的任务号改为
  `<task-id>`；删除废弃的 `release/v0.9`、`release/v1.0` 分支与 `v0.9`、`v1.0` tag
- **.gitignore**：订正 config.json 注释（仓内已无该文件，本地配置在
  `~/.blue_server_toolkit/`）
- **SKILL.md**：version 2.4.2

## 2.4.1 (2026-10-17)

仓库体检修正：卫生项与索引触发词；确立版本号约定。

- **.gitignore**：忽略 `.zcode/`（本地会话工具产物，不入库）
- **SKILL.md**：确立版本号约定（新专题/新文档/新功能 = 第二位 +1，修正补坑 =
  第三位 +1）；两个 profiling 条目触发场景去重——采集条目聚焦采集/解析管线，
  归因/分析类触发词移归分析判读条目
- 体检结论（无行动项）：docs 索引覆盖完整、文档间相对链接全部可解析、
  profiling 相关四篇（服务管理/PD 排障/采集管线/分析判读）边界清晰无重复

## 2.4.0 (2026-10-16)

profiling 分析判读专项：从聚合数据到瓶颈结论的方法与误区，持续迭代型文档。

- **新增 `docs/vllm-profiling-analysis.md`**：判读总纲（forward 结构锚点 → per-forward
  分解 p50 逐项对比 → 归因到单算子）；step_trace_time Free 桶陷阱（聚合口径 + 偶发
  停等假象，判「算 vs 等」用 kernel_details 自算多流 union busy / 静默 idle）；
  kernel_details 逐算子判读（Duration 含调度等待、aiv_vec_ratio/aiv_mte2_ratio 三分
  算力/访存延迟/访存带宽、Input Shapes 核验维度）；通信归因（reduceScatter 先查接线
  再归属、MoE a2a 多引擎争跨机链路反更贵、巨型 allGather AICPU kernel 是失步症状、
  per-call 连 payload 看、跨分支谱系横比无效）；机制性归因条目（qk 打分核线性计费
  TP 切头零收益）；7 条误区清单
- **docs/vllm-service-profiling.md**：文首互补链接与「聚合与判读口径」末尾加
  分析判读文档指针
- **SKILL.md**：进阶指南新增「vLLM profiling 分析判读」条目（采集条目补互见）；
  description 补 profiling & analysis（2.2.0 漏加）

## 2.3.0 (2026-10-16)

profiling 判读与工程化增量：聚合口径、provenance 纪律、成本预估。

- **docs/vllm-service-profiling.md**：step_trace_time 修正为真实分桶字段
  （Computing / Communication / Communication(Not Overlapped) / Overlapped / Free，
  Stage 为行总计；恒等式 Stage ≈ Computing + Not Overlapped + Free，通信占比口径
  用 Not Overlapped）；注意力占比公式（FusedInferAttentionScore +
  _decode_qk_score_kernel / 单 rank 全算子时间）；rank 计算失衡口径与窗口代表性
  校验（TPOT/TPS 对独立专测）；机间步数差 ~3% 系统性偏移的声明要求；批量解析
  编排（RAW_BASE+argv 参数化禁硬编码、docker exec -d + 日志关键字判进度、
  单 rank 成功判据 op_statistic.csv、每 rank 实测约 40s）；产物目录
  profiling/{raw,parsed} 约定与 README-provenance（镜像补丁清单必记，解读前先读）；
  成本预估（单份闭环实测 60-90min）；多机同窗编排；踩坑表 11→14 条
- **docs/npu-process-cleanup.md**：新增宿主机管道 kill 容器内 PID 静默失败
  （须 `docker exec -i bash -s` 整段进容器）；npu-smi HBM 列双空格对齐的
  grep 抓法（`grep -oE "[0-9]+ */ *98304"`，分母按机型替换）
- **SKILL.md**：进阶指南 profiling 与 NPU 进程清理条目同步增补；修复 2.2.0
  漏 bump 的 frontmatter version（本次直接升至 2.3.0）

## 2.2.0 (2026-10-14)

服务级性能 profiling 专题沉淀：torch profiler 官方路线全流程与踩坑速查。

- **新增 `docs/vllm-service-profiling.md`**：拉起烘焙 `--profiler-config`（每引擎端口
  独立子目录防 rank 同名互踩）/ 直连端口 curl 启停（proxy 不转发采集端点、
  `/start_profile` 发出即采集禁当健康探测）/ generation_tokens_total 连续 4 次大增量
  判稳态段只采 ~3s / 停服核验三件事 / 离线 `torch_npu analyse()` 逐 rank 解析（msprof
  CLI 不可用；共享盘多机并发须按机器+端口分片）/ 分析七维度口诀；11 条踩坑速查表
- **SKILL.md**：新增"服务级性能 profiling"条目（触发场景 + 详见指针）

## 2.1.0 (2026-10-12)

950DT 双机 PD 分离专题沉淀：fabric 身份配置、PD 拉起排障、docker bind-mount 陷阱。

- **新增 `docs/a5-950dt-fabric-config.md`**：950DT fabric 身份三件套（hccl_rootinfo /
  hixlep→`ASCEND_LOCAL_COMM_RES` / urma_admin 活网）关系链与排查顺序；rootinfo
  逐机生成流程；静态配置与活网 EID 漂移的诊断方法；EI0004/EI0016/E19999 错误码
  速查；RPC 面绑管理网属正常设计、数据面走 UB fabric 不占 IP 端口的平面认知
- **新增 `docs/pd-disagg-bringup.md`**：PD 分离失败类别清单（占卡者→代码缺口→
  rootinfo→KV 显存→triton 严格模式→显存释放竞态）；mooncake P2P 日志解读
  （`ret=-1` 须下钻 C++ glog 行）；冒烟规则（/v1/models 核名、P 的 200 只是
  prefill ack）
- **新增 `docs/docker-bind-mount-traps.md`**：挂载不存在文件被 docker 造目录、
  overlay2 UpperDir 手术修复、`cat >` 保 inode 热更新（`cp` 不可见）
- **docs/npu-process-cleanup.md**：新增宿主机视角清点规则（`VLLM::` 大写前缀与
  `grep "vllm"` 假阴性、容器/宿主双 PID 命名空间、批量 kill 后 PID 区间误伤核对）；
  HBM 释放窗口修订为约 5~15 分钟；修复"方式三"编号重复
- **docs/vllm-ascend-build.md**：FAQ 新增 4 条（NFS 时钟偏差触发 ninja dirty、
  build_aclnn 阶段 SIGKILL 137 与降并发、pkg/ 空导致 cmake 静默回退外网下载、
  heredoc 未加引号致成功标记恒真）
- **docs/a3-chip-numbering.md**：新增 950DT 单卡单芯对照表（两代机型换算勿混用）
- **docs/vllm-service-guide.md**：404 先核 served-model-name（权重路径派生、大小写
  敏感）；PD 章节交叉引用 pd-disagg-bringup.md
- **SKILL.md**：进阶指南新增 3 条索引；经验备忘新增 3 条（wall 声明与停机记录、
  run-id/open('xb') 日志纪律、多 flavor 镜像认 ID）；维护与同步表新增 ZCode
  junction 行；版本 2.1.0
- **README.md**：补齐文档清单（此前漏 2 篇）并纳入新增文档

## 2.0.2 (2026-10-10)

hccs_ping 结果判读修正（A3 SuperPoD 实测）：假阳性陷阱与跨机语义。

- **docs/npu-roce-connectivity.md** 三条新经验：「Cmd executed successfully!」≠ ping 通
  （不可达目标照样打印，真实输出 0 packets transmitted + not start to send，判通以
  recv time 非 0 且 transmitted=received>0 为准）；同芯片并发 hccn_tool 会静默丢 ping，
  必须串行；A3 SuperPoD 每机独立 supernode 域（vnic 192.X 各机不同段，全域扫描仅本机
  16 芯真实响应），跨机 hccs_ping 不适用，跨机 RDMA 直测 RoCE eth 面（`-ip -g`/`-ping`/
  iperf，含芯片网关 `-gateway -g` 检查）
- **SKILL.md**：NPU 跨机互联检查条目同步上述三坑；版本 2.0.2

## 2.0.1 (2026-10-10)

vLLM 服务管理工作流：PD 分离拉起顺序（纯文档建议，无脚本/配置变更）。

- **docs/vllm-service-guide.md** 新增「PD 分离的拉起顺序（P/D 并行）」：P/D 引擎无相互
  启动依赖（KV 迁移首请求按需握手，启动期只向共享元数据服务独立注册），唯一前置顺序
  约束是 mooncake master 等共享依赖——P/D 应并行拉起而非串行等待；失败单侧归因、单侧
  重拉；附 kv 握手端口段撞临时端口范围导致的偶发 `Address already in use` 处置
- **SKILL.md**：vLLM 服务管理条目增补并行拉起与单侧重拉要点；版本 2.0.1

## 2.0.0 (2026-10-05)

连接范式升级：SSH 从「逐命令新建连接」改为「ControlMaster 常驻复用」。

- **新增 `docs/ssh-connection-stability.md`**：SSH 连接稳定性专项文档
  - 根因分析：网络抖动窗口只丢「新建连接」的 SYN，已建立的 TCP 流不受影响——交互终端稳、AI 代理/批量脚本逐命令建连却间歇超时
  - 配置模板：`ControlMaster auto` + `ControlPersist 8h` + `ServerAliveInterval 30`（纯客户端，服务器零改动），单条命令 ~0.8s → ~0.1s 且抖动免疫
  - 维护命令：`ssh -O check` / `ssh -O exit`，master 判死后自动重拨语义
  - 排查范式：纯 TCP 探测（nc）与 ssh 分层，区分「网络丢包」与「sshd 层拒绝」
  - 注意事项：勿全局套用（bastion/ProxyJump 场景）、MaxSessions 并发上限、换网后重建
- **SKILL.md**：经验备忘新增 ControlMaster 条目；进阶指南新增「SSH 连接稳定性」索引；连接检查表新增 `ssh -O check` 行；description 增补 connection stability
- **SKILL.md**：吸收远端修订——vllm 配套一律查 `.github/vllm-main-verified.commit`（commit id，勿按 release tag）；vllm-ascend-build.md 合并 main2main 锚点定位、serve 才暴露的配错症状、重装 `--no-deps` 等实操细节；G 区下载三坑条目
- 首个进入 CHANGELOG 的版本；1.x 历史见 git log
