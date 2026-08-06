# 服务器配置

## 服务器列表

| # | IP | 用途 | 状态 |
|---|-----|------|------|
| 1 | 173.131.1.2 | 昇腾蓝区主服务器 | 已配置 |
| 2 | 173.125.1.2 | 昇腾蓝区次服务器 | 已配置（`/` 92%，Python 坏，已放弃）|
| 3 | 192.168.13.197 | A3-S3（vLLM 测试） | A00282 E4 单机不复现 + 双机非 RoCE |
| 4 | 192.168.13.198 | A3-S4（Atlas 800I A3） | 已装 HDK+Docker+CANN |

## 基础信息

### S1: 173.131.1.2

- **IP**: `173.131.1.2`
- **OS**: openEuler aarch64
- **Hostname**: hostname-qbnxc
- **SSH 登录**: `root@173.131.1.2`（Key 认证已配好）
- **本机用户**: xuchi
- **本机对接**: `ssh xuchi@<IP>` 后走内网

### S2: 173.125.1.2

- **IP**: `173.125.1.2`
- **OS**: openEuler aarch64
- **Hostname**: hostname-2pbfv
- **SSH 登录**: `root@173.125.1.2`（Key 认证已配好）
- **本机用户**: xuchi
- **本机对接**: `ssh xuchi@<IP>` 后走内网
- **状态**: `/` 分区 69G 用 60G（92%）

### S3: 192.168.13.197

- **IP**: `192.168.13.197`
- **OS**: Linux（Atlas 800I A3）
- **SSH 登录**: `root@192.168.13.197`
- **容器**: `xc_vllm_A00280`（镜像 `quay.io/ascend/vllm-ascend:nightly-main-a3`）
- **NPU**: 16 × Ascend 910（8 NPU = 16 chips，A3 单卡双芯）
- **vllm-ascend 代码位置**：容器内（不在 `/vllm-workspace`，需进容器 `find / -name "ascend_forward_context.py"` 确认）。直接改 Python 文件即可生效，不用重装
- **A00282 验证状态**：E4 单机强制 MC2 不复现（MC2+mask 路径走通但 32 并发精度正常）+ S3-S4 双机跨机 MC2 通信失败（非 RoCE）。A3 无法复现 A2 bug，已回绿区

### S4: 192.168.13.198

- **IP**: `192.168.13.198`
- **型号**: Huawei Atlas 800I A3（训练服务器）
- **OS**: openEuler 22.03 LTS-SP4, aarch64（鲲鹏）
- **内核**: 5.10.0-216.0.0.115.oe2203sp4.aarch64
- **SSH 登录**: `root@192.168.13.198`（免密已配）
- **NPU**: 8 NPU / 16 chips × Ascend 910B（PCIe ID `19e5:d803`），每 chip 64GB HBM
- **CPU**: 640 核
- **RAM**: 2.0 TiB
- **磁盘**: `/` 3.5T（3.3T 可用）
- **HDK**: 驱动 26.0.RC1 + 固件 9.0.0.0.205，已安装（2026-06-20）
- **状态**: 已装 HDK + Docker + CANN（2026-06-20）
- **A00282 验证状态**: S3-S4 双机跨机 MC2 通信失败（197-198 间是普通 100GbE，非 RoCE）
- **安装记录**: 见 [HDK-裸机安装指南](hdk-installation.md)

## 硬件规格

| 部件 | 规格 | 备注 |
|------|------|------|
| NPU | 8 × Ascend 910B4 | 均 OK, Health |
| HBM | 32G / 张（S3） | 已用约 2.8G / 张 |
| HBM | 64G / chip（S4） | 910B，A3 单卡双芯 |
| CPU | aarch64（openEuler） | S4 为 640 核 |
| RAM | 2.0 TiB（S4） | S3 未采集 |

## 存储

