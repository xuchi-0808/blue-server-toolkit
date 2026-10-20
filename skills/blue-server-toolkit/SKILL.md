---
name: blue-server-toolkit
description: >-
  Use for daily ops on blue-zone remote servers: SSH connection and
  stability, code sync, UT runs, model downloads, log viewing, file transfer,
  docker pull/start/exec, image mirrors, G-zone downloads, config management;
  also the fallback router when unsure which sibling skill fits.
  触发方式：提到"同步代码""跑 UT""下模型""看日志""传文件""docker pull 慢"
  "加服务器/改配置""G 区下载""SSH 老断""磁盘满""不确定用哪个 skill"时。
  NOT for NPU HBM/process/chip, cross-machine fabric, vLLM serve/PD, source
  builds, profiling, bare-metal provisioning — load the matching blue-* skill.
  泛称词（服务器/SSH/容器/NPU）本身不是本 skill 的触发条件。
---

# Blue Server Toolkit（hub，总入口 skill）

> 本 skill 只覆盖日常操作与留在本文件的专题；专项问题先查下方路由表，加载对应的专项 skill。

## 专项路由表

| 症状 / 触发词 | 去向 |
|---|---|
| npu-smi、HBM 占用/不释放、显存占满、杀进程、进程残留、判断机器空闲、chip 编号、VISIBLE_DEVICES、算力实测 | **blue-npu-ops** |
| 跨机/多机、hccs_ping、hccn_tool、RoCE、EI0004/EI0016/E19999、ret=-1、rootinfo、UB 网、fabric、部署前连通性核验 | **blue-npu-fabric** |
| 起/停 vllm 服务、PD 分离、P/D、mooncake、load-balance proxy、TP/并行度、多服务并行、served name 404、enforce-eager、精度异常、cudagraph | **blue-vllm-service** |
| 编译/装/升级 vllm-ascend、pip install -e、bisect、setuptools、pip/编译报错关键字（Metadata generation failed 等） | **blue-vllm-ascend-build** |
| profiling、start_profile、稳态窗口、trace、算子/通信占比、step_trace、瓶颈归因、拓扑对比 | **blue-vllm-profiling** |
| 新服务器、裸机、装驱动/固件、HDK、npu-smi 不可用、建容器、start-docker、同日构建多个相似镜像、镜像 ID | **blue-server-provisioning** |
| SSH 间歇超时、批量短命令重试 | 本文「SSH 连接稳定性」节 |
| docker pull 慢/失败、镜像源切换 | 本文「常用镜像源」节 |
| 单文件挂载后读不出来、热更新挂载文件 | 本文「Docker bind-mount 陷阱」节 |
| G 区（深信服 MITM + NFS）下载模型/大文件 | 本文「G 区大文件下载」节 |

路由取舍规则：错误码/专有名词 > 通用词；表达意图的动词 > 场景名词；仍定不下来时
读本表做二次分发；排障需要更深入的内容时沿文档链接继续查
（`~/.blue_server_toolkit/docs/` 下全量可读），不要求用户重新表述；安全红线优先
于路由。

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

## Overview

远程开发服务器操作参考。提供常见操作的命令模式和辅助脚本。**配置和脚本是
工具，不是规则**——用得上就用，用不上不用。

使用本插件的前提是能通过 SSH 访问目标服务器；用户未配 SSH key 时可主动协助
生成密钥对并告知公钥放置位置。

## 首次激活（安装与同步）

检查 `~/.blue_server_toolkit/config.json`：存在则读取；不存在则向用户询问
host、user（container 可选）并创建（结构见下方配置说明）。

docs 与 scripts 的安装同步（幂等，仅 hub 执行本节；其余 skill 只检查版本标记
文件）：

```bash
# 定位仓库根目录：本 skill 目录（软链先解析）上溯两级，
# 软链安装与插件安装的目录结构一致，两种方式都能定位
SKILL_DIR="$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" <本SKILL.md所在目录>)"
ROOT="$(dirname "$(dirname "$SKILL_DIR")")"     # 须含 docs/ 与 .claude-plugin/
RT="$HOME/.blue_server_toolkit"
mkdir -p "$RT/scripts" "$RT/docs"
cp "$ROOT"/docs/*.md "$RT/docs/"
cp "$ROOT"/scripts/* "$RT/scripts/"
V="$(python3 -c "import json;print(json.load(open('$ROOT/.claude-plugin/plugin.json'))['version'])")"
printf '%s\n' "$V" > "$RT/.assets-version"
printf '%s\n' "$ROOT" > "$RT/.source-repo"
```

- 每次激活先比对 `~/.blue_server_toolkit/.assets-version` 与 plugin.json 的
  version，不一致就重拷 docs/scripts 并更新版本标记文件——运行时副本落后是
  已知的失效方式。
