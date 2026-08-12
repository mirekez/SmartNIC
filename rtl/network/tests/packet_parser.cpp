// Native CppHDL and generated-SystemVerilog/Verilator tests for PacketParser.
// Packet construction is a recursive fold of Ethernet, VLAN, MPLS, IP,
// extension/option and transport layers.  Eight independent byte timelines use
// unrelated initial offsets and IPGs so SOP/EOP exercise every lane position.

#include "../PacketParser.h"

#if !defined(SYNTHESIS)

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <iostream>
#include <print>
#include <string>
#include <vector>

#include "../../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define MAKE_HEADER(name) STRINGIFY(name.h)
#include MAKE_HEADER(VERILATOR_MODEL)
#endif

long _system_clock = -1;

struct WireByte
{
    uint8_t data = 0;
    bool keep = false;
    bool sop = false;
    bool eop = false;
    bool raw = false;
};

struct ExpectedWord
{
    logic<512> data;
    logic<64> keep;
    bool last = false;
    bool raw = false;
    std::string name;
};

struct PacketCase
{
    std::vector<uint8_t> frame;
    PacketParserFields fields{};
    bool raw = false;
    std::string name;
};

static void append_be16(std::vector<uint8_t>& bytes, uint16_t value)
{
    bytes.push_back((uint8_t)(value >> 8));
    bytes.push_back((uint8_t)value);
}

static void append_be32(std::vector<uint8_t>& bytes, uint32_t value)
{
    bytes.push_back((uint8_t)(value >> 24));
    bytes.push_back((uint8_t)(value >> 16));
    bytes.push_back((uint8_t)(value >> 8));
    bytes.push_back((uint8_t)value);
}

static logic<128> ipv6_value(const std::array<uint8_t, 16>& bytes)
{
    logic<128> value = 0;
    for (uint8_t byte : bytes) {
        value = (value << 8) | logic<128>(byte);
    }
    return value;
}

static std::vector<uint8_t> fold_layers(
    const std::vector<std::vector<uint8_t>>& layers, size_t index,
    const std::vector<uint8_t>& payload)
{
    if (index == layers.size()) {
        return payload;
    }
    std::vector<uint8_t> result = layers[index];
    std::vector<uint8_t> inner = fold_layers(layers, index + 1, payload);
    result.insert(result.end(), inner.begin(), inner.end());
    return result;
}

static std::vector<uint8_t> make_transport(bool tcp, uint16_t source_port,
    uint16_t destination_port, bool options, uint32_t seed)
{
    std::vector<uint8_t> header;
    append_be16(header, source_port);
    append_be16(header, destination_port);
    if (tcp) {
        append_be32(header, 0x10203040u ^ seed);
        append_be32(header, 0x50607080u ^ (seed << 1));
        const std::vector<uint8_t> tcp_options = options
            ? std::vector<uint8_t>{1, 1, 2, 4, 0x05, 0xb4, 3, 3, 7, 0, 0, 0}
            : std::vector<uint8_t>{};
        header.push_back((uint8_t)(((20 + tcp_options.size()) / 4) << 4));
        header.push_back(0x18);
        append_be16(header, 0x4000);
        append_be16(header, 0);
        append_be16(header, 0);
        header.insert(header.end(), tcp_options.begin(), tcp_options.end());
    }
    else {
        append_be16(header, 8 + 48);
        append_be16(header, 0);
    }
    return header;
}

