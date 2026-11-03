/* ============================================================================
 * bridge_serial.js —— 和 serial.js 同接口，但底层走 HTTP/SSE 而不是 Web Serial
 *
 * 用途：Windows 没给蓝牙模块创建 COM 口时，由 tools/bt_bridge.py 把 RFCOMM
 * 数据转成 SSE 推送过来，网页这边用这个文件顶上，input.js / display.js 不用改。
 *
 * 对外接口与 serial.js 完全一致：
 *   Serial.connect() / disconnect() / sendNote() / sendRelease()
 *   Serial.onFrame(fn) / setStatus(text, kind) / crc8(bytes)
 * ========================================================================== */
(function () {
  'use strict';

  var handlers = [];
  var es = null;
  var connected = false;
  var frameCount = 0;
  var lastFrameAt = 0;
  var watchdog = null;

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

  function setStatus(text, kind) {
    var el = document.getElementById('status');
    if (!el) return;
    el.textContent = text;
    el.className = kind || '';
  }

  function updateButtons() {
    var b1 = document.getElementById('btnConnect');
    var b2 = document.getElementById('btnRelease');
    if (b1) b1.textContent = connected ? '断开' : '连接蓝牙（桥接）';
    if (b2) b2.disabled = !connected;
  }

  function connect() {
    if (es) return;
    setStatus('桥接中…', '');
    es = new EventSource('/events');

    es.onopen = function () {
      connected = true;
      setStatus('已连接', 'on');
      updateButtons();
      startWatchdog();
    };

    es.onmessage = function (e) {
      frameCount++;
      lastFrameAt = Date.now();
      var s;
      try { s = JSON.parse(e.data); } catch (err) { return; }
      for (var i = 0; i < handlers.length; i++) {
        try { handlers[i](s); } catch (err) { console.error('帧回调出错', err); }
      }
    };

    es.onerror = function () {
      setStatus('桥接断开，正在重试…', 'err');
      connected = false;
      updateButtons();
    };
  }

  function disconnect() {
    if (es) { es.close(); es = null; }
    connected = false;
    stopWatchdog();
    setStatus('未连接');
    updateButtons();
  }

  function startWatchdog() {
    stopWatchdog();
    watchdog = setInterval(function () {
      if (!connected) return;
      if (lastFrameAt && Date.now() - lastFrameAt > 1500) {
        setStatus('已连接（无数据，检查板子）', 'err');
      } else if (lastFrameAt) {
        setStatus('已连接 · ' + frameCount + ' 帧', 'on');
      }
    }, 500);
  }

  function stopWatchdog() {
    if (watchdog) { clearInterval(watchdog); watchdog = null; }
  }

  function post(type, payload) {
    if (!connected) return Promise.resolve(false);
    return fetch('/send', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: type, data: payload })
    }).then(function (r) { return r.json(); })
      .then(function (j) { return !!j.ok; })
      .catch(function () { return false; });
  }

  function sendNote(note, on, keyId) {
    var flags = ((keyId & 0x07) << 1) | (on ? 1 : 0);
    return post(0x02, [note & 0x7F, flags]);
  }

  function sendRelease() {
    return post(0x03, []);
  }

  function onFrame(fn) {
    if (typeof fn === 'function') handlers.push(fn);
  }

  window.addEventListener('DOMContentLoaded', function () {
    var b1 = document.getElementById('btnConnect');
    var b2 = document.getElementById('btnRelease');
    if (b1) b1.addEventListener('click', function () {
      if (connected) disconnect(); else connect();
    });
    if (b2) b2.addEventListener('click', function () { sendRelease(); });
    updateButtons();
    // 默认自动连；加 ?auto=0 可只看界面不连（调试用）
    if (!/[?&]auto=0/.test(location.search)) connect();
  });

  window.Serial = {
    connect: connect,
    disconnect: disconnect,
    sendNote: sendNote,
    sendRelease: sendRelease,
    onFrame: onFrame,
    setStatus: setStatus,
    crc8: crc8
  };
})();
