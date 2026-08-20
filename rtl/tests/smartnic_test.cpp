// SmartNIC integration test with two 10GBASE-R PCS lanes
// front end.  Random Ethernet frames are packed into legal XGMII characters,
// traversed through the complete eth_pcs encode/scramble/lane/decode path, and
// adapted to the Network byte/SOP/EOP interface.  The reverse TX path checks
// explicit IDLE characters, safe valid pauses, and the requested RX IPG stress
// budget.  SmartNIC TX retains the nominal 12-idle minimum.

#include "../SmartNIC.h"

#include <10GBASE.h>

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
#include <numeric>
#include <optional>
#include <print>
#include <random>
#include <string>
#include <vector>

#include "../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define SMARTNIC_STRINGIFY_INNER(value) #value
#define SMARTNIC_STRINGIFY(value) SMARTNIC_STRINGIFY_INNER(value)
#include SMARTNIC_STRINGIFY(VERILATOR_MODEL.h)
#endif

long _system_clock = -1;

namespace
{

static constexpr size_t LANE_WIDTH = NET_LANE_WIDTH;
static constexpr size_t STREAMS = 2;
static constexpr size_t NET_BITS = STREAMS * LANE_WIDTH;
static constexpr size_t NET_BYTES = NET_BITS / 8;
static constexpr size_t MAC_BYTES = LANE_WIDTH / 8;
static constexpr size_t L2_WIDTH = 256;
static constexpr size_t L2_BYTES = L2_WIDTH / 8;
static constexpr size_t READ_PORTS = 1;
static constexpr size_t HANDLE_BITS = SmartNIC<LANE_WIDTH>::HANDLE_BITS;
static constexpr size_t FRAME_LENGTH_BITS = 14;

using SelectedPCS = ethernet_pcs::PCS10G<NET_BITS, 2, 2>;
static constexpr const char* RATE_NAME = "2x10G";

struct XgmiiCharacter
{
    uint8_t data = XGMII_IDLE;
    bool control = true;
};

struct XgmiiBeat
{
    logic<NET_BITS> data{};
    logic<NET_BYTES> control{};
    bool in_frame_before = false;
    bool in_frame_after = false;
};

struct NetworkBeat
{
    logic<NET_BITS> data{};
    logic<NET_BYTES> keep{};
    logic<NET_BYTES> sop{};
    logic<NET_BYTES> eop{};
};

struct DecodedFrames
{
    std::vector<std::vector<uint8_t>> frames;
    std::vector<size_t> ipg;
    bool ok = true;
};

static uint8_t byte_at(const logic<NET_BITS>& data, size_t byte)
{
    return (uint8_t)data.bits(byte * 8 + 7, byte * 8);
}

static void set_byte(logic<NET_BITS>& data, size_t byte, uint8_t value)
{
    data.bits(byte * 8 + 7, byte * 8) = value;
}

static uint32_t frame_id(const std::vector<uint8_t>& frame)
{
    if (frame.size() < 4) return 0;
    return (uint32_t)frame[0] | ((uint32_t)frame[1] << 8)
        | ((uint32_t)frame[2] << 16) | ((uint32_t)frame[3] << 24);
}

static std::vector<uint8_t> random_frame(uint32_t id, size_t bytes,
    std::mt19937& random)
{
    std::vector<uint8_t> frame(bytes);
    for (uint8_t& byte : frame) byte = (uint8_t)random();
    frame[0] = (uint8_t)id;
    frame[1] = (uint8_t)(id >> 8);
    frame[2] = (uint8_t)(id >> 16);
    frame[3] = (uint8_t)(id >> 24);
    if (bytes >= 14) {
        frame[12] = 0x88;
        frame[13] = 0xb5;
    }
    return frame;
}

static std::vector<std::vector<uint8_t>> make_random_frames(uint32_t id_base,
    size_t count, uint32_t seed)
{
    static constexpr std::array<size_t, 12> corner_sizes = {
        64, 65, 66, 67, 127, 128, 129, 255, 256, 511, 1500, 2048};
    std::mt19937 random(seed);
    std::vector<std::vector<uint8_t>> frames;
    for (size_t index = 0; index < count; ++index) {
        size_t bytes = index < corner_sizes.size()
            ? corner_sizes[index]
            : 64 + random() % 1985;
        frames.push_back(random_frame(id_base + (uint32_t)index, bytes, random));
    }
    // An exact eight-idle first gap is possible when the first frame length is
    // 2 or 6 modulo eight and its START is on XGMII lane zero or four.
    if (frames.size() > 1 && frames[0].size() != 66) {
        frames[0] = random_frame(id_base, 66, random);
    }
    return frames;
}

static void append_idle(std::vector<XgmiiCharacter>& characters, size_t count)
{
    characters.insert(characters.end(), count, {XGMII_IDLE, true});
}

static void align_start(std::vector<XgmiiCharacter>& characters)
{
    size_t lane = characters.size() & 7;
    if (lane != 0 && lane != 4) append_idle(characters, lane < 4 ? 4 - lane : 8 - lane);
}

// Generate randomized RX stress IPGs down to eight octets as requested.  Eight
// idles is deliberately more aggressive than Clause 46 DIC transmit alignment,
// which can remove at most three from twelve; the complete stress burst still
// averages at least twelve idles between /T/ and the following /S/.
static std::vector<XgmiiBeat> pack_frames_for_pcs(
    const std::vector<std::vector<uint8_t>>& frames, uint32_t seed,
    std::vector<size_t>& actual_ipg)
{
    std::mt19937 random(seed);
    std::vector<XgmiiCharacter> characters;
    append_idle(characters, 16);
    int64_t budget = 0;
    size_t gap_sum = 0;

    for (size_t index = 0; index < frames.size(); ++index) {
        if (index != 0) {
            size_t gap_begin = characters.size();
            size_t requested;
            if (index == 1) {
                requested = 8;
            }
            else if (index + 1 == frames.size()) {
                const size_t required_total = 12 * (frames.size() - 1);
                requested = gap_sum < required_total ? required_total - gap_sum : 8;
                requested = std::max<size_t>(requested, 8);
            }
            else {
                requested = 8 + random() % 13;
                if (budget + (int64_t)requested - 12 < -8) {
                    requested = (size_t)(12 - budget - 8);
                }
            }
            append_idle(characters, requested);
            align_start(characters);
            size_t actual = characters.size() - gap_begin;
            actual_ipg.push_back(actual);
            gap_sum += actual;
            budget += (int64_t)actual - 12;
        }
        else {
            align_start(characters);
        }

        characters.push_back({XGMII_START, true});
        for (uint8_t byte : frames[index]) characters.push_back({byte, false});
        characters.push_back({XGMII_TERM, true});
    }
    append_idle(characters, NET_BYTES + 16);
    characters.resize((characters.size() + NET_BYTES - 1) / NET_BYTES * NET_BYTES,
        {XGMII_IDLE, true});

    std::vector<XgmiiBeat> beats(characters.size() / NET_BYTES);
    bool in_frame = false;
    for (size_t beat = 0; beat < beats.size(); ++beat) {
        beats[beat].in_frame_before = in_frame;
        for (size_t byte = 0; byte < NET_BYTES; ++byte) {
            const XgmiiCharacter& character = characters[beat * NET_BYTES + byte];
            set_byte(beats[beat].data, byte, character.data);
            beats[beat].control[byte] = character.control;
            if (character.control && character.data == XGMII_START) in_frame = true;
            if (character.control && character.data == XGMII_TERM) in_frame = false;
        }
        beats[beat].in_frame_after = in_frame;
    }
    return beats;
}

static DecodedFrames unpack_pcs_frames(const std::vector<XgmiiBeat>& beats)
{
    DecodedFrames result;
    std::vector<uint8_t> frame;
    bool in_frame = false;
    bool after_frame = false;
    size_t idle = 0;

    for (const XgmiiBeat& beat : beats) {
        for (size_t byte = 0; byte < NET_BYTES; ++byte) {
            uint8_t value = byte_at(beat.data, byte);
            bool control = (bool)beat.control[byte];
            if (!control) {
                if (!in_frame) result.ok = false;
                else frame.push_back(value);
            }
            else if (value == XGMII_START) {
                if (in_frame) result.ok = false;
                if (after_frame) result.ipg.push_back(idle);
                frame.clear();
                in_frame = true;
                after_frame = false;
                idle = 0;
            }
            else if (value == XGMII_TERM) {
                if (!in_frame) result.ok = false;
                else result.frames.push_back(frame);
                frame.clear();
                in_frame = false;
                after_frame = true;
                idle = 0;
            }
            else if (value == XGMII_IDLE) {
                if (in_frame) result.ok = false;
                else if (after_frame) ++idle;
            }
            else {
                result.ok = false;
            }
        }
    }
    if (in_frame) result.ok = false;
    return result;
}

static std::vector<NetworkBeat> pcs_to_network(const std::vector<XgmiiBeat>& beats,
    bool& ok)
{
    // The PCS stress source above is a convenient serialized frame generator;
    // the board, however, has two independent 64-bit MAC AXI interfaces.
    // Recreate those interfaces by assigning complete decoded frames
    // round-robin and never allowing a frame to cross a channel boundary.
    DecodedFrames decoded = unpack_pcs_frames(beats);
    ok &= decoded.ok;
    std::array<std::vector<NetworkBeat>, STREAMS> channels;
    for (size_t index = 0; index < decoded.frames.size(); ++index) {
        size_t channel = index % STREAMS;
        const auto& frame = decoded.frames[index];
        for (size_t offset = 0; offset < frame.size(); offset += MAC_BYTES) {
            NetworkBeat beat;
            size_t count = std::min(MAC_BYTES, frame.size() - offset);
            for (size_t byte = 0; byte < count; ++byte) {
                size_t flat = channel * MAC_BYTES + byte;
                set_byte(beat.data, flat, frame[offset + byte]);
                beat.keep[flat] = 1;
            }
            beat.sop[channel * MAC_BYTES] = offset == 0;
            if (offset + count == frame.size())
                beat.eop[channel * MAC_BYTES + count - 1] = 1;
            channels[channel].push_back(beat);
        }
    }

    size_t cycles = 0;
    for (const auto& channel : channels) cycles = std::max(cycles, channel.size());
    std::vector<NetworkBeat> result(cycles);
    for (size_t channel = 0; channel < STREAMS; ++channel) {
        for (size_t cycle = 0; cycle < channels[channel].size(); ++cycle) {
            for (size_t byte = 0; byte < MAC_BYTES; ++byte) {
                size_t flat = channel * MAC_BYTES + byte;
                set_byte(result[cycle].data, flat,
                    byte_at(channels[channel][cycle].data, flat));
                result[cycle].keep[flat] = channels[channel][cycle].keep[flat];
                result[cycle].sop[flat] = channels[channel][cycle].sop[flat];
                result[cycle].eop[flat] = channels[channel][cycle].eop[flat];
            }
        }
    }
    return result;
}

static std::vector<XgmiiBeat> network_to_pcs(const std::vector<NetworkBeat>& beats,
    bool& ok)
{
    std::vector<XgmiiCharacter> characters;
    bool in_frame = false;

    for (const NetworkBeat& beat : beats) {
        for (size_t byte = 0; byte < NET_BYTES; ++byte) {
            bool keep = (bool)beat.keep[byte];
            bool sop = (bool)beat.sop[byte];
            bool eop = (bool)beat.eop[byte];
            if (!keep) {
                if (sop || eop || in_frame) ok = false;
                characters.push_back({XGMII_IDLE, true});
                continue;
            }
            if (sop) {
                if (in_frame) ok = false;
                align_start(characters);
                characters.push_back({XGMII_START, true});
                in_frame = true;
            }
            else if (!in_frame) {
                ok = false;
            }
            characters.push_back({byte_at(beat.data, byte), false});
            if (eop) {
                if (!in_frame) ok = false;
                characters.push_back({XGMII_TERM, true});
                in_frame = false;
            }
        }
    }
    if (in_frame) ok = false;
    append_idle(characters, NET_BYTES + 16);
    characters.resize((characters.size() + NET_BYTES - 1) / NET_BYTES * NET_BYTES,
        {XGMII_IDLE, true});

    std::vector<XgmiiBeat> result(characters.size() / NET_BYTES);
    in_frame = false;
    for (size_t beat = 0; beat < result.size(); ++beat) {
        result[beat].in_frame_before = in_frame;
        for (size_t byte = 0; byte < NET_BYTES; ++byte) {
            const XgmiiCharacter& character = characters[beat * NET_BYTES + byte];
            set_byte(result[beat].data, byte, character.data);
            result[beat].control[byte] = character.control;
            if (character.control && character.data == XGMII_START) in_frame = true;
            if (character.control && character.data == XGMII_TERM) in_frame = false;
        }
        result[beat].in_frame_after = in_frame;
    }
    return result;
}

template<typename PCS>
class PcsLoopback
{
    PCS pcs;
    reg<u1> tx_valid;
    reg<logic<PCS::MAC_DATA_WIDTH>> tx_data;
    reg<logic<PCS::MAC_CONTROL_WIDTH>> tx_control;
    reg<u1> rx_valid;
    reg<logic<PCS::ENCODED_WIDTH>> rx_blocks;
    reg<logic<PCS::BLOCK_SLOTS>> rx_block_valid;
    bool loop_valid = false;
    logic<PCS::ENCODED_WIDTH> loop_blocks{};
    logic<PCS::BLOCK_SLOTS> loop_block_valid{};

