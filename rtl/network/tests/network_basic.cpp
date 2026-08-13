// End-to-end Network receive test.  Ordered aggregate Ethernet traffic passes
// through balancing, parsing, RxRAM and RxFifo; every descriptor and complete
// PRBS-backed packet is then checked through the public interfaces.

#include "../Network.h"
#include "../../testing/GenEthStream.h"

#if !defined(SYNTHESIS)

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <iostream>
#include <map>
#include <print>
#include <string>
#include <vector>

#include "../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define MAKE_HEADER(name) STRINGIFY(name.h)
#include MAKE_HEADER(VERILATOR_MODEL)
#endif

long _system_clock = -1;

struct NetworkPacket
{
    uint32_t id = 0;
    std::vector<uint8_t> frame;
    PacketParserFields fields{};
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

static logic<128> be128_value(const std::array<uint8_t, 16>& bytes)
{
    logic<128> value = 0;
    for (uint8_t byte : bytes) {
        value = (value << 8) | logic<128>(byte);
    }
    return value;
}

static uint32_t prbs_step(uint32_t state)
{
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static std::vector<uint8_t> prbs_payload(uint32_t id, size_t bytes)
{
    std::vector<uint8_t> payload(bytes);
    uint32_t state = 0x9e3779b9u ^ id ^ (uint32_t)(bytes * 0x45d9f3bu);
    for (size_t index = 0; index < bytes; ++index) {
        state = prbs_step(state + (uint32_t)index + 1);
        payload[index] = (uint8_t)(state >> 24);
    }
    return payload;
}

static NetworkPacket make_network_packet(uint32_t id, size_t target_size,
    bool ipv6, bool tcp, uint32_t vlan_count, uint32_t mpls_count,
    bool ip_options, bool tcp_options, bool ipv6_extensions)
{
    NetworkPacket packet;
    std::vector<uint8_t> ethernet;
    std::vector<uint8_t> tags;
    std::vector<uint8_t> network;
    std::vector<uint8_t> extensions;
    std::vector<uint8_t> transport;
    std::array<uint8_t, 16> source_ipv6{};
    std::array<uint8_t, 16> destination_ipv6{};
    const uint64_t destination_mac = 0x020000000000ull | id;
    const uint64_t source_mac = 0x0a0000000000ull | (id * 3);
    const uint16_t source_port = (uint16_t)(1000 + id);
    const uint16_t destination_port = (uint16_t)(40000 + id);
    const uint8_t protocol = tcp ? 6 : 17;
    const uint16_t network_type = mpls_count != 0
        ? 0x8847 : (ipv6 ? 0x86dd : 0x0800);

    packet.id = id;
    for (int shift = 40; shift >= 0; shift -= 8) {
        ethernet.push_back((uint8_t)(destination_mac >> shift));
    }
    for (int shift = 40; shift >= 0; shift -= 8) {
        ethernet.push_back((uint8_t)(source_mac >> shift));
    }
    append_be16(ethernet, vlan_count != 0 ? 0x88a8 : network_type);
    for (uint32_t vlan = 0; vlan < vlan_count; ++vlan) {
        append_be16(tags, (uint16_t)(0x100 + id + vlan * 0x111));
        append_be16(tags, vlan + 1 == vlan_count ? network_type : 0x8100);
    }
    for (uint32_t label = 0; label < mpls_count; ++label) {
        uint32_t entry = ((0x12000u + id * 4 + label) << 12)
            | ((label & 7) << 9)
            | ((label + 1 == mpls_count) ? 0x100 : 0)
            | (0x40 + label);
        append_be32(tags, entry);
    }

    append_be16(transport, source_port);
    append_be16(transport, destination_port);
    if (tcp) {
        append_be32(transport, 0x10203040u ^ id);
        append_be32(transport, 0x50607080u ^ (id << 1));
        std::vector<uint8_t> options = tcp_options
            ? std::vector<uint8_t>{1, 1, 2, 4, 0x05, 0xb4,
                3, 3, 7, 0, 0, 0}
            : std::vector<uint8_t>{};
        transport.push_back((uint8_t)(((20 + options.size()) / 4) << 4));
        transport.push_back(0x18);
        append_be16(transport, 0x4000);
        append_be16(transport, 0);
        append_be16(transport, 0);
        transport.insert(transport.end(), options.begin(), options.end());
    }
    else {
        // Length is patched after the payload size is known.
        append_be16(transport, 0);
        append_be16(transport, 0);
    }

    uint8_t first_next = protocol;
    if (ipv6 && ipv6_extensions) {
        const std::array<std::vector<uint8_t>, 4> chain = {
            std::vector<uint8_t>{43, 0, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16},
            std::vector<uint8_t>{60, 0, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26},
            std::vector<uint8_t>{51, 0, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36},
            std::vector<uint8_t>{protocol, 1, 0, 0, 0x41, 0x42, 0x43, 0x44,
                0x45, 0x46, 0x47, 0x48}};
        first_next = 0;
        for (const auto& header : chain) {
            extensions.insert(extensions.end(), header.begin(), header.end());
        }
    }

    size_t ip_header_bytes = ipv6 ? 40 : 20 + (ip_options ? 12 : 0);
    size_t fixed_bytes = ethernet.size() + tags.size() + ip_header_bytes
        + extensions.size() + transport.size();
    if (target_size < fixed_bytes) {
        target_size = fixed_bytes;
    }
    size_t payload_bytes = target_size - fixed_bytes;
    std::vector<uint8_t> payload = prbs_payload(id, payload_bytes);
    if (!tcp) {
        uint16_t udp_length = (uint16_t)(transport.size() + payload.size());
        transport[4] = (uint8_t)(udp_length >> 8);
        transport[5] = (uint8_t)udp_length;
    }

    if (!ipv6) {
        network.assign(ip_header_bytes, 0);
        network[0] = (uint8_t)(0x40 | (ip_header_bytes / 4));
        uint16_t total_length = (uint16_t)(network.size()
            + transport.size() + payload.size());
        network[2] = (uint8_t)(total_length >> 8);
        network[3] = (uint8_t)total_length;
        network[4] = (uint8_t)(id >> 8);
        network[5] = (uint8_t)id;
        network[8] = 64;
        network[9] = protocol;
        uint32_t source_ip = 0x0a000000u | (id & 0xffff);
        uint32_t destination_ip = 0xc0000200u | (id & 0xff);
        network[12] = (uint8_t)(source_ip >> 24);
        network[13] = (uint8_t)(source_ip >> 16);
        network[14] = (uint8_t)(source_ip >> 8);
        network[15] = (uint8_t)source_ip;
        network[16] = (uint8_t)(destination_ip >> 24);
        network[17] = (uint8_t)(destination_ip >> 16);
        network[18] = (uint8_t)(destination_ip >> 8);
        network[19] = (uint8_t)destination_ip;
        for (size_t byte = 20; byte < network.size(); ++byte) {
            network[byte] = byte == 20 ? 1 : 0;
        }
        packet.fields.source_ip = logic<128>(source_ip);
        packet.fields.destination_ip = logic<128>(destination_ip);
    }
    else {
        network.assign(40, 0);
        network[0] = 0x60;
        uint16_t ipv6_payload = (uint16_t)(extensions.size()
            + transport.size() + payload.size());
        network[4] = (uint8_t)(ipv6_payload >> 8);
        network[5] = (uint8_t)ipv6_payload;
        network[6] = first_next;
        network[7] = 64;
        for (size_t byte = 0; byte < 16; ++byte) {
            source_ipv6[byte] = (uint8_t)(byte == 0 ? 0x20
                : (byte == 1 ? 0x01 : id + byte));
            destination_ipv6[byte] = (uint8_t)(byte == 0 ? 0x20
                : (byte == 1 ? 0x01 : 0x80 + id + byte));
        }
        std::copy(source_ipv6.begin(), source_ipv6.end(), network.begin() + 8);
        std::copy(destination_ipv6.begin(), destination_ipv6.end(),
            network.begin() + 24);
        packet.fields.source_ip = be128_value(source_ipv6);
        packet.fields.destination_ip = be128_value(destination_ipv6);
    }

    packet.frame = ethernet;
    packet.frame.insert(packet.frame.end(), tags.begin(), tags.end());
    packet.frame.insert(packet.frame.end(), network.begin(), network.end());
    packet.frame.insert(packet.frame.end(), extensions.begin(), extensions.end());
    packet.frame.insert(packet.frame.end(), transport.begin(), transport.end());
    packet.frame.insert(packet.frame.end(), payload.begin(), payload.end());

    packet.fields.destination_mac = logic<48>(destination_mac);
    packet.fields.source_mac = logic<48>(source_mac);
    packet.fields.source_port = source_port;
    packet.fields.destination_port = destination_port;
    packet.fields.protocol = protocol;
    uint8_t flags = PACKET_PARSER_FLAG_PARSED
        | PACKET_PARSER_FLAG_TRANSPORT;
    if (ipv6) flags |= PACKET_PARSER_FLAG_IPV6;
    if (vlan_count != 0) flags |= PACKET_PARSER_FLAG_VLAN;
    if (mpls_count != 0) flags |= PACKET_PARSER_FLAG_MPLS;
    packet.fields.flags = flags;
    packet.fields.ip_meta = (ipv6 ? 6 : 4)
        | (std::min(vlan_count, 3u) << 4)
        | (std::min(mpls_count, 3u) << 6);
#if PACKET_PARSER_ENABLE_VLAN
    for (uint32_t index = 0; index < std::min(vlan_count,
             (uint32_t)PACKET_PARSER_OUTPUT_VLAN_HEADERS); ++index) {
        packet.fields.vlan_tci[index] = 0x100 + id + index * 0x111;
    }
#endif
#if PACKET_PARSER_ENABLE_MPLS
    for (uint32_t index = 0; index < std::min(mpls_count,
             (uint32_t)PACKET_PARSER_OUTPUT_MPLS_LABELS); ++index) {
        uint32_t entry = ((0x12000u + id * 4 + index) << 12)
            | ((index & 7) << 9)
            | ((index + 1 == mpls_count) ? 0x100 : 0)
            | (0x40 + index);
        packet.fields.mpls[index] = entry;
    }
#endif
    return packet;
}

template<size_t LANE_WIDTH, size_t READ_PORTS = 4, size_t BANK_DEPTH = 4096>
class NetworkBasicTest
{
    static constexpr size_t STREAMS = 8;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t LOGICAL_ROW_BITS = clog2(BANK_DEPTH * 2);
    static constexpr size_t HANDLE_BITS = LOGICAL_ROW_BITS + 3;
    static constexpr size_t FRAME_LENGTH_BITS = 14;

#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    Network<LANE_WIDTH, READ_PORTS, BANK_DEPTH> dut;
#endif

    bool input_valid = false;
    bool raw_mode = false;
    logic<INPUT_BITS> input_data;
    logic<INPUT_BYTES> input_keep;
    logic<INPUT_BYTES> input_sop;
    logic<INPUT_BYTES> input_eop;
    bool descriptor_ready = true;
    logic<READ_PORTS> read_request_valid;
    logic<READ_PORTS * HANDLE_BITS> read_request_handle;
    logic<READ_PORTS * LOGICAL_ROW_BITS> read_request_word;
    logic<READ_PORTS> read_response_ready;
    logic<READ_PORTS> release_valid;
    logic<READ_PORTS * HANDLE_BITS> release_handle;
    logic<READ_PORTS * FRAME_LENGTH_BITS> release_length;
    logic<STREAMS> tx_input_valid;
    logic<INPUT_BITS> tx_input_data;
    logic<INPUT_BYTES> tx_input_keep;
    logic<STREAMS> tx_input_sop;
    logic<STREAMS> tx_input_eop;
    bool tx_output_ready = true;
    bool error = false;

    template<typename T, typename V>
    static void copy_to_verilator(T& target, const V& value)
    {
        std::memset(&target, 0, sizeof(target));
        std::memcpy(&target, &value, std::min(sizeof(target), sizeof(value)));
    }

    template<typename V, typename T>
    static V copy_from_verilator(const T& source)
    {
        V value{};
        std::memcpy(&value, &source, std::min(sizeof(value), sizeof(source)));
        return value;
    }

    void bind_native()
    {
#ifndef VERILATOR
        dut.valid_in = _ASSIGN(input_valid);
        dut.data_in = _ASSIGN_REG(input_data);
        dut.keep_in = _ASSIGN_REG(input_keep);
        dut.sop_in = _ASSIGN_REG(input_sop);
        dut.eop_in = _ASSIGN_REG(input_eop);
        dut.raw_in = _ASSIGN(raw_mode);
        dut.descriptor_ready_in = _ASSIGN(descriptor_ready);
        dut.read_valid_in = _ASSIGN_REG(read_request_valid);
        dut.read_handle_in = _ASSIGN_REG(read_request_handle);
        dut.read_word_in = _ASSIGN_REG(read_request_word);
        dut.read_ready_in = _ASSIGN_REG(read_response_ready);
        dut.release_valid_in = _ASSIGN_REG(release_valid);
        dut.release_handle_in = _ASSIGN_REG(release_handle);
        dut.release_length_in = _ASSIGN_REG(release_length);
        dut.tx_valid_in = _ASSIGN_REG(tx_input_valid);
        dut.tx_data_in = _ASSIGN_REG(tx_input_data);
        dut.tx_keep_in = _ASSIGN_REG(tx_input_keep);
        dut.tx_sop_in = _ASSIGN_REG(tx_input_sop);
        dut.tx_eop_in = _ASSIGN_REG(tx_input_eop);
        dut.tx_ready_in = _ASSIGN(tx_output_ready);
        dut.__inst_name = "network";
        dut._assign();
#endif
    }

    void eval_low(bool reset)
    {
#ifdef VERILATOR
        dut.clk = 0;
        dut.reset = reset;
        dut.valid_in = input_valid;
        copy_to_verilator(dut.data_in, input_data);
        copy_to_verilator(dut.keep_in, input_keep);
        copy_to_verilator(dut.sop_in, input_sop);
        copy_to_verilator(dut.eop_in, input_eop);
        dut.raw_in = raw_mode;
        dut.descriptor_ready_in = descriptor_ready;
        dut.read_valid_in = (uint8_t)(uint64_t)read_request_valid;
        copy_to_verilator(dut.read_handle_in, read_request_handle);
        copy_to_verilator(dut.read_word_in, read_request_word);
        dut.read_ready_in = (uint8_t)(uint64_t)read_response_ready;
        dut.release_valid_in = (uint8_t)(uint64_t)release_valid;
        copy_to_verilator(dut.release_handle_in, release_handle);
        copy_to_verilator(dut.release_length_in, release_length);
        dut.tx_valid_in = (uint8_t)(uint64_t)tx_input_valid;
        copy_to_verilator(dut.tx_data_in, tx_input_data);
        copy_to_verilator(dut.tx_keep_in, tx_input_keep);
        dut.tx_sop_in = (uint8_t)(uint64_t)tx_input_sop;
        dut.tx_eop_in = (uint8_t)(uint64_t)tx_input_eop;
        dut.tx_ready_in = tx_output_ready;
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

    bool input_ready_value()
    {
#ifdef VERILATOR
        return dut.ready_out;
#else
        return dut.ready_out();
#endif
    }

    bool descriptor_valid_value()
    {
#ifdef VERILATOR
        return dut.descriptor_valid_out;
#else
        return dut.descriptor_valid_out();
#endif
    }

    RxDescriptorWord descriptor_data_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<RxDescriptorWord>(dut.descriptor_data_out);
#else
        return dut.descriptor_data_out();
#endif
    }

    logic<READ_PORTS> read_request_ready_value()
    {
#ifdef VERILATOR
        return logic<READ_PORTS>(dut.read_ready_out);
#else
        return dut.read_ready_out();
#endif
    }

    logic<READ_PORTS> read_response_valid_value()
    {
#ifdef VERILATOR
        return logic<READ_PORTS>(dut.read_valid_out);
#else
        return dut.read_valid_out();
#endif
    }

    logic<READ_PORTS * LANE_WIDTH> read_data_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<READ_PORTS * LANE_WIDTH>>(
            dut.read_data_out);
#else
        return dut.read_data_out();
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

    bool storage_full_value()
    {
#ifdef VERILATOR
        return dut.storage_full_out;
#else
        return dut.storage_full_out();
#endif
    }

    logic<STREAMS> tx_input_ready_value()
    {
#ifdef VERILATOR
        return logic<STREAMS>(dut.tx_ready_out);
#else
        return dut.tx_ready_out();
#endif
    }

    bool tx_output_valid_value()
    {
#ifdef VERILATOR
        return dut.tx_valid_out;
#else
        return dut.tx_valid_out();
#endif
    }

    logic<INPUT_BITS> tx_output_data_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<INPUT_BITS>>(dut.tx_data_out);
#else
        return dut.tx_data_out();
#endif
    }

    logic<INPUT_BYTES> tx_output_keep_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<INPUT_BYTES>>(dut.tx_keep_out);
#else
        return dut.tx_keep_out();
#endif
    }

