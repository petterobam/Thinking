/* ==========================================================================
   思笺 · Thought Cards — interactions (pass 2)
   Motion only answers a person's action: opening a card, expanding filters.
   ========================================================================== */
(function () {
  'use strict';

  var dataEl = document.getElementById('notebook-data');
  if (!dataEl) return;

  var DATA;
  try { DATA = JSON.parse(dataEl.textContent); } catch (e) { return; }
  var cards = DATA.cards || [];
  var bySlug = {};
  cards.forEach(function (card, i) { card.index = i; bySlug[card.slug] = card; });

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };
  var root = document.documentElement;

  function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  /* ---------- toast + clipboard ---------------------------------------- */
  var toastEl = $('#toast');
  var toastTimer;

  function say(message) {
    if (!toastEl) return;
    toastEl.textContent = message;
    toastEl.classList.add('is-on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.classList.remove('is-on'); }, 1900);
  }

  function copyText(text, okMessage) {
    var done = function () { say(okMessage || '已复制'); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () { say('复制失败，请手动选中复制'); });
    } else {
      var ta = document.createElement('textarea');
      ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select();
      try { document.execCommand('copy'); done(); } catch (e) { say('复制失败，请手动选中复制'); }
      document.body.removeChild(ta);
    }
  }

  $$('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var target = document.querySelector(btn.dataset.copy);
      if (target) copyText(target.textContent.trim(), '已复制到剪贴板');
    });
  });

  /* ---------- theme ---------------------------------------------------- */
  var themeBtn = $('#theme-toggle');

  function paintThemeIcons() {
    if (!themeBtn) return;
    var dark = root.dataset.theme === 'dark';
    var moon = $('.icon-moon', themeBtn), sun = $('.icon-sun', themeBtn);
    if (moon) moon.hidden = dark;
    if (sun) sun.hidden = !dark;
    themeBtn.setAttribute('aria-pressed', String(dark));
  }

  paintThemeIcons();
  if (themeBtn) {
    themeBtn.addEventListener('click', function () {
      var next = root.dataset.theme === 'dark' ? 'light' : 'dark';
      root.dataset.theme = next;
      try { localStorage.setItem('notebook-theme', next); } catch (e) {}
      paintThemeIcons();
    });
  }

  /* ---------- the skill strip ------------------------------------------ */
  var briefToggle = $('#brief-toggle');
  var briefDetail = $('#brief-detail');
  if (briefToggle && briefDetail) {
    briefToggle.addEventListener('click', function () {
      var opening = briefDetail.hidden;
      briefDetail.hidden = !opening;
      briefToggle.setAttribute('aria-expanded', String(opening));
      briefToggle.textContent = opening ? '收起步骤' : '详细步骤';
    });
  }

  /* ---------- filters -------------------------------------------------- */
  var grid = $('#grid');
  var cardEls = $$('.card', grid);
  var chipRow = $('#chips');
  var chipToggle = $('#chip-toggle');
  var searchInput = $('#q');
  var activeFilter = '*';
  var query = '';
  var emptyNote = null;

  function visibleChips() {
    return $$('.chip', chipRow);
  }

  function lastVisible(chips) {
    for (var i = chips.length - 1; i >= 0; i -= 1) if (!chips[i].hidden) return chips[i];
    return null;
  }

  // Measure the actual right edge of the last visible chip instead of trusting
  // scrollWidth: a chip must never sit half-clipped at the fold.
  function overflows(chips) {
    var last = lastVisible(chips);
    if (!last) return false;
    return last.getBoundingClientRect().right > chipRow.getBoundingClientRect().right + 0.5;
  }

  function fitChips() {
    if (!chipRow || !chipToggle) return;
    var chips = visibleChips();
    if (!chips.length) return;
    chipRow.classList.remove('is-open');
    chipToggle.setAttribute('aria-expanded', 'false');
    chipToggle.textContent = '展开 ▾';
    chips.forEach(function (c) { c.hidden = false; });
    chipToggle.hidden = true;
    if (!overflows(chips)) return;

    chipToggle.hidden = false;
    for (var i = chips.length - 1; i >= 1; i -= 1) {
      chips[i].hidden = true;
      if (!overflows(chips)) break;
    }
  }

  if (chipToggle) {
    chipToggle.addEventListener('click', function () {
      var opening = !chipRow.classList.contains('is-open');
      if (opening) {
        visibleChips().forEach(function (c) { c.hidden = false; });
        chipRow.classList.add('is-open');
      } else {
        fitChips();
        opening = false;
      }
      chipToggle.setAttribute('aria-expanded', String(opening));
      chipToggle.textContent = opening ? '收起 ▴' : '展开 ▾';
    });
  }

  function haystack(el) {
    var card = bySlug[el.dataset.slug];
    if (!card) return el.textContent || '';
    var stops = (card.stops || []).map(function (s) { return s.title + ' ' + (s.text || ''); }).join(' ');
    return [card.title, card.mode, (card.tags || []).join(' '), card.seed, card.place, stops].join(' ');
  }

  function applyFilter() {
    var q = query.trim().toLowerCase();
    var shown = 0;
    cardEls.forEach(function (el) {
      var card = bySlug[el.dataset.slug] || {};
      var tagHit = activeFilter === '*' ||
        (card.tags || []).indexOf(activeFilter) !== -1 ||
        card.mode === activeFilter;
      var qHit = !q || (el._hay || (el._hay = haystack(el))).toLowerCase().indexOf(q) !== -1;
      var visible = tagHit && qHit;
      el.classList.toggle('is-hidden', !visible);
      if (visible) shown += 1;
    });
    if (emptyNote) { emptyNote.remove(); emptyNote = null; }
    if (!shown) {
      emptyNote = document.createElement('p');
      emptyNote.className = 'empty-note';
      emptyNote.textContent = '这里没有卡片。换个词，或者让 Agent 写一张新的。';
      grid.appendChild(emptyNote);
    }
  }

  if (chipRow) {
    chipRow.addEventListener('click', function (event) {
      var chip = event.target.closest('.chip');
      if (!chip) return;
      activeFilter = chip.dataset.value;
      visibleChips().forEach(function (c) { c.setAttribute('aria-pressed', String(c === chip)); });
      applyFilter();
      if (chipRow.classList.contains('is-open')) fitChips();
    });
  }

  if (searchInput) {
    var searchTimer;
    searchInput.addEventListener('input', function () {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(function () { query = searchInput.value; applyFilter(); }, 120);
    });
  }

  // Re-fold only when the available width really changes: opening the row wraps
  // it onto another line and so changes .filters' height — a ResizeObserver sees
  // that too, and folding on it made the row flash open and snap shut. So the
  // width is measured when the debounce fires, and pure height changes are
  // ignored. Late load/font events re-fold as well, but never undo a row the
  // reader just opened.
  var lastWidth = null;
  var resizeTimer;

  function filtersBox() { return chipRow.closest('.filters') || chipRow; }

  function refit() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () {
      var width = filtersBox().getBoundingClientRect().width;
      var widthChanged = lastWidth === null || Math.abs(width - lastWidth) >= 0.5;
      lastWidth = width;
      if (!widthChanged) return;
      fitChips();
    }, 120);
  }

  function fitChipsIfClosed() {
    if (!chipRow.classList.contains('is-open')) fitChips();
  }

  window.addEventListener('resize', refit);
  fitChips();
  window.addEventListener('load', fitChipsIfClosed);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitChipsIfClosed);
  if (window.ResizeObserver) new ResizeObserver(refit).observe(filtersBox());

  /* ---------- reading panel -------------------------------------------- */
  var overlay = $('#overlay');
  if (!overlay) return;

  var panelScroll = $('#panel-scroll');
  var elLine = $('#panel-line');
  var elMeta = $('#panel-meta');
  var elMode = $('#panel-mode');
  var elSeed = $('#panel-seed');
  var elQuote = $('#panel-quote');
  var elJourney = $('#panel-journey');
  var elPermalink = $('#panel-permalink');
  var elIndex = $('#panel-index');
  var current = null;
  var lastFocus = null;
  var stopsObserver = null;
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function metaHtml(card) {
    var bits = ['<span>' + card.date.replace(/-/g, '.') + '</span>'];
    if (card.place) bits.push('<span>' + escapeHtml(card.place) + '</span>');
    bits.push('<span>约 ' + card.minutes + ' 分钟</span>');
    (card.tags || []).forEach(function (t) { bits.push('<span>#' + escapeHtml(t) + '</span>'); });
    return bits.join('');
  }

  function render(card) {
    current = card;
    elMode.textContent = card.mode;
    elLine.textContent = card.title;
    elMeta.innerHTML = metaHtml(card);

    if (card.seed) {
      elSeed.hidden = false;
      elSeed.innerHTML = '<b>起点</b>' + escapeHtml(card.seed);
    } else {
      elSeed.hidden = true;
    }

    if (card.quote) {
      elQuote.hidden = false;
      elQuote.textContent = card.quote;
    } else {
      elQuote.hidden = true;
    }

    elJourney.innerHTML = (card.stops || []).map(function (stop) {
      return '<section class="stop" id="stop-' + stop.id + '">' +
        '<h3 class="stop-title">' + escapeHtml(stop.prologue ? '序' : stop.title) + '</h3>' +
        '<div class="stop-body">' + stop.html + '</div></section>';
    }).join('');

    elPermalink.setAttribute('href', DATA.base + 'c/' + card.slug + '/');
    elIndex.textContent = (card.index + 1) + ' / ' + cards.length;

    panelScroll.scrollTop = 0;
    observeStops();
    moveProgress(0);
  }

  function revealStop(el) { el.classList.add('is-in'); }

  function observeStops() {
    if (stopsObserver) stopsObserver.disconnect();
    elJourney.classList.remove('is-animated');
    var stops = $$('.stop', elJourney);
    if (reduceMotion || !('IntersectionObserver' in window)) {
      stops.forEach(revealStop);
      return;
    }

    elJourney.classList.add('is-animated');

    // Anything already inside the reading viewport shows immediately: the
    // observer cannot be trusted to fire for content restored from display:none.
    requestAnimationFrame(function () {
      var box = panelScroll.getBoundingClientRect();
      stops.forEach(function (el) {
        if (el.getBoundingClientRect().top < box.bottom - 24) revealStop(el);
      });
    });

    stopsObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          revealStop(entry.target);
          stopsObserver.unobserve(entry.target);
        }
      });
    }, { root: panelScroll, rootMargin: '0px 0px -6% 0px', threshold: 0.1 });
    stops.forEach(function (el) { stopsObserver.observe(el); });

    // Failsafe: nothing may stay invisible, whatever the browser does.
    clearTimeout(observeStops._t);
    observeStops._t = setTimeout(function () { stops.forEach(revealStop); }, 1600);
  }

  function moveProgress(ratio) {
    var bar = $('#read-progress');
    if (bar) bar.style.transform = 'scaleX(' + ratio.toFixed(4) + ')';
  }

  if (panelScroll) {
    panelScroll.addEventListener('scroll', function () {
      var max = panelScroll.scrollHeight - panelScroll.clientHeight;
      moveProgress(max > 0 ? panelScroll.scrollTop / max : 0);
    }, { passive: true });
  }

  function visibleCards() {
    return cards.filter(function (c) {
      var el = grid && grid.querySelector('.card[data-slug="' + c.slug + '"]');
      return !el || !el.classList.contains('is-hidden');
    });
  }

  function open(card, options) {
    if (!card) return;
    var opts = options || {};
    if (!overlay.hidden && current === card) return;
    if (overlay.hidden) lastFocus = document.activeElement;
    render(card);
    overlay.hidden = false;
    document.body.classList.add('is-locked');
    if (!opts.silent) {
      try { history.pushState({ slug: card.slug }, '', '#' + card.slug); } catch (e) { location.hash = card.slug; }
    }
    var dialog = $('.panel', overlay);
    if (dialog && dialog.focus) dialog.focus({ preventScroll: true });
  }

  function close(options) {
    var opts = options || {};
    overlay.hidden = true;
    document.body.classList.remove('is-locked');
    moveProgress(0);
    if (stopsObserver) stopsObserver.disconnect();
    if (lastFocus && lastFocus.focus) lastFocus.focus({ preventScroll: true });
    if (!opts.silent && location.hash) {
      try { history.pushState({}, '', location.pathname + location.search); } catch (e) { location.hash = ''; }
    }
    current = null;
  }

  function step(delta) {
    var pool = visibleCards();
    if (!pool.length) return;
    var at = current ? pool.indexOf(bySlug[current.slug]) : -1;
    open(pool[(at + delta + pool.length) % pool.length]);
  }

  function random() {
    var pool = visibleCards();
    if (!pool.length) { say('没有可打开的卡片'); return; }
    var pick = pool[Math.floor(Math.random() * pool.length)];
    if (current && pool.length > 1 && pick.slug === current.slug) pick = pool[(pool.indexOf(pick) + 1) % pool.length];
    open(pick);
  }

  if (grid) {
    grid.addEventListener('click', function (event) {
      var link = event.target.closest('a.card-link');
      if (!link) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      open(bySlug[link.dataset.slug]);
    });
  }

  $$('[data-close]', overlay).forEach(function (el) { el.addEventListener('click', function () { close(); }); });
  var closeBtn = $('#panel-close');
  if (closeBtn) closeBtn.addEventListener('click', function () { close(); });
  var prevBtn = $('#panel-prev'), nextBtn = $('#panel-next'), rndBtn = $('#panel-random');
  if (prevBtn) prevBtn.addEventListener('click', function () { step(-1); });
  if (nextBtn) nextBtn.addEventListener('click', function () { step(1); });
  if (rndBtn) rndBtn.addEventListener('click', function () { random(); });
  var copyBtn = $('#panel-copy');
  if (copyBtn) copyBtn.addEventListener('click', function () {
    if (!current) return;
    var url = new URL(DATA.base + 'c/' + current.slug + '/', location.href).href;
    copyText('「' + current.title + '」\n\n' + current.seed + '\n\n' + url, '卡片与链接已复制');
  });
  var randomTop = $('#random');
  if (randomTop) randomTop.addEventListener('click', random);

  document.addEventListener('keydown', function (event) {
    var typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
    if (event.key === 'Escape' && !overlay.hidden) { close(); return; }
    if (typing) {
      if (event.key === 'Escape' && searchInput) { searchInput.value = ''; query = ''; applyFilter(); searchInput.blur(); }
      return;
    }
    if (event.key === '/' && searchInput) { event.preventDefault(); searchInput.focus(); return; }
    if (overlay.hidden) {
      if (event.key === 'r' || event.key === 'R') random();
      return;
    }
    if (event.key === 'ArrowLeft') { event.preventDefault(); step(-1); }
    else if (event.key === 'ArrowRight') { event.preventDefault(); step(1); }
    else if (event.key === 'r' || event.key === 'R') random();
  });

  window.addEventListener('popstate', function () {
    var slug = decodeURIComponent(location.hash.replace(/^#/, ''));
    if (slug && bySlug[slug]) open(bySlug[slug], { silent: true });
    else if (!overlay.hidden) close({ silent: true });
  });

  var initial = decodeURIComponent(location.hash.replace(/^#/, ''));
  if (initial && bySlug[initial]) open(bySlug[initial], { silent: true });
})();
