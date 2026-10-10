# NPU 跨机互联检查（多机 PD/MC2 前置）

多机 PD 分离、MC2 等场景的跨机数据面走 NPU RDMA（非主机以太网，主机互 ping 通不算数），部署前先验证 NPU RoCE 互通。
注意 PD 业务有**两条网络面**：KV 传输走 NPU RoCE（下方 1-3 步覆盖），data-parallel RPC / proxy / 服务端口走**主机 TCP**（第 4 步覆盖）；hccs_ping 通过不代表主机 TCP 端口可达。
原文兜底：vllm-ascend 仓 `docs/source/tutorials/features/pd_disaggregation_mooncake_multi_node.md`（Verify Multi-Node Communication Environment 节）。

## 检查方法

```bash
# 1. 每台机器取 NPU0 的 RoCE IP（A3 看 vnic；A2 改用 -ip -g）
hccn_tool -i 0 -vnic -g

# 2. 本机 NPU0 ping 对端 IP。判通看 "recv seq ... time = <非0>us" 且
#    "N packets transmitted, N received"（N>0）——勿 grep "success"（假阳性，见注意事项）
hccn_tool -i 0 -hccs_ping -g address <对端IP>    # A3；注意 SuperPoD 上该命令只在单机 supernode 域内有效
hccn_tool -i 0 -ping -g address <对端IP>        # A2 / A3 SuperPoD 跨机走芯片 eth 面时改用此命令

# 3. TLS 开关需各机一致
hccn_tool -i 0 -tls -g | grep switch

# 4. 主机 TCP 面：firewalld active 时跨机 TCP 全被 reject（PD 的 dp-rpc / proxy / 服务端口都在这条面上）
systemctl is-active firewalld        # 每台都查；输出 active → systemctl stop firewalld
```

## 注意事项

- `hccn_tool -i N -link -g` 的 link status（DOWN）、net_health（Init/Fault）在部分环境**失真**：整批机器全报 DOWN 但 hccs_ping 实际全通。判断互联以 hccs_ping 结果为准，**勿因 link DOWN 判物理不通**。
- **主机 ping 通 ≠ 端口通**：部分机器 firewalld 开着重载规则，INPUT 只放 22，跨机 TCP（分布式通信端口）全被 reject。跨机场景先 `systemctl is-active firewalld`，active 则停；端口级验证用 `timeout 3 bash -c "echo > /dev/tcp/<IP>/<PORT>"`。多台机器出厂即 active，勿假设个别机器；firewalld 状态会漂移（他人操作/重启可改变），**每次多机测试前都查，勿沿用历史结论**；hccs_ping 通过不覆盖此项。
- ping 通 ≠ PD 一定通：传输层仍失败时，查容器是否挂载 `/etc/hccn.conf`、防火墙、路由等配置层问题。
- **hccs_ping 判读——"Cmd executed successfully!" ≠ ping 通（2026-10-10 A3 SuperPoD 实测）**：无论目标可不可达，命令收尾都打印这个状态字；对不可达目标真实输出是 `0 packets transmitted, 0 received`、`recv seq N, time = 0.000us`、`This pkt ping not start to send!`。判通唯一标准是 `recv seq` 行 time 非 0 且 transmitted=received>0；grep "success" 会把所有失败全判成通。
- **同一芯片并发跑 hccn_tool 会让 ping 静默不启动**：用 xargs -P 之类并行扫段时大量 "not start to send"，结果不可信。同一 chip 的探测必须串行；扫段任务放后台日志再收结果，不要阻塞会话。
- **A3 SuperPoD 每机一个独立 supernode 域，跨机 hccs_ping 不适用**：vnic 地址形如 `192.X.2.y / 192.X.3.z`（偶数芯在 .2、奇数芯在 .3），第二段 X 每机独立（如 192.168 / 192.44 / 192.27），单机 16 芯占满一段连续第四字节；全域扫段只有本机 16 芯真实响应。跨机 RDMA 连通要直测 **RoCE eth 面**：`hccn_tool -i N -ip -g` 取芯片 eth IP → `hccn_tool -i N -ping -g address <对端eth IP>` 或 iperf/RDMA 打流；顺带查芯片网关 `hccn_tool -i 0 -gateway -g`（跨网段回包必须有网关，无网关=跨子网必死）。