    logic<INPUT_BYTES> tx_output_sop_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<INPUT_BYTES>>(dut.tx_sop_out);
#else
        return dut.tx_sop_out();
#endif
    }

    logic<INPUT_BYTES> tx_output_eop_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<INPUT_BYTES>>(dut.tx_eop_out);
#else
        return dut.tx_eop_out();
#endif
    }

    void fail(const std::string& message)
    {
        if (!error) {
            std::print("\n{} at cycle {}\n", message, _system_clock);
        }
        error = true;
    }

    static uint32_t raw_packet_id(const RxDescriptor& descriptor)
    {
        logic<512> raw = descriptor.packet_word0.raw;
        return ((uint32_t)raw.bits(23, 16) << 24)
            | ((uint32_t)raw.bits(31, 24) << 16)
            | ((uint32_t)raw.bits(39, 32) << 8)
            | (uint32_t)raw.bits(47, 40);
    }

    bool validate_descriptor(const RxDescriptor& descriptor, bool raw,
        const std::map<uint32_t, NetworkPacket>& expected,
        std::deque<std::pair<RxDescriptor, const NetworkPacket*>>& reads)
    {
        uint32_t id = raw ? raw_packet_id(descriptor)
            : ((uint32_t)(uint64_t)descriptor.packet_word0.fields.destination_mac);
        auto found = expected.find(id);
        if (found == expected.end()) {
            fail("descriptor identifies an unknown packet " + std::to_string(id));
            return false;
        }
        const NetworkPacket& packet = found->second;
        if ((uint32_t)descriptor.packet_length != packet.frame.size()) {
            fail("descriptor length mismatch for packet " + std::to_string(id));
        }
        if ((uint32_t)descriptor.ingress_stream >= STREAMS
            || ((uint32_t)descriptor.packet_address & 7)
                != (uint32_t)descriptor.ingress_stream) {
            fail("descriptor address/ingress-stream mismatch");
        }
        if (((uint32_t)descriptor.flags & RX_DESCRIPTOR_FLAG_RAW) != (raw ? 1u : 0u)) {
            fail("descriptor RAW flag mismatch");
        }
        if (raw) {
            for (size_t byte = 0; byte < 128; ++byte) {
                uint8_t got = byte < 64
                    ? (uint8_t)descriptor.packet_word0.raw.bits(byte * 8 + 7,
                        byte * 8)
                    : (uint8_t)descriptor.packet_word1.raw.bits(
                        (byte - 64) * 8 + 7, (byte - 64) * 8);
                uint8_t reference = byte < packet.frame.size()
                    ? packet.frame[byte] : 0;
                if (got != reference) {
                    fail("RAW descriptor data mismatch for packet "
                        + std::to_string(id));
                    break;
                }
            }
        }
        else {
            const PacketParserFields& got = descriptor.packet_word0.fields;
            if (std::memcmp(&got, &packet.fields, sizeof(got)) != 0) {
                fail("parsed fields mismatch for packet " + std::to_string(id));
            }
            if (descriptor.packet_word1.raw != logic<512>(0)) {
                fail("parsed descriptor second packet word is not zero");
            }
        }
        reads.push_back({descriptor, &packet});
        return true;
    }

    bool read_packets(
        std::deque<std::pair<RxDescriptor, const NetworkPacket*>>& jobs)
    {
        uint32_t word = 0;
        bool waiting = false;
        size_t cycles = 0;
        read_response_ready = ~logic<READ_PORTS>(0);
        while (!error && (!jobs.empty() || waiting) && cycles < 300000) {
            read_request_valid = 0;
            read_request_handle = 0;
            read_request_word = 0;
            if (!jobs.empty() && !waiting) {
                read_request_valid[0] = 1;
                uint32_t address = (uint32_t)jobs.front().first.packet_address;
                for (size_t bit = 0; bit < HANDLE_BITS; ++bit) {
                    read_request_handle[bit] = (address >> bit) & 1;
                }
                for (size_t bit = 0; bit < LOGICAL_ROW_BITS; ++bit) {
                    read_request_word[bit] = (word >> bit) & 1;
                }
            }
            eval_low(false);
            logic<READ_PORTS> response_valid = read_response_valid_value();
            if ((bool)response_valid[0]) {
                if (!waiting || jobs.empty()) {
                    fail("orphan RxRAM response");
                }
                else {
                    logic<READ_PORTS * LANE_WIDTH> all_data = read_data_value();
                    logic<LANE_WIDTH> got = all_data.bits(LANE_WIDTH - 1, 0);
                    logic<LANE_WIDTH> reference = 0;
                    const NetworkPacket& packet = *jobs.front().second;
                    size_t start = word * LANE_BYTES;
                    for (size_t byte = 0; byte < LANE_BYTES; ++byte) {
                        if (start + byte < packet.frame.size()) {
                            reference.bits(byte * 8 + 7, byte * 8) =
                                packet.frame[start + byte];
                        }
                    }
                    if (got != reference) {
                        fail("RxRAM PRBS mismatch for packet "
                            + std::to_string(packet.id) + " word "
                            + std::to_string(word));
                    }
                    waiting = false;
                    ++word;
                    if (word == (packet.frame.size() + LANE_BYTES - 1)
                            / LANE_BYTES) {
                        jobs.pop_front();
                        word = 0;
                    }
                }
            }
            logic<READ_PORTS> request_ready = read_request_ready_value();
            if ((bool)read_request_valid[0] && (bool)request_ready[0]) {
                waiting = true;
            }
            rising_edge(false);
            ++cycles;
        }
        if (!jobs.empty() || waiting) {
            fail("RxRAM packet readback did not drain");
        }
        return !error;
    }

    bool run_phase(bool raw, uint32_t id_base)
    {
        static const std::array<size_t, 14> sizes = {
            64, 65, 79, 80, 81, 127, 128, 129,
            255, 511, 1518, 2048, 4096, 9000};
        static const std::array<size_t, 8> ipgs = {0, 1, 7, 11, 12, 13, 23, 31};
        GenEthStream<LANE_WIDTH> generator;
        std::map<uint32_t, NetworkPacket> expected;
        std::deque<std::pair<RxDescriptor, const NetworkPacket*>> reads;
        generator.clear(3 + (LANE_WIDTH == 320 ? 11 : 0));
        for (size_t index = 0; index < sizes.size(); ++index) {
            uint32_t id = id_base + (uint32_t)index;
            bool ipv6 = index % 3 == 2;
            bool tcp = index % 2 == 1;
            uint32_t vlan = index % 5 == 3 ? 2 : (index % 4 == 1 ? 1 : 0);
            uint32_t mpls = index % 6 == 4 ? 2 : 0;
            bool ip_options = !ipv6 && index % 7 == 5;
            bool tcp_options = tcp && index >= 6 && index % 3 == 0;
            bool extensions = ipv6 && index >= 6 && index % 4 == 2;
            NetworkPacket packet = make_network_packet(id, sizes[index], ipv6,
                tcp, vlan, mpls, ip_options, tcp_options, extensions);
            generator.push(packet.frame, ipgs[index % ipgs.size()]);
            expected.emplace(id, std::move(packet));
        }
        generator.finalize();

        raw_mode = raw;
        descriptor_ready = true;
        read_response_ready = ~logic<READ_PORTS>(0);
        read_request_valid = 0;
        read_request_handle = 0;
        read_request_word = 0;
        input_valid = false;
        input_data = 0;
        input_keep = 0;
        input_sop = 0;
        input_eop = 0;
        tx_input_valid = 0;
        tx_input_data = 0;
        tx_input_keep = 0;
        tx_input_sop = 0;
        tx_input_eop = 0;
        tx_output_ready = true;
        for (size_t cycle = 0; cycle < 3; ++cycle) {
            eval_low(true);
            rising_edge(true);
        }

        size_t descriptors = 0;
        size_t source_stalls = 0;
        size_t cycles = 0;
        while (!error && descriptors < expected.size() && cycles < 100000) {
            input_valid = !generator.empty();
            if (input_valid) {
                const auto& beat = generator.front();
                input_data = beat.data;
                input_keep = beat.keep;
                input_sop = beat.sop;
                input_eop = beat.eop;
            }
            else {
                input_data = 0;
                input_keep = 0;
                input_sop = 0;
                input_eop = 0;
            }
            eval_low(false);
            if (descriptor_valid_value() && descriptor_ready) {
                RxDescriptorWord word = descriptor_data_value();
                validate_descriptor(word.descriptor, raw, expected, reads);
                ++descriptors;
            }
            if (input_valid) {
                if (input_ready_value()) generator.pop();
                else ++source_stalls;
            }
            rising_edge(false);
            ++cycles;
        }
        input_valid = false;
        if (descriptors != expected.size()) {
            fail("Network did not produce every RxFifo descriptor");
        }
        if (source_stalls != 0) {
            fail("Network backpressured the generated wire stream");
        }
        if (protocol_error_value()) fail("Network raised protocol_error_out");
        if (storage_full_value()) fail("Network exhausted RxRAM");
        read_packets(reads);
        std::print("    {:<6} packets={} aggregate_words={} cycles={} {}\n",
            raw ? "RAW" : "parsed", descriptors, generator.size(), cycles,
            error ? "FAILED" : "PASSED");
        return !error;
    }

    static std::vector<uint8_t> make_tx_frame(uint32_t id, size_t size)
    {
        std::vector<uint8_t> frame = prbs_payload(id, size);
        frame[0] = (uint8_t)id;
        frame[1] = (uint8_t)(id >> 8);
        frame[2] = (uint8_t)(id >> 16);
        frame[3] = (uint8_t)(id >> 24);
        return frame;
    }

    static uint32_t tx_frame_id(const std::vector<uint8_t>& frame)
    {
        return (uint32_t)frame[0] | ((uint32_t)frame[1] << 8)
            | ((uint32_t)frame[2] << 16) | ((uint32_t)frame[3] << 24);
    }

    bool run_tx_phase(uint32_t id_base)
    {
        static const std::array<size_t, 8> sizes = {
            64, 65, 79, 127, 255, 511, 1518, 9000};
        std::array<std::vector<std::vector<uint8_t>>, STREAMS> packets;
        std::array<size_t, STREAMS> packet_index{};
        std::array<size_t, STREAMS> word_index{};
        std::map<uint32_t, std::vector<uint8_t>> expected;
        std::vector<uint8_t> assembling;
        bool in_frame = false;
        bool saw_frame = false;
        size_t idle_bytes = 0;
        size_t received = 0;
        size_t cycles = 0;

        for (size_t round = 0; round < 2; ++round) {
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                uint32_t id = id_base + (uint32_t)(round * STREAMS + stream);
                std::vector<uint8_t> frame = make_tx_frame(id,
                    sizes[(round * 3 + stream) & 7]);
                expected.emplace(id, frame);
                packets[stream].push_back(std::move(frame));
            }
        }
        const size_t expected_count = expected.size();

        input_valid = false;
        input_data = 0;
        input_keep = 0;
        input_sop = 0;
        input_eop = 0;
        raw_mode = false;
        descriptor_ready = true;
        read_request_valid = 0;
        read_request_handle = 0;
        read_request_word = 0;
        read_response_ready = ~logic<READ_PORTS>(0);
        tx_input_valid = 0;
        tx_input_data = 0;
        tx_input_keep = 0;
        tx_input_sop = 0;
        tx_input_eop = 0;
        tx_output_ready = false;
        for (size_t reset_cycle = 0; reset_cycle < 3; ++reset_cycle) {
            eval_low(true);
            rising_edge(true);
        }

        while (!error && received < expected_count && cycles < 100000) {
            bool all_written = true;
            tx_input_valid = 0;
            tx_input_data = 0;
            tx_input_keep = 0;
            tx_input_sop = 0;
            tx_input_eop = 0;
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                if (packet_index[stream] >= packets[stream].size()) continue;
                all_written = false;
                const std::vector<uint8_t>& frame =
                    packets[stream][packet_index[stream]];
                size_t start = word_index[stream] * LANE_BYTES;
                size_t bytes = std::min(LANE_BYTES, frame.size() - start);
                tx_input_valid[stream] = 1;
                tx_input_sop[stream] = word_index[stream] == 0;
                tx_input_eop[stream] = start + bytes == frame.size();
                for (size_t byte = 0; byte < bytes; ++byte) {
                    tx_input_data.bits(stream * LANE_WIDTH + byte * 8 + 7,
                        stream * LANE_WIDTH + byte * 8) = frame[start + byte];
                    tx_input_keep[stream * LANE_BYTES + byte] = 1;
                }
            }
            tx_output_ready = all_written;
            eval_low(false);
            logic<STREAMS> ready = tx_input_ready_value();
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                if (!(bool)tx_input_valid[stream] || !(bool)ready[stream]) {
                    continue;
                }
                const std::vector<uint8_t>& frame =
                    packets[stream][packet_index[stream]];
                ++word_index[stream];
                if (word_index[stream]
                        == (frame.size() + LANE_BYTES - 1) / LANE_BYTES) {
                    word_index[stream] = 0;
                    ++packet_index[stream];
                }
            }

            if (tx_output_valid_value() && tx_output_ready) {
                logic<INPUT_BITS> data = tx_output_data_value();
                logic<INPUT_BYTES> keep = tx_output_keep_value();
                logic<INPUT_BYTES> sop = tx_output_sop_value();
                logic<INPUT_BYTES> eop = tx_output_eop_value();
                for (size_t byte = 0; byte < INPUT_BYTES; ++byte) {
                    if (!(bool)keep[byte]) {
                        if (in_frame) {
                            fail("Network TX inserted idle inside a packet");
                            break;
                        }
                        if (saw_frame) ++idle_bytes;
                        continue;
                    }
                    if ((bool)sop[byte]) {
                        if (in_frame || (saw_frame && idle_bytes != 12)) {
                            fail("Network TX did not use the minimum IPG");
                            break;
                        }
                        assembling.clear();
                        in_frame = true;
                        idle_bytes = 0;
                    }
                    else if (!in_frame) {
                        fail("Network TX data appeared without SOP");
                        break;
                    }
                    assembling.push_back((uint8_t)data.bits(
                        byte * 8 + 7, byte * 8));
                    if ((bool)eop[byte]) {
                        uint32_t id = tx_frame_id(assembling);
                        auto found = expected.find(id);
                        if (found == expected.end() || found->second != assembling) {
                            fail("Network TX PRBS packet mismatch");
                            break;
                        }
                        expected.erase(found);
                        ++received;
                        in_frame = false;
                        saw_frame = true;
                        idle_bytes = 0;
                    }
                }
            }
            rising_edge(false);
            ++cycles;
        }
        if (!expected.empty() || in_frame) {
            fail("Network TX did not drain every complete packet");
        }
        if (protocol_error_value()) fail("Network TX raised protocol_error_out");
        std::print("    TX     packets={} cycles={} {}\n", received, cycles,
            error ? "FAILED" : "PASSED");
        return !error;
    }

