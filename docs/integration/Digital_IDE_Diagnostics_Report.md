# Digital IDE 113 项诊断排查与工程验证报告

> 历史基线：本篇记录控制消抖默认值仍为 270000 时的 IDE 修复与回归；其中 10.049 ms FAIL 是当时的真实结果。后续正式默认值调整及当前性能验收见 [控制延迟修复报告](Control_Latency_Fix_Report.md)。

日期：2026-10-26（Asia/Shanghai）。唯一操作目录：`F:\user\FPGA\FPGA_Music_integration`；分支 `integration`，HEAD `ae57a73`。

## 1. 结论及统计口径

**已修复正式工程混入临时副本/历史替身的索引问题，以及两个 SystemVerilog 测试文件的关键字模式问题；本轮没有修改 RTL。** 原有未提交工作和全部有意义的断言均保留。

没有取得原 Problems 面板 113 项的逐条导出，也没有可读取其当前总数的插件工具，因此**无法把原 113 项准确分摊到各类别，不能声称实时 Problems 已清零**。下面三组数字含义不同：

| 统计来源 | 修复前 | 修复后 | 结论 |
|---|---:|---:|---|
| 当前 VS Code 的 Digital IDE 实时工程索引：模块定义 | 57 | 28 | 临时副本、A 阶段替身与辅助综合顶层退出正式分析范围 |
| 同一实时后端：实例解析歧义 | 38 | **0** | 已实际消除多候选模块解析 |
| 同一实时后端：sim 目录 HDL 输入 | 20 | **0** | 不是删除临时文件，而是正确排除扫描 |
| 同一实时后端：无法解析的实例 | 0 | 0 | 正式工程和保留测试的依赖均可解析 |
| 独立 LSP 完整复核：错误 | 未以同口径测量 | **0** | 28 个显式输入都收到诊断结果 |
| 独立 LSP 完整复核：警告/提示 | 未以同口径测量 | **14 / 97** | 警告均为仿真器扩展；97 项为保留的静态提示 |
| 实时 Problems 面板总数 | 用户报告约 113 | **未直接读取** | 不以模块数、歧义数或独立 LSP 总数冒充 UI 统计 |

实时索引通过已安装 Digital IDE 0.5.2 自带的 MCP `get_project` 取得，修复后 `configGeneration` 从 2 增至 6、`workspaceEpoch` 从 2 增至 5，证明配置观察器实际刷新。最终还核对了头部修复后的索引。独立 LSP 检查使用同版本 `digital-server.exe` 和项目显式输入；它不是实时窗口的 Problems 导出。

## 2. 根因分类 A–H

| 类别 | 真实文件/现象 | 根因证据 | 处理及结果 |
|---|---|---|---|
| A：真实 RTL 语法/接口错误 | 截图中的 CTRL_FILT、内部对象找不到 | 实际 rtl/control_panel.v 声明 CTRL_FILT；adsr.v 声明 level/state；独立 Icarus 和完整 LSP 检查通过 | 本轮未发现需要改 RTL 的语法/接口错误；没有依据截图盲改 RTL |
| B：TB 自身错误 | bit/string、过程赋值和退出函数被报错 | 两个测试实际采用合法 SV；-g2012 编译和断言执行通过；统计目标均为真实 reg | 不删除检查、不改统计压力夹具；仅明确关键字模式 |
| C：层级解析 | tb_adsr 的 dut.level/state；边界 TB 的 ne.cnt/clip_cnt | 真实 adsr/ note_event/mixer 均有对应对象；修复前同名模块有 2–4 个候选，旧替身没有这些内部变量 | 隔离重复输入；完整 28 文件 LSP 复核已没有 UnknownModule、HierarchicalPath 或 UndeclaredIdentifier 错误 |
| D：语言模式 | tb_contract_boundaries.v、tb_top_integration.v 的 bit/string | 最小探针：plain.v 即使声明 languageId=systemverilog 仍有 4 个未声明类型错误；同内容 .sv 和加 begin_keywords 的 .v 均为 0 错误 | 保留文件名，增加标准 `begin_keywords "1800-2012"`/`end_keywords`，配合 VS Code 语言关联；Icarus 仍用 -g2012 |
| E：重复扫描 | sim/c_runner_check.tmp、sim/integration_mutations.tmp、tb_top.v | 当前实时后端实际包含 20 个临时 HDL 文件；tb_top.v 额外定义 7 个正式模块名的替身及阶段性 top | .dideignore 排除生成目录和单个历史替身 TB；38 处歧义实际降为 0 |
| F：不支持的扩展 | `$finish_and_return`、`$abs` | 完整 LSP 快照中分别 12 和 2 处 UnknownSystemName 警告；Icarus 实际支持，原断言失败路径实测退出 1 | 保留扩展和警告，不将 `$finish_and_return` 换成会掩盖失败的 `$finish`；未使用诊断屏蔽 |
| G：timescale | 用户历史警告 | 当前正式模块已在本轮开始前具有明确声明；本轮 -Wall 顶层编译无 timescale 警告 | 未再修改时间单位，也未改变 27 MHz、46875 Hz 或硬件分频 |
| H：其他提示/工具限制 | 97 项类型/宽度/覆盖提示；原生硬件流程不含 Gowin | 独立 LSP 保留全部提示；已安装 property schema 的 toolChain 枚举只有 xilinx/efinity | 按下节解释数值边界；Gowin 继续使用真实外部综合脚本，不编造 schema 字段 |