    void strobe_inputs()
    {
        tx_valid.strobe();
        tx_data.strobe();
        tx_control.strobe();
        rx_valid.strobe();
        rx_blocks.strobe();
        rx_block_valid.strobe();
    }

    void cycle(bool reset)
    {
        strobe_inputs();
        pcs._work(reset);
        pcs._strobe();
        ++_system_clock;
    }

public:
    PcsLoopback()
    {
        pcs.tx_valid_in = _ASSIGN_REG(tx_valid);
        pcs.tx_data_in = _ASSIGN_REG(tx_data);
        pcs.tx_control_in = _ASSIGN_REG(tx_control);
        pcs.tx_ready_in = _ASSIGN(true);
        pcs.rx_valid_in = _ASSIGN_REG(rx_valid);
        pcs.rx_blocks_in = _ASSIGN_REG(rx_blocks);
        pcs.rx_block_valid_in = _ASSIGN_REG(rx_block_valid);
        pcs.rx_ready_in = _ASSIGN(true);
        pcs.__inst_name = "pcs";
        pcs._assign();
    }

    bool run(const std::vector<XgmiiBeat>& input, std::vector<XgmiiBeat>& output,
        size_t& pause_cycles, size_t& idle_characters)
    {
        std::deque<XgmiiBeat> expected;
        std::mt19937 random(0x20a55a);
        size_t next = 0;
        bool ok = true;
        bool previous_in_frame = false;
        pause_cycles = 0;
        idle_characters = 0;

        tx_valid._next = 0;
        rx_valid._next = 0;
        for (size_t reset_cycle = 0; reset_cycle < 3; ++reset_cycle) cycle(true);

        for (size_t cycle_index = 0; cycle_index < input.size() * 3 + 32; ++cycle_index) {
            // Always pause once before the first transfer, then add randomized
            // pauses only at frame boundaries.  This makes the PCS valid/IDLE
            // control check deterministic even when one aggregate beat holds
            // a short frame and therefore offers few boundary cycles.
            bool pause = next < input.size() && !previous_in_frame
                && (cycle_index == 0 || cycle_index % 11 == 7 || random() % 41 == 0);
            bool send = next < input.size() && !pause;
            tx_valid._next = send;
            tx_data._next = send ? input[next].data : logic<NET_BITS>(0);
            tx_control._next = send ? input[next].control : logic<NET_BYTES>(0);
            rx_valid._next = loop_valid;
            rx_blocks._next = loop_blocks;
            rx_block_valid._next = loop_block_valid;
            if (pause) ++pause_cycles;
            if (send) {
                if (!pcs.tx_ready_out()) ok = false;
                expected.push_back(input[next]);
                previous_in_frame = input[next].in_frame_after;
                for (size_t byte = 0; byte < NET_BYTES; ++byte) {
                    if ((bool)input[next].control[byte]
                        && byte_at(input[next].data, byte) == XGMII_IDLE) {
                        ++idle_characters;
                    }
                }
                ++next;
            }

            cycle(false);

            if (pcs.rx_valid_out()) {
                if (expected.empty()) {
                    ok = false;
                }
                else {
                    XgmiiBeat decoded = expected.front();
                    expected.pop_front();
                    decoded.data = pcs.rx_data_out();
                    decoded.control = pcs.rx_control_out();
                    output.push_back(decoded);
                }
                if ((uint64_t)pcs.rx_bad_block_out() != 0
                    || (uint64_t)pcs.rx_sequence_error_out() != 0) ok = false;
            }
            loop_valid = pcs.tx_valid_out();
            loop_blocks = pcs.tx_blocks_out();
            loop_block_valid = pcs.tx_block_valid_out();
            if (loop_valid && (uint64_t)pcs.tx_bad_block_out() != 0) ok = false;

            if (next == input.size() && expected.empty() && !loop_valid
                && !pcs.rx_valid_out()) break;
        }

        if (next != input.size() || !expected.empty() || output.size() != input.size()) {
            ok = false;
        }
        if (output.size() == input.size()) {
            for (size_t index = 0; index < input.size(); ++index) {
                if (output[index].data != input[index].data
                    || output[index].control != input[index].control) ok = false;
            }
        }
        return ok;
    }
};

class SmartNicModel
{
#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    SmartNIC<LANE_WIDTH> dut;
#endif

public:
    bool net_rx_valid = false;
    logic<NET_BITS> net_rx_data{};
    logic<NET_BYTES> net_rx_keep{};
    logic<NET_BYTES> net_rx_sop{};
    logic<NET_BYTES> net_rx_eop{};
    bool net_tx_ready = true;
    logic<READ_PORTS> read_valid{};
    logic<READ_PORTS * HANDLE_BITS> read_handle{};
    logic<READ_PORTS * FRAME_LENGTH_BITS> read_length{};
    logic<READ_PORTS> rx_ready = ~logic<READ_PORTS>(0);
    logic<STREAMS> tx_valid{};
    logic<STREAMS * L2_WIDTH> tx_data{};
    logic<STREAMS * L2_BYTES> tx_keep{};
    logic<STREAMS> tx_sop{};
    logic<STREAMS> tx_eop{};

#ifdef VERILATOR
    template<size_t WIDTH, typename Port>
    static logic<WIDTH> read_port(const Port& port)
    {
        logic<WIDTH> value = 0;
        std::memcpy(&value, &port, std::min(sizeof(value), sizeof(port)));
        return value;
    }