public:
    bool run()
    {
#ifdef VERILATOR
        std::print("VERILATOR Network<{}>\n", LANE_WIDTH);
#else
        std::print("CppHDL Network<{}>\n", LANE_WIDTH);
#endif
        bind_native();
        bool ok = run_phase(false, 0x1000 + (uint32_t)LANE_WIDTH);
        ok &= run_phase(true, 0x2000 + (uint32_t)LANE_WIDTH);
        ok &= run_tx_phase(0x3000 + (uint32_t)LANE_WIDTH);
        return ok;
    }
};

int main(int argc, char** argv)
{
    bool noveril = false;
    std::vector<std::string> positional;
    for (int arg = 1; arg < argc; ++arg) {
        if (std::strcmp(argv[arg], "--noveril") == 0) noveril = true;
        else positional.emplace_back(argv[arg]);
    }

    bool ok = true;
#ifndef VERILATOR
    if (!noveril) {
        std::cout << "Building Network Verilator simulations ==============================\n";
        const std::filesystem::path generated =
            std::filesystem::current_path() / "generated_network";
        const std::filesystem::path source = std::filesystem::absolute(__FILE__);
        const std::filesystem::path project_root = source.parent_path()
            .parent_path().parent_path().parent_path();
        const std::vector<std::string> includes = {
            source.parent_path().string(),
            source.parent_path().parent_path().string(),
            (project_root / "rtl" / "testing").string(),
            (project_root / "rtl" / "common").string(),
            (project_root / "cpphdl" / "include").string(),
            project_root.string()};
        const std::vector<std::string> modules = {
            "Predef_pkg", "PacketParserFields_pkg", "PacketParserWord_pkg",
            "PacketParserCursor_pkg", "PacketParserFlags_pkg",
            "RxRAMWritePair_pkg", "RxDescriptor_pkg", "RxDescriptorWord_pkg",
            "SmartNicMemory", "Fifo", "SmartNicRAM", "InputBalancer", "PacketParser",
            "RxRAM", "RxFifo", "TxFifo", "OutputMerger"};
        ok &= VerilatorCompileInExactFolderFromGenerated(__FILE__, "Network_160",
            "Network", generated, modules, includes, 160, 4, 4096, 64);
        ok &= VerilatorCompileInExactFolderFromGenerated(__FILE__, "Network_320",
            "Network", generated, modules, includes, 320, 4, 4096, 64);
        if (ok) {
            ok &= std::system("Network_160/obj_dir/VNetwork 160") == 0;
            ok &= std::system("Network_320/obj_dir/VNetwork 320") == 0;
        }
    }
#else
    Verilated::commandArgs(argc, argv);
#endif

    if (!positional.empty()) {
        size_t width = std::stoull(positional[0]);
        if (width == 160) return !(ok && NetworkBasicTest<160>().run());
        if (width == 320) return !(ok && NetworkBasicTest<320>().run());
        std::print("unsupported Network lane width {}\n", width);
        return 1;
    }
    ok = ok && NetworkBasicTest<160>().run();
    ok = ok && NetworkBasicTest<320>().run();
    return ok ? 0 : 1;
}

#endif
