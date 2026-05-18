#!/bin/bash
# ccmoma - Claude Code API 配置切换工具
# 用法:
#   ccmoma init            首次初始化（保存当前 Key + 配置 moma）
#   ccmoma <name>          切换到自定义 profile
#   ccmoma glm [model]     BigModel
#   ccmoma moma [model]    九天 (MOMA)
#   ccmoma status          查看当前配置

SETTINGS="$HOME/.claude/settings.json"
CONFIG="$HOME/.claude/ccmoma-config.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- 读取或初始化用户配置 ---
if [ ! -f "$CONFIG" ]; then
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
    "opus_model": "deepseek/deepseek-v4-flash",
    "model_flag": "opus"
  },
  "custom_profiles": {}
}
CONFEOF
fi

# 确保 custom_profiles 字段存在（兼容旧配置）
python3 -c "
import json
c = json.load(open('$CONFIG'))
if 'custom_profiles' not in c:
    c['custom_profiles'] = {}
    json.dump(c, open('$CONFIG','w'), indent=2)
"

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

# --- 自定义 profile ---
custom_profile_env() {
  local name="$1"
  python3 -c "
import json
c = json.load(open('$CONFIG'))
p = c['custom_profiles']['$name']
json.dump({
    'ANTHROPIC_AUTH_TOKEN': p['api_key'],
    'ANTHROPIC_BASE_URL': p['base_url'],
    'API_TIMEOUT_MS': '3000000',
    'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1'
}, sys.stdout)
" 2>/dev/null
}

custom_profile_names() {
  python3 -c "import json; print(' '.join(json.load(open('$CONFIG')).get('custom_profiles',{}).keys()))" 2>/dev/null
}

has_custom_profile() {
  python3 -c "import json,sys; sys.exit(0 if '$1' in json.load(open('$CONFIG')).get('custom_profiles',{}) else 1)" 2>/dev/null
}

