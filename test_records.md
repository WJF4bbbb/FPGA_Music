# 测试记录

状态：部分A组模块已有独立仿真记录，见下方补充；下表为整机验收状态，尚未完成整机功能仿真、综合、上板和延迟测量。

| 项目 | 期望 | 实际/证据 | 状态 |
|---|---|---|---|
| 时钟 | 9拍半周期、576拍/帧 | 待填 | 未测试 |
| I2S | 位序、WS提前一位、左右一致 | 待填 | 未测试 |
| DDS | A4 FCW=40315426 @46875Hz | 待填 | 未测试 |
| 和弦 | >=4路同时独立发声 | 待填 | 未测试 |
| 释放/重按 | 不粘音、不误关、不漏事件 | 待填 | 未测试 |
| 控制维度 | 选音与音色独立、按住变调 | 待填 | 未测试 |
| 数值 | 无回绕、默认增益不持续削波 | 待填 | 未测试 |
| 延迟 | 标注起终点，最坏<=10ms | 待填 | 未测试 |
| 稳定性 | overflow/underrun=0，连续运行 | 待填 | 未测试 |
| STA/引脚 | 真实板卡约束，时序通过 | 待填 | 未测试 |

每条记录填写日期、代码提交号、工具/板卡版本、激励条件、测量图和结论。

## i2s_tx 独立集成仿真（2026-10-21）

- 接口：用户确认采用V1.1的sample/sample_valid/data和双缓存欠载处理。
- 命令、接口、测试范围及限制：[i2s_tx.md](i2s_tx.md)。
- 代码状态：本地未提交；工具：Icarus Verilog，-g2001 -Wall；测试平台tb_i2s_tx连接真实audio_timing。
- 实际结果：退出码0，PASS，独立接收模型还原120个完整双声道帧。
- 覆盖：8类补码样本、左右一致、位序、帧边界保护、同拍提交/装载、缺样保持、欠载恢复、计数饱和及运行中复位。
- 波形：sim/i2s_tx.vcd。未进行Gowin综合、STA或板测；整机验收表不因本次单模块测试标为通过。

## test_mode 独立自检（2026-10-21）

- 保留V1.1启动锁定接口，换模式通过共享复位，不采用大纲的热切换扩展端口。
- Icarus -g2001 -Wall编译无诊断，仿真退出码0；72次握手、7轮完整和弦，覆盖顺序、计时、背压和复位重启。
- 参数使用HOLD_FRAMES=2、RELEASE_FRAMES=1加速仿真；正式默认93750/11719。
- 本地未提交；详细命令和测试限制见[test_mode.md](test_mode.md)，波形sim/test_mode.vcd。
- 尚未完成Gowin综合、整机联调、板测或频谱采集。

## top A组阶段性集成（2026-10-21）

- 用户明确本轮仅处理A成员；B/C正式RTL未修改。
- 真实top/audio_timing/i2s_tx/test_mode，B/C只用tb_top内测试接口替身；有注入接线刺激。
- 4/8声部配置自检通过；覆盖复位与启动、模式锁定、事件路由/背压、总线打包和已完成样本至I2S路径。
- 本地未提交；命令、源列表和限制见[top.md](top.md)，波形sim/tb_top.vcd。
- 该结果不代表真实全机编译/算法验证；B/C及硬件约束仍待完成，未执行Gowin/板测/FFT或整机延迟验收。

## 首次push前A组复查（2026-10-21）

