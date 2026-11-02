# 固定正式集成位流

`MusicSynth_TangNano20K.fs`为当前正式集成基线的保留副本，不是新的修复版，不表示已完整通过硬件验收。

- 原生成时间：2026-10-31 20:54:23 +08:00。
- 器件：GW2AR-LV18QN88C8/I7，27MHz、46.875kHz、四声部。
- SHA256：`595AD6DFFB0061E31A50858B3ADC52714D993B9E746D12C69E35AC97341E6636`。
- 原文件位于未版本化的正式 `impl/pnr`；此副本在复制前后均校验一致。
- 只有此FS显式允许版本化；其他实现中间文件、临时位流不上传。
- 当前RTL、CST、SDC与输入清单见manifest.json；源码哈希按CRLF→LF规范化计算。
- 启动瞬态杂声、触摸边缘误触、完整外部时序和PA连通性尚待优化/核验。

PowerShell校验：`Get-FileHash ./bitstreams/MusicSynth_TangNano20K.fs -Algorithm SHA256`。

正式开发与构建入口见 `docs/INTEGRATION_HANDOFF.md`。不自动下载硬件。
