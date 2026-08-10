#pragma once

// Bounded, eight-stream Ethernet/IP parser.  Input streams use the same packed
// data/keep/SOP/EOP convention as InputBalancer.  Every parsed packet produces
// one 64-byte record.  A packet sampled with raw_in set produces two 64-byte
// words containing the first 128 bytes of the original frame instead.

#include "../../config.h"
#include <cpphdl.h>

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

// ip_meta[3:0] is the IP version, [5:4] is the number of VLAN headers seen and
// [7:6] is the number of MPLS labels seen.  Counts saturate at three.  MPLS
// entries retain the complete wire-format 32-bit label/TC/BOS/TTL word.
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

using PacketParserOutputBus = array<8, PacketParserWord, true>;

static_assert(PACKET_PARSER_FIELDS_RESERVED_BITS > 0,
    "PacketParserFields configuration exceeds 512 bits");
static_assert(sizeof(PacketParserFields) == 64,
    "PacketParserFields must occupy exactly one 64-byte output word");
static_assert(sizeof(PacketParserWord) == 64,
    "PacketParserWord must occupy exactly one 64-byte output word");
static_assert(PACKET_PARSER_OUTPUT_VLAN_HEADERS <= 3,
    "the two-bit VLAN count supports at most three exported headers");
static_assert(PACKET_PARSER_OUTPUT_MPLS_LABELS <= 3,
    "the two-bit MPLS count supports at most three exported labels");
static_assert(PACKET_PARSER_HEADER_BYTES >= 128,
    "RAW mode requires at least a 128-byte header window");

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

struct PacketParserCursor
{
    PacketParserFields fields;
    u32 offset;
    u32 selector;
    u32 count;
    u1 noninitial_fragment;
    u1 ok;
} __PACKED;

template<size_t LANE_WIDTH = 160>
class PacketParser : public Module
{
public:
    static constexpr size_t STREAMS = 8;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t HEADER_BITS = PACKET_PARSER_HEADER_BYTES * 8;
    static constexpr size_t HEADER_COUNT_BITS = clog2(PACKET_PARSER_HEADER_BYTES + 1);
    static constexpr size_t FRAME_LENGTH_BITS = 14;
    static constexpr size_t OUTPUT_WORD_BITS = 512;
    static constexpr size_t OUTPUT_BYTES = 64;
    static constexpr size_t OUTPUT_FIFO_WORDS = 4;

    static_assert(LANE_WIDTH == 160 || LANE_WIDTH == 320,
        "PacketParser supports 160-bit and 320-bit streams");
    static_assert(PACKET_PARSER_MAX_IPV4_OPTION_BYTES <= 40,
        "IPv4 has at most 40 option bytes");
    static_assert(PACKET_PARSER_MAX_TCP_OPTION_BYTES <= 40,
        "TCP has at most 40 option bytes");

    _PORT(logic<STREAMS>) valid_in;
    _PORT(logic<INPUT_BITS>) data_in;
    _PORT(logic<INPUT_BYTES>) keep_in;
    _PORT(logic<INPUT_BYTES>) sop_in;
    _PORT(logic<INPUT_BYTES>) eop_in;
    _PORT(logic<STREAMS>) raw_in;
    _PORT(logic<STREAMS>) ready_out;

    _PORT(PacketParserOutputBus) data_out;
    _PORT(logic<STREAMS * OUTPUT_BYTES>) keep_out;
    _PORT(logic<STREAMS>) valid_out;
    _PORT(logic<STREAMS>) last_out;
    _PORT(logic<STREAMS>) raw_out;
    _PORT(logic<STREAMS>) ready_in;

    _PORT(bool) protocol_error_out;

private:
    reg<logic<HEADER_BITS>> aligned_header_reg[STREAMS];
    reg<u<HEADER_COUNT_BITS>> header_count_reg[STREAMS];
    reg<u<FRAME_LENGTH_BITS>> frame_length_reg[STREAMS];
    reg<u1> in_frame_reg[STREAMS];
    reg<u1> frame_raw_reg[STREAMS];
    reg<u1> header_truncated_reg[STREAMS];

