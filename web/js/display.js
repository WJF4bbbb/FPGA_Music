/* ============================================================================
 * display.js —— 实时状态显示（负责人：feature/bt-out 分支）
 *
 * 数据来源只有一个：
 *   Serial.onFrame(function (s) { ... })   约 30 Hz 调用一次
 *   s = { touchKeys, notes[4], gates, timbre, bend, gain, clip }
 *
 * 布局：
 *   ① 16 键触摸板热力图（TP0~7 音符，TP8 音色，TP9/10 音量，TP11/12 弯音）
 *   ② 4 个声部卡片（音名 + 发声/空闲）
 *   ③ 底部信息条（音色、弯音、音量、削顶、帧计数）
 *
 * 扩展方向：
 *   - 音符瀑布（记录历史，时间轴画矩形）
 *   - 包络电平曲线（需要板子额外输出 level，当前协议没有）
 *   - 削顶告警闪红
 * ========================================================================== */
(function () {
  'use strict';

  var NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  function noteName(midi) {
    if (!midi || midi < 12 || midi > 127) return '—';
    return NAMES[midi % 12] + (Math.floor(midi / 12) - 1);
  }

  // TP 编号 -> 功能说明
  var TP_ROLE = [
    'C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5',
    '音色', '音量+', '音量-', '弯音+', '弯音-', '预留', '预留', '预留'
  ];

  var els = {};
  var frameCount = 0;
  var lastFrameTime = 0;
  var rateHz = 0;

  function build() {
    var panel = document.getElementById('displayPanel');
    if (!panel) return;

    panel.innerHTML = '';

    var h2 = document.createElement('h2');
    h2.textContent = '实时状态';
    panel.appendChild(h2);

    // ---- ① 16 键热力图 ----
    var padTitle = document.createElement('div');
    padTitle.className = 'sec-title';
    padTitle.textContent = '触摸板 16 键';
    panel.appendChild(padTitle);

    var pad = document.createElement('div');
    pad.className = 'pad';
    for (var i = 0; i < 16; i++) {
      var cell = document.createElement('div');
      cell.className = 'pad-cell';
      cell.innerHTML = '<span class="pn">TP' + i + '</span>' +
                       '<span class="pr">' + TP_ROLE[i] + '</span>';
      pad.appendChild(cell);
      els['pad' + i] = cell;
    }
    panel.appendChild(pad);

    // ---- ② 四个声部 ----
    var vTitle = document.createElement('div');
    vTitle.className = 'sec-title';
    vTitle.textContent = '声部分配';
    panel.appendChild(vTitle);

    var voices = document.createElement('div');
    voices.className = 'voices';
    for (var v = 0; v < 4; v++) {
      var card = document.createElement('div');
      card.className = 'voice';
      card.innerHTML =
        '<div class="vlabel">声部 ' + v + '</div>' +
        '<div class="vnote">—</div>' +
        '<div class="vstate">空闲</div>';
      voices.appendChild(card);
      els['vcard' + v]  = card;
      els['vnote' + v]  = card.querySelector('.vnote');
      els['vstate' + v] = card.querySelector('.vstate');
    }
    panel.appendChild(voices);

    // ---- ③ 底部信息条 ----
    var meta = document.createElement('div');
    meta.className = 'meta';
    meta.innerHTML =
      '<div><span class="mk">音色</span><span class="mv" id="mTimbre">—</span></div>' +
      '<div><span class="mk">弯音</span><span class="mv" id="mBend">—</span></div>' +
      '<div><span class="mk">音量</span><span class="mv" id="mGain">—</span></div>' +
      '<div><span class="mk">削顶</span><span class="mv" id="mClip">—</span></div>' +
      '<div><span class="mk">帧率</span><span class="mv" id="mRate">—</span></div>';
    panel.appendChild(meta);

    els.timbre = document.getElementById('mTimbre');
    els.bend   = document.getElementById('mBend');
    els.gain   = document.getElementById('mGain');
    els.clip   = document.getElementById('mClip');
    els.rate   = document.getElementById('mRate');

    var css = document.createElement('style');
    css.textContent = [
      '#displayPanel .sec-title{font-size:11px;color:#8b93a1;margin:14px 0 8px}',
      '#displayPanel .sec-title:first-of-type{margin-top:0}',

      '#displayPanel .pad{display:grid;grid-template-columns:repeat(4,1fr);gap:6px}',
      '#displayPanel .pad-cell{background:#23272f;border:1px solid #2c313a;border-radius:8px;',
      'padding:8px 6px;display:flex;flex-direction:column;align-items:center;gap:2px;',
      'transition:none}',
      '#displayPanel .pad-cell.on{background:#4a9eff;border-color:#4a9eff}',
      '#displayPanel .pad-cell.on .pn,#displayPanel .pad-cell.on .pr{color:#fff}',
      '#displayPanel .pn{font-size:11px;color:#e8eaed}',
      '#displayPanel .pr{font-size:10px;color:#8b93a1}',

      '#displayPanel .voices{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}',
      '#displayPanel .voice{background:#23272f;border:1px solid #2c313a;border-radius:10px;',
      'padding:10px 12px;min-height:84px;display:flex;flex-direction:column;gap:4px}',
      '#displayPanel .voice.active{border-color:#4a9eff}',
      '#displayPanel .vlabel{font-size:11px;color:#8b93a1}',
      '#displayPanel .vnote{font-size:19px;font-weight:500}',
      '#displayPanel .vstate{font-size:11px;color:#8b93a1;margin-top:auto}',
      '#displayPanel .voice.active .vstate{color:#3ddc97}',

      '#displayPanel .meta{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin-top:14px}',
      '#displayPanel .meta>div{background:#23272f;border:1px solid #2c313a;border-radius:8px;',
      'padding:8px 10px;display:flex;flex-direction:column;gap:2px}',
      '#displayPanel .mk{font-size:11px;color:#8b93a1}',
      '#displayPanel .mv{font-size:14px}'
    ].join('');
    panel.appendChild(css);
  }

  var TIMBRE_NAME = ['正弦', '方波', '锯齿', '三角'];

  function onStatus(s) {
    // ① 热力图
    for (var i = 0; i < 16; i++) {
      var c = els['pad' + i];
      if (c) c.classList.toggle('on', !!(s.touchKeys & (1 << i)));
    }

    // ② 声部
    for (var v = 0; v < 4; v++) {
      var active = (s.gates >> v) & 1;
      if (els['vcard' + v])  els['vcard' + v].classList.toggle('active', !!active);
      if (els['vnote' + v])  els['vnote' + v].textContent = noteName(s.notes[v]);
      if (els['vstate' + v]) els['vstate' + v].textContent = active ? '发声' : '空闲';
    }

    // ③ 信息条
    if (els.timbre) els.timbre.textContent = TIMBRE_NAME[s.timbre] || String(s.timbre);
    if (els.bend)   els.bend.textContent = (s.bend > 0 ? '+' : '') + s.bend + ' 半音';
    if (els.gain)   els.gain.textContent = Math.round(s.gain / 65535 * 100) + '%';
    if (els.clip)   els.clip.textContent = s.clip > 0 ? String(s.clip) : '无';

    // 帧率统计（每秒算一次）
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

  // 断线时把界面清空，避免显示过期数据
  function clearAll() {
    for (var i = 0; i < 16; i++) if (els['pad' + i]) els['pad' + i].classList.remove('on');
    for (var v = 0; v < 4; v++) {
      if (els['vcard' + v])  els['vcard' + v].classList.remove('active');
      if (els['vnote' + v])  els['vnote' + v].textContent = '—';
      if (els['vstate' + v]) els['vstate' + v].textContent = '空闲';
    }
    if (els.rate) els.rate.textContent = '—';
    lastFrameTime = 0;
    frameCount = 0;
  }

  // ---- 演示模式：不接板子、不连蓝牙，也能调界面 ----
  // 用法：在网址后面加 ?demo=1
  //   file:///.../web/index.html?demo=1
  //   http://localhost:8000/web/?demo=1
  // 数据是假造的，只为看排版和动画，不代表真实板子状态。
  function startDemo() {
    var t = 0;
    setInterval(function () {
      t++;
      var key = Math.floor(t / 18) % 8;           // 每约 0.6 秒换一个键
      onStatus({
        touchKeys: (1 << key) | (1 << 8),         // 顺便点亮"音色"键
        notes: [60 + key, 64 + key, 67 + key, 0],
        gates: 7,                                  // 声部 0/1/2 发声
        timbre: Math.floor(t / 60) % 4,
        bend: (Math.floor(t / 40) % 5) - 2,
        gain: 32768 + Math.round(20000 * Math.sin(t / 30)),
        clip: (t % 200 < 6) ? Math.floor(t / 200) + 1 : 0
      });
    }, 33);
  }

  window.addEventListener('DOMContentLoaded', function () {
    build();
    var demo = /[?&]demo=1/.test(location.search);
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
