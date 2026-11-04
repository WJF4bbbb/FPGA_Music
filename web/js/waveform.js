/* Display actual complete captures only. Digital full scale is 32768, never volts. */
(function () {
  'use strict';
  window.addEventListener('DOMContentLoaded', function () {
    var panel = document.getElementById('waveformPanel');
    if (!panel || !window.Serial || !Serial.onWave) return;
    panel.innerHTML = '<h2>FPGA 实测波形</h2>' +
      '<div class="waveformToolbar"><button id="waveformFreeze" type="button">冻结</button>' +
      '<label>幅度倍率 <select id="waveformScale" aria-label="波形幅度倍率">' +
      '<option value="0.5">×0.5</option><option value="1" selected>×1</option>' +
      '<option value="2">×2</option><option value="4">×4</option></select></label>' +
      '<span id="waveformStatus" role="status" aria-live="polite"></span></div>' +
      '<p class="waveformHint">纵轴：有符号归一化数字幅度（满量程 ±1）；横轴：时间 / ms</p>' +
      '<canvas id="waveformCanvas" role="img" aria-label="FPGA 音频样本波形"></canvas>' +
      '<div id="waveformMeta"></div>';
    var canvas = document.getElementById('waveformCanvas');
    var ctx = canvas.getContext('2d');
    var status = document.getElementById('waveformStatus');
    var meta = document.getElementById('waveformMeta');
    var freeze = document.getElementById('waveformFreeze');
    var scale = document.getElementById('waveformScale');
    var latest = null, shown = null, frozen = false, receivedAt = 0;
    var STALE_MS = 1500;

    function updateStatus() {
      var waiting = '等待新 FPGA 固件 / 实测波形数据';
      status.textContent = !latest ? waiting : (frozen ? '已冻结 · ' : '') +
        (Date.now() - receivedAt > STALE_MS ? '数据已过期，等待新采集' : '已收到 FPGA 实测数据');
      status.style.color = latest && Date.now() - receivedAt > STALE_MS ? 'var(--warn)' : 'var(--dim)';
    }

    function draw() {
      if (!ctx) return;
      var width = Math.max(180, canvas.getBoundingClientRect().width);
      var height = 240, dpr = window.devicePixelRatio || 1;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, height);
      var left = 44, right = width - 16, top = 18, bottom = height - 32;
      var middle = (top + bottom) / 2, half = (bottom - top) / 2;
      var multiplier = Number(scale.value) || 1;
      ctx.font = '11px system-ui';
      ctx.lineWidth = 1;
      ctx.strokeStyle = '#2c313a';
      ctx.fillStyle = '#8b93a1';
      ctx.textAlign = 'right';
      [1, 0.5, 0, -0.5, -1].forEach(function (level) {
        var y = middle - level * half;
        ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(right, y); ctx.stroke();
        ctx.fillText((level / multiplier).toFixed(2), left - 6, y + 4);
      });
      var duration = shown ? (shown.samples.length - 1) / shown.sampleRate * 1000 : null;
      for (var tick = 0; tick <= 4; tick++) {
        var x = left + (right - left) * tick / 4;
        ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, bottom); ctx.stroke();
        ctx.textAlign = tick === 0 ? 'left' : tick === 4 ? 'right' : 'center';
        ctx.fillText(duration === null ? (tick === 0 ? '0 ms' : '') : (duration * tick / 4).toFixed(2) + (tick === 4 ? ' ms' : ''), x, height - 10);
      }
      if (!shown) { meta.textContent = '512 点采集 · 等待完整数据'; return; }
      ctx.strokeStyle = '#3ddc97'; ctx.lineWidth = 1.5;
      ctx.save(); ctx.beginPath(); ctx.rect(left, top, right - left, bottom - top); ctx.clip();
      ctx.beginPath();
      shown.samples.forEach(function (sample, index) {
        var x = left + (right - left) * index / (shown.samples.length - 1);
        var y = middle - sample / 32768 * multiplier * half;
        if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      });
      ctx.stroke(); ctx.restore();
      meta.textContent = shown.samples.length + ' 点 · ' + shown.sampleRate.toLocaleString('en-US') + ' Hz · ' +
        duration.toFixed(2) + ' ms · #' + shown.captureId + ' · ' + (shown.triggered ? '过零触发' : '自由采集');
    }
    Serial.onWave(function (capture) {
      latest = capture; receivedAt = Date.now();
      if (!frozen) { shown = capture; draw(); }
      updateStatus();
    });
    if (Serial.onConnection) Serial.onConnection(function () {
      latest = null; shown = null; receivedAt = 0;
      draw(); updateStatus();
    });
    freeze.addEventListener('click', function () {
      frozen = !frozen; freeze.textContent = frozen ? '继续' : '冻结';
      if (!frozen) { shown = latest; draw(); }
      updateStatus();
    });
    scale.addEventListener('change', draw);
    window.addEventListener('resize', draw);
    if (typeof ResizeObserver !== 'undefined') new ResizeObserver(draw).observe(canvas);
    setInterval(updateStatus, 250);
    draw(); updateStatus();
  });
})();
