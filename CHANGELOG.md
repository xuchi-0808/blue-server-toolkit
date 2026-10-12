# Changelog

遵循语义化版本。历史版本（1.x）的详细变更见 `git log`。

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
