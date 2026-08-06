# 蓝区 192.168 网段 资源备忘

> 适用范围：蓝区服务器（s3-s8，192.168 段） ｜ 验证日期：2026-08-06 ｜ 维护：遇新信息主动更新

## 共享盘 / 挂载

| 挂载点 | NFS 来源 | 容量 | 用途 |
|--------|----------|------|------|
| `/mnt/share` | suzblue.server:/share | 355T（已用 9.6T） | 杂项共享：modelscope 缓存、临时区、同事 log/tests |
| `/mnt/weight` | suzblue.server:/weight | 389T（已用 45T） | 模型权重仓库 |

容器内通过 `/mnt` 直接可见（start-docker-*.sh 默认 `-v /mnt:/mnt`）。

## 权重速查（/mnt/weight）

- MiniMax-M2.7-w8a8-QuaRot：216GB，54 个 safetensors shard，含 `MiniMax-M2.7_best_practice.yaml`
- MiniMax-M2.7-w8a8c8-QuaRot
- MiniMax-M2.7-eagle-model-short（2.5GB）
- MiniMax-M2.7-EAGLE3-draft-vocab200k（2.8GB）
- DeepSeek / Kimi / Qwen / GLM 等系列（完整清单 `ls /mnt/weight`）

## 常见路径速查

- 模型权重：`/mnt/weight`
- 共享杂项（modelscope 缓存等）：`/mnt/share`
- 同事代码仓示例：`/home/<user>/<project>/vllm-ascend`（如 minimax-m2.7 workspace）

## 注意事项

- NFS 大目录 `find` / `du` 很慢，必须加 `timeout` 并用 `tail` 而不是 `cat` 看日志
- 共享盘不主动删除他人文件；工作目录建议放 `/mnt/share` 下自己的子目录或 `/home/<user>`
- 具体服务器 IP / 账号在本机 `~/.blue_server_toolkit/config.json`（不入库）

## 更新记录

- 2026-08-06 初版（197 实测：两块 NFS 挂载、M2.7 权重与 Eagle 模型路径）
