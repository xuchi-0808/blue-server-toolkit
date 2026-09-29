# G 区大文件下载指南

> **适用范围:仅 G 区环境**(特征:唯一出网通道是深信服 netentsec MITM 代理,模型盘挂大容量 NFS)。
> 其他蓝区/内网环境网络路径不同,勿套用。具体代理 IP、proxy.sh 路径属个人环境信息,查本地
> `~/.blue_server_toolkit/notes/`。

## 网络路径特征

- **直连外网不通**(curl 超时),必须走团队共享 proxy.sh 设代理。
- 代理对 HTTPS 做 **MITM 自签签发**:Python requests/urllib3 一律报
  `CERTIFICATE_VERIFY_FAILED (self-signed certificate in certificate chain)`。
  pip 能成功是因为配置了 `trusted-host`,**不代表没被 MITM**。
- 应对:脚本头部 `requests.Session.verify = False` + `urllib3.disable_warnings()`;
  curl 加 `-k`;git 设 `GIT_SSL_NO_VERIFY=true`。给 modelscope 打持久补丁可改
  `modelscope_hub/_legacy_api.py`、`_openapi.py` 的 `self._session` 创建处(留 .bak,
  容器重建后重打)。

## NFS 直写卡死(致命坑)

单连接大文件**直写 NFS 挂载点会中途永久冻结**:curl 与 modelscope 均中招(实测 291MB 文件
两次冻在整数 MiB 处),进程僵死、`--max-time` 不触发、无重试日志;同链路 `curl -o /dev/null`
测速全程正常——用这一点区分"链路问题"还是"落盘问题"。

**标准姿势:先下容器本地盘,校验后再 mv**(小文件 <几十 MB 可直写 NFS):

```bash
# 1) 循环断点续传到 /tmp(每次最多 120s,超时自动重连续传)
URL=https://www.modelscope.cn/models/{org}/{model}/resolve/master/{file}
for i in $(seq 1 20); do
  curl -k -sSL -C - --max-time 120 -o /tmp/{file} $URL && break
  sleep 2
done
# 2) 字节数与源站核对(ModelScope 文件页可查),通过后再落 NFS
[ "$(stat -c %s /tmp/{file})" = "{expected_bytes}" ] && \
  mv -f /tmp/{file} /mnt/share/.../weights/{model}/
```

## pkill 自匹配坑

`pkill -f {pattern}` 所在命令行里若包含与 pattern 匹配的**未括号字面量**(如真实路径),
会把整个 `docker exec bash -c` 自杀(退出码 143,后续命令全部没跑)。规则:pattern 用
`[x]` 括号技巧,且**拆开执行**——先单独 pkill,再单独跑后续命令。
