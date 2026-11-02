# 初赛版比特流（prelim-1104）

**这个目录下的两个 `.fs` 是可以直接烧的成品，不需要再综合。**

> ⚠️ 注意区分：上一级目录 `bitstreams/MusicSynth_TangNano20K.fs` 是 10-31 的**基线**，
> 不含蓝牙、不含 4 音色。**别烧那个**，烧这个目录里的。

对应源码：`release/prelim-1104` 分支，commit 见 `manifest.json` 的 `SourceCommit`。

---

## 烧哪个

| 文件 | 什么时候用 | 烧录模式 |
|---|---|---|
| `MusicSynth_TangNano20K.fs` | 正常演奏（4 声部 / 4 音色 / 蓝牙双向） | **`-r 9`** exFlash，断电保留 |
| `at_cfg.fs` | 只用来把 HC-05 从 9600 改到 115200，一次性 | **`-r 2`** SRAM，断电清空 |

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
| 逻辑 | 4804 / 20736（24%） |
| 寄存器 | 1635 / 15750（11%） |
| BSRAM | 4 / 46 |
| DSP | 6.5 / 24 |
| **Fmax** | **29.080 MHz**（约束 27 MHz） |
| TNS | Setup 0.000 / Hold 0.000，无违例 |

⚠️ **Fmax 余量只有 7.7%**。最差路径在 `note_event` 的按键 FIFO（slack 2.649 ns）。
再加功能要重新看这个数，跌破 27 MHz 就得上 PLL 或 BUFG。

---

## 校验

```bash
sha256sum MusicSynth_TangNano20K.fs at_cfg.fs
```

期望值写在 `manifest.json` 的 `Files.*.SHA256`。PowerShell：

```powershell
Get-FileHash ./MusicSynth_TangNano20K.fs -Algorithm SHA256
```

---

## 自己重新综合

不想用现成的，就自己编（在 `FPGA_Music` 目录下）：

```bash
# 主固件
gw_sh gowin/MusicSynth_TangNano20K/MusicSynth_TangNano20K.gprj   # 或在 IDE 里打开

# AT 配置工具
gw_sh gowin/at_cfg/at_cfg.tcl
```

⚠️ **仓库路径里有中文会报 `EX5998`**，综合前先拷到纯 ASCII 路径，例如 `C:\gw_synth_bt`。

---

## AT 配置详细步骤

见 `docs/at_cfg.md`（接线、LED 判读、失败排查都在里面）。

一句话版：

1. 模块 `AT` 针 → 3V3（**上电前**接好），`TXD`→脚 77，`RXD`→脚 85，共地
2. 烧 `at_cfg.fs` 到 SRAM
3. 看 `led[4]` 常亮 = 成功
4. 断电，拔掉 `AT` 那根线，烧主固件到 flash，重新上电
