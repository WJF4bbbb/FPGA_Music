/* Shared, dependency-free decoder for FPGA capture protocol version 1. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.WaveProtocol = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  function crc8(bytes) {
    var c = 0;
    for (var i = 0; i < bytes.length; i++) {
      c ^= bytes[i];
      for (var b = 0; b < 8; b++) c = ((c & 128) ? (c << 1) ^ 7 : c << 1) & 255;
    }
    return c;
  }
  function Assembler() { this.reset(); }
  Assembler.prototype.reset = function () { this.capture = null; };
  Assembler.prototype.push = function (payload) {
    var p = payload, fail = function (self) { self.reset(); return null; };
    if (!p || p.length < 14 || p.length > 252 || p.length % 2) return fail(this);
    var version = p[0], flags = p[1], id = p[2] | p[3] << 8;
    var total = p[4] | p[5] << 8, offset = p[6] | p[7] << 8;
    var rate = (p[8] | p[9] << 8 | p[10] << 16 | p[11] << 24) >>> 0;
    var count = (p.length - 12) / 2;
    if (version !== 1 || flags > 1 || total !== 512 || rate !== 46875 || offset >= total ||
        offset % 120 !== 0 || count !== Math.min(120, total - offset)) return fail(this);
    if (offset === 0) this.capture = {captureId: id, sampleRate: rate, triggered: !!flags, samples: []};
    var c = this.capture;
    if (!c || c.captureId !== id || c.sampleRate !== rate || c.triggered !== !!flags || c.samples.length !== offset) return fail(this);
    for (var i = 12; i < p.length; i += 2) {
      var n = p[i] | p[i + 1] << 8;
      c.samples.push(n >= 32768 ? n - 65536 : n);
    }
    if (c.samples.length !== total) return null;
    this.reset();
    return c;
  };
  // Byte-stream framing is independent of capture assembly and status decoding.
  function FrameDecoder(onFrame, onError) {
    this.onFrame = onFrame; this.onError = onError || function () {}; this.reset();
  }
  FrameDecoder.prototype.reset = function () { this.state = 0; this.data = []; this.type = 0; this.len = 0; };
  FrameDecoder.prototype.push = function (bytes) {
    for (var i = 0; i < bytes.length; i++) {
      var b = bytes[i];
      switch (this.state) {
        case 0: if (b === 170) this.state = 1; break;
        case 1: if (b === 85) this.state = 2; else if (b !== 170) this.state = 0; break;
        case 2: this.type = b; this.state = 3; break;
        case 3: this.len = b; this.data = []; this.state = b ? 4 : 5; break;
        case 4: this.data.push(b); if (this.data.length === this.len) this.state = 5; break;
        case 5:
          var type = this.type, data = this.data;
          var ok = crc8([type, this.len].concat(data)) === b;
          this.reset();
          if (ok) this.onFrame(type, data); else this.onError();
          break;
      }
    }
  };
  function isCapture(w) {
    return !!w && Number.isInteger(w.captureId) && w.captureId >= 0 && w.captureId <= 65535 &&
      w.sampleRate === 46875 && typeof w.triggered === 'boolean' && Array.isArray(w.samples) &&
      w.samples.length === 512 && w.samples.every(function (n) { return Number.isInteger(n) && n >= -32768 && n <= 32767; });
  }
  return {Assembler: Assembler, FrameDecoder: FrameDecoder, crc8: crc8, isCapture: isCapture};
});
