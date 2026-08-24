# NPU 进程清理与 HBM 释放

> 踩坑日期：2026-06-17
> 场景：S3（A3 机器）上切换 vLLM 服务时，杀进程后 HBM 不释放

## 问题现象

在容器内 `pkill` 掉 vLLM 进程后，`npu-smi info` 显示 NPU 上没有进程了（`No running processes found`），但 HBM-Usage 仍占 47GB/65GB。重新拉起服务时报：

```text
ValueError: Free memory on device (17.87/61.27 GiB) on startup is less than desired GPU memory utilization (0.95, 58.21 GiB)
```

## 根因

`pkill -9` 强杀 Python 进程，进程没有机会执行 cleanup 逻辑（释放 HCCL communicator、释放 NPU HBM 显存等），导致驱动层面的显存成为孤儿。Docker `restart` 容器也没用——HBM 归 NPU 驱动管，不归容器的 cgroup 管。

## 错误做法（别学我）

| 步骤 | 命令 | 结果 |
|------|------|------|
| 1 | `pkill -f "vllm serve"` | 只杀了主进程，worker 子进程还在 |
| 2 | `pkill -9 -f python` | 暴力杀所有 python，**HBM 成为孤儿** |
| 3 | `docker restart xc_vllm_A00280` | 容器重启但 NPU HBM 不归容器管 |

## 正确做法

### 方式一：Ctrl+C 优雅退出（首选）

在启动 `vllm serve` 的终端按 `Ctrl+C`，vLLM 的 signal handler 会自动释放 HCCL communicator 和 HBM 显存。等一会确认进程完全退出即可。

### 方式二：精准 kill NPU 卡上的进程（标准做法）

**核心认知（重要）**：`kill -9` NPU 卡上的进程 pid（`npu-smi info` 进程表里那个 Process id）后，**CPU 侧的相关进程（主进程、EngineCore 等）会自然级联终止**，HBM 随之释放。不需要再去 CPU 侧找主进程 kill，也不需要 `pkill -f python`。

```bash
# 1. 查看各 NPU 上的进程 PID
npu-smi info
#    底部进程表形如：
#    | NPU  Chip | Process id | Process name | Process memory |
#    | 0    0   | 818449     | VLLMWorker_TP| 24883          |
#    | 0    0   | 2199895    | VLLMEngineCor| 3253           |
#    ...

# 2. 把要清理的卡上的 Process id 全部列出来，一次 kill -9
kill -9 818449 2199895 818450 ...
# CPU 侧的 vllm 主进程会随之退出，HBM 自动释放
```

> 这比"方式一 Ctrl+C"更直接（不用找到启动终端），比"pkill -9 -f python"更安全（不会误伤其他用户的 python 进程）。判断要 kill 哪些 pid：认准 `npu-smi info` 进程表里属于目标服务（VLLMWorker/VLLMEngineCore）的 Process id，**不要凭进程名 pkill**。

### 方式三：等待驱动 GC

如果已经强杀了，**等几分钟**。NPU 驱动有 GC 机制，会自动回收孤儿显存。实测约 5~10 分钟后释放。

### 方式三':`docker stop` 容器（最省心，2026-06-20 验证）

如果服务是跑在容器里（不是裸机），**直接 `docker stop <容器名>` 即可**——容器内所有进程被终止后，NPU 驱动会**自动回收 HBM**，无需手动 reset、无需额外等待步骤（通常几十秒内占用就回落）。这是切服务/换容器时最干净的做法：

```bash
docker stop xc_vllm_A00280   # 停容器 = 杀掉里面全部进程 = HBM 自动释放
```

> 区别于方式二的 `pkill -9`：`pkill` 是在容器**内部**强杀单个 Python 进程，进程没机会 cleanup → 孤儿显存要等驱动 GC。而 `docker stop` 是杀整个容器（含全部 worker 子进程），驱动会把这个容器占用的 NPU 资源整体回收，因此**不需要等 GC、不需要 reset**。判断标准：确认该 HBM 是不是属于"某个容器"——npu-smi 进程表里的 PID 用 `bash ~/.blue_server_toolkit/scripts/who.sh {host} {user} {pid}` 反查所属容器；是容器就 `docker stop`，是裸机进程才走方式二/三/四。

### 方式四：芯片级重置（终极手段）

```bash
# 重置指定 NPU 的指定 chip（危险！确认该 NPU 上无活跃进程后再用）
npu-smi set -t reset -i <npu_id> -c <chip_id>
```

## 教训

- **不要 `pkill -9 -f python`（模糊匹配），精准 `kill -9 PID` 是标准流程**
- HBM 释放是异步的，杀完进程后等几分钟再拉新服务
- 如果急着重置，用 `npu-smi set -t reset`，不要改服务配置来绕过显存不足
