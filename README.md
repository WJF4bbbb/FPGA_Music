# FPGA_Music 当前集成基线

2026-11-04 新增 **FPGA 真实音频波形工作台**：有线/蓝牙均支持 512 点、16 位采集快照，网页提供冻结、倍率和过期提示。使用与验证见 [波形说明](docs/WAVEFORM.md)，对应新固件见 [waveform-2026-11-04](bitstreams/waveform-2026-11-04/README.md)。旧发布位流保持原样；波形功能需要烧录新固件。

当前入口：[正式集成交接说明](docs/INTEGRATION_HANDOFF.md)。Tang Nano 20K V3923，27MHz，TTP229 16键，四声部DDS/ADSR/Mixer，外置MAX98357A，46.875kHz 16-bit双声道I2S。

**尚未完整硬件验收通过：启动瞬态杂声和触摸边缘误触仍待优化。** 下列旧阶段文档保留历史，不代表当前交接状态。固定正式位流及SHA256见 [bitstreams](bitstreams/README.md)。当前仿真和离线构建入口分别为 run_integration.ps1、run_gowin_implementation.ps1；工具从PATH或显式环境/参数获取。

---

# 当前 integration：TTP229-BSF 16键串行触摸

当前正式RTL已集成真实A/B/C模块及TTP229读取器，使用27MHz、46875Hz、四复音与PA静音预热；触摸映射、实际九个顶层端口、验证与首次板测限制见[集成报告](docs/integration/TTP229_Integration_Report.md)。完整回归入口为 `powershell -NoProfile -ExecutionPolicy Bypass -File ./run_integration.ps1 -UnitTests`。以下保留原阶段记录，旧状态描述不代表当前实现。

---

# FPGA_Music

Tang Nano 20K FPGA音乐合成项目，接口合同见[docs/interfaces.md](docs/interfaces.md)。

当前完成A成员模块及阶段性接线验证；B/C正式模块仍待实现。Windows运行 `run_sim.bat tb_top`，Linux运行 `bash run_sim.sh tb_top`，验证真实A模块并使用测试平台内B/C接口替身。该测试不能替代整机功能验收。

其他A组测试入口：tb_audio_timing、tb_i2s_tx、tb_test_mode、tb_clk_gen。详细状态和命令见[docs/top.md](docs/top.md)。当前采用27MHz直分频，46875Hz实际采样率；clk_gen只作备用PLL封装。

sources.f列出正式11模块；B/C完成接口迁移与实现后才能进行真实全机编译。Gowin工程和引脚/时序约束仍需按真实硬件补齐。

B/C并行开发前请先阅读[开发交接说明](docs/handoff.md)。
