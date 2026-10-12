#!/usr/bin/env node
/**
 * Static site generator for 思笺 · Thought Cards.
 *
 *   node build/build.mjs            # one-shot build into dist/
 *   node build/build.mjs --serve    # build + live-reloading preview on :4321
 *   node build/build.mjs --watch    # rebuild on change (CI never uses this)
 *
 * Zero dependencies on purpose: CI only needs `node`.
 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { loadCards, MODES } from '../scripts/lib/cards.mjs';
import { escapeHtml } from '../scripts/lib/markdown.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const argv = process.argv.slice(2);
const flag = (name) => argv.includes(`--${name}`);
const valueOf = (name, fallback) => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};

const OUT = path.resolve(root, valueOf('out', 'dist'));
const SERVE = flag('serve');
const WATCH = flag('watch') || SERVE;

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function resolveBase() {
  if (process.env.BASE_PATH) return process.env.BASE_PATH.replace(/\/?$/, '/');
  const repo = process.env.GITHUB_REPOSITORY;
  if (repo) {
    const [owner, name] = repo.split('/');
    return name.toLowerCase() === `${owner.toLowerCase()}.github.io` ? '/' : `/${name}/`;
  }
  return '/';
}

function resolveSiteUrl(site, base) {
  if (process.env.SITE_URL) return process.env.SITE_URL.replace(/\/?$/, '/');
  if (site.siteUrl) return String(site.siteUrl).replace(/\/?$/, '/');
  const owner = site.repo?.owner || 'your-name';
  const name = site.repo?.name || 'Thinking';
  // The published address is stable even when previewing locally with base "/".
  if (name.toLowerCase() === `${owner.toLowerCase()}.github.io`) return `https://${owner}.github.io/`;
  return `https://${owner}.github.io/${name}/`;
}

/* ------------------------------------------------------------------ helpers */

const fmtDate = (iso) => {
  const [y, m, d] = String(iso).split('-');
  return `${y} 年 ${Number(m)} 月 ${Number(d)} 日`;
};

function fill(template, values) {
  return template.replace(/\{\{(\w+)\}\}/g, (whole, key) =>
    Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : whole);
}

function cardMarkup(card, base) {
  const tags = (card.tags || []).map((t) => `#${escapeHtml(t)}`).join(' ');
  return `      <article class="card" data-slug="${card.slug}" data-mode="${escapeHtml(card.mode)}" data-tags="${escapeHtml((card.tags || []).join('|'))}">
        <a class="card-link" href="${base}c/${card.slug}/" data-slug="${card.slug}">
          <span class="card-tab">${escapeHtml(card.mode)}</span>
          <h2 class="card-line">${escapeHtml(card.title)}</h2>
          <p class="card-note">${escapeHtml(card.seed || card.excerpt || '')}</p>
          <span class="card-foot">
            <time datetime="${card.date}">${card.date.replace(/-/g, '.')}</time>
            <span class="card-tags">${tags}</span>
          </span>
        </a>
      </article>`;
}

function stopsMarkup(card) {
  return (card.stops || []).map((stop) => `      <section class="stop" id="stop-${stop.id}">
        <h3 class="stop-title">${escapeHtml(stop.prologue ? '序' : stop.title)}</h3>
        <div class="stop-body">${stop.html}</div>
      </section>`).join('\n');
}

function buildChips(cards) {
  const modes = new Map();
  const tags = new Map();
  for (const card of cards) {
    modes.set(card.mode, (modes.get(card.mode) || 0) + 1);
    for (const tag of card.tags || []) tags.set(tag, (tags.get(tag) || 0) + 1);
  }
  // Counts live on "全部" only; a filter row is a set of words, not a table.
  const chip = (value, label, on) =>
    `<button class="chip" type="button" data-value="${escapeHtml(value)}" aria-pressed="${on ? 'true' : 'false'}">${label}</button>`;

  const parts = [chip('*', `全部 ${cards.length}`, true)];
  for (const [mode] of modes) parts.push(chip(mode, escapeHtml(mode), false));
  const topTags = [...tags.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 12);
  for (const [tag] of topTags) parts.push(chip(tag, `#${escapeHtml(tag)}`, false));
  return parts.join('\n        ');
}

function favicon(accent, char) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="${accent}"/>
  <text x="32" y="45" font-size="38" text-anchor="middle" fill="#fff8f2" font-family="Songti SC, Noto Serif SC, serif">${char}</text>
