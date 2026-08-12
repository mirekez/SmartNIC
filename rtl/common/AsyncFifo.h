#pragma once

// The only external packet clock crossing retained by the Kintex-7 design is
// between 156.25 MHz processing/L2 and the 125 MHz PCIe System domain.

#include <cpphdl.h>

using namespace cpphdl;

#define ASYNC_FIFO_CLASS AsyncFifoL2ToSystem
#define ASYNC_FIFO_WRITE_ON_NET 1
#define ASYNC_FIFO_FIRST_WORK _work_l2_clock
#define ASYNC_FIFO_FIRST_STROBE _strobe_l2_clock
#define ASYNC_FIFO_SECOND_WORK _work_system_clock
#define ASYNC_FIFO_SECOND_STROBE _strobe_system_clock
#include "AsyncFifoImpl.inc"
#undef ASYNC_FIFO_SECOND_STROBE
#undef ASYNC_FIFO_SECOND_WORK
#undef ASYNC_FIFO_FIRST_STROBE
#undef ASYNC_FIFO_FIRST_WORK
#undef ASYNC_FIFO_WRITE_ON_NET
#undef ASYNC_FIFO_CLASS

#define ASYNC_FIFO_CLASS AsyncFifoSystemToL2
#define ASYNC_FIFO_WRITE_ON_NET 0
#define ASYNC_FIFO_FIRST_WORK _work_l2_clock
#define ASYNC_FIFO_FIRST_STROBE _strobe_l2_clock
#define ASYNC_FIFO_SECOND_WORK _work_system_clock
#define ASYNC_FIFO_SECOND_STROBE _strobe_system_clock
#include "AsyncFifoImpl.inc"
#undef ASYNC_FIFO_SECOND_STROBE
#undef ASYNC_FIFO_SECOND_WORK
#undef ASYNC_FIFO_FIRST_STROBE
#undef ASYNC_FIFO_FIRST_WORK
#undef ASYNC_FIFO_WRITE_ON_NET
#undef ASYNC_FIFO_CLASS