static PacketCase make_packet(uint32_t id, bool ipv6, bool tcp,
    uint32_t vlan_count, uint32_t mpls_count, bool ip_options,
    bool transport_options, bool ipv6_extensions, bool raw)
{
    const uint64_t destination_mac = 0x020000000000ull | id;
    const uint64_t source_mac = 0x0a0000000000ull | (id * 3);
    const uint16_t source_port = (uint16_t)(1000 + id);
    const uint16_t destination_port = (uint16_t)(40000 + id);
    const uint8_t protocol = tcp ? 6 : 17;
    std::array<uint8_t, 16> source_ipv6{};
    std::array<uint8_t, 16> destination_ipv6{};
    std::vector<std::vector<uint8_t>> layers;
    std::vector<uint8_t> ethernet;
    std::vector<uint8_t> payload(48);
    PacketCase packet;

    for (size_t i = 0; i < payload.size(); ++i) {
        payload[i] = (uint8_t)(id * 29 + i * 17);
    }
    for (int shift = 40; shift >= 0; shift -= 8) {
        ethernet.push_back((uint8_t)(destination_mac >> shift));
    }
    for (int shift = 40; shift >= 0; shift -= 8) {
        ethernet.push_back((uint8_t)(source_mac >> shift));
    }
    const uint16_t network_type = mpls_count != 0 ? 0x8847 : (ipv6 ? 0x86dd : 0x0800);
    append_be16(ethernet, vlan_count != 0 ? 0x88a8 : network_type);
    layers.push_back(ethernet);

    for (uint32_t vlan = 0; vlan < vlan_count; ++vlan) {
        std::vector<uint8_t> header;
        append_be16(header, (uint16_t)(0x100 + id + vlan * 0x111));
        append_be16(header, vlan + 1 == vlan_count ? network_type : 0x8100);
        layers.push_back(header);
    }
    for (uint32_t label = 0; label < mpls_count; ++label) {
        uint32_t entry = ((0x12000u + id * 4 + label) << 12)
            | ((label & 7) << 9) | ((label + 1 == mpls_count) ? 0x100 : 0)
            | (0x40 + label);
        std::vector<uint8_t> header;
        append_be32(header, entry);
        layers.push_back(header);
    }

    std::vector<uint8_t> transport = make_transport(tcp, source_port,
        destination_port, transport_options, id);
    std::vector<std::vector<uint8_t>> extension_layers;
    uint8_t ipv6_first_next = protocol;
    if (ipv6 && ipv6_extensions) {
        // Hop-by-hop -> routing -> destination -> AH -> TCP/UDP.
        extension_layers = {
            {43, 0, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16},
            {60, 0, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26},
            {51, 0, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36},
            {protocol, 1, 0, 0, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48}};
        ipv6_first_next = 0;
    }

    if (!ipv6) {
        const size_t option_bytes = ip_options ? 12 : 0;
        std::vector<uint8_t> ip(20 + option_bytes, 0);
        ip[0] = (uint8_t)(0x40 | ((20 + option_bytes) / 4));
        const uint16_t total_length = (uint16_t)(ip.size() + transport.size() + payload.size());
        ip[2] = (uint8_t)(total_length >> 8);
        ip[3] = (uint8_t)total_length;
        ip[4] = (uint8_t)(id >> 8);
        ip[5] = (uint8_t)id;
        ip[8] = 64;
        ip[9] = protocol;
        const uint32_t source_ip = 0x0a000000u | (id & 0xffff);
        const uint32_t destination_ip = 0xc0000200u | (id & 0xff);
        ip[12] = (uint8_t)(source_ip >> 24);
        ip[13] = (uint8_t)(source_ip >> 16);
        ip[14] = (uint8_t)(source_ip >> 8);
        ip[15] = (uint8_t)source_ip;
        ip[16] = (uint8_t)(destination_ip >> 24);
        ip[17] = (uint8_t)(destination_ip >> 16);
        ip[18] = (uint8_t)(destination_ip >> 8);
        ip[19] = (uint8_t)destination_ip;
        for (size_t i = 0; i < option_bytes; ++i) {
            ip[20 + i] = i == 0 ? 1 : (i == 1 ? 0 : 0);
        }
        layers.push_back(ip);
        packet.fields.source_ip = logic<128>(source_ip);
        packet.fields.destination_ip = logic<128>(destination_ip);
    }
    else {
        for (size_t i = 0; i < 16; ++i) {
            source_ipv6[i] = (uint8_t)(i == 0 ? 0x20 : (i == 1 ? 0x01 : id + i));
            destination_ipv6[i] = (uint8_t)(i == 0 ? 0x20 : (i == 1 ? 0x01 : 0x80 + id + i));
        }
        size_t extension_bytes = 0;
        for (const auto& extension : extension_layers) {
            extension_bytes += extension.size();
        }
        std::vector<uint8_t> ip(40, 0);
        ip[0] = 0x60;
        const uint16_t payload_length = (uint16_t)(extension_bytes + transport.size() + payload.size());
        ip[4] = (uint8_t)(payload_length >> 8);
        ip[5] = (uint8_t)payload_length;
        ip[6] = ipv6_first_next;
        ip[7] = 64;
        std::copy(source_ipv6.begin(), source_ipv6.end(), ip.begin() + 8);
        std::copy(destination_ipv6.begin(), destination_ipv6.end(), ip.begin() + 24);
        layers.push_back(ip);
        layers.insert(layers.end(), extension_layers.begin(), extension_layers.end());
        packet.fields.source_ip = ipv6_value(source_ipv6);
        packet.fields.destination_ip = ipv6_value(destination_ipv6);
    }
    layers.push_back(transport);
    packet.frame = fold_layers(layers, 0, payload);
    packet.raw = raw;
    packet.name = std::format("id-{}-{}-{}-vlan{}-mpls{}{}{}{}", id,
        ipv6 ? "ipv6" : "ipv4", tcp ? "tcp" : "udp", vlan_count,
        mpls_count, ip_options ? "-ipopt" : "",
        transport_options ? "-tcpopt" : "",
        ipv6_extensions ? "-ext" : "", raw ? "-raw" : "");

    packet.fields.destination_mac = logic<48>(destination_mac);
    packet.fields.source_mac = logic<48>(source_mac);
    packet.fields.source_port = u16(source_port);
    packet.fields.destination_port = u16(destination_port);
    packet.fields.protocol = u8(protocol);
    uint8_t flags = PACKET_PARSER_FLAG_PARSED | PACKET_PARSER_FLAG_TRANSPORT;
    if (ipv6) flags |= PACKET_PARSER_FLAG_IPV6;
    if (vlan_count != 0) flags |= PACKET_PARSER_FLAG_VLAN;
    if (mpls_count != 0) flags |= PACKET_PARSER_FLAG_MPLS;
    packet.fields.flags = u8(flags);
    packet.fields.ip_meta = u8((ipv6 ? 6 : 4)
        | (std::min(vlan_count, 3u) << 4)
        | (std::min(mpls_count, 3u) << 6));
#if PACKET_PARSER_ENABLE_VLAN
    for (uint32_t i = 0; i < std::min(vlan_count,
             (uint32_t)PACKET_PARSER_OUTPUT_VLAN_HEADERS); ++i) {
        packet.fields.vlan_tci[i] = u16(0x100 + id + i * 0x111);
    }
#endif
#if PACKET_PARSER_ENABLE_MPLS
    for (uint32_t i = 0; i < std::min(mpls_count,
             (uint32_t)PACKET_PARSER_OUTPUT_MPLS_LABELS); ++i) {
        uint32_t entry = ((0x12000u + id * 4 + i) << 12)
            | ((i & 7) << 9) | ((i + 1 == mpls_count) ? 0x100 : 0)
            | (0x40 + i);
        packet.fields.mpls[i] = u32(entry);
    }
#endif
    return packet;
}

