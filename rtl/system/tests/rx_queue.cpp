// RxQueue test: complete-packet visibility, packet metadata, simultaneous
// packet storage, randomized consumer backpressure, and synchronous clear.

#include "../RxQueue.h"

using TestedQueue = RxQueue<256>;
static constexpr const char* QUEUE_SOURCE_FILE = __FILE__;
#define QUEUE_LABEL "RxQueue"
#define QUEUE_TOP "RxQueue"
#define QUEUE_GENERATED_DIR "generated_rx_queue"
#include "packet_queue_test.inc"