    reg<logic<OUTPUT_WORD_BITS>> fifo_data_reg[STREAMS][OUTPUT_FIFO_WORDS];
    reg<logic<OUTPUT_BYTES>> fifo_keep_reg[STREAMS][OUTPUT_FIFO_WORDS];
    reg<u1> fifo_last_reg[STREAMS][OUTPUT_FIFO_WORDS];
    reg<u1> fifo_raw_reg[STREAMS][OUTPUT_FIFO_WORDS];
    reg<u<2>> fifo_head_reg[STREAMS];
    reg<u<2>> fifo_tail_reg[STREAMS];
    reg<u<3>> fifo_count_reg[STREAMS];
    reg<u1> protocol_error_reg;

    PacketParserOutputBus output_data_comb;
    logic<STREAMS * OUTPUT_BYTES> output_keep_comb;
    logic<STREAMS> output_valid_comb;
    logic<STREAMS> output_last_comb;
    logic<STREAMS> output_raw_comb;
    logic<STREAMS> input_ready_comb;

    static uint8_t get_byte(const logic<HEADER_BITS>& bytes, uint32_t offset)
    {
        return (uint8_t)bytes.bits(offset * 8 + 7, offset * 8);
    }

    static uint16_t get_be16(const logic<HEADER_BITS>& bytes, uint32_t offset)
    {
        return (uint16_t)(((uint16_t)get_byte(bytes, offset) << 8)
            | (uint16_t)get_byte(bytes, offset + 1));
    }

    static uint32_t get_be32(const logic<HEADER_BITS>& bytes, uint32_t offset)
    {
        return ((uint32_t)get_byte(bytes, offset) << 24)
            | ((uint32_t)get_byte(bytes, offset + 1) << 16)
            | ((uint32_t)get_byte(bytes, offset + 2) << 8)
            | (uint32_t)get_byte(bytes, offset + 3);
    }

    static logic<48> get_be48(const logic<HEADER_BITS>& bytes, uint32_t offset)
    {
        logic<48> value;
        uint32_t byte;
        value = 0;
        for (byte = 0; byte < 6; ++byte) {
            value = (value << 8) | logic<48>(get_byte(bytes, offset + byte));
        }
        return value;
    }

    static logic<128> get_be128(const logic<HEADER_BITS>& bytes, uint32_t offset)
    {
        logic<128> value;
        uint32_t byte;
        value = 0;
        for (byte = 0; byte < 16; ++byte) {
            value = (value << 8) | logic<128>(get_byte(bytes, offset + byte));
        }
        return value;
    }

    static bool range_valid(uint32_t offset, uint32_t bytes, uint32_t length)
    {
        return offset <= length && bytes <= length - offset
            && offset + bytes <= PACKET_PARSER_HEADER_BYTES;
    }

    static uint8_t saturating_count(uint32_t count)
    {
        return (uint8_t)(count > 3 ? 3 : count);
    }

    static PacketParserFields set_meta_counts(PacketParserFields fields,
        uint32_t version,
        uint32_t vlan_count, uint32_t mpls_count)
    {
        fields.ip_meta = u8((version & 0xf)
            | ((uint32_t)saturating_count(vlan_count) << 4)
            | ((uint32_t)saturating_count(mpls_count) << 6));
        return fields;
    }

