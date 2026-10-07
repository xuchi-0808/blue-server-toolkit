# Changelog

遵循语义化版本。历史版本（1.x）的详细变更见 `git log`。

## 2.0.0 (2026-10-05)

连接范式升级：SSH 从「逐命令新建连接」改为「ControlMaster 常驻复用」。

- **新增 `docs/ssh-connection-stability.md`**：SSH 连接稳定性专项文档
  - 根因分析：网络抖动窗口只丢「新建连接」的 SYN，已建立的 TCP 流不受影响——交互终端稳、AI 代理/批量脚本逐命令建连却间歇超时
  - 配置模板：`ControlMaster auto` + `ControlPersist 8h` + `ServerAliveInterval 30`（纯客户端，服务器零改动），单条命令 ~0.8s → ~0.1s 且抖动免疫
  - 维护命令：`ssh -O check` / `ssh -O exit`，master 判死后自动重拨语义
  - 排查范式：纯 TCP 探测（nc）与 ssh 分层，区分「网络丢包」与「sshd 层拒绝」
  - 注意事项：勿全局套用（bastion/ProxyJump 场景）、MaxSessions 并发上限、换网后重建
- **SKILL.md**：经验备忘新增 ControlMaster 条目；进阶指南新增「SSH 连接稳定性」索引；连接检查表新增 `ssh -O check` 行；description 增补 connection stability
- **SKILL.md**：吸收远端修订——vllm 配套一律查 `.github/vllm-main-verified.commit`（commit id，勿按 release tag）；vllm-ascend-build.md 合并 main2main 锚点定位、serve 才暴露的配错症状、重装 `--no-deps` 等实操细节；G 区下载三坑条目
- 首个进入 CHANGELOG 的版本；1.x 历史见 git log
