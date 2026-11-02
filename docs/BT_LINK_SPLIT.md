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
| `web/js/input.js` | ✅ 填满 | — |
| `web/js/display.js` | — | ✅ 填满 |
| `tb/tb_uart_rx.v` 等测试台 | ✅ 自己配 | ✅ 自己配 |

**这四个 `.v` 现在是空壳**（输出常量），能编译、能综合、能上板，只是不起作用。填充时**端口一个都不要改**，内部随便写。

---

## 4. 冻结文件（这几处改了容易出问题）

```
rtl/top.v
gowin/MusicSynth_TangNano20K/src/MusicSynth_TangNano20K.cst
sources.f
web/index.html
web/js/serial.js
```

这五个已经由我改好并冻结。里面已经写好：
- `top.v` 的两个新端口、蓝牙信号、事件三选一、三个模块例化
- `cst` 的两行引脚约束
- `sources.f` 的四个新文件
- `web/index.html` 骨架（顶部状态栏 + 左右两块面板）
- `web/js/serial.js` 串口收发、帧解析、CRC8、三个对外函数

> 这五个的共同点：都是**密集的单行清单**（端口列表、引脚列表、文件列表、函数定义）。
> 两个人往同一段里插东西，容易产生"重复端口名 / 重复信号"这类**不报冲突但编不过**的问题。

### 关于 gprj：可以改，但没必要

`gowin/MusicSynth_TangNano20K/MusicSynth_TangNano20K.gprj` 是 Gowin 的工程清单，
**我已经把 4 个蓝牙模块登记好了（19 条），你不用再动。**

万一你新建了额外的 `.v` 想加进去，改了也不会坏事。实测过三种合并情况：

| 情况 | git 报冲突吗 | 合并后 | 会不会编不过 |
|---|:---:|---|:---:|
| 两边加的完全一样 | 不报 | 正确 | 不会 |
| 两边加的位置不同 | 不报 | 多几条重复条目 | **不会**（Gowin 自动去重，资源占用一分不差） |
| 各加各负责的文件 | 不报 | 多几条重复条目 | **不会**（同上） |

唯一会真冲突的是：**同一行被改成不同内容**（比如把某个 `<File>` 的 `enable` 从 `1` 改成 `0`）。

所以规则就一句：**随便改，合并后跑一次综合确认即可。**

**`web/js/input.js` 和 `web/js/display.js` 已经有一个能跑的最小版本**，
不是空白。你直接在它基础上加功能就行，不用从零写。

---

## 5. 硬件接线

我们手上的模块是 **6 针**：`STATE / RXD / TXD / GND / VCC / AT`。
比常见的 4 针版本多出 `STATE` 和 `AT`，这两个不是数据线，但决定了能不能进 AT 模式。

### 5.1 正常工作（透传模式）接线

| 模块针 | 接到哪 | 排针位置 | 说明 |
|---|---|---|---|
| **TXD** | FPGA 脚 77（`uart_rx_pin`） | **J6-5** | 模块发 → FPGA 收 |
| **RXD** | FPGA 脚 85（`uart_tx_pin`） | **J6-4** | FPGA 发 → 模块收 |
| **VCC** | 3V3 | J6-19 | 别接 5V |
| **GND** | GND | J6-20 | 必须共地 |
| **AT** | **悬空或接 GND** | — | 拉高会卡在 AT 模式，不透传数据 |
| **STATE** | 悬空（可选：接万用表/备用 IO） | — | 输出脚，连上手机后变高 |

`TXD`/`RXD` 是**交叉**接的：模块的 TXD 进 FPGA 的 RX，模块的 RXD 出 FPGA 的 TX。
接反了不会烧板子，只是完全没数据——这是最容易犯的错。

⚠️ **上电前用万用表量模块 TXD 对 GND**，必须是 3.3V。如果是 5V，串一个 1kΩ + 2kΩ 分压，否则会打坏 FPGA。

### 5.2 STATE 针能干什么

`STATE` 是模块的输出，不是输入：

- **未配对**：低电平（0V）
- **已配对连接**：高电平（3.3V）

它不参与我们的协议，但调试时很有用——网页上没数据时，先量 `STATE`：

- `STATE` 一直是 0 → 手机根本没连上，问题在蓝牙配对，不在 FPGA
- `STATE` 是 3.3V 但网页没数据 → 蓝牙通了，问题在串口参数或帧格式

这一根线能把"蓝牙问题"和"FPGA 问题"直接切开，省掉一半排查时间。
想看得更直观就把它接到一个空余 IO 上点亮 LED，不接也不影响功能。

### 5.3 AT 针：进 AT 模式靠它，不靠按板子上的键

`AT` 是模块的输入，作用相当于老版 HC-05 的 `EN`/`KEY`：