    template<typename Port, size_t WIDTH>
    static void write_port(Port& port, const logic<WIDTH>& value)
    {
        std::memset(&port, 0, sizeof(port));
        std::memcpy(&port, &value, std::min(sizeof(port), sizeof(value)));
    }

    void drive(bool reset)
    {
        dut.reset = reset;
        dut.net_rx_valid_in = net_rx_valid;
        write_port(dut.net_rx_data_in, net_rx_data);
        write_port(dut.net_rx_keep_in, net_rx_keep);
        write_port(dut.net_rx_sop_in, net_rx_sop);
        write_port(dut.net_rx_eop_in, net_rx_eop);
        dut.net_rx_raw_in = 1;
        dut.net_tx_ready_in = net_tx_ready;
        dut.l2_descriptor_ready_in = 1;
        write_port(dut.l2_rx_read_valid_in, read_valid);
        write_port(dut.l2_rx_read_handle_in, read_handle);
        write_port(dut.l2_rx_read_length_in, read_length);
        write_port(dut.l2_rx_ready_in, rx_ready);
        write_port(dut.l2_tx_valid_in, tx_valid);
        write_port(dut.l2_tx_data_in, tx_data);
        write_port(dut.l2_tx_keep_in, tx_keep);
        write_port(dut.l2_tx_sop_in, tx_sop);
        write_port(dut.l2_tx_eop_in, tx_eop);
    }
#endif

