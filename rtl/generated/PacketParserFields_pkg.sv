package PacketParserFields_pkg;

typedef struct packed {
    logic[8-1:0] reserved;
    logic[2-1:0][32-1:0] mpls;
    logic[2-1:0][16-1:0] vlan_tci;
    logic[8-1:0] flags;
    logic[8-1:0] ip_meta;
    logic[8-1:0] protocol;
    logic[16-1:0] destination_port;
    logic[16-1:0] source_port;
    logic[128-1:0] destination_ip;
    logic[128-1:0] source_ip;
    logic[48-1:0] source_mac;
    logic[48-1:0] destination_mac;
} PacketParserFields;


endpackage
