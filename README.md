# Blue Server Toolkit v3.0.0

蓝区（Ascend NPU）远程开发服务器操作插件：**一个仓库一个插件，内含 7 个按任务
领域拆分的 skill**。日常操作由 hub（总入口 skill）处理；专项问题（NPU 进程/
跨机互联、vLLM 服务/编译/性能、裸机装机）各自触发对应 skill，按需加载。

## Skills

| skill | 覆盖 |
|-------|------|
| `blue-server-toolkit`（hub，总入口） | 日常操作（连接/代码/UT/下载/日志/容器/传文件）+ 镜像源 + SSH 稳定性 + bind-mount 陷阱 + G 区下载 + 路由表 + 安全红线 |
| `blue-npu-ops` | 单机 NPU：进程清理、HBM 释放、判断机器空闲、A3 chip 编号、算力实测 |
| `blue-npu-fabric` | 跨机互联：RoCE/hccs_ping、firewalld、950DT fabric 身份（EI0004/EI0016/E19999） |
| `blue-vllm-service` | vLLM 服务生命周期：起停、多实例、PD 分离、TP/并行度、graph 调试 |
| `blue-vllm-ascend-build` | vllm-ascend 源码编译/升级、版本配套、报错 FAQ、rsync 后 chown |
| `blue-vllm-profiling` | torch profiler 采集流程 + trace 分析判读 |
| `blue-server-provisioning` | 裸机 HDK 驱动/固件安装、start-docker 建容器、按镜像 ID 识别镜像 |

设计要点：docs 不内联进 skill，统一安装到 `~/.blue_server_toolkit/` 按需读取；
安全红线与运行时契约（指 docs/scripts 的安装位置、路径引用与同步规则）以
`templates/skill-contract.md` 为单一来源，全文复制进每个 skill
（`./check-repo.sh` 逐字节校验）；版本号只写在 `.claude-plugin/plugin.json`。

## 安装

### 前提

1. **VPN 已连通**（公司指定客户端）
2. **SSH 公钥已配置**（手动登录一次确保免密）

### 方式一：开发模式（软链安装，改仓库立即生效）

```bash
git clone <本仓库> && cd blue-server-toolkit
./link-dev.sh         # 为 Claude Code / Codex / OpenCode / ZCode 的每个 skill 建软链
./link-dev.sh --check # 验证；--unlink 删除链接；--prune-old 清理旧布局遗留链接
```

首次在会话中触发任一 blue-* skill 时，hub 会引导完成
`~/.blue_server_toolkit/config.json` 配置与 docs/scripts 安装。

### 方式二：插件市场（安装版本化快照，不随仓库更新）

- **ZCode**：Plugin Marketplace → `+` → Add Plugin Marketplace → 粘贴本仓库
  根目录路径 → Discover → 安装 Blue Server Toolkit。插件安装的 skill 以带
  插件前缀的名称 `blue-server-toolkit:<skill>` 出现。
- **Claude Code**：`claude plugin marketplace add <本仓库路径>` →
  `/plugin install blue-server-toolkit`。

> **开发软链与插件安装互斥**：软链注册的是不带前缀的 skill 名，插件注册的是
> 带前缀的 `blue-server-toolkit:<skill>` 名，两者同时存在会加载两份。装插件前
> 先 `./link-dev.sh --unlink`；保持开发模式则不装插件。

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
├── routing-acceptance.md         # 路由验收清单 21 条（改 description 后重跑）
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
├── .claude-plugin/{plugin.json,marketplace.json}  # 唯一插件清单（ZCode 也能识别该布局；依据是本机已装 ZCode 插件均为 .claude-plugin 形态，本插件实装冒烟待做）
├── skills/<name>/SKILL.md × 7                     # hub + 6 个专项 skill
├── docs/ · scripts/ · config.example.json         # docs 与 scripts（安装到 ~/.blue_server_toolkit/）
├── templates/skill-contract.md                    # 契约与红线单一来源（复制进每个 skill）
├── link-dev.sh · check-repo.sh                    # 开发模式安装脚本 / 合并前检查
└── README.md · CHANGELOG.md · LICENSE
```

### 提交前检查与版本

- 提交前必跑 `./check-repo.sh --strict`：目录结构、唯一清单、frontmatter、
  description 行数（合计 ≤50 行、触发词出现在前 250 字符内）、禁止 `../`、
  契约块与模板逐字节一致、版本号三处一致、行数上限（hub ≤400 / 专项 skill
  ≤120）、仓库整洁、ZCode 端插件安装与开发软链共存检测（Claude 端未覆盖）。
- 版本号只写在 `.claude-plugin/plugin.json`，README H1 与 CHANGELOG 最新条目
  同步同一版本号；各 skill 不带独立版本号。大特性 = 第二段 +1，小修正 =
  第三段 +1，大版本仅在作者明确指示时递增。

### 内容增长复查（每季度 + 新增专题时）

| 指标 | 阈值 | 动作 |
|------|------|------|
| hub 正文行数 | >400 | 把留在 hub 的专题独立成新专项 skill（按升格条件） |
| 任一专项 skill 行数 | >120 | 压缩摘要或拆分，不允许超限 |
| docs 总行数 | >2200 | 重新评估拆分；新 doc 默认只进路由表 |
| 单个专题的摘要行数 | >15 | 摘要已包含本应写入 doc 的内容，评估独立成 skill |
| description 合计 | >50 行 | 压缩后才允许新增专项 skill |
| 最坏情况会话加载量（PD 排障 = service+fabric+ops 正文 + docs） | >700 行 | 重跑路由验收并重新核算加载成本（基线：拆分前单 skill 版本 517 行） |

**专项 skill 升格条件（三条全部满足）**：① 至少 2 个仅该专题会命中的字面
触发词（错误码/工具名），或 1 个现有 skill 未覆盖的操作动词；② 正文控制在
120 行内；③ 重跑完整路由验收清单仍达标。

### 路由验收（修改任何 description 后重跑）

题目清单与评分规则见 `docs/routing-acceptance.md`（21 条口语化任务，含安全
红线测试句）。要点：总体准确率 ≥85%；含字面触发词的子集 100%；零/弱触发词句
一步路由到位 ≥80%；纯专项任务中 hub 被误触发（无效加载）≤20%；安全红线句不允许
任何误路由（"磁盘满"场景出现自动清理动作 = 整轮 FAIL）。不达标时按顺序合并：先
fabric 入 ops，再 build 入 service，最终保留 4 个粗粒度分组。

## License

MIT
