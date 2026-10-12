# PD 分离拉起与排障（P/D disaggregation）

> 场景：P/D 分离部署的首次拉起、多轮失败后排障、KV 传输链路验证。
> 与 [npu-roce-connectivity.md](npu-roce-connectivity.md)（部署前连通性检查）、
> [vllm-service-guide.md](vllm-service-guide.md)（单服务生命周期与 proxy 请求路径）
> 互补；950DT 的 fabric/KV 传输底层问题见 [a5-950dt-fabric-config.md](a5-950dt-fabric-config.md)。

## 拉起顺序

清场（NPU 空闲 + 无残留进程）→ P → D（各自日志里 `Application startup complete`
计数 = 各自 DP 数）→ load-balance proxy 最后。P/D 无相互启动依赖，可并行拉起
（详见 vllm-service-guide.md）；proxy 起早了会在健康检查里空转等后端。

## 失败类别清单（按排查优先级）

| # | 类别 | 症状 | 处置 |
|---|------|------|------|
| 1 | 占卡者 | 启动即报 `Free memory ... less than desired`，npu-smi 有别人的进程 | npu-smi 进程表 + who.sh 归因，先协调/wall 声明再精准清理，勿直接杀 |
| 2 | 上游代码缺口 | 固定算子/固定层报 Python 异常（如 `TypeError: 'tuple' object has no attribute ...`），换输入不消失 | 报错点搜 vllm-ascend 的 PR/issue 找官方修复，打对应补丁再重拉 |
| 3 | rootinfo/fabric 身份 | HCCL `EI0004`/`EI0016`；跨机 KV 传输 `E19999` | 见 a5-950dt-fabric-config.md |
| 4 | `max-model-len` 超 KV 显存 | 启动期 `ValueError: The model's max seqlen (...) is larger than the maximum number of tokens that can be stored in the KV cache` | 用启动日志的 KV cache tokens 反推上限，下调 max-model-len（留输入+输出+余量） |
| 5 | triton 严格模式 | 首次 forward 报 `NameError: name 'FP8_E4M3_MAX' is not defined`（PR 移植的 triton 算子引用模块级常量） | 模板加 `export TRITON_ALLOW_NON_CONSTEXPR_GLOBALS=1` 后重拉 |
| 6 | 显存释放竞态 | 清场后立即拉起仍报 `Free XX GB` 不足（数值随时间在涨） | kill/stop 后 HBM 释放是异步的，多卡大模型场景实测约 15 分钟；等回基线（npu-smi HBM 每卡几 GB）再拉 |

## mooncake P2P 日志解读

- `Transfer Engine parseHostNameWithPort ... port 12001` + `P2P handshake,
  listening on <IP>:<随机端口>`：先试 mooncake master、回落 P2P 模式，**正常**。
- P 侧 `Delaying free of N blocks for request <id>`：prefill 已完成、KV 块在
  等 D 拉取，属正常中间态。
- D 侧长时间重试后 `Mooncake transfer failed ... ret=-1`：python 层错误信息
  **丢了细节**，去同一日志里找 C++ glog 行（形如
  `E... transfer_executor_base.cpp:...] Failed to connect to target: <ip>:<port>`,
  `errmsg: E19999 ...`），那才是真错误码。
- 每个 TP worker 各起一个 transfer engine、各监听一个随机端口：日志里出现一串
  不同端口是正常的。

## 冒烟验证

```bash
# 1. 先核对模型名：served-model-name 从权重路径派生、大小写敏感，404 多半是名字打错
curl -s http://127.0.0.1:<proxy_port>/v1/models
# 2. 再发一条真实请求，看是否"口吐人言"
curl -s http://127.0.0.1:<proxy_port>/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model": "<v1/models 里的 id>", "messages": [{"role":"user","content":"..."}], "max_tokens": 64}'
```

- proxy 把请求**同时发给 P 和 D**：P 的 200 只是 prefill ack，真正的回答来自 D——
  判成败看最终 HTTP 响应体，不看 P 的 200。
- 500 `KV load failure` 类错误 = prefill 成功但 KV 没送到 D，按上表第 3/5 类排查。
