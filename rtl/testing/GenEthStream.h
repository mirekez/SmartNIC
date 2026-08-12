#pragma once

// Generic Ethernet aggregate-stream generator used by network-level tests.
// Frames are serialized in wire order with explicit IPG bytes, then each
// aggregate word is laid out as two adjacent IEEE-ordered lane slices:
// lane 0 byte 0 is earliest, followed by the rest of lane 0, then lane 1.

#include <cpphdl.h>

#include <algorithm>
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

    std::vector<WireByte> wire;
    std::vector<Beat> beats;
    size_t cursor = 0;
    bool finalized = false;

public:
    void clear(size_t initial_idle_bytes = 0)
    {
        wire.assign(initial_idle_bytes, WireByte{});
        beats.clear();
        cursor = 0;
        finalized = false;
    }

    void push(const std::vector<uint8_t>& packet, size_t ipg_bytes = 12)
    {
        if (finalized || packet.empty()) {
            return;
        }
        for (size_t byte = 0; byte < packet.size(); ++byte) {
            wire.push_back({packet[byte], true, byte == 0,
                byte + 1 == packet.size()});
        }
        wire.resize(wire.size() + ipg_bytes);
    }

    void finalize()
    {
        size_t word_count;
        if (finalized) {
            return;
        }
        word_count = (wire.size() + WORD_BYTES - 1) / WORD_BYTES;
        beats.assign(word_count, Beat{});
        for (size_t index = 0; index < wire.size(); ++index) {
            size_t word = index / WORD_BYTES;
            size_t flat = index % WORD_BYTES;
            beats[word].data.bits(flat * 8 + 7, flat * 8) =
                wire[index].data;
            beats[word].keep[flat] = wire[index].keep;
            beats[word].sop[flat] = wire[index].sop;
            beats[word].eop[flat] = wire[index].eop;
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
