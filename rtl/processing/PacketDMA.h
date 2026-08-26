#pragma once

// Per-cluster packet DMA.  Commands select one of four paths between the
// coherent Tribe L2 port, network RxRAM/TxFIFO, and the corresponding System
// RxQueue/TxQueue.  The command FIFO and MMIO registers are uncached CPU IOMEM.

#include "../common/Axi4Master.h"

using namespace cpphdl;

enum PacketDmaOperation : uint8_t
{
    DMA_SYSTEM_CPU = 0,
    DMA_CPU_SYSTEM = 1,
    DMA_CPU_NETWORK = 2,
    DMA_NETWORK_CPU = 3
};

enum PacketDmaState : uint8_t
{
    PACKET_DMA_IDLE,
    PACKET_DMA_ISSUE_NETWORK_READ,
    PACKET_DMA_WAIT_INPUT,
    PACKET_DMA_WRITE_ADDRESS,
    PACKET_DMA_WRITE_DATA,
    PACKET_DMA_WRITE_RESPONSE,
    PACKET_DMA_READ_ADDRESS,
    PACKET_DMA_READ_DATA,
    PACKET_DMA_SEND_OUTPUT,
    PACKET_DMA_POST_TX_CLEAR
};

enum PacketDmaError : uint8_t
{
    PACKET_DMA_ERROR_NONE,
    PACKET_DMA_ERROR_COMMAND_QUEUE_FULL,
    PACKET_DMA_ERROR_ZERO_LENGTH,
    PACKET_DMA_ERROR_FLAGS,
    PACKET_DMA_ERROR_DESTINATION_ALIGNMENT,
    PACKET_DMA_ERROR_SOURCE_ALIGNMENT,
    PACKET_DMA_ERROR_KEEP_GAP,
    PACKET_DMA_ERROR_SOP,
    PACKET_DMA_ERROR_BEAT_LENGTH,
    PACKET_DMA_ERROR_EOP_LENGTH,
    PACKET_DMA_ERROR_NON_EOP_LENGTH
};

enum PacketDmaPrefetchState : uint8_t
{
    PACKET_DMA_PREFETCH_IDLE,
    PACKET_DMA_PREFETCH_ISSUE,
    PACKET_DMA_PREFETCH_STREAM
};

template<size_t HANDLE_BITS = 16, size_t FRAME_LENGTH_BITS = 14,
    size_t CMD_DEPTH = 8, size_t AXI_ADDR_WIDTH = 32,
    size_t AXI_ID_WIDTH = 4, size_t AXI_DATA_WIDTH = 256,
    size_t BACKING_ADDR_WIDTH = 31, size_t BACKING_DEPTH = 64,
    size_t CLEAR_DEPTH = 512>
class PacketDMA : public Module
{
public:
    static constexpr size_t AXI_BYTES = AXI_DATA_WIDTH / 8;
    static constexpr size_t CMD_PTR_BITS = CMD_DEPTH <= 1 ? 1 : clog2(CMD_DEPTH);
    static constexpr size_t CMD_COUNT_BITS = clog2(CMD_DEPTH + 1);
    static constexpr size_t BACKING_PTR_BITS = BACKING_DEPTH <= 1
        ? 1 : clog2(BACKING_DEPTH);
    static constexpr size_t BACKING_COUNT_BITS = clog2(BACKING_DEPTH + 1);
    static constexpr size_t CLEAR_PTR_BITS = CLEAR_DEPTH <= 1
        ? 1 : clog2(CLEAR_DEPTH);
    static constexpr size_t CLEAR_COUNT_BITS = clog2(CLEAR_DEPTH + 1);

    static_assert(AXI_DATA_WIDTH == 256,
        "PacketDMA is matched to the Tribe 256-bit coherent L2 port");
    static_assert(CMD_DEPTH >= 2 && (CMD_DEPTH & (CMD_DEPTH - 1)) == 0,
        "PacketDMA command depth must be a power of two");
    static_assert(BACKING_DEPTH >= 2
        && (BACKING_DEPTH & (BACKING_DEPTH - 1)) == 0,
        "PacketDMA backing FIFO depth must be a power of two");
    static_assert(CLEAR_DEPTH >= 2 && (CLEAR_DEPTH & (CLEAR_DEPTH - 1)) == 0,
        "PacketDMA post-TX clear depth must be a power of two");

    enum Register : uint32_t
    {
        REG_RX_HANDLE = 0x00,
        REG_LENGTH = 0x04,
        REG_DESTINATION = 0x08,
        REG_FLAGS = 0x0c,
        REG_COMMAND = 0x10,
        REG_STATUS = 0x14,
        REG_COMPLETED = 0x18,
        REG_SOURCE = 0x1c,
        REG_LAST_OPERATION = 0x20,
        REG_CACHE_COMPLETED = 0x24,
        REG_NETWORK_PORT = 0x28,
        // Completion count for the main command engine only. REG_COMPLETED
        // remains the backwards-compatible aggregate including RX prefetch.
        REG_COMMAND_COMPLETED = 0x2c,
        // Four harts share one staged command register bank. Writing a
        // nonzero hart token acquires this lock only when it is free; writing
        // zero releases it. A failed acquisition leaves the current owner
        // unchanged and is detected by reading the register back.
        REG_COMMAND_LOCK = 0x30,
        REG_CLEAR_COMPLETED = 0x34,
        REG_CLEAR_ADDRESS = 0x38,
        // Firmware writes one after its CPU stores. PacketDMA persists a zero
        // line at REG_CLEAR_ADDRESS and completes only after DDR response.
        REG_CLEAR_NOTIFY = 0x3c,
        // Monotonic ticket assigned when a command enters CMD-FIFO. Firmware
        // can release the MMIO lock, wait for its own ticket to retire, and
        // safely reuse or clear that packet without draining the whole FIFO.
        REG_COMMAND_ISSUED = 0x40,
        // Bit 0 reserves room for one concurrent coherent backing beat plus
        // this CPU clear. Bits 15:8 report current backing FIFO occupancy.
        REG_CLEAR_STATUS = 0x44
    };

    static constexpr uint32_t COMMAND_PUSH = 1u << 0;
    static constexpr uint32_t FLAG_OPERATION_MASK = 3u;
    static constexpr uint32_t FLAG_CACHE_ALLOCATE = 1u << 2;
    static constexpr uint32_t FLAG_NETWORK_DISCARD = 1u << 3;
    static constexpr uint32_t FLAG_NETWORK_SYSTEM = 1u << 4;
    // CPU->Network source is an authoritative packet-ring address in DDR.
    // The CPU may still have touched its header coherently through L1/L2.
    static constexpr uint32_t FLAG_RING_SOURCE = 1u << 5;
    // CPU-requested post-TX ownership release. After accepting the final
    // Network beat, PacketDMA clears the first 32-byte source line in DDR.
    static constexpr uint32_t FLAG_CLEAR_SOURCE_AFTER_TX = 1u << 6;
    // Internal-only marker. DescriptorFetcher has already placed the RxRAM
    // read in the network-clock CDC FIFO while it enqueued this command, so
    // the main engine can enter WAIT_INPUT without another clock round trip.
    static constexpr uint32_t FLAG_NETWORK_PREFETCHED = 1u << 7;
    static constexpr uint32_t STATUS_BUSY = 1u << 0;
    static constexpr uint32_t STATUS_CMD_READY = 1u << 1;
    static constexpr uint32_t STATUS_ERROR = 1u << 2;

    struct Command
    {
        u<HANDLE_BITS> handle;
        u<FRAME_LENGTH_BITS> length;
        u32 source;
        u32 destination;
        u8 flags;
        u<8> network_port;
    } __PACKED;

    Axi4If<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> mmio;
    Axi4MasterIf<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> l2_dma;
    // Write-through packet backing store. Each cache-allocated RX line is
    // queued here at the identical physical address, making the lower DDR
    // half authoritative while the direct L2 allocation remains wire-rate.
    Axi4MasterIf<BACKING_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> backing_dma;

