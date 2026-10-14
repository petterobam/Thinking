#!/usr/bin/env bash
# 思考强度契约测试 · aphorism-notebook
#
#   bash scripts/test-skill-rounds.sh
#
# 覆盖：内置默认值 / 四个档位 / 整数 / 偏移 / 逐模式 / 混用 / 夹取 / 非法输入回落 /
#        config.env 解析（同名键、引号、空格、行内注释）/ 环境变量优先级 /
#        自定义思考方向（sources.conf）：默认轮数、档位推导、逐模式覆盖、与内置代号冲突。
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/skill/aphorism-notebook/assets/rounds.sh"
SKILL_DIR="$ROOT/skill/aphorism-notebook"

[ -f "$S" ] || { echo "找不到 $S" >&2; exit 1; }

pass=0
fail=0
tmp="$(mktemp -d)"

cleanup() {
  node -e "try{require('fs').unlinkSync(process.argv[1])}catch(e){}" "$SKILL_DIR/config.env"
  node -e "try{require('fs').rmSync(process.argv[1],{recursive:true,force:true})}catch(e){}" "$tmp"
}
trap cleanup EXIT

# 默认把 sources / config 指向不存在的文件，避免受本机(或刚写下的)配置影响
SRC="$tmp/no-sources.conf"
CFG="$tmp/no-config.env"

plan() { env "$@" bash "$S" --config "${CFG:-$tmp/no-config.env}" --sources "$SRC" 2>/dev/null | sed -n 's/^计划轮数：//p'; }

check() { # $1 = 描述, $2 = 期望, 其余 = 环境变量
  desc="$1"; want="$2"; shift 2
  got="$(plan "$@")"
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1)); printf '  ok   %-40s %s\n' "$desc" "$got"
  else
    fail=$((fail + 1)); printf '  FAIL %-40s got=%s want=%s\n' "$desc" "$got" "$want"
  fi
}

check_cli() { # $1 = 描述, $2 = 期望, $3 = 额外命令行参数, 其余 = 环境变量
  desc="$1"; want="$2"; flags="$3"; shift 3
  got="$(env "$@" bash "$S" --config "${CFG:-$tmp/no-config.env}" $flags 2>/dev/null | sed -n 's/^计划轮数：//p')"
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1)); printf '  ok   %-40s %s\n' "$desc" "$got"
  else
    fail=$((fail + 1)); printf '  FAIL %-40s got=%s want=%s\n' "$desc" "$got" "$want"
  fi
}

echo "内置：默认与档位"
check "不配置"                "A4 B3 C5 D3 E3"
check "level=light"           "A3 B2 C4 D2 E2" APHORISM_THINKING_LEVEL=light
check "level=standard"        "A4 B3 C5 D3 E3" APHORISM_THINKING_LEVEL=standard
check "level=deep"            "A6 B5 C7 D5 E5" APHORISM_THINKING_LEVEL=deep
check "level=max"             "A8 B7 C10 D7 E7" APHORISM_THINKING_LEVEL=max
check "level 大小写不敏感"     "A6 B5 C7 D5 E5" APHORISM_THINKING_LEVEL=DEEP
check "level 非法则回落默认"   "A4 B3 C5 D3 E3" APHORISM_THINKING_LEVEL=nope

echo "内置：APHORISM_THINKING_ROUNDS"
check "整数：所有模式"         "A7 B7 C7 D7 E7" APHORISM_THINKING_ROUNDS=7
check "偏移：+2"              "A6 B5 C7 D5 E5" APHORISM_THINKING_ROUNDS=+2
check "偏移：-2"              "A2 B2 C3 D2 E2" APHORISM_THINKING_ROUNDS=-2
check "逐模式：A=6,C=8"       "A6 B3 C8 D3 E3" APHORISM_THINKING_ROUNDS=A=6,C=8
check "混用：+1,C=8"          "A5 B4 C8 D4 E4" APHORISM_THINKING_ROUNDS=+1,C=8
check "档位 + 逐模式"          "A7 B6 C8 D6 E6" APHORISM_THINKING_LEVEL=deep APHORISM_THINKING_ROUNDS=+1,C=8
check "下限夹到 2"            "A2 B2 C2 D2 E2" APHORISM_THINKING_ROUNDS=-9
check "上限夹到 12"           "A12 B12 C12 D12 E12" APHORISM_THINKING_ROUNDS=99
check "空格容错"              "A6 B3 C8 D3 E3" APHORISM_THINKING_ROUNDS="A=6, C=8"
check "看不懂的项被忽略"       "A4 B3 C5 D3 E3" APHORISM_THINKING_ROUNDS=X=3
check "空值 = 不设置"          "A4 B3 C5 D3 E3" APHORISM_THINKING_ROUNDS=

