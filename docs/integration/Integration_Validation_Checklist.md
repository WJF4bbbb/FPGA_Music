# 可执行联调检查清单

日期：2026-10-26。状态用 PASS / FAIL / BLOCKED / NOT TESTED，不把编译、综合、STA 和板测混为一项。
当前控制默认值 267000 的复测见 [控制延迟修复报告](Control_Latency_Fix_Report.md)；下方历史检查均明确标注。

## 环境及回归入口

- [x] PASS：只在 integration 工作目录执行；工具是 OSS CAD Suite 同目录的 iverilog/vvp，PATH 包含同套件 lib。
- [x] 历史 PASS：修改默认值前，`run_integration.ps1 -UnitTests` 实际执行 12 项单元/边界；当时整机功能通过、性能失败。本次按 C 三项、B 五项、正式整机顺序复测，均退出 0。
- [x] PASS：脚本明确 `-s tb_top_integration`；不引入旧 tb_top.v，编译失败立即非零。
- [x] PASS：断言失败非零，旧单元 $finish 返回 0 时也检查 FAIL 文本，不能伪报成功。
- [x] PASS：设置 OSS CAD Suite 的 IVL 和 bin/lib PATH 后，`run_sim_c.bat` 三项全部通过，退出 0。
- [x] PASS：`D:\Git\bin\bash.exe ./run_b_tb.sh g2012` 五项全部通过，退出 0；隔离错误副本明确 FAIL 时脚本退出 1。

## 接口与功能

- [x] PASS：共享复位、启动模式锁定、两源整组选择和未选源背压。
- [x] PASS：真实 key_raw → 同步/滤波 → 排队事件 → 独立声部分配比较。
- [x] PASS：单/双/四键、第五键、释放尾音优先抢占、被抢键松开、重复按键和短脉冲拒绝。
- [x] PASS：四路独立 DDS、正负波形、包络轨迹、各路混音贡献和真实 PCM 算术。
- [x] PASS：默认控制参数下音色切换、双向弯音、双键归零、音量增减和复位默认值。
- [x] PASS：完整帧 valid 合同、signed 求和及增益、计数饱和边界。
- [x] PASS：四个隔离错误注入均被真实整机测试捕获，包括帧中额外相位更新。
- [ ] NOT TESTED：八声部完整整机功能；目前只有 4/8 配置编译检查通过。
- [ ] NOT TESTED：无限/长期背压和 FIFO 满期间所有快速反转边沿的无损保留。

## I2S 与性能

- [x] PASS：从外部三根引脚独立解码，WS 后一位延迟、MSB first、每声道 16 位、左右相同。
- [x] PASS：BCLK 高低各 9 clk、WS 半周期 288 clk、每帧 576 clk，接收沿前数据稳定。
- [x] PASS：8847 个双声道帧匹配真实 PCM 队列，复位重新同步，正常运行统计为零；3174265 条整机断言通过。
- [x] PASS：正式滤波下选音到 I2S 实测 0.236 ms；两拍 frame→PCM 流水线。
- [x] PASS：正式面板到 I2S 为 268443 拍（9.942333 ms），低于不变的 270000 拍（10 ms）上限，余量 1557 拍；INTEGRATION_EXIT=0。实际 DUT 默认值断言为 267000，无 TB 消抖覆盖。
- [ ] NOT TESTED：全部输入相位穷举、硬件抖动/光电时延和 DAC 实际输出端延迟。

## Gowin 与上板前

- [x] 历史 PASS：修改默认值前，正式 top、12 个源、Tang Nano 20K 正确目标器件的真实综合，`run_gowin_synthesis.ps1` 退出 0。
- [x] 历史 PASS：报告确认 27 MHz；综合资源报告真实存在，未用 top_i2s_test 替代。本次未重跑新默认值的综合。
- [ ] BLOCKED：填入经过实际接线核对的 CST；当前模板不含引脚。
- [ ] BLOCKED：补 I/O 延迟、CDC/异步输入和同步器约束，再运行 P&R 与 Setup/Hold。
- [ ] NOT TESTED：生成并下载正式整机 bitstream、检查 MAX98357A 使能/接线、四复音听感和频谱。

## 文档与 Git

- [x] PASS：完整报告、逐步调试日志和六幅 SVG 已提供，图示与源码/实际日志对应。
- [x] PASS：Python 第 252 行已无行尾空白；该修复在已有合并基线中。
- [x] PASS：检查 `git diff --check` 与 `git diff --cached --check`，无空白错误。
- [x] PASS：生成的 VVP/VCD/综合网表保存在忽略目录，没有加入 Git。
- [x] PASS：未自动 commit、push、merge --abort；原空文件及早期测试平台均保留。
