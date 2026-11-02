# ============================================================================
# at_cfg.tcl —— AT 配置工具的 Gowin 命令行构建脚本
#
# 用法（任意目录执行都行）：
#   gw_sh FPGA_Music/gowin/at_cfg/at_cfg.tcl
#
# 产物：gowin/at_cfg/impl/pnr/project.fs
#
# 两个坑：
#   1. gw_sh 不会切到脚本所在目录，相对路径按"进程当前目录"解析，
#      所以这里先 cd 到脚本目录，再用绝对路径拼文件列表。
#   2. set_device 必须带 -name，否则报
#      "there are more than one device named GW2AR-LV18QN88C8/I7"
# ============================================================================
set here [file normalize [file dirname [info script]]]
cd $here
set root [file normalize [file join $here .. ..]]

set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
set_option -top_module top_at_cfg

add_file [file join $root rtl uart_rx.v]
add_file [file join $root rtl bt_at_init.v]
add_file [file join $root rtl top_at_cfg.v]
add_file [file join $root constraints at_cfg.cst]
add_file [file join $root constraints at_cfg.sdc]

run all