| AT 针电平 | 模块状态 | STATE 灯 |
|---|---|---|
| 低 / 悬空 | 透传模式（正常工作） | 快闪 / 常亮（看是否连上） |
| **上电瞬间为高** | **AT 模式（发 AT 命令）** | **慢闪，约 2 秒一次** |

所以改波特率的正确姿势是：**先把 AT 接 3V3，再给模块上电**，看到慢闪就说明进去了。
改完把 AT 断开（悬空或接 GND）再重新上电，回到透传模式。

⚠️ 别在正常工作时把 AT 一直拉高——模块会一直停在 AT 模式，数据一个字节都过不去。

如果拉高 AT 上电后 STATE 仍是快闪（没进 AT 模式），说明这块板子的 AT 针是电平采样而非上电锁存，
那就改成"上电后再把 AT 拉高、发一次 `AT` 看有没有回 `OK`"。

---

## 6. 三个约定

### 6.1 串口参数

```
115200 bps，8 数据位，无校验，1 停止位，无流控
```

HC-05 出厂是 9600，**必须先用 AT 命令改**：

```
AT+UART=115200,0,0
```

回 `OK` 就成功了。三个参数分别是：波特率 115200、停止位 0（=1 位）、校验 0（=无校验）。

**注意 AT 模式下的波特率是 38400，不是 9600**（9600 是 HC-06，两者不一样）。
所以串口助手要开 **38400 8N1**，进去改完再切回 115200。

### 6.1.1 没有 USB-TTL 怎么发 AT 命令

两条路，任选：

**路 A：用板载的 USB 转串口（推荐，不用买任何东西）**

Tang Nano 20K 板上那颗 BL616 已经把 USB 桥到了 FPGA 的 UART：

| 板上丝印 | FPGA 脚 | 在我们设计里的状态 |
|---|---|---|
| `BL616_UART_TX` → `PIN70_SYS_RX` | 脚 70 | **空闲** |
| `BL616_UART_RX` ← `PIN69_SYS_TX` | 脚 69 | **空闲** |

也就是 69/70 这两个脚我们没用，可以临时借来当"USB 转串口"用：

1. 把模块的 `TXD` 接到 FPGA **脚 69**，模块的 `RXD` 接到 FPGA **脚 70**
2. 写一个几十行的**透传顶层**（`uart_rx` 收到的字节原样丢给 `uart_tx`），烧进去
3. 电脑上开串口助手连板子的 COM 口，38400 8N1，发 AT 命令

⚠️ 这条路要先烧一个透传固件，改完 AT 之后**必须把原来的正式固件烧回去**，不然板子就是个 USB 转串口了。

**路 B：找个 USB-TTL 模块 / 或者用 Arduino 的 TX RX 顶一下**

任何能输出 3.3V TTL 串口的东西都行。注意电平必须是 3.3V，5V 的要分压。

### 6.1.2 改完之后怎么确认

改完 AT 参数后，把模块切回透传模式，**先别接 FPGA**，直接 USB-TTL 对电脑：

- 串口助手开 **115200**，发任意字符
- 模块的 TXD 会把同样的字符回显到电脑（前提是 RXD 和 TXD 短接到一起做自环，或者用手机连上后互发）

更快的确认办法是看 `STATE` 灯：手机蓝牙列表里能看到模块名字并配对成功 → `STATE` 变高 → 说明模块本身是好的，
剩下的问题只可能在 FPGA 侧的波特率或帧格式。

工具脚本 `tools/hc05_setup.py` 能自动试探 AT 波特率（依次试 38400/9600/115200/57600/19200/4800），
默认只读不改；加 `--set` 才会真的写 `AT+UART=115200,0,0`：

```bash
python tools/hc05_setup.py --port COM5              # 只读，看当前参数
python tools/hc05_setup.py --port COM5 --set        # 真的改成 115200
python tools/hc05_setup.py --port COM5 --name Synth --pswd 1234
```

### 6.2 帧格式

**统一格式**：`AA 55 | 类型 | 长度 | 数据... | CRC8`

`CRC8` 覆盖**类型字节到数据末尾**（不含帧头和 CRC 自身）。

**上行：板子 → 网页（20 字节，30 Hz 周期发送）**

| 偏移 | 内容 | 说明 |
|---:|---|---|
| 0 | `AA` | 帧头 1 |
| 1 | `55` | 帧头 2 |
| 2 | `01` | 类型 = 状态帧 |
| 3 | `0F` | 长度 = 15 |
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

**下行：网页 → 板子**

音符事件（7 字节）：

| 偏移 | 内容 | 说明 |
|---:|---|---|
| 0~1 | `AA 55` | 帧头 |
| 2 | `02` | 类型 = 音符事件 |
| 3 | `02` | 长度 = 2 |
| 4 | `note` | MIDI 音号 |
| 5 | `flags` | `bit0`=1 按下 / 0 松开，`bit1~3`=键号 0~7 |
| 6 | `CRC8` | 覆盖偏移 2~5 |

