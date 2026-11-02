# AT 配置顶层：单一 27 MHz 时钟，无内部生成时钟
create_clock -name sys_clk -period 37.037037 [get_ports {clk}]
# at_rx 是板外异步信号，uart_rx 内部已有两级同步，端口到首级同步器不必做时序
set_false_path -from [get_ports {at_rx}]