- 上溯两级不含 `docs/` 与 `.claude-plugin/`（skill 目录被单独拷出的情况）时，
  读 `$RT/.source-repo` 定位仓库；仍失败则提示用户 clone 本仓或安装完整插件。
- `config.json`、`config.json.bak.*`、`notes/` 是用户自己的文件，**永不触碰**。

## 配置说明

配置文件 `~/.blue_server_toolkit/config.json`（模板见仓内 config.example.json）：

```json
{
  "version": "1.0",
  "servers": [
    {
      "alias": "s1",
      "host": "192.168.1.100",
      "user": "developer",
      "port": 22,
      "container": "dev_container",
      "desc": "主开发服务器"
    }
  ],
  "default_server": "s1",
  "workspaces": {
    "task_root": "/home/developer/Tasks",
    "weights_root": "/home/developer/weights",
    "code_root": "/home/developer/Code"
  },
  "restrictions": {
    "forbidden_commands": ["sudo rm -rf /", "reboot", "pkill -9 -f python"],
    "confirm_required": ["rm -rf", "docker rm", "docker stop", "kill -9", "npu-smi set -t reset"]
  }
}
```

- `servers[].container` 可选——不设或 null 表示不用容器
- `workspaces`、`restrictions` 可选；`version` 字段仅追踪配置格式版本
- 所有字段可随时修改（用户自己改或让 AI 代改）；新增服务器 = 改 config.json，
  **不是**往本仓写 md

## 用户配置与 Skill 本体分离

本仓（公开 GitHub）只放**通用可复用知识**；个人环境信息一律放本地：

| 归属 | 位置 | 内容 |
|------|------|------|
| Skill 本体（git 仓） | 本仓 `skills/` / `docs/` | 命令模板、机型/驱动知识、排障经验 |
| 用户配置（本地） | `~/.blue_server_toolkit/config.json` | 机器清单（IP/账号/容器）、目录约定、命令限制 |
| 用户笔记（本地） | `~/.blue_server_toolkit/notes/` | 机器档案（磁盘/HBM/共享情况）、权重清单 |

**红线**：IP、hostname、机器清单、个人路径、任务状态禁止写进本仓。

## 经验备忘

以下注意事项供决策参考，非强制规则；具体以用户实际环境和反馈为准。

- **SSH 连不上**：先问 VPN 是否已连接，再逐层排查 ping → BMC 虚拟控制台 → sshd_config
- **目录权限**：服务器上 `/home/{user}/Tasks/` 等目录可能 root 属主，`mkdir -p`
  失败可用 `sudo mkdir -p`
- **大文件传输**：打包（tar/zip）后上传比散传快；传输前提醒用户关闭 PC 休眠
- **首次登录**：密码含特殊符号须用英文半角输入法；新账号等 2-3 分钟再登录；
  首次登录须改密码
- **VPN 断连**：长下载每 10 分钟 heartbeat 保活，断连重连即可，nohup 任务不受影响
- **响应超时**：服务器命令默认等待不超过 10 秒，超时立刻上报
- **长耗时操作**：编译、拉镜像、下载模型每 10 秒检查进度日志
- **进度查看**：`du -sh` 看目录大小或 `tail -n 5` 看末尾，不要 `cat` 全量日志
- **存储布局**：`/root` 分区通常较小，大文件放 `/home`；模型缓存可软链迁移
  `ln -s /home/.cache-root ~/.cache`
- **仅 HF 独有的权重走 hf-mirror 直连**：下权重优先 ModelScope；仅 HF 独有的
  才走 HF，容器内 `export HF_ENDPOINT=https://hf-mirror.com` 后 `hf download`
  直连（新版 hf 命令参数用连字符 `--local-dir`；宿主机通常没装
  huggingface_hub，在容器里执行）
- **蓝区 pip 先配全局国内源，禁止先试默认源**：pypi.org 直连是长时间挂死而非
  快速报错；配源命令见运行时契约第 2 条；SSH 隧道代理是 git/curl 等小流量备选，
  不是 pip 首选
- **蓝区代理接入（SSH 反向隧道）**：`ssh -R 7897:127.0.0.1:7897 {user}@{host}
  -f -N` 后容器内 `export HTTP_PROXY=http://127.0.0.1:7897`；隧道易断，用前查
  `ss -tlnp | grep 7897`，断了重建
- **一次只做一个动作**：缺什么只装什么，不顺手全装；每步确认退出码再做下一步
- **rsync 多源会平铺合并**：多源到同一目标时同名文件互相覆盖；每个仓单独
  rsync 到自己的子目录
