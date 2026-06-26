# Blue Server Toolkit

## 项目结构

```
blue-server-toolkit/
├── SKILL.md              # 核心 skill 文件（唯一需要分发的文件）
├── README.md             # 分发文档
├── CLAUDE.md             # 本文件
├── LICENSE               # MIT
├── .gitignore
├── config.json           # 配置模板
├── scripts/              # 辅助脚本
│   ├── check-npu.sh      # NPU 状态检查
│   ├── init-config.sh    # 配置初始化
│   ├── start-docker-A2.sh
│   ├── start-docker-A3.sh
│   └── start-docker-A5.sh
└── docs/                 # 参考文档
    ├── a3-chip-numbering.md
    ├── graph-debugging.md
    ├── hdk-installation.md
    ├── mindie-compile.md
    ├── npu-process-cleanup.md
    ├── server-configs.md
    └── vllm-service-guide.md
```

## 开发约定

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

1. 更新版本号
2. 合并到 main
3. 打 tag 并 push
