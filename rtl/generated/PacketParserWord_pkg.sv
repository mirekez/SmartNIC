package PacketParserWord_pkg;
import PacketParserFields_pkg::*;

typedef union packed {
    logic[512-1:0] raw;
    PacketParserFields fields;
} PacketParserWord;


endpackage
