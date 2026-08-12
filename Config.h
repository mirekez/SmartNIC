#pragma once

#define CPUS_USED 1
#define CPU_MEMORY (1024*1024*1024)
#ifndef HOST_AXI4
#define HOST_AXI4 0
#endif

// KlusterLab routes one PCIe lane to the XC7K160T.  A 64-bit user datapath at
// 125 MHz comfortably carries PCIe Gen2 x1 after 8b/10b encoding.
#define HOST_DATA_WIDTH 64
#define HOST_ADDR_WIDTH 64
#define SYSTEM_CLK_HZ 125000000ULL
#define SYSTEM_QUEUES 1

// Two 64-bit 10GbE MAC-side words at 156.25 MHz. Processing shares this clock;
// its 256-bit packet datapath has ample headroom for both ports.
#define NETWORK_PORTS 2
#define NET_CLK_HZ 156250000ULL
#define PROCESSING_CLK_HZ NET_CLK_HZ
#define L2_DATA_WIDTH 256
#define NET_LANE_WIDTH 64
#define L2_CLK_HZ NET_CLK_HZ

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
