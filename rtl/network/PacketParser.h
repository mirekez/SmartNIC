#pragma once

// Single-channel, on-the-fly Ethernet parser.  Network instantiates one parser
// per independent narrow receive channel.  Header-call markup is passed by
// value as {absolute byte position, one header ID per lane}.  Runtime progress
// and each aligned word then cross one registered stage per header occurrence.

#include "../../Config.h"
#include <cpphdl.h>
#include "../common/ClockDomains.h"

using namespace cpphdl;

extern long _system_clock;

#if PACKET_PARSER_ENABLE_VLAN
#define PACKET_PARSER_VLAN_OUTPUT_BITS (PACKET_PARSER_OUTPUT_VLAN_HEADERS * 16)
#else
#define PACKET_PARSER_VLAN_OUTPUT_BITS 0
#endif
#if PACKET_PARSER_ENABLE_MPLS
#define PACKET_PARSER_MPLS_OUTPUT_BITS (PACKET_PARSER_OUTPUT_MPLS_LABELS * 32)
#else
#define PACKET_PARSER_MPLS_OUTPUT_BITS 0
#endif
#define PACKET_PARSER_FIELDS_USED_BITS \
    (2 * 48 + 2 * 128 + 2 * 16 + 8 + 8 + 8 \
        + PACKET_PARSER_VLAN_OUTPUT_BITS + PACKET_PARSER_MPLS_OUTPUT_BITS)
#define PACKET_PARSER_FIELDS_RESERVED_BITS (512 - PACKET_PARSER_FIELDS_USED_BITS)

struct PacketParserFields
{
    logic<48> destination_mac;
    logic<48> source_mac;
    logic<128> source_ip;
    logic<128> destination_ip;
    u16 source_port;
    u16 destination_port;
    u8 protocol;
    u8 ip_meta;
    u8 flags;
#if PACKET_PARSER_ENABLE_VLAN
    array<PACKET_PARSER_OUTPUT_VLAN_HEADERS, u16> vlan_tci;
#endif
#if PACKET_PARSER_ENABLE_MPLS
    array<PACKET_PARSER_OUTPUT_MPLS_LABELS, u32> mpls;
#endif
    logic<PACKET_PARSER_FIELDS_RESERVED_BITS> reserved;
} __PACKED;

union PacketParserWord
{
    PacketParserFields fields;
    logic<512> raw;
} __PACKED;

static_assert(sizeof(PacketParserFields) == 64);
static_assert(sizeof(PacketParserWord) == 64);
static_assert(PACKET_PARSER_MAX_VLAN_HEADERS == 4);
static_assert(PACKET_PARSER_MAX_MPLS_LABELS == 4);
static_assert(PACKET_PARSER_MAX_IPV6_EXTENSION_HEADERS == 8);

enum PacketParserFlags : uint8_t
{
    PACKET_PARSER_FLAG_PARSED = 1u << 0,
    PACKET_PARSER_FLAG_MALFORMED = 1u << 1,
    PACKET_PARSER_FLAG_LIMIT = 1u << 2,
    PACKET_PARSER_FLAG_VLAN = 1u << 3,
    PACKET_PARSER_FLAG_MPLS = 1u << 4,
    PACKET_PARSER_FLAG_IPV6 = 1u << 5,
    PACKET_PARSER_FLAG_TRANSPORT = 1u << 6,
    PACKET_PARSER_FLAG_FRAGMENT = 1u << 7
};

enum PacketParserHeaderId : uint8_t
{
    PACKET_HEADER_NONE = 0,
    PACKET_HEADER_VLAN = 1,
    PACKET_HEADER_MPLS = 2,
    PACKET_HEADER_IPV4 = 4,
    PACKET_HEADER_IPV4_OPTIONS = 8,
    PACKET_HEADER_IPV6 = 16,
    PACKET_HEADER_IPV6_OPTIONS = 32,
    PACKET_HEADER_TCP = 64,
    PACKET_HEADER_UDP = 128
};

// The only value threaded through the ordered on-the-fly header functions.
// Header-owned field registers are deliberately not part of this value, so
// their capture logic cannot become a serial dependency through every parser.
struct PacketParserProgress
{
    u8 state;
    u8 pos;
    u1 error;
    u1 limit;
    u1 done;
} __PACKED;

struct PacketParserCall
{
    logic<320> markup_state;
    PacketParserProgress progress;
} __PACKED;

// One aligned packet word and the parse result accumulated while that word
// crosses the protocol-family pipeline.  Fields are only snapshotted on EOP;
// carrying that snapshot with the last word lets a following packet enter the
// early stages without corrupting completion of the preceding packet.
struct PacketParserPipeWord
{
    logic<320> data;
    PacketParserFields fields;
    PacketParserProgress progress;
    u8 word_cntr;
    u<6> bytes;
    // Inclusive absolute-byte window covered by this word.  A reversed
    // [255, 0] window denotes a word beyond the u8 parser-position range.
    // Carrying this window prevents every protocol stage from rebuilding
    // word_cntr * LANE_BYTES on its recurrence path.
    u8 word_start;
    u8 word_last;
    u<3> vlan_index;
    logic<32> vlan_decode;
    logic<4> vlan_decode_valid;
    u<3> mpls_index;
    logic<40> mpls_decode;
    logic<5> mpls_decode_valid;
    u<4> ipv6_ext_index;
    // Registered bytes at offsets 0..3 of the active IPv6 extension header.
    // Separating the 320-bit lane selection from extension-state resolution
    // keeps the per-word recurrence shallow enough for the parser clock.
    logic<32> ipv6_ext_decode;
    logic<4> ipv6_ext_decode_valid;
    u8 ipv6_ext_decoded_size;
    u8 ipv6_ext_decoded_next_pos;
    u1 ipv6_ext_size_known;
    u1 ipv6_ext_header_complete;
    u1 ipv6_ext_decoded_limit;
    logic<40> transport_decode;
    logic<5> transport_decode_valid;
    u1 raw;
    u1 sop;
    u1 eop;
} __PACKED;

template<size_t LANE_WIDTH = 160>
class PacketParser : public Module
{
public:
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t BYTE_COUNT_BITS = clog2(LANE_BYTES + 1);
    static constexpr size_t OUTPUT_WORD_BITS = 512;
    static constexpr size_t OUTPUT_BYTES = 64;
    static constexpr size_t OUTPUT_FIFO_WORDS = 32;
    static constexpr size_t RAW_BYTES = 128;
    static constexpr size_t RAW_WORDS =
        (RAW_BYTES + LANE_BYTES - 1) / LANE_BYTES;
    static constexpr size_t MARKUP_BITS = 320;
    // One registered boundary per protocol family. Repeated bounded headers
    // retain their explicit occurrence functions and execute in architectural
    // order within their family stage.
    static constexpr size_t PIPE_STAGES = 49;

    static_assert(LANE_WIDTH == 160 || LANE_WIDTH == 320);

    _PORT(bool) valid_in;
    _PORT(logic<LANE_WIDTH>) data_in;
    _PORT(logic<LANE_BYTES>) keep_in;
    _PORT(logic<LANE_BYTES>) sop_in;
    _PORT(logic<LANE_BYTES>) eop_in;
    _PORT(bool) raw_in;
    _PORT(bool) ready_out;

    _PORT(PacketParserWord) data_out;
    _PORT(logic<OUTPUT_BYTES>) keep_out;
    _PORT(bool) valid_out;
    _PORT(bool) last_out;
    _PORT(bool) raw_out;
    _PORT(bool) ready_in;
    _PORT(bool) protocol_error_out;

private:
    // The transport stage retains the externally visible current parse state.
    // Earlier protocol families have independent pipeline contexts so that
    // consecutive words can occupy different stages at the same time.
    reg<u8> state_reg;
    reg<u8> pos_reg;
    reg<u8> word_cntr_reg;
    reg<u1> ethernet_done_reg;
    reg<u1> error_reg;
    reg<u1> limit_reg;
    reg<u1> done_reg;
    reg<PacketParserProgress> ethernet_progress_reg;
    reg<PacketParserProgress> vlan_progress_reg[4];
    reg<u<3>> vlan_stage_index_reg[4];
    reg<PacketParserProgress> mpls_progress_reg[4];
    reg<u<3>> mpls_stage_index_reg[4];
    reg<PacketParserProgress> ipv4_progress_reg;
    reg<PacketParserProgress> ipv4_options_progress_reg;
    reg<PacketParserProgress> ipv6_progress_reg;
    reg<PacketParserProgress> ipv6_ext_progress_reg[8];
    reg<u<2>> ipv6_ext_stage_index_reg[8];
    reg<PacketParserProgress> tcp_progress_reg;

    // Ethernet-owned registers.
    reg<logic<48>> destination_mac_reg;
    reg<logic<48>> source_mac_reg;
    reg<u16> ethernet_type_reg;

    // VLAN-owned registers.
    reg<u16> vlan_next_proto_reg[4];
    reg<u<3>> vlan_count_reg;
#if PACKET_PARSER_ENABLE_VLAN
    reg<u16> vlan_tci_reg[PACKET_PARSER_OUTPUT_VLAN_HEADERS];
#endif

    // MPLS-owned registers.
    reg<u32> mpls_entry_reg[4];
    reg<u1> mpls_entry_done_reg[4];
    reg<u<3>> mpls_count_reg;
#if PACKET_PARSER_ENABLE_MPLS
    reg<u32> mpls_output_reg[PACKET_PARSER_OUTPUT_MPLS_LABELS];
#endif

    // IP-owned registers.
    reg<logic<128>> source_ip_reg;
    reg<logic<128>> destination_ip_reg;
    reg<u8> protocol_reg;
    reg<u8> ip_version_reg;
    reg<u8> ip_header_bytes_reg;
    reg<u8> transport_pos_reg;
    reg<u16> ipv4_fragment_reg;
    reg<u1> initial_fragment_reg;
    reg<logic<128>> ipv6_source_ip_reg;
    reg<logic<128>> ipv6_destination_ip_reg;
    reg<u8> ipv6_base_next_proto_reg;
    reg<u1> ipv6_seen_reg;
    reg<u8> ipv6_next_proto_reg[8];
    reg<u8> ipv6_ext_size_reg[8];
    reg<u8> ipv6_ext_extent_size_reg[8];
    reg<u1> ipv6_ext_seen_reg[8];
    reg<u16> ipv6_fragment_reg[8];
    reg<u1> noninitial_fragment_reg[8];

    // Transport-owned registers.
    reg<u16> source_port_reg;
    reg<u16> destination_port_reg;
    reg<u8> tcp_header_bytes_reg;

    // Packet realignment and RAW capture.
    reg<logic<LANE_WIDTH>> align_data_reg;
    reg<u<BYTE_COUNT_BITS>> align_count_reg;
    reg<logic<OUTPUT_WORD_BITS>> raw_data_low_reg;
    reg<logic<OUTPUT_WORD_BITS>> raw_data_high_reg;
    reg<u<5>> raw_word_count_reg;
    reg<u1> in_frame_reg;
    reg<u1> frame_raw_reg;
    reg<u1> pending_valid_reg;
    reg<u1> pending_rollover_reg;
    reg<logic<LANE_WIDTH>> pending_data_reg;
    reg<u<BYTE_COUNT_BITS>> pending_bytes_reg;
    reg<u8> pending_word_cntr_reg;
    reg<u1> pending_sop_reg;
    reg<u1> pending_eop_reg;
    reg<u1> pending_raw_token_reg;
    reg<u8> align_word_cntr_reg;
    reg<u1> align_sop_pending_reg;
    // Elastic ingress descriptor. Boundary classification is registered
    // before the barrel alignment and RAW accumulator so neither path also
    // traverses the per-byte SOP/EOP/keep scan.
    reg<u1> ingress_valid_reg;
    reg<logic<LANE_WIDTH>> ingress_data_reg;
    reg<u1> ingress_error_reg;
    reg<u1> ingress_segment_valid_reg[2];
    reg<u1> ingress_segment_sop_reg[2];
    reg<u1> ingress_segment_eop_reg[2];
    reg<u1> ingress_segment_raw_reg[2];
    reg<u<BYTE_COUNT_BITS>> ingress_segment_start_reg[2];
    reg<u<BYTE_COUNT_BITS>> ingress_segment_bytes_reg[2];
    reg<u1> decode_in_frame_reg;
    reg<u1> decode_frame_raw_reg;
    reg<u1> raw_emit_valid_reg[2];
    reg<logic<LANE_WIDTH>> raw_emit_data_reg[2];
    reg<u<BYTE_COUNT_BITS>> raw_emit_bytes_reg[2];
    reg<u8> raw_emit_word_cntr_reg[2];
    reg<u1> raw_emit_sop_reg[2];
    reg<u1> raw_emit_eop_reg[2];

    // 0: aligned input, 1: registered absolute byte bounds, 2: Ethernet,
    // 3-10: VLAN decode/occurrence pairs, 11-18: MPLS
    // decode/occurrence pairs, 19: IPv4, 20: IPv4 options, 21: IPv6,
    // 22-45: IPv6 extension decode/extent/occurrence triples,
    // 46: transport decode, 47: TCP, 48: UDP/completion.
    reg<PacketParserPipeWord> pipe_reg[PIPE_STAGES];
    reg<u1> pipe_valid_reg[PIPE_STAGES];

    // RAW payloads wait here while a lightweight completion token traverses
    // the same pipeline as parsed EOPs, preserving descriptor order.
    reg<logic<OUTPUT_WORD_BITS>> raw_store_low_reg[4];
    reg<logic<OUTPUT_WORD_BITS>> raw_store_high_reg[4];
    reg<u8> raw_store_count_bytes_reg[4];
    reg<u<2>> raw_store_head_reg;
    reg<u<2>> raw_store_tail_reg;
    reg<u<3>> raw_store_count_reg;

    reg<logic<OUTPUT_WORD_BITS>> fifo_data_reg[OUTPUT_FIFO_WORDS];
    reg<logic<OUTPUT_BYTES>> fifo_keep_reg[OUTPUT_FIFO_WORDS];
    reg<u1> fifo_last_reg[OUTPUT_FIFO_WORDS];
    reg<u1> fifo_raw_reg[OUTPUT_FIFO_WORDS];
    reg<u<5>> fifo_head_reg;
    reg<u<5>> fifo_tail_reg;
    reg<u<6>> fifo_count_reg;
    // Total output words already committed by the FIFO and in-flight EOPs.
    // Keeping this as a credit counter avoids a combinational scan across all
    // parser pipeline stages on the ingress-ready path.
    reg<u<6>> reserved_slots_reg;
    reg<u1> protocol_error_reg;

    PacketParserWord output_data_comb;
    logic<OUTPUT_BYTES> output_keep_comb;
    bool output_valid_comb;
    bool output_last_comb;
    bool output_raw_comb;
    bool input_ready_comb;

    static bool is_vlan(uint16_t selector)
    {
        return selector == 0x8100 || selector == 0x88a8
            || selector == 0x9100;
    }

    static bool is_mpls(uint16_t selector)
    {
        return selector == 0x8847 || selector == 0x8848;
    }

    static bool is_ipv6_extension(uint8_t selector)
    {
        return selector == 0 || selector == 43 || selector == 44
            || selector == 51 || selector == 60 || selector == 135;
    }

    static logic<MARKUP_BITS> mark_header(logic<MARKUP_BITS> previous,
        uint8_t markup_pos, uint8_t header_id)
    {
        logic<MARKUP_BITS> result;
        uint8_t lane;
        result = previous;
        lane = markup_pos % LANE_BYTES;
        if (lane == 0) result.bits(7, 0) = u8(header_id);
        if (lane == 1) result.bits(15, 8) = u8(header_id);
        if (lane == 2) result.bits(23, 16) = u8(header_id);
        if (lane == 3) result.bits(31, 24) = u8(header_id);
        if (lane == 4) result.bits(39, 32) = u8(header_id);
        if (lane == 5) result.bits(47, 40) = u8(header_id);
        if (lane == 6) result.bits(55, 48) = u8(header_id);
        if (lane == 7) result.bits(63, 56) = u8(header_id);
        if (lane == 8) result.bits(71, 64) = u8(header_id);
        if (lane == 9) result.bits(79, 72) = u8(header_id);
        if (lane == 10) result.bits(87, 80) = u8(header_id);
        if (lane == 11) result.bits(95, 88) = u8(header_id);
        if (lane == 12) result.bits(103, 96) = u8(header_id);
        if (lane == 13) result.bits(111, 104) = u8(header_id);
        if (lane == 14) result.bits(119, 112) = u8(header_id);
        if (lane == 15) result.bits(127, 120) = u8(header_id);
        if (lane == 16) result.bits(135, 128) = u8(header_id);
        if (lane == 17) result.bits(143, 136) = u8(header_id);
        if (lane == 18) result.bits(151, 144) = u8(header_id);
        if (lane == 19) result.bits(159, 152) = u8(header_id);
        if (lane == 20) result.bits(167, 160) = u8(header_id);
        if (lane == 21) result.bits(175, 168) = u8(header_id);
        if (lane == 22) result.bits(183, 176) = u8(header_id);
        if (lane == 23) result.bits(191, 184) = u8(header_id);
        if (lane == 24) result.bits(199, 192) = u8(header_id);
        if (lane == 25) result.bits(207, 200) = u8(header_id);
        if (lane == 26) result.bits(215, 208) = u8(header_id);
        if (lane == 27) result.bits(223, 216) = u8(header_id);
        if (lane == 28) result.bits(231, 224) = u8(header_id);
        if (lane == 29) result.bits(239, 232) = u8(header_id);
        if (lane == 30) result.bits(247, 240) = u8(header_id);
        if (lane == 31) result.bits(255, 248) = u8(header_id);
        if (lane == 32) result.bits(263, 256) = u8(header_id);
        if (lane == 33) result.bits(271, 264) = u8(header_id);
        if (lane == 34) result.bits(279, 272) = u8(header_id);
        if (lane == 35) result.bits(287, 280) = u8(header_id);
        if (lane == 36) result.bits(295, 288) = u8(header_id);
        if (lane == 37) result.bits(303, 296) = u8(header_id);
        if (lane == 38) result.bits(311, 304) = u8(header_id);
        if (lane == 39) result.bits(319, 312) = u8(header_id);
        return result;
    }