</svg>
`;
}

function feed(cards, site, siteUrl, base) {
  const updated = cards.length ? new Date(cards[0].date + 'T09:00:00Z').toISOString() : new Date().toISOString();
  const entries = cards.slice(0, 40).map((card) => `  <entry>
    <title>${escapeHtml(card.title)}</title>
    <link href="${siteUrl}c/${card.slug}/"/>
    <id>${siteUrl}c/${card.slug}/</id>
    <updated>${new Date(card.date + 'T09:00:00Z').toISOString()}</updated>
    <category term="${escapeHtml(card.mode)}"/>
    <summary type="text">${escapeHtml(card.seed || card.excerpt)}</summary>
    <content type="html">${escapeHtml(card.bodyHtml).replace(/\n/g, ' ')}</content>
  </entry>`).join('\n');

  return `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="zh-CN">
  <title>${escapeHtml(site.title)}</title>
  <subtitle>${escapeHtml(site.tagline)}</subtitle>
  <link href="${siteUrl}feed.xml" rel="self"/>
  <link href="${siteUrl}"/>
  <id>${siteUrl}</id>
  <updated>${updated}</updated>
  <author><name>${escapeHtml(site.author)}</name></author>
  <generator uri="${site.repo ? `https://github.com/${site.repo.owner}/${site.repo.name}` : siteUrl}">思笺 build.mjs</generator>
${entries}
</feed>
`;
}

/* ------------------------------------------------------------------- agents */

function agentPrompt(site, siteUrl) {
  const repo = site.repo?.name || 'Thinking';
  const owner = site.repo?.owner || '你的账号';
  return `请安装并使用「箴言笔记 / aphorism-notebook」skill，为我的箴言卡片站写一张新卡片：