static PacketCase make_stack_limit_packet(uint32_t id, bool vlan_limit)
{
    PacketCase packet = make_packet(id, false, false,
        vlan_limit ? PACKET_PARSER_MAX_VLAN_HEADERS + 1 : 1,
        vlan_limit ? 0 : PACKET_PARSER_MAX_MPLS_LABELS + 1,
        false, false, false, false);
    PacketParserFields limited{};
    limited.destination_mac = packet.fields.destination_mac;
    limited.source_mac = packet.fields.source_mac;
    uint8_t flags = PACKET_PARSER_FLAG_LIMIT;
    uint8_t meta = 0;
#if PACKET_PARSER_ENABLE_VLAN
    uint32_t seen_vlans = vlan_limit ? PACKET_PARSER_MAX_VLAN_HEADERS : 1;
    if (seen_vlans != 0) {
        flags |= PACKET_PARSER_FLAG_VLAN;
        meta |= (uint8_t)(std::min(seen_vlans, 3u) << 4);
        for (uint32_t i = 0; i < std::min(seen_vlans,
                 (uint32_t)PACKET_PARSER_OUTPUT_VLAN_HEADERS); ++i) {
            limited.vlan_tci[i] = packet.fields.vlan_tci[i];
        }
    }
#endif
#if PACKET_PARSER_ENABLE_MPLS
    if (!vlan_limit) {
        flags |= PACKET_PARSER_FLAG_MPLS;
        meta |= (uint8_t)(3u << 6);
        for (uint32_t i = 0; i < PACKET_PARSER_OUTPUT_MPLS_LABELS; ++i) {
            limited.mpls[i] = packet.fields.mpls[i];
        }
    }
#endif
    limited.flags = u8(flags);
    limited.ip_meta = u8(meta);
    packet.fields = limited;
    packet.name += vlan_limit ? "-vlan-limit" : "-mpls-limit";
    return packet;
}

