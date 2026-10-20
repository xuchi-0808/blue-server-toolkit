---
name: blue-npu-fabric
description: >-
  Use for cross-machine NPU data-plane and fabric identity: hccn_tool /
  hccs_ping RoCE checks and false positives, firewalld host-TCP blocking,
  950DT (A5) rootinfo / ub_endpoint / urma_admin, EID drift.
  触发：跨机/多机、hccs_ping、hccn_tool、RoCE、EI0004/EI0016/E19999、
  ret=-1、rootinfo、UB 网、fabric、部署前连通性核验。Not for 单机 HBM/进程
  (blue-npu-ops)、vLLM 服务逻辑 (blue-vllm-service)。
---

# Blue NPU Fabric（跨机互联与 fabric 身份）

> 本 skill 只覆盖跨机 NPU 通信链路诊断；单机资源问题 → blue-npu-ops，日常操作 → hub（blue-server-toolkit）路由表。

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

## NPU 跨机互联检查（RoCE）

多机 PD/MC2 的跨机数据走 NPU RDMA，主机之间互 ping 通不算数。检查：
`hccn_tool -i 0 -vnic -g` 取 IP → `hccn_tool -i 0 -hccs_ping -g address
<对端IP>` 实际测试（A2 用 `-ping`）；TLS 配置各机须一致。

- **坑**：`-link -g` 报 DOWN 在部分环境是误报，勿据此判断物理链路不通；
  hccs_ping 只覆盖 NPU 侧网络，PD 的 dp-rpc/proxy 走主机侧 TCP——跨机前每台
  `systemctl is-active firewalld`，查到 active 必须停掉（默认 INPUT 只放 22，
  跨机 TCP 全被 reject；firewalld 状态会漂移，每次跨机前重查，勿沿用历史
  结论）。
- **坑**（A3 SuperPoD）：判断连通必须看 `N packets transmitted, N received`
  且 recv time 非 0——打不通的目标照样在结尾打印 "Cmd executed successfully!"
  （真实输出 0 packets + not start to send），grep "success" 全是假阳性；同一
  芯片并发跑 hccn_tool 会让 ping 静默不启动，探测必须串行；A3 SuperPoD 每机
  自成独立的 supernode 域（vnic 192.X 各机不同段，全网段扫描只有本机 16 芯
  真实响应），跨机 hccs_ping 本就不适用，跨机 RDMA 直接测 RoCE 以太网口
  （`-ip -g`/`-ping`/iperf，并查 `-gateway -g`）。

> 详见 `~/.blue_server_toolkit/docs/npu-roce-connectivity.md`

## 950DT fabric 身份与 UB 网诊断（A5）

950DT 跨机通信（HCCL / mooncake ascend-direct）依赖三份 fabric 身份配置：
`/etc/hccl_rootinfo.json`（**每台机器唯一**，mindcluster-tools 生成，拷贝其他
机器的文件必报 EI0016）、`/etc/hixlep/ub_endpoint_npu_*.json`（经环境变量
`ASCEND_LOCAL_COMM_RES` 交给 mooncake——该文件名在 .so 里搜不到，别在 .so
里找）、运行时网络状态（`urma_admin show --brief`）。静态文件与运行时 EID 段号
漂移时，跨机传输报 `E19999: Internal error!` 而 python 层只见 `ret=-1`；TCP
探测通 ≠ UB 网通，两条链路相互独立。

> 详见 `~/.blue_server_toolkit/docs/a5-950dt-fabric-config.md`

## 相关文档

| 症状 | 去向 |
|------|------|
| rootinfo 挂进容器读不到 / 热更新身份文件 | hub「Docker bind-mount 陷阱」节 + `~/.blue_server_toolkit/docs/docker-bind-mount-traps.md` |
| PD 分离失败清单（占卡/显存竞态等非 fabric 类别） | `~/.blue_server_toolkit/docs/pd-disagg-bringup.md`（属 blue-vllm-service） |
| 单机 HBM 占用、进程清理 | `~/.blue_server_toolkit/docs/npu-process-cleanup.md`（属 blue-npu-ops） |
