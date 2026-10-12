# 950DT（A5）fabric 身份配置与 UB 网诊断

> 场景：950DT 机器上跨机 HCCL 报 EI0004/EI0016；mooncake/ascend-direct KV 传输
> 失败（`E19999: Internal error!`）；部署跨机任务前想核验 fabric 身份。

## 三份配置的关系链

950DT 的跨机通信（HCCL 集合通信、mooncake ascend-direct 传输）依赖机器的
**fabric 身份**，分散在三处，排查时三者要对得上：

| 配置 | 位置 | 谁消费 | 说明 |
|------|------|--------|------|
| HCCL ranktable | `/etc/hccl_rootinfo.json` | HCCL | `rank_list → level_list → rank_addr_list`，`addr_type=EID`；**逐机唯一**，含本机每卡的 fabric 地址 |
| UB endpoint | `/etc/hixlep/ub_endpoint_npu_{0..7}.json` | vllm-ascend | 描述各 NPU 的 UB 通信端点 |
| 活网状态 | 驱动实时表 | urma/UB 设备 | 用 `urma_admin show --brief` 查看，是唯一权威 |

**UB endpoint 文件的消费路径是个环境变量交接，容易排查走弯路**：vllm-ascend 的
`setup_ascend_local_comm_res()`（`vllm_ascend/utils.py`）在绑定设备后读取
`ub_endpoint_npu_<物理卡号>.json`，把整个 JSON 塞进环境变量
`ASCEND_LOCAL_COMM_RES`，再交给 mooncake 的 `ascend_transport.so`——**在 .so
里 `strings` 搜文件名一无所获**，从 env 侧追才对得上。

## rootinfo 的生成与安装

rootinfo 不能拷贝别的机器的（EID 是机器专属），每台自己生成：

```bash
# 容器内（需能 pip 安装）
pip install unofficial-ascend-tools
mindcluster-tools rootinfo --output /tmp/rootinfo_gen.json
# 宿主机原位写入（保 inode，见 docker-bind-mount-traps.md 规则三）
cat /tmp/rootinfo_gen.json > /etc/hccl_rootinfo.json
```

前提：宿主机 `/etc/hccl_rootinfo.json` 是**文件**不是目录（被 docker 造过目录的
先做 overlay2 手术）。两台交互的机器各自生成本机的，不要共用一份。

## 静态配置与活网可能漂移

fabric 重新编号后，`rootinfo`/`ub_endpoint` 里的 EID 段号**不会自动刷新**，而
驱动活网按新编号运行。静态文件各机自洽（本机单机任务照常跑），**跨机传输才会
暴露**。诊断顺序：

```bash
# 1. 看两台机活网 EID：同 slice（EID 中段相同）、不同节点偏移 → 链路本身通
urma_admin show --brief
#    输出形如：eid0 0000:...:0010:0000:dfd8:XXXX，link 列应全 ACTIVE

# 2. 比对静态文件里的 EID 段号与活网是否一致（不一致 = 漂移，需重新生成/修复）
grep -o 'dfd[0-9a-f]' /etc/hixlep/ub_endpoint_npu_0.json   # 静态侧抽样
```

对照实验：`export ASCEND_LOCAL_COMM_RES='{"version":"1.2"}'` 可以让
vllm-ascend 跳过 hixlep 文件内容，用于区分"文件过期"还是"其他层故障"。

**urma_admin 注意**：`show topo` 走 netlink 在部分环境失败（正常）；`eid add/del`
直接改活网状态，未经授权不要用。

## 错误码速查

| 症状 | 含义 | 处置 |
|------|------|------|
| HCCL `EI0004`（roottable 解析失败） | rootinfo 是空文件/空目录/格式坏 | 查文件是否被 docker 造目录（见 docker-bind-mount-traps.md），重新生成 |
| HCCL `EI0016`（addr 非法） | 用了**别的机器**的 rootinfo | 本机重新生成，禁止跨机拷贝 |
| 传输侧 `Failed to connect to target ... errmsg: E19999: Internal error!`（python 层只见 `ret=-1`） | URMA 层建连失败 | 按上文"静态 vs 活网漂移"诊断顺序走 |
| 宿主机 TCP 探测（`/dev/tcp/<ip>/<port>`）通但传输失败 | TCP/RPC 面正常，故障在 UB 数据面 | 别再查端口/防火墙，转 fabric 身份排查 |

## 网络平面认知（防止被表象带偏）

- mooncake transfer engine 的 **RPC 握手面**绑**默认路由网卡的 IP** + 随机端口，
  这是正常设计；日志里 `parseHostNameWithPort ... port 12001` 后接
  `P2P handshake, listening on <管理网IP>:<随机端口>` 表示先试 master、回落
  P2P 模式，不是绑错网卡。
- **数据面走 UB fabric（EID 寻址），不占任何 IP 端口**——IP 可达性与 UB 可达性
  是两个独立平面，跨机问题先分清在哪一层。
