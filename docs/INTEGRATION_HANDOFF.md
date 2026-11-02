# FPGA_Music 正式集成基线交接

日期：2026-11-02，Asia/Shanghai。分支：`integration`。本文件是当前交接入口；其他带日期的阶段报告保留历史语境，不能将其旧状态当作本版本状态。

## 平台与实现

- 开发板：Tang Nano 20K V3923；FPGA：GW2AR-LV18QN88C8/I7。
- 系统时钟：27 MHz，所有正式模块在同一时钟域工作。
- I2S：46.875 kHz、16-bit 双声道 Philips 格式，BCLK=1.5 MHz；左右复制相同混音PCM。
- 音频输出：外置 MAX98357A；输入：TTP229-BSF 16键专用两线串行接口。
- 已完成 DDS、ADSR、Mixer、四声部分配及 A/B/C 全链路集成和相关软件验证。正式源清单为 `sources.f` 中13个RTL，无额外ROM文件或外部生成IP依赖。
- 单键、长按、释放及部分复音实物测试已完成；A～F及自动双音独立诊断已完成实物对照。诊断源码、日志与位流不属于此次发布包。

## 当前状态与优化任务

**尚未完整硬件验收通过。** 正式顶层仍有启动瞬态杂声、触摸边缘误触待优化；不能把独立诊断或软件通过写成正式整机完全通过。

后续重点：

1. 提高触摸边缘误触的抗扰能力，保持合法相邻多键与原扫描/响应目标。
2. 实现并评估三音色：钢琴、弦乐、鼓乐；这是待优化内容，不是当前已交付的三种真实乐器音色。
3. 让音量档位更明显。
4. 让弯音效果更明显。

相邻近音程的规律性粗糙感已通过自动四组双音对照验证，主要符合正常声学拍频/不协和，不应直接认定为数字混音故障。不得通过删声部、改音高等方式掩盖合法复音。

启动边界：GPIO73/rst_n配置内部上拉，GPIO74/test_enable配置内部下拉；73异步低有效。复位释放第三沿锁存第一沿采到的74，第四沿释放核心；74高启动会选演示和弦，运行中改变74不会退出，必须统一复位。用户当前未为73/74接外部线，内部弱偏置不能代替实际启动瞬态测量。配置期GPIO默认偏置与配置后约束接管之间的实物行为仍需核验，历史杂声根因未最终确认。

## 九个物理端口

| 端口 | FPGA封装脚 | V3923 Rev1.3参考 |
|---|---:|---|
| clk | 4 | 板载27MHz |
| rst_n | 73 | J6-1 |
| test_enable | 74 | J6-2 |
| ttp_scl | 27 | J6-8 |
| ttp_sdo | 28 | J6-9 |
| bclk | 56 | J5-7 |
| lrclk | 55 | J5-11 |
| i2s_data | 54 | J5-8 |
| pa_en | 51 | J5-9；板载PA实际连通性仍待核验 |

J6-1靠USB-C/S1一端；大FPGA面朝自己、USB-C朝上时，在左侧长排针首孔，向远离USB-C方向依次73、74、75。依据V3923装配图数字丝印，不依据旧文档J0称呼。主图PA标51、旧音频子页标53，存在文档矛盾；本版本未擅改51映射，外置MAX98357A SD不接这一未核实线路。所有实际使用Bank约束3.3V。

TP0～7对应MIDI60/62/64/65/67/69/71/72；TP8音色、TP9/10音量±、TP11/12弯音±；TP13～15预留。读取器完整位图有效不代表设备存在或电气数据可信，协议无ACK/CRC。

## 获取与构建

```bash
git clone --branch integration https://github.com/WJF4bbbb/FPGA_Music.git
cd FPGA_Music
git switch -c feature/your-improvement
```

需要自行安装并合法授权Gowin EDA；原验证使用V1.9.12.04。仿真使用Icarus Verilog/OSS CAD Suite；辅助Python脚本仅依赖标准库。许可证、安装目录、个人IDE配置不随仓库分发。

在仓库根目录的PowerShell中，工具已在PATH时可直接运行：

```powershell
./run_integration.ps1
./run_integration.ps1 -UnitTests
./run_gowin_synthesis.ps1
./run_gowin_implementation.ps1
```

也可设置环境变量 `OSS_CAD_SUITE` 为套件根目录、`GOWIN_BIN` 为Gowin `IDE/bin`目录，或使用脚本参数 `-Suite`、`-GowinBin`。不要将自己的安装绝对路径提交到项目中。

正式GUI入口：`gowin/MusicSynth_TangNano20K/MusicSynth_TangNano20K.gprj`。所有源路径相对于GPRJ，直接使用根目录RTL；`src/`仅CST参与正式构建，不使用历史RTL副本。

实现设置由 `gowin/MusicSynth_TangNano20K/project_settings.tcl` 版本化。完整实现脚本会自动载入；GUI打开GPRJ后，须在工程配置中设置同样的top/27MHz/SSPI和MSPI作为GPIO等选项，或在已打开工程的Tcl控制台 `source` 此设置文件（使用其实际路径）。仅打开GPRJ不代表这些实现选项已经生效。不要依赖未上传的旧 `impl` 配置。

`run_gowin_implementation.ps1` 将新构建输出到独立 `sim/ttp229-implementation-*`，拒绝覆盖已有输出，不操作Programmer。根目录旧A组/备用clk_gen入口属于历史，不是正式集成验收入口。`tb_osc_gowin_compare.v`为可选映射网表比较，需要先生成 `osc_gowin` 并配合本地Gowin官方原语；不属于默认软件回归的外部文件依赖。

## 验证与边界

此前原参数27MHz正式顶层验收：110,924双声道帧、110,927次独立数学PCM比较通过；启动、静音、单/四键、释放、复位、演示优先级检查通过。原样Gowin实现内部Setup/Hold违反端点0/0，Fmax31.654MHz。以上是历史已执行证据，不是本次发布自动重测的声称。

原SDC没有完整外部输入/输出延迟，保留PR1014通用时钟布线警告；内部STA通过不能代替外部I2S电气时序、冷启动和PA连通性验收。快速集成TB缩短上电等待与演示时长，保留真实扫描/滤波参数，不冒充完整原参数上电板测。此次发布的新检查记录见 `PUBLICATION_VALIDATION.md`。

## 固定正式位流

版本化文件：`bitstreams/MusicSynth_TangNano20K.fs`，从原正式实现复制，未重新生成或覆盖原文件。SHA256：

```text
595AD6DFFB0061E31A50858B3ADC52714D993B9E746D12C69E35AC97341E6636
```

输入清单、规范化源码哈希及未完成硬件验收状态见 `bitstreams/manifest.json`。`.gitattributes`禁止对这一个FS做换行转换，克隆后应再次校验SHA256。本次仅发布文件，不执行任何SRAM/Flash烧录。
