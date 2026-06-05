# Blue Server Handler

一套通用 AI skill，用于操作远程开发服务器（蓝区服务器）。覆盖 80% 日常高频操作：连接检查、代码同步、UT 运行、模型下载、日志查看、容器管理、文件传输。

## Features

- **不绑定机器**——所有服务器信息通过配置文件管理，改配置就能换服务器
- **不绑定 AI 工具**——纯 Markdown + bash 脚本，Claude Code、TRAE 等任何 AI 工具都能用
- **Prompt 为主 + 脚本为辅**——AI 处理灵活场景，脚本覆盖高频操作
- **自安装**——SKILL.md 在首次激活时自动完成安装和配置引导

## Quick Start

### 1. 安装

#### 推荐方式：让 AI 帮你安装（无需手动找路径）

建议先 clone 本仓，再让 AI 读取本地目录完成安装：

```text
我正在使用 Claude Code（或其他工具名），请阅读 /home/xuchi/Documents/Code/AgentSkills/blue-server-toolkit/ 的内容，帮我把这个 skill 正确安装。安装完成后告诉我如何使用。
```

把上面这段话中的路径改成你的实际路径，AI 就会：
1. 读取 SKILL.md 了解技能内容
2. 自动判断当前工具的技能目录位置
3. 完成安装
4. 引导你进行首次配置

#### 备选：手动安装

| Tool | Skills 目录 |
|------|-------------|
| Claude Code | `~/.claude/skills/blue-server-toolkit/SKILL.md` |
| OpenClaw | 查阅工具文档中 skills 配置路径 |
| Codex CLI | 查阅工具文档中 skills 配置路径 |
| 其他工具 | 将 `SKILL.md` 放到工具加载 skills 的目录 |

手动安装时，把 `SKILL.md` 放进对应目录即可。首次激活后 AI 会自动完成后续设置。

### 2. 启动

打开你的 AI 工具，激活这个 skill。AI 会自动：

1. 检查并安装辅助脚本到 `~/.blue_server_handler/`
2. 引导你填写服务器信息
3. 配置完成，开始使用

### 3. 使用示例

```
你：检查一下服务器的 NPU 状态
AI：好的，请告诉我你的服务器信息（IP、用户名、容器名）？
你：IP 是 192.168.1.100，用户名 dev，容器 dev_container
AI：已记录。正在检查...
     ✅ SSH 可达
     ✅ 容器运行中
     ✅ NPU 状态正常（8 芯片在线）
```

```
你：帮我拉一下 main 分支的最新代码
AI：好的，在哪个目录下操作？
你：/home/dev/Tasks/A00272/MindIE-LLM
AI：正在拉取...
     当前分支：main
     最新 commit：abc1234 fix: ...
     工作区干净 ✅
```

## Configuration

配置文件位置：`~/.blue_server_handler/config.json`

AI 会在首次激活时引导你完成配置。你随时可以直接告诉 AI 修改配置：

- "帮我加一台新服务器 S2"
- "S1 的 IP 改成了 10.0.0.5"
- "把默认服务器改成 S2"

详细配置字段说明见 [SKILL.md](SKILL.md) 的配置说明章节。

## Scripts

辅助脚本首次激活时自动安装到 `~/.blue_server_handler/scripts/`：

| Script | Description |
|--------|-------------|
| `check-npu.sh` | 远程 NPU 状态检查 |
| `init-config.sh` | 配置模板初始化 |
| `start-docker.sh` | 创建 Docker 容器（含 NPU 设备映射） |

## Development

### 目录结构

```
blue-server-toolkit/
├── SKILL.md              # 唯一需要分发的文件（内含内嵌脚本代码块）
├── README.md             # 本文件
├── LICENSE
├── .gitignore
├── config.json           # 配置模板（完整字段，与 SKILL.md 保持一致）
└── scripts/              # 脚本源码（与 SKILL.md 代码块保持一致）
```

## License

MIT
