# i2s_tx 实现与对接

## 接口决策

本次用户确认采用《模块接口规范》V1.1。附件《i2s_tx备份.md》的串行时序、位序和测试要求适用，但其单缓存sample_in/i2s_data接口不采用。正式接口如下：

| 端口 | 方向/位宽 | 含义 |
|---|---|---|
| clk / rst_n | 输入，各1位 | 27MHz / top同步释放的低有效复位 |
| sample | 输入，signed 16位 | mixer的补码样本 |
| sample_valid | 输入，1位 | 本拍提交有效样本 |
| bclk_fall_ce | 输入，1位 | audio_timing的下降沿预使能 |
| bit_index | 输入，5位 | 本次下降沿发送的旧索引 |
| frame_load | 输入，1位 | 下降沿且旧索引31时装载 |
| data | 输出，1位 | top.i2s_data，送数字功放DIN |
| underrun_count | 输出，32位 | 饱和欠载统计，留在top内部调试 |

只使用clk作内部时钟；不生成BCLK/LRCLK，不使用PLL。当前实际采样率46875Hz，每帧576拍。上游静音应提交sample=0且sample_valid=1，不能用缺失valid代替静音。

## 缓存和边界

sample_valid将结果写入pending_sample。frame_load只消费沿前已有效的pending，写入frame_sample并清有效标志。若二者同沿，新结果留给下一次装载，无旁路。若一帧内意外提交多次，则保留最新pending；正常合同仍要求每帧只提交一次。

frame_sample在整帧左右声道发送期间固定。首次frame_load缺样允许零且不计欠载；后续缺样保持上一帧并增加underrun_count，最大值保持不回绕。

| 旧bit_index | 当前发送位 | audio_timing沿后LRCLK | 发送器动作 |
|---|---|---|---|
| 15 | 左LSB | 1 | 继续旧帧 |
| 16 | 右MSB | 1 | 继续旧帧 |
| 31 | 旧帧右LSB | 0 | 同时装载下一帧 |
| 0 | 新帧左MSB | 0 | 开始新帧 |

非阻塞赋值保证索引31的data仍从旧frame_sample取bit0；新frame_sample在之后索引0才开始发送。左右均按MSB first发送同一个16位原始补码，不增加空白位。LRCLK领先新声道MSB一个完整BCLK周期。

## 连接示例

以下信号由top声明，reset应接top生成的core_rst_n：

```verilog
audio_timing u_audio_timing (
    .clk(clk), .rst_n(core_rst_n), .bclk(bclk), .lrclk(lrclk),
    .bclk_rise_ce(bclk_rise_ce), .bclk_fall_ce(bclk_fall_ce),
    .bit_index(bit_index), .frame_load(frame_load), .frame_tick(frame_tick)
);
i2s_tx u_i2s_tx (
    .clk(clk), .rst_n(core_rst_n),
    .sample(mixed_sample), .sample_valid(mixed_valid),
    .bclk_fall_ce(bclk_fall_ce), .bit_index(bit_index),
    .frame_load(frame_load), .data(i2s_data), .underrun_count(underrun_count)
);
```

mixer.sample/valid分别接mixed_sample/mixed_valid，无需top额外保存一份pending。mixer必须在下一frame_load之前交付，不能依赖同拍结果供本次装载使用。clk_gen备用PLL不接入当前链路。

现有top和sources.f仍是旧骨架，包含旧clk_gen、bit_fall_ce和旧模块名，尚待整机统一迁移。本次不改top；用以下独立命令验证已实现模块。

## 运行与验证

在FPGA_Music根目录运行，Windows OSS CAD Suite需将其bin和lib目录加入PATH：

```powershell
iverilog -g2001 -Wall -s tb_i2s_tx -o sim/tb_i2s_tx.vvp rtl/audio_timing.v rtl/i2s_tx.v tb/tb_i2s_tx.v
vvp sim/tb_i2s_tx.vvp
gtkwave sim/i2s_tx.vcd
```

测试失败使用Icarus专用$finish_and_return(1)返回非零退出码，仅存在于tb。波形重点查看15/16和31/0边界，pending_sample/pending_valid/frame_sample，以及sample_valid与frame_load同拍时的旧值/新值。

2026-10-21实际运行Icarus，Verilog-2001编译无诊断，仿真退出码0：

```text
PASS: i2s_tx, 120 decoded stereo frames; boundary, underrun, saturation and reset checks
```

测试连接真实audio_timing，逐clk检查发送位、数据保持、双缓存、首次零输出和576拍装载周期。接收模型按BCLK上升沿采样，并按LRCLK变化后的下一位开始新声道，独立重建左右字；覆盖0000、7FFF、8000、FFFF、5555、AAAA、1234、FEDC共8类样本，以及不同样本连续切换、边界同拍有/无旧pending、欠载恢复、计数饱和和帧中途复位。饱和用测试平台将计数器置到FFFFFFFE加速验证，没有修改RTL行为。

尚未运行Gowin综合、布局布线、外部I2S时序分析和板测；未验证MAX98357A对46875Hz的实际兼容性、真实引脚或功放声道配置。本模块仿真不代表整机四复音和≤10ms延迟已达标。
