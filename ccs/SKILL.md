---
name: ccs
description: 切换 Claude Code 后端模型（BigModel / 九天）
---

# ccs - Claude Code 模型切换工具

一键切换 Claude Code 的 API 后端和模型。

## 安装

把整个 `ccs` 文件夹放到 `~/.claude/skills/` 下，然后配置脚本权限：

```bash
chmod +x ~/.claude/skills/ccs/ccs.sh
```

## 使用

```bash
~/.claude/skills/ccs/ccs.sh init       # 首次配 API Key
~/.claude/skills/ccs/ccs.sh glm        # 切到 BigModel（智谱）
~/.claude/skills/ccs/ccs.sh moma       # 切到 九天（需先启动本地代理）
~/.claude/skills/ccs/ccs.sh status     # 看当前配置
```

如果觉得路径太长，可以设置别名：

```bash
alias ccs="~/.claude/skills/ccs/ccs.sh"
```

## 九天本地代理

`jt` 命令依赖本地代理 `jt-proxy.py`，skill 目录已自带。启动方式：

```bash
nohup python3 ~/.claude/skills/ccs/jt-proxy.py &
```

也可设置开机自启。

## 工作原理

修改 `~/.claude/settings.json` 的 `env` 字段，切换 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN`。

切换后新开的对话生效，当前对话维持之前的配置。

## 首次使用

运行 `init` 命令，按提示输入 BigModel 和/或九天的 API Key。

## 依赖

- Python 3
- bash
