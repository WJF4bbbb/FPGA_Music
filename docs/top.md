# top：A成员阶段性交付

## 范围与接口核对

本次仅完成A成员的top及验证，不修改B/C正式RTL。接口合同采用[interfaces.md](interfaces.md) V1.1（工程没有另一个interface_spec.md）。大纲中以下旧约定按已确认合同处理：

| 大纲/旧骨架 | 本版做法 |
|---|---|
| clk_gen生成音频时钟 | 只例化audio_timing，27MHz直分频 |
| i2s_tx.sample_in/i2s_data单缓存 | 使用已实现sample/sample_valid/data和内部双缓存 |
| test_active控制热切换 | 使用已实现enable接口，启动同步锁定模式；换模式需共享复位 |
| key_scan/timbre_sel | 按合同例化sensor_frontend/control_panel |
| osc.sample_en | 按合同连接frame_tick；ADSR/mixer也接控制快照frame_tick |

B/C仍未完成：sensor_frontend/control_panel为空文件，osc/adsr/mixer旧桩端口尚未迁移至V1.1，其余模块也仍为桩。top按冻结合同预留接口，未把这些桩当成功能实现。因此，当前正式11文件清单尚不能完成真实全机编译；A组阶段测试使用测试平台内的接口替身。

## 连接关系

```text
外部rst_n -> 两级同步释放 + 启动模式锁定 -> core_rst_n -> 全部子模块
27MHz clk -> 所有模块
                       audio_timing -> 外部bclk/lrclk
                              | frame_tick / frame_load / fall_ce / bit_index
key_raw -> sensor_frontend -> note_event --+
                                         +-> 固定模式事件选择 -> voice_alloc
                           test_mode ----+                      |
control_panel -> timbre / signed bend -> osc x N -> adsr x N -> mixer -> i2s_tx -> i2s_data
                      master_gain ---------------------------> mixer
```

voice_alloc接收ADSR的busy/env_done；每路osc.wave/valid只连本路ADSR，ADSR.sample/valid打包给mixer，第0路在最低位。NVOICE合同支持4或8，实例数、打包宽度和分配器/混音器参数一致。PCM和bend线路声明signed；打包容器本身不参与算术。

## 复位与模式

外部rst_n必须在启动时实际拉低，不能假定寄存器任意上电状态可靠。复位异步拉低reset_sync、mode_sync、mode_locked、test_mode_latched、core_rst_n。释放后：

1. 第1/2个clk使reset_sync与test_enable的两级同步器稳定。
2. 第3个clk锁定同步后的模式；test_enable需在外部复位期间设置并保持到启动完成。
3. 第4个clk寄存器释放core_rst_n，子模块从随后的clk沿开始运行。

所有子模块使用同一个core_rst_n，不重复释放同步。运行中忽略外部模式开关变化，背压中的事件不会被切断。换模式先拉低外部rst_n，设定开关，再释放复位；事件队列、分配器、包络和输出链一起重启，不能只复位测试源。按键消抖、可靠上电复位和输入电平反相需结合真实板卡落实；当前外部输入按合同高有效。

## 事件与音频流水线

事件选择包含valid、key、note、on全组。evt_ready只回传当前锁定的源，未选源ready=0；core_rst_n=0时屏蔽有效事件和两路ready。内部调试线保留overflow_count、underrun_count、clip_count。

frame_tick只启动下一轮计算或锁存配置；osc.valid -> adsr.wave_valid -> mixer.voice_valid -> i2s_tx.sample_valid逐级传递结果。top直接连接mixer输出到发送器，未重复增加样本缓冲。i2s_tx在frame_load消费沿前的pending，同拍到达的新结果留到下一次装载。索引31仍发送旧帧右LSB，随后索引0开始新帧。

无有效样本时，首次装载为零，后续保持上一帧并统计欠载，采用已确认的V1.1策略。B组交付后应确认稳态欠载为0；不能把全零输出或欠载保持当作正常合成功能。

## A组验证入口

```powershell
# FPGA_Music根目录；Windows OSS CAD Suite的bin/lib需在PATH中
.\run_sim.bat tb_top
# 等价独立编译
iverilog -g2001 -Wall -s tb_top -o sim/tb_top.vvp -c tb/top_a_sources.f tb/tb_top.v
vvp sim/tb_top.vvp
# 8声部接线；PowerShell中将-P参数整体加引号
iverilog -g2001 -Wall -s tb_top '-Ptb_top.NVOICE=8' -o sim/tb_top_8.vvp -c tb/top_a_sources.f tb/tb_top.v
vvp sim/tb_top_8.vvp
```

run_sim.bat/run_sim.sh当前作为A组阶段入口，也支持tb_audio_timing、tb_i2s_tx、tb_test_mode、tb_clk_gen。sources.f是正式11模块清单；tb/top_a_sources.f仅列4个活动A模块，备用clk_gen只在自己的独立测试编译。

tb_top.v末尾包含B/C的测试接口替身。它们不实现传感器、事件队列、分配、DDS、包络或混音；仅用于绑定端口和注入刺激，绝不能加入正式综合，也不能与真实B/C同名模块同时编译。测试强制输入事件、各声部不同样本及mixer完成样本，是接线检查而非B/C算法验证。

实际验证（2026-10-21）：4/8声部A组测试通过，包括异步复位、4拍启动顺序、模式锁定、运行时开关变化忽略、正常/测试事件及ready路由、真实test_mode四条Note On、576拍调度、各路打包、signed控制传递、注入完成样本后的缓冲/串行位输出、欠载可观测性和复位换模式。该PASS仅代表A组集成，不代表完整系统通过。

GTKWave查看sim/tb_top.vcd，重点观察core_rst_n、mode_locked、test_mode_latched、evt_*、real_ready/test_ready、frame_tick/load、mixed_sample/valid和u_i2s_tx.pending/frame_sample。

## 后续联调与硬件验收

B/C实现并统一V1.1后，新建不含接口替身的整机测试：先验证事件到分配，再验证每路DDS/ADSR与混音，最后接入真实传感器/面板；记录每帧固定流水线延迟、valid对齐和零欠载。阶段性A测试继续保留作接线回归。

Gowin以top为顶层，按sources.f精确添加11个正式RTL，排除clk_gen和所有tb。当前约束仍为模板：top.sdc仅声明27MHz，top.cst尚无真实管脚。必须按实际板卡补齐输入、复位、传感器、面板和I2S引脚及外部时序，检查时钟资源、Setup/Hold、未约束路径、复位同步器和外部BCLK/DIN关系；本次不猜测管脚。

完整验收需测量控制输入、滤波输出、事件成交、样本完成、帧装载和I2S输出时刻，按最坏背压/相位计算≤10ms；另采集真实混音或I2S重建音频做FFT，核实4独立声部和持续音变调。板测还需验证46875Hz功放兼容性、长时间稳定性及真实控制维度。以上均未在本次执行；未进行Gowin综合、布局布线或上板，不宣称资源、STA、实际四复音或频谱已达标。

首次push前复查还补充了逐声部gate/trigger与busy/env_done的非零移动刺激；交换反馈线的临时错误会导致测试失败。详见test_records.md。
