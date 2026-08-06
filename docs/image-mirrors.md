# 镜像源与拉取指南

## 常用镜像源

| 源 | 镜像地址 | 实测（197 蓝区直连） | 说明 |
|----|----------|---------------------|------|
| 官方 quay | `quay.io/ascend/vllm-ascend` | ~0.2MB/s | 海外 CDN（us-east-1），蓝区直连基本不可用 |
| 南大镜像 | `quay.nju.edu.cn/ascend/vllm-ascend` | ~18MB/s | 匿名可拉，与官方同 digest，**蓝区推荐** |
| 华为内网 | `cr.rnd.huawei.com/images/vllm-ascend` | 未测通 | 同事反馈最快；需 rnd 内网 DNS/路由，蓝区当前 VPN 不可达 |

> 以上测速为 2026-08-06 在 192.168.13.197（s3）实测；`quay.nju.edu.cn` 通过 `tags/list` 匿名 API 确认包含 `nightly-main-a3` 等 tag。

## 用法

```bash
# 从南大镜像拉取（蓝区直连推荐）
docker pull quay.nju.edu.cn/ascend/vllm-ascend:nightly-main-a3

# 重打官方 tag，方便后续命令沿用 quay.io 命名
docker tag quay.nju.edu.cn/ascend/vllm-ascend:nightly-main-a3 quay.io/ascend/vllm-ascend:nightly-main-a3

# 华为内网源（cr.rnd.huawei.com 是 Harbor，images 为项目名）
# docker pull cr.rnd.huawei.com/images/vllm-ascend:nightly-main-a3
```

同一镜像在不同源之间切换时，已下载 layer 按 digest 缓存可复用，不会重复下载。

## 已知坑

### 1. docker daemon 配了 systemd 代理

部分蓝区机器在 `/etc/systemd/system/docker.service.d/proxy.conf` 配了
`HTTP_PROXY/HTTPS_PROXY=127.0.0.1:7891`，**所有** registry 请求都会先走该代理。
若该端口没有对应隧道，`docker pull` 直接报 `proxyconnect ... connection refused`。

排查：

```bash
systemctl show docker -p Environment
cat /etc/systemd/system/docker.service.d/proxy.conf
ss -tlnp | grep 7891
```

直连内网源（如南大镜像）时，优先给 daemon 的 `NO_PROXY` 加上镜像域名，再重启 dockerd：

```bash
# 1. 备份并编辑 proxy.conf，把 NO_PROXY 追加 quay.nju.edu.cn（或直接注释代理）
# 2. 重载并重启（live-restore=true 时运行中容器不中断，仍建议先确认 docker ps）
systemctl daemon-reload && systemctl restart docker
```

改完后记得在合适时机恢复原配置。

### 2. 付费外网代理禁止大流量

不要用 SSH 反向隧道把本地付费代理（如 127.0.0.1:7897）接到服务器上给 `docker pull`
当出口——17GB 镜像会消耗大量付费流量。大镜像优先直连/内网源；确需走代理必须先征得用户同意。

### 3. 连通性快速判断

```bash
# 匿名 API 探活（能返回 200/401/JSON 都说明 registry 可达）
curl -sI -m 8 https://quay.nju.edu.cn/
curl -s -m 10 https://quay.nju.edu.cn/v2/ascend/vllm-ascend/tags/list | head -c 500
```
