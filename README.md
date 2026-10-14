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
| `config.example.env` | 思考强度配置模板（复制成 `config.env` 生效） |
| `sources.example.conf` | 自定义思考方向模板（复制成 `sources.conf` 生效） |
| `references/04-custom-directions.md` | 自定义方向：首次问话、增删改、隐私红线、读素材要求 |
| `assets/rounds.sh` | 思考强度解析器：把配置算成每个方向本次的轮数 |
| `assets/sources.sh` | 自定义思考方向管理：list / add / set / remove / check |

## 自定义思考方向（你自己的知识库 / 笔记）

除了内置的 A–E，还可以把你自己的东西配成**自定义思考方向**（`F`、`G`…）：笔记仓库、书摘、
访谈稿、某个项目的 git log。首次安装时会问一句要不要现在加；以后随时可以说
「把 ~/Notes 加成一个思考方向」。

```bash
S=~/.codex/skills/aphorism-notebook/assets/sources.sh
bash "$S" add --name 旧笔记考古 --paths '~/Notes,~/vault' --rounds 5   # 代号自动分配
bash "$S" list          # 有哪些方向
bash "$S" set F paths '~/Notes/2026,~/vault'
bash "$S" remove F
bash "$S" check         # 校验代号/字段/轮数/路径
```

配置写在 `sources.conf`（字段：`name` / `paths` / `rounds` / `emoji` / `hint` / `rounds_template`），
每个方向自己的默认轮数会并入思考强度那张表。读素材的硬要求：**真的打开读、能说出具体文件、
不写隐私**（站点是公开的），完整规则见 `references/04-custom-directions.md`。

## 思考强度（可配置）

默认轮数是 **A 4 · B 3 · C 5 · D 3 · E 3**。想更轻或更深，不用改 skill，改配置就行：

```bash
# 一次性（当前 shell / 当前 Agent 会话）
export APHORISM_THINKING_LEVEL=deep        # light / standard / deep / max
export APHORISM_THINKING_ROUNDS='+1,C=8'   # 7 / +2 / -1 / A=6,C=8 / 混着写

# 长期（插件内配置，跟着 skill 走，环境变量没设时读它）
cp ~/.codex/skills/aphorism-notebook/config.example.env \
   ~/.codex/skills/aphorism-notebook/config.env
```

轮数夹在 2–12 之间；每次运行前 Agent 会跑 `assets/rounds.sh` 把配置解析成一张轮数表，
按表执行（轮数多于模式模板就补「加轮表 / 通用加轮池」，少于模板就按删减顺序裁，必留轮不能删）。
契约测试：`bash scripts/test-skill-rounds.sh`（34 项）、`bash scripts/test-skill-sources.sh`（35 项）。

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
scripts/test-skill-rounds.sh   思考强度配置的契约测试
scripts/test-skill-sources.sh  自定义思考方向的契约测试
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

## 国内镜像

GitHub Pages 在国内访问不稳，所以站点额外部署一份国内镜像（`.github/workflows/deploy-cn.yml`）。

> 为什么不用 Gitee Pages：Gitee 已经在 2024 年 5 月无公告下线了 Gitee Pages（客服确认，帮助中心的
> Pages 文档、OpenAPI 里的 `pages` 接口、仓库的 `/pages` 路由都已删除），`gitee.io` 现在是指向
> 百度系 CDN 的泛解析，老站点（如 doocs/md）也已停止更新。所以 `gitee-pages-action` 这条路已经不存在了，
> Gitee 只当代码镜像用。

镜像用腾讯云 **EdgeOne Makers** 的免费版：**永久免费 + 全球加速区（中国大陆以外节点）免备案**。

1. 用 Gmail 登录腾讯云控制台，开通 Makers 并随便建一个项目（激活服务即可）。
2. 控制台 → **API Token** → 创建，把 token 填进仓库 `Settings → Secrets and variables → Actions`，
   名字必须是 `EDGEONE_API_TOKEN`。
3. 项目名写在 `content/site.json` 的 `mirror.project`（默认 `thinking`），push 到 `main` 即可。
   首次部署会在日志里打印 `EDGEONE_DEPLOY_URL=...`，把这个地址填回 `content/site.json` 的
   `mirror.url`，再到 Actions 手动跑一次 `Build the China mirror`——镜像里的 RSS、sitemap、
   安装脚本地址就会指向镜像域名。

没配 `EDGEONE_API_TOKEN` 时，这个工作流只做校验和构建并打印一条 notice，不会失败。

镜像站在域名根路径，所以用 `BASE_PATH=/` 构建，产物在 `dist-cn/`（不入库）；GitHub Pages 那份
仍然是 `/Thinking/` 前缀。本地复现：

```bash
BASE_PATH=/ SITE_URL=https://<镜像地址>/ node build/build.mjs --out=dist-cn
```

## 许可

代码：MIT。卡片文字：署名—非商业性使用 4.0（CC BY-NC 4.0）。
