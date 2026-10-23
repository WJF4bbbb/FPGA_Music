# audio_timing Gowin 模块工程

本目录保留实际运行过的独立模块工程、流程配置及必要结果报告。
顶层为 `audio_timing`，不是整机 `top` 工程，也不代表已完成上板验证。

## 工程与复现

- 工具：Gowin EDA V1.9.12.04 (64-bit)，综合器 GowinSyn。
- 器件：GW2AR-18C，完整型号 GW2AR-LV18QN88C8/I7。
- 工程：`audio_timing/audio_timing.gprj`，输入路径均相对工程目录。
- 输入：`audio_timing/src/audio_timing.v`、`audio_timing/src/audio_timing.sdc`。
- 流程配置：`audio_timing/impl/audio_timing_process_config.json`。
  虽位于 `impl`，该文件保存顶层、综合器、语言及实现选项，故单独纳入版本管理。

在 Gowin IDE 中打开上述 `.gprj`，核对器件和顶层后运行 Synthesize；
需要复现布局布线时继续运行 Place & Route。工具会重新生成其余 `impl` 内容。
`.gprj.user` 只含个人界面与运行状态，不需要提交。

本次工程的源码快照与仓库 `rtl/audio_timing.v` 逐字节一致；
工程内 SDC 与 `constraints/audio_timing.sdc` 也逐字节一致。
保留原工程的 `src` 布局以对应原始报告；后续修改时应同步对应副本。
SDC 定义 `clk` 为 `sys_clk`，周期 37.037 ns，约 27 MHz。

## 已有 Gowin 结果

以下数据来自此次保存的原始报告，本次 Git 整理未重新运行 Gowin。

| 阶段 | 结果与证据 |
| --- | --- |
| 综合，2026-10-23 23:58:35 | 已完成；Logic 19（15 LUT、4 ALU），Register 11，Latch 0，BSRAM 0；详见 `audio_timing/impl/gwsynthesis/audio_timing_syn.rpt.html` |
| 布局布线，2026-10-24 00:03:58 | 已完成；资源、器件及输入见 `audio_timing/impl/pnr/audio_timing.rpt.txt` |
| 布局布线后时序 | `sys_clk` 为 27 MHz；报告的 setup/hold 违例端点均为 0；最差 setup slack 32.990 ns、hold slack 0.425 ns，Fmax 247.107 MHz；详见 `audio_timing/impl/pnr/audio_timing.tr` |

综合报告的 Constraints File 为 `---`，使用默认 100 MHz 分析时钟，
其中 Fmax 为 357.270 MHz；该阶段并未应用上述 27 MHz SDC。
布局布线报告明确读取了工程内 SDC，27 MHz 结果应以其时序报告为准。
该工程没有板级 CST，也没有输入/输出延迟约束；当前结果只覆盖这个独立模块
及报告中已分析的路径，不能当作整机接口或板级时序签核。
原始报告中保留的本机绝对路径仅用于记录当时输入，不是工程复现依赖。

## 仿真核对

2026-10-24 使用现有 `tb/tb_audio_timing.v` 分别核对仓库 RTL 和工程源码快照。
两者均通过 103 个完整帧、启动及两次运行中复位检查。
仿真输出放在工程外的隔离验证目录，没有覆盖已有波形或 `.vvp` 文件。

从仓库根目录可使用以下命令复现工程快照的测试：

```powershell
iverilog -g2001 -Wall -s tb_audio_timing -o sim/tb_audio_timing.vvp gowin/audio_timing/audio_timing/src/audio_timing.v tb/tb_audio_timing.v
vvp sim/tb_audio_timing.vvp
```

Windows 使用 OSS CAD Suite 时，应让同一套安装的 `bin` 和 `lib` 位于
当前进程 PATH 前端。本次工具退出异常在按该套工具的环境设置调整 PATH 后消失。

## 提交范围

仅保留工程、源码、SDC、流程配置和以上三份原始报告。
`.dide`、`.vvp`、波形、GTKWave 本机视图、`.gprj.user`、综合网表、
临时日志、PnR 数据库及 bitstream 由 `.gitignore` 排除；本地文件保留。
