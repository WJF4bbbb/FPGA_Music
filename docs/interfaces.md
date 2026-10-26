# FPGA_Music 模块接口规范

版本：V1.1　日期：2026-10-21　维护人：A

**这份文件就是三个人写代码时共同遵守的“接线合同”。先按端口写代码，再由 top.v 接起来。**

建议放在工程 `FPGA_Music/docs/模块接口规范.md`。本版以已核对的《团队分工与开发计划(2).md》和本聊天的 audio_timing 详细时序约定为基础，统一名称并补齐未定接口。若旧计划、旧骨架与本文件冲突，后续开发以本文件为准。

本次修订的是规范，未修改你电脑或 GitHub 的工程。本版已按最新截图统一命名；原V1.0中的旧命名不再作为后续依据。旧骨架需要按第9节迁移；端口统一并不代表功能已经通过仿真、综合或板测。

## 1. 先看全局：谁负责哪一段

| 人员 | 负责的文件 | 作用 |
|---|---|---|
| A | top.v | 连接所有模块、处理复位和测试模式选择 |
| A | audio_timing.v | 产生音频时钟和每帧采样节拍 |
| A | i2s_tx.v | 把算好的样本串行发送给功放 |
| A | test_mode.v | 自动发出测试音符指令，验证多复音 |
| B | voice_alloc.v | 把音符分给不同声部 |
| B | osc.v | 每个声部产生自己的波形 |
| B | adsr.v | 给每个声部添加起音、衰减、保持和释放 |
| B | mixer.v | 合并声部、调总音量并防溢出 |
| C | sensor_frontend.v | 读取8路传感器并滤除短干扰 |
| C | control_panel.v | 读取音色、变调和音量控制键 |
| C | note_event.v | 把按下/松开变成带身份的音符指令 |

**最终采用：截图的新命名 + 27MHz直接分频方案。当前参与运行的RTL共11个；截图中的第12个文件clk_gen.v保留为备用PLL封装，当前不例化、不加入仿真/综合源列表。**

sensor_frontend.v取代旧名key_scan.v，control_panel.v取代旧名timbre_sel.v；文件名与module名一起改，职责和本规范规定的端口保持一致。

### 1.1 为什么当前选这套方案

| 方案 | 需要实现的内容 | 本轮决定 |
|---|---|---|
| 27MHz直接分频 | audio_timing固定9拍半周期，fs=46875Hz；DDS按实际fs算音高 | **正式采用**，保持一个内部时钟域和已定时序合同 |
| clk_gen封装PLL，再接audio_timing | 核实PLL可实现频率、锁定过程、时钟约束；按新时钟重算分频/FCW/包络，并重新测试 | 作为未来分支，本轮不启用 |

理由：现有赛题未要求必须48kHz，也未要求必须使用PLL。直接分频可得到固定、等间隔的采样节拍，不会因为标称采样率不是48kHz就必然音不准，关键是DDS使用46875Hz。先完成低延迟、多复音和演奏交互，更符合本轮进度。

截图只展示文件职责，并不能证明当前代码已按这些接口实现。若未来决定启用PLL，先更新本规范和时序测试，再修改代码；不能把新时钟直接接入仍按27MHz写死的audio_timing。

**两个模块职责不同：clk_gen若启用只产生内部主时钟并报告锁定；audio_timing负责由该时钟生成I2S时序。它们不是相同功能的两个分频器。当前方案只是暂时不需要前者。**

音频计算方向：选音输入 → sensor_frontend → note_event → voice_alloc → osc×N → adsr×N → mixer → i2s_tx → 功放。

test_mode 在测试时替代 note_event 提供指令；audio_timing 给合成与发送部分提供统一节拍；control_panel 提供音色、变调和总音量。

## 2. 全队先记住的规则

### 2.1 固定数值

| 项目 | 本版约定 |
|---|---|
| 主时钟 clk | 27,000,000Hz |
| BCLK | 1,500,000Hz，每9个clk周期翻转 |
| LRCLK / 实际采样率 | 46,875Hz，不写成48kHz |
| 每帧长度 | 32个BCLK周期，即576个clk周期 |
| 音频格式 | 16位有符号补码、MSB先发、标准Philips I2S |
| 左右声道 | 发送同一个单声道混音样本 |
| NVOICE | 默认4；升至8时，分配器、总线、例化和混音一起修改 |
| 波形相位 | 每个osc独立32位相位累加器 |
| 8个键的音号 | 60、62、64、65、67、69、71、72 |