# --- 检查 API Key 是否可用 ---
check_api_key() {
  local base_url="$1"
  local api_key="$2"

  if [ -z "$api_key" ]; then
    echo "MISSING"
    return
  fi

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$base_url/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"test","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
    --connect-timeout 5 --max-time 10 2>/dev/null)

  # 2xx 或 4xx（auth ok but model error）都算 key 有效
  # 401/403 = key 无效, 000 = 连接失败
  if [ "$status" = "000" ]; then
    echo "CONNECTION_FAILED"
  elif [ "$status" = "401" ] || [ "$status" = "403" ]; then
    echo "INVALID"
  else
    echo "OK"
  fi
}

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

  # 提取即将使用的 key 和 base_url 用于检查
  local target_key target_url
  target_key=$(echo "$env_data" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ANTHROPIC_AUTH_TOKEN',''))" 2>/dev/null)
  target_url=$(echo "$env_data" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)

  # 检查 key 是否存在
  if [ -z "$target_key" ]; then
    echo "❌ $profile 未配置 API Key"
    echo "   请先运行: ccmoma init"
    return 1
  fi

  # 测试 key 是否可用
  echo "⏳ 测试 $profile API Key ..."
  local check_result
  check_result=$(check_api_key "$target_url" "$target_key")

  if [ "$check_result" = "CONNECTION_FAILED" ]; then
    echo "❌ 无法连接到 $target_url"
    echo "   如果是九天，确认 jt-proxy 是否在运行"
    return 1
  elif [ "$check_result" = "INVALID" ]; then
    echo "❌ API Key 无效（401/403）"
    echo "   请检查配置: ccmoma init"
    return 1
  fi

  # 备份当前配置（用于回滚）
  local backup_env backup_model
  backup_env=$(python3 -c "
import json
s = json.load(open('$SETTINGS'))
print(json.dumps(s.get('env',{})))
" 2>/dev/null)
  backup_model=$(python3 -c "
import json
s = json.load(open('$SETTINGS'))
print(s.get('model',''))
" 2>/dev/null)

  # 执行切换
  python3 -c "
import sys, json

with open('$SETTINGS', 'r') as f:
    s = json.load(f)

s['env'] = json.loads('''$env_data''')
s['model'] = '$model_val'

with open('$SETTINGS', 'w') as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
"
  echo "✓ 已切换到: $profile"
}

show_status() {
  local base_url model opus
  base_url=$(python3 -c "import json; print(json.load(open('$SETTINGS'))['env'].get('ANTHROPIC_BASE_URL',''))")
  model=$(python3 -c "import json; print(json.load(open('$SETTINGS')).get('model',''))")
  opus=$(python3 -c "import json; print(json.load(open('$SETTINGS'))['env'].get('ANTHROPIC_DEFAULT_OPUS_MODEL',''))")

  echo "当前配置:"
  echo "  Base URL : $base_url"
  echo "  Model    : $model → $opus"

  local profiles
  profiles=$(custom_profile_names)
  if [ -n "$profiles" ]; then
    echo ""
    echo "自定义 profiles:"
    for name in $profiles; do
      local p_url
      p_url=$(python3 -c "import json; print(json.load(open('$CONFIG'))['custom_profiles']['$name']['base_url'])")
      echo "  $name → $p_url"
    done
  fi
}

init_config() {
  echo "=== ccmoma 初始化 ==="
  echo ""

  # 1. 检测并保存当前 Key
  local cur_key cur_url
  cur_key=$(python3 -c "
import json
s = json.load(open('$SETTINGS'))
print(s.get('env',{}).get('ANTHROPIC_AUTH_TOKEN',''))
" 2>/dev/null)
  cur_url=$(python3 -c "
import json
s = json.load(open('$SETTINGS'))
print(s.get('env',{}).get('ANTHROPIC_BASE_URL','https://api.anthropic.com'))
" 2>/dev/null)

  if [ -n "$cur_key" ]; then
    echo "检测到当前 API Key: ${cur_key:0:8}...${cur_key: -4}"
    echo "  Base URL: $cur_url"

    # 根据 base_url 自动识别 provider
    local bm_url
    bm_url=$(python3 -c "import json; print(json.load(open('$CONFIG'))['bigmodel']['base_url'])")
    if [ "$cur_url" = "$bm_url" ]; then
      # 自动填入 BigModel
      python3 -c "
import json
c = json.load(open('$CONFIG'))
c['bigmodel']['api_key'] = '$cur_key'
json.dump(c, open('$CONFIG','w'), indent=2)
"
      echo "  ✓ 自动识别为 BigModel，已保存"
    else
      echo ""
      read -p "给当前 Key 起个名字用于切换 (默认 anthropic): " key_name
      key_name="${key_name:-anthropic}"

      python3 -c "
import json
c = json.load(open('$CONFIG'))
c.setdefault('custom_profiles', {})['$key_name'] = {
    'api_key': '$cur_key',
    'base_url': '$cur_url'
}
json.dump(c, open('$CONFIG','w'), indent=2)
"
      echo "  ✓ 已保存为 profile: $key_name"
    fi
    echo ""
  else
    echo "未检测到当前 API Key，跳过保存。"
    echo ""
  fi

  # 2. BigModel（如果还没配过 key 才提示）
  local cur_bm_key
  cur_bm_key=$(python3 -c "import json; print(json.load(open('$CONFIG'))['bigmodel']['api_key'])" 2>/dev/null)
  if [ -z "$cur_bm_key" ]; then
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
  fi

  echo ""

  # 3. 九天（如果还没配过 key 才提示）
  local cur_jt_key
  cur_jt_key=$(python3 -c "import json; print(json.load(open('$CONFIG'))['jiutian']['api_key'])" 2>/dev/null)
  if [ -z "$cur_jt_key" ]; then
    read -p "九天 API Key (留空跳过): " jt_key
    if [ -n "$jt_key" ]; then
      python3 -c "
import json
c = json.load(open('$CONFIG'))
c['jiutian']['api_key'] = '$jt_key'
json.dump(c, open('$CONFIG','w'), indent=2)
"
      echo "  九天 API Key ✓ 已保存"
      echo ""
      echo "九天还需要启动本地代理，执行:"
      echo "  nohup python3 ~/.claude/skills/ccmoma/jt-proxy.py &"
      echo "  （也可设置开机自启）"
    fi
  fi

  echo ""
  echo "初始化完成！配置保存在: $CONFIG"
  echo ""
  echo "使用方式:"
  echo "  ccmoma <name>          切换到自定义 profile"
  echo "  ccmoma glm [model]     BigModel"
  echo "  ccmoma moma [model]    九天 (MOMA)"
  echo "  ccmoma status          查看所有配置"
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
    # 先启动 jt-proxy（如果没运行）
    if ! pgrep -f jt-proxy.py > /dev/null 2>&1; then
      proxy_path="$SCRIPT_DIR/jt-proxy.py"
      if [ ! -f "$proxy_path" ]; then
        proxy_path="$HOME/.claude/skills/ccmoma/jt-proxy.py"
      fi
      if [ -f "$proxy_path" ]; then
        nohup python3 "$proxy_path" > /dev/null 2>&1 &
        sleep 1
        echo "jt-proxy 已自动启动"
      fi
    fi
    if ! switch_to "九天" "$(jiutian_env)" "$(jiutian_model)" "${2:-}"; then
      # 切换失败，无需额外处理（switch_to 没写入 settings）
      :
    fi
    ;;
  status|show|s)
    show_status
    ;;
  *)
    # 尝试匹配自定义 profile
    if has_custom_profile "${1:-}" 2>/dev/null; then
      env_data=$(custom_profile_env "$1")
      if ! switch_to "$1" "$env_data" "$1" "${2:-}"; then
        :
      fi
    else
      echo "用法: ccmoma <command>"
      echo ""
      echo "命令:"
      echo "  init            初始化（保存当前 Key + 配置 moma）"
      echo "  glm [model]     BigModel(智谱)"
      echo "  moma [model]    九天 (MOMA)"
      echo "  status          查看当前配置"
      echo "  <name>          切换到自定义 profile"
      local profiles
      profiles=$(custom_profile_names)
      if [ -n "$profiles" ]; then
        echo ""
        echo "已保存的 profiles: $profiles"
      fi
    fi
    ;;
esac