    static PacketParserFields skip_ipv4_options(const logic<HEADER_BITS>& bytes,
        uint32_t length, uint32_t offset, uint32_t option_bytes,
        PacketParserFields fields)
    {
        if (option_bytes > PACKET_PARSER_MAX_IPV4_OPTION_BYTES) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_LIMIT);
            return fields;
        }
        if (!range_valid(offset, option_bytes, length)) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
            return fields;
        }
        return fields;
    }

    static PacketParserFields skip_tcp_options(const logic<HEADER_BITS>& bytes,
        uint32_t length, uint32_t offset, uint32_t option_bytes,
        PacketParserFields fields)
    {
        uint32_t cursor;
        uint32_t kind;
        uint32_t option_length;

        if (option_bytes > PACKET_PARSER_MAX_TCP_OPTION_BYTES) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_LIMIT);
            return fields;
        }
        if (!range_valid(offset, option_bytes, length)) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
            return fields;
        }
        cursor = 0;
        while (cursor < option_bytes) {
            kind = get_byte(bytes, offset + cursor);
            if (kind == 0) {
                cursor = option_bytes;
            }
            else if (kind == 1) {
                ++cursor;
            }
            else if (cursor + 1 >= option_bytes) {
                fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
                return fields;
            }
            else {
                option_length = get_byte(bytes, offset + cursor + 1);
                if (option_length < 2 || cursor + option_length > option_bytes) {
                    fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
                    return fields;
                }
                cursor += option_length;
            }
        }
        return fields;
    }

    static bool fields_ok(PacketParserFields fields)
    {
        return ((uint8_t)fields.flags
            & (PACKET_PARSER_FLAG_MALFORMED | PACKET_PARSER_FLAG_LIMIT)) == 0;
    }

    static PacketParserFields parse_transport(const logic<HEADER_BITS>& bytes,
        uint32_t length, uint32_t offset, uint32_t protocol,
        PacketParserFields fields)
    {
        uint32_t tcp_header_bytes;

        if (protocol != 6 && protocol != 17) {
            return fields;
        }
        if (!range_valid(offset, protocol == 6 ? 20 : 8, length)) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
            return fields;
        }
        fields.source_port = u16(get_be16(bytes, offset));
        fields.destination_port = u16(get_be16(bytes, offset + 2));
        if (protocol == 6) {
            tcp_header_bytes = (uint32_t)(get_byte(bytes, offset + 12) >> 4) * 4;
            if (tcp_header_bytes < 20) {
                fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
                return fields;
            }
            fields = skip_tcp_options(bytes, length, offset + 20,
                tcp_header_bytes - 20, fields);
            if (!fields_ok(fields)) {
                return fields;
            }
        }
        fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_TRANSPORT);
        return fields;
    }

    static PacketParserFields parse_ipv4(const logic<HEADER_BITS>& bytes,
        uint32_t length, uint32_t offset, PacketParserFields fields)
    {
        uint32_t header_bytes;
        uint32_t fragment;
        uint32_t protocol;

        if (!range_valid(offset, 20, length)
            || (get_byte(bytes, offset) >> 4) != 4) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
            return fields;
        }
        header_bytes = (uint32_t)(get_byte(bytes, offset) & 0xf) * 4;
        if (header_bytes < 20) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
            return fields;
        }
        fields = skip_ipv4_options(bytes, length, offset + 20,
            header_bytes - 20, fields);
        if (!fields_ok(fields)) {
            return fields;
        }
        fields.source_ip = logic<128>(get_be32(bytes, offset + 12));
        fields.destination_ip = logic<128>(get_be32(bytes, offset + 16));
        protocol = get_byte(bytes, offset + 9);
        fields.protocol = u8(protocol);
        fragment = get_be16(bytes, offset + 6);
        if ((fragment & 0x3fff) != 0) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_FRAGMENT);
        }
        // Only a zero-offset fragment can contain the transport header.
        if ((fragment & 0x1fff) == 0) {
            fields = parse_transport(bytes, length, offset + header_bytes,
                protocol, fields);
        }
        return fields;
    }

    static bool is_ipv6_extension(uint32_t next_header)
    {
        return next_header == 0 || next_header == 43 || next_header == 44
            || next_header == 51 || next_header == 60 || next_header == 135;
    }

    static PacketParserCursor skip_ipv6_options(const logic<HEADER_BITS>& bytes,
        uint32_t length, PacketParserCursor cursor)
    {
        uint32_t headers;
        uint32_t skipped;
        uint32_t extension_bytes;
        uint32_t fragment;

        headers = 0;
        skipped = 0;
        cursor.noninitial_fragment = 0;
        while (is_ipv6_extension((uint32_t)cursor.selector)) {
            if (headers >= PACKET_PARSER_MAX_IPV6_EXTENSION_HEADERS) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_LIMIT);
                cursor.ok = 0;
                return cursor;
            }
            if (!range_valid((uint32_t)cursor.offset, 8, length)) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_MALFORMED);
                cursor.ok = 0;
                return cursor;
            }
            if ((uint32_t)cursor.selector == 44) {
                extension_bytes = 8;
                fragment = get_be16(bytes, (uint32_t)cursor.offset + 2);
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_FRAGMENT);
                if ((fragment & 0xfff8) != 0) {
                    cursor.noninitial_fragment = 1;
                }
            }
            else if ((uint32_t)cursor.selector == 51) {
                extension_bytes = ((uint32_t)get_byte(bytes,
                    (uint32_t)cursor.offset + 1) + 2) * 4;
            }
            else {
                extension_bytes = ((uint32_t)get_byte(bytes,
                    (uint32_t)cursor.offset + 1) + 1) * 8;
            }
            if (skipped + extension_bytes > PACKET_PARSER_MAX_IPV6_EXTENSION_BYTES) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_LIMIT);
                cursor.ok = 0;
                return cursor;
            }
            if (!range_valid((uint32_t)cursor.offset, extension_bytes, length)) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_MALFORMED);
                cursor.ok = 0;
                return cursor;
            }
            cursor.selector = u32(get_byte(bytes, (uint32_t)cursor.offset));
            cursor.offset = u32((uint32_t)cursor.offset + extension_bytes);
            skipped += extension_bytes;
            ++headers;
        }
        return cursor;
    }

    static PacketParserFields parse_ipv6(const logic<HEADER_BITS>& bytes,
        uint32_t length, uint32_t offset, PacketParserFields fields)
    {
        PacketParserCursor cursor;

        if (!range_valid(offset, 40, length)
            || (get_byte(bytes, offset) >> 4) != 6) {
            fields.flags = u8((uint8_t)fields.flags | PACKET_PARSER_FLAG_MALFORMED);
            return fields;
        }
        fields.source_ip = get_be128(bytes, offset + 8);
        fields.destination_ip = get_be128(bytes, offset + 24);
        cursor = {};
        cursor.fields = fields;
        cursor.selector = u32(get_byte(bytes, offset + 6));
        cursor.offset = u32(offset + 40);
        cursor.ok = 1;
        cursor = skip_ipv6_options(bytes, length, cursor);
        fields = cursor.fields;
        if (!(bool)cursor.ok) {
            return fields;
        }
        fields.protocol = u8((uint32_t)cursor.selector);
        if (!(bool)cursor.noninitial_fragment) {
            fields = parse_transport(bytes, length, (uint32_t)cursor.offset,
                (uint32_t)cursor.selector, fields);
        }
        return fields;
    }

    static PacketParserCursor skip_vlan_headers(const logic<HEADER_BITS>& bytes,
        uint32_t length, PacketParserCursor cursor)
    {
        cursor.count = 0;
#if PACKET_PARSER_ENABLE_VLAN
        while ((uint32_t)cursor.selector == 0x8100
            || (uint32_t)cursor.selector == 0x88a8
            || (uint32_t)cursor.selector == 0x9100) {
            if ((uint32_t)cursor.count >= PACKET_PARSER_MAX_VLAN_HEADERS) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_LIMIT);
                cursor.ok = 0;
                return cursor;
            }
            if (!range_valid((uint32_t)cursor.offset, 4, length)) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_MALFORMED);
                cursor.ok = 0;
                return cursor;
            }
            if ((uint32_t)cursor.count < PACKET_PARSER_OUTPUT_VLAN_HEADERS) {
                cursor.fields.vlan_tci[(uint32_t)cursor.count] =
                    u16(get_be16(bytes, (uint32_t)cursor.offset));
            }
            cursor.selector = u32(get_be16(bytes, (uint32_t)cursor.offset + 2));
            cursor.offset = u32((uint32_t)cursor.offset + 4);
            cursor.count = u32((uint32_t)cursor.count + 1);
            cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_VLAN);
        }