这些是工程选择；4复音、两维交互和总延迟≤10ms等是整机验收目标，不是本文件已经证明的结果。

### 2.2 这些名字是什么意思

| 名字 | 大白话 | 规则 |
|---|---|---|
| clk | 内部统一节拍 | 所有模块只用它作逻辑时钟 |
| rst_n | 复位 | 0为复位，1为运行 |
| frame_tick | 开始算下一帧 | 只启动一次计算，不能当时钟 |
| xxx_valid | 这一拍的数据有用 | 音频链一般只高1个clk周期 |
| evt_ready | 接收方能收指令 | 只有evt_valid和evt_ready同时为1才成交 |
| gate | 这个音是否还按着 | 电平；变0后进入Release，不一定立即无声 |
| trigger | 重新开始起音 | 1个clk周期脉冲，不能丢 |
| busy | 包络还没完全结束 | 包括松手后的Release |
| env_done | 释放结束通知 | 1个clk周期脉冲 |

音频链的valid与事件流的valid规则不同：**事件流可以因为等待ready而持续多拍；音频结果不等待ready，每帧只提交一次。**

所有跨模块信号均属于clk域。原始传感器和按键先同步再处理。禁止用bclk或lrclk给内部always块作时钟。

### 2.3 复位由谁处理

外部rst_n只进入top的复位处理逻辑。A在top内完成“异步拉低、至少两级触发器同步释放”，内部信号命名为core_rst_n。

下面各子模块的rst_n端口都接core_rst_n。子模块不再各自多加一套复位释放同步器。

复位时：事件valid、音频valid、gate、trigger、busy、env_done和所有统计计数清零；音频输出为0。audio_timing的索引和LRCLK有专门启动值，见第3节。

## 3. A负责的模块

本节及第4、5节中的端口表是完整外部接口；内部寄存器名称可以自定。除明确标注signed之外，其余端口均为无符号。

### 3.1 audio_timing.v：统一节拍

| 方向 | 端口 | 位宽 | 接到哪里 / 含义 |
|---|---|---|---|
| 输入 | clk | 1 | 主时钟 |
| 输入 | rst_n | 1 | 内部复位 |
| 输出 | bclk | 1 | top的bclk输出，送功放 |
| 输出 | lrclk | 1 | top的lrclk输出，送功放 |
| 输出 | bclk_rise_ce | 1 | BCLK即将上升的clk使能；可供调试 |
| 输出 | bclk_fall_ce | 1 | i2s_tx，同沿准备串行数据 |
| 输出 | bit_index | 5 | i2s_tx，将要发送的位编号0～31 |
| 输出 | frame_load | 1 | i2s_tx，锁存新一帧样本 |
| 输出 | frame_tick | 1 | 所有osc、adsr及mixer，启动/快照下一帧计算 |

**边沿合同：**用当前half_cnt=8及当前bclk组合译码rise/fall使能，并在rst_n=0时屏蔽。下游在使能有效的同一个clk上升沿动作；不要让使能比实际BCLK边沿晚一拍。

bit_index是“本次下降沿要发的位”。下降沿动作使用更新前的索引，随后索引加1。0～15为左声道MSB至LSB，16～31为右声道MSB至LSB。

| 本次下降沿读取的索引 | 本次发送的数据 | LRCLK动作 | frame_load / frame_tick |
|---|---|---|---|
| 15 | 左声道LSB | 置1，提前通知右声道 | 0 |
| 16 | 右声道MSB | 保持1 | 0 |
| 31 | 旧帧右声道LSB | 置0，提前通知左声道 | 1 |
| 0 | 新帧左声道MSB | 保持0 | 0 |

两种frame使能始终相等，均为 `bclk_fall_ce && (bit_index == 31)`。这样在新帧MSB前一个BCLK周期装载样本；每帧仍是32位，不额外插空位。

复位值：half_cnt=0、bclk=0、lrclk=1、bit_index=31。释放后第9个clk产生首次上升沿，第18个clk产生首次下降沿并消费首次frame使能。启动前导输出零，不算一帧有效音乐。

