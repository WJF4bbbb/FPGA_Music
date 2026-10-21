# FPGA_Music 开发交接说明（A → B/C）

日期：2026-10-21。适用工程：本Git仓库（`FPGA_Music`）。

**B、C可以并行开发各自模块。A的顶层已按冻结接口接线，但当前仍不能作为完整音乐合成系统验收。** 本说明记录交接时状态；完成新测试后，应更新工程内的测试记录。

## 1. 开发前先读这些文件

1. [冻结接口规范](interfaces.md)：V1.1，是文件名、端口、位宽、符号、握手和时序的统一合同。
2. 根目录规范及备份大纲位于本地仓库外；仓库内以本目录interfaces.md作为可随代码交付的统一接口合同。
3. [分工与开发规划](ownership.md)：各模块职责与阶段放行条件。
4. [top对接说明](top.md)：真实顶层接线、启动复位与模式锁定、阶段性测试边界。

根目录各个“备份”大纲可用于理解模块设计，但其中存在旧接口方案。发生冲突时，按已冻结的V1.1执行；不要照旧大纲自行增加端口或更换时钟方案。发现规范自身矛盾时先联系A统一处理。

## 2. 全员统一的工程约定

| 项目 | 当前约定 |
|---|---|
| 内部时钟 | 所有模块统一使用27MHz clk；不使用PLL |
| 音频时序源 | audio_timing是唯一音频时序模块 |
| 采样率 | 实际46875Hz，每帧576个clk；不能按48000Hz计算DDS或包络 |
| I2S | BCLK=1.5MHz，16位补码，左右复制同一个混音样本，Philips格式 |
| 声部数 | 默认NVOICE=4，合同支持4或8；先完成4路，再验证8路 |
| 公共复位 | 外部rst_n只由top处理；所有子模块接top生成的core_rst_n |
| 原始输入 | 按合同高电平有效；同步/滤波由C负责的输入模块完成 |
| 模式选择 | top同步并在启动时锁定test_enable；运行中忽略变化，换模式需统一复位 |
| 事件成交 | 只在evt_valid && evt_ready的clk上升沿消费；背压保持valid及全部字段 |
| 音频valid | 每帧一次，所有声部固定延迟且对齐；静音声部也必须提交valid |
| 声部打包 | 第0路在低位：note取[i*7 +: 7]，sample取[i*16 +: 16] |
| 符号 | wave/sample为signed 16位，bend为signed 4位；样本切片取出后按signed扩展 |

frame_tick、frame_load、bclk_fall_ce都是clk域使能，不能当内部时钟。clk_gen仅为备用PLL封装，不例化、不加入当前正式源列表；其真实PLL适配层也尚未完成。

## 3. A已经交付什么

| 文件 | 交接时状态 |
|---|---|
| rtl/audio_timing.v | 已实现；独立自检检查103个完整帧及复位重启 |
| rtl/i2s_tx.v | 已实现V1.1双缓存、sample_valid和饱和欠载统计；真实audio_timing集成测试解码120个完整双声道帧 |
| rtl/test_mode.v | 已实现60/64/67/72四音和弦循环；自检72次握手、7轮完整演示 |
| rtl/top.v | 已实现复位、启动模式锁定、事件路由、声部实例化和音频链接线；4/8路阶段性接线测试通过 |
| rtl/clk_gen.v | 备用PLL封装，仅复位控制在仿真替身下通过；当前架构不启用 |

上述数量对应已有自检运行结果，不代表所有算法或硬件均已验证。top测试使用B/C接口替身并注入接线刺激，未验证真实B/C功能。Gowin综合、布局布线、板测、实际四复音、FFT和整机≤10ms延迟均未完成。

A模块说明分别位于 `FPGA_Music/docs/audio_timing.md`、`i2s_tx.md`、`test_mode.md`、`clk_gen.md`、`top.md`；结果汇总见[test_records.md](test_records.md)。

## 4. B成员的开发任务

负责 `voice_alloc.v`、`osc.v`、`adsr.v`、`mixer.v`，以及对应单元自检。交接时这四个文件仍是旧桩，需按V1.1迁移接口并实现算法，不能把已有固定输出视作完成。

| 模块 | 重点交付与检查 |
|---|---|
| voice_alloc | 跟踪key_id和占用；相邻事件不分到同一空闲槽；重按复用、确定性抢占、匹配松开、Release完成回收；新分配优先于同沿旧env_done |
| osc | 将旧sample_en改为frame_tick；每路独立32位相位；FS_HZ=46875；音色与signed bend逐帧快照；变调保持相位；安全处理不支持音号 |
| adsr | 增加frame_tick控制快照，wave_valid驱动数据处理；缓存帧间trigger；Release结束才清busy并发env_done；静音仍输出sample=0和valid |
| mixer | 增加frame_tick锁存master_gain；所有voice_valid同拍；每路按signed扩展后求和、缩放与增益处理，输出饱和16位补码及统计 |

特别注意：ADSR和mixer不能在frame_tick直接读取尚未完成的上游样本。ADSR跟wave_valid处理数据，mixer跟全路voice_valid处理数据。

