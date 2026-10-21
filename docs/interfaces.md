# 接口规范（工程骨架）

所有内部模块用 clk（27MHz）和已同步释放的低有效 rst_n。
保持所要求的 clk_gen/key_scan/timbre_sel 文件名；不另改名为 audio_timing/sensor_frontend。

| 接口 | 约定 |
|---|---|
| 时钟 | clk_gen 计划输出 BCLK=1.5MHz，LRCLK=46.875kHz；内部用使能，不使用BCLK作逻辑时钟 |
| 帧调度 | frame_load 装载完成样本，sample_en 请求下一帧；每576个sys_clk一次 |
| I2S位置 | bit_index 对应下降沿将发出的帧内数据位，0..15左/16..31右；MSB先发；clk_gen的WS需提前下一MSB一个BCLK变化 |
| 事件流 | evt_valid && evt_ready 才消费；背压时保持数据；on=1按下/0松开；key_id区分物理键 |
| 多键 | note_event用>=32项FIFO；同批先松后按，不得静默丢失note_off |
| 琴键映射 | 0..7 -> MIDI 60,62,64,65,67,69,71,72 |
| 声部打包 | voice_note[i*7 +: 7]为第i路音号；voice_samples[i*16 +: 16]为signed16样本的位模式 |
| 实时变调 | bend是signed半音数；先实现-2/0/+2，持续音改频不清相位 |
| 音频流水线 | osc.valid -> adsr.wave_valid -> mixer.voice_valid -> i2s.sample_valid；每级固定深度且帧对齐 |
| ADSR | trigger须缓存到下一个样本，Release结束才清busy；env_done完成脉冲 |
| 增益 | master_gain无符号0..65535；转换为非负signed扩展后再乘法 |
| 完成预算 | 引擎目标<=128拍且必须<576拍；未实测 |

当前所有子模块都是输出固定值的桩；top只是连接模板。
A仍需补：复位调理、异步test_enable同步/模式切换清音、控制参数逐帧快照。
复位调理和模式控制可在top内写少量胶合逻辑或独立模块；不要保留原始异步输入直接进状态机。
当前timbre_sel为保留文件名承担全部面板控制；团队若拆分须同步修改top和规范。
所有FIFO、ROM、DDS、ADSR、混音、I2S、同步器和分频器算法均待实现。
