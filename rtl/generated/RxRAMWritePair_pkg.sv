package RxRAMWritePair_pkg;

typedef struct packed {
    logic[7-1:0] _align0;
    logic valid1;
    logic[7-1:0] _align1;
    logic valid0;
    logic[16-1:0] row1;
    logic[16-1:0] row0;
    logic[64-1:0] data1;
    logic[64-1:0] data0;
} RxRAMWritePair;


endpackage
