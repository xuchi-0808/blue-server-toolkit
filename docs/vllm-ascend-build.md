# vllm-ascend 源码编译安装（AI 速查）

长尾 FAQ 原文：https://ascend-inference-wiki.readthedocs.io/zh-cn/latest/guides/environment/building-vllm-ascend-from-source/
在 vllm/ 和 vllm-ascend/ 仓根分别执行，容器内操作。

## 版本配套（装 vllm 前先查）

```bash
cat .github/vllm-release-tag.commit                     # 新版：vllm 的 git tag
grep -E 'main_vllm_(commit|tag)' docs/source/conf.py    # 旧版
```

## 安装

```bash
# 1. vllm（vllm/ 仓根）
pip uninstall vllm vllm-ascend -y    # 镜像预装的先卸，否则 pip 跳过安装
VLLM_TARGET_DEVICE=empty pip install -v -e . --no-build-isolation

# 2. vllm-ascend（vllm-ascend/ 仓根，蓝区源）
pip install -v -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
pip install -v -e . --no-build-isolation -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
# Y/G 区内网改用：--extra-index-url https://triton-ascend.osinfra.cn/pypi/simple

# 3. 验证
python -c "import vllm; print(vllm.__version__)"
python -c "import vllm_ascend; print(vllm_ascend.__version__)"
```

## FAQ（按报错关键字）

| 报错 | 解法 |
|------|------|
| `No module named setuptools_rust`（装 vllm 时） | `pip install setuptools-rust`，只装这一个，装完重跑安装命令 |
| `cp: cannot create regular file '/mc2/...'` | `sed -i 's/\$SCRIPT_DIR/\$ROOT_DIR/g' csrc/build_aclnn.sh` 后重装 |
| `Stale file handle` / CPack 缺 `CANN-custom_ops*.run` | `rm -rf csrc/build build`（CPack 场景再加 `csrc/output`）后重装 |
| vllm 版本号显示 `dev` | 拉目标 tag，或装前 export `SETUPTOOLS_SCM_PRETEND_VERSION=<版本>` |