## 3. 工程扫描和语言修复

新增 `.dideignore`，规则只排除：

- `sim/`：运行产物、反向验证和解析探针副本；原文件保留，避免删除有用证据。
- `synth_check/`：B 的辅助综合顶层，不作为正式 top 或单元测试输入。
- `.git/`、`.dide/`、Gowin `impl/`：仓库/IDE/构建缓存。
- 单个 `tb/tb_top.v`：历史 A-only 平台内包含 sensor_frontend、control_panel、note_event、voice_alloc、osc、adsr、mixer 的替身。
- `tb/tb/`：用户原有空占位文件所在的多余目录；正式测试是 `tb/tb_top_integration.v`。

**没有排除整个 tb/。** 实时后端实际保留 **12 个 src 输入、16 个 sim 输入**：16 个仿真输入由 15 个正式测试平台和 `rtl/top_i2s_test.v` 辅助顶层组成。旧 A-only 平台仍可用独立的 `tb/top_a_sources.f` 编译运行，本轮亦实际验证通过。

新增 `.vscode/property.json`：先用插件自身 `filelist import` 将 `sources.f` 的 12 个正式模块导入，再设置真实源/测试路径、显式文件清单、`srcTop=top` 和 `simTop=tb_top_integration`。当前插件回读 `success=true`，逐个模块分类和顶层均与该配置一致。

配置依据是当前安装的 `sterben.fpga-support-0.5.2/resources/property/property-schema.json` 和 package.json；已核对必填字段、字段名和枚举值。插件没有 Gowin 原生硬件 toolChain，property 中的 `toolChain=xilinx`、`device=none` 满足 schema 必填项，并沿用插件 `property-init.json` 的初始值，作为**仅分析占位配置**。schema 本身没有为 toolChain 声明默认值。项目名明确为 `FPGA_Music_analysis_only`，不代表板卡使用 Xilinx。**不要用该分析容器的原生 HARD 构建/下载按钮验收本板；正式 Gowin 目标仍由 run_gowin_synthesis.ps1 决定。**

`.vscode/settings.json` 仅给两个实际使用 SV 的 .v 测试关联 systemverilog，设置已支持的 2017 分析标准，并明确保留 `linter.mode=full`。后端按扩展名处理关键字的问题还需文件内标准指令，因此不是仅更改 VS Code 显示模式或改名来掩盖问题。

两个测试文件的修改仅为头部注释/关键字范围声明和尾部结束声明。对本轮开始时的字节哈希做还原比较：移除新增头尾后，两个文件均与原内容完全一致；全部原有断言、参数、延迟、统计夹具和退出条件未变。

## 4. 保留的 14 个警告和 97 个提示

