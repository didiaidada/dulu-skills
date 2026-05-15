# dulu-skills

我的 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 自定义技能集。

## 安装

使用 [skills CLI](https://github.com/vercel-labs/skills)（基于 `npx`）一行安装：

```bash
# 安装全部技能
npx skills add didiaidada/dulu-skills -g --all

# 安装单个技能
npx skills add didiaidada/dulu-skills -g --skill ccmoma

# 查看仓库中有哪些技能
npx skills add didiaidada/dulu-skills -l
```

**参数说明：**

| 参数 | 作用 |
|------|------|
| `-g` | 全局安装到 `~/.claude/skills/`（推荐）。不加则装到当前项目 `.claude/skills/` |
| `--skill <name>` | 指定安装某个技能，可重复使用 |
| `--all` | 安装仓库内全部技能 |
| `-l` | 仅列出可用技能，不安装 |

### 替代方式：手动安装

```bash
mkdir -p ~/.claude/skills
cp -r ccmoma ~/.claude/skills/
chmod +x ~/.claude/skills/ccmoma/ccs.sh
```

## 技能

| 技能 | 说明 |
|------|------|
| **ccmoma** | Claude Code 模型切换 — 一键切换 API 后端（BigModel / 九天）。支持指定模型，使用前需先运行 `init` 配置 API Key |

### 背景

`ccmoma` 是为了让 Claude Code 接入国内 LLM 后端（MOMA / 聚合 API）而写的切换工具。

Claude Code 原生只支持 Anthropic 官方 API，要使用第三方兼容层需要修改环境变量 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN`。`ccmoma` 做的事情就是帮你一键写入这些配置到 `~/.claude/settings.json`。

### 关于 jt-proxy

`jt-proxy.py` 是一个本地代理，解决以下问题：

- MOMA 等聚合 API 的端点格式与 Anthropic SDK 不完全兼容，需要中间层做协议转换
- 某些 provider 需要自定义请求头或鉴权逻辑，Claude Code 原生不支持
- 通过本地代理可统一管理超时、重试等策略

`ccmoma moma` 会自动检测并启动 `jt-proxy.py`，无需手动操作。

## 使用方式

安装后重启 Claude Code，即可通过 `/ccmoma` 或自然语言触发。

```bash
# 直接执行
~/.claude/skills/ccmoma/ccs.sh init           # 首次配置 API Key
~/.claude/skills/ccmoma/ccs.sh glm           # 切换到 BigModel（智谱）
~/.claude/skills/ccmoma/ccs.sh glm glm-4.7   # 切换到 BigModel 并指定模型
~/.claude/skills/ccmoma/ccs.sh moma          # 切换到 九天（自动启动本地代理）
~/.claude/skills/ccmoma/ccs.sh moma deepseek/deepseek-v4-flash # 切换到 九天并指定模型
~/.claude/skills/ccmoma/ccs.sh status        # 查看当前配置

# 设置别名更方便
alias ccs="~/.claude/skills/ccmoma/ccs.sh"
ccs status
```

## License

MIT
