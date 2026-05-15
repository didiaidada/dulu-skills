# dulu-skills

我的 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 自定义技能集。

## 安装

使用 [skills CLI](https://github.com/vercel-labs/skills)（基于 `npx`）一行安装：

```bash
# 安装全部技能
npx skills add didiaidada/dulu-skills -g --all

# 安装单个技能
npx skills add didiaidada/dulu-skills -g --skill ccs

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
cp -r ccs ~/.claude/skills/
chmod +x ~/.claude/skills/ccs/ccs.sh
```

## 技能

| 技能 | 说明 |
|------|------|
| **ccs** | Claude Code 模型切换 — 一键切换 API 后端（BigModel / 九天）。支持指定模型，使用前需先运行 `init` 配置 API Key |

## 使用方式

安装后重启 Claude Code，即可通过 `/ccs` 或自然语言触发。

```bash
# 直接执行
~/.claude/skills/ccs/ccs.sh init           # 首次配置 API Key
~/.claude/skills/ccs/ccs.sh glm           # 切换到 BigModel（智谱）
~/.claude/skills/ccs/ccs.sh glm glm-4.7   # 切换到 BigModel 并指定模型
~/.claude/skills/ccs/ccs.sh moma          # 切换到 九天（自动启动本地代理）
~/.claude/skills/ccs/ccs.sh moma moonshotai/kimi-k2.6 # 切换到 九天并指定模型
~/.claude/skills/ccs/ccs.sh status        # 查看当前配置

# 设置别名更方便
alias ccs="~/.claude/skills/ccs/ccs.sh"
ccs status
```

## License

MIT