释放控制（6 字节，交还触摸板）：

| 偏移 | 内容 |
|---:|---|
| 0~1 | `AA 55` |
| 2 | `03` |
| 3 | `00`（长度 0） |
| 4 | `CRC8`（覆盖偏移 2~3） |

### 6.3 CRC8

多项式 `0x07`，初值 `0x00`，不做反转，不异或输出。覆盖**类型字节到数据末尾**。

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

JavaScript（已实现在 `web/js/serial.js`，直接用 `Serial.crc8(bytes)`）：
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

两边必须逐字节一致。**核对用的三个标准答案**（写完各跑一次，对不上就是实现有 bug）：

| 输入 | CRC8 |
|---|---|
| `[0x01, 0x0F]` | `0x38` |
| `[0x02, 0x02, 0x3C, 0x01]` | `0xF8` |
| `[0x03, 0x00]` | `0x3F` |

**完整帧示例**（拿来对波形最方便）：

```
按下 C4（note=0x3C, keyId=0, on=1）：
AA 55 02 02 3C 01 F8

松开 C4：
AA 55 02 02 3C 00 <CRC>

交还触摸板：
AA 55 03 00 3F

板子发来的一帧状态（4 声部全空闲）：
AA 55 01 0F 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 <CRC>
```

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

**如果 Git 报冲突**，只可能是有人碰了第 4 节那五个冻结文件，或者是 `gprj` 里
同一行被改成了不同内容。直接回滚那个文件：
```bash
git checkout --ours rtl/top.v
```

**如果综合报"找不到模块 `xxx`"**，不是冲突，是有人新建了 `.v` 但没登记 `gprj`。
在 `gprj` 里补一行即可（谁补都行，重复登记也无害）。

---

## 9. 自检要求（两个人都要满足）

1. `iverilog -g2005` 和 `-g2012` 两种模式编译 0 error
2. 自己的模块必须有 testbench，打印 `PASS` / `FAIL`
3. 合入前跑一遍 `tb/tb_top_integration.v`，必须仍然 PASS
4. 不改任何现有模块的行为（`osc` / `adsr` / `mixer` / `voice_alloc` / `ttp229_reader` 等）

一条命令跑完上面 1、2 两项（跳过最慢的 `tb_top_integration`）：

```bash
bash tools/run_all_tb.sh fast     # 约 3 分钟，-g2012
bash tools/run_all_tb.sh both     # 两种模式都跑
```

单独跑那个最慢的（整树 VCD，约 12 分钟）：

```bash
SRC=$(tr -d '\r' < sources.f | sed 's|^|./|')
iverilog -g2012 -I tb -s tb_top_integration -o sim/ti.vvp $SRC ./tb/ttp229_model.v tb/tb_top_integration.v
vvp sim/ti.vvp | tail -3
```

---

## 10. 已知的坑

| 坑 | 说明 |
|---|---|
| `evt_valid` 必须等 `evt_ready` | 不等就撤销，`voice_alloc` 会漏事件，表现为"偶尔少一个音" |
| `telemetry` 必须先快照再发 | 边发边读实时信号，一帧里前后字节不同步，网页会跳 |
| 27 MHz 分频 | 115200 取 234 分频（误差 +0.16%），不要用 235 |
| HC-05 的 TXD 电平 | 必须量，5V 会烧 FPGA |
| 不要用 `#delay` | 那是仿真语法，综合不了 |
| 音色改成 4 档后，旧 testbench 的波形模型会挂 | `tb_ttp229_latency.v` 已修（新增 `wave_of_model`）；`tb_top_integration.v` 只按 1 次音色键、只到 timbre=1，暂时安全，但**以后要是在里面多按几次音色键，得同步改它的波形期望值**（`tb_top_integration.v` 第 307 行那个 `if(dut.timbre==0)`） |

---

## 11. 怎么打开网页

**只支持桌面版 Chrome 或 Edge**。Firefox、Safari、手机浏览器全部不行（没有 Web Serial）。

**方式一：直接双击**

打开 `web/index.html`。如果顶部能点"连接蓝牙串口"并弹出串口列表，就直接用这个。

**方式二：起本地服务（方式一报错时用）**

浏览器对 `file://` 的串口权限有时会拦。这时在 `FPGA_Music` 目录下开一个终端：

```bash
python -m http.server 8000
```

然后浏览器访问 `http://localhost:8000/web/`。

**连接前必须先做的两件事：**

1. 电脑和 HC-05 完成蓝牙配对（Windows 设置 → 蓝牙 → 添加设备 → 输入配对码 `1234` 或 `0000`）
2. 配对成功后，设备管理器里会出现「蓝牙链接上的标准串行 (COMx)」

