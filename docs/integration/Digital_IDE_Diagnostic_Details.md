# Digital IDE parser diagnostic details

Date: 2026-10-26 (Asia/Shanghai).

This is an independent LSP snapshot of 28 explicit project inputs, not the live VS Code Problems panel count.

Errors: **0**; warnings: **14**; hints: **97**. Nothing was filtered or suppressed.

See [classification and rationale](Digital_IDE_Diagnostics_Report.md) for the handling of each diagnostic code.

## tb/tb_osc.v

- `tb/tb_osc.v:54` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_osc.v:55` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits

## rtl/mixer.v

- `rtl/mixer.v:39` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('reg signed[31:0]' and 'logic signed[15:0]')
- `rtl/mixer.v:62` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('logic signed[31:0]' and 'logic signed[16:0]')
- `rtl/mixer.v:65` **HINT / WidthTruncate**: implicit conversion truncates from 49 to 33 bits
- `rtl/mixer.v:89` **HINT / SignConversion**: implicit conversion changes signedness from 'logic[15:0]' to 'reg signed[15:0]'

## rtl/control_panel.v

- `rtl/control_panel.v:48` **HINT / SignCompare**: comparison of differently signed types ('reg[18:0]' and 'logic signed[31:0]')

## rtl/adsr.v

- `rtl/adsr.v:163` **HINT / SignConversion**: implicit conversion changes signedness from 'reg[30:15]' to 'reg signed[15:0]'

## tb/tb_adsr.v

- `tb/tb_adsr.v:48` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_adsr.v:55` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits

## tb/tb_audio_timing.v

- `tb/tb_audio_timing.v:29` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'
- `tb/tb_audio_timing.v:71` **HINT / SignCompare**: comparison of differently signed types ('logic[4:0]' and 'integer')
- `tb/tb_audio_timing.v:71` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'logic[31:0]'
- `tb/tb_audio_timing.v:136` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'

## rtl/voice_alloc.v

- `rtl/voice_alloc.v:94` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'reg[2:0]'
- `rtl/voice_alloc.v:94` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 3 bits
- `rtl/voice_alloc.v:102` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'reg[2:0]'
- `rtl/voice_alloc.v:102` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 3 bits
- `rtl/voice_alloc.v:112` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'reg[2:0]'
- `rtl/voice_alloc.v:112` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 3 bits
- `rtl/voice_alloc.v:123` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'reg[2:0]'
- `rtl/voice_alloc.v:123` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 3 bits

## tb/tb_chain.v

