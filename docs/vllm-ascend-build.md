# vllm-ascend 源码编译安装

> 精简自 [Ascend Inference Wiki 原文](https://ascend-inference-wiki.readthedocs.io/zh-cn/latest/guides/environment/building-vllm-ascend-from-source/)（Docker 容器内编译；蓝区即其中的 B 区）。长尾 FAQ 见原文。

## 0. 版本配套

vllm-ascend 依赖特定版本的 vllm，不配套会有接口不兼容：

```bash
# 新版（2026-06-10 后）：内容为 vllm 的 git tag
cat .github/vllm-release-tag.commit
# 旧版：找 main_vllm_commit（精确 hash）和 main_vllm_tag
grep -E 'main_vllm_(commit|tag)' docs/source/conf.py
```

官方镜像通常已预装配套版本，仅源码安装 / bisect 切版本时需要查。

## 1. 装 vllm

```bash
git clone <vllm-repo> vllm && cd vllm
pip uninstall vllm vllm-ascend -y   # 镜像预装的先卸，否则 pip 认为已满足而跳过
VLLM_TARGET_DEVICE=empty pip install -v -e . --no-build-isolation
```

- `VLLM_TARGET_DEVICE=empty` 必设，否则编译 CUDA kernel 报错
- `--no-build-isolation` 避免重建 build 依赖，大幅提速

## 2. 装 vllm-ascend（B 区/蓝区）

```bash
git clone <vllm-ascend-repo> vllm-ascend && cd vllm-ascend
pip install -v -r requirements.txt \
  -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
pip install -v -e . --no-build-isolation \
  -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
```

> 华为云/清华镜像经测有 aarch64 缺包或 403，不推荐。
> Y/G 区（内网）改用 triton 源 `--extra-index-url https://triton-ascend.osinfra.cn/pypi/simple`；外网环境直接 pip。详见原文。

## 3. 验证

```bash
python -c "import vllm; print(vllm.__version__)"
python -c "import vllm_ascend; print(vllm_ascend.__version__)"
```

## 高频 FAQ

| 症状 | 原因 / 解法 |
|------|------------|
| `cp: cannot create regular file '/mc2/...'` | `csrc/build_aclnn.sh` 用了未定义变量 `$SCRIPT_DIR`；`sed -i 's/\$SCRIPT_DIR/\$ROOT_DIR/g' csrc/build_aclnn.sh` 后重装 |
| `Stale file handle`、CPack 报 `CANN-custom_ops*.run` 缺失 | NFS 上次编译残留；`rm -rf csrc/build build`（CPack 场景再删 `csrc/output`）后重装 |
| vllm 版本号显示 `dev` | setuptools_scm 无 tag；拉目标 tag 或装前设 `SETUPTOOLS_SCM_PRETEND_VERSION`。部分代码按 `vllm.__version__` 分支，`dev` 会行为异常 |

长尾 FAQ（缺 `setuptools-rust`、`HAS_TRITON=False` 算子未注册等）见开头链接的 Wiki 原文。