template<size_t LANE_WIDTH>
class PacketParserTest
{
    static constexpr size_t STREAMS = 2;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = STREAMS * LANE_BYTES;

#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    PacketParser<LANE_WIDTH> dut;
#endif

    logic<STREAMS> valid;
    logic<INPUT_BITS> data;
    logic<INPUT_BYTES> keep;
    logic<INPUT_BYTES> sop;
    logic<INPUT_BYTES> eop;
    logic<STREAMS> raw;
    logic<STREAMS> output_ready;
    std::array<std::vector<WireByte>, STREAMS> wire;
    std::array<size_t, STREAMS> position{};
    std::array<std::deque<ExpectedWord>, STREAMS> expected;
    bool error = false;
    size_t received = 0;
    size_t total_expected = 0;

    template<typename T, typename V>
    static void copy_to_verilator(T& target, const V& value)
    {
        std::memset(&target, 0, sizeof(target));
        std::memcpy(&target, &value, std::min(sizeof(target), sizeof(value)));
    }

    template<typename T, typename V>
    static V copy_from_verilator(const T& source)
    {
        V value{};
        std::memcpy(&value, &source, std::min(sizeof(source), sizeof(value)));
        return value;
    }

    void bind_native()
    {
#ifndef VERILATOR
        dut.valid_in = _ASSIGN_REG(valid);
        dut.data_in = _ASSIGN_REG(data);
        dut.keep_in = _ASSIGN_REG(keep);
        dut.sop_in = _ASSIGN_REG(sop);
        dut.eop_in = _ASSIGN_REG(eop);
        dut.raw_in = _ASSIGN_REG(raw);
        dut.ready_in = _ASSIGN_REG(output_ready);
        dut.__inst_name = "packet_parser";
        dut._assign();
#endif
    }

    void eval_low(bool reset)
    {
#ifdef VERILATOR
        dut.clk = 0;
        dut.reset = reset;
        dut.valid_in = (uint8_t)(uint64_t)valid;
        copy_to_verilator(dut.data_in, data);
        copy_to_verilator(dut.keep_in, keep);
        copy_to_verilator(dut.sop_in, sop);
        copy_to_verilator(dut.eop_in, eop);
        dut.raw_in = (uint8_t)(uint64_t)raw;
        dut.ready_in = (uint8_t)(uint64_t)output_ready;
        dut.eval();
#else
        (void)reset;
#endif
    }

    void rising_edge(bool reset)
    {
#ifdef VERILATOR
        dut.clk = 1;
        dut.reset = reset;
        dut.eval();
#else
        dut._work(reset);
        dut._strobe();
#endif
        ++_system_clock;
    }

    logic<STREAMS> input_ready_value()
    {
#ifdef VERILATOR
        return logic<STREAMS>(dut.ready_out);
#else
        return dut.ready_out();
#endif
    }

    logic<STREAMS> output_valid_value()
    {
#ifdef VERILATOR
        return logic<STREAMS>(dut.valid_out);
#else
        return dut.valid_out();
#endif
    }

    logic<STREAMS> output_last_value()
    {
#ifdef VERILATOR
        return logic<STREAMS>(dut.last_out);
#else
        return dut.last_out();
#endif
    }

    logic<STREAMS> output_raw_value()
    {
#ifdef VERILATOR
        return logic<STREAMS>(dut.raw_out);
#else
        return dut.raw_out();
#endif
    }

    logic<STREAMS * 64> output_keep_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.keep_out), logic<STREAMS * 64>>(dut.keep_out);
#else
        return dut.keep_out();
#endif
    }

    logic<STREAMS * 512> output_data_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.data_out), logic<STREAMS * 512>>(dut.data_out);
