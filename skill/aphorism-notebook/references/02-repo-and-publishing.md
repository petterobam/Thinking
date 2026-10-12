# 仓库定位、发布与故障处理

站点是纯静态的：**提交 = 部署**。GitHub Actions 在 push 到 `main` 后自动构建 `dist/` 并发布到 GitHub Pages。

---

## 一、定位用户 fork

上游仓库默认 `petterobam/Thinking`（skill 的发布源）。目标仓库是当前 GitHub 账号下的同名 fork。若用户使用别名或其它上游，以 `APHORISM_UPSTREAM` 或对话约定为准。

```bash
gh auth status || gh auth login          # 未登录先登录（会走浏览器/设备码流程）
upstream="${APHORISM_UPSTREAM:-petterobam/Thinking}"
repo_name="${upstream##*/}"
owner="$(gh api user --jq .login)"       # 当前登录的账号
target="$owner/$repo_name"

if gh repo view "$target" >/dev/null 2>&1; then
  echo "已存在：$target"
  # 已有自己的 fork，使用它；本地没有就克隆
  if [ -d .git ] && git remote get-url origin 2>/dev/null | grep -q "$owner/$repo_name"; then
    git pull --rebase
  else
    gh repo clone "$target" && cd "$repo_name"
  fi
else
  echo "不存在：从 $upstream fork 到 $target"
  # 若当前目录就是上游的 git 克隆，可在原地 fork；否则 clone 新 fork
  if [ -d .git ] && git remote get-url origin 2>/dev/null | grep -q "$upstream"; then
    gh repo fork "$upstream"
  else
    gh repo fork "$upstream" --default-branch-only --clone
    cd "$repo_name"
  fi
fi
```

**判断清单**
- 用户已经站在自己的 fork 里（`origin` 指向 `$owner/$repo_name`）→ 直接就地工作，先 `git pull --rebase`。
- 只有 gh，本地无克隆 → `gh repo clone "$target"`。
- 自己账号下还没有同名仓库 → 从 `$upstream` fork；**不要 `gh repo create`**。
- 完全没有 gh / 未登录 → **停止**，请用户执行 `gh auth login` 或提供已登录环境。不要伪造凭证。

如果同名仓库存在但不是该上游的 fork（`gh repo view "$target" --json isFork` 返回 `false`），不要覆盖或清空；先向用户确认是不是这个笔记本，确认后再继续。

---

## 二、fork 初始化（用户还没有同名仓库时）

只在第 0 步刚创建了新的 fork 时执行一次。目标是：**保留完整站点骨架和 workflow，但不把上游作者已有的卡片带进用户站点**。执行前先确认工作区干净（`git status --porcelain` 无输出）；有未提交改动时停下来问用户，不要把它们混进初始化提交。

```bash
# 1. 确保 upstream 关联存在，之后可用它取站点骨架更新
git remote get-url upstream >/dev/null 2>&1 || \
  git remote add upstream "https://github.com/$upstream.git"

# 2. 只清空 fork HEAD 里的旧卡，保留目录；不重写历史
mkdir -p content/cards
find content/cards -maxdepth 1 -type f -name '*.md' -delete
touch content/cards/.gitkeep

# 3. 把站点配置指向自己的 fork
node -e 'const fs=require("fs"); const p="content/site.json"; const s=JSON.parse(fs.readFileSync(p,"utf8")); s.repo={owner:process.argv[1],name:process.argv[2]}; fs.writeFileSync(p, JSON.stringify(s,null,2)+"\n");' "$owner" "$repo_name"

# 4. 校验空站点、提交并推送
node scripts/validate.mjs --strict
node build/build.mjs
git add -A
git commit -m "chore: fork notebook without upstream cards"
git push -u origin main
```

- `content/cards/.gitkeep` 只用来保留空目录，构建时会忽略。
- 旧卡仍留在 Git 历史里，但 HEAD 已经删除，站点不会显示；不要为了“看不见”而重写 fork 历史。
- 初始化提交只允许发生在第一次 fork 后。之后所有运行都只追加或修改用户自己的卡片。
- 如果已有 fork 但 `content/cards/` 里仍是上游卡片，只有确认这是从未初始化过的 fork 才能按本节处理；不确定就先问用户。

