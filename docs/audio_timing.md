# audio_timing 实现与验证

依据根目录《备份audio_timing.md》及接口规范V1.1。RTL为独立Verilog-2001模块，不使用PLL或厂商IP。

## 运行

从FPGA_Music目录执行（Windows OSS CAD Suite需将其bin和lib目录加入PATH）：

```powershell
iverilog -g2001 -Wall -s tb_audio_timing -o sim/tb_audio_timing.vvp rtl/audio_timing.v tb/tb_audio_timing.v
vvp sim/tb_audio_timing.vvp
```

波形：sim/tb_audio_timing.vcd。测试失败用Icarus扩展$finish_and_return(1)返回非零状态；RTL不含仿真任务。

## 发送端对接

| 下降沿消费的旧bit_index | 数据 | LRCLK沿后状态 | frame_load/tick |
|---|---|---|---|
| 15 | 左声道LSB | 1 | 0 |
| 16 | 右声道MSB | 1 | 0 |
| 31 | 旧帧右声道LSB | 0 | 1 |
| 0 | 新帧左声道MSB | 0 | 0 |

i2s_tx必须在clk上升沿使用bclk_fall_ce和旧bit_index；索引31用旧frame_sample发送最后一位，同时装载新样本。不得把使能再寄存一拍，不得使用BCLK作内部逻辑时钟。frame_tick与frame_load同沿，每576拍一次。复位释放第9拍是前导上升沿，第18拍首次装载，第36拍准备首个左MSB。

top负责复位同步释放。当前top仍是旧接口骨架，本次模块未接入整机；sources.f和旧run_sim入口仍需在整机迁移时统一，使用以上独立命令验证本模块。

## 实际验证

2026-10-21：Icarus以-g2001 -Wall编译无诊断，仿真退出码0，输出：

```text
PASS: audio_timing, 103 complete frames, startup and two running resets
```

测试逐拍检查启动、9/18拍BCLK周期、使能同沿且单拍互斥、索引序列、LRCLK边界及提前18拍、288/576拍WS周期、每帧32位且左右各16位、frame使能与周期、未知态、半周期及帧中途复位后重启。未进行Gowin综合、布局布线、板测或整机延迟验证。