    static uint8_t marked_header(const logic<MARKUP_BITS>& markup_state,
        uint8_t markup_pos)
    {
        uint8_t lane;
        uint8_t result;
        lane = markup_pos % LANE_BYTES;
        result = 0;
        if (lane == 0) result = (uint8_t)markup_state.bits(7, 0);
        if (lane == 1) result = (uint8_t)markup_state.bits(15, 8);
        if (lane == 2) result = (uint8_t)markup_state.bits(23, 16);
        if (lane == 3) result = (uint8_t)markup_state.bits(31, 24);
        if (lane == 4) result = (uint8_t)markup_state.bits(39, 32);
        if (lane == 5) result = (uint8_t)markup_state.bits(47, 40);
        if (lane == 6) result = (uint8_t)markup_state.bits(55, 48);
        if (lane == 7) result = (uint8_t)markup_state.bits(63, 56);
        if (lane == 8) result = (uint8_t)markup_state.bits(71, 64);
        if (lane == 9) result = (uint8_t)markup_state.bits(79, 72);
        if (lane == 10) result = (uint8_t)markup_state.bits(87, 80);
        if (lane == 11) result = (uint8_t)markup_state.bits(95, 88);
        if (lane == 12) result = (uint8_t)markup_state.bits(103, 96);
        if (lane == 13) result = (uint8_t)markup_state.bits(111, 104);
        if (lane == 14) result = (uint8_t)markup_state.bits(119, 112);
        if (lane == 15) result = (uint8_t)markup_state.bits(127, 120);
        if (lane == 16) result = (uint8_t)markup_state.bits(135, 128);
        if (lane == 17) result = (uint8_t)markup_state.bits(143, 136);
        if (lane == 18) result = (uint8_t)markup_state.bits(151, 144);
        if (lane == 19) result = (uint8_t)markup_state.bits(159, 152);
        if (lane == 20) result = (uint8_t)markup_state.bits(167, 160);
        if (lane == 21) result = (uint8_t)markup_state.bits(175, 168);
        if (lane == 22) result = (uint8_t)markup_state.bits(183, 176);
        if (lane == 23) result = (uint8_t)markup_state.bits(191, 184);
        if (lane == 24) result = (uint8_t)markup_state.bits(199, 192);
        if (lane == 25) result = (uint8_t)markup_state.bits(207, 200);
        if (lane == 26) result = (uint8_t)markup_state.bits(215, 208);
        if (lane == 27) result = (uint8_t)markup_state.bits(223, 216);
        if (lane == 28) result = (uint8_t)markup_state.bits(231, 224);
        if (lane == 29) result = (uint8_t)markup_state.bits(239, 232);
        if (lane == 30) result = (uint8_t)markup_state.bits(247, 240);
        if (lane == 31) result = (uint8_t)markup_state.bits(255, 248);
        if (lane == 32) result = (uint8_t)markup_state.bits(263, 256);
        if (lane == 33) result = (uint8_t)markup_state.bits(271, 264);
        if (lane == 34) result = (uint8_t)markup_state.bits(279, 272);
        if (lane == 35) result = (uint8_t)markup_state.bits(287, 280);
        if (lane == 36) result = (uint8_t)markup_state.bits(295, 288);
        if (lane == 37) result = (uint8_t)markup_state.bits(303, 296);
        if (lane == 38) result = (uint8_t)markup_state.bits(311, 304);
        if (lane == 39) result = (uint8_t)markup_state.bits(319, 312);
        return result;
    }

    static bool byte_present(uint8_t absolute, uint8_t word_cntr,
        uint8_t word_bytes)
    {
        // The parser call ABI retains the historical argument order, but the
        // pipeline supplies an inclusive [word_cntr, word_bytes] absolute
        // byte window here.  This keeps range checks shallow in every stage.
        return absolute >= word_cntr && absolute <= word_bytes;
    }

    static bool field_complete(uint8_t absolute, uint8_t bytes,
        uint8_t word_cntr, uint8_t word_bytes)
    {
        return byte_present((uint8_t)(absolute + bytes - 1),
            word_cntr, word_bytes);
    }

    static uint8_t word_byte(const logic<320>& word, uint8_t absolute,
        uint8_t word_cntr)
    {
        uint8_t lane;
        lane = absolute - word_cntr;
        return (uint8_t)word.bits(lane * 8 + 7, lane * 8);
    }

    static u8 capture_u8(const logic<320>& word, u8 previous,
        uint8_t absolute, uint8_t word_cntr, uint8_t word_bytes)
    {
        u8 result;
        result = previous;
        if (byte_present(absolute, word_cntr, word_bytes))
            result = u8(word_byte(word, absolute, word_cntr));
        return result;
    }

    static u16 capture_be16(const logic<320>& word, u16 previous,
        uint8_t absolute, uint8_t word_cntr, uint8_t word_bytes)
    {
        uint16_t result;
        uint8_t byte;
        result = (uint16_t)previous;
        byte = (uint8_t)capture_u8(word, u8(result >> 8),
            absolute, word_cntr, word_bytes);
        result = (result & 0x00ff) | ((uint16_t)byte << 8);
        byte = (uint8_t)capture_u8(word, u8(result),
            (uint8_t)(absolute + 1), word_cntr, word_bytes);
        result = (result & 0xff00) | byte;
        return u16(result);
    }

    static u32 capture_be32(const logic<320>& word, u32 previous,
        uint8_t absolute, uint8_t word_cntr, uint8_t word_bytes)
    {
        uint32_t result;
        uint8_t byte;
        result = (uint32_t)previous;
        byte = (uint8_t)capture_u8(word, u8(result >> 24), absolute, word_cntr, word_bytes);
        result = (result & 0x00ffffff) | ((uint32_t)byte << 24);
        byte = (uint8_t)capture_u8(word, u8(result >> 16), (uint8_t)(absolute + 1), word_cntr, word_bytes);
        result = (result & 0xff00ffff) | ((uint32_t)byte << 16);
        byte = (uint8_t)capture_u8(word, u8(result >> 8), (uint8_t)(absolute + 2), word_cntr, word_bytes);
        result = (result & 0xffff00ff) | ((uint32_t)byte << 8);
        byte = (uint8_t)capture_u8(word, u8(result), (uint8_t)(absolute + 3), word_cntr, word_bytes);
        result = (result & 0xffffff00) | byte;
        return u32(result);
    }

    static logic<48> capture_be48(const logic<320>& word, logic<48> previous,
        uint8_t absolute, uint8_t word_cntr, uint8_t word_bytes)
    {
        logic<48> result;
        uint8_t byte;
        result = previous;
        for (byte = 0; byte < 6; ++byte)
            result.bits(47 - byte * 8, 40 - byte * 8) = capture_u8(word,
                u8(result.bits(47 - byte * 8, 40 - byte * 8)),
                (uint8_t)(absolute + byte), word_cntr, word_bytes);
        return result;
    }

    static logic<128> capture_be128(const logic<320>& word,
        logic<128> previous, uint8_t absolute, uint8_t word_cntr,
        uint8_t word_bytes)
    {
        logic<128> result;
        uint8_t byte;
        result = previous;
        for (byte = 0; byte < 16; ++byte)
            result.bits(127 - byte * 8, 120 - byte * 8) = capture_u8(word,
                u8(result.bits(127 - byte * 8, 120 - byte * 8)),
                (uint8_t)(absolute + byte), word_cntr, word_bytes);
        return result;
    }

    static bool header_active(uint8_t markup_pos,
        const logic<MARKUP_BITS>& markup_state, uint8_t header_id,
        PacketParserProgress progress)
    {
        // Every occurrence function marks markup_state[markup_pos] with its
        // own statically known header ID immediately before doing real work.
        // Re-reading that dynamically indexed byte here only recreates a wide
        // mux on the state feedback path; progress is the registered work
        // token that qualifies the hardware operation.
        return !(bool)progress.error
            && !(bool)progress.limit
            && !(bool)progress.done
            // Header IDs are one-hot.  Test the protocol bit directly so an
            // occurrence does not instantiate an eight-bit equality tree.
            && (((uint8_t)progress.state & header_id) != 0);
    }

    static u8 select_l3(uint16_t selector)
    {
        if (is_vlan(selector)) return u8(PACKET_HEADER_VLAN);
        if (is_mpls(selector)) return u8(PACKET_HEADER_MPLS);
        if (selector == 0x0800) return u8(PACKET_HEADER_IPV4);
        if (selector == 0x86dd) return u8(PACKET_HEADER_IPV6);
        return u8(PACKET_HEADER_NONE);
    }

    static u8 select_transport(uint8_t protocol)
    {
        if (protocol == 6) return u8(PACKET_HEADER_TCP);
        if (protocol == 17) return u8(PACKET_HEADER_UDP);
        return u8(PACKET_HEADER_NONE);
    }

    void reset_parser()
    {
        uint32_t index;
        PacketParserProgress progress;
        progress = {};
        state_reg._next = PACKET_HEADER_NONE;
        pos_reg._next = 0;
        word_cntr_reg._next = 0;
        ethernet_done_reg._next = 0;
        error_reg._next = 0;
        limit_reg._next = 0;
        done_reg._next = 0;
        ethernet_progress_reg._next = progress;
        for (index = 0; index < 4; ++index) {
            vlan_progress_reg[index]._next = progress;
            vlan_stage_index_reg[index]._next = 0;
        }
        for (index = 0; index < 4; ++index) {
            mpls_progress_reg[index]._next = progress;
            mpls_stage_index_reg[index]._next = 0;
        }
        ipv4_progress_reg._next = progress;
        ipv4_options_progress_reg._next = progress;
        ipv6_progress_reg._next = progress;
        tcp_progress_reg._next = progress;
        for (index = 0; index < 8; ++index) {
            ipv6_ext_progress_reg[index]._next = progress;
            ipv6_ext_stage_index_reg[index]._next = 0;
        }
        destination_mac_reg._next = 0;
        source_mac_reg._next = 0;
        ethernet_type_reg._next = 0;
        for (index = 0; index < 4; ++index)
            vlan_next_proto_reg[index]._next = 0;
        vlan_count_reg._next = 0;
#if PACKET_PARSER_ENABLE_VLAN
        for (index = 0; index < PACKET_PARSER_OUTPUT_VLAN_HEADERS; ++index)
            vlan_tci_reg[index]._next = 0;
#endif
        for (index = 0; index < 4; ++index) {
            mpls_entry_reg[index]._next = 0;
            mpls_entry_done_reg[index]._next = 0;
        }
        mpls_count_reg._next = 0;
#if PACKET_PARSER_ENABLE_MPLS
        for (index = 0; index < PACKET_PARSER_OUTPUT_MPLS_LABELS; ++index)
            mpls_output_reg[index]._next = 0;
#endif
        source_ip_reg._next = 0;
        destination_ip_reg._next = 0;
        protocol_reg._next = 0;
        ip_version_reg._next = 0;
        ip_header_bytes_reg._next = 0;
        transport_pos_reg._next = 0;
        ipv4_fragment_reg._next = 0;
        initial_fragment_reg._next = 1;
        ipv6_source_ip_reg._next = 0;
        ipv6_destination_ip_reg._next = 0;
        ipv6_base_next_proto_reg._next = 0;
        ipv6_seen_reg._next = 0;
        for (index = 0; index < 8; ++index) {
            ipv6_next_proto_reg[index]._next = 0;
            ipv6_ext_size_reg[index]._next = 0;
            ipv6_ext_extent_size_reg[index]._next = 0;
            ipv6_ext_seen_reg[index]._next = 0;
            ipv6_fragment_reg[index]._next = 0;
            noninitial_fragment_reg[index]._next = 0;
        }
        source_port_reg._next = 0;
        destination_port_reg._next = 0;
        tcp_header_bytes_reg._next = 0;
    }

    static bool progress_inactive(PacketParserProgress progress)
    {
        return (uint8_t)progress.state == PACKET_HEADER_NONE
            && !(bool)progress.error && !(bool)progress.limit
            && !(bool)progress.done;
    }

    static PacketParserProgress accept_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        PacketParserProgress result;
        result = current;
        if (progress_inactive(current)) result = upstream;
        else {
            if ((bool)upstream.error) result.error = 1;
            if ((bool)upstream.limit) result.limit = 1;
            if ((bool)upstream.done) result.done = 1;
        }
        return result;
    }

    static PacketParserProgress accept_vlan_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if ((bool)current.error || (bool)current.limit || (bool)current.done)
            return current;
        if (state == PACKET_HEADER_VLAN || state == PACKET_HEADER_MPLS
            || state == PACKET_HEADER_IPV4
            || state == PACKET_HEADER_IPV4_OPTIONS
            || state == PACKET_HEADER_IPV6
            || state == PACKET_HEADER_IPV6_OPTIONS
            || state == PACKET_HEADER_TCP || state == PACKET_HEADER_UDP)
            return current;
        return upstream;
    }

    static PacketParserProgress accept_mpls_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if ((bool)current.error || (bool)current.limit || (bool)current.done)
            return current;
        if (state == PACKET_HEADER_MPLS || state == PACKET_HEADER_IPV4
            || state == PACKET_HEADER_IPV4_OPTIONS
            || state == PACKET_HEADER_IPV6
            || state == PACKET_HEADER_IPV6_OPTIONS
            || state == PACKET_HEADER_TCP || state == PACKET_HEADER_UDP)
            return current;
        return upstream;
    }

    static PacketParserProgress accept_ipv4_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if ((bool)current.error || (bool)current.limit || (bool)current.done)
            return current;
        if (state == PACKET_HEADER_IPV4
            || state == PACKET_HEADER_IPV4_OPTIONS
            || state == PACKET_HEADER_TCP || state == PACKET_HEADER_UDP)
            return current;
        return upstream;
    }

    static PacketParserProgress accept_ipv6_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if ((bool)current.error || (bool)current.limit || (bool)current.done)
            return current;
        if (state == PACKET_HEADER_IPV6
            || state == PACKET_HEADER_IPV6_OPTIONS
            || state == PACKET_HEADER_TCP || state == PACKET_HEADER_UDP)
            return current;
        return upstream;
    }

    static PacketParserProgress accept_ipv4_options_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if ((bool)current.error || (bool)current.limit || (bool)current.done)
            return current;
        if ((state & PACKET_HEADER_IPV4_OPTIONS) != 0
            || (state & PACKET_HEADER_TCP) != 0
            || (state & PACKET_HEADER_UDP) != 0)
            return current;
        return upstream;
    }

    static PacketParserProgress accept_ipv6_ext_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if ((bool)current.error || (bool)current.limit || (bool)current.done)
            return current;
        if (state == PACKET_HEADER_IPV6_OPTIONS
            || state == PACKET_HEADER_TCP || state == PACKET_HEADER_UDP)
            return current;
        return upstream;
    }

    static PacketParserProgress accept_transport_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if ((bool)current.error || (bool)current.limit || (bool)current.done)
            return current;
        if (state == PACKET_HEADER_TCP || state == PACKET_HEADER_UDP)
            return current;
        return upstream;
    }

    static PacketParserProgress accept_tcp_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        if ((bool)current.error || (bool)current.limit || (bool)current.done
            || (uint8_t)current.state == PACKET_HEADER_TCP)
            return current;
        return upstream;
    }

    static PacketParserProgress accept_udp_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        if ((bool)current.error || (bool)current.limit || (bool)current.done
            || (uint8_t)current.state == PACKET_HEADER_UDP)
            return current;
        return upstream;
    }

    PacketParserCall vlan_work(uint8_t occurrence,
        uint8_t markup_pos,
        const logic<MARKUP_BITS>& markup_state,
        PacketParserProgress progress, const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint16_t selector;
        PacketParserCall call;
        call.markup_state = markup_state;
        call.progress = progress;
        if (!header_active(markup_pos, markup_state, PACKET_HEADER_VLAN,
                progress))
            return call;
#if PACKET_PARSER_ENABLE_VLAN
        if (occurrence < PACKET_PARSER_OUTPUT_VLAN_HEADERS)
            vlan_tci_reg[occurrence]._next = capture_be16(word,
                vlan_tci_reg[occurrence]._next, markup_pos,
                word_cntr, word_bytes);
#endif
        vlan_next_proto_reg[occurrence]._next = capture_be16(word,
            vlan_next_proto_reg[occurrence]._next,
            (uint8_t)(markup_pos + 2),
            word_cntr, word_bytes);
        if (field_complete((uint8_t)(markup_pos + 2), 2,
            word_cntr, word_bytes)) {
            selector = (uint16_t)vlan_next_proto_reg[occurrence]._next;
            if (occurrence + 1 == PACKET_PARSER_MAX_VLAN_HEADERS
                && is_vlan(selector)) {
                call.progress.state = PACKET_HEADER_NONE;
                call.progress.limit = 1;
                call.progress.done = 1;
            }
            else {
                call.progress.pos = u8(markup_pos + 4);
                call.progress.state = select_l3(selector);
                if ((uint8_t)call.progress.state == PACKET_HEADER_NONE)
                    call.progress.error = 1;
            }
        }
        return call;
    }

    PacketParserCall mpls_work(uint8_t occurrence,
        uint8_t markup_pos,
        const logic<MARKUP_BITS>& markup_state,
        PacketParserProgress progress, const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint32_t entry;
        uint8_t version;
        PacketParserCall call;
        call.markup_state = markup_state;
        call.progress = progress;
        if (!header_active(markup_pos, markup_state, PACKET_HEADER_MPLS,
                progress))
            return call;
        if (!(bool)mpls_entry_done_reg[occurrence]._next) {
            mpls_entry_reg[occurrence]._next = capture_be32(word,
                mpls_entry_reg[occurrence]._next, markup_pos,
                word_cntr, word_bytes);
            if (field_complete(markup_pos, 4, word_cntr, word_bytes))
                mpls_entry_done_reg[occurrence]._next = 1;
        }
        if (!(bool)mpls_entry_done_reg[occurrence]._next) return call;
        entry = (uint32_t)mpls_entry_reg[occurrence]._next;
#if PACKET_PARSER_ENABLE_MPLS
        if (occurrence < PACKET_PARSER_OUTPUT_MPLS_LABELS)
            mpls_output_reg[occurrence]._next = u32(entry);
#endif
        if ((entry & 0x100) == 0) {
            if (occurrence + 1 == PACKET_PARSER_MAX_MPLS_LABELS) {
                call.progress.state = PACKET_HEADER_NONE;
                call.progress.limit = 1;
                call.progress.done = 1;
            }
            else {
                call.progress.state = PACKET_HEADER_MPLS;
                call.progress.pos = u8(markup_pos + 4);
            }
        }
        else if (byte_present((uint8_t)(markup_pos + 4),
            word_cntr, word_bytes)) {
            version = word_byte(word, (uint8_t)(markup_pos + 4),
                word_cntr) >> 4;
            call.progress.pos = u8(markup_pos + 4);
            if (version == 4) call.progress.state = PACKET_HEADER_IPV4;
            else if (version == 6) call.progress.state = PACKET_HEADER_IPV6;
            else {
                call.progress.state = PACKET_HEADER_NONE;
                call.progress.error = 1;
            }
        }
        return call;
    }

