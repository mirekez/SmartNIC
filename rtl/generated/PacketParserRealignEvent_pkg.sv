package PacketParserRealignEvent_pkg;

typedef struct packed {
    logic[7-1:0] _align0;
    logic end_raw;
    logic[7-1:0] _align12;
    logic rollover;
    logic[7-1:0] _align11;
    logic frame_end;
    logic[7-1:0] _align10;
    logic eop1;
    logic[7-1:0] _align9;
    logic eop0;
    logic[7-1:0] _align8;
    logic sop1;
    logic[7-1:0] _align7;
    logic sop0;
    logic[7-1:0] _align6;
    logic raw1;
    logic[7-1:0] _align5;
    logic raw0;
    logic[7-1:0] _align4;
    logic valid1;
    logic[7-1:0] _align3;
    logic valid0;
    logic[4-1:0] _align2;
    logic[4-1:0] bytes1;
    logic[4-1:0] _align1;
    logic[4-1:0] bytes0;
    logic[8-1:0] word_cntr1;
    logic[8-1:0] word_cntr0;
    logic[8-1:0] raw_count;
    logic[512-1:0] raw_data_high;
    logic[512-1:0] raw_data_low;
    logic[64-1:0] data1;
    logic[64-1:0] data0;
} PacketParserRealignEvent;


endpackage
