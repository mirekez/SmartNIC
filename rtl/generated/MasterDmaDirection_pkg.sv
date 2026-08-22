package MasterDmaDirection_pkg;

typedef enum logic[8-1:0] {
    MASTER_DMA_QUEUE_TO_HOST = 'h0,
    MASTER_DMA_HOST_TO_QUEUE = 'h1
} MasterDmaDirection;


endpackage
