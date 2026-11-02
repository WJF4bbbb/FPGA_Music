# Nominal 27MHz input; verify against the actual board clock.
create_clock -name sys_clk -period 37.037037 [get_ports {clk}]
# BSF SDO has an asynchronous electrical arrival. Only the external path to
# the FIRST synchronizer is exempt. sdo_meta -> sdo_sync remains clk-timed.
set_false_path -from [get_ports {ttp_sdo}] -to [get_regs {*sdo_meta_s1}]
# Reset assertion and startup-mode capture are asynchronous board boundaries.
# External clock-to-SDO, pad/cable delay, I2S setup/hold and PA51/53 continuity
# still require board measurements. This is not complete external I/O signoff.