### 3.2 i2s_tx.v：把样本发出去

| 方向 | 端口 | 位宽 | 来源 / 去向 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共时钟、内部复位 |
| 输入 | sample | signed 16 | mixer.sample |
| 输入 | sample_valid | 1 | mixer.valid |
| 输入 | bclk_fall_ce | 1 | audio_timing |
| 输入 | bit_index | 5 | audio_timing |
| 输入 | frame_load | 1 | audio_timing |
| 输出 | data | 1 | top.i2s_data，再到功放DIN |
| 输出 | underrun_count | 32 | top内部调试线，不必占外部引脚 |

模块不再自己分频，也不需要把bclk接成内部时钟。

内部至少两份样本缓存：pending_sample收新计算结果；frame_sample固定用于当前完整左右声道。sample_valid=1时接收sample，frame_load=1时才换frame_sample。

索引31时仍用旧frame_sample发送右声道LSB，同时锁存新frame_sample；下一次索引0才开始发送新帧。左右不能取到两个不同样本。

消费pending后清有效标志。若sample_valid恰好与frame_load同沿，新结果留给下一次装载，本次只消费沿前已有pending；引擎应提前完成，不能依赖边界同拍“抢到”数据。

首次frame_load允许装载零且不计欠载；从第二次起，未拿到新结果就增加underrun_count并保留上一帧。稳态验收计数应为0。计数达到最大值后保持，不回绕。

### 3.3 test_mode.v：自动发测试音符

| 方向 | 端口 | 位宽 | 含义 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共信号 |
| 输入 | enable | 1 | top锁定的测试模式 |
| 输入 | evt_ready | 1 | top回传的事件接收能力 |
| 输出 | evt_valid | 1 | 有测试指令，遵守ready/valid握手 |
| 输出 | evt_key_id | 3 | 测试键身份0～7 |
| 输出 | evt_note | 7 | MIDI音号 |
| 输出 | evt_on | 1 | 1按下，0松开 |

默认测试用4个不同音号，依次发note_on后同时保持发声；后续可逐个发note_off。测试声部必须经过同一套voice_alloc、osc、adsr、mixer、i2s_tx，不得另播放PCM。

enable=0时不发指令。enable=1时背压必须保持整条指令不变，直到握手成功。

### 3.4 top.v：总装及外部接口

参数：NVOICE=4；目前只支持4或8。

| 方向 | 端口 | 位宽 | 含义 |
|---|---|---|---|
| 输入 | clk | 1 | 板载27MHz |
| 输入 | rst_n | 1 | 外部低有效复位 |
| 输入 | key_raw | 8 | 8路原始选音传感器信号 |
| 输入 | timbre_key | 1 | 音色切换键 |
| 输入 | bend_up_key、bend_down_key | 各1 | 升/降调键 |
| 输入 | volume_up_key、volume_down_key | 各1 | 音量键 |
| 输入 | test_enable | 1 | 启动时选择正常/测试模式 |
| 输出 | bclk、lrclk | 各1 | 音频时钟 |
| 输出 | i2s_data | 1 | I2S串行数据 |

顶层外部键/传感器统一约定高电平为按下或触发；实际硬件相反时，由A在明确位置反相，不能两个人各反一次。

基础版不做演奏中热切换测试模式：test_enable在外部复位期间设置，并保持到启动完成。A先在clk域同步test_enable，启动时锁定模式，模式锁定前保持其他模块复位；运行中忽略模式变化。换模式按复位重新启动，避免残留音符、旧队列和半帧切换。同步与锁定是top职责，不交给test_mode猜测。

未启用的事件源由top给evt_ready=0；两个源不能同时驱动voice_alloc。模式锁定前内部不运行。统计线保留在top内部，便于仿真/逻辑分析，不要求全部引出管脚。

### 3.5 clk_gen.v：备用，不接入当前工程

| 项目 | 当前决定 |
|---|---|
| 负责人 | A |
| 职责 | 未来确有需要时封装PLL及锁定状态 |
| 当前是否运行 | 否，top不例化 |
| 当前是否加入sources.f或Gowin源列表 | 否 |
| 当前是否需要编写PLL实现 | 否 |
| 当前端口是否冻结 | 否；启用PLL前重新评审，不能让其他模块依赖未定义端口 |

