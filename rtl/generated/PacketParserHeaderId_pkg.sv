package PacketParserHeaderId_pkg;

typedef enum logic[8-1:0] {
    PACKET_HEADER_NONE = 'h0,
    PACKET_HEADER_VLAN = 'h1,
    PACKET_HEADER_MPLS = 'h2,
    PACKET_HEADER_IPV4 = 'h4,
    PACKET_HEADER_IPV4_OPTIONS = 'h8,
    PACKET_HEADER_IPV6 = 'h10,
    PACKET_HEADER_IPV6_OPTIONS = 'h20,
    PACKET_HEADER_TCP = 'h40,
    PACKET_HEADER_UDP = 'h80
} PacketParserHeaderId;


endpackage
