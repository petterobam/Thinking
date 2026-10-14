---
name: aphorism-notebook
description: 为「思笺」箴言卡片站写新的箴言卡片并推送部署。当用户说「写一张卡片 / 今天来一张 / 更新箴言笔记 / 往 thinking 里加一条 / aphorism notebook / 给我一句箴言」时使用。它负责定位用户 GitHub 上的同名仓库；如果还没有，就从上游 fork 一份并清空上游旧卡，用多种思考模式（读新闻、回看当天会话与任务、追问一个从未想过的问题、观察生活即景、重读旧卡）进行多轮思考，把结论压成十来字的箴言，再写下它背后的旅程，最后校验并推送，触发 GitHub Pages 自动构建。也可以把用户自己的笔记 / 知识库目录配成自定义思考方向（增删改），以及调整思考强度（轮数）。
---

# 箴言笔记 · aphorism-notebook

> 十来字见天地，一笺纸藏旅程。

这个 skill 让 Agent 替用户经营一个**箴言卡片站**：每天往仓库里放一两张卡片。卡片正面只有十来字的箴言，点开后是它背后的故事、背景与思考过程——一次简短而浪漫的思想旅程。

站点是纯静态的：仓库提交后由 GitHub Actions 自动构建部署。所以这个 skill 的最终交付物永远是**一次 commit**。

---

## 0. 契约（不可违背）

| 项目 | 规则 |
| --- | --- |
| 一次运行 | 只写 **1–3 张**卡片。宁可少，不可凑。 |
| 箴言 | **8–16 字**最舒服，硬上限 22 字；单行；不加句号叹号。 |
| 旅程 | **120–900 字**，2–6 个 `##` 小节；硬上限 2000 字。 |
| 语言 | 与用户交谈的语言一致（默认中文）。 |
| 素材来源 | 只用真实读过的材料；用自定义方向时能说出具体文件/标题；隐私内容不入卡（站点是公开的）。 |
| 思考强度 | 默认 A 4 · B 3 · C 5 · D 3 · E 3 轮；由 `APHORISM_THINKING_LEVEL` / `APHORISM_THINKING_ROUNDS`（或 skill 目录里的 `config.env`）调整，见第 2 节。 |
| 质量 | 不许鸡汤、不许口号、不许复述名人名言、不许无感情流水账。 |
| 提交前 | 必须 `node scripts/validate.mjs --strict` 通过。 |
| 提交后 | 推送即部署；向用户报告卡片、commit 与站点地址。 |

写不出好东西时，**允许只写一张，甚至如实说「今天没有值得写的」**。空转比烂卡更贵。

---

## 1. 流程总览

```
0 定位仓库  →  1 选思考模式  →  2 采集材料  →  3 多轮思考
      →  4 压缩成箴言  →  5 写旅程  →  6 校验  →  7 提交推送  →  8 汇报
```

开工前两件事：① 按第 2 节解析思考强度（这次想多深）；② 按第 3 节确认素材来源（走内置模式，还是读用户自己的知识库）。然后再走下面的流程。

**多轮思考是全部价值所在**：轮次不够，箴言一定是废话。每个模式都写明了轮次题目，不要跳步、不要合并轮次、不要用一段话冒充多轮。

---

## 2. 思考强度（可配置）

思考轮数**不是写死的**：每次运行先解析一次强度，之后全程按解析结果执行。

配置优先级（高 → 低）：

1. 环境变量 `APHORISM_THINKING_ROUNDS`
2. 环境变量 `APHORISM_THINKING_LEVEL`
3. skill 目录下的 `config.env`（插件内配置，变量名同上面两个；模板见 `config.example.env`）
4. 内置默认：**A 4 轮 · B 3 轮 · C 5 轮 · D 3 轮 · E 3 轮**

| 变量 | 取值 | 效果 |
| --- | --- | --- |
| `APHORISM_THINKING_LEVEL` | `light` / `standard` / `deep` / `max` | 整体档位；A/B/C/D/E 分别是 3/2/4/2/2、4/3/5/3/3、6/5/7/5/5、8/7/10/7/7 |
| `APHORISM_THINKING_ROUNDS` | `7` | 所有模式都做 7 轮 |
| | `+2` / `-1` | 在档位（或默认）基础上加减 |
| | `A=6,C=8` | 逐模式指定，未列出的模式照旧 |
| | `+1,C=8` | 混着写也可以 |

