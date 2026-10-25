# C 组单元仿真指南（sensor_frontend / control_panel / note_event）

## 0. 重要前提
- 本仓库 `Desktop\Programmer\` 是 **Gowin Programmer（烧录工具）**，只能把 bit 流下到
  Tang Nano 20K，**不能做 RTL 行为仿真**。
- 本机 Gowin EDA（D:\Gowin\Gowin_V1.9.12.04_x64）已安装，但**尚未授权**：
  `IDE\bin\gw_sh.exe --help` 直接报 `License verification failed — File can not be opened`。
  在申请并放置 Gowin license 之前，其 Gowin Simulator / gw_sh 都无法运行。
- 当前整机**不可综合/不可真机验收**：仓库 `top.v`、`sources.f` 仍是旧脚手架（例化了
  `clk_gen/key_scan/timbre_sel`，与 V1.1 的 `audio_timing/i2s_tx` 对不上），且 B 组模块尚未
  实现。下面只是 **C 组三个模块的单元仿真**，不是整机验收。
- C 组三个模块都是**纯 RTL（无 Gowin IP 原语）**，因此用任何标准 Verilog-2001 仿真器都能
  验证。本环境实测用的是**独立 iVerilog**（见第 1 节），已把三套 tb 全部跑成 PASS。

## 1. 用 iVerilog 跑（已验证，推荐）
iVerilog（FPGAwars toolchain v1.1.1，Windows 版）已落地在 `D:\iverilog\bin`，并把 vvp 一并打包。

方式 A — 一键脚本（仓库根目录）：
```
run_sim_c.bat        # Windows
bash run_sim_c.sh     # Git Bash / WSL
```
脚本默认指向 `D:\iverilog\bin`；若你的 iVerilog 在别处，用环境变量覆盖：
```
set IVL=C:\path\to\bin   # Windows
IVL=/path/to/bin bash run_sim_c.sh   # Linux/Mac
```

方式 B — 手动（单次一个 tb，按交接 §6 的单元编译方式）：
```
iverilog -g2001 -Wall -s tb_sensor_frontend -o sim/tb_sensor_frontend.vvp ^
         rtl/sensor_frontend.v tb/tb_sensor_frontend.v
vvp sim/tb_sensor_frontend.vvp
```
把 `sensor_frontend` 换成 `control_panel` / `note_event` 即可。tb 内 `FILT`/`CTRL_FILT` 被覆盖
成很小的值（4）以便快速跑完，不影响算法；正式滤波拍数为 5400（光电）与约 27 万（控制消抖）。

预期输出：全部通过打印 `PASS: tb_xxx all checks passed` 并以 `$finish` 结束（vvp 退出码 0）；
任一项失败打印 `FAIL ...`。每个 tb 还会生成 `sim/tb_xxx.vcd`，可用 GTKWave 打开看波形。

## 2. Gowin EDA（授权后可选，图形流程）
若你已激活 Gowin license，也可在 IDE 里跑（结果应与 iVerilog 一致）：
1. 打开 Gowin EDA IDE → `File → New → Project`，选 **Simulation**（行为仿真，无需绑器件时序）；
   若必选器件，Tang Nano 20K 对应 `GW2A-LV18PG256C8/I7`。
2. 加入 `rtl/sensor_frontend.v`、`rtl/control_panel.v`、`rtl/note_event.v` 以及要跑的
   `tb/tb_xxx.v`，把该 tb 设为 Simulation Top。
3. `Tools → Simulation` → 选 **Gowin Simulator** → Run，控制台看 `PASS/FAIL`。
> Gowin 命令行仿真需工程 + Tcl，各版本子命令有差异；图形流程最稳。

## 3. 没有 Verilog 仿真器时
已附 `tools/ref_c.py`：一份忠实镜像三份 Verilog 时序语义的 Python 行为模型 + 21 项断言，
任何有 Python 的机器上 `python3 tools/ref_c.py` 即可验证逻辑（输出 `ALL REFERENCE CHECKS
PASSED`）。它替代不了真实 Verilog 仿真签字，但能在无仿真器时确认算法/时序正确。

## 4. C 组模块交付清单
- `rtl/sensor_frontend.v`：8 路独立同步+5400 拍滤波；光电 0.2ms，多键同时。
- `rtl/control_panel.v`：5 键消抖（默认 ~10ms）+ 音色单次切换 + 音量 16384/步 4096/钳位 + 实时 bend(-2/0/+2)。
- `rtl/note_event.v`：32 深 FIFO，先松后按再按 key_id 排序，背压保持整条事件，溢出显式计数；
  位级 prev 更新保证 FIFO 满时不永久丢失 note_off（见 docs/test_records.md 2026-10-24）。
- `tb/tb_*.v`：对应单元自检（正常/边界/背压/复位/溢出），含 VCD dump。
- `sim/tb_*.vcd`：仿真波形（GTKWave 查看）。
- `run_sim_c.bat` / `run_sim_c.sh`：iVerilog 一键入口（默认 D:\iverilog\bin）。
- `tools/ref_c.py`：Python 参考验证。
- `docs/test_records.md`：真实仿真记录（2026-10-24 节）。
