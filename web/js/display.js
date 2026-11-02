/* ============================================================================
 * display.js —— 实时状态显示（负责人：feature/bt-out 分支）
 *
 * 数据来源只有一个：
 *   Serial.onFrame(function (s) { ... })   约 30 Hz 调用一次
 *   s = { touchKeys, notes[4], gates, timbre, bend, gain, clip }
 *
 * 布局：
 *   ① 标题行 + 数据新鲜度指示点（收到帧时呼吸，断流 400ms 变灰）
 *   ② 16 键触摸板热力图（TP0~7 音符，TP8 音色，TP9/10 音量，TP11/12 弯音）
 *   ③ 4 个声部卡片（音名 + 简谱 + 实际频率）
 *   ④ 音符瀑布（最近 4 秒，canvas 绘制）
 *   ⑤ 底部信息条（音色、弯音、音量、削顶、帧率）
 *
 * 演示模式：window.__DEMO__ = true 或网址带 ?demo=1
 *   不接板子、不连蓝牙也能调界面。见 web/demo.html。
 *
 * 约束：所有 DOM 和 CSS 都在本文件里生成，选择器一律以 #displayPanel 开头，
 *       不碰 index.html、不碰 serial.js、不碰队友的 input.js。
 * ========================================================================== */
(function () {
  'use strict';

  var NAMES  = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  var JIANPU = ['1', '#1', '2', '#2', '3', '4', '#4', '5', '#5', '6', '#6', '7'];
  var TIMBRE = ['正弦', '方波', '锯齿', '三角'];

  // TP 编号 -> 功能说明
  var TP_ROLE = [
    'C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5',
    '音色', '音量+', '音量-', '弯音+', '弯音-', '预留', '预留', '预留'
  ];

  // 瀑布的 8 个音，与 TP0~TP7 一一对应
  var SCALE = [60, 62, 64, 65, 67, 69, 71, 72];
  var HIST_MAX = 120;          // 30 Hz × 4 秒

  function noteName(m) {
    if (!m || m < 12 || m > 127) return '—';
    return NAMES[m % 12] + (Math.floor(m / 12) - 1);
  }
  function jianpu(m) {
    if (!m || m < 12 || m > 127) return '';
    return JIANPU[m % 12];
  }
  function freqStr(m) {
    if (!m || m < 12 || m > 127) return '—';
    var f = 440 * Math.pow(2, (m - 69) / 12);
    return f >= 1000 ? (f / 1000).toFixed(2) + ' kHz' : f.toFixed(1) + ' Hz';
  }
  function scaleIndex(m) {
    for (var i = 0; i < SCALE.length; i++) if (SCALE[i] === m) return i;
    return -1;
  }

  var els = {};
  var history = [];
  var frameCount = 0, lastFrameTime = 0, rateHz = 0;
  var lastFrameAt = 0, lastClip = 0, clipUntil = 0;

  // ---------------------------------------------------------------- 建 DOM
  function build() {
    var panel = document.getElementById('displayPanel');
    if (!panel) return;

    panel.innerHTML = '';

    // ---- ① 标题行 ----
    var head = document.createElement('div');
    head.className = 'd-head';
    head.innerHTML = '<h2>实时状态</h2><i class="d-dot" title="数据新鲜度"></i>';
    panel.appendChild(head);
    els.dot = head.querySelector('.d-dot');

    // ---- ② 16 键热力图 ----
    var t1 = document.createElement('div');
    t1.className = 'd-title';
    t1.textContent = '触摸板 16 键';
    panel.appendChild(t1);

    var pad = document.createElement('div');
    pad.className = 'pad';
    for (var i = 0; i < 16; i++) {
      var c = document.createElement('div');
      c.className = 'pad-cell' + (i < 8 ? ' note' : '');
      c.innerHTML = '<span class="pn">TP' + i + '</span>' +
                    '<span class="pr">' + TP_ROLE[i] + '</span>';
      pad.appendChild(c);
      els['pad' + i] = c;
    }
    panel.appendChild(pad);

    // ---- ③ 四个声部 ----
    var t2 = document.createElement('div');
    t2.className = 'd-title';
    t2.textContent = '声部分配';
    panel.appendChild(t2);

    var vs = document.createElement('div');
    vs.className = 'voices';
    for (var v = 0; v < 4; v++) {
      var card = document.createElement('div');
      card.className = 'voice';
      card.innerHTML =
        '<div class="vlabel">声部 ' + v + '</div>' +
        '<div class="vrow"><span class="vnote">—</span><span class="vjp"></span></div>' +
        '<div class="vfreq">—</div>' +
        '<div class="vstate">空闲</div>';
      vs.appendChild(card);
      els['vc' + v]    = card;
      els['vnote' + v] = card.querySelector('.vnote');
      els['vjp' + v]   = card.querySelector('.vjp');
      els['vfreq' + v] = card.querySelector('.vfreq');
      els['vst' + v]   = card.querySelector('.vstate');
    }
    panel.appendChild(vs);

    // ---- ④ 音符瀑布 ----
    var t3 = document.createElement('div');
    t3.className = 'd-title';
    t3.innerHTML = '<span>音符瀑布</span><span class="d-hint">最近 4 秒</span>';
    panel.appendChild(t3);

    var wrap = document.createElement('div');
    wrap.className = 'wf';
    var cv = document.createElement('canvas');
    cv.className = 'wf-cv';
    wrap.appendChild(cv);
    panel.appendChild(wrap);
    els.canvas = cv;
    els.ctx = cv.getContext('2d');

    // ---- ⑤ 信息条 ----
    var meta = document.createElement('div');
    meta.className = 'meta';
    meta.innerHTML =
      '<div><span class="mk">音色</span><span class="mv" data-k="timbre">—</span></div>' +
      '<div><span class="mk">弯音</span><span class="mv" data-k="bend">—</span></div>' +
      '<div><span class="mk">音量</span><span class="mv" data-k="gain">—</span></div>' +
      '<div><span class="mk">削顶</span><span class="mv" data-k="clip">—</span></div>' +
      '<div><span class="mk">帧率</span><span class="mv" data-k="rate">—</span></div>';
    panel.appendChild(meta);
    els.timbre = meta.querySelector('[data-k="timbre"]');
    els.bend   = meta.querySelector('[data-k="bend"]');
    els.gain   = meta.querySelector('[data-k="gain"]');
    els.clip   = meta.querySelector('[data-k="clip"]');
    els.rate   = meta.querySelector('[data-k="rate"]');

    // ---- CSS（全部以 #displayPanel 开头，不污染队友的面板）----
    var css = document.createElement('style');
    css.textContent = [
      '#displayPanel{transition:box-shadow .15s,border-color .15s}',
      '#displayPanel.clip{border-color:#ff5c5c;box-shadow:inset 0 0 0 1px rgba(255,92,92,.5)}',

      '#displayPanel .d-head{display:flex;align-items:center;justify-content:space-between;margin:0 0 12px}',
      '#displayPanel .d-head h2{margin:0;font-size:13px;font-weight:500;color:#8b93a1;letter-spacing:.04em}',
      '#displayPanel .d-dot{width:8px;height:8px;border-radius:50%;background:#3ddc97;',
      'animation:dPulse 1.1s ease-in-out infinite}',
      '#displayPanel .d-dot.stale{background:#5f5e5a;animation:none}',
      '@keyframes dPulse{0%,100%{opacity:1}50%{opacity:.3}}',

      '#displayPanel .d-title{display:flex;justify-content:space-between;align-items:baseline;',
      'font-size:11px;color:#8b93a1;margin:16px 0 8px}',
      '#displayPanel .d-hint{font-size:10px;color:#5f6b7a}',

      '#displayPanel .pad{display:grid;grid-template-columns:repeat(4,1fr);gap:6px}',
      '#displayPanel .pad-cell{background:#23272f;border:1px solid #2c313a;border-radius:8px;',
      'padding:8px 6px;display:flex;flex-direction:column;align-items:center;gap:2px;',
      'transition:transform .08s,background .08s,border-color .08s}',
      '#displayPanel .pad-cell.note{border-color:#33405a}',
      '#displayPanel .pad-cell.on{background:#4a9eff;border-color:#7bbcff;transform:scale(1.06)}',
      '#displayPanel .pad-cell.on .pn,#displayPanel .pad-cell.on .pr{color:#fff}',
      '#displayPanel .pn{font-size:11px;color:#e8eaed}',
      '#displayPanel .pr{font-size:10px;color:#8b93a1}',

      '#displayPanel .voices{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}',
      '#displayPanel .voice{background:#23272f;border:1px solid #2c313a;border-left:3px solid #2c313a;',
      'border-radius:10px;padding:10px 12px;display:flex;flex-direction:column;gap:2px;',
      'transition:border-color .12s,background .12s}',
      '#displayPanel .voice.on{border-left-color:#4a9eff;background:#252b36}',
      '#displayPanel .vlabel{font-size:11px;color:#8b93a1}',
      '#displayPanel .vrow{display:flex;align-items:baseline;gap:6px}',
      '#displayPanel .vnote{font-size:20px;font-weight:500;line-height:1.25}',
      '#displayPanel .vjp{font-size:12px;color:#4a9eff}',
      '#displayPanel .vfreq{font-size:10px;color:#8b93a1;font-variant-numeric:tabular-nums}',
      '#displayPanel .vstate{font-size:11px;color:#8b93a1}',
      '#displayPanel .voice.on .vstate{color:#3ddc97}',

      '#displayPanel .wf{background:#1a1d23;border:1px solid #2c313a;border-radius:10px;padding:6px}',
      '#displayPanel .wf-cv{width:100%;display:block;border-radius:6px}',

      '#displayPanel .meta{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin-top:16px}',
      '#displayPanel .meta>div{background:#23272f;border:1px solid #2c313a;border-radius:8px;',
      'padding:8px 10px;display:flex;flex-direction:column;gap:2px}',
      '#displayPanel .mk{font-size:11px;color:#8b93a1}',
      '#displayPanel .mv{font-size:14px;font-variant-numeric:tabular-nums}',
      '#displayPanel .mv.warn{color:#ff5c5c}'
    ].join('');
    panel.appendChild(css);

    window.addEventListener('resize', drawWaterfall);

    // 数据新鲜度：断流 400 ms 就把指示点变灰
    setInterval(function () {
      if (els.dot) els.dot.classList.toggle('stale', performance.now() - lastFrameAt > 400);
    }, 250);
  }

  // ------------------------------------------------------------ 画瀑布
  function drawWaterfall() {
    var cv = els.canvas, ctx = els.ctx;
    if (!cv || !ctx) return;

    var dpr = window.devicePixelRatio || 1;
    var cssW = cv.clientWidth || 600;
    var cssH = 116;
    var w = Math.round(cssW * dpr), h = Math.round(cssH * dpr);
    if (cv.width !== w || cv.height !== h) {
      cv.width = w;
      cv.height = h;
      cv.style.height = cssH + 'px';
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssW, cssH);

    var rows = SCALE.length;
    var pad = 3;
    var rowH = (cssH - pad * 2) / rows;
    var labelW = 30;
    var plotW = cssW - labelW;

    ctx.font = '10px system-ui, sans-serif';
    ctx.textBaseline = 'middle';

    // 行底纹 + 左侧音名
    for (var r = 0; r < rows; r++) {
      var y = pad + r * rowH;
      ctx.fillStyle = (r % 2) ? 'rgba(255,255,255,0.025)' : 'rgba(255,255,255,0.05)';
      ctx.fillRect(labelW, y, plotW, rowH - 1);
      ctx.fillStyle = '#8b93a1';
      ctx.fillText(noteName(SCALE[r]), 4, y + rowH / 2);
    }

    // 历史柱：越靠右越新
    var slot = plotW / HIST_MAX;
    var off = HIST_MAX - history.length;
    for (var i = 0; i < history.length; i++) {
      var hh = history[i];
      var x = labelW + (off + i) * slot;
      for (var v = 0; v < 4; v++) {
        if (!((hh.gates >> v) & 1)) continue;
        var idx = scaleIndex(hh.notes[v]);
        if (idx < 0) continue;
        ctx.fillStyle = '#4a9eff';
        ctx.fillRect(x, pad + idx * rowH + 1, Math.max(slot, 1), rowH - 3);
      }
    }
  }

  // ------------------------------------------------------------ 每帧更新
  function onStatus(s) {
    lastFrameAt = performance.now();

    // ② 热力图
    for (var i = 0; i < 16; i++) {
      var c = els['pad' + i];
      if (c) c.classList.toggle('on', !!(s.touchKeys & (1 << i)));
    }

    // ③ 声部
    for (var v = 0; v < 4; v++) {
      var on = (s.gates >> v) & 1;
      if (els['vc' + v])    els['vc' + v].classList.toggle('on', !!on);
      if (els['vnote' + v]) els['vnote' + v].textContent = noteName(s.notes[v]);
      if (els['vjp' + v])   els['vjp' + v].textContent = on ? jianpu(s.notes[v]) : '';
      if (els['vfreq' + v]) els['vfreq' + v].textContent = on ? freqStr(s.notes[v]) : '—';
      if (els['vst' + v])   els['vst' + v].textContent = on ? '发声' : '空闲';
    }

    // ⑤ 信息条
    if (els.timbre) els.timbre.textContent = TIMBRE[s.timbre] || String(s.timbre);
    if (els.bend)   els.bend.textContent = (s.bend > 0 ? '+' : '') + s.bend;
    if (els.gain)   els.gain.textContent = Math.round(s.gain / 65535 * 100) + '%';
    if (els.clip) {
      els.clip.textContent = s.clip > 0 ? String(s.clip) : '无';
      els.clip.classList.toggle('warn', s.clip > 0);
    }

    // 削顶：计数增长时整块面板闪红 300 ms
    if (s.clip > lastClip) clipUntil = performance.now() + 300;
    lastClip = s.clip;
    var panel = document.getElementById('displayPanel');
    if (panel) panel.classList.toggle('clip', performance.now() < clipUntil);

    // ④ 历史
    history.push({ gates: s.gates, notes: [s.notes[0], s.notes[1], s.notes[2], s.notes[3]] });
    if (history.length > HIST_MAX) history.shift();
    drawWaterfall();

    // 帧率
    frameCount++;
    var now = performance.now();
    if (!lastFrameTime) lastFrameTime = now;
    if (now - lastFrameTime >= 1000) {
      rateHz = Math.round(frameCount * 1000 / (now - lastFrameTime));
      frameCount = 0;
      lastFrameTime = now;
      if (els.rate) els.rate.textContent = rateHz + ' Hz';
    }
  }

  // 断线时清空，避免显示过期数据
  function clearAll() {
    history.length = 0;
    for (var i = 0; i < 16; i++) if (els['pad' + i]) els['pad' + i].classList.remove('on');
    for (var v = 0; v < 4; v++) {
      if (els['vc' + v])    els['vc' + v].classList.remove('on');
      if (els['vnote' + v]) els['vnote' + v].textContent = '—';
      if (els['vjp' + v])   els['vjp' + v].textContent = '';
      if (els['vfreq' + v]) els['vfreq' + v].textContent = '—';
      if (els['vst' + v])   els['vst' + v].textContent = '空闲';
    }
    if (els.rate) els.rate.textContent = '—';
    lastFrameTime = 0;
    frameCount = 0;
    drawWaterfall();
  }

  // ------------------------------------------------------------ 演示模式
  function startDemo() {
    var t = 0;
    setInterval(function () {
      t++;
      var step = Math.floor(t / 18) % 8;
      var notes = [SCALE[step], 0, 0, 0];
      var gates = 1;
      // 每两秒叠一个三和弦，让瀑布有层次
      if (t % 60 < 22) {
        notes[1] = SCALE[(step + 2) % 8];
        notes[2] = SCALE[(step + 4) % 8];
        gates = 7;
      }
      onStatus({
        touchKeys: (1 << step) | ((t % 120 < 60) ? (1 << 8) : (1 << 11)),
        notes: notes,
        gates: gates,
        timbre: Math.floor(t / 60) % 4,
        bend: (Math.floor(t / 40) % 5) - 2,
        gain: 32768 + Math.round(20000 * Math.sin(t / 30)),
        clip: (t % 240 < 4) ? Math.floor(t / 240) + 1 : 0
      });
    }, 33);
  }

  // ------------------------------------------------------------ 启动
  window.addEventListener('DOMContentLoaded', function () {
    build();

    var demo = window.__DEMO__ === true || /[?&]demo=1/.test(location.search);
    if (demo) {
      startDemo();
      var h = document.querySelector('#displayPanel h2');
      if (h) h.textContent = '实时状态（演示数据 · 非真实板子）';
    } else {
      Serial.onFrame(onStatus);
    }

    window.addEventListener('beforeunload', clearAll);
  });
})();
