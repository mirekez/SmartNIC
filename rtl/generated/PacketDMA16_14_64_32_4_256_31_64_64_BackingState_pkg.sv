package PacketDMA16_14_64_32_4_256_31_64_64_BackingState_pkg;

typedef enum logic[8-1:0] {
    BACKING_IDLE,
    BACKING_ADDRESS,
    BACKING_DATA,
    BACKING_RESPONSE
} PacketDMA16_14_64_32_4_256_31_64_64_BackingState;


endpackage