**启用 Pages**（只需一次）：工作流里的 `actions/configure-pages@v5` 带 `enablement: true`，第一次运行会自动开启 Pages（需要 workflow 有 `pages: write` 权限，仓库设置里 Actions 权限用默认即可）。Fork 首次 push 后如果 Actions 没有自动运行，需要在 fork 的 Actions 页面手动启用 Workflows；GitHub 对 fork 的首次运行可能要求确认，这不是构建失败。
若第一次运行报 Pages 未启用，也可以手动：

```bash
gh api -X POST "repos/$target/pages" -f build_type=workflow || \
gh api -X PUT  "repos/$target/pages" -f build_type=workflow
```

站点地址：`https://<owner>.github.io/<repo_name>/`（仓库名 `<owner>.github.io` 时则为 `https://<owner>.github.io/`）。

---

## 三、发布一张卡片

```bash
git pull --rebase                                  # 先同步
node scripts/new-card.mjs --slug <slug> --title "<箴言>" --mode <模式> --tags a,b --seed "<起点>"
$EDITOR content/cards/<slug>.md                    # 写完
node scripts/validate.mjs --strict                 # 必须通过
git add content/cards/<slug>.md
git commit -m "card: <slug> — <箴言>"
git push origin main
```

推送目标约定：`origin` 必须是自己的 fork；`upstream` 只用于读取上游更新。若以后同步上游的站点骨架，只合并代码、样式和 workflow，**不要合并 `content/cards/`**，否则会把上游作者的卡片带回来。

提交信息约定（便于回溯）：

| 类型 | 格式 | 例 |
| --- | --- | --- |
| 新卡片 | `card: <slug> — <箴言>` | `card: delete-needs-courage — 删除比添加更需要勇气` |
| 修订卡片 | `revise: <slug> — 为什么改` | `revise: delete-needs-courage — 第二段太像总结` |
| 站点改动 | `site: <说明>` | `site: 收紧卡片间距` |
| 建站 | `chore: <说明>` | `chore: bootstrap notebook` |

**推送后必须验证**

```bash
gh run list --limit 1                       # 看工作流是否在跑
gh run watch                                # 跟随这一次运行（可选）
```

`gh run watch` 失败时，把失败日志的**关键几行**贴给用户，不要只说"构建失败"。常见原因：内容没过 `--strict`、Node 版本过低、Pages 未启用。

---

## 四、故障处理

**1. `gh: command not found` / 未登录**
停止并请用户 `gh auth login`（或改用已配置的 SSH 远端 `git@github.com:<owner>/Thinking.git`）。

**2. `push` 被拒（non-fast-forward）**
```bash
git pull --rebase --autostash
node scripts/validate.mjs --strict      # 解决冲突后重新校验
git push
```
绝不使用 `git push -f`。

**3. Actions 构建失败**
```bash
gh run view --log-failed                 # 只看失败步骤的日志
node build/build.mjs                     # 本地先复现
```

**4. 卡片不出现在站点上**
- 检查是否 push 到了 `main`（工作流只监听 `main`）。
- 检查 `content/cards/<slug>.md` 的 front-matter 是否完整（缺 `date` 会被判错）。
- 检查 Actions 是否还在跑（Pages 部署通常 30–90 秒）。

**5. 内容重复被拦**
`validate.mjs` 会报「箴言与 <slug> 重复」。这不是要改措辞绕过，而是提醒你：今天想到的其实是旧卡的另一面——改用 **E · 旧笺重读**模式，与旧卡辩驳，写出真正不同的那一句。

**6. fork 初始化失败**
- 目标名下有非 fork 的同名仓库：**停止并让用户确认**，不要覆盖、清空或退化成 `gh repo create`。
- `gh repo fork` 因权限、网络或仓库策略失败：报告原样错误并重试；宁可停下，也不要新建一个没有关联上游的空仓库。

**7. 用户想自定义域名 / 主题**
- 自定义域名：`content/site.json` 不用改，站点是相对路径；在仓库 Settings → Pages 填域名并加 `CNAME`。
- 深浅色与主色：`content/site.json` 的 `"accent"` 改一个十六进制色即可，其余交给 `src/styles.css`。

---

## 五、给用户的收尾话术

推送成功后，汇报三件事：**卡片内容**、**它属于哪种思考模式**、**站点链接**。并提醒：Actions 需要几十秒，刷新即可看到新卡片。不要只说"已完成"。