    SmartNicModel()
    {
#ifndef VERILATOR
        dut.net_rx_valid_in = _ASSIGN(net_rx_valid);
        dut.net_rx_data_in = _ASSIGN_REG(net_rx_data);
        dut.net_rx_keep_in = _ASSIGN_REG(net_rx_keep);
        dut.net_rx_sop_in = _ASSIGN_REG(net_rx_sop);
        dut.net_rx_eop_in = _ASSIGN_REG(net_rx_eop);
        dut.net_rx_raw_in = _ASSIGN(true);
        dut.net_tx_ready_in = _ASSIGN(net_tx_ready);
        dut.l2_descriptor_ready_in = _ASSIGN(true);
        dut.l2_rx_read_valid_in = _ASSIGN_REG(read_valid);
        dut.l2_rx_read_handle_in = _ASSIGN_REG(read_handle);
        dut.l2_rx_read_length_in = _ASSIGN_REG(read_length);
        dut.l2_rx_ready_in = _ASSIGN_REG(rx_ready);
        dut.l2_tx_valid_in = _ASSIGN_REG(tx_valid);
        dut.l2_tx_data_in = _ASSIGN_REG(tx_data);
        dut.l2_tx_keep_in = _ASSIGN_REG(tx_keep);
        dut.l2_tx_sop_in = _ASSIGN_REG(tx_sop);
        dut.l2_tx_eop_in = _ASSIGN_REG(tx_eop);
        dut.__inst_name = "smartnic";
        dut._assign();
#endif
    }

    void net_low(bool reset)
    {
#ifdef VERILATOR
        dut.net_clk = 0;
        drive(reset);
        dut.eval();
#else
        (void)reset;
#endif
    }

