package PacketParserPipeWord_pkg;
import PacketParserFields_pkg::*;
import PacketParserProgress_pkg::*;

typedef struct packed {
    logic[7-1:0] _align0;
    logic eop;
    logic[7-1:0] _align6;
    logic sop;
    logic[7-1:0] _align5;
    logic raw;
    logic[5-1:0] _align4;
    logic[3-1:0] ipv6_ext_index;
    logic[5-1:0] _align3;
    logic[3-1:0] mpls_index;
    logic[5-1:0] _align2;
    logic[3-1:0] vlan_index;
    logic[4-1:0] _align1;
    logic[4-1:0] bytes;
    logic[8-1:0] word_cntr;
    PacketParserProgress progress;
    PacketParserFields fields;
    logic[64-1:0] data;
} PacketParserPipeWord;


endpackage
