# Blue Server Toolkit

## 项目结构

```
blue-server-toolkit/
├── SKILL.md              # 唯一需要分发的文件（双源之一）
├── README.md             # 分发文档
├── CLAUDE.md             # 本文件
├── LICENSE               # MIT
├── .gitignore
├── config.json           # 配置模板（双源之一）
└── scripts/              # 脚本源码（双源之一，与 SKILL.md 代码块一致）
    ├── check-npu.sh      # NPU 状态检查
    ├── init-config.sh    # 配置初始化
    └── start-docker.sh   # 创建容器
```

## 开发约定

### 双源一致性

`scripts/` 和 `config.json` 必须与 `SKILL.md` 中对应的代码块完全一致。
修改脚本时同步更新 SKILL.md 的 Scripts 章节。

### 版本号

- SKILL.md frontmatter `metadata.version`
- config.json `"version"`
- 脚本文件头 `# Version: X.Y`

三者必须保持一致。版本更新时联动修改。

### SKILL 设计原则

- **非绑定式**——命令参考是纯模式表格，不夹带 flow 步骤
- **经验备忘是参考不是规则**——AI 自行判断是否采纳
- **裸机优先**——容器是可选的包装模式
- **中文化**——说明文字用中文，技术内容保持语言中立

### 发布流程

1. 确保 scripts/ 和 SKILL.md 代码块一致
2. 更新版本号
3. 合并到 main
4. 打 tag 并 push