所有位置、原始消息和严重性列在 [诊断明细](Digital_IDE_Diagnostic_Details.md)。它们未被隐藏或重定级。

| 代码 | 当前独立快照数量 | 原因及处理 |
|---|---:|---|
| UnknownSystemName | 14 | 12 处 `$finish_and_return`、2 处 `$abs`，均在测试代码；实际 Icarus 编译/运行支持。保留静态警告 |
| ArithOpMismatch | 13 | 宽累加与单路样本、49 位乘法、数学频率参考存在不同类型操作数。检查 signed 扩展和目标宽度，并由数值边界/真实混音断言验证 |
| SignConversion | 25 | 打包 PCM 总线是位容器，切片后转回 signed；包络取积的位段；TB 整数与定宽期望值。保留明确有意的转换，不为消提示改算法 |
| WidthTruncate | 12 | 包括 mixer 49 位乘积右移后保留 33 位、分配器 integer 下标存为 3 位；合法 NVOICE=4/8 时下标 0..7，缩放/饱和有独立断言 |
| WidthExpand | 13 | 整数计数/参考值与定宽信号的拓宽；当前使用值非负且受约束，保留提示 |
| SignCompare | 19 | unsigned 消抖/FIFO 计数与正 integer 常量，以及 TB 中定宽信号和整数期望值比较。正式默认参数均在计数器容量内 |
| IntBoolConv | 5 | TB 使用整数错误数/状态作条件；非零即失败或成立，行为已真实执行 |
| IntFloatConv | 5 | 仿真周期数换算时间、数学频率参考，主动转为 real，未进入 RTL |
| CaseDefault | 5 | TB 的受限 MIDI 映射和独立模型状态分支；调用范围/状态由测试约束。没有修改硬件安全分支 |

97 项提示中 **21 项来自 RTL、76 项来自 TB**。例如 `voice_alloc` 的 32→3 位下标转换只在支持的 4/8 路范围内安全；若未来扩大声部数，应重新设计选择器宽度，不能据本次默认验证宣称任意参数均安全。`mixer` 的 PCM 总线在 top 内是 unsigned 位容器，下游逐路 `$signed` 扩展；该提示不能直接当作负数被当成正数的证据。

本轮没有关闭某个诊断类别，没有添加 UnknownSystemName 全局屏蔽，也没有批量加类型强转来换取面板清零。

## 5. 实际执行结果与退出码

