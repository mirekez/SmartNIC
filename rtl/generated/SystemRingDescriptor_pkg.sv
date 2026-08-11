package SystemRingDescriptor_pkg;

typedef struct packed {
    logic[32-1:0] reserved;
    logic[8-1:0] flags;
    logic[8-1:0] queue;
    logic[16-1:0] length;
    logic[64-1:0] address;
} SystemRingDescriptor;


endpackage
