#pragma once

#include <cpphdl.h>

using namespace cpphdl;

#define ASYNC_FIFO_CLASS AsyncFifoNetToL2
#define ASYNC_FIFO_WRITE_ON_NET 1
#include "AsyncFifoImpl.inc"
#undef ASYNC_FIFO_WRITE_ON_NET
#undef ASYNC_FIFO_CLASS

#define ASYNC_FIFO_CLASS AsyncFifoL2ToNet
#define ASYNC_FIFO_WRITE_ON_NET 0
#include "AsyncFifoImpl.inc"
#undef ASYNC_FIFO_WRITE_ON_NET
#undef ASYNC_FIFO_CLASS

template class AsyncFifoNetToL2<1280, 16>;
template class AsyncFifoNetToL2<522, 16>;
template class AsyncFifoL2ToNet<30, 16>;
template class AsyncFifoL2ToNet<522, 16>;
