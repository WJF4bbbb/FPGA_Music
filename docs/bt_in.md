# 蓝牙输入（bt-in）实现说明

> 分支：`feature/bt-in`　基线：`integration` `d018ec8`
> 分工见 [BT_LINK_SPLIT.md](BT_LINK_SPLIT.md)：本分支只做**虚拟输入**（网页 → 板子），
> 遥测回传（板子 → 网页）由 `feature/bt-out` 负责，两者改的文件不重叠。

---

## 1. 改了什么

| 文件 | 动作 | 说明 |
|---|---|---|
| `rtl/uart_rx.v` | 填满空壳 | 8N1 接收，端口未改 |
| `rtl/bt_cmd_parse.v` | 填满空壳 | `AA 55` 帧解析 → 音符事件，端口未改 |
| `web/js/input.js` | 扩展 | 虚拟键盘 + 节拍器 + 曲谱 + 判定 + 键位定义 + 录音 |
| `tb/tb_uart_rx.v` | 新增 | 串口接收自检 |
| `tb/tb_bt_cmd_parse.v` | 新增 | 帧解析自检 |
| `tb/tb_top_bt_in.v` | 新增 | 脚 77 进 → 声部起音的整机链路 |
| `tb/top_a_sources.f` | 补 4 行 | A 组清单补上四个蓝牙模块，`tb_top` 才能编译 |
| `tb/tb_top.v` | 一行 | `.uart_rx_pin(1'b1)`，避免悬空告警 |
| `tb/tb_top_board_inputs.v`、`tb_top_pa_enable.v` | 两行 | `.*` 通配需要 `uart_rx_pin` / `uart_tx_pin` 标识符 |

**没动**：`rtl/top.v`、`MusicSynth_TangNano20K.cst`、`sources.f`、`web/index.html`、
`web/js/serial.js`、`web/js/display.js`。引脚沿用脚手架已定的 **RX=77（J6-5）、TX=85（J6-4）**。

---

## 2. RTL

### 2.1 `uart_rx`

- 27 MHz / 115200 = 234.375，取 **234 分频**（误差 +0.16%）。10 位累计偏差不到 0.02 比特，采样点仍在中心。
- `rx` 先过两级同步，再检测下降沿；**起始位中心**再确认一次低电平，毛刺直接丢弃。
- 8 位 LSB first，采样点全部在比特中心。
- **停止位中心必须为高**，否则整字节丢弃、不拉 `valid`（帧错误保护）。

### 2.2 `bt_cmd_parse`

状态机：`S_H0 → S_H1 → S_TYPE → S_LEN → S_PL(0..8) → S_CRC`。

- CRC8（`0x07`，初值 0）覆盖**类型字节到数据末尾**，逐字节累积，收到 CRC 字节时直接比对。
- `type=0x02`、`len=2`：`data[0]`=MIDI 音号，`data[1].bit0`=按下/松开，`bit3:1`=键号。
- `type=0x03`、`len=0`：交还触摸板，`owner` 拉低。
- CRC 失败时若当前字节本身是 `AA`，回到 `S_H1`（把它当成下一帧的头），少丢一帧。
- `len > 8` 视为非法，丢弃重来。

**两个必须遵守的时序点**（`BT_LINK_SPLIT.md` 第 10 节也写了）：

1. `evt_valid` 用「**握手才清零**」写法，不是每拍默认清零。否则 `voice_alloc` 会漏事件，表现为偶发少一个音。
2. 收到第一条合法音符帧时 `owner` 和 `evt_valid` **同一拍**置位。下一拍 `bt_owner` 与 `bt_evt_valid` 同时可见，
   `top` 里 `bt_evt_ready = ... && bt_owner && evt_ready` 才成立，事件不会因为「还没接管」被丢掉。

---

## 3. 网页（`web/js/input.js`）

所有 DOM 与 CSS 都在 JS 里动态生成，选择器一律 `#inputPanel` 前缀，与 `display.js` 不冲突。

| 功能 | 做法 |
|---|---|
| 8 键虚拟键盘 | `Serial.sendNote(midi, on, keyId)`，鼠标/触摸/电脑键盘三种输入 |
| 键位定义 | 点琴键下方的小字 → 按任意电脑键绑定；存 `localStorage`；`复位键位` 恢复 A S D F G H J K |
| 移调 | −12…+12 半音，**发送时直接改写 MIDI 音号**。协议里 `note` 就是音号，所以移调不需要 FPGA 配合，也不用改 `serial.js` |
| 节拍器 | WebAudio，25 ms 轮询 + 音频时钟排程；强拍 1320 Hz、弱拍 880 Hz；BPM 30–240 |
| 曲谱 | 内置 5 首（小星星 / 欢乐颂 / 两只老虎 / 划船歌 / 玛丽有只小羊羔），可导入 `.mid` / `.json`，导出 `.mid` / `.json` |
| 节奏判定 | 播放时按键与谱面比对：PERFECT ≤60 ms、GREAT ≤100 ms、GOOD ≤160 ms、超过 220 ms 记 MISS；显示得分、准确率、连击 |
| 录音 | 记录本地按键（时间戳 + 键号 + 音号），可回放、导出标准 `.mid` |

