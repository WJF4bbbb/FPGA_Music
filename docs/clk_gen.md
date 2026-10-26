# clk_gen 备用PLL封装

## 状态与范围

依据《clk_gen备份.md》实现备用封装。该大纲的24.576MHz/48kHz路线与当前interfaces.md V1.1的27MHz/46875Hz路线不同，本次不启用PLL、不改audio_timing和top。clk_gen不再承担旧骨架的BCLK/LRCLK生成职责。

rtl/clk_gen.v的复位逻辑可独立测试。硬件集成尚缺经Gowin生成并验证的PLL IP及audio_pll_adapter适配层；缺少适配层时硬件构建应报未解析模块，不提供直通时钟或虚假锁定作为默认实现。

## 参数和复位时序

LOCK_STABLE_CYCLES为两级复位同步器之后的连续确认周期数，合法值>=1；默认16是设计保护值，需按实际启动需求评审，并非PLL厂商保证。外部rst_n与真实LOCK共同允许启动；任一变低立即异步复位，重新满足后在clk_audio域经过2+N个上升沿释放audio_rst_n。计数位宽按N计算，最小1位。

pll_locked直接报告PLL LOCK；同步器不改变此调试输出的含义。下游使用audio_rst_n，不直接使用LOCK释放复位。芯片专用同步器属性及复位路径约束应在Gowin工程中按实际工具支持核实。

## PLL适配层模板

以下是映射示意，不是可直接编译的生成IP。实际模块名、端口和极性必须从生成文件抄录：

```text
module audio_pll_adapter (
    input wire clk_27m, input wire reset,
    output wire clk_audio, output wire locked
);
    <实际生成的IP模块名> u_ip (
        <输入时钟端口> 连接 clk_27m,
        <输出时钟端口> 连接 clk_audio,
        <锁定端口>     连接 locked,
        <复位端口>     按实际极性连接 reset 或 ~reset
    );
endmodule
```

操作顺序：在Gowin为GW2AR-LV18QN88C8/I7建立工程；打开IP Core Generator，选择该器件支持的PLL，输入参考27MHz与目标24.576MHz；检查工具是否接受配置及报告的实际频率、误差、VCO与分频合法性。若无法精确实现，应报告实际结果，不能静默改目标。保存生成的HDL、配置及报告，再按真实端口编写上述适配层并加入工程。核实专用时钟资源、LOCK和复位行为；不手填猜测的PLL参数。

## 未来连接

```verilog
wire clk_audio, pll_locked, audio_rst_n;
clk_gen u_clk_gen (
    .clk_27m(clk), .rst_n(rst_n), .clk_audio(clk_audio),
    .pll_locked(pll_locked), .audio_rst_n(audio_rst_n)
);
// 仅在批准迁移并重验时使用：
// audio_timing.clk接clk_audio，rst_n接audio_rst_n。
```

现有audio_timing固定半周期9拍，只能保持27MHz输入。切换到24.576MHz前需将半周期改为8拍并重验512拍/帧，重算DDS的48000Hz FCW与包络时长，核查全部消抖、定时和模式启动逻辑。所有音频逻辑统一使用新时钟；避免top再重复同步释放复位。

约束建议：保留真实27MHz输入约束，例如top端口为clk时：

```tcl
create_clock -name clk_27m -period 37.037037 [get_ports {clk}]
```

PLL输出须依据实际IP建立或核对自动派生的生成时钟。不得把目标24.576MHz当作输入时钟约束；不能凭目标频率写一条独立时钟来冒充正确PLL派生关系。检查时钟报告、复位恢复/移除路径与Setup/Hold，不用大范围false path掩盖问题。具体生成时钟对象和命令待真实IP层次确定。

## 独立自检

从FPGA_Music目录执行；Windows OSS CAD Suite需要bin和lib目录在PATH中：

```powershell
iverilog -g2001 -Wall -s tb_clk_gen -o sim/tb_clk_gen.vvp rtl/clk_gen.v tb/tb_clk_gen.v
vvp sim/tb_clk_gen.vvp
```

tb末尾的audio_pll_adapter为仅仿真替身，不得加入综合，也不得与真实适配层同时编译。其近似24.576MHz时钟由延时产生，LOCK由激励控制，不能验证硬件PLL频率、锁定时间或物理亚稳态。失败采用Icarus的$finish_and_return(1)退出。

2026-10-21实际运行：Verilog-2001编译无诊断，仿真退出码0，输出PASS: clk_gen reset control (simulation PLL substitute only)。覆盖外部复位、未锁定保持、2+3拍释放、短锁定脉冲、失锁异步拉低及重启，波形为sim/tb_clk_gen.vcd。

尚未完成：实际PLL配置验证、硬件适配层、Gowin综合与布局布线、时钟/复位时序报告检查、上板锁定及频率测量、整机集成和延迟测量。因此当前不能标为硬件正式验收完成。

旧sources.f和top仍含旧clk_gen接口引用，属于整机接口迁移待办；当前请使用上述独立命令，不使用旧整机入口验证本模块。