    void net_rise(bool reset)
    {
#ifdef VERILATOR
        drive(reset);
        dut.net_clk = 1;
        dut.eval();
        dut.net_clk = 0;
        dut.eval();
#else
        dut._work_net_clk(reset);
        dut._strobe_net_clk();
#endif
        ++_system_clock;
    }

    void l2_low(bool reset)
    {
        (void)reset;
    }

    void l2_rise(bool reset)
    {
        (void)reset;
        ++_system_clock;
    }

    bool net_rx_ready_out()
    {
#ifdef VERILATOR
        return dut.net_rx_ready_out;
#else
        return dut.net_rx_ready_out();
#endif
    }
    bool descriptor_valid_out()
    {
#ifdef VERILATOR
        return dut.l2_descriptor_valid_out;
#else
        return dut.l2_descriptor_valid_out();
#endif
    }
    logic<256> descriptor_data_out()
    {
#ifdef VERILATOR
        return read_port<256>(dut.l2_descriptor_data_out);
#else
        return dut.l2_descriptor_data_out();
#endif
    }
    uint32_t descriptor_word_out()
    {
#ifdef VERILATOR
        return dut.l2_descriptor_word_out;
#else
        return (uint32_t)dut.l2_descriptor_word_out();
#endif
    }
    bool descriptor_sop_out()
    {
#ifdef VERILATOR
        return dut.l2_descriptor_sop_out;
#else
        return dut.l2_descriptor_sop_out();
#endif
    }
    bool descriptor_eop_out()
    {
#ifdef VERILATOR
        return dut.l2_descriptor_eop_out;
#else
        return dut.l2_descriptor_eop_out();
#endif
    }
    logic<READ_PORTS> read_ready_out()
    {
#ifdef VERILATOR
        return read_port<READ_PORTS>(dut.l2_rx_read_ready_out);
#else
        return dut.l2_rx_read_ready_out();
#endif
    }
    logic<READ_PORTS> rx_valid_out()
    {
#ifdef VERILATOR
        return read_port<READ_PORTS>(dut.l2_rx_valid_out);
#else
        return dut.l2_rx_valid_out();
#endif
    }
    logic<READ_PORTS * 256> rx_data_out()
    {
#ifdef VERILATOR
        return read_port<READ_PORTS * 256>(dut.l2_rx_data_out);
#else
        return dut.l2_rx_data_out();
#endif
    }
    logic<READ_PORTS * 32> rx_keep_out()
    {
#ifdef VERILATOR
        return read_port<READ_PORTS * 32>(dut.l2_rx_keep_out);
#else
        return dut.l2_rx_keep_out();
#endif
    }
    logic<READ_PORTS> rx_eop_out()
    {
#ifdef VERILATOR
        return read_port<READ_PORTS>(dut.l2_rx_eop_out);
#else
        return dut.l2_rx_eop_out();
#endif
    }
    logic<STREAMS> tx_ready_out()
    {
#ifdef VERILATOR
        return read_port<STREAMS>(dut.l2_tx_ready_out);
#else
        return dut.l2_tx_ready_out();
#endif
    }
    bool net_tx_valid_out()
    {
#ifdef VERILATOR
        return dut.net_tx_valid_out;
#else
        return dut.net_tx_valid_out();
#endif
    }
    logic<NET_BITS> net_tx_data_out()
    {
#ifdef VERILATOR
        return read_port<NET_BITS>(dut.net_tx_data_out);
#else
        return dut.net_tx_data_out();
#endif
    }
    logic<NET_BYTES> net_tx_keep_out()
    {
#ifdef VERILATOR
        return read_port<NET_BYTES>(dut.net_tx_keep_out);
#else
        return dut.net_tx_keep_out();
#endif
    }
    logic<NET_BYTES> net_tx_sop_out()
    {
#ifdef VERILATOR
        return read_port<NET_BYTES>(dut.net_tx_sop_out);
#else
        return dut.net_tx_sop_out();
#endif
    }
    logic<NET_BYTES> net_tx_eop_out()
    {
#ifdef VERILATOR
        return read_port<NET_BYTES>(dut.net_tx_eop_out);
#else
        return dut.net_tx_eop_out();
#endif
    }
    bool protocol_error_out()
    {
#ifdef VERILATOR
        return dut.protocol_error_out;
#else
        return dut.protocol_error_out();
#endif
    }
};

class SmartNicPcsTest
{
    struct PendingRead
    {
        uint32_t handle = 0;
        std::vector<uint8_t> expected;
    };

    SmartNicModel dut;
    bool ok = true;

    void fail(const std::string& message)
    {
        if (ok) std::cerr << RATE_NAME << " SmartNIC PCS: " << message << '\n';
        ok = false;
    }

    void reset()
    {
        dut.net_rx_valid = false;
        dut.net_rx_data = 0;
        dut.net_rx_keep = 0;
        dut.net_rx_sop = 0;
        dut.net_rx_eop = 0;
        dut.read_valid = 0;
        dut.read_handle = 0;
        dut.read_length = 0;
        dut.tx_valid = 0;
        dut.tx_data = 0;
        dut.tx_keep = 0;
        dut.tx_sop = 0;
        dut.tx_eop = 0;
        for (size_t cycle = 0; cycle < 5; ++cycle) {
            dut.net_low(true);
            dut.net_rise(true);
            dut.l2_low(true);
            dut.l2_rise(true);
        }
    }