文件可保留说明注释，或移到备用目录；不用为了凑齐12个运行模块再加一层时钟。若其中已经有代码，先保留，再从当前有效源列表排除，不要求直接删除。

当前所有活动模块的clk仍来自top.clk，均为27MHz。未来启用PLL的变更另发新版本，包含锁定前复位保持及必要的跨域处理。

## 4. C负责的模块

### 4.1 sensor_frontend.v：原始输入变成稳定键状态

| 方向 | 端口 | 位宽 | 来源 / 去向 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共信号 |
| 输入 | key_raw | 8 | top.key_raw |
| 输出 | key_state | 8 | note_event.key_state；1表示触发 |

每路独立同步和滤波；不能按下一个键就屏蔽其他键。光电输入初始滤波值5400拍，即0.2ms；机械替身应单独评估，不把0.2ms当通用机械消抖保证。

本模块不负责MIDI音号，不发音符事件。

### 4.2 control_panel.v：所有面板配置

| 方向 | 端口 | 位宽 | 含义 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共信号 |
| 输入 | timbre_key | 1 | 切换音色 |
| 输入 | bend_up_key、bend_down_key | 各1 | 实时变调 |
| 输入 | volume_up_key、volume_down_key | 各1 | 调整总音量 |
| 输出 | timbre | 2 | 所有osc.timbre |
| 输出 | bend | signed 4 | 所有osc.bend，单位半音 |
| 输出 | master_gain | 16 | mixer.master_gain，无符号增益 |

本模块正式命名为control_panel，职责包含整块控制面板；旧timbre_sel.v不再作为另一套模块并行运行。

初版timbre只用0和1，按一下切换一次，长按不反复切。bend约定：只按升调键为+2，只按降调键为−2，都不按或同时按为0。必须声明signed，否则负值会被误读。

master_gain范围0～65535，0静音、65535接近单位增益。复位为16384（约25%）；音量加/减每次约4096，边界钳位，不能回绕。输入键由本模块同步和消抖，输出为clk域内稳定配置值。

### 4.3 note_event.v：键状态变指令

| 方向 | 端口 | 位宽 | 来源 / 去向 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共信号 |
| 输入 | key_state | 8 | sensor_frontend |
| 输入 | evt_ready | 1 | top回传 |
| 输出 | evt_valid | 1 | top事件选择逻辑 |
| 输出 | evt_key_id | 3 | 发生变化的键编号 |
| 输出 | evt_note | 7 | 该键对应的MIDI音号 |
| 输出 | evt_on | 1 | 1按下，0松开 |
| 输出 | overflow_count | 32 | top内部调试线，饱和计数 |

键编号与音号固定如下：

| key_id | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| MIDI音号 | 60 | 62 | 64 | 65 | 67 | 69 | 71 | 72 |
| 音名 | C4 | D4 | E4 | F4 | G4 | A4 | B4 | C5 |

一次多个键变化，必须全部排队；同批先松后按，再按key_id从小到大排序。不同批次保持时间顺序。至少32条缓存，不允许静默丢note_off；满时明确计数并判该测试失败。持键到复位释放后，应识别成一次按下。

## 5. B负责的模块

### 5.1 voice_alloc.v：声部分配

参数：NVOICE=4，支持4或8。

| 方向 | 端口 | 位宽 | 来源 / 去向 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共信号 |
| 输入 | evt_valid | 1 | top选定的事件源 |
| 输出 | evt_ready | 1 | top，再回传给选定事件源 |
| 输入 | evt_key_id | 3 | 键身份 |
| 输入 | evt_note | 7 | 音号 |
| 输入 | evt_on | 1 | 按下/松开 |
| 输入 | voice_busy | NVOICE | 各adsr.busy拼接 |
| 输入 | env_done | NVOICE | 各adsr.env_done拼接 |
| 输出 | voice_note | 7×NVOICE | 各osc.note |
| 输出 | voice_gate | NVOICE | 各adsr.gate |
| 输出 | voice_trigger | NVOICE | 各adsr.trigger |

