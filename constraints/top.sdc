# Nominal 27MHz input; verify against the actual board clock.
create_clock -name sys_clk -period 37.037037 [get_ports {clk}]
# TODO: input/output delays, external I2S timing, synchronizer exceptions.
# This file alone is NOT a complete timing constraint set.