B应报告：每一级固定流水线延迟、从frame_tick到i2s_tx可接收结果的总clk数、4/8声部的验证状态，以及尚未支持的音色或音号范围。总计算目标≤128拍，并必须在下一frame_load前完成，不能依赖边界同拍提交供本次装载。

## 5. C成员的开发任务

负责 `sensor_frontend.v`、`control_panel.v`、`note_event.v`，以及对应单元自检。交接时前两个文件为空，note_event仍是旧桩。

| 模块 | 重点交付与检查 |
|---|---|
| sensor_frontend | 8路独立同步和滤波，允许多键同时保持；光电初始滤波5400拍，约0.2ms；机械替身需另评估消抖时间 |
| control_panel | 5个控制键同步/消抖；音色单次切换；bend为signed -2/0/+2；音量复位16384、步长约4096、边界钳位，不回绕 |
| note_event | key 0..7对应60/62/64/65/67/69/71/72；至少32条事件缓存；同批先松后按，再按key_id排序；背压保持整条事件；满时明确饱和计数，不能静默丢note_off |

C应报告：同步与滤波延迟、事件队列在多键同时变化时的处理延迟、FIFO满时行为，以及面板消抖方案。复位释放时已按住的键，应按规范识别为一次按下。

正常演奏的键号映射与测试模式的和弦不同，这是两个事件源各自的规定，不要把test_mode的60/64/67/72替换成正常键盘前4个音。

## 6. 单元测试与当前入口的区别

B/C开发期间，分别用自己的RTL和tb编译，不要求等待另一方完成，也不把当前全机编译作为单模块交付条件。以下命令均从 `FPGA_Music` 根目录执行，前提是已创建对应tb：

```powershell
# B示例：osc单元自检
iverilog -g2001 -Wall -s tb_osc -o sim/tb_osc.vvp rtl/osc.v tb/tb_osc.v
vvp sim/tb_osc.vvp

# C示例：note_event单元自检
iverilog -g2001 -Wall -s tb_note_event -o sim/tb_note_event.vvp rtl/note_event.v tb/tb_note_event.v
vvp sim/tb_note_event.vvp
```

其他模块采用相同方式，明确列出本次需要的RTL和tb。Windows OSS CAD Suite运行时需将其bin和lib目录加入PATH。tb只进入仿真，不能加入综合。

当前 `run_sim.bat` / `run_sim.sh` 是A组阶段入口，使用 `tb/top_a_sources.f`，不自动加入B/C真实RTL。可运行tb_top、tb_audio_timing、tb_i2s_tx、tb_test_mode和tb_clk_gen。

**不要将当前tb_top.v与真实B/C模块同时编译。** tb_top.v末尾定义了与B/C同名的测试替身，会与真实模块冲突；该测试仍只用于A组接线回归。B/C完成后，由A另建或迁移真实整机测试入口，排除这些替身，再按正式sources.f联调。

正式 `sources.f` 已列出11个活动RTL，排除了clk_gen和旧名模块。由于B/C尚未完成，它目前是目标源清单，不能据此认为真实整机已可编译或发声。

## 7. 每人交付时附上这些内容

- 完整RTL，文件名、module名和接口与V1.1一致；关键位宽、signed和复位语义正确。
- 配套自检tb：覆盖正常路径、背压或valid时序、边界条件和复位；失败明确报错并返回非零状态。
- 实际执行的编译/运行命令、工具版本、PASS/FAIL及关键日志；只写已运行的结果。
- 可复查的代码提交号；尚未提交时明确记录本地代码状态，不把本机文件当作其他成员已收到。
- 固定流水线延迟、输入滤波/事件排队延迟和已知限制；必要的ROM/查表文件一并提供，并说明路径。
- 在 `FPGA_Music/docs/test_records.md` 补充日期、测试参数和证据；不要把单元通过写成整机通过。

B主要修改自己的4个RTL及测试，C主要修改自己的3个RTL及测试；A维护top、共享源列表、测试入口和统一接口。各自分支开发，提交前查看diff，避免夹带其他人的未提交文件或编辑器缓存。修改公共接口前先由A统一同步规范、顶层和受影响tb。

## 8. B/C完成后，A继续负责的联调

1. 检查真实端口与V1.1一致，启用不含B/C替身的整机测试，先完成编译与复位检查。
2. 接入test_mode，验证事件成交、4个独立声部、相位/包络、valid对齐、混音和I2S；稳态overflow/underrun应为0。
3. 接入真实sensor_frontend/control_panel/note_event，验证多键、松开/重按、抢占、持续音变调、音色与音量。
4. 通过共享复位换模式，确认事件队列、声部分配和包络一同清除；不接入未经设计的热切换。
5. 记录控制输入、事件成交、样本完成、frame_load和串行输出时刻，按最坏条件验证整机≤10ms；单凭576拍帧周期不能证明延迟达标。
6. 按真实板卡补齐top.cst引脚和top.sdc外部时序约束，再执行Gowin综合、布局布线和STA；当前约束仍是模板，不猜管脚。
7. 上板检查MAX98357A对46875Hz的兼容性、I2S建立保持时间、实际四复音、FFT峰值及长时间稳定性。

以上未完成项不阻塞B/C并行单元开发，但在它们验证完成前，整机保持“待验收”。
