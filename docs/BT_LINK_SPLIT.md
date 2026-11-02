# 蓝牙链路 · 两人分工交接

> 一页纸看完。看完直接开工，不用开会。

---

## 1. 一句话

**两个分支，各改两个文件，互不重叠。`top.v` 已冻结，谁都不要动。**

---

## 2. 分支

| 分支 | 谁 | 做什么 |
|---|---|---|
| `feature/bt-in` | 队友 | **虚拟输入**：电脑键盘/网页 → 板子，用来选音 |
| `feature/bt-out` | 我 | **遥测回传**：板子 → 网页，显示按了哪个键、音高、音色、弯音 |

两个分支都从 `integration` 的 `d018ec8` 开出，起点完全相同。

---

## 3. 各自只改这几个文件

| 文件 | bt-in | bt-out |
|---|:---:|:---:|
| `rtl/uart_rx.v` | ✅ 填满 | — |
| `rtl/bt_cmd_parse.v` | ✅ 填满 | — |
| `rtl/uart_tx.v` | — | ✅ 填满 |
| `rtl/telemetry.v` | — | ✅ 填满 |
| `js/input.js` | ✅ 新写 | — |
| `js/display.js` | — | ✅ 新写 |
| `tb/tb_uart_rx.v` 等测试台 | ✅ 自己配 | ✅ 自己配 |

**这四个 `.v` 现在是空壳**（输出常量），能编译、能综合、能上板，只是不起作用。填充时**端口一个都不要改**，内部随便写。

---

## 4. 绝对不要碰（改了就会冲突）

```
rtl/top.v
gowin/MusicSynth_TangNano20K/src/MusicSynth_TangNano20K.cst
sources.f
index.html
js/serial.js
```

这五个已经由我改好并冻结。里面已经写好：
- `top.v` 的两个新端口、蓝牙信号、事件三选一、三个模块例化
- `cst` 的两行引脚约束
- `sources.f` 的四个新文件
- `index.html` 骨架、`js/serial.js` 串口收发

---

## 5. 硬件接线

| HC-05 针 | 接 FPGA | 排针位置 |
|---|---|---|
| TXD | 脚 77 | **J6-5** |
| RXD | 脚 85 | **J6-4** |
| VCC | 3V3 | J6-19 |
| GND | GND | J6-20 |

⚠️ **上电前用万用表量 HC-05 的 TXD 对 GND**，必须是 3.3V。如果是 5V，串一个 1kΩ + 2kΩ 分压，否则会打坏 FPGA。

---

## 6. 三个约定

### 6.1 串口参数

```
115200 bps，8 数据位，无校验，1 停止位，无流控
```

HC-05 出厂是 9600，**必须先用 AT 命令改**：
按住底板的 EN/KEY 键上电进入 AT 模式，串口助手发 `AT+UART=115200,0,0`，回 `OK` 即成功。

### 6.2 帧格式

**上行：板子 → 网页（20 字节，30 Hz 周期发送）**

| 偏移 | 内容 | 说明 |
|---:|---|---|
| 0 | `AA` | 帧头 1 |
| 1 | `55` | 帧头 2 |
| 2 | `01` | 类型 = 状态帧 |
| 3 | `14` | 长度 = 20 |
| 4~5 | `touch_keys` | 16 键位图，小端，bit0 = TP0 |
| 6 | `voice_note[0]` | 声部 0 的 MIDI 音号 |
| 7 | `voice_note[1]` | 声部 1 |
| 8 | `voice_note[2]` | 声部 2 |
| 9 | `voice_note[3]` | 声部 3 |
| 10 | `voice_gate` | 低 4 位，bit0 = 声部 0 正在响 |
| 11 | `timbre` | 0~3 |
| 12 | `bend` | 有符号 -2~+2，补码 |
| 13~14 | `master_gain` | 16 位小端 |
| 15~18 | `clip_count` | 32 位小端 |
| 19 | `CRC8` | 覆盖偏移 2~18 |

**下行：网页 → 板子（6 字节）**

| 偏移 | 内容 | 说明 |
|---:|---|---|
| 0 | `AA` | 帧头 1 |
| 1 | `55` | 帧头 2 |
| 2 | 类型 | `02` = 音符事件，`03` = 释放控制 |
| 3 | 数据 1 | 音符帧：MIDI 音号；释放帧：`00` |
| 4 | 数据 2 | 音符帧：`bit0`=1 按下/0 松开，`bit1~3`=键号 0~7；释放帧：`00` |
| 5 | `CRC8` | 覆盖偏移 2~4 |

### 6.3 CRC8

多项式 `0x07`，初值 `0x00`，不做反转，不异或输出。

Verilog：
```verilog
function [7:0] crc8;
    input [7:0] d;
    input [7:0] c;
    integer i;
    begin
        crc8 = c ^ d;
        for (i = 0; i < 8; i = i + 1)
            crc8 = crc8[7] ? ((crc8 << 1) ^ 8'h07) : (crc8 << 1);
    end
endfunction
```

JavaScript：
```js
function crc8(bytes) {
  let c = 0;
  for (const b of bytes) {
    c ^= b;
    for (let i = 0; i < 8; i++) c = (c & 0x80) ? ((c << 1) ^ 0x07) & 0xff : (c << 1) & 0xff;
  }
  return c;
}
```

两边必须逐字节一致，写完各自用 `[0x01,0x14,0x00,0x3C]` 对一次结果。

---

## 7. 蓝牙什么时候接管

`bt_owner` 信号（`bt_cmd_parse` 输出）：

- 收到**第一条合法音符命令** → 拉高，蓝牙接管，触摸板事件被丢弃
- 收到**释放控制命令**（类型 `03`）→ 拉低，交还触摸板

为什么要这样：避免网页和触摸板同时按同一个键，产生重复触发这种难查的 bug。

---

## 8. 合并步骤

```bash
# 1. 各自在自己分支上写、测、提交
git add rtl/uart_tx.v rtl/telemetry.v
git commit -m "[bt-out] 实现遥测打包与串口发送"

# 2. 推送自己的分支（不要推 integration）
git push -u origin feature/bt-out

# 3. 先做完的人先合并；另一个人先同步
git fetch origin
git merge origin/feature/bt-out   # 或先完成的那一方

# 4. 因为改的是不同文件，正常情况零冲突
```

**如果 Git 报冲突**，只可能是有人碰了第 4 节那五个文件。直接回滚那个文件：
```bash
git checkout --ours rtl/top.v
```

---

## 9. 自检要求（两个人都要满足）

1. `iverilog -g2005` 和 `-g2012` 两种模式编译 0 error
2. 自己的模块必须有 testbench，打印 `PASS` / `FAIL`
3. 合入前跑一遍 `tb/tb_top_integration.v`，必须仍然 PASS
4. 不改任何现有模块的行为（`osc` / `adsr` / `mixer` / `voice_alloc` / `ttp229_reader` 等）

---

## 10. 已知的坑

| 坑 | 说明 |
|---|---|
| `evt_valid` 必须等 `evt_ready` | 不等就撤销，`voice_alloc` 会漏事件，表现为"偶尔少一个音" |
| `telemetry` 必须先快照再发 | 边发边读实时信号，一帧里前后字节不同步，网页会跳 |
| 27 MHz 分频 | 115200 取 234 分频（误差 +0.16%），不要用 235 |
| HC-05 的 TXD 电平 | 必须量，5V 会烧 FPGA |
| 不要用 `#delay` | 那是仿真语法，综合不了 |
