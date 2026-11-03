# 有线版构建脚本：UART 走板载 BL616（pin 69/70），走 Type-C 直连
set here [file normalize [file dirname [info script]]]
cd $here
open_project [file join $here MusicSynth_Wired.gprj]
set_option -top_module top
set_option -verilog_std v2001
set_option -global_freq 27
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -timing_driven 1
set_option -place_option 0
set_option -route_option 0
set_option -cst_warn_to_error 1
run all