| 检查 | 本轮真实结果 | 退出码 |
|---|---|---:|
| 全部 rtl/*.v 显式数组，`-g2012 -Wall -s top` | PASS，无致命错误或 timescale 警告 | 0 |
| 原 `run_sim_c.bat` | sensor_frontend / control_panel / note_event 均 PASS | 0 |
| A：audio_timing / i2s_tx / test_mode | 各自真实断言通过 | 各 0 |
| B：voice_alloc / osc_timbre / adsr / mixer / chain | 各自真实断言通过 | 各 0 |
| 合同边界测试 | 关键字声明后重新编译运行；部分帧拒收、计数饱和及正负削波 PASS | 0 |
| 旧 A-only tb_top，隔离源清单 | PASS；仍明确使用替身，不能冒充真实整机 | 0 |
| top_i2s_test | 200 个双声道帧、复位、无欠载 PASS | 0 |
| 真实 tb_top_integration，头部修复后重跑 | 功能 PASS：3189021 次检查、8907 个双声道帧；默认面板延迟 FAIL | **1** |
| Gowin 正式 top/27 MHz 综合 | 实际生成网表和报告；4 条 NL0002 优化警告，无综合错误 | 0 |
| 独立 Digital IDE 完整 LSP | 28 个文件全部取得结果；0 错误、14 警告、97 提示 | 0 |
| 语言负向探针 | plain.v 4 个未声明类型错误；同内容 plain.sv/explicit.v 均 0 错误 | **1（预期）** |
| Icarus 失败退出码反向检查 | 隔离副本故意恢复 mixer OR-valid 缺陷，真实边界断言报 valid=1/期望 0 | **1（预期）** |

联合测试仍实测默认选音到 I2S 为 **0.236 ms**，默认面板为 **10.049 ms**，超过 10 ms。这是已知性能失败，保留严格非零退出码，与本轮 IDE 诊断修复是不同问题。没有通过改变消抖参数使结果变绿。

本轮没有单独运行仅打印频率的 `tb_osc.v` 观察性平台；自动频率验证由实际通过的 `tb_osc_timbre` 和真实整机 DDS 数学参考完成。不因文件存在就写 PASS。空占位文件没有 module，不作为可运行测试。

Gowin 使用已有真实正式清单和脚本，当前 RTL 与本轮开始时相同；综合资源/约束边界见 [整机报告](A_B_C_Integration_Test_Report.md)。本轮未做板级 P&R、完整 Setup/Hold 或上板实测；CST 和完整外部时序约束仍未齐备。

## 6. 可重复执行的命令和证据

```powershell
# 当前安装解析器的独立完整检查；不修改插件或用户全局设置。
python tools/check_ide_diagnostics.py

# 脚本绑定同一个 OSS CAD Suite 的 bin/lib，避免 MSYS DLL 冲突。
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_integration.ps1 -UnitTests
$env:IVL = 'E:\app\software\oss-cad-suite\bin'
.\run_sim_c.bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_gowin_synthesis.ps1
```

本轮实际 Python 为 `C:/msys64/ucrt64/bin/python.exe`。解析脚本只依赖 Python 标准库，默认读取当前已安装 Digital IDE 后端和显式 `files.src/files.sim`；任何 Error 或诊断结果缺失都会失败，不把未知状态当成功。输出保留全部诊断，没有去除扩展警告。

生成证据均留在忽略目录：`sim/dide_project_before_2.tmp`、`sim/dide_project_after.tmp`、`sim/digital_ide_diagnostics.tmp`、`sim/ide_language_comparison.tmp`、`sim/ide_unit_results.tmp`、`sim/ide_regression_console.log`、`sim/ide_final_joint_console.log` 和 `sim/ide_synthesis_console.log`。源码索引证据来自当前正在运行的窗口；独立 LSP 证据只代表可复现后端复核。

实时 Problems 总数未通过 API 取得，因此仍标记为“未直接读取”；本轮已实际触发配置刷新并核对源图，不能额外宣称面板为 0、14 或 111 项。

## 7. 本轮修改与已有未提交内容

| 本轮文件 | 改动及原因 |
|---|---|
| .dideignore | 生成/临时输入和单个历史替身平台的分析隔离，保留正式 tb |
| .vscode/property.json | 当前插件原生导入的 12 个设计源、16 个仿真输入及真实顶层；schema 合法的仅分析容器 |
| .vscode/settings.json | 两个 SV 测试的语言关联、支持的分析标准，保留完整诊断 |
| tb/tb_contract_boundaries.v | 仅新增标准关键字范围声明及说明，逻辑与断言字节保留 |
| tb/tb_top_integration.v | 同上，文件名和完整真实整机验证不变 |
| tools/check_ide_diagnostics.py | 可重复执行的真实解析器检查，错误非零，全部消息留证 |
| 本报告及诊断明细 | 记录可信统计口径、每类根因、保留提示和真实退出码 |

本轮开始时已有 **11 个已跟踪修改和 16 个未跟踪文件**。其中前轮 RTL 修复、源清单、测试记录、图示和综合脚本均原样保留。对这 27 个既有文件逐个哈希比较，仅上述两个 TB 因新增头尾声明改变；去掉新增声明后均与基线哈希一致。没有丢弃成员合并或用户已有修改。

最终执行 `git status --short --branch`、`git diff --check`、`git diff --cached --check`。不自动暂存、提交、推送或中止合并；不将 VVP/VCD、解析探针或 Gowin 产物加入 Git。

## 8. 下一阶段条件

工程现已具备可靠继续真实联合仿真的源码索引、语言设置和回归入口。仍应先处理默认面板 >10 ms 的性能问题，再补实际接线 CST、完整时序/CDC 约束并做 P&R/STA 和硬件测量。IDE 中剩余的扩展警告和类型提示不能替代这些验收，也不应通过关掉全部分析来隐藏。
