/**
 * Loads card files, renders them, and enforces the notebook's house rules.
 *
 * A card is one aphorism: a very short line, plus the thinking journey that
 * produced it. The rules below are the machine-checkable half of the writing
 * guide in skill/aphorism-notebook/references/01-writing-craft.md
 */

import fs from 'node:fs';
import path from 'node:path';
import { parseFrontMatter } from './frontmatter.mjs';
import { renderMarkdown, splitSections, countReadable, visibleLength } from './markdown.mjs';

export const MODES = {
  '时事沉思': { emoji: '📰', hint: '从新闻与公共事件中提炼社会意识的切片' },
  '会话回望': { emoji: '🧭', hint: '回看当天的工作、调试与对话，找出问题的形状' },
  '悬问求索': { emoji: '🕯️', hint: '挑一个从未认真想过的问题，追到尽头' },
  '生活即景': { emoji: '🌿', hint: '从通勤、晚餐、雨天里捡起一个瞬间' },
  '旧笺重读': { emoji: '📖', hint: '重读旧卡，与过去的自己辩驳' },
  '思想库拾遗': { emoji: '🗃', hint: '从自己的研究笔记里捡起一条旧发现，剥到人话' },
};

export const LIMITS = {
  titleMin: 4,
  titleSoftMax: 16,
  titleHardMax: 22,
  bodyMin: 120,
  bodySoftMax: 900,
  bodyHardMax: 2000,
  sectionsMin: 2,
  sectionsMax: 6,
};

const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function readCards(rawDir) {
  if (!fs.existsSync(rawDir)) return [];
  return fs
    .readdirSync(rawDir)
    .filter((f) => f.endsWith('.md'))
    .sort()
    .map((file) => ({ file, raw: fs.readFileSync(path.join(rawDir, file), 'utf8') }));
}

/**
 * @returns {{ cards: object[], problems: {level:'error'|'warn', file:string, message:string}[] }}
 */
export function loadCards(rawDir, { today } = {}) {
  const problems = [];
  const cards = [];
  const seen = new Map();

  for (const { file, raw } of readCards(rawDir)) {
    const slug = file.replace(/\.md$/, '');
    const { data, body, hasFrontMatter } = parseFrontMatter(raw);
    const at = (level, message) => problems.push({ level, file, message });

    if (!hasFrontMatter) { at('error', '缺少 front-matter（文件应以 --- 开头）'); continue; }
    if (!SLUG_RE.test(slug)) at('error', `文件名必须是 kebab-case 英文短句：${slug}`);

    const title = String(data.title ?? '').trim();
    if (!title) at('error', '缺少 title（箴言正文）');

    const date = String(data.date ?? '').trim();
    if (!DATE_RE.test(date)) at('error', 'date 必须形如 2026-10-11');
    if (today && DATE_RE.test(date) && date > today) at('warn', `date 在未来：${date}`);

    const mode = String(data.mode ?? '').trim();
    if (!mode) at('warn', '缺少 mode（建议填：时事沉思 / 会话回望 / 悬问求索 / 生活即景 / 旧笺重读）');
    else if (!MODES[mode]) at('warn', `mode 不在推荐集合内：${mode}`);

    const tags = Array.isArray(data.tags) ? data.tags.map((t) => String(t).trim()).filter(Boolean) : [];
    if (!tags.length) at('warn', '缺少 tags，卡片将无法被主题筛选');
    if (tags.length > 3) at('warn', `tags 超过 3 个（${tags.length}），标签应克制`);

    const rendered = renderMarkdown(body);
    const stops = splitSections(body);
    const readLen = countReadable(rendered.text);
    const sections = rendered.headings.filter((h) => h.level === 2);

    if (!title) { /* already reported */ } else {
      const len = visibleLength(title);
      if (len < LIMITS.titleMin) at('error', `箴言太短（${len} 字），至少要有一个完整的意思`);
      if (len > LIMITS.titleHardMax) at('error', `箴言太长（${len} 字），上限 ${LIMITS.titleHardMax} 字`);
      else if (len > LIMITS.titleSoftMax) at('warn', `箴言 ${len} 字，超过 ${LIMITS.titleSoftMax} 字就不再"一眼可读"`);
      if (/[。！]$/.test(title)) at('warn', '箴言结尾不必加句号或叹号');
      if (/\n/.test(title)) at('error', 'title 必须是单行');
    }

    if (readLen < LIMITS.bodyMin) at('warn', `正文过短（${readLen} 字），故事要有血肉`);
    if (readLen > LIMITS.bodyHardMax) at('error', `正文过长（${readLen} 字），上限 ${LIMITS.bodyHardMax} 字`);
    else if (readLen > LIMITS.bodySoftMax) at('warn', `正文 ${readLen} 字，接近"流水账"警告线，考虑删掉一半`);
    if (sections.length < LIMITS.sectionsMin) at('warn', `正文只有 ${sections.length} 个 "## 小节"，思想旅程至少要有起承两部分`);
    if (sections.length > LIMITS.sectionsMax) at('error', `"## 小节" 超过 ${LIMITS.sectionsMax} 个，旅程太长会失焦`);

    if (seen.has(title)) at('error', `箴言与 ${seen.get(title)} 重复：${title}`);
    seen.set(title, slug);

    const seed = String(data.seed ?? '').trim();
    if (!seed) at('warn', '缺少 seed（这张卡是被什么触发的），读者会失去"起点"');

    cards.push({
      slug,
      title,
      date,
      mode: mode || '随笔',
      modeEmoji: MODES[mode]?.emoji ?? '✎',
      tags,
      seed,
      place: String(data.place ?? '').trim(),
      quote: String(data.quote ?? '').trim(),
      pinned: String(data.pinned ?? '').trim() === 'true',
      bodyHtml: rendered.html,
      headings: rendered.headings,
      sections: sections.map((h) => ({ id: h.id, text: h.text })),
      stops: stops.map(({ index, id, title, prologue, html }) => ({ index, id, title, prologue, html })),
      readLen,
      minutes: Math.max(1, Math.round(readLen / 320)),
      excerpt: rendered.text.replace(/\s+/g, ' ').slice(0, 60),
      file,
    });
  }

  cards.sort((a, b) => (a.date === b.date ? a.slug.localeCompare(b.slug) : b.date.localeCompare(a.date)));
  const errors = problems.filter((p) => p.level === 'error');
  return { cards, problems, ok: errors.length === 0 };
}