网页里点"连接蓝牙串口"时，选那个 COM 口。

**验证协议是否通**：连上后如果右边"实时状态"开始每帧刷新（音色、音量有数字），说明板子在正常发帧。
如果一直是 `—`，说明板子没在发，或者波特率不对。

---

## 12. 功能边界（先划清，避免做到一半发现要改架构）

**蓝牙这一期只做两件事：**

| 做 | 不做 |
|---|---|
| ✅ 虚拟音符输入（按下/松开，键号 0~7） | ❌ 蓝牙切音色 |
| ✅ 状态回传（键位图、音高、gate、音色、弯音、音量、削顶） | ❌ 蓝牙调音量 |
| | ❌ 蓝牙控弯音 |

**为什么不做音色/音量/弯音的蓝牙控制**：这三个在现有架构里是由 `control_panel` 读取 TP8~TP12 的**按键事件**来循环切换的，不是"直接设值"。要让蓝牙改它们，就得再改 `top.v` 的 `normalized_panel` 通路，等于第二次动架构。

初赛前不值得。想切音色就用触摸板的 TP8，那个已经能用。

**回传里带上 `timbre` / `bend` / `gain` 只是"让你看到当前值"，不是"让你改"。**

---

## 13. 网页怎么加功能而不冲突（重点看这节）

### 13.1 核心规则：不写 HTML，全部用 JS 动态生成

`web/index.html` 里只有两个空容器：

```html
<section id="inputPanel"></section>    ← input.js 独占
<section id="displayPanel"></section>  ← display.js 独占
```

**两个人都不改 `index.html`。** 所有 DOM 和 CSS 都在自己的 JS 里用 `createElement` 和 `appendChild` 生成 —— 现有代码已经是这个写法，照着加就行。

示例（在 input.js 里加一个音色按钮区）：

```js
function addTimbreBar(panel) {
  var bar = document.createElement('div');
  bar.className = 'timbre-bar';
  ['正弦','方波','锯齿','三角'].forEach(function (n, i) {
    var b = document.createElement('button');
    b.textContent = n;
    b.onclick = function () { /* 你的逻辑 */ };
    bar.appendChild(b);
  });
  panel.appendChild(bar);

  var css = document.createElement('style');
  css.textContent = '#inputPanel .timbre-bar{display:flex;gap:8px;margin-top:12px}';
  panel.appendChild(css);
}
```

这样两人各写各的 CSS，**类名都带 `#inputPanel` 或 `#displayPanel` 前缀**，永远不会互相覆盖。

### 13.2 唯一可能撞的地方

| 位置 | 会不会撞 | 怎么避免 |
|---|---|---|
| `index.html` | 🔴 会 | **谁都别改** |
| `serial.js` | 🔴 会 | **谁都别改** |
| `input.js` | 🟢 不会 | 只有 bt-in 碰 |
| `display.js` | 🟢 不会 | 只有 bt-out 碰 |
| CSS 类名 | 🟡 可能 | 统一加 `#inputPanel` / `#displayPanel` 前缀 |

`serial.js` 提供的三个函数已经够用，**不需要加新的**（因为不做音色/音量控制）。

### 13.3 如果确实需要新的串口命令

比如队友想加"一键播放旋律"。那**不要自己改 `serial.js`**，而是：

1. 在 `input.js` 里用 `Serial.sendNote()` 循环调用（最简单的做法，够用）
2. 如果真需要新命令类型，先跟我说，我改 `serial.js` 并同步给另一个人

---

## 14. 队友开工（两条命令）

分支**已经建好并推到远程**，不用自己开：

```bash
# 1. 拉取
git fetch origin

# 2. 切到自己的分支
git checkout feature/bt-in
```

切过去之后，脚手架、四个空壳、网页骨架、这份文档全都在里面。

**你只改这三个文件：**

```
rtl/uart_rx.v          ← 串口接收
rtl/bt_cmd_parse.v     ← 命令解析，产出音符事件
web/js/input.js        ← 虚拟键盘（已有最小版本，在此基础上扩展）
```

**自检命令**（改完必须跑，两条都过才能提交）：

```bash
# 编译
iverilog -g2005 -s top -o /tmp/t.vvp rtl/*.v

# 整机回归（必须仍然 PASS）
iverilog -g2012 -s tb_top_integration -o /tmp/tbi.vvp \
  tb/tb_top_integration.v tb/ttp229_model.v rtl/*.v
vvp /tmp/tbi.vvp | grep -E "PASS|FAIL"
```

**推自己的分支**（不要推 integration）：

```bash
git add rtl/uart_rx.v rtl/bt_cmd_parse.v web/js/input.js
git commit -m "[bt-in] 实现串口接收与命令解析"
git push origin feature/bt-in
```