轮数一律夹在 **2–12** 之间（`-9` 得到 2，`99` 得到 12）。写错的项只会在 stderr 提醒并被忽略，不会中断这次写作。
`config.env` 里同名键写多次时**最后一条非空值生效**，行尾 `#` 是注释，留空表示不用。

**不要手算，直接跑解析器**（它同时读环境变量和 `config.env`）：

```bash
bash <skill-dir>/assets/rounds.sh                # <skill-dir> = SKILL.md 所在目录
bash <skill-dir>/assets/rounds.sh --level deep   # 临时试算，不影响配置
```

把输出原样贴进轮次笔记（`/tmp/notebook-<date>.md`）的最上面，之后每一轮都按它编号：

```
计划轮数：A6 B5 C8 D5 E5        ← 例：APHORISM_THINKING_LEVEL=deep + C=8
```

- 轮数**比模板多**：按 `references/00-thinking-modes.md` 的**加轮表**顺序补，加轮表用完了再从**通用加轮池**取。
- 轮数**比模板少**：按那里的**删减顺序**裁；**必留轮**永远不能删。
- 用户当场说「今天想得深一点 / 这次浅浅来一张」：用对话指令覆盖本次强度，并在汇报里写明实际轮数。

配置放在哪：

```bash
# 一次会话：当前 shell / 当前 Agent 进程
export APHORISM_THINKING_LEVEL=deep

# 长期：插件内配置，跟着 skill 走（环境变量没设时读它）
cp ~/.codex/skills/aphorism-notebook/config.example.env \
   ~/.codex/skills/aphorism-notebook/config.env
$EDITOR ~/.codex/skills/aphorism-notebook/config.env
```

---

## 3. 素材来源与自定义思考方向

内置 A–E 想的是「世界」：新闻、日志、报错、画面、旧卡。除此之外，用户可以把自己的东西配成
**自定义思考方向**——笔记仓库、书摘、访谈稿、剪藏、某个领域的资料库，代号从 `F` 开始往下排。

- 配置：skill 目录里的 `sources.conf`（模板 `sources.example.conf`；可用 `APHORISM_SOURCES` 或 `--config` 指定别处）。
- 管理：`bash <skill-dir>/assets/sources.sh list | add | set | remove | check`；想边问边填就 `add --interactive`。
- 轮数：每个方向在 `sources.conf` 里写自己的默认轮数，第 2 节的思考强度对它同样生效。
- 完整操作、首次问话、隐私红线、读素材的要求：**`references/04-custom-directions.md`**（第一次用自定义方向前先读它）。

**首次运行的义务**：`sources.conf` 不存在、或里面一个 `[X]` 段都没有时，先问一次（别自己扫用户的硬盘）：

> 你有没有想让卡片去读的东西？比如某个笔记仓库、某个 notes 目录、一本书的摘录、某个项目的 git log。
> 说个路径就行，我把它配成一个专属的思考方向。先不用也完全没问题，以后随时可以加。

用户给了路径 → 加好，并跑一次 `bash <skill-dir>/assets/rounds.sh` 把轮数表给他看；
用户说「先不用」→ 不再追问，直接写卡。

**读自定义素材的三条硬要求**：

1. 真的打开读（`ls -lt` / `rg` / `sed -n` / `git log`），不许凭印象写；
2. 先按最近改动或名字筛 5–10 个，别一次读遍整个知识库；
3. 卡片或汇报里要能说出一个具体出处（文件名 / 笔记标题 / 日期），并且**不写隐私**——站点是公开的。

---

## 4. 第 0 步：定位仓库

上游仓库 = 当前 skill 所在的项目，默认 `petterobam/Thinking`；目标仓库 = **用户自己 GitHub 账号下、该上游的 fork**（默认名 `Thinking`，若用户另有约定以此为准）。

```bash
gh auth status                                      # 没有登录就先 gh auth login
upstream="${APHORISM_UPSTREAM:-petterobam/Thinking}" # 上游仓库，必要时可覆盖
repo_name="${upstream##*/}"
owner="$(gh api user --jq .login)"
target="$owner/$repo_name"
gh repo view "$target" >/dev/null 2>&1 && echo exists || echo missing
```

