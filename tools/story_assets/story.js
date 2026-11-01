// 苍之涛 剧情 / 文本浏览页: 数据在 data/*.js (STORY[key] = ...), 由 tools/story_html.py 生成
(function () {
  'use strict';
  const S = window.STORY;
  const meta = S.meta;
  const $ = (s) => document.querySelector(s);
  const main = $('#main');
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // 事件 → 分区
  const evSection = {};
  for (const sec of meta.sections) for (const ev of S[sec.key].events) evSection[ev.id] = sec.key;

  // 说话者颜色: 主角固定, 其他按名字散列
  const FIXED = { '车芸': '#b03a2e', '嬴诗': '#a0427a', '慕容诗': '#a0427a', '桓远之': '#2e6f8e', '云狐': '#b0782a', '苻殷': '#4f7a3a' };
  function color(name) {
    if (FIXED[name]) return FIXED[name];
    let h = 0;
    for (const ch of name) h = (h * 31 + ch.codePointAt(0)) % 360;
    return 'hsl(' + h + ' 38% 42%)';
  }

  // 本机偏好 (localStorage 可能不可用)
  const pref = {
    get(k, d) { try { const v = localStorage.getItem('czt-story-' + k); return v === null ? d : v === '1'; } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem('czt-story-' + k, v ? '1' : '0'); } catch (e) { /* ignore */ } },
  };
  const full = $('#full');
  const talkonly = $('#talkonly');
  full.checked = pref.get('full', false);
  talkonly.checked = pref.get('talkonly', true);
  document.body.classList.toggle('full', full.checked);
  full.onchange = () => { pref.set('full', full.checked); document.body.classList.toggle('full', full.checked); };
  talkonly.onchange = () => { pref.set('talkonly', talkonly.checked); route(); };
  $('#menu').onclick = () => document.body.classList.toggle('navopen');

  // 目录
  function buildNav() {
    let h = '';
    let group = '';
    for (const s of meta.sections) {
      if (s.group !== group) { group = s.group; h += '<h4>' + esc(group) + '</h4>'; }
      h += '<a href="#s=' + s.key + '" data-k="' + s.key + '">' + esc(s.title) + '<small>' + s.talk + ' 个有台词的事件</small></a>';
    }
    h += '<h4>资料</h4>';
    h += '<a href="#missions" data-k="missions">任务与史料<small>' + S.missions.length + ' 条</small></a>';
    h += '<a href="#battles" data-k="battles">战斗对白<small>' + S.battles.filter((b) => b.lines.length).length + ' 场有对白</small></a>';
    h += '<a href="#codex" data-k="codex">图鉴<small>人物 · 怪物 · 道具 · 装备 · 法术</small></a>';
    $('#nav').innerHTML = h;
  }

  // 一行
  function line(ln) {
    const pad = 'style="margin-left:' + Math.min(ln[0], 12) * 1.1 + 'em"';
    switch (ln[1]) {
      case 't':
        return '<div class="ln t" ' + pad + '><span class="who" style="color:' + color(ln[2]) + '">' + esc(ln[2]) +
          '</span><span class="say">' + esc(ln[3]) + '</span></div>';
      case 'n': return '<div class="ln n" ' + pad + '>' + esc(ln[2]) + '</div>';
      case 'p':
        return '<div class="ln t p" ' + pad + '><span class="who" style="color:' + color(ln[2]) + '">' + esc(ln[2]) +
          '</span><span class="say">' + esc(ln[3]) + '<span class="opts">【选项】' + esc(ln[4]) + '</span></span></div>';
      case 'c': return '<div class="ln c" ' + pad + '>' + esc(ln[2]) + '</div>';
      case 'i': return '<div class="ln i" ' + pad + '>若 ' + esc(ln[2]) + '</div>';
      case 'e': return '<div class="ln e" ' + pad + '>否则</div>';
      case 'r': return '<div class="ln r" ' + pad + '>随机：' + esc(ln[2]) + '</div>';
      case 'f': return '<div class="ln f" ' + pad + '><b>任务' + esc(ln[2]) + '</b>' + esc(ln[3]) + '</div>';
      case 'x': {
        let v = esc(ln[3]);
        if (ln[2] === '战斗' && ln[4] != null) v = '<a href="#battles&b=' + ln[4] + '">' + v + '</a>';
        if (ln[2] === '转入事件' && evSection[ln[4]]) v = '<a href="#s=' + evSection[ln[4]] + '&e=' + ln[4] + '">' + v + '</a>';
        return '<div class="ln x" ' + pad + '><b>' + esc(ln[2]) + '</b>' + v + '</div>';
      }
      default: return '<div class="ln k" ' + pad + '>' + esc(ln[2] || '') + '</div>';
    }
  }

  function firstLine(ev) {
    for (const ln of ev.lines) {
      if (ln[1] === 't' || ln[1] === 'p') return ln[2] + '：' + ln[3];
      if (ln[1] === 'n') return ln[2];
    }
    return '';
  }

  function evCard(ev, open) {
    const chips = ev.acc.map((m) => '<span class="chip acc">' + esc(m) + '</span>').join('') +
      ev.comp.map((m) => '<span class="chip comp">' + esc(m) + '</span>').join('');
    const body = ev.lines.length ? ev.lines.map(line).join('') : '<div class="empty">（空脚本）</div>';
    return '<details class="ev" id="ev-' + ev.id + '"' + (open ? ' open' : '') + '><summary>' +
      '<span class="eid">#' + ev.id + '</span>' +
      '<span class="where">' + esc(ev.map || '未知地点') + '</span>' +
      (ev.trig ? '<span class="trig">' + esc(ev.trig) + '</span>' : '') + chips +
      '<span class="first">' + esc(firstLine(ev)) + '</span></summary>' +
      '<div class="body">' + body + '<div class="src">脚本：extracted/scripts/pseudo/' + esc(ev.src) + '</div></div></details>';
  }

  function showSection(key, evId) {
    const sec = S[key];
    let evs = sec.events;
    if (talkonly.checked) evs = evs.filter((e) => e.talk || e.id === evId);
    let h = '<h1 class="sec">' + esc(sec.title) + '</h1><p class="sub">' + esc(sec.sub) + '　·　' + evs.length + ' 个事件</p>' +
      '<div class="bar"><button data-act="open">全部展开</button><button data-act="close">全部收起</button>' +
      '<span>事件按编号排列（编号大致就是剧情先后）；灰色小字是场景、战斗、音乐、任务等提示，勾选「显示完整指令」可看原始伪代码。</span></div>';
    let map = null;
    for (const ev of evs) {
      if (sec.by_map && ev.map !== map) { map = ev.map; h += '<h2 class="map">' + esc(map || '未知地点') + '</h2>'; }
      h += evCard(ev, !sec.by_map && ev.talk > 0 && evs.length < 60);
    }
    main.innerHTML = h;
    main.querySelectorAll('.bar button').forEach((b) => {
      b.onclick = () => main.querySelectorAll('details.ev').forEach((d) => { d.open = b.dataset.act === 'open'; });
    });
    if (evId) {
      const el = document.getElementById('ev-' + evId);
      if (el) { el.open = true; requestAnimationFrame(() => el.scrollIntoView({ block: 'start' })); }
    } else window.scrollTo(0, 0);
  }

  function evLinks(ids) {
    return ids.map((i) => evSection[i] ? '<a href="#s=' + evSection[i] + '&e=' + i + '">#' + i + '</a>' : '#' + i).join(' ');
  }

  function showMissions() {
    const kinds = ['主线', '支线', '其他'];
    let h = '<h1 class="sec">任务与史料</h1><p class="sub">任务界面的文本；「接 / 完成」为设置对应任务旗标的事件，可点击跳转。</p>';
    for (const k of kinds) {
      const rows = S.missions.filter((m) => m.kind === k);
      if (k === '其他') {
        h += '<h2 class="map">史料与说明（' + rows.length + '）</h2>';
        for (const m of rows) h += '<div class="lore" id="m-' + m.id + '">' + esc(m.text) + '</div>';
        continue;
      }
      h += '<h2 class="map">' + k + '任务（' + rows.length + '）</h2><table class="ms"><tr><th>编号</th><th>任务</th><th>接取事件</th><th>完成事件</th></tr>';
      for (const m of rows) {
        h += '<tr id="m-' + m.id + '"><td class="k">' + m.id + '</td><td>' + esc(m.text.replace(/^[★☆]/, '')) + '</td><td>' +
          evLinks(m.acc) + '</td><td>' + evLinks(m.comp) + '</td></tr>';
      }
      h += '</table>';
    }
    main.innerHTML = h;
    window.scrollTo(0, 0);
  }

  function showBattles(bid) {
    const list = S.battles.filter((b) => b.lines.length || b.id === bid);
    let h = '<h1 class="sec">战斗对白</h1><p class="sub">FIGTALK 战斗剧情脚本里的对白与系统提示，按战场编号排列（' + list.length + ' 场有对白）。</p>';
    for (const b of list) {
      const body = b.lines.length ? b.lines.map((l) => l[0]
        ? '<div class="ln t"><span class="who" style="color:' + color(l[0]) + '">' + esc(l[0]) + '</span><span class="say">' + esc(l[1]) + '</span></div>'
        : '<div class="ln n">' + esc(l[1]) + '</div>').join('') : '<div class="empty">（无对白）</div>';
      h += '<details class="ev" id="b-' + b.id + '"' + (b.id === bid ? ' open' : '') + '><summary><span class="eid">战场 ' + b.id +
        '</span><span class="where">' + esc(b.name) + '</span>' + (b.events.length ? '<span class="trig">由事件 ' + evLinks(b.events) + ' 触发</span>' : '') +
        '</summary><div class="body">' + body + '</div></details>';
    }
    main.innerHTML = h;
    const el = bid != null && document.getElementById('b-' + bid);
    if (el) requestAnimationFrame(() => el.scrollIntoView({ block: 'start' })); else window.scrollTo(0, 0);
  }

  function showCodex() {
    let h = '<h1 class="sec">图鉴</h1><p class="sub">ObjDATA 里的名称、描述与附注。</p>';
    for (const g of S.codex) {
      h += '<h2 class="map">' + esc(g.title) + '（' + g.rows.length + '）</h2><div class="cx">';
      for (const r of g.rows) {
        h += '<div class="card"><h3>' + esc(r.name) + '</h3>' + (r.extra ? '<div class="ex">' + esc(r.extra) + '</div>' : '') +
          (r.desc ? '<p>' + esc(r.desc) + '</p>' : '') + (r.note ? '<p class="note">' + esc(r.note) + '</p>' : '') + '</div>';
      }
      h += '</div>';
    }
    main.innerHTML = h;
    window.scrollTo(0, 0);
  }

  // 搜索: 台词 / 旁白 / 说话者 / 任务 / 图鉴 / 战斗对白
  function showSearch(q) {
    const hl = (s) => esc(s).split(esc(q)).join('<span class="hl">' + esc(q) + '</span>');
    const res = [];
    const LIMIT = 400;
    outer:
    for (const sec of meta.sections) {
      for (const ev of S[sec.key].events) {
        for (const ln of ev.lines) {
          let txt = null;
          if (ln[1] === 't' || ln[1] === 'p') txt = ln[2] + '：' + ln[3];
          else if (ln[1] === 'n' || ln[1] === 'c') txt = ln[2];
          if (txt && txt.includes(q)) {
            res.push('<div class="res"><a href="#s=' + sec.key + '&e=' + ev.id + '"><div class="txt">' + hl(txt) + '</div><div class="ctx">' +
              esc(sec.title) + ' · #' + ev.id + ' ' + esc(ev.map || '') + '</div></a></div>');
            if (res.length >= LIMIT) break outer;
          }
        }
      }
    }
    for (const m of S.missions) if (m.text.includes(q)) res.push('<div class="res"><a href="#missions"><div class="txt">' + hl(m.text.slice(0, 160)) + '</div><div class="ctx">任务 / 史料 ' + m.id + '</div></a></div>');
    for (const b of S.battles) for (const l of b.lines) if ((l[0] + l[1]).includes(q)) res.push('<div class="res"><a href="#battles&b=' + b.id + '"><div class="txt">' + hl((l[0] ? l[0] + '：' : '') + l[1]) + '</div><div class="ctx">战斗 ' + b.id + ' ' + esc(b.name) + '</div></a></div>');
    for (const g of S.codex) for (const r of g.rows) if ((r.name + r.desc + r.note).includes(q)) res.push('<div class="res"><a href="#codex"><div class="txt">' + hl(r.name + '：' + r.desc) + '</div><div class="ctx">图鉴 · ' + esc(g.title) + '</div></a></div>');
    main.innerHTML = '<h1 class="sec">搜索「' + esc(q) + '」</h1><p class="sub">' + (res.length >= LIMIT ? '前 ' + LIMIT + ' 条台词结果' : res.length + ' 条结果') + '</p>' +
      (res.join('') || '<p class="empty">没有找到。</p>');
    window.scrollTo(0, 0);
  }

  function route() {
    const h = decodeURIComponent(location.hash.slice(1));
    const p = {};
    h.split('&').forEach((kv) => { const i = kv.indexOf('='); if (kv) p[i < 0 ? kv : kv.slice(0, i)] = i < 0 ? '' : kv.slice(i + 1); });
    let on = 'ch01';
    if (p.q !== undefined) { $('#q').value = p.q; showSearch(p.q); on = ''; }
    else if ('missions' in p) { showMissions(); on = 'missions'; }
    else if ('battles' in p) { showBattles(p.b ? +p.b : null); on = 'battles'; }
    else if ('codex' in p) { showCodex(); on = 'codex'; }
    else { on = p.s && S[p.s] ? p.s : 'ch01'; showSection(on, p.e ? +p.e : null); }
    document.querySelectorAll('nav a').forEach((a) => a.classList.toggle('on', a.dataset.k === on));
    document.body.classList.remove('navopen');
  }

  let timer = 0;
  $('#q').addEventListener('input', (e) => {
    clearTimeout(timer);
    const v = e.target.value.trim();
    timer = setTimeout(() => { if (v.length) location.hash = 'q=' + encodeURIComponent(v); }, 350);
  });

  buildNav();
  window.addEventListener('hashchange', route);
  route();
})();
