# 波形工作台固件

这两份固件增加 FPGA 真实音频采集和网页波形回传，保留原有键盘、四声部、四音色、音量、弯音和状态回传。使用方法见 [波形工作台说明](../../docs/WAVEFORM.md)。原 `release_prelim-1104/` 位流保持不变。

| 文件 | 连接方式 | UART TX/RX |
|---|---|---|
| `MusicSynth_Waveform_Wired.fs` | Type-C，通过板载 BL616 串口 | 69 / 70 |
| `MusicSynth_Waveform_BT.fs` | 外接 HC-05 蓝牙模块 | 85 / 77 |

器件 GW2AR-LV18QN88C8/I7，27 MHz，115200/8N1。更新固件后使用本提交的 `web/index.html` 或 `web/bridge.html`。

两版已实际完成 Gowin 综合、布局布线和已有约束下的 STA。逻辑 5558/20736、寄存器 1749/15750、BSRAM 5/46（新增 SDPB=1），DSP 6.5/24；有线 Fmax=28.261 MHz，蓝牙 Fmax=28.736 MHz；Setup/Hold 违例端点与 TNS 均为 0。

`manifest.json` 提供位流 SHA256、构建输入校验值与验证范围；`validation/` 保存实际 P&R 和 STA 原始报告。源码基线为 `ac023667ccd50654074391e51aadd925d46f7366`，新源码的精确版本由仓库提交和输入哈希确定。

尚未执行真实板卡烧录或长时间蓝牙/音频联调，不能把离线仿真和时序结果视为上板验收。PR1014 为原工程仍存在的时钟布线警告，详见完整报告。
