#pragma once

// Keep legacy one-clock native tests while allowing the same module to be
// emitted as part of the two-clock SmartNIC hierarchy.  CppHDL requires every
// generated child to declare every design-global clock domain.
#ifdef SMARTNIC_TWO_CLOCKS
#define SMARTNIC_NETWORK_CLOCK_METHODS() \
    void _work_net_clk(bool reset) { _work(reset); } \
    void _work_l2_clk(bool) {} \
    void _strobe_l2_clk() {}
#else
#define SMARTNIC_NETWORK_CLOCK_METHODS()
#endif
