#!/usr/bin/env bash
# 思考强度解析器 · aphorism-notebook
#
# 把「思考强度配置」解析成五个模式本次各走多少轮。配置优先级（高 → 低）：
#   1. 环境变量 APHORISM_THINKING_ROUNDS
#   2. 环境变量 APHORISM_THINKING_LEVEL
#   3. skill 目录下的 config.env（插件内配置，变量名同上）
#   4. 内置默认：A4 B3 C5 D3 E3
#
# 自定义思考方向（sources.conf 里的 [F] [G] ...）会自动进入这张表，
# 它们的档位按各自默认轮数推导：light −1 / standard ±0 / deep +2 / max +4。
#
# 用法：
#   bash <skill-dir>/assets/rounds.sh                 # 按当前环境解析
#   bash <skill-dir>/assets/rounds.sh --defaults      # 忽略一切配置，只看默认
#   bash <skill-dir>/assets/rounds.sh --level deep --rounds 'C=8'
#   bash <skill-dir>/assets/rounds.sh --config ./config.env --sources ./sources.conf
#   bash <skill-dir>/assets/rounds.sh --no-sources    # 只算内置 A–E
#
# 退出码：0 = 解析成功（配置有错只在 stderr 提醒并回落）；1 = 参数错误。
set -u

BUILTIN_MODES="A B C D E"
MODE_LIST="$BUILTIN_MODES"
MIN_ROUNDS=2
MAX_ROUNDS=12

# 自定义思考方向（从 sources.conf 读入）
EXTRA_CODES=""
EXTRA_DEFAULTS=""   # "F=5 G=4"
EXTRA_NAMES=""      # 每行 "F|书摘本"

warn() { printf 'rounds: %s\n' "$*" >&2; }

extra_default() { # $1 = 自定义方向代号 → 默认轮数
  for kv in $EXTRA_DEFAULTS; do
    [ "${kv%%=*}" = "$1" ] && { printf '%s' "${kv#*=}"; return 0; }
  done
  return 1
}

extra_name() { # $1 = 代号 → 名字
  printf '%s\n' "$EXTRA_NAMES" | awk -F'|' -v c="$1" '$1 == c { print $2 }'
}

default_of() { # $1 = 模式代号
  case "$1" in
    A) echo 4; return 0 ;;
    B) echo 3; return 0 ;;
    C) echo 5; return 0 ;;
    D) echo 3; return 0 ;;
    E) echo 3; return 0 ;;
  esac
  extra_default "$1" 2>/dev/null || echo 4
}

# 档位表：level/mode → 轮数。内置 A–E 用固定表；自定义方向按默认值 + 偏移推导。
level_of() {
  case "$1/$2" in
    light/A) echo 3; return 0 ;; light/B) echo 2; return 0 ;; light/C) echo 4; return 0 ;;
    light/D) echo 2; return 0 ;; light/E) echo 2; return 0 ;;
    standard/A) echo 4; return 0 ;; standard/B) echo 3; return 0 ;; standard/C) echo 5; return 0 ;;
    standard/D) echo 3; return 0 ;; standard/E) echo 3; return 0 ;;
    deep/A) echo 6; return 0 ;; deep/B) echo 5; return 0 ;; deep/C) echo 7; return 0 ;;
    deep/D) echo 5; return 0 ;; deep/E) echo 5; return 0 ;;
    max/A) echo 8; return 0 ;; max/B) echo 7; return 0 ;; max/C) echo 10; return 0 ;;
    max/D) echo 7; return 0 ;; max/E) echo 7; return 0 ;;
  esac
  case " $BUILTIN_MODES " in *" $2 "*) return 1 ;; esac
  d="$(default_of "$2")" || return 1
  case "$1" in
    light) echo "$(clamp $((d - 1)))" ;;
    standard) echo "$(clamp "$d")" ;;
    deep) echo "$(clamp $((d + 2)))" ;;
    max) echo "$(clamp $((d + 4)))" ;;
    *) return 1 ;;
  esac
}

clamp() {
  n="$1"
  [ "$n" -lt "$MIN_ROUNDS" ] && n=$MIN_ROUNDS
  [ "$n" -gt "$MAX_ROUNDS" ] && n=$MAX_ROUNDS
  echo "$n"
}

is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# ---- 参数 ---------------------------------------------------------------

arg_rounds=""
arg_level=""
arg_config=""
arg_sources=""
use_config=1
use_sources=1

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --rounds) arg_rounds="${2-}"; shift 2 ;;
    --level) arg_level="${2-}"; shift 2 ;;
    --config) arg_config="${2-}"; shift 2 ;;
    --sources) arg_sources="${2-}"; shift 2 ;;
    --no-sources) use_sources=0; shift ;;
    --defaults) use_config=0; use_sources=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "未知参数：$1"; usage; exit 1 ;;
  esac
