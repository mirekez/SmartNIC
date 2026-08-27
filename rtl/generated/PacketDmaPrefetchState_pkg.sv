package PacketDmaPrefetchState_pkg;

typedef enum logic[8-1:0] {
    PACKET_DMA_PREFETCH_IDLE,
    PACKET_DMA_PREFETCH_ISSUE,
    PACKET_DMA_PREFETCH_STREAM
} PacketDmaPrefetchState;


endpackage
