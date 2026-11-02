# Portable implementation settings. Source after creating/opening the project.
# Required GPIO reuse for the existing 54/55/56 I2S pin assignments.
set_option -top_module top
set_option -verilog_std v2001
set_option -global_freq 27
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -timing_driven 1
set_option -place_option 0
set_option -route_option 0
set_option -cst_warn_to_error 1
