# FPGA_Music

Tang Nano 20K FPGA音乐合成项目，接口合同见[docs/interfaces.md](docs/interfaces.md)。

当前完成A成员模块及阶段性接线验证；B/C正式模块仍待实现。Windows运行 `run_sim.bat tb_top`，Linux运行 `bash run_sim.sh tb_top`，验证真实A模块并使用测试平台内B/C接口替身。该测试不能替代整机功能验收。

其他A组测试入口：tb_audio_timing、tb_i2s_tx、tb_test_mode、tb_clk_gen。详细状态和命令见[docs/top.md](docs/top.md)。当前采用27MHz直分频，46875Hz实际采样率；clk_gen只作备用PLL封装。

sources.f列出正式11模块；B/C完成接口迁移与实现后才能进行真实全机编译。Gowin工程和引脚/时序约束仍需按真实硬件补齐。

B/C并行开发前请先阅读[开发交接说明](docs/handoff.md)。