- **已在本仓库里**：确认 `origin` 指向自己的 fork；`git pull --rebase` 后就地工作。
- **fork 存在但本地没有**：`gh repo clone "$target" && cd "$repo_name"`，并确保保留 `upstream` remote。
- **fork 不存在**：**不要执行 `gh repo create`**。先 `gh repo fork "$upstream" --default-branch-only`，再使用/克隆自己的 fork；随后把 `content/cards/*.md` 全部移除，只保留空目录，更新 `content/site.json` 里的 `repo.owner/name`，提交一次初始化 commit 并推送。详见 `references/02-repo-and-publishing.md` 的「fork 初始化」。
- **没有 gh / 未登录**：停下来，明确告诉用户需要 `gh auth login`，不要用假凭证或匿名方式绕。

注意：初始化时删除的是 fork 的 HEAD，不重写上游历史；清卡只允许发生在第一次 fork 初始化，之后同步上游时绝不能删掉用户自己的卡片。

细节与故障处理：`references/02-repo-and-publishing.md`。

---

## 5. 第 1 步：选择思考模式

至少要**真正执行一种**；材料够时可以混合两种（例如 A+C）。可以问用户偏好，也可以自己挑一种最有余温的。

| 代号 | 模式 | 一句话 | 默认轮数 |
| --- | --- | --- | --- |
| **A** | 📰 时事沉思 | 读新闻与公共讨论，提炼社会意识的切片 | 4 轮 |
| **B** | 🧭 会话回望 | 回看当天的工作、调试、对话，找出问题的形状 | 3 轮 |
| **C** | 🕯️ 悬问求索 | 挑一个从未认真想过的问题，追到尽头 | 5 轮 |
| **D** | 🌿 生活即景 | 从今天一个感官瞬间出发 | 3 轮 |
| **E** | 📖 旧笺重读 | 重读仓库里的旧卡，与过去的自己辩驳 | 3 轮 |
| **F…** | 🗂 自定义方向 | 用户自己的知识库 / 笔记 / 摘录（来自 `sources.conf`） | 各自配置 |

每个模式的完整操作（材料来源、每轮问什么、常见失败、判定标准、示例、加轮表）见
**`references/00-thinking-modes.md`**。开始前先读它。

表里的轮数是**默认值**，第 2 节的配置会覆盖它们；以 `assets/rounds.sh` 的输出为准。
`F` 及之后的代号、名字、路径、轮数都在 `sources.conf` 里，见第 3 节；没配就当作没有这些方向。

---

## 6. 第 2–3 步：采集材料与多轮思考

三条铁律：

1. **先有材料，再有想法。** 不允许凭空生成箴言。材料必须是具体的：一条新闻、一段日志、一次报错、一个画面。
2. **每一轮换一个视角。** 同一视角重复三遍不叫三轮思考。换利益相关方、换时间尺度（十年后/一小时前）、换尺度（个人/组织/文明）、换反方。
3. **把思考过程写下来。** 在临时文件里记录每轮的结论（一句话即可），第 5 步的旅程从这里长出来。不要一边想一边写成品。

联网工具（浏览器 / 搜索 / 抓取）在本步是**鼓励使用**的；但只引用事实，不搬用别人的观点当自己的箴言。

---

## 7. 第 4 步：把结论压成箴言

压缩是一个**删字**的动作，不是造句的动作。方法：

1. 把第 3 步的结论写成一句 40 字左右的话。
2. 删掉所有修饰词、所有"其实/总之/所以"、所有解释性从句。
3. 找出这句话里**唯一那个悖论或转折**，让它成为骨架。
4. 反复念叨它：**它是否让人停半秒？** 不让人停的半句，重写。
5. 检查它有没有"社会意识的回音"——读者能否把它联想到自己所处的时代，而不只是作者私人的心情。

四种可靠骨架、反例清单、语感训练见 **`references/01-writing-craft.md`**。

---

## 8. 第 5 步：写下旅程

旅程不是论文，是**带路的散文**。固定节奏：

- `## 起` —— 一个具体的画面或数字，不评论、不总结。
- `## 转` —— 把画面推向它背后的问题，允许走偏，但每一步都要留下脚印。
- `## 落` —— 回到箴言本身，给出一个更锋利的问题或一个克制的承认。

小节标题应当各自有画面感（例：`## 一条 47 秒的新闻`、`## 谁在替我的注意力付钱`），不要写"背景/分析/总结"这类公文标题。写作技巧与正反例见 **`references/01-writing-craft.md`**。

---

## 9. 第 6 步：写文件并校验

