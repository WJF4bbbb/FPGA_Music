#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
C 组模块行为级参考模型（非综合，仅验证算法/时序语义）。

目的：本环境无法安装 iverilog，故用 Python 忠实镜像三份 Verilog 的
      NB(非阻塞) 时序语义，跑一组覆盖正常/边界/背压/溢出的测试。
      它通过 != RTL 签字；真实 RTL 仍需在 OSS CAD Suite 上跑 Verilog tb。

模型严格按 V1.1 (docs/interfaces.md) 与仓库内 rtl/*.v 的语义编写：
  - sensor_frontend: 2 级同步 + 每通道 5400 拍稳定滤波
  - control_panel : 5 键同步消抖 + 音色单切 + 音量钳位 + 实时 bend
  - note_event    : 32 深 FIFO，先松后按再按 key_id 排序，背压保持，溢出计数
"""
import sys

# ---------------------------------------------------------------------------
# sensor_frontend
# ---------------------------------------------------------------------------
class SensorFrontend:
    FILT_CYCLES = 5400
    CNT_W = 13
    def __init__(self):
        self.sync1 = 0
        self.sync2 = 0
        self.key_state = 0
        self.filt_cnt = [0]*8
    def reset(self):
        self.sync1 = 0; self.sync2 = 0; self.key_state = 0
        self.filt_cnt = [0]*8
    def clk(self, key_raw):
        # NB semantics: reads use start-of-cycle values; updates at end.
        s1 = key_raw & 0xFF
        s2 = self.sync1
        ks = self.key_state
        fc = list(self.filt_cnt)
        ks_next = ks
        for i in range(8):
            if ((s2 >> i) & 1) != ((ks >> i) & 1):
                if fc[i] == (self.FILT_CYCLES - 1):
                    ks_next = ks_next | (1 << i) if ((s2>>i)&1) else ks_next & ~(1<<i)
                    fc[i] = 0
                else:
                    fc[i] = fc[i] + 1
            else:
                fc[i] = 0
        self.sync1 = s1
        self.sync2 = s2
        self.key_state = ks_next & 0xFF
        self.filt_cnt = fc

# ---------------------------------------------------------------------------
# control_panel
# ---------------------------------------------------------------------------
class ControlPanel:
    CTRL_FILT = 270000
    VOL_STEP = 4096
    GAIN_RST = 16384
    GAIN_MAX = 65535
    def __init__(self):
        self.s1=self.s2=self.db=0
        self.cnt=[0]*5
        self.prev_timbre=self.prev_vup=self.prev_vdn=0
        self.timbre=0
        self.bend=0   # signed 4-bit in RTL; here plain int in {-2,0,2}
        self.gain=self.GAIN_RST
    def reset(self):
        self.s1=self.s2=self.db=0
        self.cnt=[0]*5
        self.prev_timbre=self.prev_vup=self.prev_vdn=0
        self.timbre=0; self.bend=0; self.gain=self.GAIN_RST
    def clk(self, timbre_key, bend_up, bend_down, vol_up, vol_down):
        raw = ((timbre_key&1)<<4)|((bend_up&1)<<3)|((bend_down&1)<<2)|((vol_up&1)<<1)|((vol_down&1)<<0)
        s1 = raw & 0x1F
        s2 = self.s1
        db = self.db
        cnt = list(self.cnt)
        db_next = db
        for k in range(5):
            if ((s2>>k)&1) != ((db>>k)&1):
                if cnt[k] == (self.CTRL_FILT - 1):
                    db_next = db_next | (1<<k) if ((s2>>k)&1) else db_next & ~(1<<k)
                    cnt[k] = 0
                else:
                    cnt[k] = cnt[k] + 1
            else:
                cnt[k] = 0
        # edge detections use OLD db / OLD prev (start-of-cycle values)
        timbre = self.timbre
        if ((db>>4)&1) and not self.prev_timbre:
            timbre = 1 if timbre==0 else 0
        gain = self.gain
        if ((db>>1)&1) and not self.prev_vup:
            gain = self.GAIN_MAX if gain > (self.GAIN_MAX - self.VOL_STEP) else gain + self.VOL_STEP
        elif ((db>>0)&1) and not self.prev_vdn:
            gain = 0 if gain < self.VOL_STEP else gain - self.VOL_STEP
        if ((db>>3)&1) and not ((db>>2)&1):
            bend = 2
        elif ((db>>2)&1) and not ((db>>3)&1):
            bend = -2
        else:
            bend = 0
        self.s1=s1; self.s2=s2; self.db=db_next
        self.cnt=cnt
        self.prev_timbre=(db>>4)&1
        self.prev_vup=(db>>1)&1
        self.prev_vdn=(db>>0)&1
        self.timbre=timbre; self.bend=bend; self.gain=gain

# ---------------------------------------------------------------------------
# note_event
# ---------------------------------------------------------------------------
class NoteEvent:
    DEPTH = 32
    AW = 5
    def __init__(self):
        self.head=0; self.tail=0; self.cnt=0
        self.prev=0
        self.fk=[0]*self.DEPTH; self.fn=[0]*self.DEPTH; self.fo=[0]*self.DEPTH
        self.overflow=0
    def reset(self):
        self.head=0; self.tail=0; self.cnt=0; self.prev=0
        self.fk=[0]*self.DEPTH; self.fn=[0]*self.DEPTH; self.fo=[0]*self.DEPTH
        self.overflow=0
    @staticmethod
    def midi(k):
        return [60,62,64,65,67,69,71,72][k]
    # combinational outputs
    def out(self):
        if self.cnt==0:
            return (0,0,0,0)  # valid,key,note,on
        return (1, self.fk[self.head], self.fn[self.head], self.fo[self.head])
    def clk(self, key_state, evt_ready):
        h=self.head; t=self.tail; c=self.cnt; pv=self.prev; dropped=0
        if c!=0 and evt_ready:
            h=(h+1)&0x1F; c=c-1
        change = (key_state ^ pv) & 0xFF
        if change!=0:
            for i in range(8):
                if ((change>>i)&1) and not ((key_state>>i)&1):  # release
                    if c < self.DEPTH:
                        self.fk[t]=i; self.fn[t]=self.midi(i); self.fo[t]=0
                        t=(t+1)&0x1F; c=c+1
                    else:
                        dropped+=1
            for i in range(8):
                if ((change>>i)&1) and ((key_state>>i)&1):     # press
                    if c < self.DEPTH:
                        self.fk[t]=i; self.fn[t]=self.midi(i); self.fo[t]=1
                        t=(t+1)&0x1F; c=c+1
                    else:
                        dropped+=1
            pv = key_state
        if dropped!=0:
            self.overflow += dropped
        self.head=h; self.tail=t; self.cnt=c; self.prev=pv

# ---------------------------------------------------------------------------
# test harness
# ---------------------------------------------------------------------------
fails = 0
def check(name, cond):
    global fails
    if cond:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name}")
        fails += 1

print("== sensor_frontend ==")
# raw held from reset: 2-stage sync + 5400 filter counts => registered ~5402 clk.
# "5400 拍滤波" = 5400 个稳定计数，同步另加 ~2 拍，故阈值取 >=5402。
sf = SensorFrontend(); sf.reset()
for _ in range(5400):
    sf.clk(0x01)
check("not yet pressed at 5400 (sync+filter latency)", sf.key_state==0x00)
for _ in range(50):
    sf.clk(0x01)
check("held key0 becomes pressed after filter (~5402)", sf.key_state==0x01)
# glitch < 5400 should be ignored: toggle for 100 cycles then release
sf2 = SensorFrontend(); sf2.reset()
for _ in range(5500): sf2.clk(0x02)   # key1 held -> pressed
for _ in range(100): sf2.clk(0x00)    # brief release glitch
check("100-cycle glitch ignored (still pressed)", sf2.key_state==0x02)
for _ in range(5500): sf2.clk(0x00)   # stable release
check("stable release after stable low", sf2.key_state==0x00)
# two keys simultaneously
sf3 = SensorFrontend(); sf3.reset()
for _ in range(5500): sf3.clk(0x05)   # key0+key2
check("two keys simultaneously", sf3.key_state==0x05)

print("== control_panel ==")
DEB = ControlPanel.CTRL_FILT + 10   # cover 2-stage sync + full debounce count
cp = ControlPanel(); cp.reset()
# timbre toggle once per press even with long hold
for _ in range(DEB): cp.clk(1,0,0,0,0)   # press timbre, wait debounce
check("timbre toggled to 1", cp.timbre==1)
for _ in range(DEB): cp.clk(1,0,0,0,0)   # keep holding -> no repeat
check("timbre no repeat on long hold", cp.timbre==1)
for _ in range(DEB): cp.clk(0,0,0,0,0)    # release
for _ in range(DEB): cp.clk(1,0,0,0,0)    # press again
check("timbre toggled back to 0", cp.timbre==0)
for _ in range(DEB): cp.clk(0,0,0,0,0)
# volume up clamp
cp2 = ControlPanel(); cp2.reset()
for _ in range(40):
    for _ in range(DEB): cp2.clk(0,0,0,1,0)  # vol_up press
    for _ in range(DEB): cp2.clk(0,0,0,0,0)  # release
check("volume clamps at max (no wrap)", cp2.gain==cp2.GAIN_MAX)
cp3 = ControlPanel(); cp3.reset()
for _ in range(40):
    for _ in range(DEB): cp3.clk(0,0,0,0,1)  # vol_down press
    for _ in range(DEB): cp3.clk(0,0,0,0,0)
check("volume clamps at min 0 (no wrap)", cp3.gain==0)
# bend level-based
cp4 = ControlPanel(); cp4.reset()
for _ in range(DEB): cp4.clk(0,1,0,0,0)  # bend_up only
check("bend = +2 when up only", cp4.bend==2)
for _ in range(DEB): cp4.clk(0,0,1,0,0)  # bend_down only
check("bend = -2 when down only", cp4.bend==-2)
for _ in range(DEB): cp4.clk(0,0,0,0,0)
check("bend = 0 when neither", cp4.bend==0)

print("== note_event ==")
ne = NoteEvent(); ne.reset()
# single press -> one on event, pop it
for _ in range(2): ne.clk(0x01, 0)   # key0 pressed
v,k,n,on = ne.out()
check("press key0 -> valid on event", v==1 and k==0 and n==60 and on==1)
ne.clk(0x01, 1)  # consume
check("after pop empty", ne.out()[0]==0)
# release -> off event
ne.clk(0x00, 1)
v,k,n,on = ne.out()
check("release key0 -> off event", v==1 and k==0 and n==60 and on==0)
ne.clk(0x00, 1)
# multiple simultaneous presses -> ascending key_id order
ne2 = NoteEvent(); ne2.reset()
ne2.clk(0x00,1)
ne2.clk(0b10100101,1)  # press keys 0,2,5,7
order=[]
while ne2.out()[0]:
    v,k,n,on = ne2.out()
    order.append((k,on)); ne2.clk(0b10100101,1)   # keep keys held during pops (no spurious change)
check("simultaneous presses sorted ascending key_id, all on",
      order==[(0,1),(2,1),(5,1),(7,1)])
# release-before-press ordering within one batch: key0 release, key1 press
ne3 = NoteEvent(); ne3.reset()
ne3.clk(0x03,1)        # start: key0,key1 pressed
ne3.clk(0x03,1)        # settle
ne3.clk(0x02,1)        # key0 release, key1 stays, key1 no change; only key0 changes -> off
v,k,n,on=ne3.out(); 
check("single release detected", v==1 and k==0 and on==0)
ne3.clk(0x02,1)
# backpressure: evt_ready=0 must hold the entry
ne4 = NoteEvent(); ne4.reset()
ne4.clk(0x01,0)        # press key0 but do not consume
v,k,n,on = ne4.out()
check("valid asserted under backpressure", v==1 and k==0 and on==1)
ne4.clk(0x01,0)        # still not consuming; key_state unchanged -> no new event
check("no duplicate while held & not consumed", ne4.cnt==1)
# overflow: saturate FIFO with 40 events, ensure overflow counted & no silent drop of offs
ne5 = NoteEvent(); ne5.reset()
# drive a pattern that pushes many changes; cycle key states to create events
pattern=[0x01,0x03,0x07,0x0F,0x1F,0x3F,0x7F,0xFF,0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,
         0xFF,0x00,0x0A,0x55,0xAA,0x33,0xCC,0x99,0x66,0x18,0x24,0x42,0x81,0x3C,0xC3,0x7E,0x81,0x42,0x24,0x18,0x66,0x99]
exp_events=0
for p in pattern:
    ne5.clk(p,0)   # never consume -> fills FIFO then overflow
    # count expected events (each bit change = one event)
# compute expected total events from pattern deltas
prev=0
for p in pattern:
    ch=prev^p
    exp_events += bin(ch).count("1")
    prev=p
check("overflow_count equals dropped events (>= DEPTH-1 dropped)", ne5.overflow == (exp_events - ne5.DEPTH) and ne5.cnt==ne5.DEPTH)
# ensure off events not silently dropped: total produced = overflow + in-FIFO
check("no silent loss: overflow + infifo == total events", ne5.overflow + ne5.cnt == exp_events)

print()
if fails==0:
    print("ALL REFERENCE CHECKS PASSED")
    sys.exit(0)
else:
    print(f"{fails} REFERENCE CHECK(S) FAILED")
    sys.exit(1)