    bool run_rx(const std::vector<std::vector<uint8_t>>& expected_frames,
        const std::vector<NetworkBeat>& beats)
    {
        std::map<uint32_t, std::vector<uint8_t>> expected;
        for (const auto& frame : expected_frames) expected.emplace(frame_id(frame), frame);
        std::deque<PendingRead> pending;
        std::optional<PendingRead> active;
        std::vector<uint8_t> descriptor_bytes;
        std::vector<uint8_t> readback;
        size_t beat_index = 0;
        size_t descriptors = 0;
        size_t reads = 0;
        size_t rx_stalls = 0;
        const size_t net_period = 5;
        const size_t l2_period = net_period;

        reset();
        for (size_t tick = 1; tick < 800000 && ok; ++tick) {
            if (tick % net_period == 0) {
                dut.net_rx_valid = beat_index < beats.size();
                if (dut.net_rx_valid) {
                    dut.net_rx_data = beats[beat_index].data;
                    dut.net_rx_keep = beats[beat_index].keep;
                    dut.net_rx_sop = beats[beat_index].sop;
                    dut.net_rx_eop = beats[beat_index].eop;
                }
                else {
                    dut.net_rx_data = 0;
                    dut.net_rx_keep = 0;
                    dut.net_rx_sop = 0;
                    dut.net_rx_eop = 0;
                }
                dut.net_low(false);
                bool fire = dut.net_rx_valid && dut.net_rx_ready_out();
                if (dut.net_rx_valid && !dut.net_rx_ready_out()) ++rx_stalls;
                dut.net_rise(false);
                if (fire) ++beat_index;
            }

            if (tick % l2_period == 0) {
                bool command_started = false;
                if (!active && !(bool)dut.read_valid[0] && !pending.empty()) {
                    PendingRead command = pending.front();
                    pending.pop_front();
                    dut.read_handle.bits(HANDLE_BITS - 1, 0) = command.handle;
                    dut.read_length.bits(FRAME_LENGTH_BITS - 1, 0) =
                        command.expected.size();
                    dut.read_valid[0] = 1;
                    active = std::move(command);
                    readback.clear();
                    command_started = true;
                }

                dut.l2_low(false);
                bool command_fire = !command_started && (bool)dut.read_valid[0]
                    && (bool)dut.read_ready_out()[0];
                if (dut.descriptor_valid_out()) {
                    if (dut.descriptor_word_out() != descriptor_bytes.size() / 32
                        || dut.descriptor_sop_out() != descriptor_bytes.empty()
                        || dut.descriptor_eop_out() != (descriptor_bytes.size() == 128)) {
                        fail("descriptor serialization flags are inconsistent");
                    }
                    logic<256> word = dut.descriptor_data_out();
                    for (size_t byte = 0; byte < 32; ++byte) {
                        descriptor_bytes.push_back(
                            (uint8_t)word.bits(byte * 8 + 7, byte * 8));
                    }
                    if (dut.descriptor_eop_out()) {
                        RxDescriptorWord descriptor{};
                        if (descriptor_bytes.size() != sizeof(descriptor)) {
                            fail("descriptor is not five 256-bit words");
                        }
                        else {
                            std::memcpy(&descriptor, descriptor_bytes.data(), sizeof(descriptor));
                            uint32_t id = (uint32_t)descriptor.descriptor.packet_word0.raw.bits(31, 0);
                            auto found = expected.find(id);
                            if (found == expected.end()
                                || (uint32_t)descriptor.descriptor.packet_length
                                    != found->second.size()) {
                                fail("descriptor frame identity or length mismatch");
                            }
                            else {
                                pending.push_back({
                                    (uint32_t)descriptor.descriptor.packet_address,
                                    found->second});
                                expected.erase(found);
                            }
                        }
                        descriptor_bytes.clear();
                        ++descriptors;
                    }
                }
                if ((bool)dut.rx_valid_out()[0] && (bool)dut.rx_ready[0]) {
                    logic<READ_PORTS * 256> data = dut.rx_data_out();
                    logic<READ_PORTS * 32> keep = dut.rx_keep_out();
                    for (size_t byte = 0; byte < 32; ++byte) {
                        if ((bool)keep[byte]) {
                            readback.push_back((uint8_t)data.bits(byte * 8 + 7, byte * 8));
                        }
                    }
                    if ((bool)dut.rx_eop_out()[0]) {
                        if (!active || readback != active->expected) {
                            fail("RxRAM contents differ after PCS receive");
                        }
                        active.reset();
                        readback.clear();
                        ++reads;
                    }
                }
                dut.l2_rise(false);
                if (command_fire) dut.read_valid[0] = 0;
            }

            if (beat_index == beats.size() && descriptors == expected_frames.size()
                && reads == expected_frames.size() && pending.empty() && !active) break;
        }

        if (beat_index != beats.size() || descriptors != expected_frames.size()
            || reads != expected_frames.size() || !expected.empty()) {
            fail("RX phase did not complete every PCS frame");
        }
        // The PCS has no receive ready.  Sustained operation therefore requires
        // Network to accept every presented aggregate transfer in this test.
        if (rx_stalls != 0) fail("Network backpressured the non-stallable PCS RX path");
        if (dut.protocol_error_out()) fail("RX phase asserted protocol_error_out");
        std::print("  RX: PCS frames={} descriptors={} RxRAM reads={} stalls={}\n",
            expected_frames.size(), descriptors, reads, rx_stalls);
        return ok;
    }