#else
        PacketParserOutputBus bus = dut.data_out();
        logic<STREAMS * 512> flattened = 0;
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            PacketParserWord word = bus[stream];
            for (size_t bit = 0; bit < 512; ++bit) {
                flattened[stream * 512 + bit] = word.raw[bit];
            }
        }
        return flattened;
#endif
    }

    bool protocol_error_value()
    {
#ifdef VERILATOR
        return dut.protocol_error_out;
#else
        return dut.protocol_error_out();
#endif
    }

    void fail(const std::string& message)
    {
        if (!error) {
            std::print("\n{} at cycle {}\n", message, _system_clock);
        }
        error = true;
    }

    void append_case(size_t stream, const PacketCase& packet, size_t ipg)
    {
        for (size_t i = 0; i < packet.frame.size(); ++i) {
            wire[stream].push_back({packet.frame[i], true, i == 0,
                i + 1 == packet.frame.size(), packet.raw});
        }
        for (size_t i = 0; i < ipg; ++i) {
            wire[stream].push_back({});
        }

        if (packet.raw) {
            for (size_t output_word = 0; output_word < 2; ++output_word) {
                ExpectedWord output{};
                output.raw = true;
                output.last = output_word == 1;
                output.name = packet.name + (output_word == 0 ? "[0]" : "[1]");
                for (size_t byte = 0; byte < 64; ++byte) {
                    size_t frame_byte = output_word * 64 + byte;
                    if (frame_byte < packet.frame.size()) {
                        output.data.bits(byte * 8 + 7, byte * 8) = packet.frame[frame_byte];
                        output.keep[byte] = 1;
                    }
                }
                expected[stream].push_back(output);
                ++total_expected;
            }
        }
        else {
            PacketParserWord word{};
            word.fields = packet.fields;
            ExpectedWord output{};
            output.data = word.raw;
            output.keep = ~logic<64>(0);
            output.last = true;
            output.raw = false;
            output.name = packet.name;
            expected[stream].push_back(output);
            ++total_expected;
        }
    }

    void build_traffic()
    {
        static constexpr std::array<size_t, 11> ipgs = {0, 1, 2, 3, 7, 11, 12, 19, 31, 47, 65};
        uint32_t id = 1;
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            // A distinct leading hole is the explicit realignment stress.
            wire[stream].resize((stream * 7 + 3) % LANE_BYTES);
            for (size_t item = 0; item < 12; ++item, ++id) {
                bool ipv6 = ((item + stream) & 1) != 0;
                bool tcp = ((item + stream * 3) & 2) != 0;
                uint32_t vlan_count = (uint32_t)((item + stream) % 4);
                uint32_t mpls_count = (uint32_t)((item / 2 + stream) % 3);
                bool ip_options = !ipv6 && (item % 3 == 0);
                bool transport_options = tcp && (item % 2 == 0);
                bool extensions = ipv6 && (item % 3 != 0);
                bool raw_mode = (item == 2 || item == 9);
                PacketCase packet = make_packet(id, ipv6, tcp, vlan_count,
                    mpls_count, ip_options, transport_options, extensions, raw_mode);
                append_case(stream, packet, ipgs[(item * 3 + stream) % ipgs.size()]);
            }
            PacketCase limited = make_stack_limit_packet(id++, (stream & 1) == 0);
            append_case(stream, limited, ipgs[(stream * 5 + 1) % ipgs.size()]);
        }
    }

    void drive_inputs()
    {
        data = 0;
        keep = 0;
        sop = 0;
        eop = 0;
        valid = 0;
        raw = 0;
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            for (size_t byte = 0; byte < LANE_BYTES; ++byte) {
                if (position[stream] + byte >= wire[stream].size()) {
                    break;
                }
                const WireByte& item = wire[stream][position[stream] + byte];
                size_t flat = stream * LANE_BYTES + byte;
                data.bits(flat * 8 + 7, flat * 8) = item.data;
                keep[flat] = item.keep;
                sop[flat] = item.sop;
                eop[flat] = item.eop;
                valid[stream] = (bool)valid[stream] || item.keep;
                if (item.sop) {
                    raw[stream] = item.raw;
                }
            }
        }
    }

    void sample_outputs()
    {
        logic<STREAMS> out_valid = output_valid_value();
        logic<STREAMS> out_last = output_last_value();
        logic<STREAMS> out_raw = output_raw_value();
        logic<STREAMS * 64> out_keep = output_keep_value();
        logic<STREAMS * 512> out_data = output_data_value();

        for (size_t stream = 0; stream < STREAMS; ++stream) {
            if (!(bool)out_valid[stream] || !(bool)output_ready[stream]) {
                continue;
            }
            if (expected[stream].empty()) {
                fail("unexpected output on stream " + std::to_string(stream));
                continue;
            }
            ExpectedWord reference = expected[stream].front();
            expected[stream].pop_front();
            logic<512> got_data = out_data.bits(stream * 512 + 511, stream * 512);
            logic<64> got_keep = out_keep.bits(stream * 64 + 63, stream * 64);
            if (got_data != reference.data || got_keep != reference.keep
                || (bool)out_last[stream] != reference.last
                || (bool)out_raw[stream] != reference.raw) {
                fail("output mismatch on stream " + std::to_string(stream)
                    + " for " + reference.name);
            }
            ++received;
        }
    }

