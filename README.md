# 思笺 · Thought Cards

一个极简的箴言卡片站：**正面只有十来个字的箴言，点开是一场关于它的思想旅程。**

- 卡片墙：所有箴言一屏可见，没有长文章、没有信息流。
- 点开一张卡：起点、故事、背景、推理过程，串成一条可以往下读的"旅程"。
- 明暗两套主题、搜索、主题筛选、随机一笺、键盘翻页、深链分享、RSS。
- 纯静态、**零依赖**：构建只需要 `node`（≥ 18），没有 npm install。
- 提交即部署：push 到 `main` 后 GitHub Actions 校验内容 → 构建 → 发布到 GitHub Pages。

## 本地使用

```bash
node scripts/validate.mjs          # 校验所有卡片（--strict 供 CI 使用）
node build/build.mjs               # 生成 dist/
node build/build.mjs --serve       # 本地预览 http://127.0.0.1:4321/ （改动自动重建）
```

## 写一张新卡

```bash
node scripts/new-card.mjs --slug delete-needs-courage --title 删除比添加更需要勇气 \
  --mode 会话回望 --tags 克制,手艺 --seed "一次重构里删掉 400 行之后"
# 编辑 content/cards/delete-needs-courage.md
node scripts/validate.mjs --strict
git add -A && git commit -m "card: delete-needs-courage — 删除比添加更需要勇气" && git push
```

一张卡 = 一句 8–16 字的箴言 + 120–900 字、2–6 个小节的旅程。
规则、正反例、思考方法都写在 skill 里（见下）。

## 让 AI 替你写

站点首页有一块「让 AI 替你写下一张」，可以一键复制安装命令与提示词；也可以直接：

```bash
curl -fsSL https://petterobam.github.io/Thinking/skill/install.sh | bash
```

然后对一个 Agent 说：**「用箴言笔记给我写一张卡片」**。如果当前账号还没有自己的 `Thinking` 仓库，首次运行会从上游 fork 一份，并清空上游自带卡片，得到一个只属于你的空笔记本。

skill 源码在 [`skill/aphorism-notebook/`](skill/aphorism-notebook/)：

| 文件 | 作用 |
| --- | --- |
| `SKILL.md` | 主流程：定位仓库 → 选思考模式 → 多轮思考 → 压缩箴言 → 写旅程 → 校验 → 推送 |
| `references/00-thinking-modes.md` | 五种思考模式（时事沉思 / 会话回望 / 悬问求索 / 生活即景 / 旧笺重读）的完整操作 |
| `references/01-writing-craft.md` | 写作技巧：箴言骨架、删字练习、旅程节奏、正反例 |
| `references/02-repo-and-publishing.md` | 仓库定位、fork 初始化、发布与故障处理 |
| `references/03-card-format.md` | 卡片字段规范与机器校验规则 |

## 目录结构

```
content/site.json          站点配置（标题、作者、仓库）
content/cards/*.md         卡片，一张一个文件，文件名就是地址
scripts/validate.mjs       内容质量闸门（CI 里用 --strict）
scripts/new-card.mjs       卡片脚手架
scripts/lib/               front-matter / markdown / 卡片加载（零依赖实现）
src/template.html          首页模板
src/card.template.html     单卡静态页模板（可分享、带 OG 标签）
src/styles.css src/app.js  样式与交互
build/build.mjs            静态生成器（含 --serve 预览服务器）
skill/                     skill 本体与一键安装脚本
.github/workflows/deploy.yml
```

## 部署

推送到 `main` 即触发 `.github/workflows/deploy.yml`：校验 → 构建 → 上传 artifact → 发布 Pages。
首次运行会通过 `actions/configure-pages` 自动开启 Pages（工作流已申请 `pages: write` 权限）。
如果没有自动开启，也可以手动：

```bash
gh api -X POST repos/<owner>/Thinking/pages -f build_type=workflow
```

站点地址默认 `https://<owner>.github.io/Thinking/`。

## 许可

代码：MIT。卡片文字：署名—非商业性使用 4.0（CC BY-NC 4.0）。
