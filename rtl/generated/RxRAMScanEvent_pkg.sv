package RxRAMScanEvent_pkg;

typedef struct packed {
    logic[7-1:0] _align0;
    logic protocol_error;
    logic[7-1:0] _align9;
    logic in_frame_next;
    logic[7-1:0] _align8;
    logic eop1;
    logic[7-1:0] _align7;
    logic eop0;
    logic[7-1:0] _align6;
    logic sop1;
    logic[7-1:0] _align5;
    logic sop0;
    logic[7-1:0] _align4;
    logic valid1;
    logic[7-1:0] _align3;
    logic valid0;
    logic[4-1:0] _align2;
    logic[4-1:0] bytes1;
    logic[4-1:0] _align1;
    logic[4-1:0] bytes0;
    logic[64-1:0] data1;
    logic[64-1:0] data0;
} RxRAMScanEvent;


endpackage
