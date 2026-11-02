/* ============================================================================
 * input.js —— 虚拟输入（负责人：feature/bt-in 分支）
 *
 * 在脚手架最小版（8 键 + 键盘映射）基础上扩展：
 *   1. 虚拟键盘：8 键，对应 C4 D4 E4 F4 G4 A4 B4 C5
 *   2. 键位定义：每个键可重绑到任意电脑按键，存在 localStorage
 *   3. 移调：-12 ~ +12 半音，发送时直接改写 MIDI 音号（协议里 note 就是音号，
 *      所以移调不需要 FPGA 配合，也不用改 serial.js）
 *   4. 节拍器：WebAudio 打点，BPM 可调，强拍音高不同
 *   5. 曲谱：内置 5 首 + 导入/导出 .json 与 .mid，可播放（自动发音符）
 *   6. 节奏判定：播放曲谱时按下的键与谱面比对，给出 PERFECT/GREAT/GOOD/MISS
 *   7. 录音：记录本地按键事件，可回放、导出 JSON 或标准 .mid
 *
 * 约束（见 docs/BT_LINK_SPLIT.md 第 13 节）：
 *   - 不修改 index.html / serial.js / display.js
 *   - 所有 DOM 与 CSS 都在本文件内动态生成
 *   - CSS 选择器一律以 #inputPanel 开头，避免和 display.js 打架
 *   - 对外只依赖 Serial.sendNote(note, on, keyId)
 *
 * 注意：FPGA 回传实体键由 feature/bt-out 负责，本文件不订阅状态帧。
 * ========================================================================== */
