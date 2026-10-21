# 分工

A：top.v、clk_gen.v、i2s_tx.v、test_mode.v；tb入口、真实工程与约束、总装。
B：voice_alloc.v、osc.v、adsr.v、mixer.v；相应单元验证后续自行补充。
C：key_scan.v、timbre_sel.v、note_event.v；传感器/多键事件验证和文档。
接口修改先同步top与测试文件；完成一个模块后再替换其桩。
