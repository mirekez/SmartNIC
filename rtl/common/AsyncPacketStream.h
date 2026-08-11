#pragma once

#include "AsyncFifo.h"

using namespace cpphdl;

#define ASYNC_PACKET_STREAM_CLASS AsyncPacketStreamNetToL2
#define ASYNC_PACKET_FIFO_CLASS AsyncFifoNetToL2
#define ASYNC_PACKET_SOURCE_ON_NET 1
#include "AsyncPacketStreamImpl.inc"
#undef ASYNC_PACKET_SOURCE_ON_NET
#undef ASYNC_PACKET_FIFO_CLASS
#undef ASYNC_PACKET_STREAM_CLASS

#define ASYNC_PACKET_STREAM_CLASS AsyncPacketStreamL2ToNet
#define ASYNC_PACKET_FIFO_CLASS AsyncFifoL2ToNet
#define ASYNC_PACKET_SOURCE_ON_NET 0
#include "AsyncPacketStreamImpl.inc"
#undef ASYNC_PACKET_SOURCE_ON_NET
#undef ASYNC_PACKET_FIFO_CLASS
#undef ASYNC_PACKET_STREAM_CLASS

template class AsyncPacketStreamNetToL2<160, 256, 16>;
template class AsyncPacketStreamNetToL2<320, 256, 16>;
template class AsyncPacketStreamL2ToNet<256, 160, 16>;
template class AsyncPacketStreamL2ToNet<256, 320, 16>;