- **rsync 跨 uid 传代码后容器内必须 chown**：mac 传过去 owner 是本地 uid，
  容器内 git 报 `dubious ownership`；根治 `chown -R root:root <code_dir>`
  （vllm 源码编译场景详见 blue-vllm-ascend-build）

## 命令参考

### 连接检查
| 操作 | 命令 |
|------|------|
| SSH 心跳 | `ssh -o ConnectTimeout=5 {user}@{host} "echo OK"` |
| SSH master 状态 | `ssh -O check {user}@{host}`（需 ControlMaster，见下文专题节） |
| NPU 状态 | `bash ~/.blue_server_toolkit/scripts/check-npu.sh {host} {user} [{container}]` |
| 磁盘空间 | `ssh {user}@{host} "df -h"` |

### 代码操作
| 操作 | 命令 |
|------|------|
| 创建目录 | `ssh {user}@{host} "mkdir -p {target_dir}"` |
| 克隆仓库 | `ssh {user}@{host} "git clone {repo_url} {target_dir}"` |
| 强制拉取 | `ssh {user}@{host} "cd {repo_dir} && git fetch origin && git reset --hard origin/{branch}"` |
| 切换分支 | `ssh {user}@{host} "cd {repo_dir} && git checkout {branch}"` |
| 查看状态 | `ssh {user}@{host} "cd {repo_dir} && git status"` |

### UT 运行
| 操作 | 命令 |
|------|------|
| 单文件 | `ssh {user}@{host} "cd {repo_dir} && python3 -m pytest {test_file} -v"` |
| 批量文件 | `ssh {user}@{host} "cd {repo_dir} && python3 -m pytest {file1} {file2} -v"` |
| 覆盖率 | `ssh {user}@{host} "cd {repo_dir} && coverage run -m pytest {test_file} -q && coverage report -m"` |

### 模型下载
| 操作 | 命令 |
|------|------|
| ModelScope 后台下载（优先） | `ssh {user}@{host} "cd {weights_root} && nohup modelscope download {model_id} --local_dir {target_dir} --max-workers 16 >> {target_dir}/download.log 2>&1 &"` |
| HF 后台下载（仅 HF 独有，免代理） | `ssh {user}@{host} "docker exec {container} bash -c 'export HF_ENDPOINT=https://hf-mirror.com && cd {weights_root} && nohup hf download {model_id} --local-dir {target_dir} --max-workers 16 >> {target_dir}/download.log 2>&1 &'"` |
| 查看进度 | `ssh {user}@{host} "tail -n 5 {target_dir}/download.log"` |
| 已完成大小 | `ssh {user}@{host} "du -sh {target_dir}/{model_name}"` |

### 日志查看
| 操作 | 命令 |
|------|------|
| 查看文件 | `ssh {user}@{host} "cat {log_file}"` |
| 尾部 N 行 | `ssh {user}@{host} "tail -n 100 {log_file}"` |
| 关键字搜索 | `ssh {user}@{host} "grep -n {keyword} {log_file}"` |
| 容器日志 | `ssh {user}@{host} "docker logs {container}"` |

### 容器管理
| 操作 | 命令 |
|------|------|
| 创建容器 | 机型脚本见 blue-server-provisioning |
| 查看状态 | `ssh {user}@{host} "docker ps -a \| grep {container}"` |
| 启动 | `ssh {user}@{host} "docker start {container}"` |
| 交互式进入 | `ssh -t {user}@{host} "docker exec -it {container} bash"` |
| 执行命令 | `ssh {user}@{host} "docker exec {container} bash -c '{command}'"` |
| PID 反查容器 | `bash ~/.blue_server_toolkit/scripts/who.sh {host} {user} {pid}` |

### 文件同步
| 操作 | 命令 |
|------|------|
| 上传 | `scp {local_path} {user}@{host}:{remote_path}` |
| 下载 | `scp {user}@{host}:{remote_path} {local_path}` |
| 增量同步 | `rsync -avz {local_dir} {user}@{host}:{remote_dir}` |

## 常用镜像源

vllm-ascend 镜像常用来源（拉大镜像优先直连/内网源，**禁止**把大流量导到付费外网代理）：

| 源 | 地址 | 说明 |
|----|------|------|
| 官方 | `quay.io/ascend/vllm-ascend` | 海外源，蓝区直连 ~0.2MB/s，不推荐 |
| 南大镜像 | `quay.nju.edu.cn/ascend/vllm-ascend` | 国内镜像，直连 ~18MB/s，**蓝区首选** |
| 华为内网 | `cr.rnd.huawei.com/images/vllm-ascend` | 最快（未验证）；需 rnd 内网 DNS/路由，蓝区当前 VPN 不可达 |