- `tb/tb_chain.v:85` **HINT / SignConversion**: implicit conversion changes signedness from 'logic signed[15:0]' to 'logic[15:0]'
- `tb/tb_chain.v:103` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_chain.v:104` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits

## rtl/sensor_frontend.v

- `rtl/sensor_frontend.v:33` **HINT / SignCompare**: comparison of differently signed types ('reg[12:0]' and 'logic signed[31:0]')

## rtl/note_event.v

- `rtl/note_event.v:87` **HINT / SignCompare**: comparison of differently signed types ('reg[5:0]' and 'logic signed[31:0]')
- `rtl/note_event.v:100` **HINT / SignCompare**: comparison of differently signed types ('reg[5:0]' and 'logic signed[31:0]')

## tb/tb_mixer.v

- `tb/tb_mixer.v:148` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'

## tb/tb_i2s_tx.v

- `tb/tb_i2s_tx.v:32` **HINT / CaseDefault**: 'case' missing 'default' label
- `tb/tb_i2s_tx.v:46` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'
- `tb/tb_i2s_tx.v:71` **HINT / SignConversion**: implicit conversion changes signedness from 'reg signed[15:0]' to 'reg[15:0]'
- `tb/tb_i2s_tx.v:76` **HINT / SignCompare**: comparison of differently signed types ('reg signed[15:0]' and 'reg[15:0]')
- `tb/tb_i2s_tx.v:128` **HINT / SignConversion**: implicit conversion changes signedness from 'logic[15:0]' to 'reg signed[15:0]'
- `tb/tb_i2s_tx.v:129` **HINT / SignConversion**: implicit conversion changes signedness from 'logic[15:0]' to 'reg signed[15:0]'
- `tb/tb_i2s_tx.v:141` **HINT / SignCompare**: comparison of differently signed types ('reg signed[15:0]' and 'logic[15:0]')
- `tb/tb_i2s_tx.v:147` **HINT / SignConversion**: implicit conversion changes signedness from 'logic[15:0]' to 'reg signed[15:0]'
- `tb/tb_i2s_tx.v:152` **HINT / SignCompare**: comparison of differently signed types ('reg signed[15:0]' and 'bit[15:0]')
- `tb/tb_i2s_tx.v:157` **HINT / SignCompare**: comparison of differently signed types ('reg signed[15:0]' and 'bit[15:0]')
- `tb/tb_i2s_tx.v:163` **HINT / SignCompare**: comparison of differently signed types ('reg signed[15:0]' and 'bit[15:0]')
- `tb/tb_i2s_tx.v:172` **HINT / SignCompare**: comparison of differently signed types ('reg signed[15:0]' and 'bit[15:0]')
- `tb/tb_i2s_tx.v:178` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'

## tb/tb_sensor_frontend.v

- `tb/tb_sensor_frontend.v:47` **HINT / IntBoolConv**: implicit conversion from 'integer' to boolean value

## rtl/osc.v

- `rtl/osc.v:90` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('logic[31:0]' and 'logic[16:0]')
- `rtl/osc.v:107` **HINT / SignConversion**: implicit conversion changes signedness from 'logic[15:0]' to 'logic signed[15:0]'
- `rtl/osc.v:110` **HINT / SignConversion**: implicit conversion changes signedness from 'logic[15:0]' to 'logic signed[15:0]'

## tb/tb_contract_boundaries.v

- `tb/tb_contract_boundaries.v:64` **HINT / IntBoolConv**: implicit conversion from 'integer' to boolean value
- `tb/tb_contract_boundaries.v:64` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'

## tb/tb_control_panel.v

- `tb/tb_control_panel.v:162` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'logic[15:0]'
- `tb/tb_control_panel.v:162` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 16 bits
- `tb/tb_control_panel.v:163` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'logic[15:0]'
- `tb/tb_control_panel.v:163` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 16 bits
- `tb/tb_control_panel.v:170` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'logic[15:0]'
- `tb/tb_control_panel.v:170` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 16 bits
- `tb/tb_control_panel.v:171` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'logic[15:0]'
- `tb/tb_control_panel.v:171` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 16 bits
- `tb/tb_control_panel.v:172` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'logic[15:0]'
- `tb/tb_control_panel.v:172` **HINT / WidthTruncate**: implicit conversion truncates from 32 to 16 bits
- `tb/tb_control_panel.v:190` **HINT / IntBoolConv**: implicit conversion from 'integer' to boolean value
- `tb/tb_control_panel.v:195` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'

## rtl/top.v

- `rtl/top.v:129` **HINT / SignConversion**: implicit conversion changes signedness from 'logic signed[15:0]' to 'logic[15:0]'

## tb/tb_osc_timbre.v

- `tb/tb_osc_timbre.v:54` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_osc_timbre.v:54` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_osc_timbre.v:58` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_osc_timbre.v:59` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_osc_timbre.v:99` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('real' and 'integer')
- `tb/tb_osc_timbre.v:99` **HINT / IntFloatConv**: implicit conversion from 'integer' to 'real'
- `tb/tb_osc_timbre.v:99` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('real' and 'integer')
- `tb/tb_osc_timbre.v:99` **HINT / IntFloatConv**: implicit conversion from 'integer' to 'real'

## tb/tb_note_event.v

- `tb/tb_note_event.v:98` **HINT / IntBoolConv**: implicit conversion from 'integer' to boolean value

## tb/tb_test_mode.v

- `tb/tb_test_mode.v:36` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'
- `tb/tb_test_mode.v:65` **HINT / SignCompare**: comparison of differently signed types ('logic[2:0]' and 'integer')
- `tb/tb_test_mode.v:65` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'logic[31:0]'
- `tb/tb_test_mode.v:142` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'

## tb/tb_top_integration.v

- `tb/tb_top_integration.v:64` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'
- `tb/tb_top_integration.v:68` **HINT / CaseDefault**: 'case' missing 'default' label
- `tb/tb_top_integration.v:74` **HINT / CaseDefault**: 'case' missing 'default' label
- `tb/tb_top_integration.v:157` **HINT / SignCompare**: comparison of differently signed types ('logic[2:0]' and 'integer')
- `tb/tb_top_integration.v:157` **HINT / SignConversion**: implicit conversion changes signedness from 'integer' to 'logic[31:0]'
- `tb/tb_top_integration.v:157` **HINT / SignCompare**: comparison of differently signed types ('logic[6:0]' and 'integer')
- `tb/tb_top_integration.v:172` **HINT / SignCompare**: comparison of differently signed types ('integer' and 'logic[2:0]')
- `tb/tb_top_integration.v:186` **HINT / SignConversion**: implicit conversion changes signedness from 'logic[31:0]' to 'integer'
- `tb/tb_top_integration.v:186` **HINT / WidthExpand**: implicit conversion expands from 3 to 32 bits
- `tb/tb_top_integration.v:189` **HINT / SignCompare**: comparison of differently signed types ('integer' and 'logic[2:0]')
- `tb/tb_top_integration.v:218` **HINT / SignConversion**: implicit conversion changes signedness from 'reg signed[15:0]' to 'reg[15:0]'
- `tb/tb_top_integration.v:222` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('integer' and 'reg signed[15:0]')
- `tb/tb_top_integration.v:223` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('integer' and 'logic signed[16:0]')
- `tb/tb_top_integration.v:224` **HINT / WidthTruncate**: implicit conversion truncates from 64 to 32 bits
- `tb/tb_top_integration.v:244` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('integer' and 'reg signed[15:0]')
- `tb/tb_top_integration.v:244` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('integer' and 'logic signed[16:0]')
- `tb/tb_top_integration.v:245` **HINT / WidthTruncate**: implicit conversion truncates from 64 to 32 bits
- `tb/tb_top_integration.v:287` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('real' and 'reg[31:24]')
- `tb/tb_top_integration.v:287` **HINT / IntFloatConv**: implicit conversion from 'reg[31:24]' to 'real'
- `tb/tb_top_integration.v:298` **HINT / CaseDefault**: 'case' missing 'default' label
- `tb/tb_top_integration.v:314` **HINT / SignConversion**: implicit conversion changes signedness from 'reg[31:0]' to 'integer'
- `tb/tb_top_integration.v:316` **WARNING / UnknownSystemName**: unknown system name '$abs'
- `tb/tb_top_integration.v:319` **WARNING / UnknownSystemName**: unknown system name '$abs'
- `tb/tb_top_integration.v:322` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_top_integration.v:323` **HINT / WidthExpand**: implicit conversion expands from 16 to 32 bits
- `tb/tb_top_integration.v:329` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('reg signed[15:0]' and 'integer')
- `tb/tb_top_integration.v:330` **HINT / SignCompare**: comparison of differently signed types ('logic[15:0]' and 'reg signed[15:0]')
- `tb/tb_top_integration.v:405` **HINT / CaseDefault**: 'case' missing 'default' label
- `tb/tb_top_integration.v:406` **HINT / SignCompare**: comparison of differently signed types ('logic[1:0]' and 'integer')
- `tb/tb_top_integration.v:408` **HINT / SignCompare**: comparison of differently signed types ('logic[15:0]' and 'integer')
- `tb/tb_top_integration.v:447` **HINT / IntFloatConv**: implicit conversion from 'integer' to 'real'
- `tb/tb_top_integration.v:447` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('integer' and 'real')
- `tb/tb_top_integration.v:475` **HINT / IntFloatConv**: implicit conversion from 'integer' to 'real'
- `tb/tb_top_integration.v:475` **HINT / ArithOpMismatch**: arithmetic between operands of different types ('integer' and 'real')
- `tb/tb_top_integration.v:497` **HINT / IntBoolConv**: implicit conversion from 'integer' to boolean value
- `tb/tb_top_integration.v:497` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'
- `tb/tb_top_integration.v:500` **WARNING / UnknownSystemName**: unknown system name '$finish_and_return'
