# Preliminary internal evaluation target only: 100 MHz.
# No board pins or external interface timing at this stage.
create_clock -name core_clk -period 10.000 [get_ports clk]
