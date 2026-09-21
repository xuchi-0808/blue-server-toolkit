# vllm-ascend 源码编译安装（AI 速查）

> 本文档为命令速查版；遇到未覆盖的报错或信息不全时，访问原文获取全量：
> https://ascend-inference-wiki.readthedocs.io/zh-cn/latest/guides/environment/building-vllm-ascend-from-source/

在 vllm/ 和 vllm-ascend/ 仓根分别执行，容器内操作。

## 源规则（蓝区先配全局，别先试默认）

pypi.org 蓝区直连是长时间挂死而非快速报错，不要"先试一遍默认源"。装任何包
之前先配一次全局源，之后一切 pip 命令（-e 安装、requirements、临时补装小包）
自动带源：

```bash
pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/
pip config set install.trusted-host mirrors.aliyun.com
```

下文命令里显式写的 `-i` 是未配全局时的兜底写法。

> **源不是固定的，装前先比一次大文件速度（2026-09-21 实测）**：aliyun 的索引页正常
> 但**大文件可跌到 ~0**——14MB 的 wheel 75 秒只下到 40 字节，pip 就长时间停在
> `Downloading ...` 不动（看着像死锁，其实还在爬）。同期腾讯云 4.6MB/s、**华为云
> 7MB/s**（华为机器上最快）。比速方法，几秒钟出结论：
>
> ```bash
> pip download numpy==1.26.4 --no-deps -d /tmp/dl_probe -i <镜像>/pypi/simple --trusted-host <镜像域名>
> ```
>
> 出现的 `卡住不动` 先怀疑源、再怀疑代码；确认哪个快就 `pip config set global.index-url`
> 换过去，并可把另一个源挂到 `global.extra-index-url` 兜底。

## 版本配套（装 vllm 前先查）

**一律以 `.github/vllm-main-verified.commit` 里的 commit id 为准**（vllm main 上被 CI 验证的配套 commit，PR/每日测试都 checkout 它），vllm 仓直接 `git checkout <commit id>`（detached）：

```bash
cat .github/vllm-main-verified.commit   # 配套 vllm 的 commit id —— 唯一依据
cat .github/vllm-release-tag.commit     # 仅 release 场景参考的 vllm tag
grep -E 'main_vllm_(commit|tag)' docs/source/conf.py    # 旧版
```

> 踩坑：按 release-tag 给 vllm-ascend main 配套 vllm 会配错版本——tag 停在发布点，main-verified 随 main 演进更新，两者常不同点（实际踩过）。
> main2main 真实锚点可用 `git log -S "<新引入的 vllm API>" -- vllm_ascend/` 定位（提交信息里写明锚点 SHA）。
> 配错版本的典型症状：serve 启动导入期 `AttributeError: VllmConfig has no attribute '_get_v1_model_runner_unsupported_features'`
>（补丁层引用新 vllm 才有的 API），`import vllm, vllm_ascend` 不触发补丁测不出来——**必须起一次 serve 才暴露**。
> 升级 vllm 重装时若 pip 想动 torch/torch_npu/triton-ascend，改用 `--no-deps`（镜像依赖视为已满足）。

## 安装

```bash
# 1. vllm（vllm/ 仓根）
pip uninstall vllm vllm-ascend -y    # 镜像预装的先卸，否则 pip 跳过安装
VLLM_TARGET_DEVICE=empty pip install -v -e . --no-build-isolation -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com

# 2. vllm-ascend（vllm-ascend/ 仓根，蓝区源）
pip install -v -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
pip install -v -e . --no-build-isolation -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
# Y/G 区内网改用：--extra-index-url https://triton-ascend.osinfra.cn/pypi/simple

# 3. 验证
python -c "import vllm; print(vllm.__version__, vllm.__file__)"
# 新版 main 已删除 vllm_ascend.__version__ 属性，版本只读包 metadata（用 __version__ 会误报 AttributeError）
python -c "import vllm_ascend, importlib.metadata as m; print(m.version('vllm-ascend'), vllm_ascend.__file__)"
# __file__ 应指向 -e 安装的源码目录（pip show 的 Location 恒显示 site-packages，不能作为 editable 判据）
```

装完应有的稳定状态（2026-09-21 在 nightly-main-a3 镜像实测）：

- 版本号带本地 commit：`vllm 0.28.1rc1.dev676+g84030bbe3` / `vllm-ascend 0.19.1rc2.dev2295+gaf9d2d405`；
- `vllm_ascend/libvllm_ascend_kernels.so` 与 `vllm_ascend/_cann_ops_custom/vendors/custom_transformer` 已生成；
- 第 2 步的 `pip install -r requirements.txt` 会把 vllm 刚装的新版 **fastapi/numpy/starlette 降回镜像自带的 0.123.10 / 1.26.4 / 0.50.0** —— 这是正常收敛（镜像自带的 vllm 也是配这一组），不用去"修"。

## FAQ（按报错关键字）

| 报错 | 解法 |
|------|------|
| `No module named setuptools_rust`（装 vllm 时） | `pip install setuptools-rust -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com`，只装这一个，装完重跑安装命令 |
| `cp: cannot create regular file '/mc2/...'` | `sed -i 's/\$SCRIPT_DIR/\$ROOT_DIR/g' csrc/build_aclnn.sh` 后重装 |
| `Stale file handle` / CPack 缺 `CANN-custom_ops*.run` | `rm -rf csrc/build build`（CPack 场景再加 `csrc/output`）后重装 |
| `CMakeCache.txt ... is different than the directory`（从其他任务目录 cp 来的仓） | 缓存写死了旧仓绝对路径，`rm -rf csrc/build csrc/output build` 后重装 |
| vllm 版本号显示 `dev` | 拉目标 tag，或装前 export `SETUPTOOLS_SCM_PRETEND_VERSION=<版本>` |
| pip 长时间停在 `Downloading <大 wheel>` 不动、进程 CPU 时间为 0 | 源的大文件限速，不是死锁：`stat -c %s` 看 `/tmp/tmpp*` 是否在涨，然后换源（见上方比速） |
| `cargo ... failed to download from cache-service.nginx-pypi-cache.svc.cluster.local` + `optional Rust extension vllm.vllm-rs failed` | 镜像里 pip/cargo 都被指向了内网 pypi cache service，外网不可解析。该扩展是**可选**的，编译失败会被自动跳过、安装照样成功；镜像自带的 vllm 也没编它，属正常状态 |
| `vllm ... requires fastapi<0.137.0,>=0.133.0, but you have fastapi 0.123.10`（pip 冲突告警） | vllm 的 pyproject 与 vllm-ascend 的 `requirements.txt`（`fastapi<0.124.0`）本身打架，镜像采用的是后者；只影响 OpenAI 服务端，跑 UT/离线推理可忽略 |