#define PACKET_PARSER_DEFINE_VLAN_WORK(NAME, INDEX, LAST) \
    PacketParserCall NAME(uint8_t markup_pos, \
        const logic<MARKUP_BITS>& markup_state, \
        PacketParserProgress progress, const logic<320>& word, \
        uint8_t word_bytes, uint8_t word_cntr, \
        const logic<32>& decoded, const logic<4>& decoded_valid) \
    { \
        uint16_t selector; \
        uint16_t tci; \
        PacketParserCall call; \
        call.markup_state = markup_state; \
        call.progress = progress; \
        if (!header_active(markup_pos, markup_state, PACKET_HEADER_VLAN, \
                progress)) \
            return call; \
        tci = (uint16_t)vlan_tci_reg[INDEX]._next; \
        if ((bool)decoded_valid[0]) \
            tci = (tci & 0x00ff) \
                | ((uint16_t)(uint8_t)decoded.bits(7, 0) << 8); \
        if ((bool)decoded_valid[1]) \
            tci = (tci & 0xff00) | (uint8_t)decoded.bits(15, 8); \
        if (INDEX < PACKET_PARSER_OUTPUT_VLAN_HEADERS) \
            vlan_tci_reg[INDEX]._next = u16(tci); \
        selector = (uint16_t)vlan_next_proto_reg[INDEX]._next; \
        if ((bool)decoded_valid[2]) \
            selector = (selector & 0x00ff) \
                | ((uint16_t)(uint8_t)decoded.bits(23, 16) << 8); \
        if ((bool)decoded_valid[3]) \
            selector = (selector & 0xff00) \
                | (uint8_t)decoded.bits(31, 24); \
        vlan_next_proto_reg[INDEX]._next = u16(selector); \
        if ((bool)decoded_valid[3]) { \
            if (LAST && is_vlan(selector)) { \
                call.progress.state = PACKET_HEADER_NONE; \
                call.progress.limit = 1; \
                call.progress.done = 1; \
            } \
            else { \
                call.progress.pos = u8(markup_pos + 4); \
                call.progress.state = select_l3(selector); \
                if ((uint8_t)call.progress.state == PACKET_HEADER_NONE) \
                    call.progress.error = 1; \
            } \
        } \
        return call; \
    }

    PACKET_PARSER_DEFINE_VLAN_WORK(vlan_work1, 0, 0)
    PACKET_PARSER_DEFINE_VLAN_WORK(vlan_work2, 1, 0)
    PACKET_PARSER_DEFINE_VLAN_WORK(vlan_work3, 2, 0)
    PACKET_PARSER_DEFINE_VLAN_WORK(vlan_work4, 3, 1)

#undef PACKET_PARSER_DEFINE_VLAN_WORK

#define PACKET_PARSER_DEFINE_MPLS_WORK(NAME, INDEX, LAST) \
    PacketParserCall NAME(uint8_t markup_pos, \
        const logic<MARKUP_BITS>& markup_state, \
        PacketParserProgress progress, const logic<320>& word, \
        uint8_t word_bytes, uint8_t word_cntr, \
        const logic<40>& decoded, const logic<5>& decoded_valid) \
    { \
        uint32_t entry; \
        uint8_t version; \
        PacketParserCall call; \
        call.markup_state = markup_state; \
        call.progress = progress; \
        if (!header_active(markup_pos, markup_state, PACKET_HEADER_MPLS, \
                progress)) \
            return call; \
        if (!(bool)mpls_entry_done_reg[INDEX]._next) { \
            entry = (uint32_t)mpls_entry_reg[INDEX]._next; \
            if ((bool)decoded_valid[0]) \
                entry = (entry & 0x00ffffff) \
                    | ((uint32_t)(uint8_t)decoded.bits(7, 0) << 24); \
            if ((bool)decoded_valid[1]) \
                entry = (entry & 0xff00ffff) \
                    | ((uint32_t)(uint8_t)decoded.bits(15, 8) << 16); \
            if ((bool)decoded_valid[2]) \
                entry = (entry & 0xffff00ff) \
                    | ((uint32_t)(uint8_t)decoded.bits(23, 16) << 8); \
            if ((bool)decoded_valid[3]) \
                entry = (entry & 0xffffff00) \
                    | (uint8_t)decoded.bits(31, 24); \
            mpls_entry_reg[INDEX]._next = u32(entry); \
            if ((bool)decoded_valid[3]) \
                mpls_entry_done_reg[INDEX]._next = 1; \
        } \
        if (!(bool)mpls_entry_done_reg[INDEX]._next) return call; \
        entry = (uint32_t)mpls_entry_reg[INDEX]._next; \
        if (INDEX < PACKET_PARSER_OUTPUT_MPLS_LABELS) \
            mpls_output_reg[INDEX]._next = u32(entry); \
        if ((entry & 0x100) == 0) { \
            if (LAST) { \
                call.progress.state = PACKET_HEADER_NONE; \
                call.progress.limit = 1; \
                call.progress.done = 1; \
            } \
            else { \
                call.progress.state = PACKET_HEADER_MPLS; \
                call.progress.pos = u8(markup_pos + 4); \
            } \
        } \
        else if ((bool)decoded_valid[4]) { \
            version = (uint8_t)decoded.bits(39, 32) >> 4; \
            call.progress.pos = u8(markup_pos + 4); \
            if (version == 4) call.progress.state = PACKET_HEADER_IPV4; \
            else if (version == 6) call.progress.state = PACKET_HEADER_IPV6; \
            else { \
                call.progress.state = PACKET_HEADER_NONE; \
                call.progress.error = 1; \
            } \
        } \
        return call; \
    }

    PACKET_PARSER_DEFINE_MPLS_WORK(mpls_work1, 0, 0)
    PACKET_PARSER_DEFINE_MPLS_WORK(mpls_work2, 1, 0)
    PACKET_PARSER_DEFINE_MPLS_WORK(mpls_work3, 2, 0)
    PACKET_PARSER_DEFINE_MPLS_WORK(mpls_work4, 3, 1)

#undef PACKET_PARSER_DEFINE_MPLS_WORK

    PacketParserCall parse_tcp(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<40>& decoded, const logic<5>& decoded_valid)
    {
        uint8_t header_bytes;
        uint16_t source_port;
        uint16_t destination_port;
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_TCP);
        call.markup_state = marked_state;
        call.progress = progress;
        if (!header_active(markup_pos, marked_state, PACKET_HEADER_TCP,
                progress))
            return call;
        source_port = (uint16_t)source_port_reg._next;
        destination_port = (uint16_t)destination_port_reg._next;
        if ((bool)decoded_valid[0])
            source_port = (source_port & 0x00ff)
                | ((uint16_t)(uint8_t)decoded.bits(7, 0) << 8);
        if ((bool)decoded_valid[1])
            source_port = (source_port & 0xff00)
                | (uint8_t)decoded.bits(15, 8);
        if ((bool)decoded_valid[2])
            destination_port = (destination_port & 0x00ff)
                | ((uint16_t)(uint8_t)decoded.bits(23, 16) << 8);
        if ((bool)decoded_valid[3])
            destination_port = (destination_port & 0xff00)
                | (uint8_t)decoded.bits(31, 24);
        source_port_reg._next = u16(source_port);
        destination_port_reg._next = u16(destination_port);
        if ((bool)decoded_valid[4]) {
            header_bytes = ((uint8_t)decoded.bits(39, 32) >> 4) * 4;
            tcp_header_bytes_reg._next = u8(header_bytes);
            if (header_bytes < 20
                || header_bytes - 20 > PACKET_PARSER_MAX_TCP_OPTION_BYTES)
                call.progress.error = 1;
        }
        header_bytes = (uint8_t)tcp_header_bytes_reg._next;
        if (header_bytes != 0 && field_complete(markup_pos, header_bytes,
            word_cntr, word_bytes)) {
            call.progress.state = PACKET_HEADER_NONE;
            call.progress.done = 1;
        }
        return call;
    }

    PacketParserCall parse_udp(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<40>& decoded, const logic<5>& decoded_valid)
    {
        uint16_t source_port;
        uint16_t destination_port;
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_UDP);
        call.markup_state = marked_state;
        call.progress = progress;
        if (!header_active(markup_pos, marked_state, PACKET_HEADER_UDP,
                progress))
            return call;
        source_port = (uint16_t)source_port_reg._next;
        destination_port = (uint16_t)destination_port_reg._next;
        if ((bool)decoded_valid[0])
            source_port = (source_port & 0x00ff)
                | ((uint16_t)(uint8_t)decoded.bits(7, 0) << 8);
        if ((bool)decoded_valid[1])
            source_port = (source_port & 0xff00)
                | (uint8_t)decoded.bits(15, 8);
        if ((bool)decoded_valid[2])
            destination_port = (destination_port & 0x00ff)
                | ((uint16_t)(uint8_t)decoded.bits(23, 16) << 8);
        if ((bool)decoded_valid[3])
            destination_port = (destination_port & 0xff00)
                | (uint8_t)decoded.bits(31, 24);
        source_port_reg._next = u16(source_port);
        destination_port_reg._next = u16(destination_port);
        if (field_complete(markup_pos, 8, word_cntr, word_bytes)) {
            call.progress.state = PACKET_HEADER_NONE;
            call.progress.done = 1;
        }
        return call;
    }

    PacketParserCall parse_ipv4_options(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint8_t transport_pos;
        uint8_t option_bytes;
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV4_OPTIONS);
        transport_pos = (uint8_t)transport_pos_reg._next;
        option_bytes = transport_pos - markup_pos;
        call.markup_state = marked_state;
        call.progress = progress;
        if (header_active(markup_pos, marked_state,
                PACKET_HEADER_IPV4_OPTIONS, progress)
            && option_bytes != 0
            && field_complete(markup_pos, option_bytes, word_cntr, word_bytes)) {
            call.progress.pos = u8(transport_pos);
            call.progress.state = select_transport(
                (uint8_t)protocol_reg._next);
            if ((uint8_t)call.progress.state == PACKET_HEADER_NONE)
                call.progress.done = 1;
        }
        return call;
    }

    PacketParserCall parse_ipv4(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint8_t first;
        uint8_t header_bytes;
        uint16_t fragment;
        u32 address;
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_IPV4);
        call.markup_state = marked_state;
        call.progress = progress;
        if (header_active(markup_pos, marked_state, PACKET_HEADER_IPV4,
                progress)) {
            if (byte_present(markup_pos, word_cntr, word_bytes)) {
                first = word_byte(word, markup_pos, word_cntr);
                header_bytes = (first & 0xf) * 4;
                ip_version_reg._next = 4;
                ip_header_bytes_reg._next = u8(header_bytes);
                transport_pos_reg._next = u8(markup_pos + header_bytes);
                if ((first >> 4) != 4 || header_bytes < 20)
                    call.progress.error = 1;
                else if (header_bytes - 20 > PACKET_PARSER_MAX_IPV4_OPTION_BYTES)
                    call.progress.limit = 1;
            }
            ipv4_fragment_reg._next = capture_be16(word,
                ipv4_fragment_reg._next, (uint8_t)(markup_pos + 6),
                word_cntr, word_bytes);
            if (field_complete((uint8_t)(markup_pos + 6), 2,
                word_cntr, word_bytes)) {
                fragment = (uint16_t)ipv4_fragment_reg._next;
                initial_fragment_reg._next = (fragment & 0x1fff) == 0;
            }
            protocol_reg._next = capture_u8(word,
                protocol_reg._next, (uint8_t)(markup_pos + 9),
                word_cntr, word_bytes);
            address = u32((uint32_t)source_ip_reg._next);
            source_ip_reg._next.bits(31, 0) = capture_be32(word,
                address, (uint8_t)(markup_pos + 12), word_cntr, word_bytes);
            address = u32((uint32_t)destination_ip_reg._next);
            destination_ip_reg._next.bits(31, 0) = capture_be32(word,
                address, (uint8_t)(markup_pos + 16), word_cntr, word_bytes);
            header_bytes = (uint8_t)ip_header_bytes_reg._next;
            if (header_bytes >= 20
                && field_complete(markup_pos, 20, word_cntr, word_bytes)) {
                if (!(bool)initial_fragment_reg._next) {
                    call.progress.state = PACKET_HEADER_NONE;
                    call.progress.done = 1;
                }
                else if (header_bytes == 20) {
                    call.progress.pos = u8(markup_pos + 20);
                    call.progress.state = select_transport(
                        (uint8_t)protocol_reg._next);
                    if ((uint8_t)call.progress.state == PACKET_HEADER_NONE)
                        call.progress.done = 1;
                }
                else {
                    call.progress.state = PACKET_HEADER_IPV4_OPTIONS;
                    call.progress.pos = u8(markup_pos + 20);
                }
            }
        }
        return call;
    }

#define PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(NAME, INDEX, LAST) \
    PacketParserCall NAME(uint8_t markup_pos, \
        const logic<MARKUP_BITS>& markup_state, \
        PacketParserProgress progress, const logic<320>& word, \
        uint8_t word_bytes, uint8_t word_cntr, \
        const logic<32>& decoded, const logic<4>& decoded_valid, \
        uint8_t decoded_size, uint8_t decoded_next_pos, \
        bool size_known, bool header_complete, bool decoded_limit) \
    { \
        uint8_t selector; \
        uint16_t fragment; \
        PacketParserCall call; \
        call.markup_state = markup_state; \
        call.progress = progress; \
        selector = (uint8_t)ipv6_next_proto_reg[INDEX]._next; \
        if ((bool)decoded_valid[0]) \
            ipv6_next_proto_reg[INDEX]._next = \
                u8((uint8_t)decoded.bits(7, 0)); \
        if (size_known) { \
            ipv6_ext_size_reg[INDEX]._next = u8(decoded_size); \
            if (decoded_limit) call.progress.limit = 1; \
        } \
        if (selector == 44) { \
            fragment = (uint16_t)ipv6_fragment_reg[INDEX]._next; \
            if ((bool)decoded_valid[2]) \
                fragment = (fragment & 0x00ff) \
                    | ((uint16_t)(uint8_t)decoded.bits(23, 16) << 8); \
            if ((bool)decoded_valid[3]) \
                fragment = (fragment & 0xff00) \
                    | (uint8_t)decoded.bits(31, 24); \
            ipv6_fragment_reg[INDEX]._next = u16(fragment); \
            if ((bool)decoded_valid[3]) { \
                if ((fragment & 0xfff8) != 0) \
                    noninitial_fragment_reg[INDEX]._next = 1; \
            } \
        } \
        if (header_complete) { \
            selector = (uint8_t)ipv6_next_proto_reg[INDEX]._next; \
            if ((bool)noninitial_fragment_reg[INDEX]._next) { \
                call.progress.state = PACKET_HEADER_NONE; \
                call.progress.done = 1; \
            } \
            else if (is_ipv6_extension(selector)) { \
                if (LAST) { \
                    call.progress.state = PACKET_HEADER_NONE; \
                    call.progress.limit = 1; \
                    call.progress.done = 1; \
                } \
                else { \
                    call.progress.state = PACKET_HEADER_IPV6_OPTIONS; \
                    call.progress.pos = u8(decoded_next_pos); \
                } \
            } \
            else { \
                call.progress.pos = u8(decoded_next_pos); \
                call.progress.state = select_transport(selector); \
                if ((uint8_t)call.progress.state == PACKET_HEADER_NONE) \
                    call.progress.done = 1; \
            } \
        } \
        return call; \
    }

    PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(ipv6_options_work1, 0, 0)
    PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(ipv6_options_work2, 1, 0)
    PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(ipv6_options_work3, 2, 0)
    PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(ipv6_options_work4, 3, 0)
    PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(ipv6_options_work5, 4, 0)
    PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(ipv6_options_work6, 5, 0)
    PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(ipv6_options_work7, 6, 0)
    PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK(ipv6_options_work8, 7, 1)