- 对照requirement/赛题要求.md原文（本地仓库外）与V1.1复查。当前仅适合作为A成员阶段性交付，不作为整机赛题验收版本。
- Icarus Verilog 14.0开发版，-g2001 -Wall：audio_timing 103帧、i2s_tx 120帧、test_mode 72次握手/7轮、备用clk_gen复位自检以及top 4/8路阶段测试均重新通过。
- 独立只读代码复查未发现阻止A阶段提交的RTL问题。补强tb_top逐声部gate/trigger、busy/env_done的非零移动刺激，避免常零替身掩盖接错。
- 临时副本反向验证：故意改错分频、发送位序、演示音号、样本有效接线、PLL复位释放阶段及busy/env_done反馈连接，6类错误均由对应自检报FAIL并返回非零。正式RTL未应用这些错误。
- Yosys对5个A模块执行hierarchy -check、proc、opt、check -assert，通用结构检查通过。B/C和PLL采用黑盒，仅验证结构；这不是Gowin器件综合、时序收敛或硬件验证。
- 真实sources.f全机编译仍因B/C未完成而失败，符合当前分工边界；不得把替身顶层PASS当成整机通过。
- 修正交付卫生：忽略sim/*.vvp与检查临时文件；增加shell脚本LF规则；交接说明另存docs/handoff.md，使其能随本仓库push。总目录原交接说明仍保留。
- .dide二进制缓存已被旧仓库跟踪且有本地变化，本次未撤销或暂存，提交时应排除。

## C 组单元仿真（2026-10-24）

- 负责人：C。模块：sensor_frontend / control_panel / note_event（rtl/ 下三个 RTL）。
- 工具：iVerilog（FPGAwars toolchain v1.1.1，Windows 版，已落地于 D:\iverilog\bin），-g2001 -Wall；仿真引擎 vvp。
  说明：C 组三个模块均为纯 RTL（无 Gowin IP 原语）。本机 Gowin EDA（V1.9.12.04）现已**授权可用**（gw_sh 不再报 License 错误）。但经核查，Gowin 功能（RTL）仿真依赖外部第三方仿真器（ModelSim/Questa 等），本安装未捆绑、gw_sh 也无仿真命令，故功能仿真仍用独立 iVerilog 完成；Gowin 在本机真正可无头跑的引擎是**综合**（GowinSynthesis.exe），已对三模块做综合冒烟，见下方"Gowin 综合"。
- 命令（交接 §6 的单元编译方式；脚本见仓库根 run_sim_c.bat / run_sim_c.sh，默认指向 D:\iverilog\bin，可用 IVL 环境变量覆盖）：
  `iverilog -g2001 -Wall -s tb_xxx -o sim/tb_xxx.vvp rtl/xxx.v tb/tb_xxx.v` 后 `vvp sim/tb_xxx.vvp`
- 实际结果（三套 tb 均 PASS，vvp 退出码 0，已生成 VCD）：
  - tb_sensor_frontend：8 路两级同步 + 滤波；T1 单键保持接受、T2 短于滤波的毛刺拒绝、T3 多键独立滤波无互掩；FILT 参数覆盖为 4（真实 5400 拍）以加速仿真。波形 sim/tb_sensor_frontend.vcd。
  - tb_control_panel：复位 gain=16384；timbre 单次切换（长按不重复）；bend 实时 ±2/0 电平编码；volume 单步 4096、高低端钳位无回绕；CTRL_FILT 覆盖为 4（真实约 27 万拍 @27MHz）。波形 sim/tb_control_panel.vcd。
  - tb_note_event：T1 复位释放即识别按下（prev 复位为 0，满足 V1.1 §2"复位释放时已按住的键识别为一次按下"）；T2 单键按下/松开；T3 同批先松后按再按 key_id 升序；T4 背压保持整条事件（ready=0 时不丢，valid 与字段保持）；T5 FIFO 满显式 overflow 计数、不静默丢弃。波形 sim/tb_note_event.vcd。
- 本日修复：note_event 原 DETECT&PUSH 在 FIFO 满丢弃事件后仍无条件推进 prev_key_state，会导致被丢弃的 note_off 永久丢失、下游声部状态永久错位。改为**位级 prev 更新**——仅成功 push 的 bit 推进 prev，满时未处理的 bit 下一拍自动重试，溢出只计数、不丢语义。修复后 T5 仍 PASS。
- 限制：以上为 C 组三个模块的独立单元仿真，**不是整机验收**；未接入 B 组/真实 top、未做 Gowin 综合/STA/板测、未测整机 ≤10ms 延迟；tb 中 FILT/CTRL_FILT 为加速参数，不等于正式滤波拍数。不得把单元 PASS 写成整机通过。
- 代码状态：本地未提交（git 仓库工作区，branch 待建）。提交前应先做 diff，避免夹带其他成员未提交文件。

## C 组 Gowin 综合冒烟（2026-10-24）

- 工具：Gowin EDA V1.9.12.04，综合引擎 `IDE/bin/GowinSynthesis.exe`（命令行，license 现已生效）。
  器件：Tang Nano 20K = **GW2A-LV18PG256C8/I7**（GW2A-18，PBGA256，C8/I7；器件库确认）。约束：功能综合无需引脚/时序约束，未用 `constraints/top.cst`、`top.sdc`（二者仍是空模板，handoff 已说明）。
- 命令（每模块单独作为顶层综合，纯 RTL 直接吃源文件）：
  `GowinSynthesis.exe -i rtl/<m>.v -top <m> -pn GW2A-LV18PG256C8/I7 -verilog_language verilog-2001 -o syn_out/<m>.edf`
- 实际结果：三模块**均 EXIT=0、0 错误、0 警告**，生成 EDF 网表 + 报告（syn_out/）；note_event 正确识别并提取 3 块 RAM（fifo_key/fifo_note/fifo_on，32 深，最终以分布式/LUT-RAM 实现，BSRAM 占用 0）。
- 资源占用（GW2A-18 总量 20736 LUT / 15552 Reg，占比均 <10%）：

  | 模块 | Reg(FF) | LUT | ALU | BSRAM | I/O |
  |---|---|---|---|---|---|
  | sensor_frontend | 128 | 232 | — | 0 | 18 |
  | control_panel | 121 | 212 | — | 0 | 29 |
  | note_event | 376 | 1878 | 44 | 0 | 55 |

- 结论：三模块在 Gowin 器件库下可综合、无推断锁存器、无未约束时钟告警；iVerilog 功能 PASS 与 Gowin 综合 PASS 相互印证。注意这是**模块级综合冒烟**，不是整机综合/布局布线/STA；整机综合仍需等 B/C 完成、A 迁移 sources.f 与 top、并补齐真实引脚/时序约束后方可进行。
- 代码状态：本地未提交；syn_out/ 产物为综合中间文件，建议加入 .gitignore 或提交前排除。
