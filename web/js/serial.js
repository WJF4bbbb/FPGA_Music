/* ============================================================================
 * serial.js —— 串口收发 + 帧解析（共用，两个分支都不要改这个文件）
 *
 * 对外只暴露三个东西，input.js 和 display.js 只依赖这三个：
 *
 *   Serial.connect()              连接串口（必须在用户点击事件里调用）
 *   Serial.disconnect()           断开
 *   Serial.sendNote(note, on, id) 发一个音符事件
 *   Serial.sendRelease()          交还触摸板控制权
 *   Serial.onFrame(fn)            注册状态帧回调，fn(status) 每帧调用一次
 *   Serial.setStatus(text, kind)  更新右上角状态标签
 *
 * status 对象结构（20 字节状态帧解析结果）：
 *   {
 *     touchKeys : 0x0000,        // 16 键位图，bit N = TPN 按下
 *     notes     : [0,0,0,0],     // 4 个声部的 MIDI 音号，0 = 空闲
 *     gates     : 0,             // 低 4 位，bit N = 第 N 声部 gate 为高
 *     timbre    : 0,             // 0~3
 *     bend      : 0,             // -2~+2，有符号
 *     gain      : 0,             // 0~65535，65535 = 1.0
 *     clip      : 0              // 削顶累计次数
 *   }
 * ========================================================================== */