1) 先运行：curl -fsSL ${siteUrl}skill/install.sh | bash
2) 读取安装好的 SKILL.md（~/.codex/skills/${site.skill?.name || 'aphorism-notebook'}/SKILL.md），严格按其中流程执行。
3) 目标仓库：GitHub 账号 ${owner} 下的 ${repo} 仓库；如果不存在，就用 gh 从上游 fork 一份，并移除上游已有的卡片。
4) 思考完之后：写卡片 → node scripts/validate.mjs --strict → 提交推送。`;
}

/* -------------------------------------------------------------------- build */

function build() {
  const started = Date.now();
  const site = readJson(path.join(root, 'content', 'site.json'));
  const base = resolveBase();
  const siteUrl = resolveSiteUrl(site, base);
  const today = new Date().toLocaleDateString('sv-SE');
  const { cards, problems, ok } = loadCards(path.join(root, 'content', 'cards'), { today });

  for (const p of problems) console.log(`${p.level === 'error' ? '✗' : '·'} ${p.file} — ${p.message}`);
  if (!ok) {
    console.error('\n构建中止：内容校验未通过。运行 node scripts/validate.mjs 查看全部问题。');
    process.exit(1);
  }
  if (!cards.length) console.warn('提示：content/cards 里还没有卡片，站点会是空的。');

  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });

  const repoUrl = site.repo ? `https://github.com/${site.repo.owner}/${site.repo.name}` : siteUrl;
  const theme = 'light';
  const updated = cards.length ? fmtDate(cards[0].date) : fmtDate(today);
  const avgLen = cards.length ? Math.round(cards.reduce((s, c) => s + c.title.length, 0) / cards.length) : 0;
  const payload = {
    base,
    siteUrl,
    repoUrl,
    title: site.title,
    generatedAt: new Date().toISOString(),
    cards: cards.map((c) => ({
      slug: c.slug,
      title: c.title,
      date: c.date,
      mode: c.mode,
      modeEmoji: c.modeEmoji,
      tags: c.tags,
      seed: c.seed,
      place: c.place,
      quote: c.quote,
      minutes: c.minutes,
      excerpt: c.excerpt,
      stops: c.stops,
    })),
  };

  const fontLink = site.fontHref
    ? `<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />\n<link rel="stylesheet" href="${site.fontHref}" />`
    : '';

  const shared = {
    base,
    siteUrl,
    repoUrl,
    theme,
    fontLink,
    accent: site.accent || '#b4482c',
    title: site.title,
    subtitle: site.subtitle || '',
    tagline: site.tagline,
    intro: site.intro || '',
    description: site.description,
    author: site.author,
    sealChar: (site.title || '思').trim().slice(0, 1),
    skillName: site.skill?.name || 'aphorism-notebook',
  };

  // ---- index.html
  const indexTemplate = fs.readFileSync(path.join(root, 'src', 'template.html'), 'utf8');
  const indexHtml = fill(indexTemplate, {
    ...shared,
    count: cards.length,
    updated,
    avgLen,
    chips: buildChips(cards),
    cards: cards.map((c) => cardMarkup(c, base)).join('\n'),
    data: JSON.stringify(payload).replace(/</g, '\\u003c'),
    agentPrompt: escapeHtml(agentPrompt(site, siteUrl)),
  });
  fs.writeFileSync(path.join(OUT, 'index.html'), indexHtml);

  // ---- single card pages
  const cardTemplate = fs.readFileSync(path.join(root, 'src', 'card.template.html'), 'utf8');
  for (const card of cards) {
    const dir = path.join(OUT, 'c', card.slug);
    fs.mkdirSync(dir, { recursive: true });
    const cardUrl = `${siteUrl}c/${card.slug}/`;
    const html = fill(cardTemplate, {
      ...shared,
      siteTitle: site.title,
      title: card.title,
      description: `${card.title} —— ${card.seed || card.excerpt}`,
      excerpt: card.seed || card.excerpt,
      cardUrl,
      date: card.date,
      mode: card.mode,
      modeEmoji: card.modeEmoji,
      slug: card.slug,
      meta: [
        `<span>${card.date.replace(/-/g, '.')}</span>`,
        card.place ? `<span>${escapeHtml(card.place)}</span>` : '',
        `<span>约 ${card.minutes} 分钟</span>`,
        ...(card.tags || []).map((t) => `<span>#${escapeHtml(t)}</span>`),
      ].filter(Boolean).join(''),
      seedHtml: card.seed ? `<b>起点</b>${escapeHtml(card.seed)}` : '',
      quoteHtml: card.quote ? `<blockquote class="pull-quote">${escapeHtml(card.quote)}</blockquote>` : '',
      stops: stopsMarkup(card),
    });
    fs.writeFileSync(path.join(dir, 'index.html'), html);
  }

  // ---- static assets
  fs.copyFileSync(path.join(root, 'src', 'styles.css'), path.join(OUT, 'styles.css'));
  fs.copyFileSync(path.join(root, 'src', 'app.js'), path.join(OUT, 'app.js'));
  fs.writeFileSync(path.join(OUT, 'favicon.svg'), favicon(site.accent || '#b4482c', shared.sealChar));

  // ---- 404 (deep links land back on the wall, focused on the card)
  fs.writeFileSync(path.join(OUT, '404.html'), `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>没有这张卡片 · ${escapeHtml(site.title)}</title>
<link rel="stylesheet" href="${base}styles.css"/>
<meta http-equiv="refresh" content="0; url=${base}"/>
</head><body><div class="page"><p class="seed-note">这一页不存在，正在回到卡片墙…</p>
<p><a class="icon-btn" href="${base}">回到 ${escapeHtml(site.title)}</a></p>
<script>location.replace('${base}');</script></div></body></html>
`);

  // ---- feed, robots, .nojekyll
  fs.writeFileSync(path.join(OUT, 'feed.xml'), feed(cards, site, siteUrl, base));
  fs.writeFileSync(path.join(OUT, 'robots.txt'), `User-agent: *\nAllow: /\nSitemap: ${siteUrl}sitemap.xml\n`);
  fs.writeFileSync(path.join(OUT, 'sitemap.xml'), `<?xml version="1.0" encoding="utf-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>${siteUrl}</loc><lastmod>${cards[0]?.date || today}</lastmod></url>
${cards.map((c) => `  <url><loc>${siteUrl}c/${c.slug}/</loc><lastmod>${c.date}</lastmod></url>`).join('\n')}
</urlset>
`);
  fs.writeFileSync(path.join(OUT, '.nojekyll'), '');

  // ---- the skill, published alongside the site
  const skillSrc = path.join(root, 'skill', shared.skillName);
  const skillOut = path.join(OUT, 'skill');
  const files = [];
  const copyTree = (from, to, prefix) => {
    fs.mkdirSync(to, { recursive: true });
    for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
      const src = path.join(from, entry.name);
      const dst = path.join(to, entry.name);
      if (entry.isDirectory()) copyTree(src, dst, `${prefix}${entry.name}/`);
      else {
        fs.copyFileSync(src, dst);
        files.push(`${prefix}${entry.name}`);
      }
    }
  };
  fs.mkdirSync(skillOut, { recursive: true });
  if (fs.existsSync(path.join(root, 'skill', 'install.sh'))) {
    fs.copyFileSync(path.join(root, 'skill', 'install.sh'), path.join(skillOut, 'install.sh'));
  }
  copyTree(skillSrc, path.join(skillOut, shared.skillName), `${shared.skillName}/`);
  files.push('install.sh');
  fs.writeFileSync(path.join(skillOut, 'files.txt'), files.sort().join('\n') + '\n');
  fs.writeFileSync(path.join(skillOut, 'index.html'), skillLanding(site, shared, base, repoUrl));

  // ---- dev-only live reload
  if (SERVE) {
    const reload = `\n<script>new EventSource('${base}__reload').onmessage=function(){location.reload()};</script>\n`;
    fs.appendFileSync(path.join(OUT, 'index.html'), reload);
  }

  const ms = Date.now() - started;
  console.log(`✓ 构建完成 ${cards.length} 张卡片 → ${path.relative(root, OUT)}/ (${ms}ms, base=${base})`);
  return { cards, base, siteUrl };
}