echo "config.env"
cfg="$tmp/config.env"
cat > "$cfg" <<'EOF'
# 注释
APHORISM_THINKING_LEVEL = light     # 行内注释
APHORISM_THINKING_ROUNDS=
APHORISM_THINKING_LEVEL = "max"     # 同名键：最后一条非空生效
export APHORISM_THINKING_ROUNDS='C=9'
EOF
CFG="$cfg"; check "同名键取最后非空 / 引号 / 空格 / 注释" "A8 B7 C9 D7 E7"; CFG=""
CFG="$cfg"; check "环境变量压过 config.env"    "A3 B3 C3 D3 E3" APHORISM_THINKING_ROUNDS=3; CFG=""

printf 'APHORISM_THINKING_LEVEL=deep\n' > "$SKILL_DIR/config.env"
got="$(bash "$S" --sources "$tmp/no-sources.conf" 2>/dev/null | sed -n 's/^计划轮数：//p')"
if [ "$got" = "A6 B5 C7 D5 E5" ]; then
  pass=$((pass + 1)); printf '  ok   %-40s %s\n' "自动读取 skill 目录的 config.env" "$got"
else
  fail=$((fail + 1)); printf '  FAIL %-40s got=%s want=A6 B5 C7 D5 E5\n' "自动读取 skill 目录的 config.env" "$got"
fi

CFG="$cfg"; check_cli "--defaults 忽略配置" "A4 B3 C5 D3 E3" "--defaults" APHORISM_THINKING_LEVEL=max; CFG=""
check_cli "命令行 > 环境变量"   "A6 B5 C8 D5 E5" "--level deep --rounds C=8" APHORISM_THINKING_LEVEL=light
if bash "$S" --bogus >/dev/null 2>&1; then
  fail=$((fail + 1)); printf '  FAIL %-40s 应当以非 0 退出\n' "非法参数"
else
  pass=$((pass + 1)); printf '  ok   %-40s %s\n' "非法参数报错退出" "exit!=0"
fi

echo "自定义思考方向（sources.conf）"
SRC="$tmp/custom.conf"
cat > "$SRC" <<'EOF'
# 两个自定义方向
[F]
name=旧笔记考古
paths=~/Notes
rounds=5

[G]
name=论文阅读
paths=~/papers
EOF
check "自定义方向默认轮数"      "A4 B3 C5 D3 E3 F5 G4"
check "档位也作用到自定义方向"   "A6 B5 C7 D5 E5 F7 G6" APHORISM_THINKING_LEVEL=deep
check "light 也作用到自定义方向" "A3 B2 C4 D2 E2 F4 G3" APHORISM_THINKING_LEVEL=light
check "偏移作用到自定义方向"     "A5 B4 C6 D4 E4 F6 G5" APHORISM_THINKING_ROUNDS=+1
check "逐模式指定自定义方向"     "A4 B3 C5 D3 E3 F9 G4" APHORISM_THINKING_ROUNDS=F=9
check "整数覆盖所有方向"        "A7 B7 C7 D7 E7 F7 G7" APHORISM_THINKING_ROUNDS=7

cat > "$tmp/clash.conf" <<'EOF'
[B]
name=想冒充内置的方向
paths=~/x
rounds=9
EOF
SRC="$tmp/clash.conf"
check "与内置代号冲突则忽略"     "A4 B3 C5 D3 E3"
SRC="$tmp/bad.conf"
cat > "$SRC" <<'EOF'
[F]
name=坏轮数
paths=~/x
rounds=abc
EOF
check "自定义方向轮数非法 → 4"   "A4 B3 C5 D3 E3 F4"
SRC="$tmp/custom.conf"
check_cli "--no-sources 只算内置" "A4 B3 C5 D3 E3" "--no-sources --sources $tmp/custom.conf"
check_cli "--sources 指定文件"    "A4 B3 C5 D3 E3 F5 G4" "--sources $tmp/custom.conf"

echo
if [ "$fail" -eq 0 ]; then
  echo "✓ 思考强度 ${pass} 项契约全部通过"
else
  echo "✗ ${fail} 项失败（通过 ${pass} 项）" >&2
fi
exit $(( fail > 0 ? 1 : 0 ))