| 分区 | 容量 | 使用 | 可用 | 使用率 | 服务器 |
|------|------|------|------|--------|--------|
| / (S1) | 69G | 26G | 40G | 39% | 173.131.1.2 |
| / (S2) | 69G | 60G | 5.3G | 92% | 173.125.1.2 |
| /home (S1) | 6.9T | 1.9T | 4.7T | 29% | 173.131.1.2 |
| /home (S2) | 6.9T | 4.1T | 2.5T | 63% | 173.125.1.2 |

### 重要目录

| 路径 | 说明 | 容量 | 服务器 |
|------|------|------|--------|
| `/root/` | 用户家目录 | 受 `/` 分区限制 | 两台都是 |
| `/home/` | 数据盘 | S1: 4.7T 可用 / S2: 2.5T 可用 | 两台 |
| `/home/.cache-root/` | 模型缓存（软链目标） | 在大盘上 | S1 已迁, S2 待迁 |

## 缓存布局

```text
/root/.cache/  →  /home/.cache-root/   (模型/框架缓存，已迁移)
/root/.vscode-server/                    (VS Code 远程，未迁移)
/root/.vaws/                             (工具缓存，未迁移)
/root/.trae-cn-server/                   (TRAE 缓存，未迁移)
```

## 软件栈

> S1/S2/S3 的 CANN / Docker 等待补充。S4 为新装裸机。

### S4: 192.168.13.198（2026-06-20 实测）

| 组件 | 版本 / 状态 |
|------|------|
| NPU 驱动 | 26.0.RC1 |
| NPU 固件 | 9.0.0.0.205 |
| npu-smi | 26.0.rc1（`/usr/local/sbin/npu-smi`）|
| CANN | 未装（目标仅为 npu-smi 时不需要） |
| Docker | 未装 |
| 基础工具 | 已补齐（tar/vim/git/cmake/numactl/tmux 等） |
| HwHiAiUser | 已创建（驱动要求） |

## 历史变更

> 记录服务器上的环境配置、踩坑、迁移操作等。

### 2026-05-21

- 初始化本笔记
- 确认缓存迁移 `/root/.cache → /home/.cache-root/`（S1）
- 清理 S2 TRAE manager-logs 历史日志 1.1G
- S2 SSH key 配置完成
- 创建/配置 `xuchi` 用户（两台）：wheel 组 + 免密 sudo + 公钥认证

### 2026-06-20

- **S4（192.168.13.198）入册**：Atlas 800I A3 新裸机
- 从零安装 HDK：驱动 26.0.RC1 + 固件 9.0.0.0.205，`npu-smi info` 可用
- 踩坑：裸机缺 `tar` 导致 `.run` 解压报 `Decompression failed / Signal caught`（报错不提 tar，极隐蔽）
- 踩坑：缺 `HwHiAiUser` 用户（ERR 0x0091）、缺匹配版 `kernel-devel`
- 补齐基础工具（tar/vim/git/cmake/numactl/tmux/jq/htop 等一批）
- 详细流程见 [HDK-裸机安装指南](hdk-installation.md)

---

## S3 权重清单

> 路径：`/home/data/weights/`（2026-06-19 从 `/home/weights/` 迁移）
> 旧路径 `/home/weights/Eco-Tech/` 下的 Qwen3 权重已清空

### W8A8 量化权重

| 模型 | 路径 | 大小 | 备注 |
|------|------|------|------|
| Qwen3-30B-A3B-W8A8 | `/home/data/weights/Qwen3-30B-A3B-w8a8` | — | — |
| Qwen3-Coder-30B-A3B-Instruct-W8A8 | `/home/data/weights/Qwen3-Coder-30B-A3B-Instruct-w8a8` | 30G | — |

### BF16 浮点权重

| 模型 | 路径 | 大小 | 备注 |
|------|------|------|------|
| Qwen3-Coder-30B-A3B-Instruct (BF16) | `/home/data/weights/Qwen3-Coder-30B-A3B-Instruct` | 142G (16 shards) | — |

### Eagle3 投机解码权重

| 模型 | 路径 | 备注 |
|------|------|------|
| Qwen3-a3B_eagle3 | `/home/data/weights/Qwen3-a3B_eagle3` | 通用，兼容 30B 和 Coder |