### 移调为什么先松手

`cycleSemitone()` 先 `releaseAll()` 再改 `S.semitone`。
否则一个按旧音高起音的音符会用新音高发 note off，`voice_alloc` 按 `evt_key` 匹配不到，声音会卡住。

### 曲谱只有 8 键

`midiToKey()` 把任意 MIDI 音号吸到 C 大调白键上：C4→键0 … B4→键6，**C5 及以上→键7**（C4 不会被误判成键7）。
导入真实 MIDI 时只保留这 8 个音，所以请先用单声部、C 大调的旋律试。

---

## 4. 测试记录（2026-11-02，iVerilog 10.1）

| 测试 | 覆盖 | 结果 |
|---|---|---|
| `tb_uart_rx` | 6 组字节、背靠背 4 字节、毛刺、停止位为低、帧错误后恢复 | **PASS** |
| `tb_bt_cmd_parse` | CRC 标准答案 3 组、ON/OFF、键号 5、坏 CRC、帧前垃圾重同步、4 帧背靠背、非法长度、未知类型、释放帧、重新接管 | **PASS** |
| `tb_top_bt_in` | **脚 77 输入 → owner → 声部起音（60 / 71）→ 释放帧交还 → 触摸板恢复（62）→ 坏 CRC 不接管** | **PASS** |
| `tb_top` | A 组集成 | **PASS** |
| `tb_top_board_inputs` | 16 路触摸、音符/控制/保留通道 | **PASS** |
| `tb_top_input_polarity` | 两种极性、256 音符组合、32 面板组合 | **PASS** |
| `tb_top_pa_enable` | 5 组上电时序 | **PASS** |

`web/js/input.js` 离线自检（Node + 模拟 DOM）：脚本加载、面板渲染、按键发送参数、
移调、5 首曲谱合法性、MIDI 导出→导入（**5 首全部逐音一致**）、音号映射、判定窗口、
录音导出——**全部通过**。

### 综合（GowinSynthesis 1.9.12.04，GW2AR-LV18QN88C8/I7）

`uart_rx`、`bt_cmd_parse`、全量 `top` 均 **0 error / 0 warning**。

### 一个跑不起来的既有测试

`tb_top_integration` 在本机 iVerilog 10.1 上会在 `array.cc:906` 断言崩溃（vvp 直接异常退出，无任何 `$display` 输出）。
**未修改的 `integration` @ `d018ec8` 用同一个 tb 同样崩**，与本分支改动无关。
换 iVerilog 12+ 或在队友环境跑应当正常；本分支用 `tb_top_bt_in` + 四个轻量整机 tb 覆盖了同等范围。

---

## 5. 上板

| HC-05 | FPGA | 排针 |
|---|---|---|
| TXD | 脚 77 `uart_rx_pin` | J6-5 |
| GND | GND | J6-20 |
| VCC | 3V3 | J6-19 |
| RXD | 脚 85 `uart_tx_pin` | J6-4（本分支不用，留给 bt-out） |

⚠️ **上电前用万用表量 HC-05 的 TXD 对 GND**，必须是 3.3 V。若是 5 V，串 1k + 2k 分压，否则打坏 FPGA。

HC-05 出厂 9600，**先改波特率**：按住底板 EN/KEY 上电进 AT 模式，发 `AT+UART=115200,0,0`，回 `OK` 即成功。

### 验证顺序

1. **只接 TXD + GND**，网页点「连接蓝牙串口」，选配对后出现的**传出** COM 口。
2. 按一个琴键。板子应该发声，且`连接状态`变为已连接。
3. 再点「交还触摸板」，摸一下 TTP229，应该恢复由触摸板控制。
4. 最后再接 RXD（脚 85），给 bt-out 用。

### 网页打不开时

`file://` 被拦的话，在 `FPGA_Music` 目录执行 `python -m http.server 8000`，
浏览器访问 `http://localhost:8000/web/`。只支持桌面 Chrome / Edge。

---

## 6. 已知限制

- **不能回传**：本分支不碰 85 脚，网页看不到板子实际按了什么键。那部分由 `feature/bt-out` 做。
- **不做音色/音量/弯音的蓝牙控制**：协议里只有音符与释放控制两种帧（见 `BT_LINK_SPLIT.md` 第 12 节）。
- **一个八度、只有白键**：8 键就是 C4–C5 的白键，移调只能整体挪，不能改单个键的音高。
- **判定是网页侧时间**：用的是 `AudioContext.currentTime`，与 FPGA 之间隔着蓝牙延迟（典型 10–40 ms）。
  如果要把实体键也纳入判定，需要 bt-out 回传的硬件时间戳，这个分支没有做。
