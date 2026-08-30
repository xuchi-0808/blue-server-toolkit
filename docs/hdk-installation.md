# HDK 裸机安装指南（Ascend 910B / A3）

> 从一台完全空白的 Atlas 800I A3 裸机，装到 `npu-smi info` 可用。

## 前置：确认硬件与系统

```bash
# 确认是不是 910B（PCIe Device ID 19e5:d803）
lspci -nn | grep -i d803
# → Processing accelerators ... Device [19e5:d803]  （910B）

# 服务器型号（dmidecode）
dmidecode -t system | grep "Product Name"   # → Atlas 800I A3

# 系统与内核（驱动编译依赖必须精确匹配这个内核版本）
uname -r          # → 5.10.0-216.0.0.115.oe2203sp4.aarch64
cat /etc/os-release | grep PRETTY            # → openEuler 22.03 (LTS-SP4)
```

> A3 是**单卡双芯**：8 张物理卡 = 16 个 chip。`npu-smi info` 会显示 0-7 号 NPU，每个 2 个 chip。

## 第 0 步：先补基础工具（最容易被忽略的一步）

**这是整个流程最容易翻车的地方**——裸机 openEuler 连 `tar` 都没有，而昇腾 `.run` 包解压依赖 `tar`。详见下方[第一个坑](#坑-1裸机缺-tar--最隐蔽)。

```bash
# 编译驱动所需（kernel-devel 版本必须和 uname -r 完全一致）
dnf install -y "kernel-devel-$(uname -r)" gcc gcc-c++ make tar

# 顺手补齐其它绕不开的工具
dnf install -y vim git cmake autoconf automake libtool jq tree htop \
    iotop iftop lsof rsync tmux tcpdump numactl perf strace gdb socat
```

## 第 1 步：创建 HwHiAiUser 用户

昇腾驱动安装要求预先存在该用户/组，否则报 `ERR_NO:0x0091 HwHiAiUser not exists`。

```bash
groupadd HwHiAiUser
useradd -g HwHiAiUser -d /home/HwHiAiUser -m HwHiAiUser -s /bin/bash
```

## 第 2 步：下载驱动 + 固件

**下载页**：https://www.hiascend.com/hardware/firmware-drivers/community
（需 HUAWEI ID 登录；选 Atlas 800I A2 / A3 系列，架构选 **aarch64**）

只装 `npu-smi` 只需 2 个文件，都用 **`.run` 格式**：

| 文件 | 示例版本 | 说明 |
|------|------|------|
| 驱动 | `Atlas-A3-hdk-npu-driver_26.0.RC1_linux-aarch64.run` | ~120MB |
| 固件 | `Atlas-A3-hdk-npu-firmware_9.0.0.0.205.run` | ~280KB |

**为什么选 `.run` 不选 `.rpm`/`.zip`**：
- `.run` 是官方首选，自带校验 + `--full --install-for-all`，文档最全
- `.zip` 一键包需额外部署工具，只适合机房批量装机
- `.deb`/`.hpm` 不适用于 openEuler（rpm 系 / iBMC 带外）

**获取真实下载直链**（hiascend 页面是 JS 动态加载，直接复制页面 URL 无效）：
1. 浏览器点「下载」开始下载
2. 下载列表（Ctrl+J）→ 右键「复制下载链接」
3. 拿到形如 `https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/...&response-content-type=...` 的 OBS 直链
4. 服务器上 `wget` 即可（OBS 直连速度很快）

```bash
mkdir -p /home/HDK && cd /home/HDK
wget -O <driver>.run '<OBS直链>'
wget -O <firmware>.run '<OBS直链>'
# 校验：文件应是 "Bourne-Again shell script executable (binary data)"
file *.run
```

## 第 3 步：安装驱动 → 固件（顺序不能反）

官方铁律：**首次安装必须先驱动、后固件**。顺序反了会导致 `npu-smi info` 失败，要卸载重来。

```bash
cd /home/HDK
chmod +x *.run

# 1) 驱动（编译内核模块，约 1-2 分钟；--install-for-all 让所有用户可用）
./Atlas-A3-hdk-npu-driver_26.0.RC1_linux-aarch64.run --full --install-for-all
# 看到 "Driver package installed successfully!" 即成功，立即生效，无需 reboot

# 2) 固件（很快；16 芯片会全部升级）
./Atlas-A3-hdk-npu-firmware_9.0.0.0.205.run --full
# 看到 "The firmware of [16] chips are successfully upgraded." 即成功
# 固件需 reboot 后彻底生效，但驱动即时生效，npu-smi 当场可用
```

## 第 4 步：验证

```bash
npu-smi info              # 看到 8 NPU / 16 chip，全 OK
npu-smi info -t board -i 0  # 查固件版本（Firmware Version: 9.0.0.0.205）
ls /dev/davinci* /dev/davinci_manager /dev/hisi_hdc /dev/devmm_svm  # 设备文件齐全
```

驱动装好后，`start-docker.sh` 映射所需的 4 类设备文件全部自动生成。

## 三个坑

### 坑 1：裸机缺 `tar`（最隐蔽）

**症状**：`.run` 安装报
```
Uncompressing ASCEND DRIVER RUN PACKAGE ... Extraction failed.
 ... Decompression failed.
Signal caught, cleaning up
```
SHA256 校验明明 OK，文件没坏。

**根因**：昇腾 `.run` 是 Makeself 自解压包，解压管道是 `dd | gzip -cd | tar`。裸机没装 `tar` → 最后一个命令不存在 → 管道断裂 → `gzip` 收到 SIGPIPE → 报 "Signal caught / Decompression failed"。

**报错信息完全不提 tar**，极具误导性。排查时手动复现 `dd ... | gzip -cd | tar` 才会暴露 `tar: command not found`。

**解法**：`dnf install -y tar`。**装任何昇腾 `.run` 前先确保有 tar。**

### 坑 2：缺 `kernel-devel` 且版本必须精确匹配

驱动要编译内核模块，依赖 `kernel-devel`。包版本必须和 `uname -r` **完全一致**：

```bash
# 正确写法（版本号跟着内核走）
dnf install -y "kernel-devel-$(uname -r)"
# 错误：dnf install kernel-devel  ← 会装最新版，版本不符编译失败
```

### 坑 3：缺 `HwHiAiUser` 用户

报 `ERR_NO:0x0091; ERR_DES:HwHiAiUser not exists`。见第 1 步，先建用户再装驱动。

## 版本对应（实测）

| 组件 | 版本 |
|------|------|
| 驱动 | 26.0.RC1 |
| 固件 | 9.0.0.0.205 |
| 内核 | 5.10.0-216.0.0.115.oe2203sp4 |
| OS | openEuler 22.03 LTS-SP4 aarch64 |

> 早期资料说"SP4 装驱动会失败"，那是对**老版本驱动**而言。26.0.RC1 对 SP4 + kernel 5.10 兼容良好，无需降级系统。