按下时立即记录声部占用和key_id，并发trigger；不能等busy返回后才记占用，否则相邻两条指令可能分到同一路。

松开只降低匹配key_id的gate，等待Release结束。分配器保留自己的占用记录，不能把刚分配但busy尚未升高的声部误判空闲。

分配顺序：空闲声部优先；其次抢占Release中的声部；最后抢占最早按下的声部。同级并列选编号小的声部。重按同键复用其现有声部并发trigger。过期note_off不得关闭已被其他键占用的声部。

env_done清占用的同沿若有新分配/重触发，以新分配为准。抢占不清DDS相位；包络从当前值重新Attack，避免直接阶跃清零。

### 5.2 osc.v：单声部振荡器

参数：FS_HZ=46875。当前仅支持这个采样率，不声称任意参数值都已验证。

| 方向 | 端口 | 位宽 | 来源 / 去向 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共信号 |
| 输入 | frame_tick | 1 | audio_timing |
| 输入 | note | 7 | voice_note中本路音号 |
| 输入 | timbre | 2 | control_panel |
| 输入 | bend | signed 4 | control_panel |
| 输出 | wave | signed 16 | 本路adsr.wave |
| 输出 | valid | 1 | 本路adsr.wave_valid |

每次frame_tick读取一次note/timbre/bend，并推进独立相位，最终输出一个wave和一拍valid；计算中不再读可能变化的配置。

保留相位连续性，变调时只改频率控制字。A4在46875Hz下的32位FCW为40315426。复位note对应输入尚未有效时不得产生X；不支持的音号/音色应给出明确定义的安全结果，不访问越界ROM。

即使声部闲置也每帧输出一次确定波形；静音由ADSR完成。所有osc实例的valid延迟必须相同。

### 5.3 adsr.v：单声部包络

参数：FS_HZ=46875。

| 方向 | 端口 | 位宽 | 来源 / 去向 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共信号 |
| 输入 | frame_tick | 1 | audio_timing，用于锁存本帧控制 |
| 输入 | wave_valid | 1 | 本路osc.valid |
| 输入 | wave | signed 16 | 本路osc.wave |
| 输入 | gate | 1 | 本路voice_gate |
| 输入 | trigger | 1 | 本路voice_trigger |
| 输出 | sample | signed 16 | mixer中本路样本 |
| 输出 | valid | 1 | mixer中本路有效标志 |
| 输出 | busy | 1 | voice_alloc中本路voice_busy |
| 输出 | env_done | 1 | voice_alloc中本路完成通知 |

trigger可能只持续一个clk、发生在两帧之间，必须内部缓存。frame_tick时锁存gate和待处理trigger，随后wave_valid到达时按这一帧的控制更新包络、计算样本。

frame_tick之后新来的trigger留到下一帧；不能误用于已经启动的本帧。trigger与frame_tick同沿时纳入本次快照。frame_tick读取的仍是沿前的分配器输出，同沿新发出的trigger自然由后续拍捕获，不算漏事件。

Release结束后busy才为0，并给一拍env_done。若同一次包络更新有新trigger，优先重新Attack，不发送旧音的完成通知。连续出现多次短于一帧的重触发可合并到该帧，但最终gate及键身份不能出错。

闲置声部也必须在每次wave_valid后输出sample=0和一拍valid。不能因静音取消valid，否则mixer等不到全路数据。

### 5.4 mixer.v：混音与总音量

参数：NVOICE=4，支持4或8。

| 方向 | 端口 | 位宽 | 来源 / 去向 |
|---|---|---|---|
| 输入 | clk、rst_n | 各1 | 公共信号 |
| 输入 | frame_tick | 1 | audio_timing，锁存本帧总音量 |
| 输入 | voice_samples | 16×NVOICE | 各adsr.sample拼接 |
| 输入 | voice_valid | NVOICE | 各adsr.valid拼接 |
| 输入 | master_gain | 16 | control_panel |
| 输出 | sample | signed 16 | i2s_tx.sample |
| 输出 | valid | 1 | i2s_tx.sample_valid |
| 输出 | clip_count | 32 | top内部调试线，饱和计数 |

本版要求所有声部valid同拍到达。mixer在全路有效时接收同一帧，每帧只输出一次；不缓存错位帧来掩盖上游错误。

