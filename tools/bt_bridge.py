#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bt_bridge.py —— 绕过 Windows 的 COM 口，把 HC-05 的 RFCOMM 数据直接桥接给网页

为什么需要这个：
  Windows 只在配对那一瞬间做一次蓝牙服务查询。如果模块当时没准备好，
  就只拿到 GAP / Device Info，漏掉 Serial Port(0x1101)，
  于是系统永远不创建 COM 口，Web Serial 也就无从连接。

  但 RFCOMM 通道本身是通的（已实测能收到 AA 55 状态帧）。
  这个脚本直接连 RFCOMM，把帧解析成 JSON，用 SSE 推给浏览器。

用法：
  python tools/bt_bridge.py                          # 自动用默认地址
  python tools/bt_bridge.py --addr 00:25:5B:00:FF:01 --channel 1
  python tools/bt_bridge.py --scan                   # 扫描附近设备

  然后浏览器打开：  http://localhost:8765/web/bridge.html

只依赖 Python 标准库，不需要 pip install。
"""

import argparse
import json
import os
import socket
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from wave_protocol import WaveAssembler, FrameDecoder

AF_BTH = 32
BTPROTO_RFCOMM = 3

HEAD0 = 0xAA
HEAD1 = 0x55
TYPE_STATUS = 0x01
TYPE_NOTE = 0x02
TYPE_RELEASE = 0x03

DEFAULT_ADDR = None  # 不硬编码，靠 pick_addr() 从注册表自动读已配对设备
DEFAULT_CHANNEL = 1
DEFAULT_PORT = 8765


def crc8(data):
    c = 0
    for b in data:
        c ^= b
        for _ in range(8):
            c = ((c << 1) ^ 0x07) & 0xFF if (c & 0x80) else (c << 1) & 0xFF
    return c


def parse_status(d):
    return {
        "touchKeys": d[0] | (d[1] << 8),
        "notes": [d[2], d[3], d[4], d[5]],
        "gates": d[6] & 0x0F,
        "timbre": d[7],
        "bend": d[8] - 256 if d[8] > 127 else d[8],
        "gain": d[9] | (d[10] << 8),
        "clip": d[11] | (d[12] << 8) | (d[13] << 16) | (d[14] << 24),
    }


class Shared:
    def __init__(self):
        self.lock = threading.Lock()
        self.status = None
        self.wave = None
        self.wave_seq = 0
        self.seq = 0
        self.connected = False
        self.frames = 0
        self.bad = 0
        self.err = "尚未连接"
        self.sock = None
        self.sock_lock = threading.Lock()


S = Shared()


class BridgeParser:
    """Route CRC-checked status and complete captures into shared state."""
    def __init__(self, shared):
        self.shared = shared
        self.waves = WaveAssembler()
        self.decoder = FrameDecoder(self._frame, self._bad_crc)

    def reset(self):
        self.decoder.reset()
        self.waves.reset()
        with self.shared.lock:
            self.shared.wave = None

    def _bad_crc(self):
        self.waves.reset()
        with self.shared.lock:
            self.shared.bad += 1

    def _frame(self, ftype, payload):
        if ftype == TYPE_STATUS and len(payload) == 15:
            with self.shared.lock:
                self.shared.status = parse_status(payload)
                self.shared.seq += 1
                self.shared.frames += 1
        elif ftype == 0x10:
            capture = self.waves.push(payload)
            if capture is not None:
                with self.shared.lock:
                    self.shared.wave = capture
                    self.shared.wave_seq += 1

    def push(self, data):
        self.decoder.push(data)


def sse_event(data, event=None):
    prefix = ('event: ' + event + '\n') if event else ''
    return (prefix + 'data: ' + json.dumps(data) + '\n\n').encode('utf-8')


def reader_loop(addr, channel):
    parser = BridgeParser(S)

    while True:
        sock = None
        try:
            sock = socket.socket(AF_BTH, socket.SOCK_STREAM, BTPROTO_RFCOMM)
            sock.settimeout(15)
            S.err = "正在连接 %s 通道 %d ..." % (addr, channel)
            sock.connect((addr, channel))
            sock.settimeout(1.0)
            with S.sock_lock:
                S.sock = sock
            S.connected = True
            S.err = ""
            print("[bridge] RFCOMM 已连接 %s ch%d" % (addr, channel), flush=True)

            parser.reset()

            while True:
                try:
                    chunk = sock.recv(512)
                except socket.timeout:
                    continue
                if not chunk:
                    raise ConnectionError("对端关闭")

                parser.push(chunk)

        except Exception as e:
            S.connected = False
            S.err = "%s: %s" % (type(e).__name__, str(e)[:80])
            print("[bridge] 断开，2 秒后重连 -> %s" % S.err, flush=True)
        finally:
            parser.reset()
            with S.sock_lock:
                S.sock = None
            if sock is not None:
                try:
                    sock.close()
                except Exception:
                    pass

        time.sleep(2)


def send_frame(ftype, payload):
    with S.sock_lock:
        sock = S.sock
    if sock is None:
        return False
    body = bytes([ftype, len(payload)]) + bytes(payload)
    frame = bytes([HEAD0, HEAD1]) + body + bytes([crc8(body)])
    try:
        sock.sendall(frame)
        return True
    except Exception as e:
        print("[bridge] 发送失败: %s" % e, flush=True)
        return False


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("X-Accel-Buffering", "no")
            self._cors()
            self.end_headers()

            last_seq = -1
            # A newly opened/reconnected SSE stream waits for a fresh capture.
            with S.lock:
                last_wave_seq = S.wave_seq
            last_beat = time.time()
            try:
                while True:
                    with S.lock:
                        seq = S.seq
                        data = S.status
                        wave_seq, wave = S.wave_seq, S.wave
                    now = time.time()
                    if seq != last_seq and data is not None:
                        last_seq = seq
                        self.wfile.write(sse_event(data))
                        self.wfile.flush()
                    if wave_seq != last_wave_seq and wave is not None:
                        last_wave_seq = wave_seq
                        self.wfile.write(sse_event(wave, 'wave'))
                        self.wfile.flush()
                    if now - last_beat > 1.0:
                        last_beat = now
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
                    time.sleep(0.02)
            except (BrokenPipeError, ConnectionResetError, OSError):
                return
            return

        if path == "/info":
            body = json.dumps({
                "connected": S.connected,
                "err": S.err,
                "frames": S.frames,
                "bad_crc": S.bad,
            }).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self._cors()
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/":
            self.send_response(302)
            self.send_header("Location", "/web/bridge.html")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        super().do_GET()

    def do_POST(self):
        if self.path.split("?")[0] != "/send":
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n) if n else b"{}"
        ok = False
        try:
            cmd = json.loads(raw.decode("utf-8"))
            ok = send_frame(int(cmd.get("type", 0)), cmd.get("data", []))
        except Exception as e:
            print("[bridge] 命令解析失败: %s" % e, flush=True)

        body = json.dumps({"ok": ok}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)


def list_paired():
    """从注册表读已配对的蓝牙设备，返回 [(mac, name), ...]"""
    import winreg
    out = []
    path = r"SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices"
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path) as k:
            i = 0
            while True:
                try:
                    mac_hex = winreg.EnumKey(k, i)
                except OSError:
                    break
                i += 1
                if len(mac_hex) != 12:
                    continue
                name = ""
                try:
                    with winreg.OpenKey(k, mac_hex) as dk:
                        raw, _ = winreg.QueryValueEx(dk, "Name")
                        name = bytes(b for b in raw if b != 0).decode("utf-8", errors="ignore")
                except OSError:
                    pass
                mac = ":".join(mac_hex[j:j + 2].upper() for j in range(0, 12, 2))
                out.append((mac, name))
    except OSError as e:
        print("[bridge] 读配对列表失败: %s" % e)
    return out


def probe(mac, channel=DEFAULT_CHANNEL, timeout=6):
    """试着连一下，看这个地址是不是真的串口模块"""
    try:
        s = socket.socket(AF_BTH, socket.SOCK_STREAM, BTPROTO_RFCOMM)
        s.settimeout(timeout)
        s.connect((mac, channel))
        s.close()
        return True
    except Exception:
        return False


def pick_addr():
    """自动挑出蓝牙串口模块的 MAC"""
    devs = list_paired()
    if not devs:
        return None

    cands = [d for d in devs if "HC" in d[1].upper() or "BT" in d[1].upper()]
    if not cands:
        cands = devs

    print("[bridge] 这台电脑上已配对的蓝牙设备：")
    for i, (mac, name) in enumerate(cands, 1):
        mark = "  <== 像是串口模块" if "HC" in name.upper() else ""
        print("  %d) %-18s %s%s" % (i, name or "(无名)", mac, mark))

    if len(cands) == 1:
        print("[bridge] 只有一个候选，自动选用 %s" % cands[0][0])
        return cands[0][0]

    # 后台运行（没有终端可以输入）时，逐个试连，能连上的就用
    if not sys.stdin.isatty():
        for mac, name in cands:
            if probe(mac):
                print("[bridge] 试连成功，选用 %s (%s)" % (name, mac))
                return mac
        print("[bridge] 都连不上（模块没上电？），先试第一个: %s" % cands[0][0])
        return cands[0][0]

    try:
        n = input("[bridge] 用哪个？输入序号（直接回车 = 1）: ").strip()
        idx = (int(n) - 1) if n else 0
        if 0 <= idx < len(cands):
            return cands[idx][0]
    except Exception:
        pass
    return cands[0][0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--addr", default=None,
                    help="蓝牙模块 MAC，不填会自动扫描已配对设备让你选")
    ap.add_argument("--channel", type=int, default=DEFAULT_CHANNEL, help="RFCOMM 通道，默认 1")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT, help="HTTP 端口，默认 8765")
    ap.add_argument("--scan", action="store_true", help="只列出已配对设备，不启动服务")
    args = ap.parse_args()

    if args.scan:
        for mac, name in list_paired():
            print("  %-18s %s" % (name or "(无名)", mac))
        return

    addr = args.addr or pick_addr()
    if not addr:
        print("[bridge] 没找到已配对的蓝牙设备。")
        print("         先把模块和电脑配对，或者手动指定：")
        print("         python tools/bt_bridge.py --addr 00:25:5B:00:FF:01")
        sys.exit(1)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    t = threading.Thread(target=reader_loop, args=(addr, args.channel), daemon=True)
    t.start()

    httpd = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = "http://localhost:%d/web/bridge.html" % args.port

    print("=" * 56)
    print("  蓝牙桥接服务已启动")
    print("=" * 56)
    print("  目标模块: %s  通道 %d" % (addr, args.channel))
    print("  网页地址: %s" % url)
    print("  服务根目录: %s" % root)
    print("  按 Ctrl+C 停止")
    print("=" * 56, flush=True)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[bridge] 已停止", flush=True)


if __name__ == "__main__":
    main()