    // Whole-line coherent allocation path for network ingress. This is used
    // when FLAG_CACHE_ALLOCATE is set; other operations retain the AXI port.
    _PORT(bool) l2_line_valid_out;
    _PORT(u<AXI_ADDR_WIDTH>) l2_line_addr_out;
    _PORT(logic<AXI_DATA_WIDTH>) l2_line_data_out;
    _PORT(logic<AXI_BYTES>) l2_line_keep_out;
    _PORT(bool) l2_line_eop_out;
    _PORT(bool) l2_line_ready_in;
    // Processing returns one token only after an EOP line has crossed its
    // CPU/L2 CDC and has actually been accepted by the target L2.  Software
    // must not observe a packet as cache-resident merely because it entered
    // the forward CDC FIFO.
    _PORT(bool) l2_commit_valid_in;
    _PORT(bool) l2_commit_ready_out;

    // Network/RxRAM command and response path (DMA_NETWORK_CPU).
    _PORT(bool) rx_read_valid_out;
    _PORT(u<HANDLE_BITS>) rx_read_handle_out;
    _PORT(u<FRAME_LENGTH_BITS>) rx_read_length_out;
    _PORT(bool) rx_read_ready_in;
    _PORT(bool) rx_valid_in;
    _PORT(logic<AXI_DATA_WIDTH>) rx_data_in;
    _PORT(logic<AXI_BYTES>) rx_keep_in;
    _PORT(bool) rx_sop_in;
    _PORT(bool) rx_eop_in;
    _PORT(bool) rx_ready_out;

    // System TxQueue to CPU L2 path (DMA_SYSTEM_CPU).
    _PORT(bool) system_rx_valid_in;
    _PORT(logic<AXI_DATA_WIDTH>) system_rx_data_in;
    _PORT(logic<AXI_BYTES>) system_rx_keep_in;
    _PORT(bool) system_rx_sop_in;
    _PORT(bool) system_rx_eop_in;
    _PORT(bool) system_rx_ready_out;

    // CPU L2 to System RxQueue path (DMA_CPU_SYSTEM).
    _PORT(bool) system_tx_valid_out;
    _PORT(logic<AXI_DATA_WIDTH>) system_tx_data_out;
    _PORT(logic<AXI_BYTES>) system_tx_keep_out;
    _PORT(bool) system_tx_sop_out;
    _PORT(bool) system_tx_eop_out;
    _PORT(bool) system_tx_ready_in;

    // CPU L2 to Network TxFIFO path (DMA_CPU_NETWORK).
    _PORT(bool) network_tx_valid_out;
    _PORT(logic<AXI_DATA_WIDTH>) network_tx_data_out;
    _PORT(logic<AXI_BYTES>) network_tx_keep_out;
    _PORT(bool) network_tx_sop_out;
    _PORT(bool) network_tx_eop_out;
    _PORT(bool) network_tx_ready_in;
    _PORT(u<8>) network_tx_port_out;

    _PORT(bool) busy_out;
    _PORT(bool) command_ready_out;
    _PORT(bool) descriptor_command_ready_out;
    _PORT(bool) descriptor_command_valid_in;
    _PORT(u<HANDLE_BITS>) descriptor_command_handle_in;
    _PORT(u<FRAME_LENGTH_BITS>) descriptor_command_length_in;
    _PORT(bool) descriptor_command_system_in;
    _PORT(bool) descriptor_command_cache_in;
    _PORT(u32) descriptor_command_destination_in;
    _PORT(u<32>) completed_count_out;
    _PORT(u<32>) cache_completed_count_out;
    _PORT(u<32>) command_completed_count_out;
    _PORT(u<32>) clear_completed_count_out;
    _PORT(u<BACKING_COUNT_BITS>) backing_pending_count_out;
    _PORT(u<32>) backing_completed_beat_count_out;
    _PORT(u<2>) last_operation_out;
    _PORT(bool) protocol_error_out;
    _PORT(u<4>) protocol_error_reason_out;

private:
    struct BackingBeat
    {
        u<BACKING_ADDR_WIDTH> address;
        logic<AXI_DATA_WIDTH> data;
        logic<AXI_BYTES> keep;
        u1 clear;
        u1 eop;
    } __PACKED;

    enum BackingState : uint8_t
    {
        BACKING_IDLE,
        BACKING_ADDRESS,
        BACKING_DATA,
        BACKING_RESPONSE
    };

    reg<Command> command_reg[CMD_DEPTH];
    reg<u<CMD_PTR_BITS>> command_head_reg;
    reg<u<CMD_PTR_BITS>> command_tail_reg;
    reg<u<CMD_COUNT_BITS>> command_count_reg;

    reg<u<HANDLE_BITS>> stage_handle_reg;
    reg<u<FRAME_LENGTH_BITS>> stage_length_reg;
    reg<u32> stage_source_reg;
    reg<u32> stage_destination_reg;
    reg<u8> stage_flags_reg;
    reg<u<8>> stage_network_port_reg;
    reg<u1> stage_command_armed_reg;

    reg<u8> state_reg;
    reg<u<2>> operation_reg;
    reg<u8> active_flags_reg;
    reg<u<8>> active_network_port_reg;
    reg<u<AXI_ADDR_WIDTH>> source_reg;
    reg<u<AXI_ADDR_WIDTH>> source_base_reg;
    reg<u<AXI_ADDR_WIDTH>> destination_reg;
    reg<u<FRAME_LENGTH_BITS>> remaining_reg;
    reg<logic<AXI_DATA_WIDTH>> beat_data_reg;
    reg<logic<AXI_BYTES>> beat_keep_reg;
    reg<u1> beat_sop_reg;
    reg<u1> beat_eop_reg;
    reg<u1> first_beat_reg;
    reg<u<32>> completed_reg;
    reg<u<32>> cache_completed_reg;
    reg<u<32>> command_completed_reg;
    reg<u<32>> command_issued_reg;
    reg<u<8>> command_lock_reg;
    reg<u<32>> clear_completed_reg;
    reg<u<BACKING_ADDR_WIDTH>> clear_address_reg;
    reg<u1> clear_notify_armed_reg;
    reg<u<4>> cache_invalidate_count_reg;
    reg<u<2>> last_operation_reg;
    reg<u1> protocol_error_reg;
    reg<u<4>> protocol_error_reason_reg;

    // Cache-allocating descriptor traffic has an independent receive engine.
    // It uses RxRAM and Tribe's direct L2 line allocator while the main engine
    // may concurrently read L2 for CPU->Network/System traffic.
    reg<u<2>> prefetch_state_reg;
    reg<u<HANDLE_BITS>> prefetch_handle_reg;
    reg<u<FRAME_LENGTH_BITS>> prefetch_length_reg;
    reg<u<AXI_ADDR_WIDTH>> prefetch_destination_reg;
    reg<u<FRAME_LENGTH_BITS>> prefetch_remaining_reg;
    reg<u1> prefetch_first_reg;

    reg<u<AXI_ADDR_WIDTH>> write_addr_reg;
    reg<u<AXI_ID_WIDTH>> write_id_reg;
    reg<u1> write_addr_valid_reg;
    reg<u1> write_response_valid_reg;
    // An AXI master crossing Tribe's internal CDC may retain AWVALID for a
    // cycle after B retirement. Remember the accepted payload so a sticky
    // command-register write cannot enqueue the same DMA command twice.
    reg<u1> write_aw_seen_reg;
    reg<u<AXI_ADDR_WIDTH>> write_aw_seen_addr_reg;
    reg<u<AXI_ID_WIDTH>> write_aw_seen_id_reg;
    reg<u<AXI_ID_WIDTH>> read_id_reg;
    reg<u<AXI_ADDR_WIDTH>> read_addr_reg;
    reg<u1> read_pending_reg;
    reg<logic<AXI_DATA_WIDTH>> read_data_reg;
    reg<u1> read_valid_reg;