frame_tick先锁存总音量，混音时使用该快照。内部至少32位有符号求和；4路默认总和右移2位，8路右移3位，再乘总音量，最终饱和到−32768～32767。

master_gain的标度固定为gain/65536：65535是接近1，不是精确1。乘法前将无符号增益扩成非负signed数，不能把16'hFFFF当成−1。

## 6. 重点接线：top照这张表连接

### 6.1 控制链

| 发送端 | 接收端 |
|---|---|
| top.key_raw | sensor_frontend.key_raw |
| sensor_frontend.key_state | note_event.key_state |
| top的5个面板键 | control_panel对应的5个同名输入 |
| control_panel.timbre | 所有osc.timbre |
| control_panel.bend | 所有osc.bend |
| control_panel.master_gain | mixer.master_gain |
| note_event / test_mode的evt_* | top选择后接voice_alloc的同名输入 |
| voice_alloc.evt_ready | top仅回传给当前选定的事件源 |

事件选择必须整组切换：evt_valid、evt_key_id、evt_note、evt_on。未选源的evt_ready=0，不把两个valid直接相或。

### 6.2 音频链

| 发送端 | 接收端 |
|---|---|
| voice_alloc.voice_note第i路 | 第i个osc.note |
| voice_alloc.voice_gate第i位 | 第i个adsr.gate |
| voice_alloc.voice_trigger第i位 | 第i个adsr.trigger |
| 第i个osc.wave / valid | 第i个adsr.wave / wave_valid |
| 第i个adsr.sample / valid | mixer.voice_samples第i路 / voice_valid第i位 |
| 第i个adsr.busy / env_done | voice_alloc.voice_busy / env_done第i位 |
| mixer.sample / valid | i2s_tx.sample / sample_valid |
| audio_timing.frame_tick | 所有osc、所有adsr、mixer的frame_tick |
| audio_timing.frame_load | i2s_tx.frame_load |
| audio_timing.bclk_fall_ce / bit_index | i2s_tx同名端口 |
| audio_timing.bclk / lrclk | top同名输出 |
| i2s_tx.data | top.i2s_data |

### 6.3 多声部打包怎么理解

第0路放在低位，第1路接着放，依次类推。

| 总线 | 第i路取法 | 4路时的总宽度 |
|---|---|---|
| voice_note | voice_note[i*7 +: 7] | 28位 |
| voice_samples | voice_samples[i*16 +: 16] | 64位 |
| voice_gate / trigger / busy / done / valid | 对应总线[i] | 每根4位 |

voice_samples整根总线只是位容器，不当作一个大有符号数参与计算；取出的每一路必须赋给signed 16位信号，再扩展求和。

例如第0路样本是[15:0]、第1路是[31:16]。不要把拼接顺序反过来。

## 7. 运行时序：每帧只算一次

| 顺序 | 发生什么 |
|---|---|
| 1 | frame_load与frame_tick同沿：i2s_tx装载之前算好的样本；osc/adsr/mixer启动或锁存新一帧控制 |
| 2 | osc算出波形，拉高valid |
| 3 | adsr收到wave_valid，更新包络并算出本路sample |
| 4 | 所有声部valid对齐，mixer求和后输出sample与valid |
| 5 | i2s_tx把结果存入pending，等待下一次frame_load |

**只有osc用frame_tick启动波形计算；ADSR数据处理跟wave_valid走，mixer数据处理跟voice_valid走。**它们新增的frame_tick输入只是控制快照，不用于直接抢读尚未完成的数据。

从一次frame_tick到对应结果被i2s_tx接收，目标不超过128个clk周期，并必须早于下一次frame_load；绝不能超过576拍。此处为预算，具体流水线延迟由B实现后报告。所有声部使用相同固定流水线延迟，复位和启动帧也不能出现一部分声部有valid、另一部分没有的情况。

## 8. 写代码前的核对清单

