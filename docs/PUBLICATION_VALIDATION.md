# 本次集成基线发布前验证

日期：2026-11-02，Asia/Shanghai。将Git暂存内容导出到独立副本后执行检查，副本不含原本debug、impl、工具缓存或个人IDE配置。未操作硬件。

| 检查 | 实际结果 |
|---|---|
| 交付依赖审计 | PASS；GPRJ相对路径解析13个正式RTL、CST、SDC，与sources.f一致 |
| 约束审计 | PASS；9个顶层端口，唯一引脚和预期上下拉；无旧impl依赖 |
| 完整离线构建 | Gowin V1.9.12.04综合、P&R、位流生成成功，整体退出0 |
| 内部STA | 27MHz；Setup/Hold违反端点0/0，Fmax31.654MHz |
| 新旧配置内容比较 | 新构建BIN与原正式BIN的907418字节完全相同 |
| 正式FS | 原文件、保留副本、Git暂存导出文件SHA256完全一致 |

## 软件回归的实际进度

完整18项回归已启动；截至本次上传，16项日志已有PASS，其余仍在运行，整体退出码尚未产生，**不宣称18/18通过**。按用户“继续上传先”的要求，以已经通过的完整离线构建及下列审计先发布。

- tb_adsr: 日志PASS
- tb_audio_timing: 日志PASS
- tb_chain: 日志PASS
- tb_contract_boundaries: 日志PASS
- tb_control_panel: 日志PASS
- tb_i2s_tx: 日志PASS
- tb_mixer: 日志PASS
- tb_note_event: 日志PASS
- tb_osc_timbre: 日志PASS
- tb_sensor_frontend: 日志PASS
- tb_test_mode: 日志PASS
- tb_top_board_inputs: 日志PASS
- tb_top_input_polarity: 日志PASS
- tb_top_pa_enable: 日志PASS
- tb_ttp229_reader: 日志PASS
- tb_voice_alloc: 日志PASS

## 交付与保护

正式音频RTL在此次发布整理中没有改变，保留此前全部集成修改。GPRJ仅改为相对路径，构建工具从参数、环境变量或PATH解析，实现选项显式版本化。CST仅清除版权注释行尾空格，约束词元与引脚无变化。历史文档个人主目录路径已脱敏；原文备份保留本地。

原正式FS没有重新生成或覆盖；版本化副本为bitstreams/MusicSynth_TangNano20K.fs，SHA256：

`595AD6DFFB0061E31A50858B3ADC52714D993B9E746D12C69E35AC97341E6636`

该文件禁止换行转换和文本合并。仅取消Git索引中9个旧生成VVP的跟踪，磁盘文件仍保留。debug诊断工程、日志、波形、临时数据库、impl、个人配置和许可证均未纳入本次提交。原始新验证日志留在发布者本地独立目录，团队可用提交的脚本重新生成。

## 验收边界

保留NL0002层级优化和PR1014通用时钟路由警告。现有SDC没有完整外部IO延迟，内部STA不代替整机电气验收。快速集成TB缩短启动等待/演示周期，不冒充原参数实物启动验证。

**尚未完整硬件验收通过**：正式顶层启动瞬态杂声、触摸边缘误触及PA51/53实际连通性仍待优化/核验。单键、部分复音及A～F/自动双音板测来自此前用户实物反馈，本次没有新增下载或板测。相邻近音程的规律性粗糙感主要符合自动双音对照下的正常声学拍频，不据此修改数字混音器。