#undef PACKET_PARSER_DEFINE_IPV6_OPTIONS_WORK

    PacketParserCall parse_ipv6_options8(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid,
        uint8_t decoded_size, uint8_t decoded_next_pos,
        bool size_known, bool header_complete, bool decoded_limit)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work8(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid,
            decoded_size, decoded_next_pos, size_known, header_complete,
            decoded_limit);
        return call;
    }

    PacketParserCall parse_ipv6_options7(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid,
        uint8_t decoded_size, uint8_t decoded_next_pos,
        bool size_known, bool header_complete, bool decoded_limit)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work7(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid,
            decoded_size, decoded_next_pos, size_known, header_complete,
            decoded_limit);
        return call;
    }

    PacketParserCall parse_ipv6_options6(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid,
        uint8_t decoded_size, uint8_t decoded_next_pos,
        bool size_known, bool header_complete, bool decoded_limit)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work6(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid,
            decoded_size, decoded_next_pos, size_known, header_complete,
            decoded_limit);
        return call;
    }

    PacketParserCall parse_ipv6_options5(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid,
        uint8_t decoded_size, uint8_t decoded_next_pos,
        bool size_known, bool header_complete, bool decoded_limit)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work5(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid,
            decoded_size, decoded_next_pos, size_known, header_complete,
            decoded_limit);
        return call;
    }


    PacketParserCall parse_ipv6_options4(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid,
        uint8_t decoded_size, uint8_t decoded_next_pos,
        bool size_known, bool header_complete, bool decoded_limit)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work4(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid,
            decoded_size, decoded_next_pos, size_known, header_complete,
            decoded_limit);
        return call;
    }

    PacketParserCall parse_ipv6_options3(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid,
        uint8_t decoded_size, uint8_t decoded_next_pos,
        bool size_known, bool header_complete, bool decoded_limit)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work3(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid,
            decoded_size, decoded_next_pos, size_known, header_complete,
            decoded_limit);
        return call;
    }

    PacketParserCall parse_ipv6_options2(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid,
        uint8_t decoded_size, uint8_t decoded_next_pos,
        bool size_known, bool header_complete, bool decoded_limit)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work2(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid,
            decoded_size, decoded_next_pos, size_known, header_complete,
            decoded_limit);
        return call;
    }

    PacketParserCall parse_ipv6_options1(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid,
        uint8_t decoded_size, uint8_t decoded_next_pos,
        bool size_known, bool header_complete, bool decoded_limit)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work1(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid,
            decoded_size, decoded_next_pos, size_known, header_complete,
            decoded_limit);
        return call;
    }

    PacketParserCall parse_ipv6(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint8_t first;
        uint8_t selector;
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_IPV6);
        call.markup_state = marked_state;
        call.progress = progress;
        if (header_active(markup_pos, marked_state, PACKET_HEADER_IPV6,
                progress)) {
            if (byte_present(markup_pos, word_cntr, word_bytes)) {
                first = word_byte(word, markup_pos, word_cntr);
                ipv6_seen_reg._next = 1;
                if ((first >> 4) != 6) call.progress.error = 1;
            }
            ipv6_base_next_proto_reg._next = capture_u8(word,
                ipv6_base_next_proto_reg._next, (uint8_t)(markup_pos + 6),
                word_cntr, word_bytes);
            ipv6_source_ip_reg._next = capture_be128(word,
                ipv6_source_ip_reg._next, (uint8_t)(markup_pos + 8),
                word_cntr, word_bytes);
            ipv6_destination_ip_reg._next = capture_be128(word,
                ipv6_destination_ip_reg._next, (uint8_t)(markup_pos + 24),
                word_cntr, word_bytes);
            if (field_complete(markup_pos, 40, word_cntr, word_bytes)) {
                selector = (uint8_t)ipv6_base_next_proto_reg._next;
                if (is_ipv6_extension(selector)) {
                    call.progress.state = PACKET_HEADER_IPV6_OPTIONS;
                    call.progress.pos = u8(markup_pos + 40);
                }
                else {
                    call.progress.pos = u8(markup_pos + 40);
                    call.progress.state = select_transport(selector);
                    if ((uint8_t)call.progress.state == PACKET_HEADER_NONE)
                        call.progress.done = 1;
                }
            }
        }
        return call;
    }

    PacketParserCall parse_mpls4(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<40>& decoded, const logic<5>& decoded_valid)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_MPLS);
        call = mpls_work4(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid);
        return call;
    }

    PacketParserCall parse_mpls3(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<40>& decoded, const logic<5>& decoded_valid)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_MPLS);
        call = mpls_work3(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid);
        return call;
    }

    PacketParserCall parse_mpls2(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<40>& decoded, const logic<5>& decoded_valid)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_MPLS);
        call = mpls_work2(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid);
        return call;
    }

    PacketParserCall parse_mpls1(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<40>& decoded, const logic<5>& decoded_valid)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_MPLS);
        call = mpls_work1(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid);
        return call;
    }

    PacketParserCall parse_vlan4(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_VLAN);
        call = vlan_work4(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid);
        return call;
    }

    PacketParserCall parse_vlan3(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_VLAN);
        call = vlan_work3(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid);
        return call;
    }

    PacketParserCall parse_vlan2(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_VLAN);
        call = vlan_work2(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid);
        return call;
    }

    PacketParserCall parse_vlan1(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<320>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        const logic<32>& decoded, const logic<4>& decoded_valid)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_VLAN);
        call = vlan_work1(markup_pos, marked_state, progress,
            word, word_bytes, word_cntr, decoded, decoded_valid);
        return call;
    }

    PacketParserCall parse_ethernet(PacketParserProgress progress,
        const logic<320>& word, uint8_t word_bytes, uint8_t word_cntr)
    {
        uint16_t selector;
        PacketParserCall call;
        call.markup_state = 0;
        call.progress = progress;
        if (!(bool)ethernet_done_reg._next) {
            destination_mac_reg._next = capture_be48(word,
                destination_mac_reg._next, 0, word_cntr, word_bytes);
            source_mac_reg._next = capture_be48(word,
                source_mac_reg._next, 6, word_cntr, word_bytes);
            ethernet_type_reg._next = capture_be16(word,
                ethernet_type_reg._next, 12, word_cntr, word_bytes);
            if (field_complete(12, 2, word_cntr, word_bytes)) {
                ethernet_done_reg._next = 1;
                selector = (uint16_t)ethernet_type_reg._next;
                call.progress.pos = 14;
                call.progress.state = select_l3(selector);
                call.markup_state = mark_header(call.markup_state, 14,
                    (uint8_t)call.progress.state);
                if ((uint8_t)call.progress.state == PACKET_HEADER_NONE)
                    call.progress.error = 1;
            }
        }
        return call;
    }

    void hold_parser()
    {
        uint32_t index;
        state_reg._next = state_reg;
        pos_reg._next = pos_reg;
        word_cntr_reg._next = word_cntr_reg;
        ethernet_done_reg._next = ethernet_done_reg;
        error_reg._next = error_reg;
        limit_reg._next = limit_reg;
        done_reg._next = done_reg;
        destination_mac_reg._next = destination_mac_reg;
        source_mac_reg._next = source_mac_reg;
        ethernet_type_reg._next = ethernet_type_reg;
        for (index = 0; index < 4; ++index)
            vlan_next_proto_reg[index]._next = vlan_next_proto_reg[index];
        vlan_count_reg._next = vlan_count_reg;
#if PACKET_PARSER_ENABLE_VLAN
        for (index = 0; index < PACKET_PARSER_OUTPUT_VLAN_HEADERS; ++index)
            vlan_tci_reg[index]._next = vlan_tci_reg[index];
#endif
        for (index = 0; index < 4; ++index) {
            mpls_entry_reg[index]._next = mpls_entry_reg[index];
            mpls_entry_done_reg[index]._next = mpls_entry_done_reg[index];
        }
        mpls_count_reg._next = mpls_count_reg;
#if PACKET_PARSER_ENABLE_MPLS
        for (index = 0; index < PACKET_PARSER_OUTPUT_MPLS_LABELS; ++index)
            mpls_output_reg[index]._next = mpls_output_reg[index];
#endif
        source_ip_reg._next = source_ip_reg;
        destination_ip_reg._next = destination_ip_reg;
        protocol_reg._next = protocol_reg;
        ip_version_reg._next = ip_version_reg;
        ip_header_bytes_reg._next = ip_header_bytes_reg;
        transport_pos_reg._next = transport_pos_reg;
        ipv4_fragment_reg._next = ipv4_fragment_reg;
        initial_fragment_reg._next = initial_fragment_reg;
        ipv6_source_ip_reg._next = ipv6_source_ip_reg;
        ipv6_destination_ip_reg._next = ipv6_destination_ip_reg;
        ipv6_base_next_proto_reg._next = ipv6_base_next_proto_reg;
        ipv6_seen_reg._next = ipv6_seen_reg;
        for (index = 0; index < 8; ++index) {
            ipv6_next_proto_reg[index]._next = ipv6_next_proto_reg[index];
            ipv6_ext_size_reg[index]._next = ipv6_ext_size_reg[index];
            ipv6_ext_extent_size_reg[index]._next =
                ipv6_ext_extent_size_reg[index];
            ipv6_ext_seen_reg[index]._next = ipv6_ext_seen_reg[index];
            ipv6_fragment_reg[index]._next = ipv6_fragment_reg[index];
            noninitial_fragment_reg[index]._next =
                noninitial_fragment_reg[index];
        }
        source_port_reg._next = source_port_reg;
        destination_port_reg._next = destination_port_reg;
        tcp_header_bytes_reg._next = tcp_header_bytes_reg;
    }

    PacketParserPipeWord ingress_bounds_stage(PacketParserPipeWord item)
    {
        uint16_t word_start;
        uint16_t word_last;
        word_start = (uint16_t)(uint8_t)item.word_cntr * LANE_BYTES;
        word_last = word_start + (uint8_t)item.bytes - 1;
        if ((uint8_t)item.bytes != 0 && word_start <= 255) {
            item.word_start = u8(word_start);
            if (word_last > 255) item.word_last = u8(255);
            else item.word_last = u8(word_last);
        }
        else {
            item.word_start = u8(255);
            item.word_last = 0;
        }
        return item;
    }

    PacketParserPipeWord ethernet_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.raw) return result;
        if ((bool)item.sop) {
            ethernet_done_reg._next = 0;
            destination_mac_reg._next = 0;
            source_mac_reg._next = 0;
            ethernet_type_reg._next = 0;
            progress = item.progress;
        }
        else progress = accept_upstream(ethernet_progress_reg, item.progress);
        call = parse_ethernet(progress, item.data,
            (uint8_t)item.word_last, (uint8_t)item.word_start);
        progress = call.progress;
        ethernet_progress_reg._next = progress;
        result.progress = progress;
        if ((bool)item.eop) {
            result.fields.destination_mac = destination_mac_reg._next;
            result.fields.source_mac = source_mac_reg._next;
        }
        return result;
    }

    PacketParserPipeWord vlan_stage(uint8_t occurrence,
        PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        uint8_t prior_pos;
        uint8_t stage_index;
        uint8_t flags;
        uint8_t vlan_count;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.raw) return result;
        if ((bool)item.sop) {
            vlan_next_proto_reg[occurrence]._next = 0;
#if PACKET_PARSER_ENABLE_VLAN
            if (occurrence < PACKET_PARSER_OUTPUT_VLAN_HEADERS)
                vlan_tci_reg[occurrence]._next = 0;
#endif
            progress = item.progress;
            stage_index = (uint8_t)item.vlan_index;
            if (stage_index > occurrence) stage_index = occurrence;
        }
        else {
            progress = vlan_progress_reg[occurrence];
            stage_index = (uint8_t)vlan_stage_index_reg[occurrence];
            if (stage_index < occurrence) {
                progress = item.progress;
                if ((uint8_t)item.vlan_index >= occurrence)
                    stage_index = occurrence;
            }
            else if (stage_index == occurrence)
                progress = accept_vlan_upstream(progress, item.progress);
        }
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        prior_pos = markup_pos;
        if ((uint8_t)progress.state == PACKET_HEADER_VLAN
            && stage_index == occurrence) {
            call.progress = progress;
            call.markup_state = 0;
            if (occurrence == 0)
                call = parse_vlan1(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.word_last,
                    (uint8_t)item.word_start, item.vlan_decode,
                    item.vlan_decode_valid);
            if (occurrence == 1)
                call = parse_vlan2(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.word_last,
                    (uint8_t)item.word_start, item.vlan_decode,
                    item.vlan_decode_valid);
            if (occurrence == 2)
                call = parse_vlan3(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.word_last,
                    (uint8_t)item.word_start, item.vlan_decode,
                    item.vlan_decode_valid);
            if (occurrence == 3)
                call = parse_vlan4(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.word_last,
                    (uint8_t)item.word_start, item.vlan_decode,
                    item.vlan_decode_valid);
            progress = call.progress;
            if ((uint8_t)progress.pos != prior_pos
                || (uint8_t)progress.state != PACKET_HEADER_VLAN
                || (bool)progress.error || (bool)progress.limit
                || (bool)progress.done)
                stage_index = occurrence + 1;
        }
        vlan_progress_reg[occurrence]._next = progress;
        vlan_stage_index_reg[occurrence]._next = u<3>(stage_index);
        result.progress = progress;
        if ((uint8_t)item.vlan_index > stage_index)
            result.vlan_index = item.vlan_index;
        else result.vlan_index = u<3>(stage_index);
        if ((bool)item.eop) {
#if PACKET_PARSER_ENABLE_VLAN
            if (occurrence < PACKET_PARSER_OUTPUT_VLAN_HEADERS)
                result.fields.vlan_tci[occurrence] =
                    vlan_tci_reg[occurrence]._next;
#endif
            if (occurrence == 3) {
                flags = (uint8_t)result.fields.flags;
                vlan_count = (uint8_t)result.vlan_index;
                if (vlan_count != 0) flags |= PACKET_PARSER_FLAG_VLAN;
                result.fields.flags = u8(flags);
                result.fields.ip_meta = u8(
                    ((uint8_t)result.fields.ip_meta & 0xcf)
                    | ((vlan_count > 3 ? 3 : vlan_count) << 4));
            }
        }
        return result;
    }

#define PACKET_PARSER_DEFINE_VLAN_DECODE_STAGE(NAME, INDEX) \
    PacketParserPipeWord NAME(PacketParserPipeWord item) \
    { \
        PacketParserProgress progress; \
        logic<32> decoded; \
        logic<4> decoded_valid; \
        uint8_t markup_pos; \
        decoded = 0; \
        decoded_valid = 0; \
        progress = item.progress; \
        if (!(bool)item.raw && (uint8_t)item.vlan_index >= INDEX \
            && ((uint8_t)progress.state & PACKET_HEADER_VLAN) != 0 \
            && !(bool)progress.error && !(bool)progress.limit \
            && !(bool)progress.done) { \
            markup_pos = (uint8_t)progress.pos; \
            if (byte_present(markup_pos, (uint8_t)item.word_start, \
                    (uint8_t)item.word_last)) { \
                decoded.bits(7, 0) = u8(word_byte(item.data, markup_pos, \
                    (uint8_t)item.word_start)); \
                decoded_valid[0] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 1), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(15, 8) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 1), \
                    (uint8_t)item.word_start)); \
                decoded_valid[1] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 2), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(23, 16) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 2), \
                    (uint8_t)item.word_start)); \
                decoded_valid[2] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 3), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(31, 24) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 3), \
                    (uint8_t)item.word_start)); \
                decoded_valid[3] = 1; \
            } \
        } \
        item.vlan_decode = decoded; \
        item.vlan_decode_valid = decoded_valid; \
        return item; \
    }

    PACKET_PARSER_DEFINE_VLAN_DECODE_STAGE(vlan1_decode_stage, 0)
    PACKET_PARSER_DEFINE_VLAN_DECODE_STAGE(vlan2_decode_stage, 1)
    PACKET_PARSER_DEFINE_VLAN_DECODE_STAGE(vlan3_decode_stage, 2)
    PACKET_PARSER_DEFINE_VLAN_DECODE_STAGE(vlan4_decode_stage, 3)

#undef PACKET_PARSER_DEFINE_VLAN_DECODE_STAGE

#define PACKET_PARSER_DEFINE_VLAN_STAGE(NAME, INDEX, PARSE, LAST) \
    PacketParserPipeWord NAME(PacketParserPipeWord item) \
    { \
        PacketParserPipeWord result; \
        uint8_t markup_pos; \
        uint8_t prior_pos; \
        uint8_t stage_index; \
        uint8_t flags; \
        uint8_t vlan_count; \
        logic<MARKUP_BITS> markup_state; \
        PacketParserCall call; \
        PacketParserProgress progress; \
        result = item; \
        if ((bool)item.raw) return result; \
        if ((bool)item.sop) { \
            vlan_next_proto_reg[INDEX]._next = 0; \
            if (INDEX < PACKET_PARSER_OUTPUT_VLAN_HEADERS) \
                vlan_tci_reg[INDEX]._next = 0; \
            progress = item.progress; \
            stage_index = (uint8_t)item.vlan_index; \
            if (stage_index > INDEX) stage_index = INDEX; \
        } \
        else { \
            progress = vlan_progress_reg[INDEX]; \
            stage_index = (uint8_t)vlan_stage_index_reg[INDEX]; \
            if (stage_index < INDEX) { \
                progress = item.progress; \
                if ((uint8_t)item.vlan_index >= INDEX) \
                    stage_index = INDEX; \
            } \
            else if (stage_index == INDEX) \
                progress = accept_vlan_upstream(progress, item.progress); \
        } \
        markup_state = 0; \
        markup_pos = (uint8_t)progress.pos; \
        prior_pos = markup_pos; \
        if (((uint8_t)progress.state & PACKET_HEADER_VLAN) != 0 \
            && stage_index == INDEX) { \
            call = PARSE(markup_pos, markup_state, progress, item.data, \
                (uint8_t)item.word_last, (uint8_t)item.word_start, \
                item.vlan_decode, item.vlan_decode_valid); \
            progress = call.progress; \
            if ((uint8_t)progress.pos != prior_pos \
                || ((uint8_t)progress.state & PACKET_HEADER_VLAN) == 0 \
                || (bool)progress.error || (bool)progress.limit \
                || (bool)progress.done) \
                stage_index = INDEX + 1; \
        } \
        vlan_progress_reg[INDEX]._next = progress; \
        vlan_stage_index_reg[INDEX]._next = u<3>(stage_index); \
        result.progress = progress; \
        if ((uint8_t)item.vlan_index > stage_index) \
            result.vlan_index = item.vlan_index; \
        else result.vlan_index = u<3>(stage_index); \
        if ((bool)item.eop) { \
            if (INDEX < PACKET_PARSER_OUTPUT_VLAN_HEADERS) \
                result.fields.vlan_tci[INDEX] = vlan_tci_reg[INDEX]._next; \
            if (LAST) { \
                flags = (uint8_t)result.fields.flags; \
                vlan_count = (uint8_t)result.vlan_index; \
                if (vlan_count != 0) flags |= PACKET_PARSER_FLAG_VLAN; \
                result.fields.flags = u8(flags); \
                result.fields.ip_meta = u8( \
                    ((uint8_t)result.fields.ip_meta & 0xcf) \
                    | ((vlan_count > 3 ? 3 : vlan_count) << 4)); \
            } \
        } \
        return result; \
    }

    PACKET_PARSER_DEFINE_VLAN_STAGE(vlan1_stage, 0, parse_vlan1, 0)
    PACKET_PARSER_DEFINE_VLAN_STAGE(vlan2_stage, 1, parse_vlan2, 0)
    PACKET_PARSER_DEFINE_VLAN_STAGE(vlan3_stage, 2, parse_vlan3, 0)
    PACKET_PARSER_DEFINE_VLAN_STAGE(vlan4_stage, 3, parse_vlan4, 1)

#undef PACKET_PARSER_DEFINE_VLAN_STAGE

#define PACKET_PARSER_DEFINE_MPLS_DECODE_STAGE(NAME, INDEX) \
    PacketParserPipeWord NAME(PacketParserPipeWord item) \
    { \
        PacketParserPipeWord result; \
        PacketParserProgress progress; \
        logic<40> decoded; \
        logic<5> decoded_valid; \
        uint8_t markup_pos; \
        result = item; \
        decoded = 0; \
        decoded_valid = 0; \
        progress = item.progress; \
        if (!(bool)item.raw && (uint8_t)item.mpls_index >= INDEX \
            && ((uint8_t)progress.state & PACKET_HEADER_MPLS) != 0 \
            && !(bool)progress.error && !(bool)progress.limit \
            && !(bool)progress.done) { \
            markup_pos = (uint8_t)progress.pos; \
            if (byte_present(markup_pos, (uint8_t)item.word_start, \
                    (uint8_t)item.word_last)) { \
                decoded.bits(7, 0) = u8(word_byte(item.data, markup_pos, \
                    (uint8_t)item.word_start)); \
                decoded_valid[0] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 1), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(15, 8) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 1), \
                    (uint8_t)item.word_start)); \
                decoded_valid[1] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 2), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(23, 16) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 2), \
                    (uint8_t)item.word_start)); \
                decoded_valid[2] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 3), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(31, 24) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 3), \
                    (uint8_t)item.word_start)); \
                decoded_valid[3] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 4), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(39, 32) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 4), \
                    (uint8_t)item.word_start)); \
                decoded_valid[4] = 1; \
            } \
        } \
        result.mpls_decode = decoded; \
        result.mpls_decode_valid = decoded_valid; \
        return result; \
    }

    PACKET_PARSER_DEFINE_MPLS_DECODE_STAGE(mpls1_decode_stage, 0)
    PACKET_PARSER_DEFINE_MPLS_DECODE_STAGE(mpls2_decode_stage, 1)
    PACKET_PARSER_DEFINE_MPLS_DECODE_STAGE(mpls3_decode_stage, 2)
    PACKET_PARSER_DEFINE_MPLS_DECODE_STAGE(mpls4_decode_stage, 3)

