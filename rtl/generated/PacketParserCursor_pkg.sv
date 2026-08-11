package PacketParserCursor_pkg;
import PacketParserFields_pkg::*;

typedef struct packed {
    logic[7-1:0] _align0;
    logic ok;
    logic[7-1:0] _align1;
    logic noninitial_fragment;
    logic[32-1:0] count;
    logic[32-1:0] selector;
    logic[32-1:0] offset;
    PacketParserFields fields;
} PacketParserCursor;


endpackage
