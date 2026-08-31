package PacketDMA16_14_64_32_4_256_31_64_64_BackingBeat_pkg;

typedef struct packed {
    logic[7-1:0] _align0;
    logic clear;
    logic[32-1:0] keep;
    logic[256-1:0] data;
    logic[1-1:0] _align1;
    logic[31-1:0] address;
} PacketDMA16_14_64_32_4_256_31_64_64_BackingBeat;


endpackage