#undef PACKET_PARSER_DEFINE_MPLS_DECODE_STAGE

    PacketParserPipeWord mpls_stage(uint8_t occurrence,
        PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        uint8_t prior_pos;
        uint8_t stage_index;
        uint8_t flags;
        uint8_t mpls_count;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.raw) return result;
        if ((bool)item.sop) {
            mpls_entry_reg[occurrence]._next = 0;
            mpls_entry_done_reg[occurrence]._next = 0;
#if PACKET_PARSER_ENABLE_MPLS
            if (occurrence < PACKET_PARSER_OUTPUT_MPLS_LABELS)
                mpls_output_reg[occurrence]._next = 0;
#endif
            progress = item.progress;
            stage_index = (uint8_t)item.mpls_index;
            if (stage_index > occurrence) stage_index = occurrence;
        }
        else {
            progress = mpls_progress_reg[occurrence];
            stage_index = (uint8_t)mpls_stage_index_reg[occurrence];
            if (stage_index < occurrence) {
                progress = item.progress;
                if ((uint8_t)item.mpls_index >= occurrence)
                    stage_index = occurrence;
            }
            else if (stage_index == occurrence)
                progress = accept_mpls_upstream(progress, item.progress);
        }
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        prior_pos = markup_pos;
        if ((uint8_t)progress.state == PACKET_HEADER_MPLS
            && stage_index == occurrence) {
            call.progress = progress;
            call.markup_state = 0;
            if (occurrence == 0)
                call = parse_mpls1(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.word_last,
                    (uint8_t)item.word_start, item.mpls_decode,
                    item.mpls_decode_valid);
            if (occurrence == 1)
                call = parse_mpls2(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.word_last,
                    (uint8_t)item.word_start, item.mpls_decode,
                    item.mpls_decode_valid);
            if (occurrence == 2)
                call = parse_mpls3(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.word_last,
                    (uint8_t)item.word_start, item.mpls_decode,
                    item.mpls_decode_valid);
            if (occurrence == 3)
                call = parse_mpls4(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.word_last,
                    (uint8_t)item.word_start, item.mpls_decode,
                    item.mpls_decode_valid);
            progress = call.progress;
            if ((uint8_t)progress.pos != prior_pos
                || (uint8_t)progress.state != PACKET_HEADER_MPLS
                || (bool)progress.error || (bool)progress.limit
                || (bool)progress.done)
                stage_index = occurrence + 1;
        }
        mpls_progress_reg[occurrence]._next = progress;
        mpls_stage_index_reg[occurrence]._next = u<3>(stage_index);
        result.progress = progress;
        if ((uint8_t)item.mpls_index > stage_index)
            result.mpls_index = item.mpls_index;
        else result.mpls_index = u<3>(stage_index);
        if ((bool)item.eop) {
#if PACKET_PARSER_ENABLE_MPLS
            if (occurrence < PACKET_PARSER_OUTPUT_MPLS_LABELS)
                result.fields.mpls[occurrence] =
                    mpls_output_reg[occurrence]._next;
#endif
            if (occurrence == 3) {
                flags = (uint8_t)result.fields.flags;
                mpls_count = (uint8_t)result.mpls_index;
                if (mpls_count != 0) flags |= PACKET_PARSER_FLAG_MPLS;
                result.fields.flags = u8(flags);
                result.fields.ip_meta = u8(
                    ((uint8_t)result.fields.ip_meta & 0x3f)
                    | ((mpls_count > 3 ? 3 : mpls_count) << 6));
            }
        }
        return result;
    }

#define PACKET_PARSER_DEFINE_MPLS_STAGE(NAME, INDEX, PARSE, LAST) \
    PacketParserPipeWord NAME(PacketParserPipeWord item) \
    { \
        PacketParserPipeWord result; \
        uint8_t markup_pos; \
        uint8_t prior_pos; \
        uint8_t stage_index; \
        uint8_t flags; \
        uint8_t mpls_count; \
        logic<MARKUP_BITS> markup_state; \
        PacketParserCall call; \
        PacketParserProgress progress; \
        result = item; \
        if ((bool)item.raw) return result; \
        if ((bool)item.sop) { \
            mpls_entry_reg[INDEX]._next = 0; \
            mpls_entry_done_reg[INDEX]._next = 0; \
            if (INDEX < PACKET_PARSER_OUTPUT_MPLS_LABELS) \
                mpls_output_reg[INDEX]._next = 0; \
            progress = item.progress; \
            stage_index = (uint8_t)item.mpls_index; \
            if (stage_index > INDEX) stage_index = INDEX; \
        } \
        else { \
            progress = mpls_progress_reg[INDEX]; \
            stage_index = (uint8_t)mpls_stage_index_reg[INDEX]; \
            if (stage_index < INDEX) { \
                progress = item.progress; \
                if ((uint8_t)item.mpls_index >= INDEX) \
                    stage_index = INDEX; \
            } \
            else if (stage_index == INDEX) \
                progress = accept_mpls_upstream(progress, item.progress); \
        } \
        markup_state = 0; \
        markup_pos = (uint8_t)progress.pos; \
        prior_pos = markup_pos; \
        if (((uint8_t)progress.state & PACKET_HEADER_MPLS) != 0 \
            && stage_index == INDEX) { \
            call = PARSE(markup_pos, markup_state, progress, item.data, \
                (uint8_t)item.word_last, (uint8_t)item.word_start, \
                item.mpls_decode, item.mpls_decode_valid); \
            progress = call.progress; \
            if ((uint8_t)progress.pos != prior_pos \
                || ((uint8_t)progress.state & PACKET_HEADER_MPLS) == 0 \
                || (bool)progress.error || (bool)progress.limit \
                || (bool)progress.done) \
                stage_index = INDEX + 1; \
        } \
        mpls_progress_reg[INDEX]._next = progress; \
        mpls_stage_index_reg[INDEX]._next = u<3>(stage_index); \
        result.progress = progress; \
        if ((uint8_t)item.mpls_index > stage_index) \
            result.mpls_index = item.mpls_index; \
        else result.mpls_index = u<3>(stage_index); \
        if ((bool)item.eop) { \
            if (INDEX < PACKET_PARSER_OUTPUT_MPLS_LABELS) \
                result.fields.mpls[INDEX] = mpls_output_reg[INDEX]._next; \
            if (LAST) { \
                flags = (uint8_t)result.fields.flags; \
                mpls_count = (uint8_t)result.mpls_index; \
                if (mpls_count != 0) flags |= PACKET_PARSER_FLAG_MPLS; \
                result.fields.flags = u8(flags); \
                result.fields.ip_meta = u8( \
                    ((uint8_t)result.fields.ip_meta & 0x3f) \
                    | ((mpls_count > 3 ? 3 : mpls_count) << 6)); \
            } \
        } \
        return result; \
    }

    PACKET_PARSER_DEFINE_MPLS_STAGE(mpls1_stage, 0, parse_mpls1, 0)
    PACKET_PARSER_DEFINE_MPLS_STAGE(mpls2_stage, 1, parse_mpls2, 0)
    PACKET_PARSER_DEFINE_MPLS_STAGE(mpls3_stage, 2, parse_mpls3, 0)
    PACKET_PARSER_DEFINE_MPLS_STAGE(mpls4_stage, 3, parse_mpls4, 1)

#undef PACKET_PARSER_DEFINE_MPLS_STAGE

    PacketParserPipeWord ipv4_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        uint8_t flags;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.raw) return result;
        if ((bool)item.sop) {
            source_ip_reg._next = 0;
            destination_ip_reg._next = 0;
            protocol_reg._next = 0;
            ip_version_reg._next = 0;
            ip_header_bytes_reg._next = 0;
            transport_pos_reg._next = 0;
            ipv4_fragment_reg._next = 0;
            initial_fragment_reg._next = 1;
            progress = item.progress;
        }
        else progress = accept_ipv4_upstream(ipv4_progress_reg,
            item.progress);
        markup_state = 0;

        markup_pos = (uint8_t)progress.pos;
        call = parse_ipv4(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.word_last, (uint8_t)item.word_start);
        progress = call.progress;
        ipv4_progress_reg._next = progress;
        result.progress = progress;
        if ((uint8_t)ip_version_reg._next == 4)
            result.fields.protocol = protocol_reg._next;
        if ((bool)item.eop && (uint8_t)ip_version_reg._next == 4) {
            result.fields.source_ip = source_ip_reg._next;
            result.fields.destination_ip = destination_ip_reg._next;
            result.fields.protocol = protocol_reg._next;
            result.fields.ip_meta = u8(((uint8_t)result.fields.ip_meta & 0xf0)
                | 4);
            flags = (uint8_t)result.fields.flags;
            if (((uint16_t)ipv4_fragment_reg._next & 0x3fff) != 0)
                flags |= PACKET_PARSER_FLAG_FRAGMENT;
            result.fields.flags = u8(flags);
        }
        return result;
    }

    PacketParserPipeWord ipv4_options_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.raw) return result;
        if ((bool)item.sop) progress = item.progress;
        else progress = accept_ipv4_options_upstream(
            ipv4_options_progress_reg, item.progress);
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        call = parse_ipv4_options(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.word_last, (uint8_t)item.word_start);
        progress = call.progress;
        ipv4_options_progress_reg._next = progress;
        result.progress = progress;
        return result;
    }

    PacketParserPipeWord ipv6_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        uint8_t flags;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.raw) return result;
        if ((bool)item.sop) {
            ipv6_source_ip_reg._next = 0;
            ipv6_destination_ip_reg._next = 0;
            ipv6_base_next_proto_reg._next = 0;
            ipv6_seen_reg._next = 0;
            progress = item.progress;
        }
        else progress = accept_ipv6_upstream(ipv6_progress_reg,
            item.progress);
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        call = parse_ipv6(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.word_last, (uint8_t)item.word_start);
        progress = call.progress;
        ipv6_progress_reg._next = progress;
        result.progress = progress;
        if ((bool)ipv6_seen_reg._next)
            result.fields.protocol = ipv6_base_next_proto_reg._next;
        if ((bool)item.eop && (bool)ipv6_seen_reg._next) {
            result.fields.source_ip = ipv6_source_ip_reg._next;
            result.fields.destination_ip = ipv6_destination_ip_reg._next;
            result.fields.ip_meta = u8(((uint8_t)result.fields.ip_meta & 0xf0)
                | 6);
            flags = (uint8_t)result.fields.flags;
            flags |= PACKET_PARSER_FLAG_IPV6;
            result.fields.flags = u8(flags);
        }
        return result;
    }

#define PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(NAME, INDEX) \
    PacketParserPipeWord NAME(PacketParserPipeWord item) \
    { \
        PacketParserPipeWord result; \
        PacketParserProgress progress; \
        logic<32> decoded; \
        logic<4> decoded_valid; \
        uint8_t markup_pos; \
        result = item; \
        decoded = 0; \
        decoded_valid = 0; \
        progress = item.progress; \
        if (!(bool)item.raw \
            && (uint8_t)item.ipv6_ext_index >= INDEX \
            && ((uint8_t)progress.state \
                & PACKET_HEADER_IPV6_OPTIONS) != 0 \
            && !(bool)progress.error && !(bool)progress.limit \
            && !(bool)progress.done) { \
            markup_pos = (uint8_t)progress.pos; \
            if (byte_present(markup_pos, (uint8_t)item.word_start, \
                    (uint8_t)item.word_last)) { \
                decoded.bits(7, 0) = u8(word_byte(item.data, markup_pos, \
                    (uint8_t)item.word_start)); \
                decoded_valid[0] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 1), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(15, 8) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 1), \
                    (uint8_t)item.word_start)); \
                decoded_valid[1] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 2), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(23, 16) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 2), \
                    (uint8_t)item.word_start)); \
                decoded_valid[2] = 1; \
            } \
            if (byte_present((uint8_t)(markup_pos + 3), \
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) { \
                decoded.bits(31, 24) = u8(word_byte(item.data, \
                    (uint8_t)(markup_pos + 3), \
                    (uint8_t)item.word_start)); \
                decoded_valid[3] = 1; \
            } \
        } \
        result.ipv6_ext_decode = decoded; \
        result.ipv6_ext_decode_valid = decoded_valid; \
        return result; \
    }

    PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(ipv6_ext1_decode_stage, 0)
    PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(ipv6_ext2_decode_stage, 1)
    PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(ipv6_ext3_decode_stage, 2)
    PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(ipv6_ext4_decode_stage, 3)
    PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(ipv6_ext5_decode_stage, 4)
    PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(ipv6_ext6_decode_stage, 5)
    PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(ipv6_ext7_decode_stage, 6)
    PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE(ipv6_ext8_decode_stage, 7)

#undef PACKET_PARSER_DEFINE_IPV6_EXT_DECODE_STAGE

#define PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(NAME, INDEX) \
    PacketParserPipeWord NAME(PacketParserPipeWord item) \
    { \
        PacketParserPipeWord result; \
        PacketParserProgress progress; \
        uint8_t markup_pos; \
        uint8_t selector; \
        uint8_t size; \
        uint16_t next_pos; \
        bool size_known; \
        result = item; \
        result.ipv6_ext_decoded_size = 0; \
        result.ipv6_ext_decoded_next_pos = 0; \
        result.ipv6_ext_size_known = 0; \
        result.ipv6_ext_header_complete = 0; \
        result.ipv6_ext_decoded_limit = 0; \
        progress = item.progress; \
        if (!(bool)item.raw \
            && (uint8_t)item.ipv6_ext_index >= INDEX \
            && ((uint8_t)progress.state \
                & PACKET_HEADER_IPV6_OPTIONS) != 0 \
            && !(bool)progress.error && !(bool)progress.limit \
            && !(bool)progress.done) { \
            markup_pos = (uint8_t)progress.pos; \
            selector = (uint8_t)item.fields.protocol; \
            size = (uint8_t)ipv6_ext_extent_size_reg[INDEX]; \
            size_known = selector == 44 \
                || (bool)item.ipv6_ext_decode_valid[1] \
                || (uint8_t)item.word_start > (uint8_t)(markup_pos + 1); \
            if (selector == 44) size = 8; \
            else if ((bool)item.ipv6_ext_decode_valid[1]) { \
                if (selector == 51) \
                    size = ((uint8_t)item.ipv6_ext_decode.bits(15, 8) \
                        + 2) * 4; \
                else \
                    size = ((uint8_t)item.ipv6_ext_decode.bits(15, 8) \
                        + 1) * 8; \
            } \
            if (size_known) { \
                ipv6_ext_extent_size_reg[INDEX]._next = u8(size); \
                next_pos = (uint16_t)markup_pos + size; \
                result.ipv6_ext_decoded_size = u8(size); \
                result.ipv6_ext_decoded_next_pos = u8(next_pos); \
                result.ipv6_ext_size_known = 1; \
                if (next_pos > PACKET_PARSER_HEADER_BYTES) \
                    result.ipv6_ext_decoded_limit = 1; \
                else if (size != 0 && field_complete(markup_pos, size, \
                        (uint8_t)item.word_start, \
                        (uint8_t)item.word_last)) \
                    result.ipv6_ext_header_complete = 1; \
            } \
        } \
        return result; \
    }

    PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(ipv6_ext1_extent_stage, 0)
    PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(ipv6_ext2_extent_stage, 1)
    PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(ipv6_ext3_extent_stage, 2)
    PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(ipv6_ext4_extent_stage, 3)
    PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(ipv6_ext5_extent_stage, 4)
    PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(ipv6_ext6_extent_stage, 5)
    PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(ipv6_ext7_extent_stage, 6)
    PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE(ipv6_ext8_extent_stage, 7)

#undef PACKET_PARSER_DEFINE_IPV6_EXT_EXTENT_STAGE

#define PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(NAME, INDEX, PARSE) \
    PacketParserPipeWord NAME(PacketParserPipeWord item) \
    { \
        PacketParserPipeWord result; \
        uint8_t markup_pos; \
        uint8_t flags; \
        u<2> phase; \
        uint8_t prior_pos; \
        logic<MARKUP_BITS> markup_state; \
        PacketParserCall call; \
        PacketParserProgress progress; \
        bool eligible; \
        result = item; \
        if ((bool)item.raw) return result; \
        if (!(bool)item.sop \
            && ((uint8_t)ipv6_ext_stage_index_reg[INDEX] & 3) != 0) \
            progress = ipv6_ext_progress_reg[INDEX]; \
        else progress = item.progress; \
        phase = ipv6_ext_stage_index_reg[INDEX]; \
        if ((bool)item.sop) { \
            phase = 0; \
            progress = item.progress; \
        } \
        eligible = (uint8_t)item.ipv6_ext_index >= INDEX; \
        if (((uint8_t)phase & 3) == 0 && eligible \
            && ((uint8_t)progress.state \
                & PACKET_HEADER_IPV6_OPTIONS) != 0 \
            && !(bool)progress.error && !(bool)progress.limit \
            && !(bool)progress.done) { \
            phase = 1; \
            ipv6_next_proto_reg[INDEX]._next = item.fields.protocol; \
            ipv6_ext_size_reg[INDEX]._next = 0; \
            ipv6_fragment_reg[INDEX]._next = 0; \
            noninitial_fragment_reg[INDEX]._next = 0; \
            ipv6_ext_seen_reg[INDEX]._next = 1; \
        } \
        markup_state = 0; \
        markup_pos = (uint8_t)progress.pos; \
        prior_pos = markup_pos; \
        if (((uint8_t)progress.state \
                & PACKET_HEADER_IPV6_OPTIONS) != 0 \
            && ((uint8_t)phase & 1) != 0) { \
            call = PARSE(markup_pos, markup_state, progress, item.data, \
                (uint8_t)item.word_last, (uint8_t)item.word_start, \
                item.ipv6_ext_decode, item.ipv6_ext_decode_valid, \
                (uint8_t)item.ipv6_ext_decoded_size, \
                (uint8_t)item.ipv6_ext_decoded_next_pos, \
                (bool)item.ipv6_ext_size_known, \
                (bool)item.ipv6_ext_header_complete, \
                (bool)item.ipv6_ext_decoded_limit); \
            progress = call.progress; \
            if ((uint8_t)progress.pos != prior_pos \
                || ((uint8_t)progress.state \
                    & PACKET_HEADER_IPV6_OPTIONS) == 0 \
                || (bool)progress.error || (bool)progress.limit \
                || (bool)progress.done) \
                phase = 2; \
        } \
        ipv6_ext_progress_reg[INDEX]._next = progress; \
        ipv6_ext_stage_index_reg[INDEX]._next = phase; \
        result.progress = progress; \
        if (((uint8_t)phase & 2) != 0) \
            result.ipv6_ext_index = u<4>(INDEX + 1); \
        else if (((uint8_t)phase & 1) != 0) \
            result.ipv6_ext_index = u<4>(INDEX); \
        else result.ipv6_ext_index = item.ipv6_ext_index; \
        if (((uint8_t)phase & 2) != 0) \
            result.fields.protocol = ipv6_next_proto_reg[INDEX]._next; \
        if ((bool)item.eop && ((uint8_t)phase & 3) != 0 \
            && (uint16_t)ipv6_fragment_reg[INDEX]._next != 0) { \
            flags = (uint8_t)result.fields.flags; \
            flags |= PACKET_PARSER_FLAG_FRAGMENT; \
            result.fields.flags = u8(flags); \
        } \
        return result; \
    }

    PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(ipv6_ext1_stage, 0,
        parse_ipv6_options1)
    PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(ipv6_ext2_stage, 1,
        parse_ipv6_options2)
    PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(ipv6_ext3_stage, 2,
        parse_ipv6_options3)
    PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(ipv6_ext4_stage, 3,
        parse_ipv6_options4)
    PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(ipv6_ext5_stage, 4,
        parse_ipv6_options5)
    PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(ipv6_ext6_stage, 5,
        parse_ipv6_options6)
    PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(ipv6_ext7_stage, 6,
        parse_ipv6_options7)
    PACKET_PARSER_DEFINE_IPV6_EXT_STAGE(ipv6_ext8_stage, 7,
        parse_ipv6_options8)

