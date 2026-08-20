#pragma once

// Single-channel, on-the-fly Ethernet parser.  Network instantiates one parser
// per independent 10G receive channel.  Header-call markup is passed by
// value as {absolute byte position, one header ID per lane}.  It is never
// stored.  Runtime progress is held only in state_reg/pos_reg plus the small
// set of registers owned by each protocol parser.

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
static_assert(PACKET_PARSER_MAX_IPV6_EXTENSION_HEADERS == 4);

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
    logic<64> markup_state;
    PacketParserProgress progress;
} __PACKED;

// One aligned packet word and the parse result accumulated while that word
// crosses the protocol-family pipeline.  Fields are only snapshotted on EOP;
// carrying that snapshot with the last word lets a following packet enter the
// early stages without corrupting completion of the preceding packet.
struct PacketParserPipeWord
{
    logic<64> data;
    PacketParserFields fields;
    PacketParserProgress progress;
    u8 word_cntr;
    u<4> bytes;
    u<3> vlan_index;
    u<3> mpls_index;
    u<3> ipv6_ext_index;
    u1 raw;
    u1 sop;
    u1 eop;
} __PACKED;

template<size_t LANE_WIDTH = 64, bool ENABLE_RAW = true>
class PacketParser : public Module
{
public:
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t OUTPUT_WORD_BITS = 512;
    static constexpr size_t OUTPUT_BYTES = 64;
    static constexpr size_t OUTPUT_FIFO_WORDS = 4;
    static constexpr size_t RAW_BYTES = 128;
    static constexpr size_t RAW_STORE_WORDS = 2;
    static constexpr size_t MARKUP_BITS = LANE_BYTES * 8;
    // One registered boundary per protocol family. Repeated bounded headers
    // retain their explicit parse_vlan1..4/parse_mpls1..4 function calls and
    // execute in architectural order within the family stage.
    static constexpr size_t PIPE_STAGES = 6;

    static_assert(LANE_WIDTH == 64);

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
    reg<PacketParserProgress> ipv6_progress_reg;
    reg<PacketParserProgress> ipv6_ext_progress_reg[4];
    reg<u<3>> ipv6_ext_stage_index_reg[4];

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
    reg<u8> ipv6_next_proto_reg[4];
    reg<u8> ipv6_ext_size_reg[4];
    reg<u1> ipv6_ext_seen_reg[4];
    reg<u16> ipv6_fragment_reg[4];
    reg<u1> noninitial_fragment_reg[4];

    // Transport-owned registers.
    reg<u16> source_port_reg;
    reg<u16> destination_port_reg;
    reg<u8> tcp_header_bytes_reg;

    // Packet realignment and RAW capture.
    reg<logic<64>> align_data_reg;
    reg<u<4>> align_count_reg;
    reg<logic<OUTPUT_WORD_BITS>> raw_data_low_reg;
    reg<logic<OUTPUT_WORD_BITS>> raw_data_high_reg;
    reg<u8> raw_count_reg;
    reg<u<5>> raw_word_count_reg;
    reg<u1> in_frame_reg;
    reg<u1> frame_raw_reg;
    reg<u1> pending_valid_reg;
    reg<u1> pending_rollover_reg;
    reg<logic<64>> pending_data_reg;
    reg<u<4>> pending_bytes_reg;
    reg<u8> pending_word_cntr_reg;
    reg<u1> pending_sop_reg;
    reg<u1> pending_eop_reg;
    reg<u8> align_word_cntr_reg;
    reg<u1> align_sop_pending_reg;

    // 0: input, 1: Ethernet, 2: VLAN family, 3: MPLS family,
    // 4: IP family, 5: transport/completion input.
    reg<PacketParserPipeWord> pipe_reg[PIPE_STAGES];
    reg<u1> pipe_valid_reg[PIPE_STAGES];

    // RAW payloads wait here while a lightweight completion token traverses
    // the same pipeline as parsed EOPs, preserving descriptor order.
    reg<logic<OUTPUT_WORD_BITS>> raw_store_low_reg[RAW_STORE_WORDS];
    reg<logic<OUTPUT_WORD_BITS>> raw_store_high_reg[RAW_STORE_WORDS];
    reg<u8> raw_store_count_bytes_reg[RAW_STORE_WORDS];
    reg<u1> raw_store_head_reg;
    reg<u1> raw_store_tail_reg;
    reg<u<2>> raw_store_count_reg;