    reg<BackingBeat> backing_reg[BACKING_DEPTH];
    reg<u<BACKING_PTR_BITS>> backing_head_reg;
    reg<u<BACKING_PTR_BITS>> backing_tail_reg;
    reg<u<BACKING_COUNT_BITS>> backing_count_reg;
    reg<u<2>> backing_state_reg;
    reg<u<32>> backing_completed_reg;
    // Cache visibility requires both ordered sinks: the EOP line must be in
    // Tribe L2 and the corresponding write-through beat must have received a
    // DDR B response.  These counters pair the independently timed streams.
    reg<u<8>> l2_commit_pending_reg;
    reg<u<8>> backing_commit_pending_reg;
    reg<u<BACKING_ADDR_WIDTH>> post_clear_reg[CLEAR_DEPTH];
    reg<u<CLEAR_PTR_BITS>> post_clear_head_reg;
    reg<u<CLEAR_PTR_BITS>> post_clear_tail_reg;
    reg<u<CLEAR_COUNT_BITS>> post_clear_count_reg;

    u<HANDLE_BITS> current_handle_comb;
    u<FRAME_LENGTH_BITS> current_length_comb;
    logic<AXI_BYTES> output_keep_comb;

    Command current_command()
    {
        Command command = {};
        if ((uint32_t)command_count_reg != 0) {
            command = command_reg[(uint32_t)command_head_reg];
        }
        return command;
    }

    u<HANDLE_BITS>& current_handle_comb_func()
    {
        current_handle_comb = 0;
        if ((uint32_t)command_count_reg != 0) {
            current_handle_comb = command_reg[(uint32_t)command_head_reg].handle;
        }
        return current_handle_comb;
    }

    u<FRAME_LENGTH_BITS>& current_length_comb_func()
    {
        current_length_comb = 0;
        if ((uint32_t)command_count_reg != 0) {
            current_length_comb = command_reg[(uint32_t)command_head_reg].length;
        }
        return current_length_comb;
    }

    logic<AXI_BYTES>& output_keep_comb_func()
    {
        uint32_t byte;
        output_keep_comb = 0;
        for (byte = 0; byte < AXI_BYTES; ++byte) {
            output_keep_comb[byte] = byte < (uint32_t)remaining_reg;
        }
        return output_keep_comb;
    }

    uint32_t register_value(uint32_t address)
    {
        if (address == REG_RX_HANDLE) return (uint32_t)stage_handle_reg;
        if (address == REG_LENGTH) return (uint32_t)stage_length_reg;
        if (address == REG_DESTINATION) return (uint32_t)stage_destination_reg;
        if (address == REG_SOURCE) return (uint32_t)stage_source_reg;
        if (address == REG_FLAGS) return (uint32_t)stage_flags_reg;
        if (address == REG_NETWORK_PORT)
            return (uint32_t)stage_network_port_reg;
        if (address == REG_STATUS) {
            return (((uint32_t)state_reg != PACKET_DMA_IDLE
                    || (uint32_t)command_count_reg != 0
                    || (uint32_t)backing_count_reg != 0
                    || (uint32_t)backing_state_reg != BACKING_IDLE
                        ? STATUS_BUSY : 0))
                | ((uint32_t)command_count_reg < CMD_DEPTH ? STATUS_CMD_READY : 0)
                | ((bool)protocol_error_reg ? STATUS_ERROR : 0)
                | ((uint32_t)command_count_reg << 8);
        }
        if (address == REG_COMPLETED) return (uint32_t)completed_reg;
        if (address == REG_CACHE_COMPLETED)
            return (uint32_t)cache_completed_reg;
        if (address == REG_COMMAND_COMPLETED)
            return (uint32_t)command_completed_reg;
        if (address == REG_COMMAND_ISSUED)
            return (uint32_t)command_issued_reg;
        if (address == REG_COMMAND_LOCK)
            return (uint32_t)command_lock_reg;
        if (address == REG_CLEAR_COMPLETED)
            return (uint32_t)clear_completed_reg;
        if (address == REG_CLEAR_ADDRESS)
            return (uint32_t)clear_address_reg;
        if (address == REG_CLEAR_STATUS)
            return ((uint32_t)backing_count_reg < BACKING_DEPTH - 1 ? 1u : 0u)
                | ((uint32_t)backing_count_reg << 8);
        if (address == REG_LAST_OPERATION) return (uint32_t)last_operation_reg;
        return 0;
    }

    logic<AXI_DATA_WIDTH> register_read_value(uint32_t address)
    {
        logic<AXI_DATA_WIDTH> data = 0;
        uint32_t index;
        uint32_t lane = address & (AXI_BYTES - 1);
        uint32_t value = register_value(address & ~3u);
        for (index = 0; index < 32; ++index) {
            data[lane * 8 + index] = (value >> index) & 1u;
        }
        return data;
    }

    uint32_t write_value()
    {
        uint32_t value = 0;
        uint32_t index;
        uint32_t lane = (uint32_t)write_addr_reg & (AXI_BYTES - 1);
        for (index = 0; index < 32; ++index) {
            if (mmio.wdata_in()[lane * 8 + index]) value |= 1u << index;
        }
        return value;
    }

    uint32_t beat_bytes()
    {
        uint32_t count = 0;
        uint32_t index;
        bool gap = false;
        for (index = 0; index < AXI_BYTES; ++index) {
            if (beat_keep_reg[index]) {
                if (gap) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_KEEP_GAP;
                }
                ++count;
            }
            else gap = true;
        }
        return count;
    }

    uint32_t input_bytes(logic<AXI_BYTES> keep)
    {
        uint32_t count = 0;
        uint32_t index;
        bool gap = false;
        for (index = 0; index < AXI_BYTES; ++index) {
            if (keep[index]) {
                if (gap) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_KEEP_GAP;
                }
                ++count;
            }
            else gap = true;
        }
        return count;
    }

    bool output_ready()
    {
        if ((uint32_t)operation_reg == DMA_CPU_SYSTEM) {
            return system_tx_ready_in();
        }
        return network_tx_ready_in();
    }

    _LAZY_COMB(rx_l2_line_selected_comb, bool)
        rx_l2_line_selected_comb =
            (((uint32_t)prefetch_state_reg == PACKET_DMA_PREFETCH_STREAM)
                || ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                    && (uint32_t)operation_reg == DMA_NETWORK_CPU
                    && ((uint32_t)active_flags_reg & FLAG_CACHE_ALLOCATE) != 0))
            && rx_valid_in();
        return rx_l2_line_selected_comb;
    }

    _LAZY_COMB(clear_l2_line_selected_comb, bool)
        // Ingress has priority. At 80% wire load the remaining allocator slots
        // are ample for one 32-byte clear per 1516-byte transmitted packet.
        clear_l2_line_selected_comb =
            (uint32_t)post_clear_count_reg != 0
            && !rx_l2_line_selected_comb_func();
        return clear_l2_line_selected_comb;
    }