done

# ---- 读 config.env（只解析这两个键，不 source） --------------------------

script_dir="$(cd "$(dirname "$0")" && pwd)"
skill_dir="$(dirname "$script_dir")"
config_path="${arg_config:-${APHORISM_CONFIG:-${skill_dir}/config.env}}"

read_config_key() { # $1 = 文件，$2 = 键名。同名键写多次时，最后一条非空值生效；留空 = 不用。
  [ -n "${1-}" ] && [ -f "$1" ] || return 1
  found=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/[[:space:]]*=[[:space:]]*/=/; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      "$2="*|"export $2="*) : ;;
      *) continue ;;
    esac
    value="${line#*=}"
    value="$(printf '%s' "$value" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    [ -n "$value" ] && found="$value"
  done < "$1"
  [ -n "$found" ] || return 1
  printf '%s' "$found"
}

rounds_src=""
level_src=""
rounds="${arg_rounds:-}"
level="${arg_level:-}"

if [ -n "$rounds" ]; then
  rounds_src="命令行 --rounds"
elif [ -n "${APHORISM_THINKING_ROUNDS-}" ]; then
  rounds="${APHORISM_THINKING_ROUNDS}"; rounds_src="环境变量 APHORISM_THINKING_ROUNDS"
elif [ "$use_config" = "1" ]; then
  rounds="$(read_config_key "$config_path" APHORISM_THINKING_ROUNDS || true)"
  [ -n "$rounds" ] && rounds_src="config.env ${config_path}"
fi

if [ -n "$level" ]; then
  level_src="命令行 --level"
elif [ -n "${APHORISM_THINKING_LEVEL-}" ]; then
  level="${APHORISM_THINKING_LEVEL}"; level_src="环境变量 APHORISM_THINKING_LEVEL"
elif [ "$use_config" = "1" ]; then
  level="$(read_config_key "$config_path" APHORISM_THINKING_LEVEL || true)"
  [ -n "$level" ] && level_src="config.env ${config_path}"
fi

[ "$use_config" = "0" ] && { rounds=""; level=""; rounds_src=""; level_src=""; }

# ---- 读 sources.conf：自定义思考方向 ------------------------------------

sources_path="${arg_sources:-${APHORISM_SOURCES:-${skill_dir}/sources.conf}}"

parse_sources() { # $1 = 文件
  src="$1"
  [ -f "$src" ] || return 0
  cur=""; cname=""; crounds=""
  flush_extra() {
    [ -z "$cur" ] && return 0
    case " $BUILTIN_MODES " in *" $cur "*) return 0 ;; esac
    case " $EXTRA_CODES " in *" $cur "*) return 0 ;; esac
    [ -z "$crounds" ] && crounds=4
    case "$crounds" in ''|*[!0-9]*) warn "方向 [$cur] 的 rounds 不是数字（${crounds}），按 4 算"; crounds=4 ;; esac
    crounds="$(clamp "$crounds")"
    EXTRA_CODES="$EXTRA_CODES $cur"
    EXTRA_DEFAULTS="$EXTRA_DEFAULTS $cur=$crounds"
    EXTRA_NAMES="${EXTRA_NAMES}${cur}|${cname}
"
  }
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      '['?' ]'|'['?']')
        flush_extra
        cur="$(printf '%s' "$line" | tr -d '[]')"
        cname=""; crounds=""
        ;;
      name=*) cname="${line#name=}" ;;
      rounds=*) crounds="${line#rounds=}" ;;
    esac
  done < "$src"
  flush_extra
  EXTRA_CODES="${EXTRA_CODES# }"
  EXTRA_DEFAULTS="${EXTRA_DEFAULTS# }"
  MODE_LIST="$BUILTIN_MODES $EXTRA_CODES"
}

if [ "$use_sources" = "1" ]; then
  parse_sources "$sources_path"
fi

# ---- 基准：档位 or 默认 --------------------------------------------------

base_level=""
if [ -n "$level" ]; then
  base_level="$(printf '%s' "$level" | tr '[:upper:]' '[:lower:]')"
  if ! level_of "$base_level" A >/dev/null 2>&1; then
    warn "未知档位 '${level}'（可选 light/standard/deep/max），已回落默认"
    base_level=""
  fi
fi

PLAN=""
for m in $MODE_LIST; do
  if [ -n "$base_level" ]; then v="$(level_of "$base_level" "$m")"; else v="$(default_of "$m")"; fi
  PLAN="${PLAN} ${m}=${v}"
done
PLAN="${PLAN# }"

