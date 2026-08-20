# NPU 跨机互联检查（多机 PD/MC2 前置）

多机 PD 分离、MC2 等场景的跨机数据面走 NPU RDMA（非主机以太网，主机互 ping 通不算数），部署前先实测 NPU RoCE 互通。
原文兜底：vllm-ascend 仓 `docs/source/tutorials/features/pd_disaggregation_mooncake_multi_node.md`（Verify Multi-Node Communication Environment 节）。

## 检查方法

```bash
# 1. 每台机器取 NPU0 的 RoCE IP（A3 看 vnic；A2 改用 -ip -g）
hccn_tool -i 0 -vnic -g

# 2. 本机 NPU0 ping 对端 IP，输出 "This pkt ping success" 即通；卡住/超时即不通
hccn_tool -i 0 -hccs_ping -g address <对端IP>    # A3
hccn_tool -i 0 -ping -g address <对端IP>        # A2

# 3. TLS 开关需各机一致
hccn_tool -i 0 -tls -g | grep switch
```

## 坑

- `hccn_tool -i N -link -g` 的 link status（DOWN）、net_health（Init/Fault）在部分环境**失真**：整批机器全报 DOWN 但 hccs_ping 实际全通。判断互联以 hccs_ping 实测为准，**勿因 link DOWN 判物理不通**。
- **主机 ping 通 ≠ 端口通**：部分机器 firewalld 开着重载规则，INPUT 只放 22，跨机 TCP（分布式通信端口）全被 reject。跨机场景先 `systemctl is-active firewalld`，active 则停；端口级验证用 `timeout 3 bash -c "echo > /dev/tcp/<IP>/<PORT>"`。
- ping 通 ≠ PD 一定通：传输层仍失败时，查容器是否挂载 `/etc/hccn.conf`、防火墙、路由等配置层问题。