    bool run_tx(const std::vector<std::vector<uint8_t>>& frames,
        std::vector<NetworkBeat>& output)
    {
        std::array<std::vector<size_t>, STREAMS> assigned;
        std::array<size_t, STREAMS> packet_index{};
        std::array<size_t, STREAMS> packet_offset{};
        std::map<uint32_t, std::vector<uint8_t>> expected;
        std::vector<uint8_t> assembling;
        bool in_frame = false;
        size_t completed = 0;
        const size_t net_period = 5;
        const size_t l2_period = net_period;

        for (size_t index = 0; index < frames.size(); ++index) {
            assigned[index % STREAMS].push_back(index);
            expected.emplace(frame_id(frames[index]), frames[index]);
        }
        reset();
        dut.net_tx_ready = true; // PCS tx_ready_out is permanently asserted.

        for (size_t tick = 1; tick < 800000 && ok; ++tick) {
            if (tick % l2_period == 0) {
                dut.tx_valid = 0;
                dut.tx_data = 0;
                dut.tx_keep = 0;
                dut.tx_sop = 0;
                dut.tx_eop = 0;
                for (size_t stream = 0; stream < STREAMS; ++stream) {
                    if (packet_index[stream] >= assigned[stream].size()) continue;
                    const auto& frame = frames[assigned[stream][packet_index[stream]]];
                    size_t offset = packet_offset[stream];
                    size_t bytes = std::min(L2_BYTES, frame.size() - offset);
                    dut.tx_valid[stream] = 1;
                    dut.tx_sop[stream] = offset == 0;
                    dut.tx_eop[stream] = offset + bytes == frame.size();
                    for (size_t byte = 0; byte < bytes; ++byte) {
                        dut.tx_data.bits(stream * L2_WIDTH + byte * 8 + 7,
                            stream * L2_WIDTH + byte * 8) = frame[offset + byte];
                        dut.tx_keep[stream * L2_BYTES + byte] = 1;
                    }
                }
                dut.l2_low(false);
                logic<STREAMS> ready = dut.tx_ready_out();
                dut.l2_rise(false);
                for (size_t stream = 0; stream < STREAMS; ++stream) {
                    if (!(bool)dut.tx_valid[stream] || !(bool)ready[stream]) continue;
                    const auto& frame = frames[assigned[stream][packet_index[stream]]];
                    packet_offset[stream] += std::min(L2_BYTES,
                        frame.size() - packet_offset[stream]);
                    if (packet_offset[stream] == frame.size()) {
                        packet_offset[stream] = 0;
                        ++packet_index[stream];
                    }
                }
            }

            if (tick % net_period == 0) {
                dut.net_low(false);
                if (dut.net_tx_valid_out() && dut.net_tx_ready) {
                    NetworkBeat beat;
                    beat.data = dut.net_tx_data_out();
                    beat.keep = dut.net_tx_keep_out();
                    beat.sop = dut.net_tx_sop_out();
                    beat.eop = dut.net_tx_eop_out();
                    output.push_back(beat);
                    for (size_t byte = 0; byte < NET_BYTES; ++byte) {
                        if (!(bool)beat.keep[byte]) {
                            if (in_frame) fail("Network inserted IDLE inside TX frame");
                            continue;
                        }
                        if ((bool)beat.sop[byte]) {
                            if (in_frame) fail("nested Network TX SOP");
                            assembling.clear();
                            in_frame = true;
                        }
                        if (!in_frame) fail("Network TX data without SOP");
                        assembling.push_back(byte_at(beat.data, byte));
                        if ((bool)beat.eop[byte]) {
                            uint32_t id = frame_id(assembling);
                            auto found = expected.find(id);
                            if (found == expected.end() || found->second != assembling) {
                                fail("Network TX frame mismatch before PCS");
                            }
                            else expected.erase(found);
                            assembling.clear();
                            in_frame = false;
                            ++completed;
                        }
                    }
                }
                dut.net_rise(false);
            }
            if (completed == frames.size()) break;
        }

        if (completed != frames.size() || !expected.empty() || in_frame) {
            fail("TX phase did not drain every L2 frame");
        }
        if (dut.protocol_error_out()) fail("TX phase asserted protocol_error_out");
        std::print("  TX: L2 frames={} aggregate Network beats={}\n",
            frames.size(), output.size());
        return ok;
    }

public:
    bool run()
    {
        std::print("{} SmartNIC + PCS integration ({}, {} bits @ 156.25 MHz)\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
            RATE_NAME, NET_BITS);

        auto rx_frames = make_random_frames(0x10000000, 24, 0x200400);
        std::vector<size_t> requested_ipg;
        auto rx_xgmii = pack_frames_for_pcs(rx_frames, 0x200d1c, requested_ipg);
        std::vector<XgmiiBeat> rx_decoded;
        size_t rx_pause = 0;
        size_t rx_idle = 0;
        PcsLoopback<SelectedPCS> rx_pcs;
        if (!rx_pcs.run(rx_xgmii, rx_decoded, rx_pause, rx_idle)) {
            fail("PCS RX encode/scramble/lane/decode loopback failed");
        }
        DecodedFrames rx_check = unpack_pcs_frames(rx_decoded);
        if (!rx_check.ok || rx_check.frames != rx_frames) {
            fail("PCS RX frame unpacking mismatch");
        }
        if (requested_ipg.empty() || *std::min_element(requested_ipg.begin(),
                requested_ipg.end()) != 8
            || std::accumulate(requested_ipg.begin(), requested_ipg.end(), size_t(0))
                < 12 * requested_ipg.size()) {
            fail("random RX stress did not reach 8-byte IPG or repay its average budget");
        }
        bool adapter_ok = true;
        auto rx_network = pcs_to_network(rx_decoded, adapter_ok);
        if (!adapter_ok) fail("PCS-to-Network IDLE/SOP/EOP adaptation failed");
        run_rx(rx_frames, rx_network);

        auto tx_frames = make_random_frames(0x20000000, 16, 0x200800);
        std::vector<NetworkBeat> tx_network;
        run_tx(tx_frames, tx_network);
        adapter_ok = true;
        auto tx_xgmii = network_to_pcs(tx_network, adapter_ok);
        if (!adapter_ok) fail("Network-to-PCS IDLE/SOP/EOP adaptation failed");
        std::vector<XgmiiBeat> tx_decoded;
        size_t tx_pause = 0;
        size_t tx_idle = 0;
        PcsLoopback<SelectedPCS> tx_pcs;
        if (!tx_pcs.run(tx_xgmii, tx_decoded, tx_pause, tx_idle)) {
            fail("PCS TX encode/scramble/lane/decode loopback failed");
        }
        DecodedFrames tx_check = unpack_pcs_frames(tx_decoded);
        if (!tx_check.ok || tx_check.frames.size() != tx_frames.size()) {
            fail("PCS TX frame unpacking failed");
        }
        else {
            std::map<uint32_t, std::vector<uint8_t>> expected;
            for (const auto& frame : tx_frames) expected.emplace(frame_id(frame), frame);
            for (const auto& frame : tx_check.frames) {
                auto found = expected.find(frame_id(frame));
                if (found == expected.end() || found->second != frame) {
                    fail("PCS TX frame payload mismatch");
                    break;
                }
                expected.erase(found);
            }
            if (!expected.empty()) fail("PCS TX lost frames");
        }
        if (!tx_check.ipg.empty()
            && *std::min_element(tx_check.ipg.begin(), tx_check.ipg.end()) < 12) {
            fail("SmartNIC TX produced less than the 12-byte nominal IPG");
        }
        if (rx_pause == 0 || tx_pause == 0 || rx_idle == 0 || tx_idle == 0) {
            fail("PCS test did not exercise explicit IDLE and safe valid-pause signaling");
        }

        std::print("  PCS controls: RX pauses={} TX pauses={} RX idles={} TX idles={}\n",
            rx_pause, tx_pause, rx_idle, tx_idle);
        std::print("  IPG: RX min={} average={:.2f}, TX min={}\n",
            *std::min_element(requested_ipg.begin(), requested_ipg.end()),
            (double)std::accumulate(requested_ipg.begin(), requested_ipg.end(), size_t(0))
                / requested_ipg.size(),
            tx_check.ipg.empty() ? 0 : *std::min_element(tx_check.ipg.begin(), tx_check.ipg.end()));
        std::print("{} SmartNIC + PCS integration {}\n", RATE_NAME, ok ? "PASSED" : "FAILED");
        return ok;
    }
};

static bool build_verilator_model(const char* source_file, const char* program_file)
{
#ifdef VERILATOR
    (void)source_file;
    (void)program_file;
    return true;
#else
    namespace fs = std::filesystem;
    const fs::path source = fs::absolute(source_file);
    const fs::path project_root = source.parent_path().parent_path().parent_path();
    // Generated RTL is next to the native test executable.  Do not depend on
    // the caller's working directory: developers commonly launch the test
    // from either the build directory or the repository root.
    const fs::path binary_dir = fs::absolute(program_file).parent_path();
    const fs::path generated = binary_dir / "generated_smartnic";
    const fs::path model_dir = binary_dir / "SmartNIC_pcs";
    const std::vector<std::string> includes = {
        source.parent_path().string(),
        (project_root / "rtl").string(),
        (project_root / "rtl" / "common").string(),
        (project_root / "rtl" / "network").string(),
        (project_root / "eth_pcs" / "rtl").string(),
        (project_root / "cpphdl" / "include").string(),
        project_root.string()};
    const std::vector<std::string> modules = {
        "Predef_pkg", "PacketParserFields_pkg", "PacketParserWord_pkg",
        "PacketParserHeaderId_pkg", "PacketParserFlags_pkg", "RxRAMWritePair_pkg",
        "RxDescriptor_pkg", "RxDescriptorWord_pkg", "RxDescriptorFlags_pkg",
        "SmartNicMemory", "Fifo", "SmartNicRAM", "InputBalancer", "PacketParser", "RxRAM",
        "RxFifo", "TxFifo", "OutputMerger", "Network", "PacketStream"};
    return VerilatorCompileInExactFolderFromGenerated(source.string(),
        model_dir.string(), "SmartNIC", generated, modules, includes);
#endif
}

} // namespace

int main(int argc, char** argv)
{
#ifdef VERILATOR
    Verilated::commandArgs(argc, argv);
#endif
    bool noveril = false;
    for (int arg = 1; arg < argc; ++arg) {
        if (std::strcmp(argv[arg], "--noveril") == 0) noveril = true;
    }

    bool ok = true;
#ifndef VERILATOR
    if (!noveril) {
        std::cout << "Building SmartNIC + PCS Verilator integration ================\n";
        ok = build_verilator_model(__FILE__, argv[0]);
        if (ok) {
            const std::filesystem::path model = std::filesystem::absolute(argv[0])
                .parent_path() / "SmartNIC_pcs" / "obj_dir" / "VSmartNIC";
            ok = std::system(std::format("'{}' --noveril", model.string()).c_str()) == 0;
        }
    }
#endif
    ok = SmartNicPcsTest().run() && ok;
    return ok ? 0 : 1;
}

#endif
