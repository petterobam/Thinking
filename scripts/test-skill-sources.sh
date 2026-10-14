#!/usr/bin/env bash
# 自定义思考方向契约测试 · aphorism-notebook
#
#   bash scripts/test-skill-sources.sh
#
# 覆盖：init / add（显式代号、自动代号、夹取轮数）/ list / codes / set（改字段、加字段）/
#        remove / check（缺字段、坏轮数、占内置代号）/ 交互式 add（喂答案、取消、EOF）/
#        路径检查（读不到只提醒，不拦）。
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/skill/aphorism-notebook/assets/sources.sh"
[ -f "$S" ] || { echo "找不到 $S" >&2; exit 1; }

pass=0
fail=0
tmp="$(mktemp -d)"
mkdir -p "$tmp/notes"
printf 'x\n' > "$tmp/notes/a.md"
trap 'node -e "try{require(\"fs\").rmSync(process.argv[1],{recursive:true,force:true})}catch(e){}" "$tmp"' EXIT

ok()   { pass=$((pass + 1)); printf '  ok   %-42s %s\n' "$1" "${2-}"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %-42s %s\n' "$1" "${2-}"; }

expect_ok()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1" "应当成功"; fi; }
expect_fail() { if eval "$2" >/dev/null 2>&1; then bad "$1" "应当失败"; else ok "$1" "exit!=0"; fi; }

expect_contains() { # 描述 命令 期望片段
  out="$(eval "$2" 2>/dev/null)"
  case "$out" in *"$3"*) ok "$1" ;; *) bad "$1" "输出里没有『$3』" ;; esac
}

C="$tmp/sources.conf"

echo "init"
expect_ok "init 建配置" "bash '$S' init --config '$C'"
expect_contains "init 带注释样例" "bash '$S' list --config '$C'" "还没有任何方向"
expect_ok "init 幂等（已存在不覆盖）" "bash '$S' init --config '$C'"

echo "add"
expect_ok "显式代号 F" "bash '$S' add --config '$C' --code F --name 旧笔记考古 --paths '$tmp/notes,~/不存在' --rounds 5 --emoji 🗂 --hint '先看最近改动'"
expect_ok "自动指派代号 G" "bash '$S' add --config '$C' --name 论文阅读 --paths '$tmp/notes/*.md'"
expect_ok "轮数 99 夹到 12" "bash '$S' add --config '$C' --code H --name 测夹取 --paths '$tmp/notes' --rounds 99"
expect_ok "轮数 1 夹到 2" "bash '$S' add --config '$C' --code I --name 测下限 --paths '$tmp/notes' --rounds 1"
expect_fail "重复代号被拒" "bash '$S' add --config '$C' --code F --name 重复 --paths '$tmp/notes'"
expect_fail "占用内置代号被拒" "bash '$S' add --config '$C' --code B --name 冲突 --paths '$tmp/notes'"
expect_fail "缺 name 被拒" "bash '$S' add --config '$C' --code J --paths '$tmp/notes'"
expect_fail "缺 paths 被拒" "bash '$S' add --config '$C' --code K --name 缺路径"
expect_fail "轮数非数字被拒" "bash '$S' add --config '$C' --code L --name 坏轮数 --paths '$tmp/notes' --rounds abc"

echo "list / codes"
expect_contains "list 显示名字"   "bash '$S' list --config '$C'" "旧笔记考古"
expect_contains "list 显示默认轮数" "bash '$S' list --config '$C'" "默认 5 轮"
expect_contains "list 显示路径"   "bash '$S' list --config '$C'" "$tmp/notes"
expect_contains "codes 列出代号" "bash '$S' codes --config '$C' | tr '\n' ' '" "F G H I"

echo "set / remove"
expect_ok  "set 改 rounds"  "bash '$S' set --config '$C' F rounds 7"
expect_contains "set 生效"   "bash '$S' list --config '$C'" "默认 7 轮"
expect_ok  "set 新增字段 hint" "bash '$S' set --config '$C' F hint '换个说法'"
expect_contains "set 新字段可见" "bash '$S' list --config '$C'" "换个说法"
expect_fail "set 未知字段被拒" "bash '$S' set --config '$C' F 不存在的字段 1"
expect_fail "set 坏轮数被拒"   "bash '$S' set --config '$C' F rounds x"
expect_fail "set 未知代号被拒" "bash '$S' set --config '$C' Z rounds 3"
expect_ok  "remove 生效"    "bash '$S' remove --config '$C' I"
expect_fail "remove 未知代号被拒" "bash '$S' remove --config '$C' I"

echo "check"
expect_ok "check 正常配置" "bash '$S' check --config '$C'"
printf '\n[M]\nname=缺路径\n' >> "$C"
expect_fail "check 抓缺 paths" "bash '$S' check --config '$C'"
printf '\n[N]\nname=坏轮数\npaths=%s\nrounds=abc\n' "$tmp/notes" >> "$C"
expect_fail "check 抓坏轮数" "bash '$S' check --config '$C'"
printf '\n[B]\nname=占内置代号\npaths=%s\n' "$tmp/notes" >> "$C"
expect_fail "check 抓代号冲突" "bash '$S' check --config '$C'"

echo "交互式 add"
C2="$tmp/interactive.conf"
bash "$S" init --config "$C2" >/dev/null
printf '书摘本\n%s,~/vault\n6\n' "$tmp/notes" | bash "$S" add --interactive --input /dev/stdin --config "$C2" >/dev/null 2>&1
expect_contains "喂答案：名字" "bash '$S' list --config '$C2'" "书摘本"
expect_contains "喂答案：轮数" "bash '$S' list --config '$C2'" "默认 6 轮"
printf '访谈稿\n%s\n\n' "$tmp/notes" | bash "$S" add --interactive --input /dev/stdin --config "$C2" >/dev/null 2>&1
expect_contains "空轮数用默认 4" "bash '$S' list --config '$C2'" "默认 4 轮"
before="$(bash "$S" codes --config "$C2" | tr '\n' ' ')"
printf '!\n' | bash "$S" add --interactive --input /dev/stdin --config "$C2" >/dev/null 2>&1
after="$(bash "$S" codes --config "$C2" | tr '\n' ' ')"
[ "$before" = "$after" ] && ok "输入 ! 取消，不写入" || bad "输入 ! 取消，不写入" "before=$before after=$after"
printf '半截\n' | bash "$S" add --interactive --input /dev/stdin --config "$C2" >/dev/null 2>&1
after2="$(bash "$S" codes --config "$C2" | tr '\n' ' ')"
[ "$after" = "$after2" ] && ok "中途 EOF 不写入" || bad "中途 EOF 不写入" "after=$after after2=$after2"
expect_fail "读不到输入源 → 跳过" "bash '$S' add --interactive --input '$tmp/does-not-exist' --config '$C2'"

echo
if [ "$fail" -eq 0 ]; then
  echo "✓ 自定义思考方向 ${pass} 项契约全部通过"
else
  echo "✗ ${fail} 项失败（通过 ${pass} 项）" >&2
fi
exit $(( fail > 0 ? 1 : 0 ))