public:
    void _assign()
    {
        mmio.awready_out = _ASSIGN(!write_addr_valid_reg
            && !write_response_valid_reg
            && (!(bool)write_aw_seen_reg
                || mmio.awaddr_in() != write_aw_seen_addr_reg
                || mmio.awid_in() != write_aw_seen_id_reg));
        // Doorbells are lossless MMIO operations. Hold WREADY low while the
        // selected queue cannot accept the operation; the CPU store and AXI B
        // response then complete only after the command/clear is committed.
        // This closes the race between a preceding status read and an
        // independent descriptor or coherent backing write.
        mmio.wready_out = _ASSIGN(write_addr_valid_reg
            && !write_response_valid_reg
            && ((((uint32_t)write_addr_reg & ~3u) != REG_COMMAND)
                || (uint32_t)command_count_reg < CMD_DEPTH)
            && ((((uint32_t)write_addr_reg & ~3u) != REG_CLEAR_NOTIFY)
                || ((uint32_t)backing_count_reg < BACKING_DEPTH
                    && !(l2_line_valid_out() && l2_line_ready_in()))));
        mmio.bvalid_out = _ASSIGN_REG(write_response_valid_reg);
        mmio.bid_out = _ASSIGN_REG(write_id_reg);
        mmio.arready_out = _ASSIGN(!read_pending_reg && !read_valid_reg);
        mmio.rvalid_out = _ASSIGN_REG(read_valid_reg);
        mmio.rdata_out = _ASSIGN_REG(read_data_reg);
        mmio.rlast_out = _ASSIGN_REG(read_valid_reg);
        mmio.rid_out = _ASSIGN_REG(read_id_reg);

        l2_dma.awvalid_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WRITE_ADDRESS);
        l2_dma.awaddr_out = _ASSIGN_REG(destination_reg);
        l2_dma.awid_out = _ASSIGN((u<AXI_ID_WIDTH>)0);
        l2_dma.wvalid_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WRITE_DATA);
        l2_dma.wdata_out = _ASSIGN_REG(beat_data_reg);
        l2_dma.wstrb_out = _ASSIGN_REG(beat_keep_reg);
        l2_dma.wlast_out = _ASSIGN(true);
        l2_dma.bready_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WRITE_RESPONSE);
        l2_dma.arvalid_out = _ASSIGN((uint32_t)state_reg
            == PACKET_DMA_READ_ADDRESS
            && !((uint32_t)operation_reg == DMA_CPU_NETWORK
                && ((uint32_t)active_flags_reg & FLAG_RING_SOURCE) != 0));
        l2_dma.araddr_out = _ASSIGN_REG(source_reg);
        l2_dma.arid_out = _ASSIGN((u<AXI_ID_WIDTH>)0);
        l2_dma.rready_out = _ASSIGN((uint32_t)state_reg
            == PACKET_DMA_READ_DATA
            && !((uint32_t)operation_reg == DMA_CPU_NETWORK
                && ((uint32_t)active_flags_reg & FLAG_RING_SOURCE) != 0));

        l2_line_valid_out = _ASSIGN((uint32_t)backing_count_reg
            < BACKING_DEPTH
            && !(((uint32_t)state_reg == PACKET_DMA_READ_ADDRESS
                    || (uint32_t)state_reg == PACKET_DMA_READ_DATA)
                && !((uint32_t)operation_reg == DMA_CPU_NETWORK
                    && ((uint32_t)active_flags_reg & FLAG_RING_SOURCE) != 0))
            && (rx_l2_line_selected_comb_func()
                || clear_l2_line_selected_comb_func()));
        l2_line_addr_out = _ASSIGN(clear_l2_line_selected_comb_func()
            ? (u<AXI_ADDR_WIDTH>)post_clear_reg[
                (uint32_t)post_clear_head_reg]
            : ((uint32_t)prefetch_state_reg == PACKET_DMA_PREFETCH_STREAM
                ? (u<AXI_ADDR_WIDTH>)prefetch_destination_reg
                : (u<AXI_ADDR_WIDTH>)destination_reg));
        l2_line_data_out = _ASSIGN(clear_l2_line_selected_comb_func()
            ? (logic<AXI_DATA_WIDTH>)0 : (logic<AXI_DATA_WIDTH>)rx_data_in());
        l2_line_keep_out = _ASSIGN(clear_l2_line_selected_comb_func()
            ? (logic<AXI_BYTES>)-1 : (logic<AXI_BYTES>)rx_keep_in());
        // EOP is a CDC commit marker, not the periodic L1-invalidation hint
        // used by the synchronous OpenSwitch variant.  Every received packet
        // therefore generates exactly one reverse completion token; DDR/L2
        // clear writes do not masquerade as newly loaded packets.
        l2_line_eop_out = _ASSIGN(l2_line_valid_out()
            && l2_line_ready_in() && !clear_l2_line_selected_comb_func()
            && rx_eop_in());
        l2_commit_ready_out = _ASSIGN(true);

        rx_read_valid_out = _ASSIGN((uint32_t)prefetch_state_reg
                == PACKET_DMA_PREFETCH_ISSUE
            || ((uint32_t)prefetch_state_reg != PACKET_DMA_PREFETCH_ISSUE
                && (uint32_t)state_reg == PACKET_DMA_ISSUE_NETWORK_READ)
            || ((uint32_t)prefetch_state_reg != PACKET_DMA_PREFETCH_ISSUE
                && (uint32_t)state_reg != PACKET_DMA_ISSUE_NETWORK_READ
                && descriptor_command_valid_in()
                && !descriptor_command_cache_in()
                && (uint32_t)command_count_reg < CMD_DEPTH));
        rx_read_handle_out = _ASSIGN((uint32_t)prefetch_state_reg
                == PACKET_DMA_PREFETCH_ISSUE
            ? (u<HANDLE_BITS>)prefetch_handle_reg
            : ((uint32_t)state_reg == PACKET_DMA_ISSUE_NETWORK_READ
                ? (u<HANDLE_BITS>)current_handle_comb_func()
                : (u<HANDLE_BITS>)descriptor_command_handle_in()));
        rx_read_length_out = _ASSIGN((uint32_t)prefetch_state_reg
                == PACKET_DMA_PREFETCH_ISSUE
            ? (u<FRAME_LENGTH_BITS>)prefetch_length_reg
            : ((uint32_t)state_reg == PACKET_DMA_ISSUE_NETWORK_READ
                ? (u<FRAME_LENGTH_BITS>)current_length_comb_func()
                : (u<FRAME_LENGTH_BITS>)descriptor_command_length_in()));
        rx_ready_out = _ASSIGN((uint32_t)prefetch_state_reg
                == PACKET_DMA_PREFETCH_STREAM
            ? (l2_line_ready_in()
                && (uint32_t)backing_count_reg < BACKING_DEPTH
                && !(((uint32_t)state_reg == PACKET_DMA_READ_ADDRESS
                        || (uint32_t)state_reg == PACKET_DMA_READ_DATA)
                    && !((uint32_t)operation_reg == DMA_CPU_NETWORK
                        && ((uint32_t)active_flags_reg
                            & FLAG_RING_SOURCE) != 0)))
            : ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((((uint32_t)active_flags_reg & FLAG_CACHE_ALLOCATE) != 0)
                        ? (l2_line_ready_in()
                            && (uint32_t)backing_count_reg < BACKING_DEPTH)
                        : (((uint32_t)active_flags_reg
                                & FLAG_NETWORK_SYSTEM) == 0
                            || system_tx_ready_in()))));
        system_rx_ready_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
            && (uint32_t)operation_reg == DMA_SYSTEM_CPU);

        system_tx_valid_out = _ASSIGN(((uint32_t)state_reg
                == PACKET_DMA_SEND_OUTPUT
                && (uint32_t)operation_reg == DMA_CPU_SYSTEM)
            || ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0
                && rx_valid_in()));
        network_tx_valid_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_SEND_OUTPUT
            && (uint32_t)operation_reg == DMA_CPU_NETWORK);
        system_tx_data_out = _ASSIGN(
            ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
            ? rx_data_in() : (logic<AXI_DATA_WIDTH>)beat_data_reg);
        network_tx_data_out = _ASSIGN_REG(beat_data_reg);
        system_tx_keep_out = _ASSIGN(
            ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
            ? rx_keep_in() : (logic<AXI_BYTES>)beat_keep_reg);
        network_tx_keep_out = _ASSIGN_REG(beat_keep_reg);
        system_tx_sop_out = _ASSIGN(
            ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
            ? rx_sop_in() : (bool)beat_sop_reg);
        network_tx_sop_out = _ASSIGN_REG(beat_sop_reg);
        system_tx_eop_out = _ASSIGN(
            ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
            ? rx_eop_in() : (bool)beat_eop_reg);
        network_tx_eop_out = _ASSIGN_REG(beat_eop_reg);
        network_tx_port_out = _ASSIGN_REG(active_network_port_reg);

        busy_out = _ASSIGN((uint32_t)state_reg != PACKET_DMA_IDLE
            || (uint32_t)command_count_reg != 0
            || (uint32_t)backing_count_reg != 0
            || (uint32_t)backing_state_reg != BACKING_IDLE);
        command_ready_out = _ASSIGN((uint32_t)command_count_reg < CMD_DEPTH);
        descriptor_command_ready_out = _ASSIGN(
            descriptor_command_cache_in()
                ? (uint32_t)prefetch_state_reg == PACKET_DMA_PREFETCH_IDLE
                : ((uint32_t)command_count_reg < CMD_DEPTH
                    && (uint32_t)prefetch_state_reg
                        != PACKET_DMA_PREFETCH_ISSUE
                    && (uint32_t)state_reg
                        != PACKET_DMA_ISSUE_NETWORK_READ));
        completed_count_out = _ASSIGN_REG(completed_reg);
        cache_completed_count_out = _ASSIGN_REG(cache_completed_reg);
        command_completed_count_out = _ASSIGN_REG(command_completed_reg);
        clear_completed_count_out = _ASSIGN_REG(clear_completed_reg);
        last_operation_out = _ASSIGN_REG(last_operation_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
        protocol_error_reason_out = _ASSIGN_REG(protocol_error_reason_reg);
        backing_pending_count_out = _ASSIGN_REG(backing_count_reg);
        backing_completed_beat_count_out = _ASSIGN_REG(backing_completed_reg);

        backing_dma.awvalid_out = _ASSIGN((uint32_t)backing_state_reg
            == BACKING_ADDRESS && (uint32_t)backing_count_reg != 0);
        backing_dma.awaddr_out = _ASSIGN((u<BACKING_ADDR_WIDTH>)
            backing_reg[(uint32_t)backing_head_reg].address);
        backing_dma.awid_out = _ASSIGN((u<AXI_ID_WIDTH>)0);
        backing_dma.wvalid_out = _ASSIGN(((uint32_t)backing_state_reg
                == BACKING_ADDRESS
            || (uint32_t)backing_state_reg == BACKING_DATA)
            && (uint32_t)backing_count_reg != 0);
        backing_dma.wdata_out = _ASSIGN(
            (logic<AXI_DATA_WIDTH>)backing_reg[
                (uint32_t)backing_head_reg].data);
        backing_dma.wstrb_out = _ASSIGN(
            (logic<AXI_BYTES>)backing_reg[(uint32_t)backing_head_reg].keep);
        backing_dma.wlast_out = _ASSIGN(true);
        backing_dma.bready_out = _ASSIGN((uint32_t)backing_state_reg
            == BACKING_RESPONSE);
        // Network TX streams from the authoritative DDR packet ring. Cores
        // still inspect headers through coherent L1/L2, while bulk payload
        // reads no longer block the direct L2 ingress allocator.
        backing_dma.arvalid_out = _ASSIGN((uint32_t)state_reg
            == PACKET_DMA_READ_ADDRESS
            && (uint32_t)operation_reg == DMA_CPU_NETWORK
            && ((uint32_t)active_flags_reg & FLAG_RING_SOURCE) != 0);
        backing_dma.araddr_out = _ASSIGN(
            (u<BACKING_ADDR_WIDTH>)source_reg);
        backing_dma.arid_out = _ASSIGN((u<AXI_ID_WIDTH>)0);
        backing_dma.rready_out = _ASSIGN((uint32_t)state_reg
            == PACKET_DMA_READ_DATA
            && (uint32_t)operation_reg == DMA_CPU_NETWORK
            && ((uint32_t)active_flags_reg & FLAG_RING_SOURCE) != 0);
    }

    void _work(bool reset)
    {
        uint32_t slot;
        uint32_t address;
        uint32_t value;
        uint32_t count;
        uint32_t bytes;
        bool push;
        bool pop;
        bool descriptor_push;
        bool input_valid;
        bool input_sop;
        bool input_eop;
        bool backing_push;
        bool backing_pop;
        uint32_t completed_events;
        uint32_t backing_count;
        uint32_t l2_commits;
        uint32_t backing_commits;
        uint32_t post_clear_count;
        logic<AXI_DATA_WIDTH> input_data;
        logic<AXI_BYTES> input_keep;
        Command command;
        Command staged;

        count = (uint32_t)command_count_reg;
        push = false;
        pop = false;
        descriptor_push = false;
        command = current_command();
        backing_count = (uint32_t)backing_count_reg;
        backing_push = l2_line_valid_out() && l2_line_ready_in();
        backing_pop = false;
        completed_events = 0;
        l2_commits = (uint32_t)l2_commit_pending_reg;
        backing_commits = (uint32_t)backing_commit_pending_reg;
        post_clear_count = (uint32_t)post_clear_count_reg;

        if (backing_push) {
            backing_reg[(uint32_t)backing_tail_reg]._next.address =
                (u<BACKING_ADDR_WIDTH>)l2_line_addr_out();
            backing_reg[(uint32_t)backing_tail_reg]._next.data =
                l2_line_data_out();
            backing_reg[(uint32_t)backing_tail_reg]._next.keep =
                l2_line_keep_out();
            backing_reg[(uint32_t)backing_tail_reg]._next.clear =
                clear_l2_line_selected_comb_func();
            backing_reg[(uint32_t)backing_tail_reg]._next.eop =
                l2_line_eop_out();
            backing_tail_reg._next = ((uint32_t)backing_tail_reg + 1)
                & (BACKING_DEPTH - 1);
            ++backing_count;
            if (clear_l2_line_selected_comb_func()) {
                post_clear_head_reg._next =
                    ((uint32_t)post_clear_head_reg + 1) & (CLEAR_DEPTH - 1);
                --post_clear_count;
            }
        }
        if ((uint32_t)backing_state_reg == BACKING_IDLE
            && backing_count != 0) {
            backing_state_reg._next = BACKING_ADDRESS;
        }
        else if ((uint32_t)backing_state_reg == BACKING_ADDRESS
            && backing_dma.awvalid_out() && backing_dma.awready_in()) {
            backing_state_reg._next = backing_dma.wvalid_out()
                    && backing_dma.wready_in()
                ? BACKING_RESPONSE : BACKING_DATA;
        }
        else if ((uint32_t)backing_state_reg == BACKING_DATA
            && backing_dma.wvalid_out() && backing_dma.wready_in()) {
            backing_state_reg._next = BACKING_RESPONSE;
        }
        else if ((uint32_t)backing_state_reg == BACKING_RESPONSE
            && backing_dma.bvalid_in() && backing_dma.bready_out()) {
            // Turn directly to the next queued address. Returning through
            // IDLE inserted a full CPU-clock bubble per 32-byte beat, reducing
            // backing bandwidth below the sustained two-port ingress rate.
            backing_state_reg._next = backing_count > 1
                ? BACKING_ADDRESS : BACKING_IDLE;
            backing_head_reg._next = ((uint32_t)backing_head_reg + 1)
                & (BACKING_DEPTH - 1);
            backing_pop = true;
            backing_completed_reg._next = backing_completed_reg + 1;
            if (backing_reg[(uint32_t)backing_head_reg].clear)
                clear_completed_reg._next = clear_completed_reg + 1;
            if (backing_reg[(uint32_t)backing_head_reg].eop)
                ++backing_commits;
        }
        if (backing_pop) --backing_count;
        backing_count_reg._next = backing_count;

        // Dedicated coherent RX prefetch. DescriptorFetcher holds valid until
        // this ready/valid handshake, so no descriptor can be accepted twice.
        if (descriptor_command_valid_in()
            && descriptor_command_cache_in()
            && descriptor_command_ready_out()) {
            prefetch_handle_reg._next = descriptor_command_handle_in();
            prefetch_length_reg._next = descriptor_command_length_in();
            prefetch_destination_reg._next =
                descriptor_command_destination_in();
            prefetch_remaining_reg._next = descriptor_command_length_in();
            prefetch_first_reg._next = true;
            prefetch_state_reg._next = PACKET_DMA_PREFETCH_ISSUE;
        }
        else if ((uint32_t)prefetch_state_reg == PACKET_DMA_PREFETCH_ISSUE
            && rx_read_ready_in()) {
            prefetch_state_reg._next = PACKET_DMA_PREFETCH_STREAM;
        }
        else if ((uint32_t)prefetch_state_reg == PACKET_DMA_PREFETCH_STREAM
            && rx_l2_line_selected_comb_func()
            && l2_line_valid_out() && l2_line_ready_in()) {
            bytes = input_bytes(rx_keep_in());
            if ((bool)prefetch_first_reg != rx_sop_in()) {
                protocol_error_reg._next = true;
                protocol_error_reason_reg._next = PACKET_DMA_ERROR_SOP;
            }
            if (bytes == 0 || bytes > (uint32_t)prefetch_remaining_reg) {
                protocol_error_reg._next = true;
                protocol_error_reason_reg._next = PACKET_DMA_ERROR_BEAT_LENGTH;
            }
            if (rx_eop_in()) {
                if (bytes != (uint32_t)prefetch_remaining_reg) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_EOP_LENGTH;
                }
                if ((uint32_t)cache_invalidate_count_reg == 0)
                    cache_invalidate_count_reg._next = 9;
                else cache_invalidate_count_reg._next =
                    cache_invalidate_count_reg - 1;
                prefetch_state_reg._next = PACKET_DMA_PREFETCH_IDLE;
            }
            else {
                if (bytes != AXI_BYTES
                    || bytes >= (uint32_t)prefetch_remaining_reg) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_NON_EOP_LENGTH;
                }
                prefetch_destination_reg._next =
                    prefetch_destination_reg + AXI_BYTES;
                prefetch_remaining_reg._next =
                    prefetch_remaining_reg - bytes;
                prefetch_first_reg._next = false;
            }
        }

        if (mmio.awvalid_in() && mmio.awready_out()) {
            write_addr_reg._next = mmio.awaddr_in();
            write_id_reg._next = mmio.awid_in();
            write_addr_valid_reg._next = true;
            write_aw_seen_reg._next = true;
            write_aw_seen_addr_reg._next = mmio.awaddr_in();
            write_aw_seen_id_reg._next = mmio.awid_in();
        }
        if (!mmio.awvalid_in()) write_aw_seen_reg._next = false;
        if (mmio.wvalid_in() && mmio.wready_out()) {
            address = (uint32_t)write_addr_reg & ~3u;
            value = write_value();
            if (address == REG_RX_HANDLE) {
                stage_handle_reg._next = value;
                stage_command_armed_reg._next = true;
            }
            else if (address == REG_LENGTH) {
                stage_length_reg._next = value;
                stage_command_armed_reg._next = true;
            }
            else if (address == REG_SOURCE) {
                stage_source_reg._next = value;
                stage_command_armed_reg._next = true;
            }
            else if (address == REG_DESTINATION) {
                stage_destination_reg._next = value;
                stage_command_armed_reg._next = true;
            }
            else if (address == REG_FLAGS) {
                stage_flags_reg._next = value;
                stage_command_armed_reg._next = true;
            }
            else if (address == REG_NETWORK_PORT) {
                stage_network_port_reg._next = value;
                stage_command_armed_reg._next = true;
            }
            else if (address == REG_COMMAND_LOCK) {
                if (value == 0 || (uint32_t)command_lock_reg == 0
                    || (uint32_t)command_lock_reg == (value & 0xffu)) {
                    command_lock_reg._next = value & 0xffu;
                }
            }
            else if (address == REG_CLEAR_ADDRESS) {
                clear_address_reg._next = value & ~(AXI_BYTES - 1);
                clear_notify_armed_reg._next = true;
            }
            else if (address == REG_CLEAR_NOTIFY && value != 0
                && clear_notify_armed_reg) {
                if (backing_count < BACKING_DEPTH && !backing_push) {
                    backing_reg[(uint32_t)backing_tail_reg]._next.address =
                        clear_address_reg;
                    backing_reg[(uint32_t)backing_tail_reg]._next.data = 0;
                    backing_reg[(uint32_t)backing_tail_reg]._next.keep =
                        (logic<AXI_BYTES>)-1;
                    backing_reg[(uint32_t)backing_tail_reg]._next.clear = true;
                    backing_reg[(uint32_t)backing_tail_reg]._next.eop = false;
                    backing_tail_reg._next =
                        ((uint32_t)backing_tail_reg + 1)
                            & (BACKING_DEPTH - 1);
                    ++backing_count;
                    backing_count_reg._next = backing_count;
                    clear_notify_armed_reg._next = false;
                }
                else {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_COMMAND_QUEUE_FULL;
                }
            }
            else if (address == REG_COMMAND && (value & COMMAND_PUSH) != 0
                && stage_command_armed_reg) {
                push = count < CMD_DEPTH;
                if (!push) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_COMMAND_QUEUE_FULL;
#ifndef SYNTHESIS
                    std::print(stderr,
                        "{}: PacketDMA command queue full count={} completed={} length={} flags={}\n",
                        __inst_name, count, (uint32_t)completed_reg,
                        (uint32_t)stage_length_reg,
                        (uint32_t)stage_flags_reg);
#endif
                }
                else if ((uint32_t)stage_length_reg == 0) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_ZERO_LENGTH;
                    push = false;
                }
                else if (((uint32_t)stage_flags_reg
                        & ~(FLAG_OPERATION_MASK | FLAG_CACHE_ALLOCATE
                            | FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM
                            | FLAG_RING_SOURCE
                            | FLAG_CLEAR_SOURCE_AFTER_TX)) != 0
                    || (((uint32_t)stage_flags_reg
                            & (FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM)) != 0
                        && ((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            != DMA_NETWORK_CPU)
                    || (((uint32_t)stage_flags_reg & FLAG_NETWORK_DISCARD) != 0
                        && ((uint32_t)stage_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
                    || (((uint32_t)stage_flags_reg & FLAG_RING_SOURCE) != 0
                        && ((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            != DMA_CPU_NETWORK)
                    || (((uint32_t)stage_flags_reg
                            & FLAG_CLEAR_SOURCE_AFTER_TX) != 0
                        && (((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                                != DMA_CPU_NETWORK
                            || ((uint32_t)stage_flags_reg & FLAG_RING_SOURCE)
                                == 0))) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_FLAGS;
                    push = false;
                }
                if (push && ((((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            == DMA_NETWORK_CPU
                        || ((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            == DMA_SYSTEM_CPU))
                    && ((uint32_t)stage_destination_reg & (AXI_BYTES - 1)) != 0) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_DESTINATION_ALIGNMENT;
                    push = false;
                }
                if (push && ((((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            == DMA_CPU_SYSTEM
                        || ((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            == DMA_CPU_NETWORK))
                    && ((uint32_t)stage_source_reg & (AXI_BYTES - 1)) != 0) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_SOURCE_ALIGNMENT;
                    push = false;
                }
            }
            write_addr_valid_reg._next = false;
            write_response_valid_reg._next = true;
        }
        if (write_response_valid_reg && mmio.bready_in()) {
            write_response_valid_reg._next = false;
        }
        if (mmio.arvalid_in() && mmio.arready_out()) {
            read_id_reg._next = mmio.arid_in();
            read_addr_reg._next = mmio.araddr_in();
            read_pending_reg._next = true;
        }
        if (read_pending_reg && !read_valid_reg) {
            read_data_reg._next = register_read_value(
                (uint32_t)read_addr_reg);
            read_valid_reg._next = true;
            read_pending_reg._next = false;
        }
        if (read_valid_reg && mmio.rready_in()) read_valid_reg._next = false;

        if (descriptor_command_valid_in() && !descriptor_command_cache_in()
            && count < CMD_DEPTH && !push) {
            staged = {};
            staged.handle = descriptor_command_handle_in();
            staged.length = descriptor_command_length_in();
            staged.destination = descriptor_command_destination_in();
            staged.flags = DMA_NETWORK_CPU
                | (descriptor_command_cache_in() ? FLAG_CACHE_ALLOCATE
                    : (descriptor_command_system_in()
                        ? FLAG_NETWORK_SYSTEM : FLAG_NETWORK_DISCARD))
                | (rx_read_ready_in() ? FLAG_NETWORK_PREFETCHED : 0);
            push = true;
            descriptor_push = true;
        }

        if (push) {
            if (!descriptor_push) {
                staged = {};
                staged.handle = stage_handle_reg;
                staged.length = stage_length_reg;
                staged.source = stage_source_reg;
                staged.destination = stage_destination_reg;
                staged.flags = stage_flags_reg;
                staged.network_port = stage_network_port_reg;
                stage_command_armed_reg._next = false;
            }
            command_reg[(uint32_t)command_tail_reg]._next = staged;
            command_tail_reg._next = ((uint32_t)command_tail_reg + 1)
                & (CMD_DEPTH - 1);
            command_issued_reg._next = command_issued_reg + 1;
            ++count;
        }

        if ((uint32_t)state_reg == PACKET_DMA_IDLE && count != 0) {
            if ((uint32_t)command_count_reg == 0 && push) command = staged;
            operation_reg._next = (uint32_t)command.flags & FLAG_OPERATION_MASK;
            active_flags_reg._next = command.flags;
            active_network_port_reg._next = command.network_port;
            source_reg._next = command.source;
            source_base_reg._next = command.source;
            destination_reg._next = command.destination;
            remaining_reg._next = command.length;
            first_beat_reg._next = true;
            if (((uint32_t)command.flags & FLAG_OPERATION_MASK)
                    == DMA_NETWORK_CPU
                && (uint32_t)prefetch_state_reg
                    != PACKET_DMA_PREFETCH_IDLE) {
                // The single RxRAM response channel belongs to prefetch until
                // its current packet reaches EOP.
            }
            else if (((uint32_t)command.flags & FLAG_OPERATION_MASK)
                == DMA_NETWORK_CPU) {
                state_reg._next = ((uint32_t)command.flags
                        & FLAG_NETWORK_PREFETCHED) != 0
                    ? PACKET_DMA_WAIT_INPUT
                    : PACKET_DMA_ISSUE_NETWORK_READ;
            }
            else if (((uint32_t)command.flags & FLAG_OPERATION_MASK)
                == DMA_SYSTEM_CPU) {
                state_reg._next = PACKET_DMA_WAIT_INPUT;
            }
            else {
                state_reg._next = PACKET_DMA_READ_ADDRESS;
            }
        }
        else if ((uint32_t)state_reg == PACKET_DMA_ISSUE_NETWORK_READ
            && rx_read_ready_in()) {
            state_reg._next = PACKET_DMA_WAIT_INPUT;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT) {
            input_valid = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_valid_in() : system_rx_valid_in();
            input_data = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_data_in() : system_rx_data_in();
            input_keep = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_keep_in() : system_rx_keep_in();
            input_sop = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_sop_in() : system_rx_sop_in();
            input_eop = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_eop_in() : system_rx_eop_in();
            if ((uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg
                    & (FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM)) != 0) {
                if (input_valid
                    && (((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) == 0
                        || system_tx_ready_in())) {
                    bytes = input_bytes(input_keep);
                    if ((bool)first_beat_reg != input_sop) {
                        protocol_error_reg._next = true;
                        protocol_error_reason_reg._next = PACKET_DMA_ERROR_SOP;
                    }
                    if (bytes == 0 || bytes > (uint32_t)remaining_reg) {
                        protocol_error_reg._next = true;
                        protocol_error_reason_reg._next =
                            PACKET_DMA_ERROR_BEAT_LENGTH;
                    }
                    if (input_eop) {
                        if (bytes != (uint32_t)remaining_reg) {
                            protocol_error_reg._next = true;
                            protocol_error_reason_reg._next =
                                PACKET_DMA_ERROR_EOP_LENGTH;
                        }
                        ++completed_events;
                        command_completed_reg._next =
                            command_completed_reg + 1;
                        last_operation_reg._next = operation_reg;
                        state_reg._next = PACKET_DMA_IDLE;
                        pop = count != 0;
                    }
                    else {
                        if (bytes != AXI_BYTES
                            || bytes >= (uint32_t)remaining_reg) {
                            protocol_error_reg._next = true;
                            protocol_error_reason_reg._next =
                                PACKET_DMA_ERROR_NON_EOP_LENGTH;
                        }
                        remaining_reg._next = remaining_reg - bytes;
                        first_beat_reg._next = false;
                    }
                }
            }
            else if (input_valid
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_CACHE_ALLOCATE) != 0
                && l2_line_valid_out() && l2_line_ready_in()) {
                bytes = input_bytes(input_keep);
                if ((bool)first_beat_reg != input_sop) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_SOP;
                }
                if (bytes == 0 || bytes > (uint32_t)remaining_reg) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_BEAT_LENGTH;
                }
                if (input_eop) {
                    if (bytes != (uint32_t)remaining_reg) {
                        protocol_error_reg._next = true;
                        protocol_error_reason_reg._next =
                            PACKET_DMA_ERROR_EOP_LENGTH;
                    }
                    command_completed_reg._next = command_completed_reg + 1;
                    if ((uint32_t)cache_invalidate_count_reg == 0)
                        cache_invalidate_count_reg._next = 9;
                    else cache_invalidate_count_reg._next =
                        cache_invalidate_count_reg - 1;
                    last_operation_reg._next = operation_reg;
                    state_reg._next = PACKET_DMA_IDLE;
                    pop = count != 0;
                }
                else {
                    if (bytes != AXI_BYTES || bytes >= (uint32_t)remaining_reg) {
                        protocol_error_reg._next = true;
                        protocol_error_reason_reg._next =
                            PACKET_DMA_ERROR_NON_EOP_LENGTH;
                    }
                    destination_reg._next = destination_reg + AXI_BYTES;
                    remaining_reg._next = remaining_reg - bytes;
                    first_beat_reg._next = false;
                }
            }
            else if (input_valid
                && ((uint32_t)operation_reg != DMA_NETWORK_CPU
                    || ((uint32_t)active_flags_reg & FLAG_CACHE_ALLOCATE) == 0)) {
                beat_data_reg._next = input_data;
                beat_keep_reg._next = input_keep;
                beat_sop_reg._next = input_sop;
                beat_eop_reg._next = input_eop;
                if ((bool)first_beat_reg != input_sop) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_SOP;
                }
                first_beat_reg._next = false;
                state_reg._next = PACKET_DMA_WRITE_ADDRESS;
            }
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WRITE_ADDRESS
            && l2_dma.awready_in()) {
            state_reg._next = PACKET_DMA_WRITE_DATA;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WRITE_DATA
            && l2_dma.wready_in()) {
            state_reg._next = PACKET_DMA_WRITE_RESPONSE;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WRITE_RESPONSE
            && l2_dma.bvalid_in()) {
            bytes = beat_bytes();
            if (bytes == 0 || bytes > (uint32_t)remaining_reg) {
                protocol_error_reg._next = true;
                protocol_error_reason_reg._next = PACKET_DMA_ERROR_BEAT_LENGTH;
            }
            if (beat_eop_reg) {
                if (bytes != (uint32_t)remaining_reg) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_EOP_LENGTH;
                }
                ++completed_events;
                command_completed_reg._next = command_completed_reg + 1;
                last_operation_reg._next = operation_reg;
                state_reg._next = PACKET_DMA_IDLE;
                pop = count != 0;
            }
            else {
                if (bytes != AXI_BYTES || bytes >= (uint32_t)remaining_reg) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_NON_EOP_LENGTH;
                }
                destination_reg._next = destination_reg + AXI_BYTES;
                remaining_reg._next = remaining_reg - bytes;
                state_reg._next = PACKET_DMA_WAIT_INPUT;
            }
        }
        else if ((uint32_t)state_reg == PACKET_DMA_READ_ADDRESS
            && (((uint32_t)operation_reg == DMA_CPU_NETWORK
                    && ((uint32_t)active_flags_reg & FLAG_RING_SOURCE) != 0)
                ? backing_dma.arready_in() : l2_dma.arready_in())) {
            state_reg._next = PACKET_DMA_READ_DATA;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_READ_DATA
            && (((uint32_t)operation_reg == DMA_CPU_NETWORK
                    && ((uint32_t)active_flags_reg & FLAG_RING_SOURCE) != 0)
                ? backing_dma.rvalid_in() : l2_dma.rvalid_in())) {
            beat_data_reg._next = ((uint32_t)operation_reg == DMA_CPU_NETWORK
                    && ((uint32_t)active_flags_reg & FLAG_RING_SOURCE) != 0)
                ? backing_dma.rdata_in() : l2_dma.rdata_in();
            beat_keep_reg._next = output_keep_comb_func();
            beat_sop_reg._next = first_beat_reg;
            beat_eop_reg._next = (uint32_t)remaining_reg <= AXI_BYTES;
            state_reg._next = PACKET_DMA_SEND_OUTPUT;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_SEND_OUTPUT
            && output_ready()) {
            if ((uint32_t)remaining_reg <= AXI_BYTES) {
                if (((uint32_t)active_flags_reg
                        & FLAG_CLEAR_SOURCE_AFTER_TX) != 0) {
                    state_reg._next = PACKET_DMA_POST_TX_CLEAR;
                }
                else {
                    ++completed_events;
                    command_completed_reg._next = command_completed_reg + 1;
                    last_operation_reg._next = operation_reg;
                    state_reg._next = PACKET_DMA_IDLE;
                    pop = count != 0;
                }
            }
            else {
                source_reg._next = source_reg + AXI_BYTES;
                remaining_reg._next = remaining_reg - AXI_BYTES;
                first_beat_reg._next = false;
                state_reg._next = PACKET_DMA_READ_ADDRESS;
            }
        }
        else if ((uint32_t)state_reg == PACKET_DMA_POST_TX_CLEAR
            && post_clear_count < CLEAR_DEPTH) {
            post_clear_reg[(uint32_t)post_clear_tail_reg]._next =
                source_base_reg & ~(AXI_BYTES - 1);
            post_clear_tail_reg._next =
                ((uint32_t)post_clear_tail_reg + 1) & (CLEAR_DEPTH - 1);
            ++post_clear_count;
            ++completed_events;
            command_completed_reg._next = command_completed_reg + 1;
            last_operation_reg._next = operation_reg;
            state_reg._next = PACKET_DMA_IDLE;
            pop = count != 0;
        }

        post_clear_count_reg._next = post_clear_count;

        if (pop) {
            command_head_reg._next = ((uint32_t)command_head_reg + 1)
                & (CMD_DEPTH - 1);
            --count;
        }
        // A cache-load completion is published only after the final line is
        // installed in L2.  This event may coincide with an unrelated queued
        // command completion, so aggregate through a local event count rather
        // than allowing two nonblocking assignments to overwrite each other.
        if (l2_commit_valid_in() && l2_commit_ready_out()) {
            ++l2_commits;
        }
        if (l2_commits != 0 && backing_commits != 0) {
            --l2_commits;
            --backing_commits;
            cache_completed_reg._next = cache_completed_reg + 1;
            ++completed_events;
        }
        l2_commit_pending_reg._next = l2_commits;
        backing_commit_pending_reg._next = backing_commits;
        if (completed_events != 0)
            completed_reg._next = completed_reg + completed_events;

        command_count_reg._next = count;

        if (reset) {
            command_head_reg.clr();
            command_tail_reg.clr();
            command_count_reg.clr();
            stage_handle_reg.clr();
            stage_length_reg.clr();
            stage_source_reg.clr();
            stage_destination_reg.clr();
            stage_flags_reg.clr();
            stage_network_port_reg.clr();
            stage_command_armed_reg.clr();
            state_reg.clr();
            operation_reg.clr();
            active_flags_reg.clr();
            active_network_port_reg.clr();
            source_reg.clr();
            source_base_reg.clr();
            destination_reg.clr();
            remaining_reg.clr();
            beat_data_reg.clr();
            beat_keep_reg.clr();
            beat_sop_reg.clr();
            beat_eop_reg.clr();
            first_beat_reg.clr();
            completed_reg.clr();
            cache_completed_reg.clr();
            command_completed_reg.clr();
            command_issued_reg.clr();
            command_lock_reg.clr();
            clear_completed_reg.clr();
            clear_address_reg.clr();
            clear_notify_armed_reg.clr();
            cache_invalidate_count_reg.set(9);
            last_operation_reg.clr();
            protocol_error_reg.clr();
            protocol_error_reason_reg.clr();
            prefetch_state_reg.clr();
            prefetch_handle_reg.clr();
            prefetch_length_reg.clr();
            prefetch_destination_reg.clr();
            prefetch_remaining_reg.clr();
            prefetch_first_reg.clr();
            write_addr_reg.clr();
            write_id_reg.clr();
            write_addr_valid_reg.clr();
            write_response_valid_reg.clr();
            write_aw_seen_reg.clr();
            write_aw_seen_addr_reg.clr();
            write_aw_seen_id_reg.clr();
            read_id_reg.clr();
            read_addr_reg.clr();
            read_pending_reg.clr();
            read_data_reg.clr();
            read_valid_reg.clr();
            backing_head_reg.clr();
            backing_tail_reg.clr();
            backing_count_reg.clr();
            backing_state_reg.clr();
            backing_completed_reg.clr();
            l2_commit_pending_reg.clr();
            backing_commit_pending_reg.clr();
            post_clear_head_reg.clr();
            post_clear_tail_reg.clr();
            post_clear_count_reg.clr();
            for (slot = 0; slot < CMD_DEPTH; ++slot) command_reg[slot].clr();
            for (slot = 0; slot < BACKING_DEPTH; ++slot)
                backing_reg[slot].clr();
            for (slot = 0; slot < CLEAR_DEPTH; ++slot)
                post_clear_reg[slot].clr();
        }
    }

    void _strobe()
    {
        uint32_t slot;
        for (slot = 0; slot < CMD_DEPTH; ++slot) command_reg[slot].strobe();
        command_head_reg.strobe();
        command_tail_reg.strobe();
        command_count_reg.strobe();
        stage_handle_reg.strobe();
        stage_length_reg.strobe();
        stage_source_reg.strobe();
        stage_destination_reg.strobe();
        stage_flags_reg.strobe();
        stage_network_port_reg.strobe();
        stage_command_armed_reg.strobe();
        state_reg.strobe();
        operation_reg.strobe();
        active_flags_reg.strobe();
        active_network_port_reg.strobe();
        source_reg.strobe();
        source_base_reg.strobe();
        destination_reg.strobe();
        remaining_reg.strobe();
        beat_data_reg.strobe();
        beat_keep_reg.strobe();
        beat_sop_reg.strobe();
        beat_eop_reg.strobe();
        first_beat_reg.strobe();
        completed_reg.strobe();
        cache_completed_reg.strobe();
        command_completed_reg.strobe();
        command_issued_reg.strobe();
        command_lock_reg.strobe();
        clear_completed_reg.strobe();
        clear_address_reg.strobe();
        clear_notify_armed_reg.strobe();
        cache_invalidate_count_reg.strobe();
        last_operation_reg.strobe();
        protocol_error_reg.strobe();
        protocol_error_reason_reg.strobe();
        prefetch_state_reg.strobe();
        prefetch_handle_reg.strobe();
        prefetch_length_reg.strobe();
        prefetch_destination_reg.strobe();
        prefetch_remaining_reg.strobe();
        prefetch_first_reg.strobe();
        write_addr_reg.strobe();
        write_id_reg.strobe();
        write_addr_valid_reg.strobe();
        write_response_valid_reg.strobe();
        write_aw_seen_reg.strobe();
        write_aw_seen_addr_reg.strobe();
        write_aw_seen_id_reg.strobe();
        read_id_reg.strobe();
        read_addr_reg.strobe();
        read_pending_reg.strobe();
        read_data_reg.strobe();
        read_valid_reg.strobe();
        for (slot = 0; slot < BACKING_DEPTH; ++slot)
            backing_reg[slot].strobe();
        backing_head_reg.strobe();
        backing_tail_reg.strobe();
        backing_count_reg.strobe();
        backing_state_reg.strobe();
        backing_completed_reg.strobe();
        l2_commit_pending_reg.strobe();
        backing_commit_pending_reg.strobe();
        for (slot = 0; slot < CLEAR_DEPTH; ++slot) post_clear_reg[slot].strobe();
        post_clear_head_reg.strobe();
        post_clear_tail_reg.strobe();
        post_clear_count_reg.strobe();
    }
};

template class PacketDMA<16, 14, 8, 32, 4, 256, 31, 64>;
