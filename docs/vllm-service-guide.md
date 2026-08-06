# vLLM 服务管理

> 从蓝区操作速查提取的 vLLM 服务管理专题。

## 后台启动服务

```bash
# 方式一：docker exec -d（推荐）
docker exec -d <container> bash -c 'bash /path/to/start_script.sh > /path/to/log 2>&1'

# 方式二：nohup + SSH（容器外）
nohup ssh root@<host> "docker exec -d <container> bash -c 'bash /path/to/start_script.sh > /path/to/log 2>&1'" > /dev/null 2>&1 &
```

## 检查服务状态

```bash
# 检查端口是否可达
curl -s http://localhost:<port>/v1/models | python3 -m json.tool

# 查看服务日志（最后 5 行）
docker exec <container> bash -c 'tail -5 /path/to/log'

# 查看 NPU 进程
npu-smi info  # 进程表在底部
```

## 停止服务

```bash
# 统一用 kill -9 PID
kill -9 <PID>
```

> **禁止 `pkill -9 -f python`** — 会误伤其他用户进程并导致 HBM 孤儿。详见 [npu-process-cleanup.md](npu-process-cleanup.md)。

## 多服务并行

A3 有 16 张 NPU 卡（chips 0-15），可同时跑 4 个 TP4 服务：

| 服务 | Chips | 端口 | 说明 |
|------|-------|------|------|
| A | 0-3 | 8000 | `ASCEND_RT_VISIBLE_DEVICES=0,1,2,3` |
| B | 4-7 | 8001 | `ASCEND_RT_VISIBLE_DEVICES=4,5,6,7` |
| C | 8-11 | 8002 | `ASCEND_RT_VISIBLE_DEVICES=8,9,10,11` |
| D | 12-15 | 8003 | `ASCEND_RT_VISIBLE_DEVICES=12,13,14,15` |

每个服务需独立端口 + 独立 `ASCEND_RT_VISIBLE_DEVICES`，互不干扰。

## 关键参数备忘

- `num_speculative_tokens`：TP4 时必须设为 3（不能设 2，与 TP4 的 cudagraph shapes 冲突）
- `max_out_len`：不能等于 `max-model-len`（需留 2000+ token 给 prompt），建议 32768
- `--quantization ascend`：仅 W8A8 需要，BF16 权重要去掉
- `VLLM_USE_MODELSCOPE`：使用本地权重时不要设，会与本地路径冲突
- `VLLM_USE_V1`：v0.21.0 已默认 V1，无需设置

## Graph 模式调试

精度/行为异常时，优先用 `--enforce-eager` 排除 graph capture 的影响：

```bash
vllm serve <model_path> --enforce-eager ...  # 其他参数不变
```

加上后问题消失 → 说明问题在 graph capture 阶段（如 Python property 被静态化、cudagraph shape 冲突等）。问题仍在 → 非 graph 相关，排查其他方向。

> 等价于设置 `VLLM_GRAPH_MODE=none`，但 `--enforce-eager` 更直接。

## 并发多请求验证

`ais_bench` 不是验证多并发行为的唯一手段。用 curl 搭配后台并发请求更灵活：

```bash
# concurrent_curl.sh（简易版）
for i in $(seq 1 32); do
    curl -s -X POST http://localhost:8080/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model":"default","messages":[{"role":"user","content":"hi"}],"max_tokens":32}' \
        > /dev/null 2>&1 &
done
wait
# 观察各请求的回复是否正常
```

如果单请求正常、多请求乱码，优先怀疑触发条件跟 batch size / num_tokens 相关（如 graph capture 静态化、通信策略切换阈值等）。
