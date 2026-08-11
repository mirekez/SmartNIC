package RxRAMWritePair320_13_pkg;

typedef struct packed {
    logic[7-1:0] _align0;
    logic valid1;
    logic[7-1:0] _align3;
    logic valid0;
    logic[3-1:0] _align2;
    logic[13-1:0] row1;
    logic[3-1:0] _align1;
    logic[13-1:0] row0;
    logic[320-1:0] data1;
    logic[320-1:0] data0;
} RxRAMWritePair320_13;


endpackage
