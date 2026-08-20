#pragma once

// Generic two-channel Ethernet AXI-stream generator used by network tests.
// Frames are assigned round-robin to independent 64-bit MAC channels.  Each
// channel starts packets at byte zero; physical IPG becomes idle AXI clocks.

#include <cpphdl.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

#include "../../Config.h"

using namespace cpphdl;

template<size_t LANE_WIDTH>
struct GenEthBeat
{
    static constexpr size_t LANES = NETWORK_PORTS;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t WORD_BITS = LANES * LANE_WIDTH;
    static constexpr size_t WORD_BYTES = LANES * LANE_BYTES;

    logic<WORD_BITS> data{};
    logic<WORD_BYTES> keep{};
    logic<WORD_BYTES> sop{};
    logic<WORD_BYTES> eop{};
};

template<size_t LANE_WIDTH>
class GenEthStream
{
public:
    static constexpr size_t LANES = NETWORK_PORTS;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t WORD_BYTES = LANES * LANE_BYTES;
    using Beat = GenEthBeat<LANE_WIDTH>;

private:
    struct WireByte
    {
        uint8_t data = 0;
        bool keep = false;
        bool sop = false;
        bool eop = false;
    };

    std::array<std::vector<WireByte>, LANES> wire;
    std::vector<Beat> beats;
    size_t cursor = 0;
    size_t next_lane = 0;
    bool finalized = false;

public:
    void clear(size_t initial_idle_bytes = 0)
    {
        size_t initial_idle = (initial_idle_bytes + LANE_BYTES - 1)
            / LANE_BYTES * LANE_BYTES;
        for (auto& lane : wire) lane.assign(initial_idle, WireByte{});
        beats.clear();
        cursor = 0;
        next_lane = 0;
        finalized = false;
    }

    void push(const std::vector<uint8_t>& packet, size_t ipg_bytes = 12)
    {
        if (finalized || packet.empty()) {
            return;
        }
        auto& lane = wire[next_lane];
        next_lane = (next_lane + 1) % LANES;
        for (size_t byte = 0; byte < packet.size(); ++byte) {
            lane.push_back({packet[byte], true, byte == 0,
                byte + 1 == packet.size()});
        }
        lane.resize((lane.size() + LANE_BYTES - 1) / LANE_BYTES * LANE_BYTES);
        size_t idle_words = (ipg_bytes + LANE_BYTES - 1) / LANE_BYTES;
        lane.resize(lane.size() + idle_words * LANE_BYTES);
    }

    void finalize()
    {
        size_t word_count;
        if (finalized) {
            return;
        }
        word_count = 0;
        for (const auto& lane : wire) {
            word_count = std::max(word_count,
                (lane.size() + LANE_BYTES - 1) / LANE_BYTES);
        }
        beats.assign(word_count, Beat{});
        for (size_t channel = 0; channel < LANES; ++channel) {
            for (size_t index = 0; index < wire[channel].size(); ++index) {
                size_t word = index / LANE_BYTES;
                size_t flat = channel * LANE_BYTES + index % LANE_BYTES;
                beats[word].data.bits(flat * 8 + 7, flat * 8) =
                    wire[channel][index].data;
                beats[word].keep[flat] = wire[channel][index].keep;
                beats[word].sop[flat] = wire[channel][index].sop;
                beats[word].eop[flat] = wire[channel][index].eop;
            }
        }
        finalized = true;
    }

    bool empty() const
    {
        return cursor >= beats.size();
    }

    size_t size() const
    {
        return beats.size();
    }

    size_t position() const
    {
        return cursor;
    }

    const Beat& front() const
    {
        return beats[cursor];
    }

    void pop()
    {
        if (!empty()) {
            ++cursor;
        }
    }
};
