#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hc05_setup.py —— HC-05 蓝牙串口模块配置助手

它干三件事：
  1. 自动找出模块在 AT 模式下用哪个波特率（不用你猜 38400 还是 9600）
  2. 打印模块当前的所有关键参数
  3. 加 --set 时把波特率改成 115200（FPGA 那边要的值）

用法：
  python tools/hc05_setup.py                     只列串口，不连
  python tools/hc05_setup.py --port COM5         只读检查，不改任何东西
  python tools/hc05_setup.py --port COM5 --set   改成 115200

前提：HC-05 已经进 AT 模式（指示灯慢闪，约 2 秒一次）。
      没进 AT 模式的话，本脚本会告诉你"没有响应"。
"""

import argparse
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("缺 pyserial，先执行：")
    print("    python -m pip install pyserial")
    sys.exit(1)

# HC-05 的 AT 模式波特率各家不同，按可能性从高到低试
CANDIDATE_BAUDS = [38400, 9600, 115200, 57600, 19200, 4800]
TARGET_BAUD = 115200


def list_serial_ports():
    ports = list(list_ports.comports())
    if not ports:
        print("没有找到任何串口。")
        print("  · USB-TTL 转接板插了吗？")
        print("  · 驱动装了吗？（CH340 / CP2102 要装对应驱动）")
        return []
    print("可用串口：")
    for p in ports:
        print("  %-8s %s" % (p.device, p.description))
    return ports


def send_cmd(ser, text, wait=0.4):
    """发一条 AT 命令，返回模块的回复文本。"""
    try:
        ser.reset_input_buffer()
    except Exception:
        pass
    ser.write((text + "\r\n").encode("ascii"))
    time.sleep(wait)
    n = ser.in_waiting
    raw = ser.read(n if n > 0 else 1)
    return raw.decode("ascii", "replace").strip()


def open_port(port, baud):
    try:
        return serial.Serial(port, baud, bytesize=8, parity="N",
                             stopbits=1, timeout=0.5)
    except Exception:
        return None


def detect_at_baud(port):
    """挨个波特率试 AT，谁回 OK 就是谁。"""
    for baud in CANDIDATE_BAUDS:
        ser = open_port(port, baud)
        if ser is None:
            return None, None
        reply = send_cmd(ser, "AT")
        if "OK" in reply.upper():
            return ser, baud
        ser.close()
    return None, None


def query(ser, command, label):
    reply = send_cmd(ser, command)
    one_line = " ".join(reply.split())
    print("  %-14s %s" % (label, one_line if one_line else "(无回复)"))
    return one_line


def main():
    ap = argparse.ArgumentParser(description="HC-05 配置助手")
    ap.add_argument("--port", help="串口号，例如 COM5")
    ap.add_argument("--set", action="store_true",
                    help="把波特率改成 %d" % TARGET_BAUD)
    ap.add_argument("--name", help="顺带改蓝牙名（可选），例如 FPGA-MUSIC")
    ap.add_argument("--pswd", help="顺带改配对码（可选），4 位数字")
    args = ap.parse_args()

    ports = list_serial_ports()
    if not args.port:
        print()
        print("下一步：用 --port 指定一个，例如")
        if ports:
            print("    python tools/hc05_setup.py --port %s" % ports[0].device)
        else:
            print("    python tools/hc05_setup.py --port COM5")
        return 0

    print()
    print("正在连接 %s，自动探测 AT 模式波特率……" % args.port)
    ser, baud = detect_at_baud(args.port)

    if ser is None:
        print()
        print("连不上。逐个排查：")
        print("  1. 模块进 AT 模式了吗？指示灯应该【慢闪，约 2 秒一次】")
        print("     有按钮的：按住 EN/KEY 再上电")
        print("     没按钮的：EN/KEY 脚接 3.3V 再上电")
        print("  2. TXD/RXD 接反了吗？（要交叉：模块 TXD 接转接板 RXD）")
        print("  3. 串口号对吗？是不是被别的软件占用了？")
        print("  4. 模块供电了吗？指示灯亮不亮？")
        return 1

    print("连上了，AT 模式波特率 = %d" % baud)
    print()
    print("当前参数：")
    version = query(ser, "AT+VERSION?", "固件版本")
    uart = query(ser, "AT+UART?", "串口参数")
    query(ser, "AT+NAME?", "蓝牙名")
    query(ser, "AT+PSWD?", "配对码")
    query(ser, "AT+ROLE?", "角色(0=从机)")

    if not args.set:
        print()
        print("以上只是读取，没有改动任何东西。")
        if TARGET_BAUD not in uart:
            print("注意：当前波特率不是 %d，FPGA 那边用的是 %d。" % (TARGET_BAUD, TARGET_BAUD))
            print("      要改的话加 --set 重跑一次。")
        else:
            print("波特率已经是 %d，和 FPGA 一致，不用改。" % TARGET_BAUD)
        ser.close()
        return 0

    print()
    print("开始修改……")

    if args.name:
        r = send_cmd(ser, "AT+NAME=%s" % args.name)
        print("  改名字 -> %s" % (" ".join(r.split()) or "(无回复)"))

    if args.pswd:
        r = send_cmd(ser, "AT+PSWD=%s" % args.pswd)
        print("  改配对码 -> %s" % (" ".join(r.split()) or "(无回复)"))

    r = send_cmd(ser, "AT+UART=%d,0,0" % TARGET_BAUD)
    print("  改波特率 -> %s" % (" ".join(r.split()) or "(无回复)"))

    # 改完模块可能立刻切到新波特率，重新探测一次确认
    ser.close()
    time.sleep(0.3)
    ser2, baud2 = detect_at_baud(args.port)

    print()
    if ser2 is None:
        print("改完之后连不上了。别慌，断电重启模块，再跑一次本脚本检查。")
        return 1

    print("现在 AT 模式波特率 = %d" % baud2)
    uart2 = query(ser2, "AT+UART?", "串口参数")
    ser2.close()

    print()
    if str(TARGET_BAUD) in uart2:
        print("成功！波特率已经是 %d,0,0（1 停止位，无校验）。" % TARGET_BAUD)
        print()
        print("接下来：")
        print("  1. 断电，把 EN/KEY 断开（或松开按钮）")
        print("  2. 重新上电 —— 指示灯变【快闪】= 已进入透传模式")
        print("  3. 接回 FPGA：模块 TXD -> 脚 77(J6-5)，RXD -> 脚 85(J6-4)")
        print("  4. Windows 里配对：设置 -> 蓝牙 -> 添加设备 -> HC-05 -> 配对码")
        return 0

    print("没确认成功，AT+UART? 的回复是：%s" % uart2)
    print("再跑一次本脚本看看，或者断电重启后重试。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
