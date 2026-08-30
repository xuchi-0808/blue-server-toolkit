"""FP16 matmul TFLOPS probe for Ascend NPU (single die, torch_npu).

Hosts usually lack torch — run inside a vllm-ascend container (stdin pipe,
nothing written server-side); uses the first NPU die visible to the container:

  ssh {user}@{host} "docker exec -i {container} python3 -" < flops-torch.py

Single-die fp16 matmul peak on the 560T SKU: ~230-250 TFLOPS (measured);
752T SKU expected ~320. Classification threshold 280 — the 752T side is an
estimate until first measured on real 752T hardware (then update the constant).

NOTE: real compute load (~seconds). Do not run while other jobs occupy the chip.
"""
import time

import torch
import torch_npu  # noqa: F401

THRESHOLD_752T = 280

torch.npu.set_device(0)


def bench(m, iters):
    a = torch.randn(m, m, device="npu").half()
    b = torch.randn(m, m, device="npu").half()
    for _ in range(3):
        c = a @ b
    torch.npu.synchronize()
    t0 = time.perf_counter()
    for _ in range(iters):
        c = a @ b
    torch.npu.synchronize()
    return 2 * m**3 * iters / (time.perf_counter() - t0) / 1e12


best = 0.0
for m, iters in [(4096, 600), (8192, 200), (16384, 50)]:
    tf = bench(m, iters)
    best = max(best, tf)
    print(f"matmul {m}^3 fp16: {tf:6.1f} TFLOPS")
print(f"PEAK fp16 matmul: {best:.1f} TFLOPS")
kind = "752T" if best >= THRESHOLD_752T else "560T"
print(f"=> A3 {kind} machine (560T ~230-250 measured / 752T ~320 est., threshold {THRESHOLD_752T})")