(function () {
  'use strict';

  // ---- 协议常量（与 docs/BT_LINK_SPLIT.md 一致） ----
  var BAUD_RATE     = 115200;
  var HEAD0         = 0xAA;
  var HEAD1         = 0x55;
  var TYPE_STATUS   = 0x01;   // 板子 -> 网页，长度 15
  var TYPE_NOTE     = 0x02;   // 网页 -> 板子，长度 2
  var TYPE_RELEASE  = 0x03;   // 网页 -> 板子，长度 0
  var TYPE_KEEPALIVE= 0x00;   // 网页 -> 板子，长度 0，解析器会忽略，只用来重置 2 s 超时

  // ---- 内部状态 ----
  var port   = null;
  var reader = null;
  var writer = null;
  var reading = false;
  var handlers = [];
  var waveHandlers = [];
  var connectionHandlers = [];
  var waves = new WaveProtocol.Assembler();
  var keepalive = null;

  // ---- CRC8：多项式 0x07，初值 0x00，不反转 ----
  function crc8(bytes) {
    var c = 0;
    for (var i = 0; i < bytes.length; i++) {
      c ^= bytes[i];
      for (var b = 0; b < 8; b++) {
        c = (c & 0x80) ? ((c << 1) ^ 0x07) & 0xFF : (c << 1) & 0xFF;
      }
    }
    return c;
  }

  // ---- 状态标签 ----
  function setStatus(text, kind) {
    var el = document.getElementById('status');
    if (!el) return;
    el.textContent = text;
    el.className = kind || '';
  }

  // ---- 帧解析状态机 ----
  // 格式：AA 55 | 类型 | 长度 | 数据... | CRC8（覆盖类型到数据末尾）
  var decoder = new WaveProtocol.FrameDecoder(dispatch, function () { waves.reset(); });

  function resetParser() {
    decoder.reset();
    waves.reset();
  }

  function connectionState(value) {
    connectionHandlers.forEach(function (fn) { try { fn(value); } catch (e) { console.error(e); } });
  }

  function parseStatus(d) {
    return {
      touchKeys: d[0] | (d[1] << 8),
      notes:     [d[2], d[3], d[4], d[5]],
      gates:     d[6] & 0x0F,
      timbre:    d[7],
      bend:      (d[8] << 24) >> 24,                                  // 符号扩展
      gain:      d[9] | (d[10] << 8),
      clip:      (d[11] | (d[12] << 8) | (d[13] << 16) | (d[14] << 24)) >>> 0
    };
  }

  function dispatch(type, data) {
    if (type === 0x10) {
      var capture = waves.push(data);
      if (capture) waveHandlers.forEach(function (fn) { try { fn(capture); } catch (e) { console.error(e); } });
      return;
    }
    if (type !== TYPE_STATUS) return;
    if (data.length !== 15) return;
    var s = parseStatus(data);
    for (var i = 0; i < handlers.length; i++) {
      try { handlers[i](s); } catch (e) { console.error('帧回调出错', e); }
    }
  }

  // ---- 读循环 ----
  async function readLoop() {
    while (reading && port && port.readable) {
      reader = port.readable.getReader();
      try {
        while (true) {
          var r = await reader.read();
          if (r.done) break;
          var chunk = r.value;
          decoder.push(chunk);
        }
      } catch (e) {
        if (reading) setStatus('读取中断', 'err');
      } finally {
        try { reader.releaseLock(); } catch (e) {}
        reader = null;
        resetParser();
      }
    }
  }

  // ---- 连接 ----
  async function connect() {
    if (!('serial' in navigator)) {
      setStatus('浏览器不支持 Web Serial', 'err');
      throw new Error('navigator.serial 不存在，请用 Chrome 或 Edge 桌面版');
    }
    if (port) return;

    try {
      port = await navigator.serial.requestPort();
      await port.open({ baudRate: BAUD_RATE });
      writer = port.writable.getWriter();
      reading = true;
      resetParser();
      connectionState(true);
      setStatus('已连接', 'on');
      readLoop();
      updateButtons();
      startKeepalive();
    } catch (e) {
      port = null;
      var msg = (e && e.message) ? e.message : String(e);
      setStatus('连接失败: ' + msg, 'err');
      if (window.console) console.error('[serial] connect failed:', e);
      throw e;
    }
  }

  async function disconnect() {
    reading = false;
    resetParser();
    connectionState(false);
    stopKeepalive();
    try { if (reader) await reader.cancel(); } catch (e) {}
    try { if (writer) { writer.releaseLock(); } } catch (e) {}
    writer = null;
    try { if (port) await port.close(); } catch (e) {}
    port = null;
    resetParser();
    setStatus('未连接');
    updateButtons();
  }

  function updateButtons() {
    var b1 = document.getElementById('btnConnect');
    var b2 = document.getElementById('btnRelease');
    if (b1) b1.textContent = port ? '断开' : '连接蓝牙串口';
    if (b2) b2.disabled = !port;
  }

  // ---- 发送 ----
  async function sendFrame(type, payload) {
    if (!writer) return false;
    var body = [type, payload.length].concat(payload);
    var frame = [HEAD0, HEAD1].concat(body).concat([crc8(body)]);
    try {
      await writer.write(new Uint8Array(frame));
      return true;
    } catch (e) {
      setStatus('发送失败', 'err');
      return false;
    }
  }

  // note: MIDI 音号；on: true=按下；keyId: 0~7
  function sendNote(note, on, keyId) {
    var flags = ((keyId & 0x07) << 1) | (on ? 1 : 0);
    return sendFrame(TYPE_NOTE, [note & 0x7F, flags]);
  }

  // 交还触摸板控制权（bt_owner 回低）
  function sendRelease() {
    return sendFrame(TYPE_RELEASE, []);
  }

  // ---- 保活心跳 ----
  // 板子的 bt_cmd_parse 有一条保护：蓝牙接管后连续 2 秒收不到任何字节，就判定
  // "网页那边断了"，把控制权还给触摸板；而 top.v 在交还的那一拍会把所有正在响
  // 的音清零。两条凑一起，结果就是「按住一个音超过 2 秒会被掐断」。
  // 这里每秒补一帧 type=0x00、长度 0 的合法帧：CRC 能过，但解析器不认识这个类型，
  // 直接忽略，只起到"我还活着"的作用，顺便把那个 2 秒计时器重置。
  // 旧固件（没有这条保护）同样会忽略它，所以对两种板子都安全。
  function startKeepalive() {
    stopKeepalive();
    keepalive = setInterval(function () {
      if (writer) sendFrame(TYPE_KEEPALIVE, []);
    }, 1000);
  }

  function stopKeepalive() {
    if (keepalive) { clearInterval(keepalive); keepalive = null; }
  }

  function onFrame(fn) {
    if (typeof fn === 'function') handlers.push(fn);
  }

  // ---- 按钮绑定 ----
  window.addEventListener('DOMContentLoaded', function () {
    var b1 = document.getElementById('btnConnect');
    var b2 = document.getElementById('btnRelease');
    if (b1) b1.addEventListener('click', function () {
      if (port) disconnect();
      else connect().catch(function (e) { console.error(e); });
    });
    if (b2) b2.addEventListener('click', function () { sendRelease(); });
    if (!('serial' in navigator)) {
      setStatus('浏览器不支持 Web Serial', 'err');
    }
    updateButtons();
  });

  // ---- 对外接口 ----
  window.Serial = {
    connect: connect,
    disconnect: disconnect,
    sendNote: sendNote,
    sendRelease: sendRelease,
    onFrame: onFrame,
    onWave: function (fn) { if (typeof fn === 'function') waveHandlers.push(fn); },
    onConnection: function (fn) { if (typeof fn === 'function') connectionHandlers.push(fn); },
    setStatus: setStatus,
    crc8: crc8
  };
})();
