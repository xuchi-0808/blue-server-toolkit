# A3 NPU 芯片编号规则

> A3（Atlas 800I A3）与 A2 的关键区别：单卡双芯

## 编号映射

A3 每张卡（NPU）包含 **2 个芯片（chip）**，`ASCEND_RT_VISIBLE_DEVICES`、Docker `--device` 等接口使用的是 **chip ID（0-15）**，不是 NPU/卡 ID（0-7）。

| NPU（卡） | Chip IDs | 对应 /dev/davinci |
|-----------|----------|-------------------|
| NPU 0 | 0, 1 | davinci0（内含 2 chip） |
| NPU 1 | 2, 3 | davinci1 |
| NPU 2 | 4, 5 | davinci2 |
| NPU 3 | 6, 7 | davinci3 |
| NPU 4 | 8, 9 | davinci4 |
| NPU 5 | 10, 11 | davinci5 |
| NPU 6 | 12, 13 | davinci6 |
| NPU 7 | 14, 15 | davinci7 |

## TP 与 NPU 数量换算

- **TP1** = 1 chip = 0.5 NPU（单芯跑）
- **TP2** = 2 chips = 1 NPU
- **TP4** = 4 chips = 2 NPU
- **TP8** = 8 chips = 4 NPU
- **TP16** = 16 chips = 8 NPU（全机）

## ASCEND_RT_VISIBLE_DEVICES 示例

```bash
# 用 NPU 4-5（8 个 chip 中的 4 个），跑 TP4
export ASCEND_RT_VISIBLE_DEVICES=8,9,10,11

# 用 NPU 0-1，跑 TP4
export ASCEND_RT_VISIBLE_DEVICES=0,1,2,3

# 用 NPU 0 的单芯，跑 TP1
export ASCEND_RT_VISIBLE_DEVICES=0
```

## 常见误区

- 写 `ASCEND_RT_VISIBLE_DEVICES=4,5,6,7` 实际选的是 NPU 2-3 的芯片，不是 NPU 4-7
- `npu-smi info` 中 NPU 列显示的是卡号（0-7），Chip 列才是芯片号（0-1 per NPU）；但 `ASCEND_RT_VISIBLE_DEVICES` 用的是全局芯片号（0-15）

## npu-smi 输出解读

```text
| NPU   Name      | Health | ... |
| Chip  Phy-ID    | Bus-Id | ... | HBM-Usage(MB) |
| 0     Ascend910 | OK     | ... |               |
| 0     0         | 0000:..| ... | 47128/ 65536   |  ← NPU 0, Chip 0 = 全局 chip 0
| 0     Ascend910 | OK     | ... |               |
| 1     1         | 0000:..| ... | 46906/ 65536   |  ← NPU 0, Chip 1 = 全局 chip 1
```

第一列是 NPU 内的 chip 序号（0 或 1），不是全局 chip ID。全局 chip ID = NPU × 2 + NPU内chip序号。
