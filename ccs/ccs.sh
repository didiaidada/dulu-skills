#!/bin/bash
# ccs - Claude Code API 配置切换工具
# 用法:
#   ccs glm             BigModel (需要先配置 BM_API_KEY)
#   ccs moma [model]    九天 (MOMA) (需要先配置 JT_API_KEY + 本地代理)
#   ccs init            首次初始化 API Key
#   ccs status          查看当前配置

SETTINGS="$HOME/.claude/settings.json"
CONFIG="$HOME/.claude/ccs-config.json"

# --- 读取或初始化用户配置 ---
if [ ! -f "$CONFIG" ]; then
  # 创建默认配置
  cat > "$CONFIG" <<'CONFEOF'
{
  "bigmodel": {
    "api_key": "",
    "base_url": "https://open.bigmodel.cn/api/anthropic",
    "haiku_model": "glm-4.7",
    "sonnet_model": "GLM-5",
    "opus_model": "GLM-5.1",
    "model_flag": "opus[1m]"
  },
  "jiutian": {
    "api_key": "",
    "base_url": "http://127.0.0.1:8976",
    "opus_model": "moonshotai/kimi-k2.6",
    "model_flag": "opus"
  },
}
CONFEOF
fi

# --- 配置定义 ---
bigmodel_env() {
  local key
  key=$(python3 -c "import json; print(json.load(open('$CONFIG'))['bigmodel']['api_key'])" 2>/dev/null)
  cat <<EOF
{
  "ANTHROPIC_AUTH_TOKEN": "$key",
  "ANTHROPIC_BASE_URL": "$(python3 -c "import json; print(json.load(open('$CONFIG'))['bigmodel']['base_url'])")",
  "API_TIMEOUT_MS": "3000000",
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL": "$(python3 -c "import json; print(json.load(open('$CONFIG'))['bigmodel']['haiku_model'])")",
  "ANTHROPIC_DEFAULT_SONNET_MODEL": "$(python3 -c "import json; print(json.load(open('$CONFIG'))['bigmodel']['sonnet_model'])")",
  "ANTHROPIC_DEFAULT_OPUS_MODEL": "$(python3 -c "import json; print(json.load(open('$CONFIG'))['bigmodel']['opus_model'])")"
}
EOF
}
bigmodel_model() { python3 -c "import json; print(json.load(open('$CONFIG'))['bigmodel']['model_flag'])"; }

jiutian_env() {
  local key
  key=$(python3 -c "import json; print(json.load(open('$CONFIG'))['jiutian']['api_key'])" 2>/dev/null)
  cat <<EOF
{
  "ANTHROPIC_AUTH_TOKEN": "$key",
  "ANTHROPIC_BASE_URL": "$(python3 -c "import json; print(json.load(open('$CONFIG'))['jiutian']['base_url'])")",
  "API_TIMEOUT_MS": "3000000",
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
  "ANTHROPIC_DEFAULT_OPUS_MODEL": "$(python3 -c "import json; print(json.load(open('$CONFIG'))['jiutian']['opus_model'])")"
}
EOF
}
jiutian_model() { python3 -c "import json; print(json.load(open('$CONFIG'))['jiutian']['model_flag'])"; }

# --- 工具函数 ---
switch_to() {
  local profile="$1"
  local env_data="$2"
  local model_val="$3"
  local custom_model="$4"

  if [ -n "$custom_model" ]; then
    env_data=$(echo "$env_data" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['ANTHROPIC_DEFAULT_OPUS_MODEL'] = '$custom_model'
json.dump(d, sys.stdout)
")
    profile="$profile ($custom_model)"
  fi

  python3 -c "
import sys, json

with open('$SETTINGS', 'r') as f:
    s = json.load(f)

s['env'] = json.loads('''$env_data''')
s['model'] = '$model_val'

with open('$SETTINGS', 'w') as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
"
  echo "已切换到: $profile"
}

show_status() {
  local base_url model
  base_url=$(python3 -c "import json; print(json.load(open('$SETTINGS'))['env'].get('ANTHROPIC_BASE_URL',''))")
  model=$(python3 -c "import json; print(json.load(open('$SETTINGS')).get('model',''))")
  local opus=$(python3 -c "import json; print(json.load(open('$SETTINGS'))['env'].get('ANTHROPIC_DEFAULT_OPUS_MODEL',''))")

  echo "当前配置:"
  echo "  Base URL : $base_url"
  echo "  Model    : $model → $opus"
}

init_config() {
  echo "=== ccs 首次初始化 ==="
  echo ""

  # BigModel
  read -p "BigModel API Key (留空跳过): " bm_key
  if [ -n "$bm_key" ]; then
    python3 -c "
import json
c = json.load(open('$CONFIG'))
c['bigmodel']['api_key'] = '$bm_key'
json.dump(c, open('$CONFIG','w'), indent=2)
"
    echo "  BigModel API Key ✓ 已保存"
  fi

  echo ""

  # 九天
  read -p "九天 API Key (留空跳过): " jt_key
  if [ -n "$jt_key" ]; then
    python3 -c "
import json
c = json.load(open('$CONFIG'))
c['jiutian']['api_key'] = '$jt_key'
json.dump(c, open('$CONFIG','w'), indent=2)
"
    echo ""
    echo "九天还需要启动本地代理，执行:"
    echo "  nohup python3 ~/bin/jt-proxy.py &"
    echo "  （也可设置开机自启）"
  fi

  echo ""
  echo "初始化完成！配置保存在: $CONFIG"
  echo ""
  echo "使用方式:"
  echo "  ccs glm             BigModel"
  echo "  ccs moma [model]    九天 (MOMA)"
}

# --- 主逻辑 ---
case "${1:-}" in
  init|setup)
    init_config
    ;;
  glm|bigmodel)
    switch_to "BigModel" "$(bigmodel_env)" "$(bigmodel_model)" "${2:-}"
    ;;
  moma|jiutian)
    switch_to "九天" "$(jiutian_env)" "$(jiutian_model)" "${2:-}"
    ;;
  status|show|s)
    show_status
    ;;
  *)
    echo "用法: ccs <command>"
    echo ""
    echo "命令:"
    echo "  init            首次初始化 API Key"
    echo "  glm [model]     BigModel(智谱)"
    echo "  moma [model]    九天 (MOMA)"
    echo "  status          查看当前配置"
    ;;
esac