#undef PACKET_PARSER_DEFINE_IPV6_EXT_STAGE

    PacketParserPipeWord transport_decode_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        PacketParserProgress progress;
        logic<40> decoded;
        logic<5> decoded_valid;
        uint8_t markup_pos;
        decoded = 0;
        decoded_valid = 0;
        result = item;
        progress = item.progress;
        if (!(bool)item.raw
            && (((uint8_t)progress.state & PACKET_HEADER_TCP) != 0
                || ((uint8_t)progress.state & PACKET_HEADER_UDP) != 0)
            && !(bool)progress.error && !(bool)progress.limit
            && !(bool)progress.done) {
            markup_pos = (uint8_t)progress.pos;
            if (byte_present(markup_pos, (uint8_t)item.word_start,
                    (uint8_t)item.word_last)) {
                decoded.bits(7, 0) = u8(word_byte(item.data, markup_pos,
                    (uint8_t)item.word_start));
                decoded_valid[0] = 1;
            }
            if (byte_present((uint8_t)(markup_pos + 1),
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) {
                decoded.bits(15, 8) = u8(word_byte(item.data,
                    (uint8_t)(markup_pos + 1),
                    (uint8_t)item.word_start));
                decoded_valid[1] = 1;
            }
            if (byte_present((uint8_t)(markup_pos + 2),
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) {
                decoded.bits(23, 16) = u8(word_byte(item.data,
                    (uint8_t)(markup_pos + 2),
                    (uint8_t)item.word_start));
                decoded_valid[2] = 1;
            }
            if (byte_present((uint8_t)(markup_pos + 3),
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) {
                decoded.bits(31, 24) = u8(word_byte(item.data,
                    (uint8_t)(markup_pos + 3),
                    (uint8_t)item.word_start));
                decoded_valid[3] = 1;
            }
            if (byte_present((uint8_t)(markup_pos + 12),
                    (uint8_t)item.word_start, (uint8_t)item.word_last)) {
                decoded.bits(39, 32) = u8(word_byte(item.data,
                    (uint8_t)(markup_pos + 12),
                    (uint8_t)item.word_start));
                decoded_valid[4] = 1;
            }
        }
        result.transport_decode = decoded;
        result.transport_decode_valid = decoded_valid;
        return result;
    }

    PacketParserPipeWord tcp_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.raw) return result;
        if ((bool)item.sop) {
            source_port_reg._next = 0;
            destination_port_reg._next = 0;
            tcp_header_bytes_reg._next = 0;
            progress = item.progress;
        }
        else progress = accept_tcp_upstream(tcp_progress_reg,
            item.progress);
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        call = parse_tcp(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.word_last, (uint8_t)item.word_start,
            item.transport_decode, item.transport_decode_valid);
        progress = call.progress;
        tcp_progress_reg._next = progress;
        result.progress = progress;
        return result;
    }

    PacketParserPipeWord udp_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.raw) return result;
        if ((bool)item.sop) progress = item.progress;
        else {
            progress.state = state_reg;
            progress.pos = pos_reg;
            progress.error = error_reg;
            progress.limit = limit_reg;
            progress.done = done_reg;
            progress = accept_udp_upstream(progress, item.progress);
        }
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        call = parse_udp(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.word_last, (uint8_t)item.word_start,
            item.transport_decode, item.transport_decode_valid);
        progress = call.progress;
        state_reg._next = progress.state;
        pos_reg._next = progress.pos;
        error_reg._next = progress.error;
        limit_reg._next = progress.limit;
        done_reg._next = progress.done;
        word_cntr_reg._next = item.word_cntr;
        result.progress = progress;
        if ((bool)item.eop) {
            result.fields.source_port = source_port_reg._next;
            result.fields.destination_port = destination_port_reg._next;
        }
        return result;
    }

    PacketParserWord finish_parser(PacketParserPipeWord item)
    {
        PacketParserWord word;
        PacketParserFields fields;
        uint8_t flags;
        word.raw = 0;
        fields = item.fields;
        flags = (uint8_t)fields.flags;
        if ((bool)item.progress.limit)
            flags |= PACKET_PARSER_FLAG_LIMIT;
        else if ((bool)item.progress.error)
            flags |= PACKET_PARSER_FLAG_MALFORMED;
        else if ((bool)item.progress.done) {
            flags |= PACKET_PARSER_FLAG_PARSED;
            if ((uint8_t)fields.protocol == 6
                || (uint8_t)fields.protocol == 17)
                flags |= PACKET_PARSER_FLAG_TRANSPORT;
        }
        fields.flags = u8(flags);
        word.fields = fields;
        return word;
    }

    static logic<320> segment_mask(uint8_t bytes)
    {
        logic<320> result;
        result = 0;
        if (bytes > 0) result.bits(7, 0) = ~u8(0);
        if (bytes > 1) result.bits(15, 8) = ~u8(0);
        if (bytes > 2) result.bits(23, 16) = ~u8(0);
        if (bytes > 3) result.bits(31, 24) = ~u8(0);
        if (bytes > 4) result.bits(39, 32) = ~u8(0);
        if (bytes > 5) result.bits(47, 40) = ~u8(0);
        if (bytes > 6) result.bits(55, 48) = ~u8(0);
        if (bytes > 7) result.bits(63, 56) = ~u8(0);
        if (bytes > 8) result.bits(71, 64) = ~u8(0);
        if (bytes > 9) result.bits(79, 72) = ~u8(0);
        if (bytes > 10) result.bits(87, 80) = ~u8(0);
        if (bytes > 11) result.bits(95, 88) = ~u8(0);
        if (bytes > 12) result.bits(103, 96) = ~u8(0);
        if (bytes > 13) result.bits(111, 104) = ~u8(0);
        if (bytes > 14) result.bits(119, 112) = ~u8(0);
        if (bytes > 15) result.bits(127, 120) = ~u8(0);
        if (bytes > 16) result.bits(135, 128) = ~u8(0);
        if (bytes > 17) result.bits(143, 136) = ~u8(0);
        if (bytes > 18) result.bits(151, 144) = ~u8(0);
        if (bytes > 19) result.bits(159, 152) = ~u8(0);
        if (bytes > 20) result.bits(167, 160) = ~u8(0);
        if (bytes > 21) result.bits(175, 168) = ~u8(0);
        if (bytes > 22) result.bits(183, 176) = ~u8(0);
        if (bytes > 23) result.bits(191, 184) = ~u8(0);
        if (bytes > 24) result.bits(199, 192) = ~u8(0);
        if (bytes > 25) result.bits(207, 200) = ~u8(0);
        if (bytes > 26) result.bits(215, 208) = ~u8(0);
        if (bytes > 27) result.bits(223, 216) = ~u8(0);
        if (bytes > 28) result.bits(231, 224) = ~u8(0);
        if (bytes > 29) result.bits(239, 232) = ~u8(0);
        if (bytes > 30) result.bits(247, 240) = ~u8(0);
        if (bytes > 31) result.bits(255, 248) = ~u8(0);
        if (bytes > 32) result.bits(263, 256) = ~u8(0);
        if (bytes > 33) result.bits(271, 264) = ~u8(0);
        if (bytes > 34) result.bits(279, 272) = ~u8(0);
        if (bytes > 35) result.bits(287, 280) = ~u8(0);
        if (bytes > 36) result.bits(295, 288) = ~u8(0);
        if (bytes > 37) result.bits(303, 296) = ~u8(0);
        if (bytes > 38) result.bits(311, 304) = ~u8(0);
        if (bytes > 39) result.bits(319, 312) = ~u8(0);
        return result;
    }

    static logic<OUTPUT_WORD_BITS> store_raw_low(
        logic<OUTPUT_WORD_BITS> previous, const logic<320>& word,
        uint8_t slot)
    {
        logic<OUTPUT_WORD_BITS> result;
        result = previous;
        if (LANE_WIDTH == 160) {
            if (slot == 0) result.bits(159, 0) = word.bits(159, 0);
            if (slot == 1) result.bits(319, 160) = word.bits(159, 0);
            if (slot == 2) result.bits(479, 320) = word.bits(159, 0);
            if (slot == 3) result.bits(511, 480) = word.bits(31, 0);
        }
        else {
            if (slot == 0) result.bits(319, 0) = word;
            if (slot == 1) result.bits(511, 320) = word.bits(191, 0);
        }
        return result;
    }

    static logic<OUTPUT_WORD_BITS> store_raw_high(
        logic<OUTPUT_WORD_BITS> previous, const logic<320>& word,
        uint8_t slot)
    {
        logic<OUTPUT_WORD_BITS> result;
        result = previous;
        if (LANE_WIDTH == 160) {
            if (slot == 3) result.bits(127, 0) = word.bits(159, 32);
            if (slot == 4) result.bits(287, 128) = word.bits(159, 0);
            if (slot == 5) result.bits(447, 288) = word.bits(159, 0);
            if (slot == 6) result.bits(511, 448) = word.bits(63, 0);
        }
        else {
            if (slot == 1) result.bits(127, 0) = word.bits(319, 192);
            if (slot == 2) result.bits(447, 128) = word;
            if (slot == 3) result.bits(511, 448) = word.bits(63, 0);
        }
        return result;
    }

    static logic<OUTPUT_BYTES> raw_keep_word(uint8_t count, uint8_t base)
    {
        logic<OUTPUT_BYTES> result;
        uint8_t byte;
        result = 0;
        for (byte = 0; byte < OUTPUT_BYTES; ++byte)
            result[byte] = (uint16_t)base + byte < count;
        return result;
    }

    PacketParserWord& output_data_comb_func()
    {
        uint32_t head;
        head = 0;
        output_data_comb.raw = 0;
        if ((uint8_t)fifo_count_reg != 0) {
            head = (uint8_t)fifo_head_reg;
            output_data_comb.raw = fifo_data_reg[head];
        }
        return output_data_comb;
    }

    logic<OUTPUT_BYTES>& output_keep_comb_func()
    {
        uint32_t byte;
        uint32_t head;
        head = 0;
        output_keep_comb = 0;
        if ((uint8_t)fifo_count_reg != 0) {
            head = (uint8_t)fifo_head_reg;
            for (byte = 0; byte < OUTPUT_BYTES; ++byte)
                output_keep_comb[byte] = fifo_keep_reg[head][byte];
        }
        return output_keep_comb;
    }

    bool& output_valid_comb_func()
    {
        output_valid_comb = (uint8_t)fifo_count_reg != 0;
        return output_valid_comb;
    }

    bool& output_last_comb_func()
    {
        uint32_t head;
        head = 0;
        output_last_comb = false;
        if ((uint8_t)fifo_count_reg != 0) {
            head = (uint8_t)fifo_head_reg;
            output_last_comb = fifo_last_reg[head];
        }
        return output_last_comb;
    }

    bool& output_raw_comb_func()
    {
        uint32_t head;
        head = 0;
        output_raw_comb = false;
        if ((uint8_t)fifo_count_reg != 0) {
            head = (uint8_t)fifo_head_reg;
            output_raw_comb = fifo_raw_reg[head];
        }
        return output_raw_comb;
    }

    bool& input_ready_comb_func()
    {
        uint8_t count;
        count = (uint8_t)reserved_slots_reg;
        if ((uint8_t)fifo_count_reg != 0 && ready_in()) --count;
        // Two free entries are reserved because a RAW frame emits two words.
        input_ready_comb = !(bool)ingress_valid_reg
            || (count <= OUTPUT_FIFO_WORDS - 2
                && !(bool)pending_valid_reg
                && !(bool)pending_raw_token_reg
                && (uint8_t)raw_store_count_reg < 4);
        return input_ready_comb;
    }

