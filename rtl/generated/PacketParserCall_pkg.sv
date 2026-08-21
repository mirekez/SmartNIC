package PacketParserCall_pkg;
import PacketParserProgress_pkg::*;

typedef struct packed {
    PacketParserProgress progress;
    logic[64-1:0] markup_state;
} PacketParserCall;


endpackage