```bash
docker pull quay.nju.edu.cn/ascend/vllm-ascend:nightly-main-a3
docker tag quay.nju.edu.cn/ascend/vllm-ascend:nightly-main-a3 quay.io/ascend/vllm-ascend:nightly-main-a3
```

> docker daemon 若配了 systemd 代理（`/etc/systemd/system/docker.service.d/proxy.conf`），
> 所有 registry 请求都走代理；改直连内网源需临时调 NO_PROXY 并重启 dockerd
> （`live-restore=true` 时容器不中断）。详见 `~/.blue_server_toolkit/docs/image-mirrors.md`。

## SSH 连接稳定性（ControlMaster 复用）

批量短命令/AI 代理场景的 SSH 间歇超时，根因是网络抖动的时间窗口里丢掉了
「新建连接」的 SYN——用 ControlMaster 把所有命令复用到一条常驻连接（纯客户端
配置，服务器零改动）。`~/.ssh/config` 对目标网段配 `ControlMaster auto` +
`ControlPersist 8h` + `ServerAliveInterval 30`，后续 ssh/scp/rsync 全复用
（单条 ~0.8s → ~0.1s）；维护用 `ssh -O check` / `ssh -O exit`，master 判定
失效后下条命令自动重拨。

> 详见 `~/.blue_server_toolkit/docs/ssh-connection-stability.md`

## Docker bind-mount 单文件陷阱

挂载**不存在的宿主机文件**时 docker 自动造出同名空目录，容器内该路径变目录、
配置"读不出来"，症状会误导人去查应用层；修复要直接处理 overlay2 的 UpperDir。
热更新挂载文件必须 `cat >` 原位写（保 inode，运行中容器实时可见）——`cp` 会换
inode，容器看到的仍是旧内容。

> 详见 `~/.blue_server_toolkit/docs/docker-bind-mount-traps.md`

## G 区大文件下载

仅适用 G 区环境（深信服 MITM 代理 + NFS 大盘）：Python requests 关 SSL 校验；
大文件先下容器本地 /tmp、循环断点续传、校验字节数后再 mv，勿直写 NFS；
`pkill -f` 的匹配串不要与命令行里出现的路径重合，避免误杀自身。

> 详见 `~/.blue_server_toolkit/docs/gzone-download.md`

## 脚本索引

安装后位于 `~/.blue_server_toolkit/scripts/`。

| 脚本 | 用途 |
|------|------|
| check-npu.sh | NPU 状态检查：`bash ~/.blue_server_toolkit/scripts/check-npu.sh <host> <user> [container]` |
| who.sh | 宿主机 PID 反查容器：`bash ~/.blue_server_toolkit/scripts/who.sh <host> <user> <pid>` |
| init-config.sh | 配置模板初始化：`bash ~/.blue_server_toolkit/scripts/init-config.sh` |

（flops-torch.py 用法见 blue-npu-ops；start-docker-A2/A3/A5.sh 用法见 blue-server-provisioning。）

## 维护与同步

- **开发模式**：本仓是唯一源头，`./link-dev.sh` 为四个工具（Claude Code /
  Codex / OpenCode / ZCode）的每个 skill 建软链，改仓即生效；`--check` 验证、
  `--unlink` 删除链接、`--prune-old` 清理旧布局遗留的链接。
- **发布模式**：通过插件市场安装（marketplace.json 在仓库根目录）。安装的是
  版本化快照，不随仓库改动更新；更新流程 = 递增版本号 → 市场刷新 → Update。
  **开发软链与插件安装互斥**：软链注册的是不带前缀的 skill 名，插件注册的是
  带前缀的 `blue-server-toolkit:<skill>` 名，两者同时存在会加载两份；装插件前
  先 `./link-dev.sh --unlink`。
- **版本**：版本号只写在 plugin.json，README H1 与 CHANGELOG 最新条目同步同一
  版本号；`./check-repo.sh` 做三处版本号比对、契约块一致性、行数上限等检查，
  提交前必跑。
- **写回**：新情况写回对应 skill 的文档或摘要；红线或契约变更改
  `templates/skill-contract.md`，并把该块复制进全部 skill（check-repo.sh 强制
  校验）；个人环境信息只进本地 config.json / notes/。
- **内容增长复查与新增专项 skill 的条件**：见 README「Development」章节。

## 扩展

新增文档：加到 `docs/`，在所属 skill 的摘要段加一行 + 本文件路由表加一行；
暂无所属 skill 的专题先进 hub 路由表。从 hub 拆出新 skill 须满足 README 的
三条升格条件（独占触发词、正文行数上限、验收回归）。版本号：大特性 = 第二段
+1，小修正 = 第三段 +1，大版本只在作者明确指示时递增。
