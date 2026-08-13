#pragma once

// The generated SmartNIC uses named clock-domain work methods, while the
// standalone C++ model uses the legacy _work entry point.  Keep this target
// flow difference limited to the function name; the implementation remains in
// InputBalancer.h and is always converted by CppHDL.
#ifdef SMARTNIC_TWO_CLOCKS
#define INPUT_BALANCER_WORK_METHOD _work_net_clk
#else
#define INPUT_BALANCER_WORK_METHOD _work
#endif
