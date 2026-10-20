# Blue Server Toolkit v3.0.0

蓝区（Ascend NPU）远程开发服务器操作插件：**一仓一插件，7 个按任务域拆分的 skill**。
日常操作走 hub，专项问题（NPU 进程/跨机互联、vLLM 服务/编译/性能、裸机装机）
各自触发对应 skill，按需加载。

## Skills

| skill | 覆盖 |
|-------|------|
| `blue-server-toolkit`（hub） | 日常操作（连接/代码/UT/下载/日志/容器/传文件）+ 镜像源 + SSH 稳定性 + bind-mount 陷阱 + G 区下载 + 路由表 + 安全红线 |
| `blue-npu-ops` | 单机 NPU：进程清理、HBM 释放、判机空闲、A3 chip 编号、算力实测 |
| `blue-npu-fabric` | 跨机互联：RoCE/hccs_ping、firewalld、950DT fabric 身份（EI0004/EI0016/E19999） |
| `blue-vllm-service` | vLLM 服务生命周期：起停、多实例、PD 分离、TP/并行度、graph 调试 |
| `blue-vllm-ascend-build` | vllm-ascend 源码编译/升级、版本配套、报错 FAQ、rsync-chown |
| `blue-vllm-profiling` | torch profiler 采集管线 + trace 分析判读 |
| `blue-server-provisioning` | 裸机 HDK 驱动/固件安装、start-docker 建容器、镜像 ID 纪律 |

设计要点：docs 永不内联进 skill，统一安装到 `~/.blue_server_toolkit/` 懒加载；
安全红线与运行时契约单源于 `templates/skill-contract.md`、全文复制进每个 skill
（`./check-repo.sh` 逐字节校验）；版本单源于 `.claude-plugin/plugin.json`。

## 安装

### 前提

1. **VPN 已连通**（公司指定客户端）
2. **SSH 公钥已配置**（手动登录一次确保免密）

### 方式一：开发态（软链，改仓即生效）

```bash
git clone <本仓> && cd blue-server-toolkit
./link-dev.sh        # 为 Claude Code / Codex / OpenCode / ZCode 建逐 skill 软链
./link-dev.sh --check # 验证；--unlink 拆链；--prune-old 清旧形态链接
```

首次在会话中触发任一 blue-* skill 时，hub 会引导完成
`~/.blue_server_toolkit/config.json` 配置与 docs/scripts 安装。

### 方式二：插件市场（版本化快照，不热更）

- **ZCode**：Plugin Marketplace → `+` → Add Plugin Marketplace → 粘贴本仓根路径 →
  Discover → 安装 Blue Server Toolkit。安装态 skill 以
  `blue-server-toolkit:<skill>` 限定名出现。
- **Claude Code**：`claude plugin marketplace add <本仓路径>` →
  `/plugin install blue-server-toolkit`。

> **开发链与插件安装互斥**：裸名 skill 与插件限定名是不同加载键，同机会双载。
> 装插件前先 `./link-dev.sh --unlink`；保持开发态则不装插件。

## 配置

`~/.blue_server_toolkit/config.json`（模板 `config.example.json`）。个人环境信息
（IP/机器清单/任务状态）只进本地 config 与 `notes/`，**永不入仓**。

## Scripts & Docs

安装后位于 `~/.blue_server_toolkit/`：

| 脚本 | 用途 |
|------|------|
| `scripts/check-npu.sh` | 远程 NPU 状态检查 |
| `scripts/flops-torch.py` | A3 算力实测与机型判定（容器内单 die fp16 matmul → 560T/752T） |
| `scripts/who.sh` | 宿主机 PID 反查所属 Docker 容器 |
| `scripts/init-config.sh` | 配置模板初始化 |
| `scripts/start-docker-A2.sh` / `A3` / `A5` | 机型容器创建（用法见 blue-server-provisioning） |

