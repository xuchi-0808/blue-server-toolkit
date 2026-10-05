# SSH 连接稳定性（ControlMaster 连接复用）

批量执行大量短命令（AI 代理逐命令调用、批量巡检脚本）时，每条命令各建一条 SSH 连接。
网络抖动窗口只丢「新建连接」的 SYN，**已建立的 TCP 流不受影响**——这就是为什么
交互终端的长连接一直稳、而逐命令新建连接的自动化间歇超时。解法：所有命令复用一条
常驻 master 连接，把「反复过抖动窗口」变成「只在建流那一刻过一次」。

## 配置（纯客户端，服务器零改动）

`~/.ssh/config` 按目标网段追加（替换为实际网段）：

```
Host 192.168.100.*
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h-%p
  ControlPersist 8h
  ServerAliveInterval 30
  ServerAliveCountMax 6
```

| 字段 | 作用 |
|------|------|
| `ControlMaster auto` | 首条连接自动成为 master，后续命令自动复用 |
| `ControlPath ~/.ssh/cm-%r@%h-%p` | master socket 路径（按 用户@主机-端口 区分） |
| `ControlPersist 8h` | 命令退出后 master 常驻 8 小时（核心：模拟终端长连接） |
| `ServerAliveInterval 30` × `CountMax 6` | ~3 分钟静默判死；死后**下一条命令自动重拨**，无需人工干预 |

效果实测：单条命令 ~0.8s（新建连接）→ ~0.1s（复用），且抖动窗口免疫。
scp / rsync 走同一 ControlPath 自动复用，无需额外配置。

## 维护与排查

```bash
ssh -O check root@{host}   # master 状态（正常输出 Master running (pid=...)）
ssh -O exit root@{host}    # 主动断掉，下条命令重拨（服务器重启/换网后用）
ls ~/.ssh/cm-*             # 列出现存 master socket
```

- master 在抖动中死后**自动重拨**，但半死 socket 偶发残留（表现为所有新命令卡住）→ `ssh -O exit` 清掉重连
- 换网 / 换 VPN 出口后 master 大概率已死但未判定期满 → 同上，先 `-O exit`
- 判断「master 问题还是网络问题」：`ssh -O check` 通但命令超时 = 网络/对端问题；`-O check` 本身失败 = master 已死

## 排查范式：先分层再动手

连接不稳定时先区分「网络路径丢包」还是「sshd 层拒绝」，避免盲目重试：

```bash
# 1. 纯 TCP 探测（不涉及 sshd），连续多次看丢包模式
for i in $(seq 1 8); do nc -z -G 5 {host} 22 >/dev/null 2>&1 && echo TCP_OK || echo TCP_FAIL; sleep 2; done

# 2. TCP 全通但 ssh 间歇失败 → sshd 层（MaxStartups/fail2ban/UseDNS）
#    TCP 也间歇失败 → 网络路径问题（抖动窗口），ControlMaster 是正解
ssh -v -o ConnectTimeout=10 root@{host} true 2>&1 | tail -5
```

## 注意事项

- 配置按网段收敛（`Host 192.168.100.*`），**勿全局套用**：经 bastion/ProxyJump 的主机复用语义不合适
- 复用后所有会话共享一条 TCP 连接，受 sshd `MaxSessions`（默认 10）限制——**高并发并行调用**（>10 同时通道）会表现为新命令卡住；并行度高的场景错峰或分拆 master
- `ControlPersist` 期间服务器侧是一条长连接，服务器重启/sshd 重载后 master 必死，`-O check` 确认后 `-O exit` 重建
- socket 文件在客户端 `~/.ssh/` 下，多工具（终端 + AI）共享同一 master，互不干扰
