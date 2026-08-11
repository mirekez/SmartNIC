package RxDescriptor_pkg;
import PacketParserWord_pkg::*;
import PacketParserFields_pkg::*;

typedef struct packed {
    PacketParserWord packet_word1;
    PacketParserWord packet_word0;
    logic[192-1:0] reserved;
    logic[8-1:0] flags;
    logic[8-1:0] ingress_stream;
    logic[16-1:0] packet_length;
    logic[32-1:0] packet_address;
} RxDescriptor;


endpackage
