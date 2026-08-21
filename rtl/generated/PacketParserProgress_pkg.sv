package PacketParserProgress_pkg;

typedef struct packed {
    logic[7-1:0] _align0;
    logic done;
    logic[7-1:0] _align2;
    logic limit;
    logic[7-1:0] _align1;
    logic error;
    logic[8-1:0] pos;
    logic[8-1:0] state;
} PacketParserProgress;


endpackage
