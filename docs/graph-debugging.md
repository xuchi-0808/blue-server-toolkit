# Graph 模式调试

> 精度/行为异常时，优先用 `--enforce-eager` 排除 graph capture 的影响：
>
> ```bash
> vllm serve <model_path> --enforce-eager ...  # 其他参数不变
> ```
>
> 加上后问题消失 → 说明问题在 graph capture 阶段（如 Python property 被静态化、cudagraph shape 冲突等）。问题仍在 → 非 graph 相关，排查其他方向。
>
> 等价于设置 `VLLM_GRAPH_MODE=none`，但 `--enforce-eager` 更直接。

---

# torch_npu.print_npugraph_tensor

## 功能说明

aclgraph 模式下，由于原生 Python 的 print 函数包含同步处理，在 `torch.compile` 时会触发断图，并且无法被 aclgraph 捕获，导致图模式下无法使用 print 接口观察 aclgraph 模式执行过程中的 tensor 数据。

当前接口提供了类似原生 Python 的 print 接口特性且不影响 aclgraph 捕获、重放的 tensor 打印能力，允许将 aclgraph 中间节点的 tensor 数据、数据类型、shape 信息直接打印出来，以便用户观察 aclgraph 的执行过程中的 tensor 数据，以快速定位问题。

## 函数原型

```python
torch_npu.print_npugraph_tensor(input, tensor_name=None) -> None
```

## 参数说明

- **input** (`Tensor`)：必选参数，用于打印的 tensor。
- **tensor_name** (`str`)：可选参数，指定打印 tensor 的 tensor name，用于区分不同的 tensor，默认为 None。
  - tensor_name 为 None 时：直接输出 tensor 数据内容。
  - tensor_name 不为 None 时：以 `{tensor_name}:` 格式作为前缀，后接 tensor 数据。

## 约束说明

该接口支持在 Eager 模式和 aclgraph 模式下使用。

## 调用示例

- **单算子模式调用**

```python
import torch
import torch_npu
a = torch.randn([5, 5]).npu()
torch_npu.print_npugraph_tensor(a, tensor_name="a")
```

- **基于 `torch.npu.graph` 调用**

```python
import torch
import torch_npu

x = torch.randn([5, 5]).npu()

graph1 = torch.npu.NPUGraph()
with torch.npu.graph(graph1):
    torch_npu.print_npugraph_tensor(x, tensor_name="x")
    output = torch.square(x)
    torch_npu.print_npugraph_tensor(output, tensor_name="output")

graph1.replay()
```

- **基于 `torch.compile` 调用**

```python
import torch
import torch_npu

class Model(torch.nn.Module):
    def __init__(self):
        super().__init__()

    def forward(self, x):
        x = torch.add(x, x)
        torch_npu.print_npugraph_tensor(x, tensor_name="x")
        x = torch.add(x, 2)
        torch_npu.print_npugraph_tensor(x, tensor_name="added_x")
        return x

x = torch.randn([5, 5]).npu()
model = Model()
model = torch.compile(model, backend="npugraph_ex", dynamic=False, fullgraph=True)
model(x)
```
