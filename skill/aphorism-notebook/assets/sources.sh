#!/usr/bin/env bash
# 自定义思考方向管理 · aphorism-notebook
#
# 一个"自定义思考方向" = 一段 [代号] 配置：名字 + 素材路径（知识库/笔记/仓库）+ 默认轮数 + 挖掘提示。
# 配置写在 skill 目录的 sources.conf（可用 APHORISM_SOURCES 或 --config 指定）。
#
# 用法：
#   bash <skill-dir>/assets/sources.sh list
#   bash <skill-dir>/assets/sources.sh codes            # 只列代号（给 rounds.sh 用）
#   bash <skill-dir>/assets/sources.sh check            # 校验代号/轮数/路径
#   bash <skill-dir>/assets/sources.sh init             # 建一份带注释的空配置
#   bash <skill-dir>/assets/sources.sh add --name 旧笔记考古 --paths '~/Notes,~/vault' [--code F] [--rounds 5] [--emoji 🗂] [--hint "..."]
#   bash <skill-dir>/assets/sources.sh add --interactive [--input FILE]   # 逐项问（首次安装用）
#   bash <skill-dir>/assets/sources.sh set F rounds 6
#   bash <skill-dir>/assets/sources.sh remove F
set -u

BUILTIN_CODES="A B C D E"
script_dir="$(cd "$(dirname "$0")" && pwd)"
skill_dir="$(dirname "$script_dir")"

warn() { printf 'sources: %s\n' "$*" >&2; }

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

# ---- 参数 ---------------------------------------------------------------

cmd="${1-}"
[ $# -gt 0 ] && shift

config=""
want_help=0
interactive=0
input_src="/dev/tty"
code=""
name=""
paths=""
rounds=""
emoji=""
hint=""
template=""
key=""
value=""

while [ $# -gt 0 ]; do
  case "$1" in
    --config) config="${2-}"; shift 2 ;;
    --input) input_src="${2-}"; shift 2 ;;
    --interactive) interactive=1; shift ;;
    --code) code="${2-}"; shift 2 ;;
    --name) name="${2-}"; shift 2 ;;
    --paths) paths="${2-}"; shift 2 ;;
    --rounds) rounds="${2-}"; shift 2 ;;
    --emoji) emoji="${2-}"; shift 2 ;;
    --hint) hint="${2-}"; shift 2 ;;
    --template) template="${2-}"; shift 2 ;;
    -h|--help) want_help=1; shift ;;
    *)
      case "$cmd" in
        set)
          # set <code> <key> <value>
          if [ -z "$code" ]; then code="$1"
          elif [ -z "$key" ]; then key="$1"
          else value="$1"; fi
          shift
          ;;
        remove)
          # remove <code>
          if [ -z "$code" ]; then code="$1"; shift
          else warn "未知参数：$1"; usage; exit 1; fi
          ;;
        *) warn "未知参数：$1"; usage; exit 1 ;;
      esac
      ;;
  esac
done

[ "$want_help" = "1" ] || [ -z "$cmd" ] && { usage; [ -z "$cmd" ] && exit 1; exit 0; }

config="${config:-${APHORISM_SOURCES:-${skill_dir}/sources.conf}}"

is_builtin() { case " $BUILTIN_CODES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
is_code() { case "$1" in [A-Z]) return 0 ;; *) return 1 ;; esac; }

codes_in_file() { # $1 = 文件
  [ -f "$1" ] || return 0
  sed -n 's/^[[:space:]]*\[\([A-Z]\)\][[:space:]]*$/\1/p' "$1"
}

next_code() { # 找一个没被占用的代号
  used=" $(codes_in_file "$config" | tr '\n' ' ') "
  for c in F G H I J K L M N O P Q R S T U V W X Y Z; do
    case "$used" in *" $c "*) : ;; *) printf '%s' "$c"; return 0 ;; esac
  done
  return 1
}

# ---- init ---------------------------------------------------------------

cmd_init() {
  if [ -f "$config" ]; then
    echo "已存在：${config}"
    return 0
  fi
  mkdir -p "$(dirname "$config")"
  if [ -f "${skill_dir}/sources.example.conf" ]; then
    cp "${skill_dir}/sources.example.conf" "$config"
  else
    printf '# 思笺 · 自定义思考方向（素材来源）\n#\n# 每个 [代号] = 一个自定义思考方向，A–E 是内置模式，自定义方向从 F 开始。\n# 字段：name / paths / rounds / emoji / hint / rounds_template\n' > "$config"
  fi
  echo "✓ 已创建 ${config}"
}

# ---- list / codes -------------------------------------------------------

