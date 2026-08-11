package RxDescriptorWord_pkg;
import RxDescriptor_pkg::*;
import PacketParserWord_pkg::*;
import PacketParserFields_pkg::*;

typedef union packed {
    logic[1280-1:0] raw;
    RxDescriptor descriptor;
} RxDescriptorWord;


endpackage
