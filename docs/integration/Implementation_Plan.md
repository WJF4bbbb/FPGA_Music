# A+B+C 整机验证实施计划

> 本计划为默认 CTRL_FILT=270000 时的已执行历史计划。后续控制延迟修复采用正式默认 267000，见 [当前修复报告](Control_Latency_Fix_Report.md)。

> 执行方式：当前 integration 工作目录内逐项执行；使用只读代码复核。用户明确禁止自动提交、推送，保留原测试文件和原始分支。

**目标：** 用正式 top 和真实 RTL 验证四复音、输入、配置、PCM、I2S 及默认参数延迟，保存可重复执行的证据。

**架构：** 单个外部激励测试平台；只读层次监视检查内部控制与计算。独立串口接收模型仅从 BCLK/WS/DATA 解码，使用生产端 PCM 队列按双缓存合同比对。正式消抖参数保持不变，仅演示保持时间在功能测试中缩短，并明确记录。

**工具：** OSS CAD Suite Icarus Verilog / vvp，Windows PowerShell；可用时使用 Gowin CLI。

- [x] 读取附件、正式 RTL、旧测试、接口和工程约束；定位用户空文件实际位于 tb/tb/。
- [x] 创建 tb/tb_top_integration.v：下降沿驱动、NBA 后检查、超时、事件排序/分配模型、逐路 DDS/ADSR 检查、混音参考计算、外部 I2S 解码与延迟计数。
- [x] 创建 run_integration.ps1：同安装编译/运行器及 DLL 环境、自动收集 RTL 并排除备用顶层、日志/VCD、失败非零、场景汇总；运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\run_integration.ps1`。
- [x] 原样运行后定位失败；仅对有复现证据的问题写边界测试并修复；再次运行完整真实整机及 A/B/C 回归。
- [x] 默认面板消抖 270000 拍另做严格 10 ms 断言，若超限保留 FAIL 和测量，不擅自修改硬件消抖策略。
- [x] 修正 sources.f 的 sin_rom 依赖；检查 Gowin 的顶层、源清单、SDC/CST。能运行则实际综合，缺失条件列为 BLOCKED。
- [x] 独立复核新测试是否可能假通过；用隔离副本注入真实接线/计算/位序错误验证断言能捕获。
- [x] 输出接口审计表、报告、调试日志、检查清单和六幅源码依据图示到 docs/integration/。
- [x] 最后运行 `git status --short`、`git diff --check`、`git diff --cached --check`，核对生成文件未暂存；不自动提交。
