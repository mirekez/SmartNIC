#pragma once

// Standalone conversion entry point for the exact KlusterLab Tribe L2 cache.
// It also lets the banked cpphdl::memory lowering be tested without the CPU
// wrapper's optional CDC headers.
#include "tribe_cpu/cache/l2/L2Cache.h"

template class L2Cache<65536, 256, 32, 4, 32, 31, 4, 4>;
