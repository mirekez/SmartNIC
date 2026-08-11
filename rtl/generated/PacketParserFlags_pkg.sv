package PacketParserFlags_pkg;

typedef enum {
    PACKET_PARSER_FLAG_PARSED = 'h1 <<< 'h0,
    PACKET_PARSER_FLAG_MALFORMED = 'h1 <<< 'h1,
    PACKET_PARSER_FLAG_LIMIT = 'h1 <<< 'h2,
    PACKET_PARSER_FLAG_VLAN = 'h1 <<< 'h3,
    PACKET_PARSER_FLAG_MPLS = 'h1 <<< 'h4,
    PACKET_PARSER_FLAG_IPV6 = 'h1 <<< 'h5,
    PACKET_PARSER_FLAG_TRANSPORT = 'h1 <<< 'h6,
    PACKET_PARSER_FLAG_FRAGMENT = 'h1 <<< 'h7
} PacketParserFlags;


endpackage