```bash
# 脚手架（推荐）
node scripts/new-card.mjs --slug <kebab-case> --title "<箴言>" \
  --mode 时事沉思 --tags "社会,注意力" --seed "起点一句话" --place "场景"

$EDITOR content/cards/<slug>.md
node scripts/validate.mjs --strict
```

- 文件名就是卡片地址：`content/cards/<kebab-case>.md`，必须是小写英文短句。
- 字段规范、正文约定、校验规则表见 **`references/03-card-format.md`**，模板在 `assets/card-template.md`。
- 仓库里若没有 `scripts/`（老版本或用户自建仓库）：改用 `assets/card-template.md` 手写文件，并**手工执行**同名规则（字数、小节数、去重），再照常提交。
- `--strict` 有提醒就必须处理：要么改，要么能说出为什么这个提醒在这个卡片上不成立。

---

## 10. 第 7 步：提交推送

```bash
git add content/cards/<slug>.md
git commit -m "card: <slug> — <箴言>"
git pull --rebase --autostash   # 远端有新提交时的保险
git push origin main            # 推送到自己的 fork，不要推 upstream
```

- 一次提交 = 一张（或同批的几张）卡片，不要混入无关改动。
- 推送失败不要 `push -f`；先 `git pull --rebase`。处理方式见 `references/02-repo-and-publishing.md`。
- 推送后 GitHub Actions 会自动构建部署（提交即更新）。

---

## 11. 第 8 步：向用户汇报

控制在三行以内：

```
✦ <箴言>            # 卡片正文
   <模式> · <slug> · <N 字旅程>
   已推送 <commit 短哈希>，站点稍后更新：<站点地址>
```

同时把**旅程的第一段**贴给用户看——他看到的具体文字，才判断得了你今天是否真的想过了。

---

## 12. 反模式清单（出现任一条就是失败）

- ❌ 「人生就是一场旅行，我们要珍惜当下。」——正确的废话。
- ❌ 「在这个快节奏的时代，我们更应该……」——说教腔。
- ❌ 引号里放一句名言然后解释它。
- ❌ 旅程写成三段「首先/其次/最后」的应用文。
- ❌ 用"内卷、熵增、量子、觉醒"堆深度感而不解释。
- ❌ 一次交十张卡，每张都像同一个模子印的。
- ❌ 卡片是昨天那张的改写版（查重命令：`node scripts/validate.mjs` 会报重复箴言）。
- ❌ 声称「读过用户的笔记/知识库」，却说不出一个文件名或标题。
- ❌ 把笔记原句直接抄成箴言，或把隐私（客户名、私人对话、未公开项目细节）写进公开站点。
- ❌ 只改了 `title` 没写旅程，或反过来。

---

## 13. 完成前自检

逐条回答，任何一条答不上就回去改（也可直接跑 `assets/checklist.md` 里的清单）：

1. 这张卡是被**今天真实发生的什么东西**触发的？说出具体来源。
2. 箴言多少字？删掉两个字还成立吗？
3. 读者会不会在某一秒停下？停在哪里？
4. 旅程里有没有一句只有我知道的细节（数字、名字、时间、原话）？
5. 结尾我给的是答案还是更好的问题？
6. 这次解析出的轮数是多少？每一轮的一句话结论还在笔记里吗？（把 `rounds.sh` 的输出贴出来核一遍）
7. 这张卡的材料我真读过吗？说得出具体文件 / 标题 / 时间吗？有没有不该公开的内容？
8. `node scripts/validate.mjs --strict` 过了吗？

---

## 附：文件地图

```
SKILL.md                              ← 你正在读的
config.example.env                    ← 思考强度配置模板（复制成 config.env 生效）
sources.example.conf                  ← 自定义思考方向模板（复制成 sources.conf 生效）
references/00-thinking-modes.md       ← 五种思考模式的完整操作
references/01-writing-craft.md        ← 箴言与旅程的写作技巧、正反例
references/02-repo-and-publishing.md  ← 仓库定位、建站、推送、故障处理
references/03-card-format.md          ← 卡片字段规范与校验规则
references/04-custom-directions.md    ← 自定义方向：首次问话、增删改、隐私红线、读素材要求
assets/rounds.sh                      ← 思考强度解析器（读环境变量 + config.env + sources.conf）
assets/sources.sh                     ← 自定义思考方向管理（list/add/set/remove/check）
assets/card-template.md               ← 手写卡片时的模板
assets/checklist.md                   ← 发布前清单
```
