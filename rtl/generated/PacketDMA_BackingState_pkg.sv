package PacketDMA_BackingState_pkg;

typedef enum logic[8-1:0] {
    BACKING_IDLE,
    BACKING_ADDRESS,
    BACKING_DATA,
    BACKING_RESPONSE
} PacketDMA_BackingState;


endpackage
