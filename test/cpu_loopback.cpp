// Dedicated cycle-accurate CPU forwarding regression and throughput benchmark.
// Keep the shared SmartNIC harness in l2_switch.cpp; these compile-time knobs
// select raw 2-port loopback traffic and its one-core rate acceptance window.

#define CPU_LOOPBACK_TEST 1
#ifndef CPU_LOOPBACK_PERFORMANCE_TEST
#define CPU_LOOPBACK_PERFORMANCE_TEST 1
#endif
#include "l2_switch.cpp"