(function () {
  'use strict';

  // ---- 音高与键位 ----
  var BASE_NOTES   = [60, 62, 64, 65, 67, 69, 71, 72];     // C4..C5，C 大调白键
  var NOTE_NAMES   = ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5'];
  var DEFAULT_KEYS = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k'];
  var KEY_LABEL    = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K'];

  var STORE_KEYMAP = 'btin.keymap';
  var STORE_SEMI   = 'btin.semitone';
  var STORE_BPM    = 'btin.bpm';

  // 判定窗口（秒）
  var WIN_PERFECT = 0.060;
  var WIN_GREAT   = 0.100;
  var WIN_GOOD    = 0.160;
  var WIN_MISS    = 0.220;

  // ---- 状态 ----
  var S = {
    semitone: 0,
    keys: DEFAULT_KEYS.slice(),
    pressed: {},
    bpm: 96,
    metroOn: false,
    metroNext: 0,
    metroCount: 0,
    metroTimer: null,
    audio: null,
    song: null,
    songBpm: 96,
    playing: false,
    playStart: 0,
    songTimer: null,
    judged: [],
    score: null,
    rebindSlot: -1,
    rec: false,
    recStart: 0,
    recEvents: [],
    recTimer: null
  };

  var refs = {};      // 常用 DOM 引用

  // ---- 音名 ----
  function noteName(midi) {
    var names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return names[((midi % 12) + 12) % 12] + (Math.floor(midi / 12) - 1);
  }

  function noteOf(k) { return BASE_NOTES[k] + S.semitone; }

  // ---- 持久化 ----
  function loadPrefs() {
    try {
      var km = localStorage.getItem(STORE_KEYMAP);
      if (km) {
        var arr = JSON.parse(km);
        if (arr && arr.length === 8) S.keys = arr;
      }
      var sem = parseInt(localStorage.getItem(STORE_SEMI), 10);
      if (!isNaN(sem)) S.semitone = Math.max(-12, Math.min(12, sem));
      var bpm = parseInt(localStorage.getItem(STORE_BPM), 10);
      if (!isNaN(bpm)) S.bpm = Math.max(30, Math.min(240, bpm));
    } catch (e) { /* localStorage 不可用时静默 */ }
  }

  function savePrefs() {
    try {
      localStorage.setItem(STORE_KEYMAP, JSON.stringify(S.keys));
      localStorage.setItem(STORE_SEMI, String(S.semitone));
      localStorage.setItem(STORE_BPM, String(S.bpm));
    } catch (e) { /* 忽略 */ }
  }

  // ---- 串口发送（薄封装，没有串口时也能本地演示）----
  function sendNote(midi, on, k) {
    if (window.Serial && typeof window.Serial.sendNote === 'function') {
      window.Serial.sendNote(midi, on, k);
    }
  }

  // ---- 按下 / 松开 ----
  function press(k) {
    if (S.pressed[k]) return;
    S.pressed[k] = true;
    sendNote(noteOf(k), true, k);
    paint(k, true);
    record(k, true);
    judge(k);
  }

  function release(k) {
    if (!S.pressed[k]) return;
    S.pressed[k] = false;
    sendNote(noteOf(k), false, k);
    paint(k, false);
    record(k, false);
  }

  function releaseAll() {
    for (var k = 0; k < 8; k++) release(k);
  }

  function paint(k, on) {
    var e = document.querySelector('#inputPanel [data-key="' + k + '"]');
    if (!e || !e.classList) return;
    if (on) e.classList.add('on');
    else    e.classList.remove('on');
  }

  // ==========================================================================
  // 录音
  // ==========================================================================
  function record(k, on) {
    if (!S.rec) return;
    S.recEvents.push({
      t: Math.round(performance.now() - S.recStart),
      k: k,
      on: on,
      n: noteOf(k)
    });
    updateRecLabel();
  }

  function updateRecLabel() {
    if (!refs.recInfo) return;
    if (S.rec) refs.recInfo.textContent = '录音中… ' + S.recEvents.length + ' 个事件';
    else       refs.recInfo.textContent = S.recEvents.length
               ? ('已录 ' + S.recEvents.length + ' 个事件') : '未录音';
  }

  function startRec() {
    S.recEvents = [];
    S.recStart = performance.now();
    S.rec = true;
    updateRecLabel();
    if (refs.btnRec) refs.btnRec.textContent = '停止录音';
  }

  function stopRec() {
    S.rec = false;
    if (refs.btnRec) refs.btnRec.textContent = '开始录音';
    updateRecLabel();
  }

  function playRec() {
    if (!S.recEvents.length) return;
    if (S.recTimer) { clearTimeout(S.recTimer); S.recTimer = null; }
    var evs = S.recEvents.slice();
    var t0 = performance.now();
    var i = 0;
    function step() {
      var now = performance.now() - t0;
      while (i < evs.length && evs[i].t <= now) {
        sendNote(evs[i].n, evs[i].on, evs[i].k);
        i++;
      }
      if (i < evs.length) S.recTimer = setTimeout(step, 8);
      else S.recTimer = null;
    }
    step();
  }

  // ==========================================================================
  // WebAudio（节拍器）
  // ==========================================================================
  function ac() {
    if (!S.audio) {
      var Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return null;
      try { S.audio = new Ctx(); } catch (e) { return null; }
    }
    if (S.audio.state === 'suspended' && S.audio.resume) S.audio.resume();
    return S.audio;
  }

  function click(when, strong) {
    var ctx = ac();
    if (!ctx) return;
    var osc = ctx.createOscillator();
    var g   = ctx.createGain();
    osc.type = 'square';
    osc.frequency.value = strong ? 1320 : 880;
    g.gain.setValueAtTime(0.0001, when);
    g.gain.exponentialRampToValueAtTime(strong ? 0.20 : 0.12, when + 0.002);
    g.gain.exponentialRampToValueAtTime(0.0001, when + 0.045);
    osc.connect(g);
    g.connect(ctx.destination);
    osc.start(when);
    osc.stop(when + 0.06);
  }

  function metroTickFn() {
    if (!S.metroOn) return;
    var ctx = ac();
    if (!ctx) return;
    while (S.metroNext < ctx.currentTime + 0.12) {
      click(S.metroNext, (S.metroCount % 4) === 0);
      S.metroNext += 60 / S.bpm;
      S.metroCount++;
    }
  }

  function metroToggle() {
    S.metroOn = !S.metroOn;
    if (S.metroOn) {
      var ctx = ac();
      if (ctx) S.metroNext = ctx.currentTime + 0.08;
      S.metroCount = 0;
      if (refs.btnMetro) refs.btnMetro.textContent = '停节拍器';
      S.metroTimer = setInterval(metroTickFn, 25);
    } else {
      if (S.metroTimer) { clearInterval(S.metroTimer); S.metroTimer = null; }
      if (refs.btnMetro) refs.btnMetro.textContent = '开节拍器';
    }
  }

  // ==========================================================================
  // 曲谱
  // ==========================================================================
  // notes: k=键号 0..7, b=起始拍, d=时长拍
  function seqNotes(pairs) {
    var out = [], t = 0;
    for (var i = 0; i < pairs.length; i++) {
      out.push({ k: pairs[i][0], b: t, d: pairs[i][1] });
      t += pairs[i][1];
    }
    return out;
  }

  var BUILTIN = [
    {
      name: '小星星',
      bpm: 100,
      notes: seqNotes([
        [0, 1], [0, 1], [4, 1], [4, 1], [5, 1], [5, 1], [4, 2],
        [3, 1], [3, 1], [2, 1], [2, 1], [1, 1], [1, 1], [0, 2]
      ])
    },
    {
      name: '欢乐颂',
      bpm: 108,
      notes: seqNotes([
        [2, 1], [2, 1], [3, 1], [4, 1], [4, 1], [3, 1], [2, 1], [1, 1],
        [0, 1], [0, 1], [1, 1], [2, 1], [2, 1.5], [1, 0.5], [1, 2]
      ])
    },
    {
      name: '两只老虎',
      bpm: 112,
      notes: seqNotes([
        [0, 1], [1, 1], [2, 1], [0, 1], [0, 1], [1, 1], [2, 1], [0, 1],
        [2, 1], [3, 1], [4, 2], [2, 1], [3, 1], [4, 2]
      ])
    },
    {
      name: '划船歌',
      bpm: 96,
      notes: seqNotes([
        [0, 1], [0, 0.5], [0, 0.5], [1, 1], [2, 1],
        [2, 0.5], [1, 0.5], [2, 1], [3, 1], [4, 2],
        [7, 0.5], [7, 0.5], [7, 0.5], [4, 0.5], [4, 0.5], [4, 0.5],
        [2, 0.5], [2, 0.5], [2, 0.5], [0, 0.5], [0, 0.5], [0, 0.5],
        [4, 1], [3, 1], [2, 1], [1, 1], [0, 2]
      ])
    },
    {
      name: '玛丽有只小羊羔',
      bpm: 104,
      notes: seqNotes([
        [2, 1], [1, 1], [0, 1], [1, 1], [2, 1], [2, 1], [2, 2],
        [1, 1], [1, 1], [1, 2], [2, 1], [4, 1], [4, 2]
      ])
    }
  ];

  function songEnd(song) {
    var end = 0;
    for (var i = 0; i < song.notes.length; i++) {
      var n = song.notes[i];
      if (n.b + n.d > end) end = n.b + n.d;
    }
    return end;
  }

  function newScore() {
    return { perfect: 0, great: 0, good: 0, miss: 0, hit: 0, combo: 0, maxCombo: 0 };
  }

  function loadSong(song) {
    S.song = song;
    S.songBpm = song.bpm || 96;
    S.judged = [];
    S.score = newScore();
    renderSongInfo();
    renderScore();
  }

  function playSong() {
    if (!S.song) return;
    stopSong(true);
    var ctx = ac();
    if (!ctx) { alert('当前浏览器不支持 WebAudio，无法播放曲谱'); return; }

    S.playing = true;
    S.playStart = ctx.currentTime + 0.20;
    S.judged = S.song.notes.map(function () { return false; });
    S.score = newScore();
    renderScore();

    var spb = 60 / S.songBpm;
    for (var i = 0; i < S.song.notes.length; i++) {
      var n = S.song.notes[i];
      scheduleNote(S.playStart + n.b * spb, n.k);
    }
    S.songTimer = setInterval(songTick, 20);
    if (refs.btnPlay) refs.btnPlay.textContent = '停止';
  }

  // 到点发 note on，短暂后发 note off（FPGA 侧 ADSR 会自己收尾）
  function scheduleNote(at, k) {
    var ctx = ac();
    if (!ctx) return;
    var wait = (at - ctx.currentTime) * 1000;
    var fire = function () {
      if (!S.playing) return;
      sendNote(noteOf(k), true, k);
      paint(k, true);
      setTimeout(function () {
        sendNote(noteOf(k), false, k);
        paint(k, false);
      }, 110);
    };
    if (wait <= 0) fire();
    else setTimeout(fire, wait);
  }

  function songTick() {
    if (!S.playing || !S.song) return;
    var ctx = ac();
    if (!ctx) return;
    var beat = (ctx.currentTime - S.playStart) * S.songBpm / 60;
    var i, n, late;

    // 漏判：超过窗口还没按
    for (i = 0; i < S.song.notes.length; i++) {
      if (S.judged[i]) continue;
      n = S.song.notes[i];
      late = (beat - n.b) * 60 / S.songBpm;
      if (late > WIN_MISS) {
        S.judged[i] = true;
        S.score.miss++;
        S.score.combo = 0;
        renderScore();
      }
    }

    if (beat > songEnd(S.song) + 1.2) stopSong(true);
  }

  function stopSong(keepSong) {
    S.playing = false;
    if (S.songTimer) { clearInterval(S.songTimer); S.songTimer = null; }
    for (var k = 0; k < 8; k++) {
      if (S.pressed[k]) {
        sendNote(noteOf(k), false, k);
        paint(k, false);
        S.pressed[k] = false;
      }
    }
    if (refs.btnPlay) refs.btnPlay.textContent = '播放';
    if (!keepSong) renderSongInfo();
  }

  // 播放中按键 -> 与最近的未判定同键音符比对
  function judge(k) {
    if (!S.playing || !S.song) return;
    var ctx = ac();
    if (!ctx) return;
    var beat = (ctx.currentTime - S.playStart) * S.songBpm / 60;
    var best = -1, bestAbs = 1e9, i, n, dt;

    for (i = 0; i < S.song.notes.length; i++) {
      if (S.judged[i]) continue;
      n = S.song.notes[i];
      if (n.k !== k) continue;
      dt = (beat - n.b) * 60 / S.songBpm;
      if (Math.abs(dt) < bestAbs && Math.abs(dt) <= WIN_MISS) {
        best = i;
        bestAbs = Math.abs(dt);
      }
    }
    if (best < 0) return;      // 谱面没有这个音（或已经判过）：不记错

    S.judged[best] = true;
    S.score.hit++;
    S.score.combo++;
    if (S.score.combo > S.score.maxCombo) S.score.maxCombo = S.score.combo;

    if (bestAbs <= WIN_PERFECT)      S.score.perfect++;
    else if (bestAbs <= WIN_GREAT)   S.score.great++;
    else                             S.score.good++;

    renderScore();
  }

  function scorePoints(sc) {
    return sc.perfect * 100 + sc.great * 70 + sc.good * 40;
  }

  function hitRate(sc) {
    var total = sc.perfect + sc.great + sc.good + sc.miss;
    if (!total) return 0;
    var weighted = sc.perfect * 1 + sc.great * 0.8 + sc.good * 0.5;
    return Math.round(weighted / total * 100);
  }

  // ==========================================================================
  // MIDI 读写（纯前端，无第三方库）
  // ==========================================================================
  function vlqBytes(v) {
    var out = [v & 0x7f];
    v >>= 7;
    while (v > 0) { out.unshift((v & 0x7f) | 0x80); v >>= 7; }
    return out;
  }

  // events: [{t: ms, midi, on}] -> Uint8Array（format 0，单轨）
  function buildMidi(events, bpm) {
    var division = 480;
    var msPerQuarter = 60000 / (bpm || 96);
    var evs = events.slice().sort(function (a, b) { return a.t - b.t; });

    var track = [];
    var usPerQuarter = Math.round(msPerQuarter * 1000);
    // 速度 meta
    track = track.concat([0x00, 0xFF, 0x51, 0x03,
      (usPerQuarter >> 16) & 0xff, (usPerQuarter >> 8) & 0xff, usPerQuarter & 0xff]);

    var lastTick = 0, i;
    for (i = 0; i < evs.length; i++) {
      var e = evs[i];
      var tick = Math.round(e.t / msPerQuarter * division);
      var delta = tick - lastTick;
      if (delta < 0) delta = 0;
      lastTick = tick;
      track = track.concat(vlqBytes(delta));
      track.push(e.on ? 0x90 : 0x80, e.midi & 0x7f, e.on ? 0x64 : 0x00);
    }
    track = track.concat([0x00, 0xFF, 0x2F, 0x00]);

    var out = [0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1];
    out.push((division >> 8) & 0xff, division & 0xff);
    out = out.concat([0x4D, 0x54, 0x72, 0x6B]);
    var len = track.length;
    out.push((len >> 24) & 0xff, (len >> 16) & 0xff, (len >> 8) & 0xff, len & 0xff);
    return new Uint8Array(out.concat(track));
  }

  // 解析 SMF -> {division, bpm, events:[{tick, midi, on}]}
  // 入参可以是 ArrayBuffer 或 Uint8Array；内部统一按字节视图访问。
  // （直接 buf[i] 索引 ArrayBuffer 得到 undefined，是最容易踩的坑）
  function parseMidi(input) {
    var bytes = (input instanceof Uint8Array)
              ? input
              : new Uint8Array(input);
    var dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    if (dv.getUint32(0) !== 0x4D546864) throw new Error('不是标准 MIDI 文件');
    var hlen = dv.getUint32(4);
    var ntrk = dv.getUint16(10);
    var div  = dv.getUint16(12);
    if (!div || (div & 0x8000)) throw new Error('不支持 SMPTE 时间格式的 MIDI');

    var p = 8 + hlen;
    var events = [];
    var bpm = 120;
    var tr, tick, running, b;

    for (tr = 0; tr < ntrk && p + 8 <= bytes.byteLength; tr++) {
      if (dv.getUint32(p) !== 0x4D54726B) break;
      var tlen = dv.getUint32(p + 4);
      p += 8;
      var end = Math.min(bytes.byteLength, p + tlen);

      tick = 0;
      running = 0;
      while (p < end) {
        var delta = 0;
        do {
          b = bytes[p++];
          delta = (delta << 7) | (b & 0x7f);
        } while (b & 0x80);
        tick += delta;
        if (p >= end) break;

        var st = bytes[p];
        if (st & 0x80) { p++; running = st; } else { st = running; }

        if (st === 0xFF) {
          var meta = bytes[p++];
          var mlen = 0;
          do { b = bytes[p++]; mlen = (mlen << 7) | (b & 0x7f); } while (b & 0x80);
          if (meta === 0x51 && mlen >= 3) {
            var us = (bytes[p] << 16) | (bytes[p + 1] << 8) | bytes[p + 2];
            if (us > 0) bpm = Math.round(60000000 / us);
          }
          p += mlen;
          continue;
        }

        var hi = st & 0xF0;
        if (hi === 0x90 || hi === 0x80) {
          var midi = bytes[p++];
          var vel  = bytes[p++];
          events.push({ tick: tick, midi: midi, on: (hi === 0x90) && vel > 0 });
        } else if (hi === 0xC0 || hi === 0xD0) {
          p += 1;
        } else {
          p += 2;
        }
      }
      p = end;
    }
    return { division: div, bpm: bpm, events: events };
  }

  // MIDI 音号 -> 8 键里最近的白键
  function midiToKey(m) {
    var semis = [0, 2, 4, 5, 7, 9, 11];
    var pc = ((m % 12) + 12) % 12;
    var best = 0, bd = 99, i, d;
    for (i = 0; i < 7; i++) {
      d = Math.abs(pc - semis[i]);
      if (d < bd) { bd = d; best = i; }
    }
    // 只有 C5 及以上才用第 8 键；C4(60) 仍是按下标 0
    if (pc === 0 && m >= 72) best = 7;
    return best;
  }

  // MIDI -> 曲谱（拍为单位，保留相对节奏）
  function midiToSong(buf, name) {
    var p = parseMidi(buf);
    if (!p.events.length) throw new Error('这个 MIDI 里没有音符事件');

    var div = p.division;
    var pending = {};
    var notes = [];
    var i, e;

    for (i = 0; i < p.events.length; i++) {
      e = p.events[i];
      if (e.on) {
        if (pending[e.midi] === undefined) pending[e.midi] = e.tick;
      } else if (pending[e.midi] !== undefined) {
        notes.push({
          k: midiToKey(e.midi),
          b: pending[e.midi] / div,
          d: Math.max(0.1, (e.tick - pending[e.midi]) / div)
        });
        delete pending[e.midi];
      }
    }
    if (!notes.length) throw new Error('没能从 MIDI 提取出音符');

    notes.sort(function (a, b) { return a.b - b.b; });
    return { name: name || '导入的曲谱', bpm: p.bpm, notes: notes };
  }

  function download(name, bytes) {
    var blob = new Blob([bytes], { type: 'application/octet-stream' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
  }

  // ==========================================================================
  // 渲染
  // ==========================================================================
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function btn(label, fn, cls) {
    var b = el('button', cls || '', label);
    b.addEventListener('click', fn);
    return b;
  }

  function render() {
    var panel = document.getElementById('inputPanel');
    if (!panel) return;
    panel.innerHTML = '';

    panel.appendChild(el('h2', '', '虚拟输入'));

    // ---------- 1. 键盘 ----------
    var grid = el('div', 'key-grid');
    for (var i = 0; i < 8; i++) {
      (function (k) {
        var b = el('button', 'key');
        b.setAttribute('data-key', String(k));

        var kn = el('span', 'kn', NOTE_NAMES[k]);
        var kk = el('span', 'kk', keyLabel(k));
        kk.setAttribute('data-bind', String(k));
        kk.title = '点这里再按一个电脑按键，可重新绑定';

        b.appendChild(kn);
        b.appendChild(kk);

        b.addEventListener('mousedown', function (e) { e.preventDefault(); press(k); });
        b.addEventListener('mouseup', function () { release(k); });
        b.addEventListener('mouseleave', function () { release(k); });
        b.addEventListener('touchstart', function (e) { e.preventDefault(); press(k); }, { passive: false });
        b.addEventListener('touchend', function (e) { e.preventDefault(); release(k); }, { passive: false });

        kk.addEventListener('click', function (e) {
          e.stopPropagation();
          e.preventDefault();
          startRebind(k);
        });

        grid.appendChild(b);
      })(i);
    }
    panel.appendChild(grid);

    panel.appendChild(el('p', 'tip',
      '鼠标点击，或按键盘 ' + KEY_LABEL.join(' ') + '。首次按下会自动接管输入，触摸板暂停。'));

    // ---------- 2. 移调 / 复位 / 全松 ----------
    var bar = el('div', 'row');
    bar.appendChild(el('span', 'lab', '移调'));
    refs.semiBtn = btn('0 半音', cycleSemitone, 'small');
    bar.appendChild(refs.semiBtn);
    bar.appendChild(btn('复位键位', function () {
      S.keys = DEFAULT_KEYS.slice();
      savePrefs();
      renderKeysOnly();
    }, 'small'));
    bar.appendChild(btn('全部松开', releaseAll, 'small'));
    panel.appendChild(bar);

    // ---------- 3. 节拍器 ----------
    var mrow = el('div', 'row');
    mrow.appendChild(el('span', 'lab', '节拍器'));
    refs.bpmInput = document.createElement('input');
    refs.bpmInput.type = 'number';
    refs.bpmInput.min = '30';
    refs.bpmInput.max = '240';
    refs.bpmInput.value = String(S.bpm);
    refs.bpmInput.className = 'num';
    refs.bpmInput.addEventListener('change', function () {
      var v = parseInt(refs.bpmInput.value, 10);
      if (isNaN(v)) v = 96;
      S.bpm = Math.max(30, Math.min(240, v));
      refs.bpmInput.value = String(S.bpm);
      savePrefs();
    });
    mrow.appendChild(refs.bpmInput);
    mrow.appendChild(el('span', 'lab', 'BPM'));
    refs.btnMetro = btn(S.metroOn ? '停节拍器' : '开节拍器', metroToggle, 'small');
    mrow.appendChild(refs.btnMetro);
    panel.appendChild(mrow);

    // ---------- 4. 曲谱 ----------
    var srow = el('div', 'row');
    srow.appendChild(el('span', 'lab', '曲谱'));
    refs.songSel = document.createElement('select');
    refs.songSel.className = 'sel';
    for (var si = 0; si < BUILTIN.length; si++) {
      var op = document.createElement('option');
      op.value = String(si);
      op.textContent = BUILTIN[si].name;
      refs.songSel.appendChild(op);
    }
    refs.songSel.addEventListener('change', function () {
      if (S.playing) stopSong(true);
      loadSong(BUILTIN[parseInt(refs.songSel.value, 10)]);
    });
    srow.appendChild(refs.songSel);
    refs.btnPlay = btn('播放', function () {
      if (S.playing) stopSong(true);
      else playSong();
    }, 'small primary');
    srow.appendChild(refs.btnPlay);
    panel.appendChild(srow);

    var srow2 = el('div', 'row');
    srow2.appendChild(btn('导入 .mid / .json', function () { refs.file.click(); }, 'small'));
    srow2.appendChild(btn('导出 .mid', function () {
      if (!S.song) return;
      var beatMs = 60 / S.songBpm * 1000;
      var evs = [];
      for (var j = 0; j < S.song.notes.length; j++) {
        var n = S.song.notes[j];
        evs.push({ t: n.b * beatMs, midi: noteOf(n.k), on: true });
        evs.push({ t: (n.b + n.d) * beatMs - 30, midi: noteOf(n.k), on: false });
      }
      download('song.mid', buildMidi(evs, S.songBpm));
    }, 'small'));
    srow2.appendChild(btn('导出 .json', function () {
      if (!S.song) return;
      var txt = JSON.stringify({ name: S.song.name, bpm: S.songBpm, notes: S.song.notes }, null, 2);
      download('song.json', new TextEncoder().encode(txt));
    }, 'small'));
    panel.appendChild(srow2);

    refs.file = document.createElement('input');
    refs.file.type = 'file';
    refs.file.accept = '.mid,.midi,.json,application/json,audio/midi';
    refs.file.style.display = 'none';
    refs.file.addEventListener('change', importFile);
    panel.appendChild(refs.file);

    refs.songInfo = el('p', 'tip', '');
    panel.appendChild(refs.songInfo);

    // ---------- 5. 判定 ----------
    refs.scoreBox = el('div', 'score');
    panel.appendChild(refs.scoreBox);

    // ---------- 6. 录音 ----------
    var rrow = el('div', 'row');
    refs.btnRec = btn('开始录音', function () {
      if (S.rec) stopRec(); else startRec();
    }, 'small');
    rrow.appendChild(refs.btnRec);
    rrow.appendChild(btn('回放', playRec, 'small'));
    rrow.appendChild(btn('导出录音 .mid', function () {
      if (!S.recEvents.length) return;
      var evs = S.recEvents.map(function (e) {
        return { t: e.t, midi: e.n, on: e.on };
      });
      download('recording.mid', buildMidi(evs, S.bpm));
    }, 'small'));
    rrow.appendChild(btn('清空', function () {
      S.recEvents = [];
      updateRecLabel();
    }, 'small'));
    panel.appendChild(rrow);

    refs.recInfo = el('p', 'tip', '未录音');
    panel.appendChild(refs.recInfo);

    // ---------- 样式 ----------
    var css = document.createElement('style');
    css.textContent = [
      '#inputPanel .key-grid{display:grid;grid-template-columns:repeat(8,1fr);gap:8px}',
      '#inputPanel .key{height:96px;border-radius:10px;border:1px solid #2c313a;',
      'background:#262b34;color:#e8eaed;cursor:pointer;display:flex;flex-direction:column;',
      'align-items:center;justify-content:center;gap:4px;font-family:inherit;transition:none}',
      '#inputPanel .key .kn{font-size:15px}',
      '#inputPanel .key .kk{font-size:11px;color:#8b93a1;border-bottom:1px dashed transparent;padding:0 2px}',
      '#inputPanel .key .kk:hover{color:#4a9eff;border-bottom-color:#4a9eff}',
      '#inputPanel .key.on{background:#4a9eff;border-color:#4a9eff;color:#fff}',
      '#inputPanel .key.on .kk{color:rgba(255,255,255,.8)}',
      '#inputPanel .key.waiting{outline:2px solid #ffb020;outline-offset:2px}',
      '#inputPanel .tip{margin:10px 0 0;font-size:12px;color:#8b93a1}',
      '#inputPanel .row{display:flex;align-items:center;gap:8px;margin-top:10px;flex-wrap:wrap}',
      '#inputPanel .lab{font-size:12px;color:#8b93a1}',
      '#inputPanel button.small{padding:5px 10px;font-size:12px;border-radius:7px}',
      '#inputPanel button.small.primary{background:#4a9eff;border-color:#4a9eff;color:#fff}',
      '#inputPanel input.num{width:62px;padding:5px 8px;border-radius:7px;border:1px solid #2c313a;',
      'background:#14161a;color:#e8eaed;font-family:inherit;font-size:12px}',
      '#inputPanel select.sel{padding:5px 8px;border-radius:7px;border:1px solid #2c313a;',
      'background:#14161a;color:#e8eaed;font-family:inherit;font-size:12px}',
      '#inputPanel .score{margin-top:10px;display:flex;gap:14px;flex-wrap:wrap;font-size:12px;color:#8b93a1}',
      '#inputPanel .score b{color:#e8eaed;font-weight:500}',
      '#inputPanel .score .pf{color:#3ddc97}',
      '#inputPanel .score .gr{color:#4a9eff}',
      '#inputPanel .score .gd{color:#ffb020}',
      '#inputPanel .score .ms{color:#ff5c5c}'
    ].join('');
    panel.appendChild(css);

    loadSong(BUILTIN[0]);
    renderKeysOnly();
    updateRecLabel();
  }

  function keyLabel(k) {
    var v = S.keys[k] || '';
    if (v === ' ') return '空格';
    return v.length === 1 ? v.toUpperCase() : v;
  }

  // 只刷新键位标签，不重建面板（重绑后用）
  function renderKeysOnly() {
    for (var k = 0; k < 8; k++) {
      var e = document.querySelector('#inputPanel [data-bind="' + k + '"]');
      if (e) e.textContent = keyLabel(k);
    }
    if (refs.semiBtn) {
      refs.semiBtn.textContent = (S.semitone > 0 ? '+' : '') + S.semitone + ' 半音';
    }
  }

  function renderSongInfo() {
    if (!refs.songInfo) return;
    if (!S.song) { refs.songInfo.textContent = ''; return; }
    refs.songInfo.textContent = '当前曲谱：' + S.song.name + '　' +
      S.song.notes.length + ' 个音　' + Math.round(songEnd(S.song)) + ' 拍　' +
      S.songBpm + ' BPM。播放会自动发音符；按下琴键会与谱面比对节奏。';
  }

  function renderScore() {
    if (!refs.scoreBox || !S.score) return;
    var sc = S.score;
    refs.scoreBox.innerHTML =
      '<span>得分 <b>' + scorePoints(sc) + '</b></span>' +
      '<span>准确率 <b>' + hitRate(sc) + '%</b></span>' +
      '<span class="pf">PERFECT <b>' + sc.perfect + '</b></span>' +
      '<span class="gr">GREAT <b>' + sc.great + '</b></span>' +
      '<span class="gd">GOOD <b>' + sc.good + '</b></span>' +
      '<span class="ms">MISS <b>' + sc.miss + '</b></span>' +
      '<span>连击 <b>' + sc.combo + '</b> / 最高 <b>' + sc.maxCombo + '</b></span>';
  }

  function importFile() {
    var f = refs.file && refs.file.files && refs.file.files[0];
    if (!f) return;
    var reader = new FileReader();
    reader.onload = function () {
      try {
        var buf = reader.result;
        var song;
        if (/\.json$/i.test(f.name)) {
          var obj = JSON.parse(new TextDecoder().decode(new Uint8Array(buf)));
          if (!obj || !obj.notes) throw new Error('JSON 里没有 notes 数组');
          song = {
            name: obj.name || f.name,
            bpm: Math.max(30, Math.min(240, obj.bpm || 96)),
            notes: obj.notes.map(function (n) {
              return { k: n.k & 7, b: n.b, d: n.d || 1 };
            })
          };
        } else {
          song = midiToSong(buf, f.name);
        }
        if (S.playing) stopSong(true);
        loadSong(song);
        refs.songSel.selectedIndex = -1;
        renderSongInfo();
      } catch (e) {
        alert('导入失败：' + e.message);
      }
      refs.file.value = '';
    };
    reader.readAsArrayBuffer(f);
  }

  // 移调阶梯：常用的大三度/纯五度优先，再给整八度
  function cycleSemitone() {
    var steps = [0, 2, 4, 5, 7, 9, 12, -12, -9, -7, -5, -4, -2];
    var i = steps.indexOf(S.semitone);
    releaseAll();                    // 先松，避免用新音高发旧音的 note off
    S.semitone = steps[(i + 1) % steps.length];
    savePrefs();
    renderKeysOnly();
  }

  function startRebind(k) {
    S.rebindSlot = k;
    var all = document.querySelectorAll('#inputPanel .key');
    for (var i = 0; i < all.length; i++) all[i].classList.remove('waiting');
    var bind = document.querySelector('#inputPanel [data-bind="' + k + '"]');
    if (bind) {
      var keyBtn = bind.parentNode;
      if (keyBtn && keyBtn.classList) keyBtn.classList.add('waiting');
      bind.textContent = '按键…';
    }
  }

  // ==========================================================================
  // 键盘事件
  // ==========================================================================
  function isTyping(e) {
    var t = e.target;
    if (!t || !t.tagName) return false;
    var tag = t.tagName.toUpperCase();
    return tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA';
  }

  function keyName(e) {
    if (e.key === ' ') return ' ';
    return String(e.key || '').toLowerCase();
  }

  document.addEventListener('keydown', function (e) {
    if (isTyping(e)) return;

    // 重绑模式优先
    if (S.rebindSlot >= 0) {
      e.preventDefault();
      var name = keyName(e);
      if (!name || name.length > 8) return;
      for (var j = 0; j < 8; j++) {
        if (j !== S.rebindSlot && S.keys[j] === name) S.keys[j] = '';
      }
      S.keys[S.rebindSlot] = name;
      S.rebindSlot = -1;
      var w = document.querySelector('#inputPanel .key.waiting');
      if (w && w.classList) w.classList.remove('waiting');
      savePrefs();
      renderKeysOnly();
      return;
    }

    if (e.repeat) return;
    var idx = S.keys.indexOf(keyName(e));
    if (idx >= 0) {
      e.preventDefault();
      press(idx);
    }
  });

  document.addEventListener('keyup', function (e) {
    if (isTyping(e)) return;
    var idx = S.keys.indexOf(keyName(e));
    if (idx >= 0) {
      e.preventDefault();
      release(idx);
    }
  });

  // 窗口失焦时全部松开，避免卡音
  window.addEventListener('blur', function () { releaseAll(); });

  // ---- 启动 ----
  window.addEventListener('DOMContentLoaded', function () {
    loadPrefs();
    render();
  });

  // ---- 离线测试钩子（浏览器里不会用到）----
  window.__btin = {
    state: S,
    press: press,
    release: release,
    noteOf: noteOf,
    noteName: noteName,
    loadSong: loadSong,
    judge: judge,
    newScore: newScore,
    midiToSong: midiToSong,
    buildMidi: buildMidi,
    parseMidi: parseMidi,
    BUILTIN: BUILTIN,
    songEnd: songEnd,
    midiToKey: midiToKey,
    cycleSemitone: cycleSemitone,
    hitRate: hitRate,
    scorePoints: scorePoints
  };
})();
