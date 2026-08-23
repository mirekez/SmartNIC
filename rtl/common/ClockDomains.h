#pragma once

// Keep legacy one-clock native tests while allowing the same module to be
// emitted as part of the two-clock SmartNIC hierarchy.  CppHDL requires every
// generated child to declare every design-global clock domain.
#ifdef SMARTNIC_SYSTEM_DOMAIN
#define SMARTNIC_NETWORK_WORK_METHOD _work_system_clock
#define SMARTNIC_SYSTEM_WORK_METHOD _work_system_clock
#define SMARTNIC_NETWORK_STROBE_METHOD _strobe_system_clock
#define SMARTNIC_SYSTEM_STROBE_METHOD _strobe_system_clock
#define SMARTNIC_SYSTEM_CLOCK_METHODS() \
    void _work_l2_clock(bool) {} \
    void _strobe_l2_clock() {}
#define SMARTNIC_NETWORK_CLOCK_METHODS() SMARTNIC_SYSTEM_CLOCK_METHODS()
#elif defined(SMARTNIC_TWO_CLOCKS)
#define SMARTNIC_NETWORK_WORK_METHOD _work_net_clk
#define SMARTNIC_SYSTEM_WORK_METHOD _work
#define SMARTNIC_NETWORK_STROBE_METHOD _strobe
#define SMARTNIC_SYSTEM_STROBE_METHOD _strobe
#define SMARTNIC_SYSTEM_CLOCK_METHODS()
#define SMARTNIC_NETWORK_CLOCK_METHODS() \
    void _work(bool reset) { _work_net_clk(reset); } \
    void _work_l2_clk(bool) {} \
    void _strobe_l2_clk() {}
#else
#define SMARTNIC_NETWORK_WORK_METHOD _work
#define SMARTNIC_SYSTEM_WORK_METHOD _work
#define SMARTNIC_NETWORK_STROBE_METHOD _strobe
#define SMARTNIC_SYSTEM_STROBE_METHOD _strobe
#define SMARTNIC_SYSTEM_CLOCK_METHODS()
#define SMARTNIC_NETWORK_CLOCK_METHODS()
#endif
