// TxQueue test: scatter-gather-compatible packet commitment, packet metadata,
// randomized processing-side backpressure, ordering, and synchronous clear.

#include "../TxQueue.h"

using TestedQueue = TxQueue<256>;
static constexpr const char* QUEUE_SOURCE_FILE = __FILE__;
#define QUEUE_LABEL "TxQueue"
#define QUEUE_TOP "TxQueue"
#define QUEUE_GENERATED_DIR "generated_tx_queue"
#include "packet_queue_test.inc"
