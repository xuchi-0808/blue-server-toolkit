# vllm-ascend 源码编译安装（AI 速查）

> 本文档为命令速查版；遇到未覆盖的报错或信息不全时，访问原文获取全量：
> https://ascend-inference-wiki.readthedocs.io/zh-cn/latest/guides/environment/building-vllm-ascend-from-source/

在 vllm/ 和 vllm-ascend/ 仓根分别执行，容器内操作。

## 版本配套（装 vllm 前先查）

**一律以 `.github/vllm-main-verified.commit` 里的 commit id 为准**（vllm main 上被 CI 验证的配套 commit，PR/每日测试都 checkout 它），vllm 仓直接 `git checkout <commit id>`（detached）：

```bash
cat .github/vllm-main-verified.commit   # 配套 vllm 的 commit id —— 唯一依据
cat .github/vllm-release-tag.commit     # 仅 release 场景参考的 vllm tag
grep -E 'main_vllm_(commit|tag)' docs/source/conf.py    # 旧版
```

> 踩坑：按 release-tag 给 vllm-ascend main 配套 vllm 会配错版本——tag 停在发布点，main-verified 随 main 演进更新，两者常不同点（实际踩过）。

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
| `CMakeCache.txt ... is different than the directory`（从其他任务目录 cp 来的仓） | 缓存写死了旧仓绝对路径，`rm -rf csrc/build csrc/output build` 后重装 |
| vllm 版本号显示 `dev` | 拉目标 tag，或装前 export `SETUPTOOLS_SCM_PRETEND_VERSION=<版本>` |
