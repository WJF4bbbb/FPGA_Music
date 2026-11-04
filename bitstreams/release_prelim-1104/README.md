# 初赛版比特流（prelim-1104）

**这个目录下的两个 `.fs` 是可以直接烧的成品，不需要再综合。**

> ⚠️ 注意区分：上一级目录 `bitstreams/MusicSynth_TangNano20K.fs` 是 10-31 的**基线**，
> 不含蓝牙、不含 4 音色。**别烧那个**，烧这个目录里的。

对应源码：`release/prelim-1104` 分支，commit 见 `manifest.json` 的 `SourceCommit`。

---

## 烧哪个

| 文件 | 什么时候用 | 烧录模式 |
|---|---|---|
| `MusicSynth_TangNano20K.fs` | **无线版**：4 声部 / 4 音色 / 蓝牙双向，串口走脚 85/77 接 HC-05 | **`-r 9`** exFlash，断电保留 |
| `MusicSynth_Wired.fs` | **有线版**：逻辑完全一样，串口改到脚 69/70（板载 BL616 USB 桥），插一根 Type-C 就能用，**不需要蓝牙模块** | **`-r 9`** exFlash |
| `at_cfg.fs` | 只用来把 HC-05 从 9600 改到 115200，一次性 | **`-r 2`** SRAM，断电清空 |

> 队友自测优先用**有线版**：不用配对、不用装驱动，插 Type-C 后在网页里点"连接串口"选 BL616 那个 COM 口即可。
> 无线版留给现场演示。

`at_cfg.fs` 一定要烧 **SRAM**：这样 flash 里原来的主固件不受影响，
配完 AT 拔电重插，板子自己就回去了，不会卡在 AT 配置模式。

---

## 主固件规格

| 项 | 值 |
|---|---|
| 器件 | GW2AR-LV18QN88C8/I7（Tang Nano 20K） |
| 时钟 | 27 MHz |
| 采样率 | 46.875 kHz |
| 声道 / 位深 | 2 / 16 bit |
| 声部 | 4 |
| 音色 | 0 正弦 / 1 方波 / 2 锯齿 / 3 三角（按音色键循环） |
| 逻辑 | 4992 / 20736（25%） |
| 寄存器 | 1626 / 15750（11%） |
| BSRAM | 4 / 46 |
| DSP | 6.5 / 24 |
| **Fmax** | **30.424 MHz**（约束 27 MHz） |
| TNS | Setup 0.000 / Hold 0.000，无违例 |

⚠️ **Fmax 余量 11.3%**。最差路径在 `note_event` 的按键 FIFO（slack 4.169 ns）。
再加功能要重新看这个数，跌破 27 MHz 就得上 PLL 或 BUFG。

---

## 这一版修了什么（相对 11-02 那版）

1. **关掉演示模式**（`top.v` 新增 `DEMO_ENABLE=0`）。脚 74 和配置 Flash 的 MSPI 共用，
   上电会被拉高，把 `test_enable` 顶起来 → 演示和弦**完整顶替**触摸板，
   表现为"恒音高一直响、按音符键没反应"。现在该参数钉死为 0，综合时
   `test_enable` 直接被优化成常量 0（报告里会有 `CV0016 unused` 警告，正常）。
2. **死锁看门狗**（`top.v`）：事件链卡住约 0.6 s 就强制复位三个模块，全音关断。
3. **蓝牙交还自动清音**（`top.v` `rel_hold`）：`bt_owner` 1→0 时把门控全清，
   网页漏发 note_off 也不会留恒音。
4. **蓝牙 owner 超时**（`bt_cmd_parse.v`）：2 s 收不到字节就自动交还触摸板。
5. `ttp229_reader.v` 只是把同一表达式提成 `frame_now` 并补注释，**逻辑没变**。

---

## 校验

```bash
sha256sum MusicSynth_TangNano20K.fs MusicSynth_Wired.fs at_cfg.fs
```

期望值写在 `manifest.json` 的 `Files.*.SHA256`。PowerShell：

```powershell
Get-FileHash ./MusicSynth_TangNano20K.fs -Algorithm SHA256
```

---

## 自己重新综合

不想用现成的，就自己编（在 `FPGA_Music` 目录下）：

```bash
# 无线版主固件（脚 85/77 接 HC-05）
gw_sh gowin/MusicSynth_TangNano20K/build_prelim.tcl

# 有线版主固件（脚 69/70 接板载 BL616）
gw_sh gowin/wired/build_wired.tcl

# AT 配置工具
gw_sh gowin/at_cfg/at_cfg.tcl
```

⚠️ **仓库路径里有中文会报 `EX5998`**，综合前先拷到纯 ASCII 路径，例如 `C:\gw_synth_bt`。
两个 `.gprj` 里的源码路径是相对 `../../rtl`，所以拷的时候 `rtl/`、`constraints/`、`gowin/` 要一起拷。

---

## 回归结果（2026-11-04）

`bash tools/run_all_tb.sh both`：

- RTL 在 `-g2005` / `-g2012` 两种模式下**都能编译**
- 模块级 + 链路级 testbench **全过**，包括烧板子前必跑的 `tb_ttp229_latency`
  和新加的 `tb_bt_chain`（7 个场景，含 type=03 交还）
- **3 个顶层 testbench 会报 FAIL，是断言过时，不是 RTL 有问题**：
  `tb_top` / `tb_top_board_inputs` / `tb_top_pa_enable` 还在断言
  "`test_enable=1` → `test_mode_latched=1`"。这一版故意把演示模式关死了，
  这个契约不再成立，所以它们红。要清红只需把这三处期望值改成 0。
- 另外 6 个顶层 testbench 在 `-g2005` 下编不过，是它们自己用了
  SystemVerilog 的 task 写法，只能在 `-g2012` 下编，属于历史遗留。

---

## AT 配置详细步骤

见 `docs/at_cfg.md`（接线、LED 判读、失败排查都在里面）。

一句话版：

1. 模块 `AT` 针 → 3V3（**上电前**接好），`TXD`→脚 77，`RXD`→脚 85，共地
2. 烧 `at_cfg.fs` 到 SRAM
3. 看 `led[4]` 常亮 = 成功
4. 断电，拔掉 `AT` 那根线，烧主固件到 flash，重新上电
