---
name: blue-vllm-service
description: >-
  Use for the vLLM-on-Ascend service lifecycle: start/stop vllm serve in
  containers, health checks, multi-service port/chip layout, launch params,
  P/D disaggregation bring-up (mooncake, load-balance proxy), TP/parallelism
  planning, graph-mode debugging.
  触发：起服务/停服务、vllm serve 启动、PD 分离、P/D、mooncake、proxy、TP、
  并行度、多服务并行、served name 404、enforce-eager、精度异常、cudagraph。
  Not for 源码编译 (blue-vllm-ascend-build)、profiling (blue-vllm-profiling)、
  单机 NPU 清理 (blue-npu-ops)。
---

# Blue vLLM Service（服务生命周期与排障）

> 本 skill 只覆盖 vLLM 服务的启动/停止/并行/排障；源码编译 → blue-vllm-ascend-build，性能采集与判读 → blue-vllm-profiling，日常操作 → hub（blue-server-toolkit）路由表。

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

## vLLM 服务管理

后台启动用 `docker exec -d`，健康检查用 `curl localhost:<port>/v1/models`，
停止服务用 `kill -9 <PID>`（从 npu-smi info 获取，kill 前需用户确认）。拉起
服务的 cwd 不要在 vllm 代码仓内（代码仓目录与 pip 安装的 vllm 包同名会冲突）。
A3 可同时跑 4 个 TP4 服务（端口 8000-8003，各用独立 chip 组）。

**PD 分离验证的请求必须打 load-balance proxy**——直打 D 端口时 D 会本地
prefill、P 收不到请求，验证不到真实分离链路（vllm-ascend
examples/disaggregated_prefill_v1 自带 proxy 脚本）。**P/D 两端无相互启动
依赖**：共享依赖（mooncake master 等）先起，之后 P/D 并行拉起；失败的一侧
单独重拉；kv 握手端口偶尔撞上临时端口范围、报 `Address already in use`，
重拉即可。

> 详见 `~/.blue_server_toolkit/docs/vllm-service-guide.md`

## PD 分离拉起与排障

失败类别清单按排查优先级组织：占卡者 → 上游代码缺口 → rootinfo/fabric →
max-model-len 超 KV 显存 → triton 严格模式
（`TRITON_ALLOW_NON_CONSTEXPR_GLOBALS=1`）→ 显存释放竞态（kill 后约 15 分钟
才回到基线）。mooncake P2P 日志解读（随机握手端口正常、`Delaying free` 含义、
`ret=-1` 要到 C++ 层的 glog 日志行里找真正的错误码）；冒烟先请求
`/v1/models` 核对模型名（served name 从权重路径派生、大小写敏感），proxy 把
请求同时发 P 和 D——**P 的 200 只是 prefill 确认，回答来自 D**。

> 详见 `~/.blue_server_toolkit/docs/pd-disagg-bringup.md`

## TP ↔ 卡数速查（A3）

A3 单卡双芯：chip ID = NPU号 × 2 + 芯片序号，`ASCEND_RT_VISIBLE_DEVICES` 用
全局 chip ID（0-15）。TP4 = 4 chip = 2 张 NPU；TP8 = 8 chip = 4 张 NPU。
950DT（A5）单卡单芯无 ×2 换算。完整对照表：
`~/.blue_server_toolkit/docs/a3-chip-numbering.md`（属 blue-npu-ops）。

## Graph 模式调试

精度/行为异常时，先加 `--enforce-eager` 排除 graph capture 影响：问题消失 →
graph 相关（如 Python property 被静态化）；问题仍在 → 非 graph。aclgraph 下
打印 tensor 用 `torch_npu.print_npugraph_tensor()`。

> 详见 `~/.blue_server_toolkit/docs/graph-debugging.md`

## 相关文档

| 症状 | 去向 |
|------|------|
| 占卡者清理、kill 后 HBM 不回、Free memory 不足 | `~/.blue_server_toolkit/docs/npu-process-cleanup.md`（属 blue-npu-ops） |
| EI0004/EI0016、E19999、跨机 ret=-1 | `~/.blue_server_toolkit/docs/npu-roce-connectivity.md`、`a5-950dt-fabric-config.md`（属 blue-npu-fabric） |
| rootinfo 挂载读取异常 | hub「Docker bind-mount 陷阱」节 |
| 带采集参数的拉起、稳态窗口 | blue-vllm-profiling |
