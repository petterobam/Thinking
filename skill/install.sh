#!/usr/bin/env bash
# 思笺 · aphorism-notebook — skill installer
#
#   curl -fsSL <站点>/skill/install.sh | bash
#   bash skill/install.sh --dest ~/.codex/skills
#
# Installs the skill into every agent skill directory it can find
# (Codex, Claude Code) unless --dest is given.
set -euo pipefail

NOTES_URL_DEFAULT="https://petterobam.github.io/Thinking/skill"
BASE_URL="${NOTEBOOK_URL:-${NOTES_URL_DEFAULT}}"
SKILL_NAME="aphorism-notebook"

dests=()

usage() {
  cat <<'USAGE'
安装「箴言笔记」skill 到你的 AI Agent。

用法：
  curl -fsSL <站点>/skill/install.sh | bash [-- 选项]
  bash install.sh [选项]

选项：
  --dest DIR     安装到指定目录（可重复；默认为探测到的 skills 目录）
  --name NAME    安装成其它名字（默认 aphorism-notebook）
  --url URL      从指定站点下载（默认仓库站点）
  --list         只列出将要安装的文件
  -h, --help     显示帮助

环境变量：
  NOTEBOOK_URL   等同于 --url
USAGE
}

list_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) dests+=("$2"); shift 2 ;;
    --name) SKILL_NAME="$2"; shift 2 ;;
    --url) BASE_URL="${2%/}"; shift 2 ;;
    --list) list_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v curl >/dev/null 2>&1; then
  echo "需要 curl，请先安装。" >&2
  exit 1
fi

echo "→ 从 ${BASE_URL} 拉取文件清单…"
manifest="$(curl -fsSL "${BASE_URL}/files.txt")" || {
  echo "无法获取 files.txt，检查网络或 --url 是否正确。" >&2
  exit 1
}

if [[ "${list_only}" == "1" ]]; then
  echo "${manifest}"
  exit 0
fi

# Where do agents look for skills on this machine?
if [[ ${#dests[@]} -eq 0 ]]; then
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  [[ -d "${codex_home}" || ! -d "$HOME/.claude" ]] && dests+=("${codex_home}/skills")
  [[ -d "$HOME/.claude" ]] && dests+=("$HOME/.claude/skills")
  [[ ${#dests[@]} -eq 0 ]] && dests+=("$HOME/.codex/skills")
fi

installed_any=0
for base_dest in "${dests[@]}"; do
  target="${base_dest}/${SKILL_NAME}"
  mkdir -p "${target}"
  count=0
  while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    [[ "${rel}" == "files.txt" || "${rel}" == "install.sh" ]] && continue
    # files.txt paths are relative to the published /skill directory and
    # start with the skill name; strip it because the target already has it.
    rel="${rel#${SKILL_NAME}/}"
    mkdir -p "${target}/$(dirname "${rel}")"
    if curl -fsSL "${BASE_URL}/${SKILL_NAME}/${rel}" -o "${target}/${rel}"; then
      count=$((count + 1))
    else
      echo "  · 跳过（下载失败）：${SKILL_NAME}/${rel}" >&2
    fi
  done <<< "${manifest}"
  # keep a copy of the installer so the skill can be updated in place
  curl -fsSL "${BASE_URL}/install.sh" -o "${target}/install.sh" 2>/dev/null && chmod +x "${target}/install.sh" || true
  installed_any=1
  echo "✓ 已安装 ${count} 个文件 → ${target}"
done

if [[ "${installed_any}" == "0" ]]; then
  echo "没有安装任何文件，请用 --dest 指定目标目录。" >&2
  exit 1
fi

cat <<'NEXT'

装好了。接下来对一个 Agent 说：

  「用箴言笔记给我写一张卡片」

Agent 会读取 SKILL.md，定位你的 GitHub 同名仓库（没有就从上游 fork 并清空上游旧卡），
按其中一种思考模式思考多轮，写下箴言与旅程，校验后推送；
GitHub Actions 会在提交后自动重新部署站点。

想先看看内容？打开 <站点>/skill/aphorism-notebook/SKILL.md
NEXT