public:
    void _assign()
    {
        ready_out = _ASSIGN_COMB(input_ready_comb_func());
        data_out = _ASSIGN_COMB(output_data_comb_func());
        keep_out = _ASSIGN_COMB(output_keep_comb_func());
        valid_out = _ASSIGN_COMB(output_valid_comb_func());
        last_out = _ASSIGN_COMB(output_last_comb_func());
        raw_out = _ASSIGN_COMB(output_raw_comb_func());
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void _work(bool reset)
    {
        uint32_t slot;
        uint32_t stage;
        uint32_t lane;
        uint32_t flat;
        uint8_t head;
        uint8_t tail;
        uint8_t fifo_count;
        uint8_t raw_store_head;
        uint8_t raw_store_tail;
        uint8_t raw_store_count;
        uint8_t reserved_slots;
        uint8_t align_count;
        uint8_t raw_word_count;
        uint8_t align_word_cntr;
        uint8_t emit_word_cntr;
        uint8_t emit2_word_cntr;
        bool in_frame;
        bool frame_raw;
        bool keep;
        bool sop;
        bool eop;
        bool emit_valid;
        bool emit_raw;
        bool emit2_valid;
        bool emit2_raw;
        bool emit_sop;
        bool emit_eop;
        bool emit2_sop;
        bool emit2_eop;
        bool frame_end;
        bool rollover;
        bool pending_valid;
        bool pending_rollover;
        bool pending_raw_token;
        bool parse_valid;
        bool consume_pending;
        uint8_t input_byte;
        uint8_t emit_bytes;
        uint8_t emit2_bytes;
        uint8_t pending_bytes;
        uint8_t parse_bytes;
        uint8_t parse_word_cntr;
        uint8_t sop_pos;
        uint8_t eop_pos;
        uint8_t keep_last;
        uint8_t part;
        uint8_t segment_start;
        uint8_t segment_bytes;
        uint8_t total_bytes;
        uint16_t frame_byte_count;
        bool parse_sop;
        bool parse_eop;
        bool align_sop_pending;
        bool has_sop;
        bool has_eop;
        bool has_keep;
        bool started_in_frame;
        bool segment_valid;
        bool segment_sop;
        bool segment_eop;
        bool segment_raw;
        bool alignment_ready;
        bool ingress_valid;
        bool decode_in_frame;
        bool decode_frame_raw;
        bool ingress_error;
        logic<320> align_data;
        logic<320> ingress_data;
        logic<320> segment_data;
        logic<320> output_word;
        logic<640> combined;
        logic<320> emit_data;
        logic<320> emit2_data;
        logic<320> pending_data;
        logic<320> parse_data;
        logic<OUTPUT_WORD_BITS> raw_data_low;
        logic<OUTPUT_WORD_BITS> raw_data_high;
        uint8_t end_raw_count;
        PacketParserWord parsed;
        PacketParserPipeWord pipe_item;
        PacketParserProgress empty_progress;

        if (reset) {
            reset_parser();
            align_data_reg._next = 0;
            align_count_reg._next = 0;
            raw_data_low_reg._next = 0;
            raw_data_high_reg._next = 0;
            raw_word_count_reg._next = 0;
            in_frame_reg._next = 0;
            frame_raw_reg._next = 0;
            pending_valid_reg._next = 0;
            pending_rollover_reg._next = 0;
            pending_data_reg._next = 0;
            pending_bytes_reg._next = 0;
            pending_word_cntr_reg._next = 0;
            pending_sop_reg._next = 0;
            pending_eop_reg._next = 0;
            pending_raw_token_reg._next = 0;
            align_word_cntr_reg._next = 0;
            align_sop_pending_reg._next = 0;
            ingress_valid_reg._next = 0;
            ingress_data_reg._next = 0;
            ingress_error_reg._next = 0;
            decode_in_frame_reg._next = 0;
            decode_frame_raw_reg._next = 0;
            for (part = 0; part < 2; ++part) {
                ingress_segment_valid_reg[part]._next = 0;
                ingress_segment_sop_reg[part]._next = 0;
                ingress_segment_eop_reg[part]._next = 0;
                ingress_segment_raw_reg[part]._next = 0;
                ingress_segment_start_reg[part]._next = 0;
                ingress_segment_bytes_reg[part]._next = 0;
                raw_emit_valid_reg[part]._next = 0;
                raw_emit_data_reg[part]._next = 0;
                raw_emit_bytes_reg[part]._next = 0;
                raw_emit_word_cntr_reg[part]._next = 0;
                raw_emit_sop_reg[part]._next = 0;
                raw_emit_eop_reg[part]._next = 0;
            }
            for (stage = 0; stage < PIPE_STAGES; ++stage) {
                pipe_reg[stage]._next = {};
                pipe_valid_reg[stage]._next = 0;
            }
            raw_store_head_reg._next = 0;
            raw_store_tail_reg._next = 0;
            raw_store_count_reg._next = 0;
            for (slot = 0; slot < 4; ++slot) {
                raw_store_low_reg[slot]._next = 0;
                raw_store_high_reg[slot]._next = 0;
                raw_store_count_bytes_reg[slot]._next = 0;
            }
            fifo_head_reg._next = 0;
            fifo_tail_reg._next = 0;
            fifo_count_reg._next = 0;
            reserved_slots_reg._next = 0;
            for (slot = 0; slot < OUTPUT_FIFO_WORDS; ++slot) {
                fifo_data_reg[slot]._next = 0;
                fifo_keep_reg[slot]._next = 0;
                fifo_last_reg[slot]._next = 0;
                fifo_raw_reg[slot]._next = 0;
            }
            protocol_error_reg._next = 0;
            return;
        }

        protocol_error_reg._next = protocol_error_reg;
        hold_parser();
            ethernet_progress_reg._next = ethernet_progress_reg;
            for (stage = 0; stage < 4; ++stage) {
                vlan_progress_reg[stage]._next = vlan_progress_reg[stage];
                vlan_stage_index_reg[stage]._next =
                    vlan_stage_index_reg[stage];
            }
            for (stage = 0; stage < 4; ++stage) {
                mpls_progress_reg[stage]._next = mpls_progress_reg[stage];
                mpls_stage_index_reg[stage]._next =
                    mpls_stage_index_reg[stage];
            }
            ipv4_progress_reg._next = ipv4_progress_reg;
            ipv4_options_progress_reg._next = ipv4_options_progress_reg;
            ipv6_progress_reg._next = ipv6_progress_reg;
            tcp_progress_reg._next = tcp_progress_reg;
            for (stage = 0; stage < 8; ++stage) {
                ipv6_ext_progress_reg[stage]._next =
                    ipv6_ext_progress_reg[stage];
                ipv6_ext_stage_index_reg[stage]._next =
                    ipv6_ext_stage_index_reg[stage];
            }
            for (slot = 0; slot < OUTPUT_FIFO_WORDS; ++slot) {
                fifo_data_reg[slot]._next = fifo_data_reg[slot];
                fifo_keep_reg[slot]._next = fifo_keep_reg[slot];
                fifo_last_reg[slot]._next = fifo_last_reg[slot];
                fifo_raw_reg[slot]._next = fifo_raw_reg[slot];
            }
            for (slot = 0; slot < 4; ++slot) {
                raw_store_low_reg[slot]._next = raw_store_low_reg[slot];
                raw_store_high_reg[slot]._next = raw_store_high_reg[slot];
                raw_store_count_bytes_reg[slot]._next =
                    raw_store_count_bytes_reg[slot];
            }
            head = (uint8_t)fifo_head_reg;
            tail = (uint8_t)fifo_tail_reg;
            fifo_count = (uint8_t)fifo_count_reg;
            raw_store_head = (uint8_t)raw_store_head_reg;
            raw_store_tail = (uint8_t)raw_store_tail_reg;
            raw_store_count = (uint8_t)raw_store_count_reg;
            reserved_slots = (uint8_t)reserved_slots_reg;
            if (fifo_count != 0 && (bool)ready_in()) {
                head = (head + 1) & (OUTPUT_FIFO_WORDS - 1);
                --fifo_count;
                --reserved_slots;
            }

            // Advance every occupied pipeline stage exactly once.  Each
            // family sees one registered word and writes only its own state.
            for (stage = 0; stage < PIPE_STAGES; ++stage) {
                pipe_reg[stage]._next = {};
                pipe_valid_reg[stage]._next = 0;
            }
            if ((bool)pipe_valid_reg[PIPE_STAGES - 1]) {
                pipe_item = pipe_reg[PIPE_STAGES - 1];
                if ((bool)pipe_item.eop) {
                    if ((bool)pipe_item.raw) {
                        if (raw_store_count != 0
                            && fifo_count <= OUTPUT_FIFO_WORDS - 2) {
                            fifo_data_reg[tail]._next =
                                raw_store_low_reg[raw_store_head];
                            fifo_keep_reg[tail]._next = raw_keep_word(
                                (uint8_t)raw_store_count_bytes_reg[raw_store_head], 0);
                            fifo_last_reg[tail]._next = 0;
                            fifo_raw_reg[tail]._next = 1;
                            tail = (tail + 1) & (OUTPUT_FIFO_WORDS - 1);
                            ++fifo_count;
                            fifo_data_reg[tail]._next =
                                raw_store_high_reg[raw_store_head];
                            fifo_keep_reg[tail]._next = raw_keep_word(
                                (uint8_t)raw_store_count_bytes_reg[raw_store_head],
                                OUTPUT_BYTES);
                            fifo_last_reg[tail]._next = 1;
                            fifo_raw_reg[tail]._next = 1;
                            tail = (tail + 1) & (OUTPUT_FIFO_WORDS - 1);
                            ++fifo_count;
                            raw_store_head = (raw_store_head + 1) & 3;
                            --raw_store_count;
                        }
                        else protocol_error_reg._next = 1;
                    }
                    else {
                    if (!(bool)pipe_item.progress.done
                        && !(bool)pipe_item.progress.error
                        && !(bool)pipe_item.progress.limit)
                        pipe_item.progress.error = 1;
                    parsed = finish_parser(pipe_item);
                    if (fifo_count < OUTPUT_FIFO_WORDS) {
                        fifo_data_reg[tail]._next = parsed.raw;
                        fifo_keep_reg[tail]._next = ~logic<OUTPUT_BYTES>(0);
                        fifo_last_reg[tail]._next = 1;
                        fifo_raw_reg[tail]._next = 0;
                        tail = (tail + 1) & (OUTPUT_FIFO_WORDS - 1);
                        ++fifo_count;
                    }
                    else protocol_error_reg._next = 1;
                    }
                }
            }
            if ((bool)pipe_valid_reg[47]) {
                pipe_reg[48]._next = udp_stage(pipe_reg[47]);
                pipe_valid_reg[48]._next = 1;
            }
            if ((bool)pipe_valid_reg[46]) {
                pipe_reg[47]._next = tcp_stage(pipe_reg[46]);
                pipe_valid_reg[47]._next = 1;
            }
            if ((bool)pipe_valid_reg[45]) {
                pipe_reg[46]._next = transport_decode_stage(pipe_reg[45]);
                pipe_valid_reg[46]._next = 1;
            }
#define PACKET_PARSER_ADVANCE_IPV6_EXT(NUMBER, INPUT) \
            if ((bool)pipe_valid_reg[INPUT + 2]) { \
                pipe_reg[INPUT + 3]._next = \
                    ipv6_ext##NUMBER##_stage(pipe_reg[INPUT + 2]); \
                pipe_valid_reg[INPUT + 3]._next = 1; \
            } \
            if ((bool)pipe_valid_reg[INPUT + 1]) { \
                pipe_reg[INPUT + 2]._next = \
                    ipv6_ext##NUMBER##_extent_stage(pipe_reg[INPUT + 1]); \
                pipe_valid_reg[INPUT + 2]._next = 1; \
            } \
            if ((bool)pipe_valid_reg[INPUT]) { \
                pipe_reg[INPUT + 1]._next = \
                    ipv6_ext##NUMBER##_decode_stage(pipe_reg[INPUT]); \
                pipe_valid_reg[INPUT + 1]._next = 1; \
            }
            PACKET_PARSER_ADVANCE_IPV6_EXT(8, 42)
            PACKET_PARSER_ADVANCE_IPV6_EXT(7, 39)
            PACKET_PARSER_ADVANCE_IPV6_EXT(6, 36)
            PACKET_PARSER_ADVANCE_IPV6_EXT(5, 33)
            PACKET_PARSER_ADVANCE_IPV6_EXT(4, 30)
            PACKET_PARSER_ADVANCE_IPV6_EXT(3, 27)
            PACKET_PARSER_ADVANCE_IPV6_EXT(2, 24)
            PACKET_PARSER_ADVANCE_IPV6_EXT(1, 21)
#undef PACKET_PARSER_ADVANCE_IPV6_EXT
            if ((bool)pipe_valid_reg[20]) {
                pipe_reg[21]._next = ipv6_stage(pipe_reg[20]);
                pipe_valid_reg[21]._next = 1;
            }
            if ((bool)pipe_valid_reg[19]) {
                pipe_reg[20]._next = ipv4_options_stage(pipe_reg[19]);
                pipe_valid_reg[20]._next = 1;
            }
            if ((bool)pipe_valid_reg[18]) {
                pipe_reg[19]._next = ipv4_stage(pipe_reg[18]);
                pipe_valid_reg[19]._next = 1;
            }
#define PACKET_PARSER_ADVANCE_MPLS(NUMBER, INPUT) \
            if ((bool)pipe_valid_reg[INPUT + 1]) { \
                pipe_reg[INPUT + 2]._next = \
                    mpls##NUMBER##_stage(pipe_reg[INPUT + 1]); \
                pipe_valid_reg[INPUT + 2]._next = 1; \
            } \
            if ((bool)pipe_valid_reg[INPUT]) { \
                pipe_reg[INPUT + 1]._next = \
                    mpls##NUMBER##_decode_stage(pipe_reg[INPUT]); \
                pipe_valid_reg[INPUT + 1]._next = 1; \
            }
            PACKET_PARSER_ADVANCE_MPLS(4, 16)
            PACKET_PARSER_ADVANCE_MPLS(3, 14)
            PACKET_PARSER_ADVANCE_MPLS(2, 12)
            PACKET_PARSER_ADVANCE_MPLS(1, 10)
#undef PACKET_PARSER_ADVANCE_MPLS
#define PACKET_PARSER_ADVANCE_VLAN(NUMBER, INPUT) \
            if ((bool)pipe_valid_reg[INPUT + 1]) { \
                pipe_reg[INPUT + 2]._next = \
                    vlan##NUMBER##_stage(pipe_reg[INPUT + 1]); \
                pipe_valid_reg[INPUT + 2]._next = 1; \
            } \
            if ((bool)pipe_valid_reg[INPUT]) { \
                pipe_reg[INPUT + 1]._next = \
                    vlan##NUMBER##_decode_stage(pipe_reg[INPUT]); \
                pipe_valid_reg[INPUT + 1]._next = 1; \
            }
            PACKET_PARSER_ADVANCE_VLAN(4, 8)
            PACKET_PARSER_ADVANCE_VLAN(3, 6)
            PACKET_PARSER_ADVANCE_VLAN(2, 4)
            PACKET_PARSER_ADVANCE_VLAN(1, 2)
#undef PACKET_PARSER_ADVANCE_VLAN
            if ((bool)pipe_valid_reg[1]) {
                pipe_reg[2]._next = ethernet_stage(pipe_reg[1]);
                pipe_valid_reg[2]._next = 1;
            }
            if ((bool)pipe_valid_reg[0]) {
                pipe_reg[1]._next = ingress_bounds_stage(pipe_reg[0]);
                pipe_valid_reg[1]._next = 1;
            }
            alignment_ready = reserved_slots <= OUTPUT_FIFO_WORDS - 2
                && !(bool)pending_valid_reg
                && !(bool)pending_raw_token_reg
                && raw_store_count < 4;
            ingress_valid = (bool)ingress_valid_reg;
            ingress_data = ingress_data_reg;
            ingress_error = (bool)ingress_error_reg;
            decode_in_frame = (bool)decode_in_frame_reg;
            decode_frame_raw = (bool)decode_frame_raw_reg;
            ingress_valid_reg._next = ingress_valid_reg;
            ingress_data_reg._next = ingress_data_reg;
            ingress_error_reg._next = ingress_error_reg;
            decode_in_frame_reg._next = decode_in_frame_reg;
            decode_frame_raw_reg._next = decode_frame_raw_reg;
            for (part = 0; part < 2; ++part) {
                ingress_segment_valid_reg[part]._next =
                    ingress_segment_valid_reg[part];
                ingress_segment_sop_reg[part]._next =
                    ingress_segment_sop_reg[part];
                ingress_segment_eop_reg[part]._next =
                    ingress_segment_eop_reg[part];
                ingress_segment_raw_reg[part]._next =
                    ingress_segment_raw_reg[part];
                ingress_segment_start_reg[part]._next =
                    ingress_segment_start_reg[part];
                ingress_segment_bytes_reg[part]._next =
                    ingress_segment_bytes_reg[part];
                raw_emit_valid_reg[part]._next = 0;
                raw_emit_data_reg[part]._next = raw_emit_data_reg[part];
                raw_emit_bytes_reg[part]._next = raw_emit_bytes_reg[part];
                raw_emit_word_cntr_reg[part]._next =
                    raw_emit_word_cntr_reg[part];
                raw_emit_sop_reg[part]._next = raw_emit_sop_reg[part];
                raw_emit_eop_reg[part]._next = raw_emit_eop_reg[part];
            }
            align_data = align_data_reg;
            align_count = (uint8_t)align_count_reg;
            raw_data_low = raw_data_low_reg;
            raw_data_high = raw_data_high_reg;
            raw_word_count = (uint8_t)raw_word_count_reg;
            in_frame = (bool)in_frame_reg;
            frame_raw = (bool)frame_raw_reg;
            pending_valid = (bool)pending_valid_reg;
            pending_rollover = (bool)pending_rollover_reg;
            pending_raw_token = (bool)pending_raw_token_reg;
            pending_data = pending_data_reg;
            pending_bytes = (uint8_t)pending_bytes_reg;
            pending_word_cntr_reg._next = pending_word_cntr_reg;
            pending_sop_reg._next = pending_sop_reg;
            pending_eop_reg._next = pending_eop_reg;
            align_word_cntr = (uint8_t)align_word_cntr_reg;
            align_sop_pending = (bool)align_sop_pending_reg;
            emit_valid = false;
            emit_raw = false;
            emit2_valid = false;
            emit2_raw = false;
            emit_sop = false;
            emit_eop = false;
            emit2_sop = false;
            emit2_eop = false;
            emit_word_cntr = 0;
            emit2_word_cntr = 0;
            emit_bytes = 0;
            emit2_bytes = 0;
            emit_data = 0;
            emit2_data = 0;
            frame_end = false;
            rollover = false;
            end_raw_count = 0;

            if (ingress_valid && alignment_ready) {
                if (ingress_error) protocol_error_reg._next = 1;
                ingress_valid = false;
                // At most two registered contiguous frame segments occur in
                // one queue beat: the tail of the current packet and the head
                // of the next. Append each with one barrel shift.
                for (part = 0; part < 2; ++part) {
                    segment_valid =
                        (bool)ingress_segment_valid_reg[part];
                    segment_sop = (bool)ingress_segment_sop_reg[part];
                    segment_eop = (bool)ingress_segment_eop_reg[part];
                    segment_raw = (bool)ingress_segment_raw_reg[part];
                    segment_start =
                        (uint8_t)ingress_segment_start_reg[part];
                    segment_bytes =
                        (uint8_t)ingress_segment_bytes_reg[part];
                    if (segment_valid) {
                    if (segment_sop) {
                        if (in_frame) protocol_error_reg._next = 1;
                        if (frame_end) rollover = true;
                        align_data = 0;
                        align_count = 0;
                        align_word_cntr = 0;
                        align_sop_pending = true;
                        frame_raw = segment_raw;
                        in_frame = true;
                    }

                    segment_data = ingress_data;
                    segment_data >>= segment_start * 8;
                    segment_data &= segment_mask(segment_bytes);
                    combined = 0;
                    combined.bits(319, 0) = segment_data;
                    combined <<= align_count * 8;
                    combined.bits(319, 0) =
                        logic<320>(combined.bits(319, 0)) | align_data;
                    total_bytes = align_count + segment_bytes;
                    if (total_bytes >= LANE_BYTES) {
                        output_word = 0;
                        output_word.bits(LANE_WIDTH - 1, 0) =
                            combined.bits(LANE_WIDTH - 1, 0);
                        if (!emit_valid) {
                            emit_valid = true;
                            emit_raw = frame_raw;
                            emit_bytes = LANE_BYTES;
                            emit_data = output_word;
                            emit_word_cntr = align_word_cntr;
                            emit_sop = align_sop_pending;
                            emit_eop = segment_eop
                                && total_bytes == LANE_BYTES;
                        }
                        else {
                            emit2_valid = true;
                            emit2_raw = frame_raw;
                            emit2_bytes = LANE_BYTES;
                            emit2_data = output_word;
                            emit2_word_cntr = align_word_cntr;
                            emit2_sop = align_sop_pending;
                            emit2_eop = segment_eop
                                && total_bytes == LANE_BYTES;
                        }
                        align_sop_pending = false;
                        ++align_word_cntr;
                        combined >>= LANE_WIDTH;
                        align_data = combined.bits(319, 0);
                        align_count = total_bytes - LANE_BYTES;
                    }
                    else {
                        align_data = combined.bits(319, 0);
                        align_count = total_bytes;
                    }

                    if (segment_eop) {
                        if (align_count != 0) {
                            if (!emit_valid) {
                                emit_valid = true;
                                emit_raw = frame_raw;
                                emit_bytes = align_count;
                                emit_data = align_data;
                                emit_word_cntr = align_word_cntr;
                                emit_sop = align_sop_pending;
                                emit_eop = true;
                            }
                            else {
                                emit2_valid = true;
                                emit2_raw = frame_raw;
                                emit2_bytes = align_count;
                                emit2_data = align_data;
                                emit2_word_cntr = align_word_cntr;
                                emit2_sop = align_sop_pending;
                                emit2_eop = true;
                            }
                            align_sop_pending = false;
                            ++align_word_cntr;
                        }
                        if (frame_end) protocol_error_reg._next = 1;
                        frame_end = true;
                        in_frame = false;
                        align_data = 0;
                        align_count = 0;
                    }
                    }
                }
            }

            // Decode the next accepted beat into an elastic segment
            // descriptor. The decoder owns a predicted frame state so it can
            // accept a replacement descriptor in the same cycle that the
            // alignment stage consumes the previous one.
            if ((bool)valid_in() && (bool)input_ready_comb_func()) {
                has_sop = false;
                has_eop = false;
                has_keep = false;
                ingress_error = false;
                sop_pos = 0;
                eop_pos = 0;
                keep_last = 0;
                started_in_frame = decode_in_frame;
                for (lane = 0; lane < LANE_BYTES; ++lane) {
                    keep = (bool)keep_in()[lane];
                    sop = (bool)sop_in()[lane];
                    eop = (bool)eop_in()[lane];
                    if (keep) {
                        has_keep = true;
                        keep_last = lane;
                    }
                    else if (sop || eop) ingress_error = true;
                    if (sop && keep) {
                        if (has_sop) ingress_error = true;
                        has_sop = true;
                        sop_pos = lane;
                    }
                    if (eop && keep) {
                        if (has_eop) ingress_error = true;
                        has_eop = true;
                        eop_pos = lane;
                    }
                }

                for (part = 0; part < 2; ++part) {
                    segment_valid = false;
                    segment_sop = false;
                    segment_eop = false;
                    segment_raw = false;
                    segment_start = 0;
                    segment_bytes = 0;
                    if (part == 0 && has_keep) {
                        if (started_in_frame) {
                            segment_valid = true;
                            segment_raw = decode_frame_raw;
                            segment_eop = has_eop;
                            segment_bytes =
                                (has_eop ? eop_pos : keep_last) + 1;
                        }
                        else if (has_sop) {
                            segment_valid = true;
                            segment_sop = true;
                            segment_raw = (bool)raw_in();
                            segment_start = sop_pos;
                            segment_eop = has_eop && eop_pos >= sop_pos;
                            segment_bytes =
                                (segment_eop ? eop_pos : keep_last)
                                - segment_start + 1;
                        }
                        else ingress_error = true;
                    }
                    if (part == 1 && started_in_frame && has_eop && has_sop
                        && sop_pos > eop_pos) {
                        segment_valid = true;
                        segment_sop = true;
                        segment_raw = (bool)raw_in();
                        segment_start = sop_pos;
                        segment_bytes = keep_last - segment_start + 1;
                    }
                    ingress_segment_valid_reg[part]._next = segment_valid;
                    ingress_segment_sop_reg[part]._next = segment_sop;
                    ingress_segment_eop_reg[part]._next = segment_eop;
                    ingress_segment_raw_reg[part]._next = segment_raw;
                    ingress_segment_start_reg[part]._next =
                        u<BYTE_COUNT_BITS>(segment_start);
                    ingress_segment_bytes_reg[part]._next =
                        u<BYTE_COUNT_BITS>(segment_bytes);
                }

                if (started_in_frame) {
                    if (has_eop) {
                        decode_in_frame = has_sop && sop_pos > eop_pos;
                        if (decode_in_frame)
                            decode_frame_raw = (bool)raw_in();
                    }
                }
                else if (has_sop) {
                    decode_frame_raw = (bool)raw_in();
                    decode_in_frame = !(has_eop && eop_pos >= sop_pos);
                }
                ingress_data_reg._next = data_in();
                ingress_error_reg._next = ingress_error;
                ingress_valid = true;
            }

            consume_pending = pending_valid;
            parse_valid = !pending_raw_token
                && (consume_pending || (emit_valid && !emit_raw));
            parse_data = consume_pending ? pending_data : emit_data;
            parse_bytes = consume_pending ? pending_bytes : emit_bytes;
            parse_word_cntr = consume_pending
                ? (uint8_t)pending_word_cntr_reg : emit_word_cntr;
            parse_sop = consume_pending
                ? (bool)pending_sop_reg : emit_sop;
            parse_eop = consume_pending
                ? (bool)pending_eop_reg : emit_eop;
            if (parse_valid) {
                empty_progress = {};
                pipe_item = {};
                pipe_item.data = parse_data;
                pipe_item.fields = {};
                pipe_item.progress = empty_progress;
                pipe_item.word_cntr = u8(parse_word_cntr);
                pipe_item.bytes = u<6>(parse_bytes);
                pipe_item.sop = parse_sop;
                pipe_item.eop = parse_eop;
                pipe_reg[0]._next = pipe_item;
                pipe_valid_reg[0]._next = 1;
                if (parse_eop) ++reserved_slots;
            }
            if (pending_raw_token) {
                empty_progress = {};
                pipe_item = {};
                pipe_item.progress = empty_progress;
                pipe_item.raw = 1;
                pipe_item.sop = 1;
                pipe_item.eop = 1;
                pipe_reg[0]._next = pipe_item;
                pipe_valid_reg[0]._next = 1;
                pending_raw_token = false;
                reserved_slots += 2;
            }

            // The registered RAW emit batch is accumulated one cycle after
            // alignment. Direct word indices avoid another byte recurrence.
            for (part = 0; part < 2; ++part) {
                if ((bool)raw_emit_valid_reg[part]) {
                    if ((bool)raw_emit_sop_reg[part]) {
                        raw_data_low = 0;
                        raw_data_high = 0;
                        raw_word_count = 0;
                    }
                    if (raw_word_count < RAW_WORDS) {
                        raw_data_low = store_raw_low(raw_data_low,
                            raw_emit_data_reg[part], raw_word_count);
                        raw_data_high = store_raw_high(raw_data_high,
                            raw_emit_data_reg[part], raw_word_count);
                        ++raw_word_count;
                    }
                    if ((bool)raw_emit_eop_reg[part]) {
                        frame_byte_count =
                            (uint16_t)(uint8_t)raw_emit_word_cntr_reg[part]
                                * LANE_BYTES
                            + (uint8_t)raw_emit_bytes_reg[part];
                        if (frame_byte_count > RAW_BYTES)
                            end_raw_count = RAW_BYTES;
                        else end_raw_count = (uint8_t)frame_byte_count;
                        if (raw_store_count < 4) {
                            raw_store_low_reg[raw_store_tail]._next =
                                raw_data_low;
                            raw_store_high_reg[raw_store_tail]._next =
                                raw_data_high;
                            raw_store_count_bytes_reg[raw_store_tail]._next =
                                u8(end_raw_count);
                            raw_store_tail = (raw_store_tail + 1) & 3;
                            ++raw_store_count;
                            empty_progress = {};
                            pipe_item = {};
                            pipe_item.progress = empty_progress;
                            pipe_item.raw = 1;
                            pipe_item.sop = 1;
                            pipe_item.eop = 1;
                            // RAW accumulation is one cycle behind alignment.
                            // Enter at stage 1 while the following parsed word
                            // enters stage 0, retaining descriptor order.
                            pipe_reg[1]._next = pipe_item;
                            pipe_valid_reg[1]._next = 1;
                            reserved_slots += 2;
                        }
                        else protocol_error_reg._next = 1;
                        raw_data_low = 0;
                        raw_data_high = 0;
                        raw_word_count = 0;
                    }
                }
            }

            if (emit2_valid && !emit2_raw) {
                pending_valid = true;
                pending_data = emit2_data;
                pending_bytes = emit2_bytes;
                pending_rollover = rollover;
                pending_word_cntr_reg._next = u8(emit2_word_cntr);
                pending_sop_reg._next = emit2_sop;
                pending_eop_reg._next = emit2_eop;
                frame_end = false;
            }

            if (consume_pending) {
                pending_valid = false;
                pending_rollover = false;
            }
            raw_emit_valid_reg[0]._next = emit_valid && emit_raw;
            raw_emit_data_reg[0]._next = emit_data;
            raw_emit_bytes_reg[0]._next = u<BYTE_COUNT_BITS>(emit_bytes);
            raw_emit_word_cntr_reg[0]._next = u8(emit_word_cntr);
            raw_emit_sop_reg[0]._next = emit_sop;
            raw_emit_eop_reg[0]._next = emit_eop;
            raw_emit_valid_reg[1]._next = emit2_valid && emit2_raw;
            raw_emit_data_reg[1]._next = emit2_data;
            raw_emit_bytes_reg[1]._next = u<BYTE_COUNT_BITS>(emit2_bytes);
            raw_emit_word_cntr_reg[1]._next = u8(emit2_word_cntr);
            raw_emit_sop_reg[1]._next = emit2_sop;
            raw_emit_eop_reg[1]._next = emit2_eop;

            align_data_reg._next = align_data;
            align_count_reg._next = u<BYTE_COUNT_BITS>(align_count);
            raw_data_low_reg._next = raw_data_low;
            raw_data_high_reg._next = raw_data_high;
            raw_word_count_reg._next = u<5>(raw_word_count);
            in_frame_reg._next = in_frame;
            frame_raw_reg._next = frame_raw;
            pending_valid_reg._next = pending_valid;
            pending_rollover_reg._next = pending_rollover;
            pending_data_reg._next = pending_data;
            pending_bytes_reg._next = u<BYTE_COUNT_BITS>(pending_bytes);
            pending_raw_token_reg._next = pending_raw_token;
            if (!pending_valid) {
                pending_word_cntr_reg._next = 0;
                pending_sop_reg._next = 0;
                pending_eop_reg._next = 0;
            }
            align_word_cntr_reg._next = u8(align_word_cntr);
            align_sop_pending_reg._next = align_sop_pending;
            ingress_valid_reg._next = ingress_valid;
            decode_in_frame_reg._next = decode_in_frame;
            decode_frame_raw_reg._next = decode_frame_raw;
            fifo_head_reg._next = u<5>(head);
            fifo_tail_reg._next = u<5>(tail);
            fifo_count_reg._next = u<6>(fifo_count);
            reserved_slots_reg._next = u<6>(reserved_slots);
            raw_store_head_reg._next = u<2>(raw_store_head);
            raw_store_tail_reg._next = u<2>(raw_store_tail);
            raw_store_count_reg._next = u<3>(raw_store_count);
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        uint32_t slot;
        uint32_t stage;
        uint32_t index;
        state_reg.strobe(); pos_reg.strobe();
            word_cntr_reg.strobe(); ethernet_done_reg.strobe();
            error_reg.strobe(); limit_reg.strobe();
            done_reg.strobe();
            ethernet_progress_reg.strobe();
            for (index = 0; index < 4; ++index) {
                vlan_progress_reg[index].strobe();
                vlan_stage_index_reg[index].strobe();
            }
            for (index = 0; index < 4; ++index) {
                mpls_progress_reg[index].strobe();
                mpls_stage_index_reg[index].strobe();
            }
            ipv4_progress_reg.strobe();
            ipv4_options_progress_reg.strobe();
            ipv6_progress_reg.strobe();
            tcp_progress_reg.strobe();
            for (index = 0; index < 8; ++index) {
                ipv6_ext_progress_reg[index].strobe();
                ipv6_ext_stage_index_reg[index].strobe();
            }
            destination_mac_reg.strobe();
            source_mac_reg.strobe(); ethernet_type_reg.strobe();
            for (index = 0; index < 4; ++index)
                vlan_next_proto_reg[index].strobe();
            vlan_count_reg.strobe();
#if PACKET_PARSER_ENABLE_VLAN
            for (index = 0; index < PACKET_PARSER_OUTPUT_VLAN_HEADERS; ++index)
                vlan_tci_reg[index].strobe();
#endif
            for (index = 0; index < 4; ++index) {
                mpls_entry_reg[index].strobe();
                mpls_entry_done_reg[index].strobe();
            }
            mpls_count_reg.strobe();
#if PACKET_PARSER_ENABLE_MPLS
            for (index = 0; index < PACKET_PARSER_OUTPUT_MPLS_LABELS; ++index)
                mpls_output_reg[index].strobe();
#endif
            source_ip_reg.strobe(); destination_ip_reg.strobe();
            protocol_reg.strobe(); ip_version_reg.strobe();
            ip_header_bytes_reg.strobe(); transport_pos_reg.strobe();
            ipv4_fragment_reg.strobe(); initial_fragment_reg.strobe();
            ipv6_source_ip_reg.strobe(); ipv6_destination_ip_reg.strobe();
            ipv6_base_next_proto_reg.strobe(); ipv6_seen_reg.strobe();
            for (index = 0; index < 8; ++index) {
                ipv6_next_proto_reg[index].strobe();
                ipv6_ext_size_reg[index].strobe();
                ipv6_ext_extent_size_reg[index].strobe();
                ipv6_ext_seen_reg[index].strobe();
                ipv6_fragment_reg[index].strobe();
                noninitial_fragment_reg[index].strobe();
            }
            source_port_reg.strobe();
            destination_port_reg.strobe(); tcp_header_bytes_reg.strobe();
            align_data_reg.strobe(); align_count_reg.strobe();
            raw_data_low_reg.strobe(); raw_data_high_reg.strobe();
            raw_word_count_reg.strobe();
            in_frame_reg.strobe(); frame_raw_reg.strobe();
            pending_valid_reg.strobe(); pending_rollover_reg.strobe();
            pending_data_reg.strobe(); pending_bytes_reg.strobe();
            pending_word_cntr_reg.strobe(); pending_sop_reg.strobe();
            pending_eop_reg.strobe(); align_word_cntr_reg.strobe();
            pending_raw_token_reg.strobe();
            align_sop_pending_reg.strobe();
            ingress_valid_reg.strobe(); ingress_data_reg.strobe();
            ingress_error_reg.strobe();
            decode_in_frame_reg.strobe(); decode_frame_raw_reg.strobe();
            for (index = 0; index < 2; ++index) {
                ingress_segment_valid_reg[index].strobe();
                ingress_segment_sop_reg[index].strobe();
                ingress_segment_eop_reg[index].strobe();
                ingress_segment_raw_reg[index].strobe();
                ingress_segment_start_reg[index].strobe();
                ingress_segment_bytes_reg[index].strobe();
                raw_emit_valid_reg[index].strobe();
                raw_emit_data_reg[index].strobe();
                raw_emit_bytes_reg[index].strobe();
                raw_emit_word_cntr_reg[index].strobe();
                raw_emit_sop_reg[index].strobe();
                raw_emit_eop_reg[index].strobe();
            }
            fifo_head_reg.strobe(); fifo_tail_reg.strobe();
            fifo_count_reg.strobe();
            reserved_slots_reg.strobe();
            raw_store_head_reg.strobe(); raw_store_tail_reg.strobe();
            raw_store_count_reg.strobe();
        for (stage = 0; stage < PIPE_STAGES; ++stage) {
            pipe_reg[stage].strobe();
            pipe_valid_reg[stage].strobe();
        }
        for (slot = 0; slot < 4; ++slot) {
            raw_store_low_reg[slot].strobe();
            raw_store_high_reg[slot].strobe();
            raw_store_count_bytes_reg[slot].strobe();
        }
        for (slot = 0; slot < OUTPUT_FIFO_WORDS; ++slot) {
            fifo_data_reg[slot].strobe();
            fifo_keep_reg[slot].strobe();
            fifo_last_reg[slot].strobe();
            fifo_raw_reg[slot].strobe();
        }
        protocol_error_reg.strobe();
    }
#endif

    void _strobe()
    {
        uint32_t slot;
        uint32_t stage;
        uint32_t index;
        state_reg.strobe(); pos_reg.strobe();
            word_cntr_reg.strobe(); ethernet_done_reg.strobe();
            error_reg.strobe(); limit_reg.strobe();
            done_reg.strobe();
            ethernet_progress_reg.strobe();
            for (index = 0; index < 4; ++index) {
                vlan_progress_reg[index].strobe();
                vlan_stage_index_reg[index].strobe();
            }
            for (index = 0; index < 4; ++index) {
                mpls_progress_reg[index].strobe();
                mpls_stage_index_reg[index].strobe();
            }
            ipv4_progress_reg.strobe();
            ipv4_options_progress_reg.strobe();
            ipv6_progress_reg.strobe();
            tcp_progress_reg.strobe();
            for (index = 0; index < 8; ++index) {
                ipv6_ext_progress_reg[index].strobe();
                ipv6_ext_stage_index_reg[index].strobe();
            }
            destination_mac_reg.strobe();
            source_mac_reg.strobe(); ethernet_type_reg.strobe();
            for (index = 0; index < 4; ++index)
                vlan_next_proto_reg[index].strobe();
            vlan_count_reg.strobe();
#if PACKET_PARSER_ENABLE_VLAN
            for (index = 0; index < PACKET_PARSER_OUTPUT_VLAN_HEADERS; ++index)
                vlan_tci_reg[index].strobe();
#endif
            for (index = 0; index < 4; ++index) {
                mpls_entry_reg[index].strobe();
                mpls_entry_done_reg[index].strobe();
            }
            mpls_count_reg.strobe();
#if PACKET_PARSER_ENABLE_MPLS
            for (index = 0; index < PACKET_PARSER_OUTPUT_MPLS_LABELS; ++index)
                mpls_output_reg[index].strobe();
#endif
            source_ip_reg.strobe(); destination_ip_reg.strobe();
            protocol_reg.strobe(); ip_version_reg.strobe();
            ip_header_bytes_reg.strobe(); transport_pos_reg.strobe();
            ipv4_fragment_reg.strobe(); initial_fragment_reg.strobe();
            ipv6_source_ip_reg.strobe(); ipv6_destination_ip_reg.strobe();
            ipv6_base_next_proto_reg.strobe(); ipv6_seen_reg.strobe();
            for (index = 0; index < 8; ++index) {
                ipv6_next_proto_reg[index].strobe();
                ipv6_ext_size_reg[index].strobe();
                ipv6_ext_extent_size_reg[index].strobe();
                ipv6_ext_seen_reg[index].strobe();
                ipv6_fragment_reg[index].strobe();
                noninitial_fragment_reg[index].strobe();
            }
            source_port_reg.strobe();
            destination_port_reg.strobe(); tcp_header_bytes_reg.strobe();
            align_data_reg.strobe(); align_count_reg.strobe();
            raw_data_low_reg.strobe(); raw_data_high_reg.strobe();
            raw_word_count_reg.strobe();
            in_frame_reg.strobe(); frame_raw_reg.strobe();
            pending_valid_reg.strobe(); pending_rollover_reg.strobe();
            pending_data_reg.strobe(); pending_bytes_reg.strobe();
            pending_word_cntr_reg.strobe(); pending_sop_reg.strobe();
            pending_eop_reg.strobe(); align_word_cntr_reg.strobe();
            pending_raw_token_reg.strobe();
            align_sop_pending_reg.strobe();
            ingress_valid_reg.strobe(); ingress_data_reg.strobe();
            ingress_error_reg.strobe();
            decode_in_frame_reg.strobe(); decode_frame_raw_reg.strobe();
            for (index = 0; index < 2; ++index) {
                ingress_segment_valid_reg[index].strobe();
                ingress_segment_sop_reg[index].strobe();
                ingress_segment_eop_reg[index].strobe();
                ingress_segment_raw_reg[index].strobe();
                ingress_segment_start_reg[index].strobe();
                ingress_segment_bytes_reg[index].strobe();
                raw_emit_valid_reg[index].strobe();
                raw_emit_data_reg[index].strobe();
                raw_emit_bytes_reg[index].strobe();
                raw_emit_word_cntr_reg[index].strobe();
                raw_emit_sop_reg[index].strobe();
                raw_emit_eop_reg[index].strobe();
            }
            fifo_head_reg.strobe(); fifo_tail_reg.strobe();
            fifo_count_reg.strobe();
            reserved_slots_reg.strobe();
            raw_store_head_reg.strobe(); raw_store_tail_reg.strobe();
            raw_store_count_reg.strobe();
        for (stage = 0; stage < PIPE_STAGES; ++stage) {
            pipe_reg[stage].strobe();
            pipe_valid_reg[stage].strobe();
        }
        for (slot = 0; slot < 4; ++slot) {
            raw_store_low_reg[slot].strobe();
            raw_store_high_reg[slot].strobe();
            raw_store_count_bytes_reg[slot].strobe();
        }
        for (slot = 0; slot < OUTPUT_FIFO_WORDS; ++slot) {
            fifo_data_reg[slot].strobe();
            fifo_keep_reg[slot].strobe();
            fifo_last_reg[slot].strobe();
            fifo_raw_reg[slot].strobe();
        }
        protocol_error_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class PacketParser<160>;
template class PacketParser<320>;

#undef PACKET_PARSER_FIELDS_USED_BITS
#undef PACKET_PARSER_FIELDS_RESERVED_BITS
#undef PACKET_PARSER_VLAN_OUTPUT_BITS
#undef PACKET_PARSER_MPLS_OUTPUT_BITS
