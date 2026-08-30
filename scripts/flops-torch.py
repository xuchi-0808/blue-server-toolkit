"""FP16 matmul TFLOPS benchmark for Ascend NPU (torch_npu) — no toolbox needed.

Run inside any container that has torch + torch_npu (e.g. vllm-ascend image);
uses the first NPU device visible to that container:

  ssh {user}@{host} "docker exec -i {container} python3 -" < flops-torch.py

Peak fp16 matmul on the 560T SKU measures ~230-250 TFLOPS (aclnn GEMM,
~43% of ascend-dmi counting); 752T SKU expected ~320 by scaling.
Classification threshold 280 — 752T side is an estimate until first measured
on real 752T hardware (then update the threshold here).

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
