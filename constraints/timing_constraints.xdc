create_clock -period 10.000 -name s_axis_aclk [get_ports s_axis_aclk]
create_clock -period 26.000 -name m_axis_aclk [get_ports m_axis_aclk]

set_max_delay -datapath_only -from [get_clocks s_axis_aclk] -to [get_clocks m_axis_aclk] 10.000
set_max_delay -datapath_only -from [get_clocks m_axis_aclk] -to [get_clocks s_axis_aclk] 26.000
