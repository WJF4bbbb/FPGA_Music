# 板级输入极性、功放使能与暂定引脚修改报告

日期：2026-10-27（Asia/Shanghai）。实施范围：按用户授权修改板级边界、测试和暂定 CST，保留全部现有未提交工作；不自动 commit、push、merge、reset 或清理文件。

## 硬件核验状态

已确认开发板型号为 Sipeed Tang Nano 20K。**实物是否为 3921 Rev 1.30 尚未确认**；本文仅以 [官方 3921 Rev 1.30 原理图](https://dl.sipeed.com/fileList/TANG/Nano_20K/2_Schematic/Tang_Nano_20K_3921_Schematics.pdf) 作暂定参考。

五个面板键已约定接地式机械按键；8 路音符输入的机械/传感器方案、推挽/开漏及实际有效电平尚未确定。所有“通过”均按具体仿真/综合项目描述，不表示实物接线已核验或可以安全下载。

## 工作区保护与有效文件

完整备份位于：

`<user-home>/.codex/visualizations/2026/10/27/01a17ddc-659a-7431-b889-d17067df27b0/backups/board-io-20261027-233025/`

- `workspace.zip` 包含 532 个原始文件，包括未跟踪/忽略文件和链接工作区 `.git` 指针；`manifest.json` 记录每个文件的 SHA256。
- 已逐个读取 ZIP 中全部 532 个文件验证 SHA256，全部匹配。验证记录为 `backup-verification.json`。
- 另存 `MusicSynth_TangNano20K.cst`、HEAD、Git 状态、工作区/暂存区 binary patch。
- ZIP SHA256：`C646E88A5AD0A86E5E1D0D2F2FEFBB58B7FF554D3C9358650B2B3AF93F290691`。
- 原 CST SHA256：`9EC851A73FA22337A6CED1152C54CD9AA6E5889AD2666167BDAC7A38F39D39B4`。
- 原工作区已是 `integration` 分支的链接工作区；未创建分支、未改 Git 元数据。原 CST 中用户已将 `rst_n` 改到 73，本轮保留。

实际 `.gprj` 唯一启用的 CST 为 `gowin/MusicSynth_TangNano20K/src/MusicSynth_TangNano20K.cst`，不是空模板 `constraints/top.cst`。正式综合源仍为根目录 `sources.f` 对应的 12 个 `rtl/` 文件，`src/` 历史 RTL 未加入。

`tools/check_board_constraints.ps1` 检查：有效 CST 解析、器件型号、全部 20 个物理端口、LOC/IO_PORT 覆盖、引脚唯一性、暂定映射、默认上下拉、LVCMOS33、12 个正式 RTL 引用及 27 MHz SDC。其 PASS 仅表示暂定配置自洽；JSON 中的 P&R BLOCKED 是审计状态，并不是阻止其他人手工调用 P&R 的工具锁。

## 实现

### 输入边界

仅修改 `rtl/top.v` 的输入边界，不改变 sensor_frontend、control_panel、note_event、voice_alloc、osc、adsr、mixer、i2s_tx 的端口或实现。

| 物理输入 | 顶层默认适配 | 核心接口 |
| --- | --- | --- |
| 八路 `key_raw` | `key_raw ^ KEY_ACTIVE_LOW`，默认 `8'h00` | 高为触发，原双级同步与 5400 周期滤波不变 |
| 五个面板键 | XOR `PANEL_ACTIVE_LOW=5'b11111` | 高为按下，原双级同步与 267000 周期滤波不变 |
| `rst_n` | 不反相，低有效 | 保留异步断言、同步释放 |
| `test_enable` | 不反相，高演示、低正常 | 保留启动同步锁存，运行中变化无效 |

面板掩码位序为 `{timbre,bend_up,bend_down,volume_up,volume_down}`，位为 1 表示对应物理输入低有效。极性适配为组合逻辑，不额外增加同步拍数。改变音符掩码时必须同时审查外部电阻与 CST，不能只改参数。

暂定默认接线要求：面板和复位上拉，按键接 GND；test_enable 外接明确的 4.7 kΩ 下拉，选择开关接 3.3 V，且在复位期间设置并保持到锁存结束。八路默认高有效音符输入规划外接 4.7 kΩ 下拉以建立空闲低；不能用未知传感器输出替代该电气核对。

尤其 25 有板载 CEC 上拉负载，不能仅凭 FPGA 的内部 DOWN 就保证空闲低。4.7 kΩ 是待核验的外接接线方案，仍需按实际板型、输入阈值及传感器驱动能力测量确认。开漏低有效方案需要改掩码、上拉并重新核验负载。若音符输入最终选机械键，当前 0.2 ms 滤波不是已验证的机械消抖方案，需要另行在 10 ms 预算内设计并验收。

### 功放启动

新增 `pa_en` 输出，暂定 FPGA 51，LVCMOS33。复位时异步关闭；内部启动尚未释放时保持关闭。

I2S 时钟和 `mixed_valid` 保持原合同，预热时仅在发送器输入把 PCM 替换为零。预热顺序如下：

1. 第一个 `frame_load` 对齐串流，继续发送零。
2. 再经过两个完整双声道帧；第三个 `frame_load` 是第二个静音帧右 LSB 的准备沿，其最后一位还要等下一次 BCLK 上升沿采样。
3. 等待再下一个 BCLK 下降沿，即新帧左 MSB 准备沿，锁存 `pa_en=1`。在 27 MHz 下，该时刻为核心释放后第 1188 个时钟，约 44 µs。
4. 随后允许真实混音样本进入原 pending/frame 缓冲。已装载的当前帧仍为零，不发生半帧样本切换。
5. 运行中静音继续发送零并保持 PA 开启；外部复位立即关闭 PA、清除预热状态，下次启动重新发送静音帧。

RTL 证明的是数字事件顺序，不能替代实际输出传播、复位关闭间隔、上电电压和扬声器瞬态测量。PA 高选择 MAX98357A 左声道；当前左右发送相同样本，与该模式一致。[芯片手册](https://www.analog.com/media/en/technical-documentation/data-sheets/MAX98357A-MAX98357B.pdf)

## 暂定引脚与 25/26 评估

| 信号 | 备份中的引脚 | 本轮暂定引脚 | 默认上/下拉 |
| --- | --- | --- | --- |
| `bend_up_key` | 49 | 71 | UP |
| `bend_down_key` | 52 | 72 | UP |
| `rst_n` | 73（此前为 53，用户已改） | 73 | UP |
| `test_enable` | 80 | 74 | DOWN，并规划外部下拉 |
| `pa_en` | 无 | 51 | DOWN，输出低关断 |
| 八路 `key_raw`，按 bit0→bit7 | 25/26/27/28/29/30/31/77 | 本轮保留 | DOWN，并规划外部下拉 |

其他面板脚仍为 48/41/42；I2S 54/55/56、27 MHz 时钟 4 不变。暂定原理图中 71/72/73/74 对应 J5-18/J5-17/J6-1/J6-2；数字为 FPGA 物理引脚号，不能与排针序号混用。

25/26 保留为待定项，未将其风险宣布消除：

- 25 与 LCD HS、HDMI CEC 共用；26 与 LCD VS、HDMI HPD 共用，且有 5.1 kΩ 下拉及 HPD 网络。
- 15/16 是可达排针的替代候选，但连接板载 LED 与约 510 Ω 限流电阻，输入驱动器必须承担 LED 支路负载，弱传感器/开漏输出不能直接视为适用。17～20 也有类似 LED 负载。
- 80/85 等 SDIO 候选仍连卡槽并带上拉，不能在高有效空闲低的方案中直接当作空闲普通 GPIO。
- 75/76/86 与 BL616 通信共用，不作为未经核对的替代品。
- 71～74 已分配四路控制，本次没有确认另外两路完全无板载负载的普通排针 GPIO。定稿需确认 PCB 版本、输入器件驱动能力与实际扩展连接，再决定保留 25/26、使用 LED 负载候选或重新分配。

本轮接线方案要求不连接 LCD/HDMI，但拔掉外设不会移除板载电阻。保留共享引脚、未知输入类型和未确认板型，使物理审计状态仍为 UNVERIFIED。

## 验证记录

### 测试驱动与新增测试

先在旧 RTL 上运行新增测试，记录两个预期失败：

- `tb_top_board_inputs`：`pulled-up idle panel must not act`，退出 1。
- `tb_top_pa_enable`：`external reset holds amplifier off`，退出 1。

实现后两项均退出 0。新增测试包括：

- `tb_top_board_inputs`：实际面板空闲高/按下低、按一次只动作一次、松键无动作、正确变调、八路默认音符输入及启动模式锁存。
- `tb_top_input_polarity`：00/FF/A5/5A 四组音符掩码及四组面板掩码，覆盖 256 种音符模式、32 种面板模式。临时副本删除音符 XOR 后该测试预期失败，证明能发现适配回归。
- `tb_top_pa_enable`：从外部三根 I2S 线独立解码完整静音双声道帧；检查至少两帧完成后 PA 开启、持续时钟、五次启动、不同位相的异步复位、后续真实演示音频及正常模式持续静音。
- 输入单元测试只缩短滤波以穷举逻辑；正式整机测试使用原始 5400/267000 默认滤波，不能用前者代替延迟验收。

旧 A 组接线测试调整为在 PA 就绪后注入非零样本，保留其原有 signed PCM/无撕裂断言；4/8 声部均通过。固定 I2S 测试顶层通过，解码 200 个双声道帧。

### 完整回归

已从备份快照中提取原始 RTL/测试，在独立 `baseline-workspace/` 运行新的基线回归：12 项原有单元/合同测试和真实整机集成，**13/13 PASS，退出 0**。快照 top.v 的 SHA256 与原始备份清单一致，未用当前修改覆盖基线。

当前完整回归为 **16/16 PASS，退出 0**：15 项单元/边界测试（原 12 项加板级输入、混合极性和 PA 启动三项），以及真实 A/B/C 整机集成。整机完成 3174266 个断言、8847 个外部解码双声道帧，`performance_failures=0`。两套回归均在 2026-10-27 新执行并核对退出码及产物时间；历史日志不作为本轮通过依据。

完整单元清单：audio_timing、i2s_tx、test_mode、sensor_frontend、control_panel、note_event、voice_alloc、osc_timbre、adsr、mixer、chain、contract_boundaries、top_board_inputs、top_input_polarity、top_pa_enable。

补充验证为 A-only 4/8 声部接线、固定 I2S 顶层三项均通过；它们没有替代真实整机测试。

### Gowin 综合

本轮 `run_gowin_synthesis.ps1` 成功，退出码 0；新网表 `sim/gowin_top.tmp/top.edf` 和报告生成于 2026-10-27 23:42:42（客户端时区）。器件 GW2AR-LV18QN88C8/I7，时钟约束 27 MHz，顶层包含非恒定的 pa_en 寄存器与输出。

资源：3939 LUT、1203 FF、4 BSRAM；推断锁存器 0。综合估计 Fmax=45.413 MHz，高于 27 MHz 约束，**不是布局布线后的 Setup/Hold 结论**。

存在四条 `sin_rom` 层级优化提示；现有网表审计脚本确认四个 256×16 pROM 均保留并与数学正弦表逐字一致；Gowin 官方原语模型扫过 1024 个字，全部通过。并未将“层级 swept”误判为音频表丢失。

### 延迟标准

保留 27 MHz、每帧 576 拍、46.875 kHz 以及 270000 拍（10 ms）验收门槛。面板只加组合反相，无额外同步或队列。

正式整机回归仍独立验证原始输入→消抖→真实相位/PCM→外部解码 I2S MSB。另给出保守数字时序上界：267003 拍同步/滤波 + 2 帧等待相位变化输出 + 128 拍 PCM 管线上限 + 1 帧等待 pending 装载 + 36 拍左 MSB 提前量 = **268895 拍，约 9.959074 ms**，余量 1105 拍。这是依赖现有模块时序合同的保守数字上界，不包含未确定的外部传感器、机械抖动和模拟声学延迟。

默认滤波下的新仿真结果与原始快照基线一致：

| 测量 | 新结果 | 备份快照基线 |
| --- | --- | --- |
| 音符原始输入→首个已验证非零 I2S 左 MSB | 6372 拍，0.236000 ms | 相同 |
| 变调原始输入→消抖配置 | 267003 拍 | 相同 |
| 变调配置→含新相位的 PCM | 839 拍 | 相同 |
| 新 PCM→I2S 左 MSB | 601 拍 | 相同 |
| 变调输入→I2S 总延迟 | 268443 拍，9.942333 ms | 相同 |
| 变调总延迟余量 | 1557 拍，约 57.667 µs | 相同 |

采样点是可追溯到真实相位更新 PCM 的外部 I2S MSB；仿真波形与解码模型核对其完整帧，未以内部 valid 单独代替输出验收。

## 物理实施阶段

本轮不执行 Place & Route、完整 Setup/Hold、烧写或板级测试。当前 SDC 只有系统时钟，外部输入/输出时序及 CDC 例外尚不完整，不能用综合估计替代板级 STA。

下一阶段前置条件：核实实物 PCB；定稿 25/26 或替代位置；确认全部输入电平、输出类型及外部电阻；核对 LCD/HDMI/SD/BL616 冲突；补齐实际 I/O 时序与同步器约束。随后再执行 P&R、Setup/Hold、示波器/逻辑分析仪测量及听音验收。

按用户要求保持 46.875 kHz。MAX98357A 手册明确列举的标准采样率并未列出 46.875 kHz，其实物兼容性继续为未验证项，没有在本轮擅自切换 PLL 或采样率。

## 产物

- 配置审计：`sim/board_constraints_audit.json`。
- 修改保护检查：`sim/board_io_preservation.json`，原有 103 个非生成文件中仅本任务涉及的 9 个文件发生变更，无原有文件被删除，无其他源代码变更。
- 完整回归：`sim/board_io_regression.log`、`sim/integration_results.tmp` 和各测试 `*.run.log`。
- 新基线：备份目录下 `baseline-workspace/baseline-transcript.log`、`baseline-workspace/sim/integration_results.tmp`。
- 综合：`sim/board_io_synthesis_transcript.log`、`sim/gowin_top.tmp/`。
- 网表正弦审计：`sim/board_io_rom_audit.log`、`sim/board_io_rom_sweep.tmp/sweep.log`。
- 新测试：`tb/tb_top_board_inputs.v`、`tb/tb_top_input_polarity.v`、`tb/tb_top_pa_enable.v`。

只读代码复核未发现阻断缺陷；复核没有代替测试执行或实物测量。用户原有工作、历史副本和旧生成文件均保留。

可复现的当前入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check_board_constraints.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_integration.ps1 -UnitTests
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_gowin_synthesis.ps1
```

使用同一 OSS CAD Suite 的 Icarus 编译器/运行器及 DLL 环境。当前环境中受限原生进程可能异常退出，本轮经允许的本地非沙箱执行完成并记录真实退出码。后续若在 Gowin GUI 使用工程，应重新载入实际 CST，避免旧的 GUI 缓存覆盖暂定映射。
