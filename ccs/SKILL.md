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
~/.claude/skills/ccs/ccs.sh init           # 首次配 API Key
~/.claude/skills/ccs/ccs.sh glm           # 切到 BigModel（智谱）
~/.claude/skills/ccs/ccs.sh glm glm-4.7   # 切到 BigModel 并指定模型
~/.claude/skills/ccs/ccs.sh moma          # 切到 九天（自动启动本地代理）
~/.claude/skills/ccs/ccs.sh moma moonshotai/kimi-k2.6  # 切到 九天并指定模型
~/.claude/skills/ccs/ccs.sh status        # 看当前配置
```

如果觉得路径太长，可以设置别名：

```bash
alias ccs="~/.claude/skills/ccs/ccs.sh"
```

## 九天本地代理

`ccs moma` 依赖本地代理 `jt-proxy.py`（skill 目录已自带）。切换到 moma 时脚本会自动启动代理，也支持手动启动：

```bash
nohup python3 ~/.claude/skills/ccs/jt-proxy.py &
```

## 工作原理

修改 `~/.claude/settings.json` 的 `env` 字段，切换 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN`。

切换后新开的对话生效，当前对话维持之前的配置。

### 背景

`ccs` 是为了让 Claude Code 接入国内 LLM 后端（MOMA / 聚合 API）而写的切换工具。Claude Code 原生只支持 Anthropic 官方 API，通过修改环境变量指向兼容层即可使用第三方模型。

### 关于 jt-proxy

`jt-proxy.py` 是一个本地代理，解决以下问题：

- MOMA 等聚合 API 的端点格式与 Anthropic SDK 不完全兼容，需要中间层做协议转换
- 某些 provider 需要自定义请求头或鉴权逻辑，Claude Code 原生不支持
- 通过本地代理可统一管理超时、重试等策略

`ccs moma` 会自动检测并启动 `jt-proxy.py`，无需手动操作。

## 首次使用

运行 `init` 命令，按提示输入 BigModel 和/或九天的 API Key。

## 依赖

- Python 3
- bash