cmd_list() {
  if [ ! -f "$config" ]; then
    echo "还没有自定义思考方向（${config} 不存在）。"
    echo "加一个：bash assets/sources.sh add --name 旧笔记考古 --paths '~/Notes'"
    return 0
  fi
  awk -v file="$config" '
    function flush() {
      if (code == "") return
      printf "[%s] %s  默认 %s 轮\n", code, (name == "" ? "（未命名）" : name), (rounds == "" ? "4" : rounds)
      if (hint != "") printf "     提示：%s\n", hint
      if (paths != "") printf "     路径：%s\n", paths
      found++
    }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (line == "" || line ~ /^#/) next
      if (line ~ /^\[[A-Z]\]$/) { flush(); code = substr(line, 2, 1); name = ""; paths = ""; rounds = ""; hint = ""; next }
      if (line ~ /^name=/) { name = substr(line, 6); next }
      if (line ~ /^paths=/) { paths = substr(line, 7); next }
      if (line ~ /^rounds=/) { rounds = substr(line, 8); next }
      if (line ~ /^hint=/) { hint = substr(line, 6); next }
      if (line ~ /^emoji=/ || line ~ /^rounds_template=/) next
    }
    END {
      flush()
      if (found == 0) printf "文件里还没有任何方向：%s\n", file
    }
  ' "$config"
  return 0
}

cmd_codes() { codes_in_file "$config"; }

# ---- add ----------------------------------------------------------------

# 逐项问用户；--input 默认 /dev/tty（curl | bash 时 stdin 是脚本，不能读）
ask() { # $1 提示，$2 默认值 → 输出答案
  prompt="$1"; def="${2-}"
  if [ "$def" != "" ]; then prompt="$prompt [$def]"; fi
  printf '%s: ' "$prompt" >&2
  if ! IFS= read -r ans <&3; then
    warn "读不到输入（${input_src}）——跳过自定义方向，之后可以让 Agent 再帮你加。"
    return 1
  fi
  [ -z "$ans" ] && ans="$def"
  printf '%s' "$ans"
}

cmd_add_interactive() {
  # 用一个 fd 读答案：curl | bash 时 stdin 是脚本本身，只能读 /dev/tty；
  # 每次 read 都重定向自文件会把文件重头读，所以这里一次性打开 fd 3。
  if [ "$input_src" = "/dev/tty" ]; then
    if ! exec 3< /dev/tty 2>/dev/null; then
      warn "当前没有可交互的终端，跳过自定义方向；之后可以让 Agent 帮你加。"
      return 1
    fi
  elif ! exec 3< "$input_src" 2>/dev/null; then
    warn "无法读取 ${input_src}，跳过交互式添加。"
    return 1
  fi
  echo "把你自己的知识库 / 笔记目录加成一个思考方向（直接回车用默认值，输入 ! 取消）"
  nm="$(ask '方向名字（例：旧笔记考古）' '' )" || return 1
  [ "$nm" = "!" ] && return 1
  [ -z "$nm" ] && { warn "没给名字，取消。"; return 1; }
  ps="$(ask '素材路径（多个用逗号分隔，支持 ~）' '')" || return 1
  [ -z "$ps" ] && { warn "没给路径，取消。"; return 1; }
  rd="$(ask '默认思考轮数（2–12）' '4')" || return 1
  code="$(next_code)" || { exec 3<&-; warn "代号用完了（F–Z）。"; return 1; }
  exec 3<&-
  apply_add "$code" "$nm" "$ps" "$rd" "" ""
}

apply_add() { # code name paths rounds emoji hint [template]
  a_code="$1"; a_name="$2"; a_paths="$3"; a_rounds="${4:-4}"; a_emoji="${5-}"; a_hint="${6-}"; a_template="${7-}"
  is_code "$a_code" || { warn "代号必须是一个大写字母：$a_code"; return 1; }
  is_builtin "$a_code" && { warn "$a_code 是内置模式代号（A–E），换个字母。"; return 1; }
  if codes_in_file "$config" | grep -qx "$a_code"; then
    warn "代号 $a_code 已经存在（要改就用 set，要删就用 remove）。"
    return 1
  fi
  [ -n "$a_name" ] || { warn "缺少 --name"; return 1; }
  [ -n "$a_paths" ] || { warn "缺少 --paths"; return 1; }
  case "$a_rounds" in ''|*[!0-9]*) warn "轮数必须是数字：$a_rounds"; return 1 ;; esac
  a_rounds="$(clamp_rounds "$a_rounds")"
  [ -f "$config" ] || cmd_init >/dev/null
  {
    printf '\n[%s]\n' "$a_code"
    printf 'name=%s\n' "$a_name"
    [ -n "$a_emoji" ] && printf 'emoji=%s\n' "$a_emoji"
    printf 'paths=%s\n' "$a_paths"
    printf 'rounds=%s\n' "$a_rounds"
    [ -n "$a_hint" ] && printf 'hint=%s\n' "$a_hint"
    [ -n "$a_template" ] && printf 'rounds_template=%s\n' "$a_template"
  } >> "$config"
  echo "✓ 已添加 [${a_code}] ${a_name}（${a_rounds} 轮）→ $config"
  check_paths "$a_paths"
}

clamp_rounds() {
  n="$1"
  [ "$n" -lt 2 ] && n=2
  [ "$n" -gt 12 ] && n=12
  echo "$n"
}

