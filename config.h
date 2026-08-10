#define ENABLE_800G 0

// PacketParser bounds.  These are deliberately finite: the parser examines a
// fixed header window and reports PACKET_PARSER_FLAG_LIMIT instead of allowing
// an attacker-controlled header chain to create an unbounded datapath.
#define PACKET_PARSER_HEADER_BYTES 384
#define PACKET_PARSER_MAX_IPV4_OPTION_BYTES 40
#define PACKET_PARSER_MAX_IPV6_EXTENSION_HEADERS 8
#define PACKET_PARSER_MAX_IPV6_EXTENSION_BYTES 256
#define PACKET_PARSER_MAX_TCP_OPTION_BYTES 40

// VLAN/MPLS traversal can be disabled independently.  The output record is
// always 512 bits; disabled/shorter arrays become reserved zero bits.
#define PACKET_PARSER_ENABLE_VLAN 1
#define PACKET_PARSER_MAX_VLAN_HEADERS 4
#define PACKET_PARSER_OUTPUT_VLAN_HEADERS 2
#define PACKET_PARSER_ENABLE_MPLS 1
#define PACKET_PARSER_MAX_MPLS_LABELS 4
#define PACKET_PARSER_OUTPUT_MPLS_LABELS 2