plan_get() {
  local IFS=' '
  for kv in $PLAN; do
    if [ "${kv%%=*}" = "$1" ]; then printf '%s' "${kv#*=}"; return 0; fi
  done
  return 1
}

plan_set() {
  local IFS=' '
  next=""
  for kv in $PLAN; do
    if [ "${kv%%=*}" = "$1" ]; then next="${next} $1=$2"; else next="${next} ${kv}"; fi
  done
  PLAN="${next# }"
}

# ---- 应用 APHORISM_THINKING_ROUNDS --------------------------------------

offset=0
global_abs=""
mode_abs=""

if [ -n "$rounds" ]; then
  IFS=','
  for tok_raw in $rounds; do
    tok="$(printf '%s' "$tok_raw" | tr -d '[:space:]')"
    [ -z "$tok" ] && continue
    case "$tok" in
      [A-Z]=*)
        m="${tok%%=*}"; n="${tok#*=}"
        case " $MODE_LIST " in
          *" $m "*) : ;;
          *) warn "模式 '${m}' 不在本次的思考方向里（A–E + sources.conf 的自定义方向），已忽略"; continue ;;
        esac
        if is_number "$n"; then plan_set "$m" "$(clamp "$n")"; mode_abs="${mode_abs} ${m}"
        else warn "模式覆盖 '${tok}' 不是数字，已忽略"; fi
        ;;
      +*|-*)
        n="${tok#?}"; sign="${tok%"$n"}"
        if is_number "$n"; then
          if [ "$sign" = "-" ]; then offset=$((offset - n)); else offset=$((offset + n)); fi
        else warn "偏移 '${tok}' 不是数字，已忽略"; fi
        ;;
      [0-9]*)
        if is_number "$tok"; then global_abs="$tok"; else warn "轮数 '${tok}' 不是数字，已忽略"; fi
        ;;
      *)
        warn "看不懂的配置 '${tok}'（支持 7 / +2 / -1 / A=6 / C=8,+1 / F=6），已忽略"
        ;;
    esac
  done
  unset IFS
fi

summary=""
if [ -n "$mode_abs" ]; then
  for m in $MODE_LIST; do
    cur="$(plan_get "$m")"
    case " $mode_abs " in *" $m "*) : ;; *)
      if [ -n "$global_abs" ]; then plan_set "$m" "$(clamp "$global_abs")"
      elif [ "$offset" != "0" ]; then plan_set "$m" "$(clamp $((cur + offset)))"; fi
      ;;
    esac
    summary="${summary} ${m}$(plan_get "$m")"
  done
else
  for m in $MODE_LIST; do
    cur="$(plan_get "$m")"
    if [ -n "$global_abs" ]; then plan_set "$m" "$(clamp "$global_abs")"
    elif [ "$offset" != "0" ]; then plan_set "$m" "$(clamp $((cur + offset)))"; fi
    summary="${summary} ${m}$(plan_get "$m")"
  done
fi
summary="${summary# }"

# ---- 输出 ---------------------------------------------------------------

level_label="$level"; [ -n "$level_label" ] || level_label="（未设置）"
rounds_label="$rounds"; [ -n "$rounds_label" ] || rounds_label="（未设置）"
level_note=""; [ -n "$level_src" ] && level_note=" （${level_src}）"
rounds_note=""; [ -n "$rounds_src" ] && rounds_note=" （${rounds_src}）"
if [ -n "$base_level" ]; then level_used="$base_level"; else level_used="default"; fi

printf '# 思考强度解析 · aphorism-notebook\n'
printf '# level  : %s%s\n' "$level_label" "$level_note"
printf '# rounds : %s%s\n' "$rounds_label" "$rounds_note"
if [ "$use_config" = "1" ] && [ -f "$config_path" ]; then
  printf '# config : %s\n' "$config_path"
elif [ "$use_config" = "1" ]; then
  printf '# config : 未找到（可 cp config.example.env config.env）\n'
else
  printf '# config : 已忽略（--defaults）\n'
fi
printf '计划轮数：%s\n\n' "$summary"
printf '模式  默认  本次  档位\n'
for m in $MODE_LIST; do
  printf '%s     %s     %s     %s\n' "$m" "$(default_of "$m")" "$(plan_get "$m")" "$level_used"
done
if [ -n "$EXTRA_CODES" ]; then
  printf '自定义方向（%s）：' "$sources_path"
  for c in $EXTRA_CODES; do
    printf '%s %s  ' "$c" "$(extra_name "$c")"
  done
  printf '\n'
fi
printf '\n轮数范围 %s–%s；不足按「加轮表/通用加轮池」补，超出按删减顺序裁，必留轮不能删。\n' "$MIN_ROUNDS" "$MAX_ROUNDS"
