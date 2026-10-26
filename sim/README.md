仿真输出目录。运行时生成 .vvp/.vcd；输出文件不纳入源码提交。

在仓库根目录的 PowerShell 中重新编译并运行 I2S 联合仿真：

```powershell
iverilog -g2012 -Wall -s tb_top_i2s_test -c tb/top_i2s_test_sources.f -o sim/tb_top_i2s_test.vvp
if ($LASTEXITCODE -ne 0) { throw 'I2S simulation compilation failed' }
vvp sim/tb_top_i2s_test.vvp
if ($LASTEXITCODE -ne 0) { throw 'I2S simulation failed' }
```

修改 `.v` 后必须重新运行 `iverilog`；直接运行 `vvp` 会执行旧的 `.vvp`。
预期打印 `PASS: top_i2s_test, 200 stereo frames`，进程退出码为 0。
测试从 LRCLK 边沿同步，在观察到声道切换后的下一个 BCLK 上升沿接收 MSB，
检查启动静音、后续 `E000/2000` 交替、左右一致、无欠载，以及帧中复位后的重新同步。
断言失败或超时会返回非零退出码。

Windows 使用 OSS CAD Suite 时，先加载安装目录的 `environment.ps1`（按实际路径调整）：

```powershell
. 'E:\app\software\oss-cad-suite\environment.ps1'
```

该环境同时将 `bin` 和 `lib` 加入当前会话的 PATH。仅加入 `bin` 可能导致
`vvp` 使用错误的 DLL，出现访问冲突或仿真结束后进程未正常退出。
