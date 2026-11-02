# 当前正式工程的可移植入口

当前工程为 MusicSynth_TangNano20K/MusicSynth_TangNano20K.gprj，引用根目录13个RTL与27MHz SDC。实现选项见同目录project_settings.tcl；根目录run_gowin_implementation.ps1自动载入这些设置并生成独立输出。GUI须配置相同选项，尤其SSPI/MSPI GPIO复用。不要依赖本地impl缓存。完整步骤和硬件验收限制见 [当前交接说明](../docs/INTEGRATION_HANDOFF.md)。以下为历史记录。

---

2026-10-28 TTP229更新：当前顶层为9个物理端口，SCL27/SDO28；移除8个key_raw与5个面板GPIO。新读取器已同时加入sources.f和MusicSynth_TangNano20K.gprj，仍只使用根目录rtl。实际CST未变路径。保留SSPI/MSPI作为GPIO；PA51保持，V3923的51/53标注矛盾待实物核验。新离线实现使用根目录run_gowin_implementation.ps1，输出到新的sim/ttp229-implementation-*目录，不覆盖本目录历史实现。详见docs/integration/TTP229_Integration_Report.md。

# 建立 Gowin 工程

**2026-10-27 板级适配：** 当前 `MusicSynth_TangNano20K/MusicSynth_TangNano20K.gprj` 实际启用 `src/MusicSynth_TangNano20K.cst`，不是空模板 `../constraints/top.cst`。有效 CST 为 3921 Rev 1.30 暂定映射，实物版本/接线未核验；已增加 PA51 与控制脚 71/72/73/74。运行 `../tools/check_board_constraints.ps1` 检查源列表、引脚和默认上下拉。下述早期引脚/相对源路径说明属于历史记录，以当前 `.gprj` 和 [板级修改报告](../docs/integration/Board_IO_Change_Report.md) 为准；本轮不进行 P&R、完整 STA 或下载。

1. 用 Gowin EDA 新建 FPGA 工程，保存到本目录，顶层为 top。
2. 按手中板卡核实芯片型号/封装/速度等级后选择器件。
3. 按 ../sources.f 的11个活动RTL清单添加源文件，添加 ../constraints/top.cst 与 top.sdc；排除备用clk_gen和所有tb。
4. 完成模块逻辑、复位处理和真实约束后再综合/布局布线/下载。

此处未伪造 .gprj 工程：必须由实际 EDA 版本和真实器件配置生成。
当前骨架会被综合优化为常量，不可据此评价资源或功能。

## 2026-10-26 真实整机补充

上文是初始交接说明。当前正式 top 已有真实 A/B/C 逻辑，完整源清单增加 sin_rom，合计 12 个模块。
可运行根目录 `run_gowin_synthesis.ps1` 对 GW2AR-LV18QN88C8/I7 的正式 top 做 27 MHz 综合。
旧 audio_timing 工程只包含早期 I2S 测试链且源路径需修正，不能代表正式整机；本轮保留历史工程。
正式 top.cst 仍没有引脚，不据模块/整机综合结果声明板级 P&R 或 STA 通过。
实际结果见 [联调报告](../docs/integration/A_B_C_Integration_Test_Report.md)。

## MusicSynth_TangNano20K 的正式源引用

`MusicSynth_TangNano20K/MusicSynth_TangNano20K.gprj` 已直接引用 `../../rtl/` 下的 12 个正式 Verilog 文件（包含 sin_rom），以及 `../../constraints/top.sdc`。路径相对于 .gprj 所在目录；与根目录 sources.f 的 RTL 集合一致，各文件只加入一次。

`MusicSynth_TangNano20K/src/` 的原文件保留供历史核对，不再参与该工程的综合源列表；以后只编辑正式 rtl/ 和 constraints/，无需手工拷贝。若 GUI 当前仍打开旧工程，请重新加载这个 .gprj，再确认文件树中 osc.v 的完整路径为正式 rtl/osc.v。不要再把 src 副本加入工程。

本次对比时，原 src 的 12 个 RTL 及 SDC 与正式文件全部相同；此次修改消除的是独立副本后续漂移的风险，并不把 sin_rom 的优化警告归因为旧 RTL。修改后的工程源列表已经由实际 GowinSynthesis 验证，ROM 是否保留仍以生成网表/报告为准。详见 [源路径与 ROM 诊断报告](../docs/integration/Sin_ROM_Synthesis_Diagnostic_Report.md#10-gowin-工程正式源路径修复与复测)。

GUI 当前的 global_freq 仍为原配置 default（此前报告实际为 100MHz），本次没有修改这项设置。命令行脚本显式设为 27MHz；应分别核对实际 Clock Summary，不把源文件引用一致等同于综合选项全部一致。