```
docs/
├── a3-chip-numbering.md          # A3 芯片编号 + 950DT 单芯对照（blue-npu-ops）
├── a5-950dt-fabric-config.md     # 950DT fabric 身份与 UB 网诊断（blue-npu-fabric）
├── docker-bind-mount-traps.md    # bind-mount 单文件陷阱与热更新（hub）
├── graph-debugging.md            # Graph 模式调试（blue-vllm-service）
├── gzone-download.md             # G 区大文件下载（hub）
├── hdk-installation.md           # 裸机驱动安装（blue-server-provisioning）
├── image-mirrors.md              # 镜像源与拉取（hub）
├── npu-process-cleanup.md        # NPU 进程清理与 HBM 释放（blue-npu-ops）
├── npu-roce-connectivity.md      # NPU 跨机互联检查（blue-npu-fabric）
├── pd-disagg-bringup.md          # PD 分离拉起与排障（blue-vllm-service）
├── ssh-connection-stability.md   # SSH 连接稳定性（hub）
├── vllm-ascend-build.md          # vllm-ascend 源码编译（blue-vllm-ascend-build）
├── vllm-profiling-analysis.md    # profiling 分析判读（blue-vllm-profiling）
├── vllm-service-guide.md         # vLLM 服务管理（blue-vllm-service）
└── vllm-service-profiling.md     # 服务级性能 profiling 采集（blue-vllm-profiling）
```

## Development

### 目录结构

```
blue-server-toolkit/
├── .claude-plugin/{plugin.json,marketplace.json}  # 唯一插件清单（ZCode 兼容识别）
├── skills/<name>/SKILL.md × 7                     # hub + 6 专项
├── docs/ · scripts/ · config.example.json         # 共享资产（安装到 ~/.blue_server_toolkit/）
├── templates/skill-contract.md                    # 契约+红线单源（复制进每个 skill）
├── link-dev.sh · check-repo.sh                    # 开发态安装器 / 合入门禁
└── README.md · CHANGELOG.md · LICENSE
```

### 提交门禁与版本

- 提交前必跑 `./check-repo.sh --strict`：仓形、单一清单、frontmatter、description
  预算（合计 ≤50 行、触发词前 250 字符）、`../` 零容忍、契约块与单源逐字节一致、
  版本三镜像、行数预算（hub ≤400 / spoke ≤120）、卫生、开发链/插件互斥。
- 版本单源 `.claude-plugin/plugin.json`，README H1 与 CHANGELOG 头条镜像同一号；
  各 skill 不带独立版本号。大版本仅作者指示时 bump。

### 增长检查点（每季度 + 新增专题时）

| 指标 | 阈值 | 动作 |
|------|------|------|
| hub body 行数 | >400 | 自留专题升格 spoke（走升格门） |
| 任一 spoke 行数 | >120 | 摘要瘦身或拆分，禁止"先超着" |
| docs 总行数 | >2200 | 重跑拆分分析；新 doc 默认只进路由表 |
| 单专题摘要行数 | >15 | 摘要已在替 doc 干活，评估升格 |
| description 合计 | >50 行 | 压缩后才允许新 spoke |
| 最坏会话加载（PD 排障 = service+fabric+ops + docs） | >700 行 | 重跑验收 + 经济账（基线：旧单体 517） |

**spoke 升格门（三条全过）**：① ≥2 个独占字面量触发词或一个未覆盖的工作流动词；
② body 压进 120 行；③ 验收清单整体回归仍达标。

### 路由验收（改任何 description 后重跑）

21 条口语任务（含零触发词句"帮我看看这个起不来"、安全门句"磁盘满了"）：总准确
≥85%；字面量子集 100%；零/弱词 1 跳到达 ≥80%；纯专项任务的 hub 无效共触发
≤20%；安全门零容忍（磁盘满出现自动清理 = 整轮 FAIL）。不达标降级阶梯：合并
fabric→ops → build→service → 4 粗组地板。

## License

MIT
