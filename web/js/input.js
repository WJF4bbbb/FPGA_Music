/* ============================================================================
 * input.js —— 虚拟输入（负责人：feature/bt-in 分支）
 *
 * 当前是一个能跑的最小版本：8 个音符键 + 电脑键盘映射。
 * 扩展方向（自己加，不要改 serial.js）：
 *   - 音色 4 档切换按钮
 *   - 音量 +/-
 *   - 弯音 +/-
 *   - 八度切换、移调
 *   - 预设保存到 localStorage
 *
 * 可用的接口只有这几个：
 *   Serial.sendNote(midiNote, isOn, keyId)   keyId 固定 0~7
 *   Serial.sendRelease()                     交还触摸板
 * ========================================================================== */
(function () {
  'use strict';

  // TP0~TP7 对应 MIDI 60/62/64/65/67/69/71/72（C 大调音阶）
  var NOTES = [
    { midi: 60, name: 'C4' },
    { midi: 62, name: 'D4' },
    { midi: 64, name: 'E4' },
    { midi: 65, name: 'F4' },
    { midi: 67, name: 'G4' },
    { midi: 69, name: 'A4' },
    { midi: 71, name: 'B4' },
    { midi: 72, name: 'C5' }
  ];

  // 电脑键盘映射：A S D F G H J K
  var KEYS = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k'];

  var pressed = {};   // keyId -> true

  function press(id) {
    if (pressed[id]) return;
    pressed[id] = true;
    Serial.sendNote(NOTES[id].midi, true, id);
    paint(id, true);
  }

  function release(id) {
    if (!pressed[id]) return;
    pressed[id] = false;
    Serial.sendNote(NOTES[id].midi, false, id);
    paint(id, false);
  }

  function paint(id, on) {
    var el = document.querySelector('[data-key="' + id + '"]');
    if (el) el.classList.toggle('on', on);
  }

  function render() {
    var panel = document.getElementById('inputPanel');
    if (!panel) return;

    panel.innerHTML = '';

    var h2 = document.createElement('h2');
    h2.textContent = '虚拟输入';
    panel.appendChild(h2);

    var grid = document.createElement('div');
    grid.className = 'key-grid';

    NOTES.forEach(function (n, i) {
      var b = document.createElement('button');
      b.className = 'key';
      b.dataset.key = i;
      b.innerHTML = '<span class="kn">' + n.name + '</span>' +
                    '<span class="kk">' + KEYS[i].toUpperCase() + '</span>';

      b.addEventListener('mousedown', function (e) { e.preventDefault(); press(i); });
      b.addEventListener('mouseup',   function () { release(i); });
      b.addEventListener('mouseleave', function () { release(i); });
      b.addEventListener('touchstart', function (e) { e.preventDefault(); press(i); }, { passive: false });
      b.addEventListener('touchend',   function (e) { e.preventDefault(); release(i); }, { passive: false });

      grid.appendChild(b);
    });

    panel.appendChild(grid);

    var tip = document.createElement('p');
    tip.className = 'tip';
    tip.textContent = '鼠标点击，或按键盘 A S D F G H J K。首次按下会自动接管输入，触摸板暂停。';
    panel.appendChild(tip);

    // ---- 样式 ----
    var css = document.createElement('style');
    css.textContent = [
      '#inputPanel .key-grid{display:grid;grid-template-columns:repeat(8,1fr);gap:8px}',
      '#inputPanel .key{height:96px;border-radius:10px;border:1px solid #2c313a;',
      'background:#262b34;color:#e8eaed;cursor:pointer;display:flex;flex-direction:column;',
      'align-items:center;justify-content:center;gap:4px;font-family:inherit;transition:none}',
      '#inputPanel .key .kn{font-size:15px}',
      '#inputPanel .key .kk{font-size:11px;color:#8b93a1}',
      '#inputPanel .key.on{background:#4a9eff;border-color:#4a9eff;color:#fff}',
      '#inputPanel .key.on .kk{color:rgba(255,255,255,.8)}',
      '#inputPanel .tip{margin:12px 0 0;font-size:12px;color:#8b93a1}'
    ].join('');
    panel.appendChild(css);
  }

  // ---- 键盘 ----
  document.addEventListener('keydown', function (e) {
    if (e.repeat) return;
    var i = KEYS.indexOf(e.key.toLowerCase());
    if (i >= 0) { e.preventDefault(); press(i); }
  });

  document.addEventListener('keyup', function (e) {
    var i = KEYS.indexOf(e.key.toLowerCase());
    if (i >= 0) { e.preventDefault(); release(i); }
  });

  window.addEventListener('DOMContentLoaded', render);
})();