check_paths() { # 逐个看路径是否可访问；不存在只提醒，不拦
  IFS=','
  for p in $1; do
    unset IFS
    p="$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$p" ] && { IFS=','; continue; }
    case "$p" in "~/"*) p="$HOME/${p#\~/}" ;; "~") p="$HOME" ;; esac
    case "$p" in
      *'*'*|*'?'*)
        found=0
        for f in $p; do [ -e "$f" ] && found=1; done
        [ "$found" = "1" ] && printf '     ✓ %s\n' "$p" || printf '     ? %s（通配没匹配到，先记着）\n' "$p"
        ;;
      *)
        [ -e "$p" ] && printf '     ✓ %s\n' "$p" || printf '     ✗ %s（现在读不到，之后再改）\n' "$p"
        ;;
    esac
    IFS=','
  done
  unset IFS
  return 0
}

cmd_add() {
  if [ "$interactive" = "1" ]; then cmd_add_interactive; return $?; fi
  [ -z "$code" ] && code="$(next_code)" || true
  apply_add "$code" "$name" "$paths" "$rounds" "$emoji" "$hint" "$template"
}

# ---- set / remove -------------------------------------------------------

cmd_set() {
  [ -n "$code" ] && [ -n "$key" ] || { warn "用法：set <代号> <字段> <值>"; return 1; }
  [ -f "$config" ] || { warn "没有配置文件：$config"; return 1; }
  codes_in_file "$config" | grep -qx "$code" || { warn "没有这个方向：$code"; return 1; }
  case "$key" in
    name|paths|rounds|emoji|hint|rounds_template) : ;;
    *) warn "不认识的字段：${key}（可选 name/paths/rounds/emoji/hint/rounds_template）"; return 1 ;;
  esac
  if [ "$key" = "rounds" ]; then
    case "$value" in ''|*[!0-9]*) warn "轮数必须是数字：$value"; return 1 ;; esac
    value="$(clamp_rounds "$value")"
  fi
  tmp="${config}.tmp.$$"
  awk -v code="$code" -v key="$key" -v val="$value" '
    BEGIN { insec = 0; done = 0 }
    /^[[:space:]]*\[[A-Z]\][[:space:]]*$/ {
      if (insec && !done) { print key "=" val; done = 1 }
      insec = ($0 ~ "^[[:space:]]*\\[" code "\\][[:space:]]*$")
      print; next
    }
    {
      if (insec && $0 ~ "^[[:space:]]*" key "=") { print key "=" val; done = 1; next }
      print
    }
    END { if (insec && !done) print key "=" val }
  ' "$config" > "$tmp" && mv "$tmp" "$config"
  echo "✓ [${code}] ${key}=${value}"
}

cmd_remove() {
  [ -n "$code" ] || { warn "用法：remove <代号>"; return 1; }
  [ -f "$config" ] || { warn "没有配置文件：$config"; return 1; }
  codes_in_file "$config" | grep -qx "$code" || { warn "没有这个方向：$code"; return 1; }
  tmp="${config}.tmp.$$"
  awk -v code="$code" '
    /^[[:space:]]*\[[A-Z]\][[:space:]]*$/ { skip = ($0 ~ "^[[:space:]]*\\[" code "\\][[:space:]]*$"); if (!skip) print; next }
    { if (!skip) print }
  ' "$config" > "$tmp" && mv "$tmp" "$config"
  echo "✓ 已删除 [${code}]"
}

# ---- check --------------------------------------------------------------

cmd_check() {
  [ -f "$config" ] || { echo "没有自定义方向（$config 不存在）——这不算错误。"; return 0; }
  errs=0
  while IFS= read -r c; do
    is_builtin "$c" && { warn "[$c] 与内置模式代号冲突"; errs=$((errs + 1)); }
  done <<EOF
$(codes_in_file "$config")
EOF
  cur=""; nm=""; ps=""; rd=""
  flush() {
    [ -z "$cur" ] && return 0
    [ -z "$nm" ] && { warn "[$cur] 缺 name"; errs=$((errs + 1)); }
    [ -z "$ps" ] && { warn "[$cur] 缺 paths"; errs=$((errs + 1)); }
    case "$rd" in ''|*[!0-9]*) warn "[$cur] rounds 不是 2–12 的数字：${rd:-（空）}"; errs=$((errs + 1)) ;; esac
  }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      \[*\]) flush; cur="$(printf '%s' "$line" | tr -d '[]')"; nm=""; ps=""; rd="" ;;
      name=*) nm="${line#name=}" ;;
      paths=*) ps="${line#paths=}" ;;
      rounds=*) rd="${line#rounds=}" ;;
    esac
  done < "$config"
  flush
  if [ "$errs" -gt 0 ]; then
    echo "✗ $errs 处问题（${config}）" >&2
    return 1
  fi
  echo "✓ 自定义方向配置正常：$(codes_in_file "$config" | tr '\n' ' ')"
}

case "$cmd" in
  init) cmd_init ;;
  list) cmd_list ;;
  codes) cmd_codes ;;
  add) cmd_add ;;
  set) cmd_set ;;
  remove) cmd_remove ;;
  check) cmd_check ;;
  path) echo "$config" ;;
  -h|--help) usage ;;
  *) warn "未知子命令：$cmd"; usage; exit 1 ;;
esac
