# test_mode 自动和弦事件发生器

## 采用的接口与范围

依据根目录《test_mode备份.md》，遵循其中“以团队确认的冻结接口为准”的约定，保留interfaces.md V1.1：clk、rst_n、enable、evt_ready输入，evt_valid、evt_key_id[2:0]、evt_note[6:0]、evt_on输出。不增加frame_tick、test_enable或test_active端口。

大纲的运行中退出清理方案需要test_active与top路由配合，当前V1.1采用启动锁定模式，因此不实现热切换。enable由top同步后启动锁定，在一次运行期间保持不变；换模式必须同时复位test_mode、voice_alloc及音频链。仅关闭enable不能代替共享复位：源会停止发事件，但此前已经分配的声部不会由该动作释放。不得将原始异步开关直接接enable或事件选择器。

模块默认只实现演示A：四音持续和弦。无演示类型选择端口，不增加隐藏的顺序音符模式。

## 状态机与握手

```text
IDLE -> NOTE_ON -> HOLD -> NOTE_OFF -> RELEASE_WAIT -> NOTE_ON ...
```

- NOTE_ON依次发送key 0/1/2/3，对应MIDI 60/64/67/72，evt_on=1。仅在evt_valid && evt_ready的clk上升沿推进。
- 第4条Note On握手成功后，四个键同时保持，进入HOLD；该握手沿不计入保持计数。
- HOLD完成后NOTE_OFF按同样顺序发送匹配键与音号，evt_on=0。
- 最后一条Note Off握手完成后进入RELEASE_WAIT，等待结束再完整重播。
- 背压期间状态和事件索引保持，valid及所有字段稳定；valid不组合依赖ready。
- rst_n异步拉低后状态、索引和计数清零，事件输出全部为0。复位释放且enable=0时不发事件。

这是测试事件发生器，不生成音频样本、音色、I2S或DDS频率控制字。四个事件逐clk握手，不能在单事件总线上同拍发送4条。

## 计时合同

V1.1没有frame_tick端口，因此按固定27MHz主时钟计算等效帧时长；不生成第二份音频时钟或帧调度输出，不要求演示动作与I2S帧边界对齐。

| 参数/常量 | 默认值 | 含义 |
|---|---|---|
| HOLD_FRAMES | 93750 | 保持2秒的等效音频帧数 |
| RELEASE_FRAMES | 11719 | 释放等待约0.250005333秒 |
| CLOCKS_PER_FRAME | 576，固定 | 27MHz/46875Hz |
| HOLD_LAST | HOLD_FRAMES*576-1 | 保持计数终值 |
| RELEASE_LAST | RELEASE_FRAMES*576-1 | 释放等待计数终值 |

参数合法范围均为1..3728270，保证乘576不超过正32位integer范围；内部等待计数器32位。默认保持54,000,000个clk，释放等待6,750,144个clk。

设第4条Note On在沿T成功，第一条Note Off的valid在沿T+HOLD_FRAMES*576更新后出现；最快在下一clk沿握手。释放等待同理，从第4条Note Off成功开始计算。背压只延长事件发送阶段，不会缩短保持或释放等待。释放等待是固定演示间隔，并未观测ADSR的env_done，不能认为所有包络必然已结束。

## top连接

```verilog
test_mode u_test_mode (
    .clk(clk), .rst_n(core_rst_n), .enable(test_mode_latched),
    .evt_ready(test_ready), .evt_valid(test_valid),
    .evt_key_id(test_key), .evt_note(test_note), .evt_on(test_on)
);
```

启动前由top同步test_enable并锁定test_mode_latched，锁定前保持各模块复位。事件选择整组切换valid/key/note/on；voice_alloc.evt_ready仅回传到所选源，未选源ready=0。正常源是note_event，测试源是本模块；最终统一通过voice_alloc -> osc -> adsr -> mixer -> i2s_tx，不绕过合成引擎。audio_timing继续提供真实音频链的frame_tick。

当前top仍是旧骨架，尚未完成上述模式锁定与统一接口迁移；本次仅独立验证test_mode。

## 仿真

在FPGA_Music根目录执行；Windows OSS CAD Suite需将其bin与lib目录加入PATH：

```powershell
iverilog -g2001 -Wall -s tb_test_mode -o sim/tb_test_mode.vvp rtl/test_mode.v tb/tb_test_mode.v
vvp sim/tb_test_mode.vvp
gtkwave sim/test_mode.vcd
```

自检覆盖HOLD_FRAMES=2、RELEASE_FRAMES=1以缩短时间，正式默认值不变。失败使用Icarus扩展$finish_and_return(1)返回非零状态，仅存在于测试平台。每次成功握手打印周期、key、note和on。波形重点查看state、event_index、wait_count和事件总线，检查阻塞时稳定、最后一次握手与计时起点的关系。

2026-10-21实际运行：Verilog-2001编译无诊断，仿真退出码0：

```text
PASS: test_mode, 72 checked handshakes, 7 complete rounds, stalls and reset restarts
```

覆盖复位零输出、禁用静默、两轮连续完整演示、精确保持/释放时长、四键同时按下、匹配Note Off、固定长背压和确定性伪随机背压；在第1/2/3/4条Note On后、Note Off中途及待发事件被阻塞时复位并重新启动。测试平台同步清除其声部记账，模拟共享复位；没有声称验证真实voice_alloc。热切换退出清理测试不适用于本版接口，未实现或测试该扩展。

尚未进行Gowin综合、布局布线、真实top/voice_alloc联调、板测或音频FFT。正式上板前需检查复位和模式锁定、事件路由、4个独立声部分配、全部时序约束、I2S引脚及功放配置，并实测46875Hz兼容性与频谱。本模块测试不证明实际四复音、FFT峰值或整机≤10ms延迟。