#else
#endif
        return cursor;
    }

    static PacketParserCursor skip_mpls_headers(const logic<HEADER_BITS>& bytes,
        uint32_t length, PacketParserCursor cursor)
    {
        uint32_t entry;
        bool bottom;
        cursor.count = 0;
        bottom = false;
#if PACKET_PARSER_ENABLE_MPLS
        while (!bottom) {
            if ((uint32_t)cursor.count >= PACKET_PARSER_MAX_MPLS_LABELS) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_LIMIT);
                cursor.ok = 0;
                return cursor;
            }
            if (!range_valid((uint32_t)cursor.offset, 4, length)) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_MALFORMED);
                cursor.ok = 0;
                return cursor;
            }
            entry = get_be32(bytes, (uint32_t)cursor.offset);
            if ((uint32_t)cursor.count < PACKET_PARSER_OUTPUT_MPLS_LABELS) {
                cursor.fields.mpls[(uint32_t)cursor.count] = u32(entry);
            }
            bottom = (entry & 0x100) != 0;
            cursor.offset = u32((uint32_t)cursor.offset + 4);
            cursor.count = u32((uint32_t)cursor.count + 1);
            cursor.fields.flags = u8((uint8_t)cursor.fields.flags | PACKET_PARSER_FLAG_MPLS);
        }
