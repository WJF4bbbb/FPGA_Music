# Sin ROM 综合诊断报告

日期：2026-10-26；工作目录 `F:\user\FPGA\FPGA_Music_integration`；分支 integration。

**最新源路径修复及复测见[第 10 节](#10-gowin-工程正式源路径修复与复测)。** 第 1–9 节保留上一轮 ROM 定点诊断；本轮进一步修改 .gprj，使 GUI 工程直接引用正式 RTL，未改变任何正式 RTL 或 src 副本。

## 验证步骤

- [x] 检查 Git 现有差异并保存已跟踪文件哈希，不覆盖原有修改。
- [x] 读取 osc/sin_rom/top/control_panel/mixer、正式源清单、SDC 和 GUI 综合配置。
- [x] 保存原始综合日志、网表及报告到 `sim/sin_rom_diagnostic.tmp/before_*`。
- [x] 比对正式整机网表的四份 ROM 初始化和地址/选择/输出链。
- [x] 复用振荡器测试，补齐原先缺少的 -1 半音检查；验证综合映射前后输出。
- [x] 运行真实整机回归与指定 Gowin 综合回归，记录实际退出码及警告数量。
- [x] 按证据判定是否需要正式 RTL 修复，补齐结论、范围和 Git 检查。

仅确认真实缺陷后才修改正式 RTL；不加 keep/dont_touch，不屏蔽警告，不改变波形分支或性能预算。

## 1. 结论及复现

本例属于任务中的 **A：层级模块被优化移除，但查表功能以其他形式保留**。没有发现正弦波功能丢失，不需要修改正式 RTL。

执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_gowin_synthesis.ps1
```

复测仍出现四条：

```text
WARN (NL0002): The module "sin_rom" instantiated to "u_sin_rom" is swept in optimizing("...rtl/osc.v":40)
GOWIN_TOP_SYNTHESIS_EXIT=0
```

关键证据不是退出码，而是生成网表中的 **四个 pROM、每份完整的 256×16 初始化、动态音色选择链**，以及官方原语模型下的逐地址/逐样本测试。本轮没有尝试让警告数量归零。

## 2. 源码和实际综合网表证据

| 检查点 | 实际证据 | 判断 |
|---|---|---|
| ROM 例化 | rtl/osc.v:35 的 `phase[31:24]` 接 addr，37–40 行 dout 接 lut_dout | 8 位地址与 signed 16 位数据一致 |
| 正弦分支 | osc.v:105 的 `2'd0: wave_of = sn`；126 行调用传入 lut_dout | ROM 输出确实参与波形计算 |
| 相位与有效数据 | osc.v:125–127 每次 frame_tick 推进 FCW、更新 wave_r 和 valid_r | 改音色/弯音不清相位 |
| ROM 数据 | sin_rom.v 是覆盖 0..255 的组合 case，含 default；没有 initial、外部 readmem 文件或未初始化存储数组 | 排除外部文件遗漏及初始化不支持 |
| 数值与符号 | 独立数学式 `round(32767*sin(2*pi*addr/256))` 与 256 项全部一致；四象限为 0000/7FFF/0000/8001 | 正负半周期与符号位完整 |
| 顶层接线 | top.v:115–118 为每个 osc 接同一 timbre/bend，各路 wave/valid 接自己的 ADSR，voice_samples/voice_valid 接 mixer，mixed_sample/mixed_valid 接 I2S | 四路真实音频链未断开 |
| 源清单 | sources.f 含 rtl/sin_rom.v；综合日志有 Analyzing/Compiling sin_rom；报告源文件表也列出该文件 | 排除漏编 ROM |
| GUI 工程 | MusicSynth_TangNano20K.gprj 和生成的 .prj 均包含 src/sin_rom.v；12 个 src RTL 及 SDC 与根目录对应文件逐字节一致 | GUI 未使用另一份 ROM 实现 |

正式 `sim/gowin_top.tmp/top.edf` 中没有名为 sin_rom 的模块，但存在：

| 声部 | 所在映射模块 | 实际 pROM 实例 | 当前网表起始行 |
|---|---|---|---:|
| 0 | osc | `\voices[0].wave_0_s8` | 33328 |
| 1 | osc_0 | `\voices[1].wave_0_s8` | 36319 |
| 2 | osc_1 | `\voices[2].wave_0_s8` | 39196 |
| 3 | osc_2 | `\voices[3].wave_0_s8` | 42150 |

每个实例的真实参数/接线如下：

```verilog
.AD({GND,GND,phase[31:24],GND,GND,VCC,VCC})
.CLK(clk_d), .CE(VCC), .OCE(GND), .RESET(GND)
// defparam: BIT_WIDTH=16; READ_MODE=0; RESET_MODE="SYNC"
// INIT_RAM_00..0F: 共 4096 位，即 256 个 16 位表值
```

报告资源统计为 **BSRAM=4、pROM=4**。工具审计逐项恢复每个 INIT_RAM 的低位优先 16 位字，与 RTL 及独立数学表全部一致：4×256=1024 项。GUI 的 .vg 网表也独立审计通过同样的 1024 项。

选择链也有实际网表证据。声部 0 的 `wave_0_s15`（32705 行附近）是 LUT3：I0 为 pROM 低位输出 `wave_0_12`，I1 为相位符号寄存，I2 为共享音色寄存 `\voices[3].wave_0_10`，INIT=8'h3A。当 I2=0 时该真值表输出 I0，即正弦表数据；I2=1 时选择方波相应位。共享选择寄存的 D 在 42045 行接 `timbre_Z[0]`，来自 u_control_panel，而不是常量。其他位和声部具有相应的选择链；输出端接真实 u_adsr 的 wave 位。

### 综合后的时序含义

本地官方 `IDE/simlib/gw2a/prim_sim.v:7417` 的 pROM 模型表明，READ_MODE=0 为单级时钟读出，未启用额外 OCE 输出流水级。综合器把组合查表与周围时序逻辑重新映射为 pROM 及选择/保持寄存器。因此不能仅看到层级名消失或 pROM 的时钟端口，就认定正弦被删或额外增加了有效样本延迟；本轮另用完整独立振荡器的映射网表逐拍比较验证了 valid 和有效样本。

## 3. 必须区分的既有功能范围

**振荡器支持四音色；当前正式面板只选择两音色。** rtl/control_panel.v:59 明确写为 `timbre <= (timbre == 0) ? 1 : 0`，docs/interfaces.md:229 也规定初版只用 0/1。因此其高位在整机综合中被传播为 0，锯齿/三角选择在当前 top 中不可由面板按键到达；正弦 0 和方波 1 都可动态到达。

这解释了整机映射中 timbre_Z 只有低位，以及部分波形逻辑被专门化；**不意味着正弦不可达，也不是此次 sin_rom 警告的缺陷原因**。独立 osc 的 timbre 为完整动态 2 位输入，四种音色已全部验证。本轮依照“正常优化则保留原代码”和“不改变已验证控制行为”的要求，没有擅自把面板从两态改为四态，也没有把独立四音色 PASS 写成整机按键四音色 PASS。若产品要求整机面板也选择四音色，需要另行统一接口规范、面板状态循环和对应单元/整机断言。

## 4. 本轮文件修改与取舍

| 文件 | 修改内容 |
|---|---|
| tb/tb_osc_timbre.v | 保留全部原断言，补齐此前缺少的 -1 半音频率检查 |
| tb/tb_osc_gowin_compare.v | 新增 RTL 与独立 Gowin 映射振荡器逐拍比较；检查有效样本、valid、相位推进/保持，覆盖四音色×五种 bend |
| tools/check_sin_rom_netlist.py | 新增实际综合网表初始化/地址参数审计，并从真实参数生成忽略目录中的官方原语扫描夹具 |
| docs/integration/Sin_ROM_Synthesis_Diagnostic_Report.md | 本报告 |

本轮所有正式 rtl/*.v、sources.f、SDC、综合脚本、整机 TB 和 GUI 源/配置均未修改。开始时已有的控制延迟修复、B/C 修复和其他未提交文件均保留。未添加 keep/dont_touch，未屏蔽警告，未用 ROM 存储风格强制替换正常推断。

## 5. 独立验证及失败检测

采用 OSS CAD Suite 同套 bin/lib，以及 Gowin V1.9.12.04 官方 gw2a/prim_sim.v，未编写替代 pROM 模型。

| 验证 | 实际结果 | 退出码 |
|---|---|---:|
| 现有 tb_osc_timbre（补 -1） | 四音色频率/幅度/连续性、±1/±2 半音、动态切换检查均 PASS (0 errors) | 0 |
| B 五项回归 | mixer / ADSR / voice_alloc / osc_timbre / tb_chain，ALL PASS (-g2012) | 0 |
| 正式 top 网表初始化审计 | 4 份 ROM ×256 表值，全部一致 | 0 |
| GUI .vg 初始化审计 | 4 份 ROM ×256 表值，全部一致 | 0 |
| 官方 pROM 模型逐地址扫描 | 从正式 top 实际参数生成夹具，1024 个输出全部匹配 | 0 |
| 独立完整映射 osc 与 RTL 比较 | 10248 个有效样本逐位一致，30208 周期检查通过 | 0 |
| 审计负向副本 | 仅 sim 副本中翻转一位初始化，实际报 ROM mismatch | **1（预期失败）** |

原测试实测：正弦幅度 −32767..32767，最大相邻步长 1608，无大跳变；方波 −32768..32767；锯齿 −32735..32746；三角 −32723..32766、无大跳变。C4 的 bend +2/−2/+1/−1 测得约 293.7/233.1/277.2/247.0 Hz，均满足原 2% 误差断言。

逐拍比较覆盖 timbre=0..3、bend=−2..+2，运行中切换 MIDI 60..72，不复位相位；包括连续 frame_tick、1..3 拍间隔和正式 576 拍间隔。比较的是 valid 和每个有效 wave；不要求综合器保持 valid=0 时内部无效数据的实现形式。相位检查在激励稳定后保存前值/当前 FCW，验证使能时仅加 FCW、非使能时保持。本比较是有限仿真，不声称完成形式等价证明或全整机综合网表时序仿真。

复现独立映射验证的准备和命令（均在仓库根目录）：

```powershell
$env:IVL='E:\app\software\oss-cad-suite\bin'
$env:PATH="$env:IVL;E:\app\software\oss-cad-suite\lib;$env:PATH"
$prim='E:/app/gowin/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw2a/prim_sim.v'
$synth='E:/app/gowin/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/GowinSynthesis.exe'
$py='C:/msys64/ucrt64/bin/python.exe'
$dir='sim/sin_rom_diagnostic.tmp'
New-Item -ItemType Directory -Force $dir | Out-Null
Set-Content -Encoding ASCII "$dir/osc_sources.f" @('rtl/osc.v','rtl/sin_rom.v')
& $synth -if "$dir/osc_sources.f" -top osc -pn GW2AR-LV18QN88C8/I7 -verilog_language verilog-2001 -global_freq 27 -o "$dir/osc_map.v"
if($LASTEXITCODE -ne 0){throw 'osc synthesis failed'}
$mapped=Get-Content -Raw -Encoding UTF8 "$dir/osc_map.v"
$mapped=[regex]::Replace($mapped,'\bmodule osc\s*\(','module osc_gowin (')
Set-Content -Encoding UTF8 "$dir/osc_gowin.v" $mapped
& "$env:IVL/iverilog.exe" -g2012 -s tb_osc_gowin_compare -o "$dir/compare.vvp" rtl/osc.v rtl/sin_rom.v "$dir/osc_gowin.v" tb/tb_osc_gowin_compare.v $prim
if($LASTEXITCODE -ne 0){throw 'comparison compile failed'}
& "$env:IVL/vvp.exe" "$dir/compare.vvp"
if($LASTEXITCODE -ne 0){throw 'comparison failed'}
& $py tools/check_sin_rom_netlist.py
if($LASTEXITCODE -ne 0){throw 'ROM audit failed'}
& "$env:IVL/iverilog.exe" -g2012 -s tb_sin_rom_mapped -o "$dir/sweep.vvp" "$dir/rom_sweep/tb_sin_rom_mapped.v" $prim
if($LASTEXITCODE -ne 0){throw 'ROM sweep compile failed'}
& "$env:IVL/vvp.exe" "$dir/sweep.vvp"
if($LASTEXITCODE -ne 0){throw 'ROM sweep failed'}
```

这里只给生成的独立映射模块改名以便同一仿真中并列例化；没有修改网表逻辑，也没有将生成文件加入正式 sources.f。

## 6. 本轮真实整机回归

实际重新执行 `run_integration.ps1`，编译退出 0、运行退出 0：

```text
PASS [A] reset/startup; shared reset and demo latch
PASS [B] four real voices, independent signed mix and demo releases
LATENCY key raw_event=5404 event_alloc=0 alloc_pcm=367 pcm_i2s_msb=601 total=6372 clocks (0.236000 ms)
PASS [C] single/two/four keys, FIFO batch order, steal, old off, retrigger, short pulse and release
LATENCY control raw_config=267003 config_pcm=839 pcm_i2s_msb=601 total=268443 clocks (9.942333 ms)
PASS [F-control] default control-to-I2S=268443 clocks <=270000; margin=1557 clocks
PASS [D] default 267000-cycle debounce; timbre, +/-2/0, gain and real audio propagation
PASS [E] external Philips I2S decoded=8847 stereo frames; exact produced PCM, 16-bit MSB-first, LR polarity, reset resync
PASS [F-key] default sensor raw-to-I2S <=10ms; max frame-to-PCM=2 clocks
RESULT assertions=3174265 functional=PASS performance_failures=0
PASS: tb_top_integration all checks passed
INTEGRATION_EXIT=0
SIN_ROM_INTEGRATION_EXIT=0
```

控制延迟 9.942333ms、余量 1557 拍，选音 0.236ms；均保持原先通过的结果。本轮没有修改 C RTL，未另重跑 C 单元；此前控制延迟任务的 C 三项退出 0 记录仍见 Control_Latency_Fix_Report.md。

## 7. 综合回归与警告对比

| 内容 | 诊断前保存的结果 | 本轮重新综合 |
|---|---|---|
| 工具 | GowinSynthesis V1.9.12.04 (89079) | 相同 |
| top / 器件 | top / GW2AR-LV18QN88C8/I7 | 相同 |
| NL0002 sin_rom 警告 | 4 | **4** |
| 实际 pROM / BSRAM 数 | 4 / 4 | **4 / 4** |
| 表数据 | 256×16，每声部各一份 | 每份逐项核对一致 |
| 本轮综合退出 | — | **0** |
| Clock Summary | 正式脚本设 27MHz | **27.000MHz / 37.037ns** |

新网表为 `sim/gowin_top.tmp/top.edf`（1063987 字节），新报告为 `sim/gowin_top.tmp/top_syn.rpt.html`，原始日志 `sim/gowin_top_synthesis.log`；带命令和退出码的完整控制台记录 `sim/sin_rom_gowin_regression.log`。文件名虽为 .edf，该版本引擎实际输出内容是 Verilog 技术映射网表（以 module/LUT/DFF/pROM 表达），已按其实际格式审计，未误按 EDIF 文法解读。

独立综合 osc 也产生相同警告一次，同时保留一个数据完整的 pROM；这进一步排除了“只有 top 漏接 ROM 才会出现此警告”的解释。

## 8. 尚未完成及工程差异

- **GUI 综合配置与正式脚本不同。** GUI 生成 .prj 的 global_freq=100.000，当前 GUI 报告 Clock Summary 为 100.000MHz/10ns；正式 run_gowin_synthesis.ps1 显式 global_freq=27 且传入 SDC，复测报告为 27.000MHz。GUI 工程虽然列入同内容 SDC，并不能仅凭文件存在宣称生效。此差异不是 ROM 警告根因；本轮未擅自修改 GUI 自动生成配置，后续 GUI 综合前应统一频率并核对实际报告。
- 正式面板只有 0/1 的既有协议与“四音色均可由整机按键选择”的更高要求存在范围差异，见第 3 节。锯齿/三角的独立功能已通过，未宣称整机面板可选择。
- 本轮未运行 P&R、完整 Setup/Hold 或板级播放测试，也未做 SDF 后仿真/全设计形式等价；综合与功能仿真结果不能替代这些验收。
- CST 真实接线、I/O 时序和完整同步器约束仍属此前尚未完成的板级工作。

## 9. 日志与 Git 保护

本轮日志：`sim/sin_rom_oscillator.log`、`sim/sin_rom_b_regression.log`、`sim/sin_rom_netlist_audit.log`、`sim/sin_rom_gui_audit.log`、`sim/sin_rom_sweep.log`、`sim/sin_rom_compare.log`、`sim/sin_rom_integration.log`、`sim/sin_rom_gowin_regression.log`。原日志/网表/报告副本及负向副本均保存在忽略目录 `sim/sin_rom_diagnostic.tmp/`。

开始时的已跟踪文件哈希快照 `sim/sin_rom_diagnostic.tmp/baseline.json` 核对显示，本轮已跟踪文件仅 tb/tb_osc_timbre.v 改变；正式 RTL 全部与本轮开始时一致。新增文件为第 4 节所列三份测试/诊断/报告文件。既有未提交修改及用户的 GUI 工程保留；未将 VVP/VCD、生成网表和报告纳入正式源清单或暂存区。未执行 commit、push、merge、reset 或切换分支。

最终执行 `git status --short --branch`，仍在 `integration...origin/integration`，存在此前工作及本轮测试/诊断文件的未提交修改；暂存区差异为空。`git diff --check` 与 `git diff --cached --check` 均实际退出 0。`git check-ignore` 确认本轮 VVP/VCD、top.edf/综合报告及 sim 临时夹具均已忽略。Python 第 252 行无行尾空白；现有 SVG XML 解析通过。

## 10. Gowin 工程正式源路径修复与复测

本节为随后执行的“解决 Gowin 工程使用旧 RTL 副本”任务，替代上文对当前工程引用路径的描述。上一轮结果保留供追溯，本轮没有更改正式 RTL。

### 10.1 修改前实际引用与差异

首先执行 `git status --short --branch`，确认仍为 integration，工作区存在既有未提交文件，暂存区没有差异。保存本轮正式 RTL、src 文件、SDC、sources.f、整机脚本及工程文件的哈希到 `sim/gowin_source_paths.tmp/baseline.json`；工程文件原文另存 before.gprj。没有 reset、clean、提交、推送或切换分支。

原工程为 `gowin/MusicSynth_TangNano20K/MusicSynth_TangNano20K.gprj`，所有文件 enable=1。File 的 path 相对于该 .gprj 所在目录解析，因此 **确实使用 src 独立副本**，不是根目录 rtl 的链接。

| 文件 | 修改前工程 path | 与正式文件逐字节对比 | 修改后工程 path |
|---|---|---|---|
| adsr.v | src/adsr.v | 相同 | ../../rtl/adsr.v |
| audio_timing.v | src/audio_timing.v | 相同 | ../../rtl/audio_timing.v |
| control_panel.v | src/control_panel.v | 相同 | ../../rtl/control_panel.v |
| i2s_tx.v | src/i2s_tx.v | 相同 | ../../rtl/i2s_tx.v |
| mixer.v | src/mixer.v | 相同 | ../../rtl/mixer.v |
| note_event.v | src/note_event.v | 相同 | ../../rtl/note_event.v |
| osc.v | src/osc.v | 相同 | ../../rtl/osc.v |
| sensor_frontend.v | src/sensor_frontend.v | 相同 | ../../rtl/sensor_frontend.v |
| sin_rom.v | src/sin_rom.v | 相同 | ../../rtl/sin_rom.v |
| test_mode.v | src/test_mode.v | 相同 | ../../rtl/test_mode.v |
| top.v | src/top.v | 相同 | ../../rtl/top.v |
| voice_alloc.v | src/voice_alloc.v | 相同 | ../../rtl/voice_alloc.v |
| top.sdc | src/top.sdc | 相同 | ../../constraints/top.sdc |

**本次检查没有发现任一同名文件内容不同。** 包括正式 CTRL_FILT=267000、既有 mixer/note_event 修复及 timescale 变更在内的当前内容，已经存在于这些副本中。因此不能把“四条警告仍存在”解释成“之前的修复未进入 GUI 综合”。实际问题是工程维护了第二份可漂移源码；即使本次内容相同，后续修改正式文件也不会自动更新副本。

旧 GUI 日志及网表的源路径确实指向 `.../gowin/MusicSynth_TangNano20K/src/osc.v`。完整比较记录保存于 `sim/gowin_source_paths.tmp/before_paths.txt`，旧 GUI .log/.prj/.vg/报告也复制到该忽略目录，未覆盖原件。

### 10.2 实施方案与修改范围

工程文件中的 12 条 Verilog 引用改为 `../../rtl/<文件名>`，唯一 SDC 改为 `../../constraints/top.sdc`。保留器件、文件类型、enable、顺序及其余 XML 内容，没有重复添加模块。工程目录和仓库可整体移动，路径仍相对有效。

解析修改后的实际 .gprj 并验证：

```text
PROJECT_SOURCE_AUDIT=PASS: 12 unique formal RTL; sin_rom once; 1 formal SDC; same set as sources.f
```

实际解析的 osc 文件为 `F:\user\FPGA\FPGA_Music_integration\rtl\osc.v`；sin_rom 同样直接解析到正式 rtl，且只出现一次。没有给副本写入任何内容；src 下全部文件仍保留，但不在该工程的活动源列表中。`sources.f`、正式 RTL、SDC 和 run_integration.ps1 也都未改。

本轮仅修改以下三处：

1. `gowin/MusicSynth_TangNano20K/MusicSynth_TangNano20K.gprj`：13 条源/约束路径。
2. `gowin/README.md`：说明正式源引用规则、历史副本保留及重新加载工程的方法。
3. 本报告：追加本节，并在开头链接到最新结果。

工程 before/after 的完整统一差异保存于 `sim/gowin_source_paths.tmp/project_paths.diff`。若 GUI 已经打开原工程，需要重新加载这个 .gprj，避免旧的内存文件树再次保存旧路径；本轮没有控制或关闭用户的 GUI 会话，也未删除其生成缓存。

### 10.3 实际综合方式与退出码

本环境调用 `gw_sh.exe -h` 时，初始化即报：

```text
alog error: failed to open log file: '<user-home>/AppData/Local/GowinSemi/IDE/cache/sh.log'
```

该次工具返回 0，但没有运行综合，因此没有将其记作成功。尝试将 LOCALAPPDATA 指向工作区的子进程环境也未改变该日志路径；没有修改用户目录、机器环境或 GUI 配置。

使用真实 GowinSynthesis 引擎完成替代验证：**从修改后的 .gprj 读取启用的 Verilog 和 SDC 引用，按工程目录解析绝对路径**，验证 12 条路径唯一且与 sources.f 的集合一致，然后写入忽略目录 `project_sources.f`。这份清单不是从旧的 GUI .prj 缓存复制，也不是绕过工程引用另选一套 RTL。

实际执行的核心综合命令为：

```powershell
& 'E:/app/gowin/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/GowinSynthesis.exe' `
  -if sim/gowin_source_paths.tmp/project_sources.f -top top `
  -pn GW2AR-LV18QN88C8/I7 -verilog_language verilog-2001 `
  -sdc constraints/top.sdc -global_freq 27 `
  -o sim/gowin_source_paths.tmp/project_top.vg
```

结果 **PROJECT_SOURCE_SYNTHESIS_EXIT=0**，实际生成：

- `sim/gowin_source_paths.tmp/project_top.vg`
- `sim/gowin_source_paths.tmp/project_top_syn.rpt.html`
- `sim/gowin_source_paths_synthesis.log`

新日志明确显示 Analyzing/Compiling 正式 `rtl/osc.v` 和 `rtl/sin_rom.v`。新网表源文件索引也全部为正式 RTL，检查不含 `MusicSynth_TangNano20K/src/`。因此本轮验证的是修复后的工程引用实际所指向的源码；不是只把 .gprj 写对后运行旧缓存。

本轮执行的是上述工程清单驱动的独立综合，**没有声称已在 GUI 界面点击重新综合**；GUI 原有 impl/.prj/.vg 报告未被冒充为新结果。独立综合显式使用 27MHz，报告 Clock Summary 为 27.000MHz/37.037ns。GUI 的原 Global_Freq=default 配置未改，其先前生成报告为 100MHz 的差异仍如第 8 节所述；本轮只修复源路径，不宣称两种综合入口的所有选项相同。

### 10.4 警告对比及新网表中的 ROM

| 证据 | 修改前 GUI 结果 | 修改后工程清单驱动综合 |
|---|---|---|
| sin_rom NL0002 数量 | 4 | **4** |
| 警告源码 | .../gowin/MusicSynth_TangNano20K/src/osc.v:40 | **.../rtl/osc.v:40** |
| pROM / BSRAM | 4 / 4 | **4 / 4** |
| 正式 ROM 数据核对 | 上轮已确认正确 | 新网表四份各 256 项，再次全部一致 |
| 官方原语模型扫描 | 上轮通过 | 新网表参数生成的 1024 项扫描再次通过、退出 0 |

本轮执行：

```powershell
C:/msys64/ucrt64/bin/python.exe tools/check_sin_rom_netlist.py `
  sim/gowin_source_paths.tmp/project_top.vg `
  --out sim/gowin_source_paths.tmp/rom_sweep
```

四个 `\voices[0..3].wave_0_s8` pROM 的 BIT_WIDTH=16、READ_MODE=0、phase[31:24] 地址连接及 INIT_RAM_00..0F 均正确。表值与 RTL 及独立正弦数学表完全匹配。随后用 OSS CAD Suite 重新编译该工具从新网表生成的扫描夹具，连接 Gowin 官方 `IDE/simlib/gw2a/prim_sim.v`，真实运行结果为：

```text
PASS: mapped pROM sweep 1024 words, official Gowin model
PROJECT_ROM_SWEEP_EXIT=0
```

因此，路径修复已进入实际综合输入，但四条警告仍然存在；**这四条警告本身是 sin_rom 层级被优化映射为 pROM，并不表示 ROM 从最终电路消失**。本轮继续保留正弦分支、动态音色输入、弯音及既有音频时序，没有加 keep/dont_touch 或屏蔽警告。完整功能路径分析见第 2 节。

### 10.5 回归验证

本轮在同套 OSS CAD Suite bin/lib 环境下重新执行 B 五项，mixer/ADSR/voice_alloc/osc_timbre/tb_chain 全部 PASS，SOURCE_PATH_B_EXIT=0。osc_timbre 覆盖正弦、方波、锯齿、三角，±1/±2 半音以及动态切换。正式面板仍遵守原 0/1 选择协议，不能把独立四音色验证误写成整机按键可选四音色；见第 3 节。

随后 `run_integration.ps1` 的本轮实际回归结束，结果如下（不是沿用上一轮日志）：

```text
PASS [A] reset/startup; shared reset and demo latch
PASS [B] four real voices, independent signed mix and demo releases
LATENCY key raw_event=5404 event_alloc=0 alloc_pcm=367 pcm_i2s_msb=601 total=6372 clocks (0.236000 ms)
PASS [C] single/two/four keys, FIFO batch order, steal, old off, retrigger, short pulse and release
LATENCY control raw_config=267003 config_pcm=839 pcm_i2s_msb=601 total=268443 clocks (9.942333 ms)
PASS [F-control] default control-to-I2S=268443 clocks <=270000; margin=1557 clocks
PASS [D] default 267000-cycle debounce; timbre, +/-2/0, gain and real audio propagation
PASS [E] external Philips I2S decoded=8847 stereo frames; exact produced PCM, 16-bit MSB-first, LR polarity, reset resync
PASS [F-key] default sensor raw-to-I2S <=10ms; max frame-to-PCM=2 clocks
RESULT assertions=3174265 functional=PASS performance_failures=0
PASS: tb_top_integration all checks passed
INTEGRATION_EXIT=0
SOURCE_PATH_INTEGRATION_EXIT=0
```

编译退出 0、运行退出 0、脚本退出 0；控制路径仍为 268443 拍（9.942333ms），比 270000 拍上限余 1557 拍。选音路径仍为 6372 拍（0.236ms）。没有删减断言或改动滤波/延迟验收参数。

### 10.6 最终保护检查、产物与使用范围

- `git status --short --branch`：仍为 integration...origin/integration，原有未提交工作保留；.gprj 原本即为未跟踪工程的一部分，本轮没有自动暂存。
- `git diff --check` 与 `git diff --cached --check` 均退出 0；暂存区差异为空。
- 对本轮开始时的哈希逐项复核：所有正式 RTL、所有 src 原文件、两份 SDC、sources.f 和整机脚本均未改变；只有明确授权的 .gprj 引用路径改变。额外修改仅为 README 与报告的追加说明。
- 不同文件中声明的模块名也检查无重复，共 12 个唯一模块；没有把任何生成网表、仿真器原语模型或 TB 加入正式工程。
- 未运行 P&R、完整 Setup/Hold 或板级测试。GUI 缓存初始化问题没有被描述为已修复，也没有将命令行 27MHz 结果冒充为 GUI 默认频率已改变。

本轮证据保存在忽略目录/日志：

| 产物 | 路径 |
|---|---|
| 旧/新路径逐项记录、工程原文及差异、保护快照 | sim/gowin_source_paths.tmp/{before_paths.txt,after_paths.txt,before.gprj,project_paths.diff,baseline.json} |
| 修改前 GUI 综合证据 | sim/gowin_source_paths.tmp/before_MusicSynth_TangNano20K.* |
| 新工程解析出的活动源清单 | sim/gowin_source_paths.tmp/project_sources.f |
| 新实际网表和报告 | sim/gowin_source_paths.tmp/project_top.vg、project_top_syn.rpt.html |
| 新实际综合日志 | sim/gowin_source_paths_synthesis.log |
| ROM 数据审计与官方原语扫描 | sim/gowin_source_paths_rom_audit.log、sim/gowin_source_paths_rom_sweep.log |
| B 组五项与整机回归 | sim/gowin_source_paths_b.log、sim/gowin_source_paths_integration.log |

后续维护应直接编辑 rtl/ 和 constraints/；src 副本只保留作历史核对。若需复查最新源码，可在重载 .gprj 后查看任一文件的完整路径；osc 与 sin_rom 均应落在正式 rtl 下。此方案不需要以后反复同步副本。
