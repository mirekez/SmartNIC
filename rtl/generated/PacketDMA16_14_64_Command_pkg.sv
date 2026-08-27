package PacketDMA16_14_64_Command_pkg;

typedef struct packed {
    logic[8-1:0] network_port;
    logic[8-1:0] flags;
    logic[32-1:0] destination;
    logic[32-1:0] source;
    logic[2-1:0] _align1;
    logic[14-1:0] length;
    logic[16-1:0] handle;
} PacketDMA16_14_64_Command;


endpackage
