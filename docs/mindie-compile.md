# MindIE-LLM 编译指南

> 来源: A00243 代码仓 `docs/zh/developer_guide/build_guide.md`

## 环境准备

MindIE 镜像获取请参见镜像安装方式文档。

## 编译安装

1. 安装 Python 工具。支持 Python 3.10 和 3.11。

```bash
pip install --upgrade pip
pip install wheel setuptools
```

2. 编译第三方依赖。

```bash
bash build.sh 3rd
```

3. 设置环境变量。

```bash
TORCH_PATH=$(python3 -c "import torch, os; print(os.path.dirname(torch.__file__))")
TORCH_NPU_PATH=$(python3 -c "import torch_npu, os; print(os.path.dirname(torch_npu.__file__))")
export LD_LIBRARY_PATH=${TORCH_PATH}/lib:${TORCH_PATH}/../torch.libs:$LD_LIBRARY_PATH
export PYTORCH_NPU_INSTALL_PATH=${TORCH_NPU_PATH}
```

可选：指定版本号：

```bash
export MINDIE_LLM_VERSION_OVERRIDE=3.0.0
```

4. 编译生成 `.whl` 包。

```bash
pip wheel . --no-build-isolation -v
```

5. 安装 MindIE-LLM。

```bash
old_umask=$(umask)
umask 027
pip install mindie_llm*.whl
umask $old_umask
```

6. 编译 ATB_Models。

```bash
cd examples/atb_models
pip wheel . --no-build-isolation -v
```

7. 安装 ATB_Models。

```bash
pip install atb_llm*.whl
```

8. 配置 ATB 环境变量。

```bash
ATB_LLM_PATH=$(python3 -c "import atb_llm, os; print(os.path.dirname(atb_llm.__file__))")
export ATB_SPEED_HOME_PATH=${ATB_LLM_PATH}
export LD_LIBRARY_PATH=${ATB_LLM_PATH}/lib:${LD_LIBRARY_PATH}
```

## 重新编译（A00243 快速迭代用）

```bash
rm -f src/kernels/dist/mie_ops_*.whl
rm -rf src/kernels/mie_ops/csrc/batch_matmul_transpose/build
rm -rf src/kernels/mie_ops/opp/vendors/custom_transformer
pip wheel . --no-build-isolation -v
pip install mindie_llm*.whl --force-reinstall
```

> SOC 精确值: `ascend910_9392` | `PlatformAscendCManager` 在 `libtiling_api.a`