function skillLanding(site, shared, base, repoUrl) {
  const skill = shared.skillName;
  return `<!doctype html>
<html lang="zh-CN" data-theme="light"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${escapeHtml(site.skill?.displayName || skill)} · skill</title>
<link rel="stylesheet" href="../styles.css"/>
<style>:root{--accent:${shared.accent}}</style></head>
<body><div class="atmosphere"></div>
<article class="page">
  <a class="back" href="../">← 回到 ${escapeHtml(site.title)}</a>
  <span class="section-label">Skill</span>
  <h1 class="panel-line" style="margin-top:.8rem">${escapeHtml(site.skill?.displayName || skill)}</h1>
  <div class="panel-rule"></div>
  <p class="seed-note"><b>一句话安装</b>curl -fsSL ${shared.siteUrl}skill/install.sh | bash</p>
  <div class="journey" style="margin-top:2rem">
    <section class="stop is-in"><h3 class="stop-title">文件</h3><div class="stop-body">
      <ul>${['install.sh', 'files.txt', `${skill}/SKILL.md`].map((f) => `<li><a href="./${f}">${f}</a></li>`).join('')}</ul>
      <p>完整清单见 <a href="./files.txt">files.txt</a>，源码见 <a href="${repoUrl}/tree/main/skill">${repoUrl}/tree/main/skill</a>。</p>
    </div></section>
    <section class="stop is-in"><h3 class="stop-title">手动安装</h3><div class="stop-body">
      <p>把 skill 目录整体拷到你的 Agent 的 skills 目录即可：</p>
      <pre><code>git clone ${repoUrl}.git
cp -r Thinking/skill/${skill} ~/.codex/skills/</code></pre>
    </div></section>
  </div>
</article></body></html>
`;
}

/* ------------------------------------------------------------------- serving */

async function serve(initial) {
  let state = initial;
  const clients = new Set();
  const port = Number(valueOf('port', 4321));
  const MIME = {
    '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
    '.svg': 'image/svg+xml', '.xml': 'application/xml; charset=utf-8',
    '.txt': 'text/plain; charset=utf-8', '.sh': 'text/x-sh; charset=utf-8',
    '.md': 'text/markdown; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg',
  };

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://localhost:${port}`);
    if (url.pathname.endsWith('/__reload')) {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
      res.write('retry: 500\n\n');
      clients.add(res);
      req.on('close', () => clients.delete(res));
      return;
    }
    let rel = decodeURIComponent(url.pathname);
    if (state.base !== '/' && rel.startsWith(state.base)) rel = rel.slice(state.base.length - 1);
    let file = path.join(OUT, rel);
    if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
    if (!fs.existsSync(file)) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(fs.readFileSync(path.join(OUT, '404.html')));
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(fs.readFileSync(file));
  });

  const host = valueOf('host', '127.0.0.1');
  server.listen(port, host, () => {
    console.log(`\n  预览： http://${host}:${port}${state.base}\n  改动 content/ 或 src/ 会自动重建，浏览器自动刷新。\n`);
  });

  let timer = null;
  const watchDirs = ['content', 'src', 'skill', 'scripts'].map((d) => path.join(root, d));
  for (const dir of watchDirs) {
    if (!fs.existsSync(dir)) continue;
    fs.watch(dir, { recursive: true }, () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        try {
          state = build();
          clients.forEach((c) => c.write('data: reload\n\n'));
        } catch (err) {
          console.error('重建失败：', err.message);
        }
      }, 120);
    });
  }
}

const initial = build();
if (SERVE) serve(initial);