    reg<logic<OUTPUT_WORD_BITS>> fifo_data_reg[OUTPUT_FIFO_WORDS];
    reg<logic<OUTPUT_BYTES>> fifo_keep_reg[OUTPUT_FIFO_WORDS];
    reg<u1> fifo_last_reg[OUTPUT_FIFO_WORDS];
    reg<u1> fifo_raw_reg[OUTPUT_FIFO_WORDS];
    reg<u<2>> fifo_head_reg;
    reg<u<2>> fifo_tail_reg;
    reg<u<3>> fifo_count_reg;
    // FIFO words already present plus words promised by in-flight EOPs.
    // Keeping this as a registered credit count avoids a combinational scan
    // from every protocol stage back into the input realigner.
    reg<u<3>> output_reserved_reg;
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
        lane = markup_pos & (LANE_BYTES - 1);
        if (lane == 0) result.bits(7, 0) = u8(header_id);
        if (lane == 1) result.bits(15, 8) = u8(header_id);
        if (lane == 2) result.bits(23, 16) = u8(header_id);
        if (lane == 3) result.bits(31, 24) = u8(header_id);
        if (lane == 4) result.bits(39, 32) = u8(header_id);
        if (lane == 5) result.bits(47, 40) = u8(header_id);
        if (lane == 6) result.bits(55, 48) = u8(header_id);
        if (lane == 7) result.bits(63, 56) = u8(header_id);
        return result;
    }

    static uint8_t marked_header(const logic<MARKUP_BITS>& markup_state,
        uint8_t markup_pos)
    {
        uint8_t lane;
        uint8_t result;
        lane = markup_pos & (LANE_BYTES - 1);
        result = 0;
        if (lane == 0) result = (uint8_t)markup_state.bits(7, 0);
        if (lane == 1) result = (uint8_t)markup_state.bits(15, 8);
        if (lane == 2) result = (uint8_t)markup_state.bits(23, 16);
        if (lane == 3) result = (uint8_t)markup_state.bits(31, 24);
        if (lane == 4) result = (uint8_t)markup_state.bits(39, 32);
        if (lane == 5) result = (uint8_t)markup_state.bits(47, 40);
        if (lane == 6) result = (uint8_t)markup_state.bits(55, 48);
        if (lane == 7) result = (uint8_t)markup_state.bits(63, 56);
        return result;
    }

    static bool byte_present(uint8_t absolute, uint8_t word_cntr,
        uint8_t word_bytes)
    {
        uint8_t lane;
        // Packet words are aligned to byte zero. Splitting the absolute
        // offset into quotient/remainder implements offset/WORD_SIZE and
        // offset%WORD_SIZE without two full absolute-range comparisons.
        lane = absolute & (LANE_BYTES - 1);
        return (absolute >> 3) == word_cntr && lane < word_bytes;
    }

    static bool field_complete(uint8_t absolute, uint8_t bytes,
        uint8_t word_cntr, uint8_t word_bytes)
    {
        return byte_present((uint8_t)(absolute + bytes - 1),
            word_cntr, word_bytes);
    }

    static uint8_t word_byte(const logic<64>& word, uint8_t absolute)
    {
        uint8_t lane;
        lane = absolute & (LANE_BYTES - 1);
        return (uint8_t)word.bits(lane * 8 + 7, lane * 8);
    }

    static u8 capture_u8(const logic<64>& word, u8 previous,
        uint8_t absolute, uint8_t word_cntr, uint8_t word_bytes)
    {
        u8 result;
        result = previous;
        if (byte_present(absolute, word_cntr, word_bytes))
            result = u8(word_byte(word, absolute));
        return result;
    }

    static u16 capture_be16(const logic<64>& word, u16 previous,
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

    static u32 capture_be32(const logic<64>& word, u32 previous,
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

    static logic<48> capture_be48(const logic<64>& word, logic<48> previous,
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

    static logic<128> capture_be128(const logic<64>& word,
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
        return !(bool)progress.error
            && !(bool)progress.limit
            && !(bool)progress.done
            && (uint8_t)progress.state == header_id
            && (uint8_t)progress.pos == markup_pos
            && marked_header(markup_state, markup_pos) == header_id;
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
        ipv6_progress_reg._next = progress;
        for (index = 0; index < 4; ++index) {
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
        for (index = 0; index < 4; ++index) {
            ipv6_next_proto_reg[index]._next = 0;
            ipv6_ext_size_reg[index]._next = 0;
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
        if (!(bool)current.error && !(bool)current.limit
            && !(bool)current.done && state != PACKET_HEADER_VLAN
            && state != PACKET_HEADER_MPLS
            && state != PACKET_HEADER_IPV4
            && state != PACKET_HEADER_IPV4_OPTIONS
            && state != PACKET_HEADER_IPV6
            && state != PACKET_HEADER_IPV6_OPTIONS
            && state != PACKET_HEADER_TCP && state != PACKET_HEADER_UDP)
            return upstream;
        return accept_upstream(current, upstream);
    }

    static PacketParserProgress accept_mpls_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if (!(bool)current.error && !(bool)current.limit
            && !(bool)current.done && state != PACKET_HEADER_MPLS
            && state != PACKET_HEADER_IPV4
            && state != PACKET_HEADER_IPV4_OPTIONS
            && state != PACKET_HEADER_IPV6
            && state != PACKET_HEADER_IPV6_OPTIONS
            && state != PACKET_HEADER_TCP && state != PACKET_HEADER_UDP)
            return upstream;
        return accept_upstream(current, upstream);
    }

    static PacketParserProgress accept_ipv4_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if (!(bool)current.error && !(bool)current.limit
            && !(bool)current.done && state != PACKET_HEADER_IPV4
            && state != PACKET_HEADER_IPV4_OPTIONS
            && state != PACKET_HEADER_TCP && state != PACKET_HEADER_UDP)
            return upstream;
        return accept_upstream(current, upstream);
    }

    static PacketParserProgress accept_ipv6_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if (!(bool)current.error && !(bool)current.limit
            && !(bool)current.done && state != PACKET_HEADER_IPV6
            && state != PACKET_HEADER_IPV6_OPTIONS
            && state != PACKET_HEADER_TCP && state != PACKET_HEADER_UDP)
            return upstream;
        return accept_upstream(current, upstream);
    }

    static PacketParserProgress accept_ipv6_ext_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if (!(bool)current.error && !(bool)current.limit
            && !(bool)current.done && state != PACKET_HEADER_IPV6_OPTIONS
            && state != PACKET_HEADER_TCP && state != PACKET_HEADER_UDP)
            return upstream;
        return accept_upstream(current, upstream);
    }

    static PacketParserProgress accept_transport_upstream(
        PacketParserProgress current, PacketParserProgress upstream)
    {
        uint8_t state;
        state = (uint8_t)current.state;
        if (!(bool)current.error && !(bool)current.limit
            && !(bool)current.done && state != PACKET_HEADER_TCP
            && state != PACKET_HEADER_UDP)
            return upstream;
        return accept_upstream(current, upstream);
    }

    PacketParserCall vlan_work(uint8_t occurrence,
        uint8_t markup_pos,
        const logic<MARKUP_BITS>& markup_state,
        PacketParserProgress progress, const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint16_t selector;
        PacketParserCall call;
        call.markup_state = 0;
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
        PacketParserProgress progress, const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint32_t entry;
        uint8_t version;
        PacketParserCall call;
        call.markup_state = 0;
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
            version = word_byte(word, (uint8_t)(markup_pos + 4)) >> 4;
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

    PacketParserCall parse_tcp(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint8_t header_bytes;
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_TCP);
        call.markup_state = 0;
        call.progress = progress;
        if (!header_active(markup_pos, marked_state, PACKET_HEADER_TCP,
                progress))
            return call;
        source_port_reg._next = capture_be16(word,
            source_port_reg._next, markup_pos, word_cntr, word_bytes);
        destination_port_reg._next = capture_be16(word,
            destination_port_reg._next, (uint8_t)(markup_pos + 2),
            word_cntr, word_bytes);
        if (byte_present((uint8_t)(markup_pos + 12), word_cntr, word_bytes)) {
            header_bytes = (word_byte(word, (uint8_t)(markup_pos + 12)) >> 4) * 4;
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
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_UDP);
        call.markup_state = 0;
        call.progress = progress;
        if (!header_active(markup_pos, marked_state, PACKET_HEADER_UDP,
                progress))
            return call;
        source_port_reg._next = capture_be16(word,
            source_port_reg._next, markup_pos, word_cntr, word_bytes);
        destination_port_reg._next = capture_be16(word,
            destination_port_reg._next, (uint8_t)(markup_pos + 2),
            word_cntr, word_bytes);
        if (field_complete(markup_pos, 8, word_cntr, word_bytes)) {
            call.progress.state = PACKET_HEADER_NONE;
            call.progress.done = 1;
        }
        return call;
    }

    PacketParserCall parse_ipv4_options(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
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
        call.markup_state = 0;
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
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint8_t first;
        uint8_t header_bytes;
        uint16_t fragment;
        u32 address;
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_IPV4);
        call.markup_state = 0;
        call.progress = progress;
        if (header_active(markup_pos, marked_state, PACKET_HEADER_IPV4,
                progress)) {
            if (byte_present(markup_pos, word_cntr, word_bytes)) {
                first = word_byte(word, markup_pos);
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

    PacketParserCall ipv6_options_work(uint8_t occurrence,
        uint8_t markup_pos, const logic<MARKUP_BITS>& markup_state,
        PacketParserProgress progress, const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint8_t selector;
        uint8_t size;
        uint16_t fragment;
        PacketParserCall call;
        call.markup_state = 0;
        call.progress = progress;
        if (!header_active(markup_pos, markup_state,
                PACKET_HEADER_IPV6_OPTIONS, progress))
            return call;
        selector = (uint8_t)ipv6_next_proto_reg[occurrence]._next;
        if (byte_present(markup_pos, word_cntr, word_bytes))
            ipv6_next_proto_reg[occurrence]._next =
                u8(word_byte(word, markup_pos));
        if (byte_present((uint8_t)(markup_pos + 1), word_cntr, word_bytes)) {
            if (selector == 44) size = 8;
            else if (selector == 51)
                size = (word_byte(word, (uint8_t)(markup_pos + 1)) + 2) * 4;
            else
                size = (word_byte(word, (uint8_t)(markup_pos + 1)) + 1) * 8;
            ipv6_ext_size_reg[occurrence]._next = u8(size);
            if ((uint16_t)(markup_pos + size) > PACKET_PARSER_HEADER_BYTES)
                call.progress.limit = 1;
        }
        if (selector == 44) {
            ipv6_fragment_reg[occurrence]._next = capture_be16(word,
                ipv6_fragment_reg[occurrence]._next,
                (uint8_t)(markup_pos + 2),
                word_cntr, word_bytes);
            if (field_complete((uint8_t)(markup_pos + 2), 2,
                word_cntr, word_bytes)) {
                fragment = (uint16_t)ipv6_fragment_reg[occurrence]._next;
                if ((fragment & 0xfff8) != 0)
                    noninitial_fragment_reg[occurrence]._next = 1;
            }
        }
        size = (uint8_t)ipv6_ext_size_reg[occurrence]._next;
        if (size != 0 && field_complete(markup_pos, size,
            word_cntr, word_bytes)) {
            selector = (uint8_t)ipv6_next_proto_reg[occurrence]._next;
            if ((bool)noninitial_fragment_reg[occurrence]._next) {
                call.progress.state = PACKET_HEADER_NONE;
                call.progress.done = 1;
            }
            else if (is_ipv6_extension(selector)) {
                if (occurrence + 1 == PACKET_PARSER_MAX_IPV6_EXTENSION_HEADERS) {
                    call.progress.state = PACKET_HEADER_NONE;
                    call.progress.limit = 1;
                    call.progress.done = 1;
                }
                else {
                    call.progress.state = PACKET_HEADER_IPV6_OPTIONS;
                    call.progress.pos = u8(markup_pos + size);
                }
            }
            else {
                call.progress.pos = u8(markup_pos + size);
                call.progress.state = select_transport(selector);
                if ((uint8_t)call.progress.state == PACKET_HEADER_NONE)
                    call.progress.done = 1;
            }
        }
        return call;
    }

    PacketParserCall parse_ipv6_options4(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work(3, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_ipv6_options3(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work(2, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_ipv6_options2(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work(1, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_ipv6_options1(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos,
            PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work(0, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_ipv6(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        uint8_t first;
        uint8_t selector;
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_IPV6);
        call.markup_state = 0;
        call.progress = progress;
        if (header_active(markup_pos, marked_state, PACKET_HEADER_IPV6,
                progress)) {
            if (byte_present(markup_pos, word_cntr, word_bytes)) {
                first = word_byte(word, markup_pos);
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
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_MPLS);
        call = mpls_work(3, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_mpls3(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_MPLS);
        call = mpls_work(2, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_mpls2(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_MPLS);
        call = mpls_work(1, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_mpls1(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_MPLS);
        call = mpls_work(0, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_vlan4(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_VLAN);
        call = vlan_work(3, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_vlan3(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_VLAN);
        call = vlan_work(2, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_vlan2(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_VLAN);
        call = vlan_work(1, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_vlan1(uint8_t markup_pos,
        logic<MARKUP_BITS> markup_state, PacketParserProgress progress,
        const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr)
    {
        logic<MARKUP_BITS> marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PACKET_HEADER_VLAN);
        call = vlan_work(0, markup_pos, marked_state, progress,
            word, word_bytes, word_cntr);
        return call;
    }

    PacketParserCall parse_ethernet(PacketParserProgress progress,
        const logic<64>& word, uint8_t word_bytes, uint8_t word_cntr)
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
        for (index = 0; index < 4; ++index) {
            ipv6_next_proto_reg[index]._next = ipv6_next_proto_reg[index];
            ipv6_ext_size_reg[index]._next = ipv6_ext_size_reg[index];
            ipv6_ext_seen_reg[index]._next = ipv6_ext_seen_reg[index];
            ipv6_fragment_reg[index]._next = ipv6_fragment_reg[index];
            noninitial_fragment_reg[index]._next =
                noninitial_fragment_reg[index];
        }
        source_port_reg._next = source_port_reg;
        destination_port_reg._next = destination_port_reg;
        tcp_header_bytes_reg._next = tcp_header_bytes_reg;
    }

    PacketParserPipeWord ethernet_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.sop) {
            ethernet_done_reg._next = 0;
            destination_mac_reg._next = 0;
            source_mac_reg._next = 0;
            ethernet_type_reg._next = 0;
            progress = item.progress;
        }
        else progress = accept_upstream(ethernet_progress_reg, item.progress);
        call = parse_ethernet(progress, item.data, (uint8_t)item.bytes,
            (uint8_t)item.word_cntr);
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
        if ((bool)item.sop) {
            vlan_next_proto_reg[occurrence]._next = 0;
#if PACKET_PARSER_ENABLE_VLAN
            if (occurrence < PACKET_PARSER_OUTPUT_VLAN_HEADERS)
                vlan_tci_reg[occurrence]._next = 0;
#endif
            progress = item.progress;
            stage_index = 0;
            vlan_progress_reg[occurrence]._next = progress;
            vlan_stage_index_reg[occurrence]._next = 0;
            result.progress = progress;
            result.vlan_index = 0;
            return result;
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
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 1)
                call = parse_vlan2(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 2)
                call = parse_vlan3(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 3)
                call = parse_vlan4(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
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

    PacketParserPipeWord vlan1_stage(PacketParserPipeWord item)
    {
        return vlan_stage(0, item);
    }

    PacketParserPipeWord vlan2_stage(PacketParserPipeWord item)
    {
        return vlan_stage(1, item);
    }

    PacketParserPipeWord vlan3_stage(PacketParserPipeWord item)
    {
        return vlan_stage(2, item);
    }

    PacketParserPipeWord vlan4_stage(PacketParserPipeWord item)
    {
        return vlan_stage(3, item);
    }

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
        if ((bool)item.sop) {
            mpls_entry_reg[occurrence]._next = 0;
            mpls_entry_done_reg[occurrence]._next = 0;
#if PACKET_PARSER_ENABLE_MPLS
            if (occurrence < PACKET_PARSER_OUTPUT_MPLS_LABELS)
                mpls_output_reg[occurrence]._next = 0;
#endif
            progress = item.progress;
            stage_index = 0;
            mpls_progress_reg[occurrence]._next = progress;
            mpls_stage_index_reg[occurrence]._next = 0;
            result.progress = progress;
            result.mpls_index = 0;
            return result;
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
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 1)
                call = parse_mpls2(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 2)
                call = parse_mpls3(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 3)
                call = parse_mpls4(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
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

    PacketParserPipeWord mpls1_stage(PacketParserPipeWord item)
    {
        return mpls_stage(0, item);
    }

    PacketParserPipeWord mpls2_stage(PacketParserPipeWord item)
    {
        return mpls_stage(1, item);
    }

    PacketParserPipeWord mpls3_stage(PacketParserPipeWord item)
    {
        return mpls_stage(2, item);
    }

    PacketParserPipeWord mpls4_stage(PacketParserPipeWord item)
    {
        return mpls_stage(3, item);
    }

    PacketParserPipeWord ipv4_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        uint8_t flags;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
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
            ipv4_progress_reg._next = progress;
            result.progress = progress;
            return result;
        }
        else progress = accept_ipv4_upstream(ipv4_progress_reg,
            item.progress);
        markup_state = 0;

        markup_pos = (uint8_t)progress.pos;
        call = parse_ipv4(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.bytes, (uint8_t)item.word_cntr);
        progress = call.progress;
        markup_pos = (uint8_t)progress.pos;
        call = parse_ipv4_options(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.bytes, (uint8_t)item.word_cntr);
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

    PacketParserPipeWord ipv6_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        uint8_t flags;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.sop) {
            ipv6_source_ip_reg._next = 0;
            ipv6_destination_ip_reg._next = 0;
            ipv6_base_next_proto_reg._next = 0;
            ipv6_seen_reg._next = 0;
            progress = item.progress;
            ipv6_progress_reg._next = progress;
            result.progress = progress;
            return result;
        }
        else progress = accept_ipv6_upstream(ipv6_progress_reg,
            item.progress);
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        call = parse_ipv6(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.bytes, (uint8_t)item.word_cntr);
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

    PacketParserPipeWord ipv6_ext_stage(uint8_t occurrence,
        PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        uint8_t flags;
        uint8_t prior_state;
        uint8_t stage_index;
        uint8_t prior_pos;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.sop) {
            ipv6_next_proto_reg[occurrence]._next = 0;
            ipv6_ext_size_reg[occurrence]._next = 0;
            ipv6_ext_seen_reg[occurrence]._next = 0;
            ipv6_fragment_reg[occurrence]._next = 0;
            noninitial_fragment_reg[occurrence]._next = 0;
            progress = item.progress;
            prior_state = PACKET_HEADER_NONE;
            stage_index = 0;
            ipv6_ext_progress_reg[occurrence]._next = progress;
            ipv6_ext_stage_index_reg[occurrence]._next = 0;
            result.progress = progress;
            result.ipv6_ext_index = 0;
            return result;
        }
        else {
            progress = ipv6_ext_progress_reg[occurrence];
            prior_state = (uint8_t)progress.state;
            stage_index = (uint8_t)ipv6_ext_stage_index_reg[occurrence];
            if (stage_index < occurrence) {
                progress = item.progress;
                if ((uint8_t)item.ipv6_ext_index >= occurrence)
                    stage_index = occurrence;
            }
            else if (stage_index == occurrence)
                progress = accept_ipv6_ext_upstream(progress, item.progress);
        }
        if ((uint8_t)progress.state == PACKET_HEADER_IPV6_OPTIONS
            && stage_index == occurrence
            && (prior_state != PACKET_HEADER_IPV6_OPTIONS
                || !(bool)ipv6_ext_seen_reg[occurrence]._next)) {
            ipv6_next_proto_reg[occurrence]._next = item.fields.protocol;
            ipv6_ext_size_reg[occurrence]._next = 0;
            ipv6_fragment_reg[occurrence]._next = 0;
            noninitial_fragment_reg[occurrence]._next = 0;
            ipv6_ext_seen_reg[occurrence]._next = 1;
        }
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        prior_pos = markup_pos;
        if ((uint8_t)progress.state == PACKET_HEADER_IPV6_OPTIONS
            && stage_index == occurrence) {
            call.progress = progress;
            call.markup_state = 0;
            if (occurrence == 0)
                call = parse_ipv6_options1(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 1)
                call = parse_ipv6_options2(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 2)
                call = parse_ipv6_options3(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            if (occurrence == 3)
                call = parse_ipv6_options4(markup_pos, markup_state, progress,
                    item.data, (uint8_t)item.bytes,
                    (uint8_t)item.word_cntr);
            progress = call.progress;
            if ((uint8_t)progress.pos != prior_pos
                || (uint8_t)progress.state != PACKET_HEADER_IPV6_OPTIONS
                || (bool)progress.error || (bool)progress.limit
                || (bool)progress.done)
                stage_index = occurrence + 1;
        }
        ipv6_ext_progress_reg[occurrence]._next = progress;
        ipv6_ext_stage_index_reg[occurrence]._next = u<3>(stage_index);
        result.progress = progress;
        result.ipv6_ext_index = u<3>(stage_index);
        if ((bool)ipv6_ext_seen_reg[occurrence]._next)
            result.fields.protocol = ipv6_next_proto_reg[occurrence]._next;
        if ((bool)item.eop
            && (uint16_t)ipv6_fragment_reg[occurrence]._next != 0) {
            flags = (uint8_t)result.fields.flags;
            flags |= PACKET_PARSER_FLAG_FRAGMENT;
            result.fields.flags = u8(flags);
        }
        return result;
    }

    PacketParserPipeWord ipv6_ext1_stage(PacketParserPipeWord item)
    {
        return ipv6_ext_stage(0, item);
    }

    PacketParserPipeWord ipv6_ext2_stage(PacketParserPipeWord item)
    {
        return ipv6_ext_stage(1, item);
    }

    PacketParserPipeWord ipv6_ext3_stage(PacketParserPipeWord item)
    {
        return ipv6_ext_stage(2, item);
    }

    PacketParserPipeWord ipv6_ext4_stage(PacketParserPipeWord item)
    {
        return ipv6_ext_stage(3, item);
    }

    PacketParserPipeWord transport_stage(PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if ((bool)item.sop) {
            source_port_reg._next = 0;
            destination_port_reg._next = 0;
            tcp_header_bytes_reg._next = 0;
            progress = item.progress;
            state_reg._next = progress.state;
            pos_reg._next = progress.pos;
            error_reg._next = progress.error;
            limit_reg._next = progress.limit;
            done_reg._next = progress.done;
            word_cntr_reg._next = item.word_cntr;
            result.progress = progress;
            return result;
        }
        else {
            progress.state = state_reg;
            progress.pos = pos_reg;
            progress.error = error_reg;
            progress.limit = limit_reg;
            progress.done = done_reg;
            progress = accept_transport_upstream(progress, item.progress);
        }
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        call = parse_tcp(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.bytes, (uint8_t)item.word_cntr);
        progress = call.progress;
        markup_pos = (uint8_t)progress.pos;
        call = parse_udp(markup_pos, markup_state, progress,
            item.data, (uint8_t)item.bytes, (uint8_t)item.word_cntr);
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

    static logic<64> store_aligned_byte(logic<64> previous, u8 byte,
        uint8_t slot)
    {
        logic<64> result;
        result = previous;
        if (slot == 0) result.bits(7, 0) = byte;
        if (slot == 1) result.bits(15, 8) = byte;
        if (slot == 2) result.bits(23, 16) = byte;
        if (slot == 3) result.bits(31, 24) = byte;
        if (slot == 4) result.bits(39, 32) = byte;
        if (slot == 5) result.bits(47, 40) = byte;
        if (slot == 6) result.bits(55, 48) = byte;
        if (slot == 7) result.bits(63, 56) = byte;
        return result;
    }

    static logic<OUTPUT_WORD_BITS> store_raw_word(
        logic<OUTPUT_WORD_BITS> previous, const logic<64>& word,
        uint8_t slot, bool enable)
    {
        logic<OUTPUT_WORD_BITS> result;
        result = previous;
        if (enable && slot == 0) result.bits(63, 0) = word;
        if (enable && slot == 1) result.bits(127, 64) = word;
        if (enable && slot == 2) result.bits(191, 128) = word;
        if (enable && slot == 3) result.bits(255, 192) = word;
        if (enable && slot == 4) result.bits(319, 256) = word;
        if (enable && slot == 5) result.bits(383, 320) = word;
        if (enable && slot == 6) result.bits(447, 384) = word;
        if (enable && slot == 7) result.bits(511, 448) = word;
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
        count = (uint8_t)output_reserved_reg;
        if ((uint8_t)fifo_count_reg != 0 && ready_in()) --count;
        // Two free entries are reserved because a RAW frame emits two words.
        input_ready_comb = count <= OUTPUT_FIFO_WORDS - 2
            && !(bool)pending_valid_reg
            && (uint8_t)raw_store_count_reg < RAW_STORE_WORDS;
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

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
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
        uint8_t output_reserved;
        uint8_t align_count;
        uint8_t raw_count;
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
        bool end_raw;
        bool pending_valid;
        bool pending_rollover;
        bool parse_valid;
        bool consume_pending;
        uint8_t input_byte;
        uint8_t emit_bytes;
        uint8_t emit2_bytes;
        uint8_t pending_bytes;
        uint8_t parse_bytes;
        uint8_t parse_word_cntr;
        bool parse_sop;
        bool parse_eop;
        bool align_sop_pending;
        logic<64> align_data;
        logic<64> emit_data;
        logic<64> emit2_data;
        logic<64> pending_data;
        logic<64> parse_data;
        logic<OUTPUT_WORD_BITS> raw_data_low;
        logic<OUTPUT_WORD_BITS> raw_data_high;
        logic<OUTPUT_WORD_BITS> end_raw_data_low;
        logic<OUTPUT_WORD_BITS> end_raw_data_high;
        uint8_t end_raw_count;
        uint8_t end_raw_word_count;
        PacketParserWord parsed;
        PacketParserPipeWord pipe_item;
        PacketParserProgress empty_progress;

        if (reset) {
            reset_parser();
            align_data_reg._next = 0;
            align_count_reg._next = 0;
            raw_data_low_reg._next = 0;
            raw_data_high_reg._next = 0;
            raw_count_reg._next = 0;
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
            align_word_cntr_reg._next = 0;
            align_sop_pending_reg._next = 0;
            for (stage = 0; stage < PIPE_STAGES; ++stage) {
                pipe_reg[stage]._next = {};
                pipe_valid_reg[stage]._next = 0;
            }
            raw_store_head_reg._next = 0;
            raw_store_tail_reg._next = 0;
            raw_store_count_reg._next = 0;
            for (slot = 0; slot < RAW_STORE_WORDS; ++slot) {
                raw_store_low_reg[slot]._next = 0;
                raw_store_high_reg[slot]._next = 0;
                raw_store_count_bytes_reg[slot]._next = 0;
            }
            fifo_head_reg._next = 0;
            fifo_tail_reg._next = 0;
            fifo_count_reg._next = 0;
            output_reserved_reg._next = 0;
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
            ipv6_progress_reg._next = ipv6_progress_reg;
            for (stage = 0; stage < 4; ++stage) {
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
            for (slot = 0; slot < RAW_STORE_WORDS; ++slot) {
                raw_store_low_reg[slot]._next = raw_store_low_reg[slot];
                raw_store_high_reg[slot]._next = raw_store_high_reg[slot];
                raw_store_count_bytes_reg[slot]._next =
                    raw_store_count_bytes_reg[slot];
            }
            head = (uint8_t)fifo_head_reg;
            tail = (uint8_t)fifo_tail_reg;
            fifo_count = (uint8_t)fifo_count_reg;
            output_reserved = (uint8_t)output_reserved_reg;
            raw_store_head = (uint8_t)raw_store_head_reg;
            raw_store_tail = (uint8_t)raw_store_tail_reg;
            raw_store_count = (uint8_t)raw_store_count_reg;
            if (fifo_count != 0 && (bool)ready_in()) {
                head = (head + 1) & (OUTPUT_FIFO_WORDS - 1);
                --fifo_count;
                --output_reserved;
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
                                (uint8_t)raw_store_count_bytes_reg[
                                    raw_store_head], 0);
                            fifo_last_reg[tail]._next = 0;
                            fifo_raw_reg[tail]._next = 1;
                            tail = (tail + 1) & (OUTPUT_FIFO_WORDS - 1);
                            ++fifo_count;
                            fifo_data_reg[tail]._next =
                                raw_store_high_reg[raw_store_head];
                            fifo_keep_reg[tail]._next = raw_keep_word(
                                (uint8_t)raw_store_count_bytes_reg[
                                    raw_store_head], OUTPUT_BYTES);
                            fifo_last_reg[tail]._next = 1;
                            fifo_raw_reg[tail]._next = 1;
                            tail = (tail + 1) & (OUTPUT_FIFO_WORDS - 1);
                            ++fifo_count;
                            raw_store_head = (raw_store_head + 1)
                                & (RAW_STORE_WORDS - 1);
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
                            fifo_keep_reg[tail]._next =
                                ~logic<OUTPUT_BYTES>(0);
                            fifo_last_reg[tail]._next = 1;
                            fifo_raw_reg[tail]._next = 0;
                            tail = (tail + 1) & (OUTPUT_FIFO_WORDS - 1);
                            ++fifo_count;
                        }
                        else protocol_error_reg._next = 1;
                    }
                }
            }
            if ((bool)pipe_valid_reg[4]) {
                pipe_reg[5]._next = transport_stage(pipe_reg[4]);
                pipe_valid_reg[5]._next = 1;
            }
            if ((bool)pipe_valid_reg[3]) {
                pipe_item = ipv4_stage(pipe_reg[3]);
                pipe_item = ipv6_stage(pipe_item);
                pipe_item = ipv6_ext1_stage(pipe_item);
                pipe_item = ipv6_ext2_stage(pipe_item);
                pipe_item = ipv6_ext3_stage(pipe_item);
                pipe_item = ipv6_ext4_stage(pipe_item);
                pipe_reg[4]._next = pipe_item;
                pipe_valid_reg[4]._next = 1;
            }
            if ((bool)pipe_valid_reg[2]) {
                pipe_item = mpls1_stage(pipe_reg[2]);
                pipe_item = mpls2_stage(pipe_item);
                pipe_item = mpls3_stage(pipe_item);
                pipe_item = mpls4_stage(pipe_item);
                pipe_reg[3]._next = pipe_item;
                pipe_valid_reg[3]._next = 1;
            }
            if ((bool)pipe_valid_reg[1]) {
                pipe_item = vlan1_stage(pipe_reg[1]);
                pipe_item = vlan2_stage(pipe_item);
                pipe_item = vlan3_stage(pipe_item);
                pipe_item = vlan4_stage(pipe_item);
                pipe_reg[2]._next = pipe_item;
                pipe_valid_reg[2]._next = 1;
            }
            if ((bool)pipe_valid_reg[0]) {
                pipe_reg[1]._next = ethernet_stage(pipe_reg[0]);
                pipe_valid_reg[1]._next = 1;
            }
            align_data = align_data_reg;
            align_count = (uint8_t)align_count_reg;
            raw_data_low = raw_data_low_reg;
            raw_data_high = raw_data_high_reg;
            raw_count = (uint8_t)raw_count_reg;
            raw_word_count = (uint8_t)raw_word_count_reg;
            in_frame = (bool)in_frame_reg;
            frame_raw = (bool)frame_raw_reg;
            pending_valid = (bool)pending_valid_reg;
            pending_rollover = (bool)pending_rollover_reg;
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
            end_raw = frame_raw;
            end_raw_data_low = raw_data_low;
            end_raw_data_high = raw_data_high;
            end_raw_count = raw_count;
            end_raw_word_count = raw_word_count;

            if ((bool)valid_in() && (bool)input_ready_comb_func()) {
                for (lane = 0; lane < LANE_BYTES; ++lane) {
                    flat = lane;
                    keep = (bool)keep_in()[flat];
                    sop = (bool)sop_in()[flat];
                    eop = (bool)eop_in()[flat];
                    if (!keep) {
                        if (sop || eop) protocol_error_reg._next = 1;
                    }
                    else {
                        if (sop) {
                            if (in_frame) protocol_error_reg._next = 1;
                            if (frame_end) rollover = true;
                            if (!frame_end) {
                                end_raw_data_low = 0;
                                end_raw_data_high = 0;
                                end_raw_count = 0;
                                end_raw_word_count = 0;
                            }
                            align_data = 0;
                            align_count = 0;
                            raw_data_low = 0;
                            raw_data_high = 0;
                            raw_count = 0;
                            raw_word_count = 0;
                            align_word_cntr = 0;
                            align_sop_pending = true;
                            frame_raw = ENABLE_RAW && (bool)raw_in();
                            in_frame = true;
                        }
                        else if (!in_frame) protocol_error_reg._next = 1;

                        if (in_frame) {
                            input_byte = (uint8_t)data_in().bits(flat * 8 + 7,
                                flat * 8);
                            align_data = store_aligned_byte(align_data,
                                u8(input_byte), align_count);
                            ++align_count;
                            if (frame_raw && raw_count < RAW_BYTES) ++raw_count;
                            if (align_count == LANE_BYTES || eop) {
                                if (emit_valid) {
                                    if (eop) {
                                        emit2_valid = true;
                                        emit2_raw = frame_raw;
                                        emit2_bytes = align_count;
                                        emit2_data = align_data;
                                        emit2_word_cntr = align_word_cntr;
                                        emit2_sop = align_sop_pending;
                                        emit2_eop = eop;
                                        align_sop_pending = false;
                                        ++align_word_cntr;
                                        align_data = 0;
                                        align_count = 0;
                                    }
                                    else protocol_error_reg._next = 1;
                                }
                                else {
                                    emit_valid = true;
                                    emit_raw = frame_raw;
                                    emit_bytes = align_count;
                                    emit_data = align_data;
                                    emit_word_cntr = align_word_cntr;
                                    emit_sop = align_sop_pending;
                                    emit_eop = eop;
                                    align_sop_pending = false;
                                    ++align_word_cntr;
                                    align_data = 0;
                                    align_count = 0;
                                }
                            }
                            if (eop) {
                                end_raw = frame_raw;
                                end_raw_data_low = raw_data_low;
                                end_raw_data_high = raw_data_high;
                                end_raw_count = raw_count;
                                end_raw_word_count = raw_word_count;
                                if (frame_end) protocol_error_reg._next = 1;
                                frame_end = true;
                                in_frame = false;
                            }
                        }
                        else if (eop) protocol_error_reg._next = 1;
                    }
                }
            }

            consume_pending = pending_valid;
            parse_valid = consume_pending || (emit_valid && !emit_raw);
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
                pipe_item.bytes = u<4>(parse_bytes);
                pipe_item.sop = parse_sop;
                pipe_item.eop = parse_eop;
                pipe_reg[0]._next = pipe_item;
                pipe_valid_reg[0]._next = 1;
                if (parse_eop) ++output_reserved;
            }

            if (emit_valid && emit_raw
                && end_raw_word_count < RAW_BYTES / LANE_BYTES) {
                end_raw_data_low = store_raw_word(end_raw_data_low, emit_data,
                    end_raw_word_count,
                    end_raw_word_count < OUTPUT_BYTES / LANE_BYTES);
                end_raw_data_high = store_raw_word(end_raw_data_high, emit_data,
                    end_raw_word_count - OUTPUT_BYTES / LANE_BYTES,
                    end_raw_word_count >= OUTPUT_BYTES / LANE_BYTES);
                ++end_raw_word_count;
                if (!rollover) {
                    raw_data_low = end_raw_data_low;
                    raw_data_high = end_raw_data_high;
                    raw_word_count = end_raw_word_count;
                }
            }
            if (emit2_valid) {
                if (emit2_raw && end_raw_word_count < RAW_BYTES / LANE_BYTES) {
                    end_raw_data_low = store_raw_word(end_raw_data_low, emit2_data,
                        end_raw_word_count,
                        end_raw_word_count < OUTPUT_BYTES / LANE_BYTES);
                    end_raw_data_high = store_raw_word(end_raw_data_high, emit2_data,
                        end_raw_word_count - OUTPUT_BYTES / LANE_BYTES,
                        end_raw_word_count >= OUTPUT_BYTES / LANE_BYTES);
                    ++end_raw_word_count;
                    if (!rollover) {
                        raw_data_low = end_raw_data_low;
                        raw_data_high = end_raw_data_high;
                        raw_word_count = end_raw_word_count;
                    }
                }
                else if (!emit2_raw) {
                    pending_valid = true;
                    pending_data = emit2_data;
                    pending_bytes = emit2_bytes;
                    pending_rollover = rollover;
                    pending_word_cntr_reg._next = u8(emit2_word_cntr);
                    pending_sop_reg._next = emit2_sop;
                    pending_eop_reg._next = emit2_eop;
                    frame_end = false;
                }
            }

            if (consume_pending) {
                pending_valid = false;
                pending_rollover = false;
            }
            else if (frame_end) {
                if (end_raw) {
                    if (raw_store_count < RAW_STORE_WORDS && !parse_valid) {
                        raw_store_low_reg[raw_store_tail]._next =
                            end_raw_data_low;
                        raw_store_high_reg[raw_store_tail]._next =
                            end_raw_data_high;
                        raw_store_count_bytes_reg[raw_store_tail]._next =
                            u8(end_raw_count);
                        raw_store_tail = (raw_store_tail + 1)
                            & (RAW_STORE_WORDS - 1);
                        ++raw_store_count;

                        // RAW payload bypasses protocol logic, but its EOP
                        // token observes identical pipeline latency so that
                        // RAW and parsed descriptors cannot overtake.
                        empty_progress = {};
                        pipe_item = {};
                        pipe_item.progress = empty_progress;
                        pipe_item.raw = 1;
                        pipe_item.sop = 1;
                        pipe_item.eop = 1;
                        pipe_reg[0]._next = pipe_item;
                        pipe_valid_reg[0]._next = 1;
                        output_reserved += 2;
                    }
                    else protocol_error_reg._next = 1;
                }
            }

            align_data_reg._next = align_data;
            align_count_reg._next = u<4>(align_count);
            raw_data_low_reg._next = raw_data_low;
            raw_data_high_reg._next = raw_data_high;
            raw_count_reg._next = u8(raw_count);
            raw_word_count_reg._next = u<5>(raw_word_count);
            in_frame_reg._next = in_frame;
            frame_raw_reg._next = frame_raw;
            pending_valid_reg._next = pending_valid;
            pending_rollover_reg._next = pending_rollover;
            pending_data_reg._next = pending_data;
            pending_bytes_reg._next = u<4>(pending_bytes);
            if (!pending_valid) {
                pending_word_cntr_reg._next = 0;
                pending_sop_reg._next = 0;
                pending_eop_reg._next = 0;
            }
            align_word_cntr_reg._next = u8(align_word_cntr);
            align_sop_pending_reg._next = align_sop_pending;
            raw_store_head_reg._next = raw_store_head != 0;
            raw_store_tail_reg._next = raw_store_tail != 0;
            raw_store_count_reg._next = u<2>(raw_store_count);
            fifo_head_reg._next = u<2>(head);
            fifo_tail_reg._next = u<2>(tail);
            fifo_count_reg._next = u<3>(fifo_count);
            output_reserved_reg._next = u<3>(output_reserved);
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
            ipv4_progress_reg.strobe(); ipv6_progress_reg.strobe();
            for (index = 0; index < 4; ++index) {
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
            for (index = 0; index < 4; ++index) {
                ipv6_next_proto_reg[index].strobe();
                ipv6_ext_size_reg[index].strobe();
                ipv6_ext_seen_reg[index].strobe();
                ipv6_fragment_reg[index].strobe();
                noninitial_fragment_reg[index].strobe();
            }
            source_port_reg.strobe();
            destination_port_reg.strobe(); tcp_header_bytes_reg.strobe();
            align_data_reg.strobe(); align_count_reg.strobe();
            raw_data_low_reg.strobe(); raw_data_high_reg.strobe();
            raw_count_reg.strobe(); raw_word_count_reg.strobe();
            in_frame_reg.strobe(); frame_raw_reg.strobe();
            pending_valid_reg.strobe(); pending_rollover_reg.strobe();
            pending_data_reg.strobe(); pending_bytes_reg.strobe();
            pending_word_cntr_reg.strobe(); pending_sop_reg.strobe();
            pending_eop_reg.strobe(); align_word_cntr_reg.strobe();
            align_sop_pending_reg.strobe();
            raw_store_head_reg.strobe(); raw_store_tail_reg.strobe();
            raw_store_count_reg.strobe();
            fifo_head_reg.strobe(); fifo_tail_reg.strobe();
            fifo_count_reg.strobe();
            output_reserved_reg.strobe();
        for (stage = 0; stage < PIPE_STAGES; ++stage) {
            pipe_reg[stage].strobe();
            pipe_valid_reg[stage].strobe();
        }
        for (slot = 0; slot < RAW_STORE_WORDS; ++slot) {
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
            ipv4_progress_reg.strobe(); ipv6_progress_reg.strobe();
            for (index = 0; index < 4; ++index) {
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
            for (index = 0; index < 4; ++index) {
                ipv6_next_proto_reg[index].strobe();
                ipv6_ext_size_reg[index].strobe();
                ipv6_ext_seen_reg[index].strobe();
                ipv6_fragment_reg[index].strobe();
                noninitial_fragment_reg[index].strobe();
            }
            source_port_reg.strobe();
            destination_port_reg.strobe(); tcp_header_bytes_reg.strobe();
            align_data_reg.strobe(); align_count_reg.strobe();
            raw_data_low_reg.strobe(); raw_data_high_reg.strobe();
            raw_count_reg.strobe(); raw_word_count_reg.strobe();
            in_frame_reg.strobe(); frame_raw_reg.strobe();
            pending_valid_reg.strobe(); pending_rollover_reg.strobe();
            pending_data_reg.strobe(); pending_bytes_reg.strobe();
            pending_word_cntr_reg.strobe(); pending_sop_reg.strobe();
            pending_eop_reg.strobe(); align_word_cntr_reg.strobe();
            align_sop_pending_reg.strobe();
            raw_store_head_reg.strobe(); raw_store_tail_reg.strobe();
            raw_store_count_reg.strobe();
            fifo_head_reg.strobe(); fifo_tail_reg.strobe();
            fifo_count_reg.strobe();
            output_reserved_reg.strobe();
        for (stage = 0; stage < PIPE_STAGES; ++stage) {
            pipe_reg[stage].strobe();
            pipe_valid_reg[stage].strobe();
        }
        for (slot = 0; slot < RAW_STORE_WORDS; ++slot) {
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

template class PacketParser<64>;

#undef PACKET_PARSER_FIELDS_USED_BITS
#undef PACKET_PARSER_FIELDS_RESERVED_BITS
#undef PACKET_PARSER_VLAN_OUTPUT_BITS
#undef PACKET_PARSER_MPLS_OUTPUT_BITS