#else
#endif
        return cursor;
    }

    PacketParserWord parse_frame(const logic<HEADER_BITS>& bytes,
        uint32_t length, bool truncated)
    {
        PacketParserWord word;
        PacketParserCursor cursor;
        uint32_t vlan_count;
        uint32_t mpls_count;
        uint32_t version;
        bool ok;

        word.raw = 0;
        word.fields = {};
        vlan_count = 0;
        mpls_count = 0;
        version = 0;
        ok = true;
        if (!range_valid(0, 14, length)) {
            word.fields.flags = u8((uint8_t)word.fields.flags
                | PACKET_PARSER_FLAG_MALFORMED);
            return word;
        }
        word.fields.destination_mac = get_be48(bytes, 0);
        word.fields.source_mac = get_be48(bytes, 6);
        cursor = {};
        cursor.fields = word.fields;
        cursor.offset = 14;
        cursor.selector = u32(get_be16(bytes, 12));
        cursor.ok = 1;
        cursor = skip_vlan_headers(bytes, length, cursor);
        vlan_count = (uint32_t)cursor.count;
        if ((bool)cursor.ok
            && ((uint32_t)cursor.selector == 0x8847
                || (uint32_t)cursor.selector == 0x8848)) {
            cursor = skip_mpls_headers(bytes, length, cursor);
            mpls_count = (uint32_t)cursor.count;
            if ((bool)cursor.ok
                && range_valid((uint32_t)cursor.offset, 1, length)) {
                version = get_byte(bytes, (uint32_t)cursor.offset) >> 4;
            }
            else if ((bool)cursor.ok) {
                cursor.fields.flags = u8((uint8_t)cursor.fields.flags
                    | PACKET_PARSER_FLAG_MALFORMED);
                cursor.ok = 0;
            }
        }
        else if ((uint32_t)cursor.selector == 0x0800) {
            version = 4;
        }
        else if ((uint32_t)cursor.selector == 0x86dd) {
            version = 6;
        }
        word.fields = cursor.fields;
        ok = (bool)cursor.ok;
        if (ok && version == 4) {
            word.fields = parse_ipv4(bytes, length, (uint32_t)cursor.offset,
                word.fields);
            ok = fields_ok(word.fields);
        }
        else if (ok && version == 6) {
            word.fields.flags = u8((uint8_t)word.fields.flags
                | PACKET_PARSER_FLAG_IPV6);
            word.fields = parse_ipv6(bytes, length, (uint32_t)cursor.offset,
                word.fields);
            ok = fields_ok(word.fields);
        }
        else if (ok) {
            word.fields.flags = u8((uint8_t)word.fields.flags
                | PACKET_PARSER_FLAG_MALFORMED);
            ok = false;
        }
        if (ok) {
            word.fields.flags = u8((uint8_t)word.fields.flags
                | PACKET_PARSER_FLAG_PARSED);
        }
        word.fields = set_meta_counts(word.fields, version,
            vlan_count, mpls_count);
        return word;
    }

    PacketParserOutputBus& output_data_comb_func()
    {
        uint32_t stream;
        uint32_t head;
        PacketParserWord word;
        head = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            word.raw = 0;
            if ((uint32_t)fifo_count_reg[stream] != 0) {
                head = (uint32_t)fifo_head_reg[stream];
                word.raw = fifo_data_reg[stream][head];
            }
            output_data_comb[stream] = word;
        }
        return output_data_comb;
    }

    logic<STREAMS * OUTPUT_BYTES>& output_keep_comb_func()
    {
        uint32_t stream;
        uint32_t byte;
        uint32_t head;
        head = 0;
        output_keep_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            if ((uint32_t)fifo_count_reg[stream] != 0) {
                head = (uint32_t)fifo_head_reg[stream];
                for (byte = 0; byte < OUTPUT_BYTES; ++byte) {
                    output_keep_comb[stream * OUTPUT_BYTES + byte] =
                        fifo_keep_reg[stream][head][byte];
                }
            }
        }
        return output_keep_comb;
    }

    logic<STREAMS>& output_valid_comb_func()
    {
        uint32_t stream;
        output_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            output_valid_comb[stream] = (uint32_t)fifo_count_reg[stream] != 0;
        }
        return output_valid_comb;
    }

    logic<STREAMS>& output_last_comb_func()
    {
        uint32_t stream;
        uint32_t head;
        head = 0;
        output_last_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            if ((uint32_t)fifo_count_reg[stream] != 0) {
                head = (uint32_t)fifo_head_reg[stream];
                output_last_comb[stream] = fifo_last_reg[stream][head];
            }
        }
        return output_last_comb;
    }

    logic<STREAMS>& output_raw_comb_func()
    {
        uint32_t stream;
        uint32_t head;
        head = 0;
        output_raw_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            if ((uint32_t)fifo_count_reg[stream] != 0) {
                head = (uint32_t)fifo_head_reg[stream];
                output_raw_comb[stream] = fifo_raw_reg[stream][head];
            }
        }
        return output_raw_comb;
    }

    logic<STREAMS>& input_ready_comb_func()
    {
        uint32_t stream;
        uint32_t count;
        input_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            count = (uint32_t)fifo_count_reg[stream];
            if (count != 0 && (bool)ready_in()[stream]) {
                --count;
            }
            // Reserve two slots because RAW mode completes with two words.
            input_ready_comb[stream] = count <= OUTPUT_FIFO_WORDS - 2;
        }
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
        uint32_t stream;
        uint32_t slot;
        uint32_t byte;
        uint32_t bit;
        uint32_t flat;
        uint32_t head;
        uint32_t tail;
        uint32_t fifo_count;
        uint32_t header_count;
        uint32_t frame_length;
        uint32_t raw_word;
        uint32_t raw_byte;
        bool in_frame;
        bool frame_raw;
        bool header_truncated;
        bool keep;
        bool sop;
        bool eop;
        uint8_t input_byte;
        PacketParserWord parsed;
        logic<OUTPUT_WORD_BITS> raw_data;
        logic<OUTPUT_BYTES> raw_keep;

        if (reset) {
            for (stream = 0; stream < STREAMS; ++stream) {
                aligned_header_reg[stream]._next = 0;
                header_count_reg[stream]._next = 0;
                frame_length_reg[stream]._next = 0;
                in_frame_reg[stream]._next = 0;
                frame_raw_reg[stream]._next = 0;
                header_truncated_reg[stream]._next = 0;
                fifo_head_reg[stream]._next = 0;
                fifo_tail_reg[stream]._next = 0;
                fifo_count_reg[stream]._next = 0;
                for (slot = 0; slot < OUTPUT_FIFO_WORDS; ++slot) {
                    fifo_data_reg[stream][slot]._next = 0;
                    fifo_keep_reg[stream][slot]._next = 0;
                    fifo_last_reg[stream][slot]._next = 0;
                    fifo_raw_reg[stream][slot]._next = 0;
                }
            }
            protocol_error_reg._next = 0;
            return;
        }

        for (stream = 0; stream < STREAMS; ++stream) {
            aligned_header_reg[stream]._next = aligned_header_reg[stream];
            header_count_reg[stream]._next = header_count_reg[stream];
            frame_length_reg[stream]._next = frame_length_reg[stream];
            in_frame_reg[stream]._next = in_frame_reg[stream];
            frame_raw_reg[stream]._next = frame_raw_reg[stream];
            header_truncated_reg[stream]._next = header_truncated_reg[stream];
            for (slot = 0; slot < OUTPUT_FIFO_WORDS; ++slot) {
                fifo_data_reg[stream][slot]._next = fifo_data_reg[stream][slot];
                fifo_keep_reg[stream][slot]._next = fifo_keep_reg[stream][slot];
                fifo_last_reg[stream][slot]._next = fifo_last_reg[stream][slot];
                fifo_raw_reg[stream][slot]._next = fifo_raw_reg[stream][slot];
            }

            head = (uint32_t)fifo_head_reg[stream];
            tail = (uint32_t)fifo_tail_reg[stream];
            fifo_count = (uint32_t)fifo_count_reg[stream];
            if (fifo_count != 0 && (bool)ready_in()[stream]) {
                head = (head + 1) & (OUTPUT_FIFO_WORDS - 1);
                --fifo_count;
            }

            header_count = (uint32_t)header_count_reg[stream];
            frame_length = (uint32_t)frame_length_reg[stream];
            in_frame = (bool)in_frame_reg[stream];
            frame_raw = (bool)frame_raw_reg[stream];
            header_truncated = (bool)header_truncated_reg[stream];

            if ((bool)valid_in()[stream] && (bool)input_ready_comb_func()[stream]) {
                for (byte = 0; byte < LANE_BYTES; ++byte) {
                    flat = stream * LANE_BYTES + byte;
                    keep = (bool)keep_in()[flat];
                    sop = (bool)sop_in()[flat];
                    eop = (bool)eop_in()[flat];
                    if (!keep) {
                        if (sop || eop) {
                            protocol_error_reg._next = 1;
                        }
                    }
                    else {
                        if (sop) {
                            if (in_frame) {
                                protocol_error_reg._next = 1;
                            }
                            // Realignment stage: irrespective of the input SOP
                            // byte position, the first frame byte is written to
                            // aligned_header[7:0].
                            aligned_header_reg[stream]._next = 0;
                            header_count = 0;
                            frame_length = 0;
                            header_truncated = false;
                            frame_raw = (bool)raw_in()[stream];
                            in_frame = true;
                        }
                        else if (!in_frame) {
                            protocol_error_reg._next = 1;
                        }
                        if (in_frame) {
                            input_byte = (uint8_t)data_in().bits(flat * 8 + 7, flat * 8);
                            if (header_count < PACKET_PARSER_HEADER_BYTES) {
                                for (bit = 0; bit < 8; ++bit) {
                                    aligned_header_reg[stream]._next[header_count * 8 + bit] =
                                        (input_byte >> bit) & 1;
                                }
                                ++header_count;
                            }
                            else {
                                header_truncated = true;
                            }
                            if (frame_length != (1u << FRAME_LENGTH_BITS) - 1) {
                                ++frame_length;
                            }

                            if (eop) {
                                if (frame_raw) {
                                    for (raw_word = 0; raw_word < 2; ++raw_word) {
                                        raw_data = 0;
                                        raw_keep = 0;
                                        for (raw_byte = 0; raw_byte < OUTPUT_BYTES; ++raw_byte) {
                                            if (raw_word * OUTPUT_BYTES + raw_byte < header_count) {
                                                input_byte = get_byte(aligned_header_reg[stream]._next,
                                                    raw_word * OUTPUT_BYTES + raw_byte);
                                                raw_data.bits(raw_byte * 8 + 7, raw_byte * 8) = input_byte;
                                                raw_keep[raw_byte] = 1;
                                            }
                                        }
                                        fifo_data_reg[stream][tail]._next = raw_data;
                                        fifo_keep_reg[stream][tail]._next = raw_keep;
                                        fifo_last_reg[stream][tail]._next = raw_word == 1;
                                        fifo_raw_reg[stream][tail]._next = 1;
                                        tail = (tail + 1) & (OUTPUT_FIFO_WORDS - 1);
                                        ++fifo_count;
                                    }
                                }
                                else {
                                    parsed = parse_frame(aligned_header_reg[stream]._next,
                                        frame_length, header_truncated);
                                    fifo_data_reg[stream][tail]._next = parsed.raw;
                                    fifo_keep_reg[stream][tail]._next = ~logic<OUTPUT_BYTES>(0);
                                    fifo_last_reg[stream][tail]._next = 1;
                                    fifo_raw_reg[stream][tail]._next = 0;
                                    tail = (tail + 1) & (OUTPUT_FIFO_WORDS - 1);
                                    ++fifo_count;
                                }
                                in_frame = false;
                            }
                            else if (eop) {
                                protocol_error_reg._next = 1;
                            }
                        }
                        else if (eop) {
                            protocol_error_reg._next = 1;
                        }
                    }
                }
            }

            header_count_reg[stream]._next = u<HEADER_COUNT_BITS>(header_count);
            frame_length_reg[stream]._next = u<FRAME_LENGTH_BITS>(frame_length);
            in_frame_reg[stream]._next = in_frame;
            frame_raw_reg[stream]._next = frame_raw;
            header_truncated_reg[stream]._next = header_truncated;
            fifo_head_reg[stream]._next = u<2>(head);
            fifo_tail_reg[stream]._next = u<2>(tail);
            fifo_count_reg[stream]._next = u<3>(fifo_count);
        }
    }

    void _strobe()
    {
        uint32_t stream;
        uint32_t slot;
        for (stream = 0; stream < STREAMS; ++stream) {
            aligned_header_reg[stream].strobe();
            header_count_reg[stream].strobe();
            frame_length_reg[stream].strobe();
            in_frame_reg[stream].strobe();
            frame_raw_reg[stream].strobe();
            header_truncated_reg[stream].strobe();
            fifo_head_reg[stream].strobe();
            fifo_tail_reg[stream].strobe();
            fifo_count_reg[stream].strobe();
            for (slot = 0; slot < OUTPUT_FIFO_WORDS; ++slot) {
                fifo_data_reg[stream][slot].strobe();
                fifo_keep_reg[stream][slot].strobe();
                fifo_last_reg[stream][slot].strobe();
                fifo_raw_reg[stream][slot].strobe();
            }
        }
        protocol_error_reg.strobe();
    }
};

template class PacketParser<160>;
template class PacketParser<320>;

#undef PACKET_PARSER_FIELDS_USED_BITS
#undef PACKET_PARSER_FIELDS_RESERVED_BITS
#undef PACKET_PARSER_VLAN_OUTPUT_BITS
#undef PACKET_PARSER_MPLS_OUTPUT_BITS
