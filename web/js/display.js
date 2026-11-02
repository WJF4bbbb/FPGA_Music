/* ============================================================================
 * display.js —— 实时状态显示（负责人：feature/bt-out 分支）
 *
 * 当前是一个能跑的最小版本：4 个声部 + 音色/弯音/音量/削顶。
 * 扩展方向（自己加，不要改 serial.js）：
 *   - 16 键触摸板热力图
 *   - 音符瀑布（时间轴上画每个音的起止）
 *   - 包络电平曲线
 *   - 削顶告警闪红
 *
 * 唯一的数据来源：
 *   Serial.onFrame(function (s) { ... })   约 30 Hz 调用一次
 *   s = { touchKeys, notes[4], gates, timbre, bend, gain, clip }
 * ========================================================================== */
(function () {
  'use strict';

  var NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  function noteName(midi) {
    if (!midi || midi < 12 || midi > 127) return '—';
    return NAMES[midi % 12] + (Math.floor(midi / 12) - 1);
  }

  var els = {};   // 缓存 DOM 引用，避免每帧查询

  function build() {
    var panel = document.getElementById('displayPanel');
    if (!panel) return;

    panel.innerHTML = '';

    var h2 = document.createElement('h2');
    h2.textContent = '实时状态';
    panel.appendChild(h2);

    var voices = document.createElement('div');
    voices.className = 'voices';
    for (var i = 0; i < 4; i++) {
      var card = document.createElement('div');
      card.className = 'voice';
      card.innerHTML =
        '<div class="vlabel">声部 ' + i + '</div>' +
        '<div class="vnote" data-note="' + i + '">—</div>' +
        '<div class="vstate" data-state="' + i + '">空闲</div>';
      voices.appendChild(card);
      els['note' + i] = card.querySelector('[data-note]');
      els['state' + i] = card.querySelector('[data-state]');
    }
    panel.appendChild(voices);

    var meta = document.createElement('div');
    meta.className = 'meta';
    meta.innerHTML =
      '<div><span class="mk">音色</span><span class="mv" id="mTimbre">—</span></div>' +
      '<div><span class="mk">弯音</span><span class="mv" id="mBend">—</span></div>' +
      '<div><span class="mk">音量</span><span class="mv" id="mGain">—</span></div>' +
      '<div><span class="mk">削顶</span><span class="mv" id="mClip">—</span></div>';
    panel.appendChild(meta);

    els.timbre = document.getElementById('mTimbre');
    els.bend   = document.getElementById('mBend');
    els.gain   = document.getElementById('mGain');
    els.clip   = document.getElementById('mClip');

    var css = document.createElement('style');
    css.textContent = [
      '#displayPanel .voices{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}',
      '#displayPanel .voice{background:#23272f;border:1px solid #2c313a;border-radius:10px;',
      'padding:10px 12px;min-height:96px;display:flex;flex-direction:column;gap:4px}',
      '#displayPanel .voice.active{border-color:#4a9eff}',
      '#displayPanel .vlabel{font-size:11px;color:#8b93a1}',
      '#displayPanel .vnote{font-size:20px;font-weight:500}',
      '#displayPanel .vstate{font-size:11px;color:#8b93a1;margin-top:auto}',
      '#displayPanel .voice.active .vstate{color:#3ddc97}',
      '#displayPanel .meta{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-top:12px}',
      '#displayPanel .meta>div{background:#23272f;border:1px solid #2c313a;border-radius:8px;',
      'padding:8px 10px;display:flex;flex-direction:column;gap:2px}',
      '#displayPanel .mk{font-size:11px;color:#8b93a1}',
      '#displayPanel .mv{font-size:14px}'
    ].join('');
    panel.appendChild(css);
  }

  var TIMBRE_NAME = ['正弦', '方波', '锯齿', '三角'];

  function onStatus(s) {
    for (var i = 0; i < 4; i++) {
      var active = (s.gates >> i) & 1;
      var card = els['note' + i] && els['note' + i].parentElement;
      if (card) card.classList.toggle('active', !!active);
      if (els['note' + i])  els['note' + i].textContent = noteName(s.notes[i]);
      if (els['state' + i]) els['state' + i].textContent = active ? '发声' : '空闲';
    }
    if (els.timbre) els.timbre.textContent = TIMBRE_NAME[s.timbre] || String(s.timbre);
    if (els.bend)   els.bend.textContent = (s.bend > 0 ? '+' : '') + s.bend + ' 半音';
    if (els.gain)   els.gain.textContent = Math.round(s.gain / 65535 * 100) + '%';
    if (els.clip)   els.clip.textContent = s.clip > 0 ? String(s.clip) : '无';
  }

  window.addEventListener('DOMContentLoaded', function () {
    build();
    Serial.onFrame(onStatus);
  });
})();