1. 文件名、module名、端口名和位宽与本文件一致。
2. 公共时钟只接clk，子模块复位只接top生成的core_rst_n。
3. wave、sample、bend声明signed，混音每路取出后符号扩展。
4. note_event与test_mode遵守ready/valid背压；音频链valid每帧一次。
5. ADSR不会丢失两帧之间的trigger，静音声部仍交付valid。
6. bit_index、LRCLK和frame_load严格采用第3.1节同一边沿定义。
7. i2s_tx在索引31发送旧帧LSB，不误用刚装入的新样本。
8. 4声部与8声部使用一致NVOICE；无未连接输入和多驱动输出。
9. 仿真检查接口之后，再分别验证算法、I2S解码、整机延迟及板卡时序。

单元仿真推荐按职责补齐：tb_audio_timing、tb_i2s_tx、tb_top由A负责；B/C分别为自己的模块补测试。tb不是正式硬件模块，不能参与顶层综合。

## 9. 旧工程怎么迁移

| 旧名称/接口 | 统一后的做法 |
|---|---|
| 旧clk_gen承担音频分频 | 音频分频统一由audio_timing负责；现有clk_gen.v只保留为备用PLL封装，当前不例化、不加入源列表 |
| key_scan.v / module key_scan | 改成sensor_frontend.v / module sensor_frontend，更新top与tb |
| timbre_sel.v / module timbre_sel | 改成control_panel.v / module control_panel，更新top与tb |
| sample_en | osc改为frame_tick；不得把旧名字与新名字随意混用 |
| bit_fall_ce | 统一为bclk_fall_ce |
| 旧i2s_tx内部自己分频 | 删除重复分频，使用audio_timing提供的使能和位位置 |
| note / note_on / valid事件 | 统一为evt_note / evt_on / evt_valid，加evt_key_id与evt_ready |
| v0_note至v3_note等硬编码端口 | 改成按NVOICE打包的voice_note等总线 |
| adsr只输入wave和sample_en | 改用wave_valid，并增加frame_tick作控制快照 |
| mixer只等采样节拍 | 改为voice_valid收数据，并用frame_tick锁存增益 |
| 旧timbre_sel只处理音色键 | 改名control_panel并采用本版完整面板接口 |

这些改动需要在本地工程实际完成；本文没有自动覆盖旧代码。

以后修改接口，由A更新本文件版本号和改动说明，同时修改端口声明、top例化和受影响的tb。B/C可以调整模块内部实现，但不能自行改变端口含义。

### 9.1 当前sources.f固定清单

下面是当前11个活动RTL文件，路径相对于FPGA_Music根目录；同一清单用于核对Gowin源列表。tb文件只在对应仿真命令中添加。

```text
rtl/top.v
rtl/audio_timing.v
rtl/i2s_tx.v
rtl/test_mode.v
rtl/voice_alloc.v
rtl/osc.v
rtl/adsr.v
rtl/mixer.v
rtl/sensor_frontend.v
rtl/control_panel.v
rtl/note_event.v
```

当前不加入rtl/clk_gen.v、旧key_scan.v或旧timbre_sel.v。若旧文件尚未移走，避免用rtl/*.v把旧版本和备用PLL文件全部自动加入。

C的测试文件对应改名为tb_sensor_frontend.v、tb_control_panel.v；A的节拍测试文件使用tb_audio_timing.v。接口信号名key_raw、key_state、timbre等保持本文件定义，不因文件改名再随意变更。

### 9.2 V1.1修改记录

- 采纳截图中的sensor_frontend、control_panel正式命名，更新所有端口来源、连接表与职责说明。
- 明确当前采用27MHz直接分频，仍保持46.875kHz，不引入PLL新时钟。
- 区分11个活动模块与1个备用clk_gen；补充精确源文件清单。
- audio_timing、i2s_tx及B组模块的端口、I2S位边界和ready/valid合同保持V1.0定义，避免为改文件名重写算法。

## 10. 发给AI写模块时，附上这段话

请依据《模块接口规范》V1.1编写指定模块。严格保持本文的模块名、端口名、方向、位宽、符号、时钟域和握手语义。只能改变内部实现，不得自行增加第二套分频、改变实际采样率，或把事件valid当成无握手的一拍脉冲。编写audio_timing和i2s_tx时，特别核对索引15/16/31/0及frame_load的旧值/新值关系；编写ADSR和mixer时，按规定锁存控制并逐级传递valid。若发现规格矛盾，先指出。请提供完整代码、自检testbench及真实验证状态；没有实际运行的测试不能声称通过。