public:
    bool run()
    {
#ifdef VERILATOR
        std::print("VERILATOR PacketParser<{}>\n", LANE_WIDTH);
#else
        std::print("CppHDL PacketParser<{}>\n", LANE_WIDTH);
#endif
        bind_native();
        build_traffic();
        output_ready = 0xff;
        for (size_t cycle = 0; cycle < 2; ++cycle) {
            eval_low(true);
            rising_edge(true);
        }

        size_t cycles = 0;
        while (!error && received < total_expected && cycles < 20000) {
            drive_inputs();
            // Independent, bounded stalls exercise output holding and RAW's
            // two-word reservation without starving any stream.
            output_ready = 0xff;
            if ((cycles % 13) < 2) output_ready[cycles % STREAMS] = 0;
            if ((cycles % 29) == 7) output_ready[(cycles / 3) % STREAMS] = 0;
            eval_low(false);
            sample_outputs();
            logic<STREAMS> input_ready = input_ready_value();
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                if ((bool)input_ready[stream] && position[stream] < wire[stream].size()) {
                    position[stream] += LANE_BYTES;
                }
            }
            rising_edge(false);
            ++cycles;
        }

        if (protocol_error_value()) {
            fail("DUT raised protocol_error_out");
        }
        if (received != total_expected) {
            fail("timed out before receiving every parser word");
        }
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            if (!expected[stream].empty()) {
                fail("stream " + std::to_string(stream) + " retained expected outputs");
            }
        }
        std::print("    words={} cycles={} {}\n", received, cycles,
            error ? "FAILED" : "PASSED");
        return !error;
    }
};

int main(int argc, char** argv)
{
    bool noveril = false;
    std::vector<std::string> positional;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--noveril") == 0) {
            noveril = true;
        }
        else {
            positional.emplace_back(argv[i]);
        }
    }

    bool ok = true;
#ifndef VERILATOR
    if (!noveril) {
        std::cout << "Building PacketParser Verilator simulations =========================\n";
        const std::filesystem::path generated = std::filesystem::current_path() / "generated_parser";
        const std::filesystem::path source = std::filesystem::absolute(__FILE__);
        const std::filesystem::path project_root =
            source.parent_path().parent_path().parent_path().parent_path();
        const std::vector<std::string> includes = {
            (source.parent_path().parent_path()).string(),
            (project_root / "cpphdl" / "include").string(),
            project_root.string()};
        const std::vector<std::string> packages = {
            "Predef_pkg", "PacketParserFields_pkg", "PacketParserWord_pkg",
            "PacketParserCursor_pkg", "PacketParserFlags_pkg"};
        ok &= VerilatorCompileInExactFolderFromGenerated(__FILE__, "PacketParser_64",
            "PacketParser", generated, packages, includes, 64);
        if (ok) {
            ok &= std::system("PacketParser_64/obj_dir/VPacketParser 64") == 0;
        }
    }
#else
    Verilated::commandArgs(argc, argv);
#endif

    if (!positional.empty()) {
        size_t width = std::stoull(positional[0]);
        if (width == 64) return !(ok && PacketParserTest<64>().run());
        std::print("unsupported PacketParser lane width {}\n", width);
        return 1;
    }
    ok = ok && PacketParserTest<64>().run();
    return ok ? 0 : 1;
}

#endif
