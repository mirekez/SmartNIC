package PacketDmaOperation_pkg;

typedef enum {
    DMA_SYSTEM_CPU = 'h0,
    DMA_CPU_SYSTEM = 'h1,
    DMA_CPU_NETWORK = 'h2,
    DMA_NETWORK_CPU = 'h3
} PacketDmaOperation;


endpackage
