#pragma once

#include <cpphdl.h>

using namespace cpphdl;

#define ASYNC_FIFO_CLASS AsyncFifoNetToL2
#define ASYNC_FIFO_WRITE_ON_NET 1
#define ASYNC_FIFO_FIRST_WORK _work_net_clk
#define ASYNC_FIFO_FIRST_STROBE _strobe_net_clk
#define ASYNC_FIFO_SECOND_WORK _work_l2_clk
#define ASYNC_FIFO_SECOND_STROBE _strobe_l2_clk
#include "AsyncFifoImpl.inc"
#undef ASYNC_FIFO_SECOND_STROBE
#undef ASYNC_FIFO_SECOND_WORK
#undef ASYNC_FIFO_FIRST_STROBE
#undef ASYNC_FIFO_FIRST_WORK
#undef ASYNC_FIFO_WRITE_ON_NET
#undef ASYNC_FIFO_CLASS

#define ASYNC_FIFO_CLASS AsyncFifoL2ToNet
#define ASYNC_FIFO_WRITE_ON_NET 0
#define ASYNC_FIFO_FIRST_WORK _work_net_clk
#define ASYNC_FIFO_FIRST_STROBE _strobe_net_clk
#define ASYNC_FIFO_SECOND_WORK _work_l2_clk
#define ASYNC_FIFO_SECOND_STROBE _strobe_l2_clk
#include "AsyncFifoImpl.inc"
#undef ASYNC_FIFO_SECOND_STROBE
#undef ASYNC_FIFO_SECOND_WORK
#undef ASYNC_FIFO_FIRST_STROBE
#undef ASYNC_FIFO_FIRST_WORK
#undef ASYNC_FIFO_WRITE_ON_NET
#undef ASYNC_FIFO_CLASS

#define ASYNC_FIFO_CLASS AsyncFifoCpuToL2
#define ASYNC_FIFO_WRITE_ON_NET 1
#define ASYNC_FIFO_FIRST_WORK _work_clk
#define ASYNC_FIFO_FIRST_STROBE _strobe_clk
#define ASYNC_FIFO_SECOND_WORK _work_l2_clock
#define ASYNC_FIFO_SECOND_STROBE _strobe_l2_clock
#include "AsyncFifoImpl.inc"
#undef ASYNC_FIFO_SECOND_STROBE
#undef ASYNC_FIFO_SECOND_WORK
#undef ASYNC_FIFO_FIRST_STROBE
#undef ASYNC_FIFO_FIRST_WORK
#undef ASYNC_FIFO_WRITE_ON_NET
#undef ASYNC_FIFO_CLASS

#define ASYNC_FIFO_CLASS AsyncFifoL2ToCpu
#define ASYNC_FIFO_WRITE_ON_NET 0
#define ASYNC_FIFO_FIRST_WORK _work_clk
#define ASYNC_FIFO_FIRST_STROBE _strobe_clk
#define ASYNC_FIFO_SECOND_WORK _work_l2_clock
#define ASYNC_FIFO_SECOND_STROBE _strobe_l2_clock
#include "AsyncFifoImpl.inc"
#undef ASYNC_FIFO_SECOND_STROBE
#undef ASYNC_FIFO_SECOND_WORK
#undef ASYNC_FIFO_FIRST_STROBE
#undef ASYNC_FIFO_FIRST_WORK
#undef ASYNC_FIFO_WRITE_ON_NET
#undef ASYNC_FIFO_CLASS

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

template class AsyncFifoNetToL2<1280, 16>;
template class AsyncFifoNetToL2<522, 16>;
template class AsyncFifoL2ToNet<30, 16>;
template class AsyncFifoL2ToNet<522, 16>;
