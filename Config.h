#pragma once

#ifndef ENABLE_800G
#define ENABLE_800G 0
#endif
#define CPUS_USED   4
#define CPU_MEMORY (1024*1024*1024)
#ifndef HOST_AXI4
#define HOST_AXI4 0
#endif

// System/host datapath.  Both the AXI4 and Avalon variants use 256-bit data;
// HOST_AXI4 selects the external pin protocol without changing queue formats.
#define HOST_DATA_WIDTH 256
#define HOST_ADDR_WIDTH 64
#define SYSTEM_CLK_HZ 250000000ULL

// Datapath clocks.  The L2 clock is rate-matched to one balanced Ethernet
// stream so a 256-bit CPU/DMA lane has exactly the same raw byte rate.
#define NET_CLK_HZ 312500000ULL
#define L2_DATA_WIDTH 256
#if ENABLE_800G
#define NET_LANE_WIDTH 320
#else
#define NET_LANE_WIDTH 160
#endif
#define L2_CLK_HZ ((NET_CLK_HZ * NET_LANE_WIDTH) / L2_DATA_WIDTH)

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
