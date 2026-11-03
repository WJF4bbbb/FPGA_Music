# 临时构建脚本：验证 release/prelim-1104 能否综合通过
set here [file normalize [file dirname [info script]]]
cd $here
open_project [file join $here MusicSynth_TangNano20K.gprj]
source [file join $here project_settings.tcl]
run all
