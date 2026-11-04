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
  var waveHandlers = [];
  var connectionHandlers = [];
  var es = null;
  var connected = false;
  var frameCount = 0;
  var lastFrameAt = 0;
  var watchdog = null;
  var keepalive = null;

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
    var stream = new EventSource('/events');
    es = stream;

    es.onopen = function () {
      if (es !== stream) return;
      lastFrameAt = 0;
      frameCount = 0;
      connectionState(true);
      connected = true;
      setStatus('已连接', 'on');
      updateButtons();
      startWatchdog();
      startKeepalive();
    };

    es.onmessage = function (e) {
      if (es !== stream || !connected) return;
      frameCount++;
      lastFrameAt = Date.now();
      var s;
      try { s = JSON.parse(e.data); } catch (err) { return; }
      for (var i = 0; i < handlers.length; i++) {
        try { handlers[i](s); } catch (err) { console.error('帧回调出错', err); }
      }
    };

    es.addEventListener('wave', function (e) {
      if (es !== stream || !connected) return;
      var capture;
      try { capture = JSON.parse(e.data); } catch (err) { return; }
      if (!WaveProtocol.isCapture(capture)) return;
      waveHandlers.forEach(function (fn) { try { fn(capture); } catch (err) { console.error(err); } });
    });

    es.onerror = function () {
      if (es !== stream) return;
      lastFrameAt = 0;
      connectionState(false);
      setStatus('桥接断开，正在重试…', 'err');
      connected = false;
      updateButtons();
      stopKeepalive();
    };
  }

  function disconnect() {
    if (es) { es.close(); es = null; }
    connected = false;
    lastFrameAt = 0;
    frameCount = 0;
    connectionState(false);
    stopWatchdog();
    stopKeepalive();
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

  // ---- 保活心跳 ----
  // 板子的 bt_cmd_parse 有一条保护：蓝牙接管后连续 2 秒收不到任何字节，就判定
  // "网页那边断了"，把控制权还给触摸板；而 top.v 在交还的那一拍会把所有正在响
  // 的音清零。两条凑一起，结果就是「按住一个音超过 2 秒会被掐断」。
  // 这里每秒补一帧 type=0x00、长度 0 的合法帧：CRC 能过，但解析器不认识这个类型，
  // 直接忽略，只起到"我还活着"的作用，顺便把那个 2 秒计时器重置。
  // 旧固件（没有这条保护）同样会忽略它，所以对两种板子都安全。
  var KEEPALIVE_MS = 1000;

  function startKeepalive() {
    stopKeepalive();
    keepalive = setInterval(function () {
      if (connected) post(0x00, []);
    }, KEEPALIVE_MS);
  }

  function stopKeepalive() {
    if (keepalive) { clearInterval(keepalive); keepalive = null; }
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

  function connectionState(value) {
    connectionHandlers.forEach(function (fn) { try { fn(value); } catch (err) { console.error(err); } });
  }

  function onFrame(fn) {
    if (typeof fn === 'function') handlers.push(fn);
  }

  window.addEventListener('DOMContentLoaded', function () {
    var b1 = document.getElementById('btnConnect');
    var b2 = document.getElementById('btnRelease');

    // 最常见的错：直接双击 bridge.html，地址栏是 file:///C:/...
    // 这种页面里的 /events 会解析成 file:///events，永远连不上桥接服务。
    // 这里直接拦下来，把正确地址写在状态栏上，别再让人猜。
    if (location.protocol === 'file:') {
      setStatus('打开方式不对：先双击 web/桥接.bat，再访问 http://localhost:8765/web/bridge.html', 'err');
      if (b1) { b1.textContent = '请改用 localhost:8765 打开'; b1.disabled = true; }
      if (b2) b2.disabled = true;
      return;
    }

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
    onWave: function (fn) { if (typeof fn === 'function') waveHandlers.push(fn); },
    onConnection: function (fn) { if (typeof fn === 'function') connectionHandlers.push(fn); },
    setStatus: setStatus,
    crc8: crc8
  };
})();
