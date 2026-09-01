`default_nettype none

import Predef_pkg::*;
import DescriptorFetcher_Register_pkg::*;


module DescriptorFetcher #(
    parameter DEPTH = 'h4
,   parameter AXI_ADDR_WIDTH = 'h20
,   parameter AXI_ID_WIDTH = 'h4
,   parameter AXI_DATA_WIDTH = 'h100
,   parameter HANDLE_BITS = 'h11
 )
 (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   input wire descriptor_valid_in
,   input wire[256-1:0] descriptor_data_in
,   input wire[3-1:0] descriptor_word_in
,   input wire descriptor_sop_in
,   input wire descriptor_eop_in
,   output wire descriptor_ready_out
,   input wire packet_command_ready_in
,   output wire packet_command_valid_out
,   output wire[HANDLE_BITS-1:0] packet_command_handle_out
,   output wire[14-1:0] packet_command_length_out
,   output wire packet_command_system_out
,   output wire packet_command_cache_out
,   output wire packet_command_network_out
,   output wire[8-1:0] packet_command_network_port_out
,   output wire[32-1:0] packet_command_destination_out
,   input wire mmio__awvalid_in
,   output wire mmio__awready_out
,   input wire[32-1:0] mmio__awaddr_in
,   input wire[4-1:0] mmio__awid_in
,   input wire mmio__wvalid_in
,   output wire mmio__wready_out
,   input wire[256-1:0] mmio__wdata_in
,   input wire[256/'h8-1:0] mmio__wstrb_in
,   input wire mmio__wlast_in
,   output wire mmio__bvalid_out
,   input wire mmio__bready_in
,   output wire[4-1:0] mmio__bid_out
,   input wire mmio__arvalid_in
,   output wire mmio__arready_out
,   input wire[32-1:0] mmio__araddr_in
,   input wire[4-1:0] mmio__arid_in
,   output wire mmio__rvalid_out
,   input wire mmio__rready_in
,   output wire[256-1:0] mmio__rdata_out
,   output wire mmio__rlast_out
,   output wire[4-1:0] mmio__rid_out
,   output wire descriptor_available_out
,   output wire[COUNT_BITS-1:0] descriptor_count_out
,   output wire prefetch_enabled_out
,   output wire auto_l2_enabled_out
,   output wire protocol_error_out
);
    localparam  DESCRIPTOR_BITS = 64'h500;
    localparam  DESCRIPTOR_WORD_BITS = 64'h100;
    localparam  DESCRIPTOR_WORDS = 64'h5;
    localparam  PTR_BITS = (DEPTH<='h1) ? ('h1) : ($clog2(DEPTH));
    localparam  COUNT_BITS = $clog2(DEPTH + 'h1);
    localparam  CONTROL_ENABLE = 'h1;
    localparam  CONTROL_AUTO_L2 = 'h2;
    localparam  ACTION_NEXT = 'h1;
    localparam  ACTION_DMA_DISCARD = 'h2;
    localparam  ACTION_DMA_SYSTEM = 'h4;
    localparam  ACTION_DMA_CACHE = 'h8;
    localparam  ACTION_DMA_NETWORK = 'h10;
    localparam  STATUS_AVAILABLE = 'h1;
    localparam  STATUS_PREFETCH_ENABLED = 'h2;
    localparam  STATUS_PROTOCOL_ERROR = 'h4;
    localparam  STATUS_DMA_READY = 'h8;


    // regs and combs
    reg[PTR_BITS-1:0] head_reg;
    reg[PTR_BITS-1:0] tail_reg;
    reg[COUNT_BITS-1:0] count_reg;
    reg[1280-1:0] assembly_reg;
    reg[3-1:0] assembly_word_reg;
    reg assembly_active_reg;
    reg enabled_reg;
    reg auto_l2_reg;
    reg[9-1:0] auto_slot_mask_reg;
    reg[32-1:0] auto_base_reg;
    reg[32-1:0] auto_sequence_reg;
    reg protocol_error_reg;
    reg packet_command_valid_reg;
    reg[HANDLE_BITS-1:0] packet_command_handle_reg;
    reg[14-1:0] packet_command_length_reg;
    reg packet_command_system_reg;
    reg packet_command_cache_reg;
    reg packet_command_network_reg;
    reg[8-1:0] packet_command_network_port_reg;
    reg[32-1:0] packet_command_destination_reg;
    reg[32-1:0] action_destination_reg;
    reg[AXI_ADDR_WIDTH-1:0] write_addr_reg;
    reg[AXI_ID_WIDTH-1:0] write_id_reg;
    reg write_addr_valid_reg;
    reg write_response_valid_reg;
    reg[AXI_ID_WIDTH-1:0] read_id_reg;
    reg[AXI_ADDR_WIDTH-1:0] read_addr_reg;
    reg[32-1:0] read_value_reg;
    reg[$clog2(AXI_DATA_WIDTH/'h8)-1:0] read_lane_reg;
    reg read_pending_reg;
    reg read_format_pending_reg;
    reg[AXI_DATA_WIDTH-1:0] read_data_reg;
    reg read_valid_reg;
    logic[1280-1:0] current_descriptor_comb;
    logic[1280-1:0] queue_write_data_comb;
    logic[AXI_DATA_WIDTH-1:0] register_read_comb;

    // members
    wire[$clog2(DEPTH)-1:0] queue_mem__write_addr_in;
    wire queue_mem__write_in;
    wire[DESCRIPTOR_BITS-1:0] queue_mem__write_data_in;
    wire[$clog2(DEPTH)-1:0] queue_mem__read_addr_in;
    wire[DESCRIPTOR_BITS-1:0] queue_mem__read_data_out;
    AsyncReadRam #(
        DESCRIPTOR_BITS
,       DEPTH
    ) queue_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(queue_mem__write_addr_in)
,       .write_in(queue_mem__write_in)
,       .write_data_in(queue_mem__write_data_in)
,       .read_addr_in(queue_mem__read_addr_in)
,       .read_data_out(queue_mem__read_data_out)
    );

    // tmp variables
    logic[PTR_BITS-1:0] head_reg_tmp;
    logic[PTR_BITS-1:0] tail_reg_tmp;
    logic[COUNT_BITS-1:0] count_reg_tmp;
    logic[1280-1:0] assembly_reg_tmp;
    logic[3-1:0] assembly_word_reg_tmp;
    logic assembly_active_reg_tmp;
    logic enabled_reg_tmp;
    logic auto_l2_reg_tmp;
    logic[9-1:0] auto_slot_mask_reg_tmp;
    logic[32-1:0] auto_base_reg_tmp;
    logic[32-1:0] auto_sequence_reg_tmp;
    logic protocol_error_reg_tmp;
    logic packet_command_valid_reg_tmp;
    logic[HANDLE_BITS-1:0] packet_command_handle_reg_tmp;
    logic[14-1:0] packet_command_length_reg_tmp;
    logic packet_command_system_reg_tmp;
    logic packet_command_cache_reg_tmp;
    logic packet_command_network_reg_tmp;
    logic[8-1:0] packet_command_network_port_reg_tmp;
    logic[32-1:0] packet_command_destination_reg_tmp;
    logic[32-1:0] action_destination_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] write_addr_reg_tmp;
    logic[AXI_ID_WIDTH-1:0] write_id_reg_tmp;
    logic write_addr_valid_reg_tmp;
    logic write_response_valid_reg_tmp;
    logic[AXI_ID_WIDTH-1:0] read_id_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] read_addr_reg_tmp;
    logic[32-1:0] read_value_reg_tmp;
    logic[$clog2(AXI_DATA_WIDTH/'h8)-1:0] read_lane_reg_tmp;
    logic read_pending_reg_tmp;
    logic read_format_pending_reg_tmp;
    logic[AXI_DATA_WIDTH-1:0] read_data_reg_tmp;
    logic read_valid_reg_tmp;


    always_comb begin : current_descriptor_comb_func  // current_descriptor_comb_func
        current_descriptor_comb = 'h0;
        if (unsigned'(32'(count_reg)) != 'h0) begin
            current_descriptor_comb = queue_mem__read_data_out;
        end
    end

    always_comb begin : queue_write_data_comb_func  // queue_write_data_comb_func
        logic[31:0] _bit;
        logic[31:0] word_index;
        queue_write_data_comb = assembly_reg;
        word_index=unsigned'(32'(descriptor_word_in));
        if (word_index>=DESCRIPTOR_WORDS) begin
            word_index='h0;
        end
        if (descriptor_sop_in) begin
            queue_write_data_comb = 'h0;
        end
        for (_bit='h0;_bit < DESCRIPTOR_WORD_BITS;_bit=_bit+1) begin
            queue_write_data_comb[(word_index*DESCRIPTOR_WORD_BITS) + _bit] = descriptor_data_in[_bit];
        end
    end

    function logic[31:0] descriptor_bits32 (input logic[31:0] bit_offset);
        logic[31:0] _bit;
        logic[31:0] value;
        logic[1280-1:0] descriptor;
        descriptor = current_descriptor_comb;
        value='h0;
        for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
            if (((bit_offset + _bit) < DESCRIPTOR_BITS) && descriptor[(bit_offset + _bit)]) begin
                value|='h1 <<< _bit;
            end
        end
        return value;
    endfunction

    function logic[31:0] register_value (input logic[31:0] address);
        logic[31:0] body_word;
        if (address == DescriptorFetcher_Register_pkg::REG_CONTROL) begin
            return ((enabled_reg) ? (CONTROL_ENABLE) : ('h0)) | ((auto_l2_reg) ? (CONTROL_AUTO_L2) : ('h0));
        end
        if (address == DescriptorFetcher_Register_pkg::REG_STATUS) begin
            return ((((((unsigned'(32'(count_reg)) != 'h0)) ? (STATUS_AVAILABLE) : ('h0)) | ((enabled_reg) ? (STATUS_PREFETCH_ENABLED) : ('h0))) | ((protocol_error_reg) ? (STATUS_PROTOCOL_ERROR) : ('h0))) | (((packet_command_ready_in && !packet_command_valid_reg)) ? (STATUS_DMA_READY) : ('h0))) | ((unsigned'(32'(count_reg)) <<< 'h8));
        end
        if (address == DescriptorFetcher_Register_pkg::REG_AUTO_SLOT_MASK) begin
            return unsigned'(32'(auto_slot_mask_reg));
        end
        if (address == DescriptorFetcher_Register_pkg::REG_AUTO_BASE) begin
            return unsigned'(32'(auto_base_reg));
        end
        if ((address>=DescriptorFetcher_Register_pkg::REG_DESCRIPTOR_BASE && (address < (DescriptorFetcher_Register_pkg::REG_DESCRIPTOR_BASE + (DESCRIPTOR_BITS/'h8)))) && (((address & 'h3)) == 'h0)) begin
            body_word=((address - DescriptorFetcher_Register_pkg::REG_DESCRIPTOR_BASE))/'h4;
            return descriptor_bits32(body_word*'h20);
        end
        if (address == DescriptorFetcher_Register_pkg::REG_PACKET_ADDRESS) begin
            return descriptor_bits32('h0);
        end
        if (address == DescriptorFetcher_Register_pkg::REG_PACKET_META) begin
            return descriptor_bits32('h20);
        end
        if (address == DescriptorFetcher_Register_pkg::REG_DESTINATION_MAC_LO) begin
            return descriptor_bits32('h100);
        end
        if (address == DescriptorFetcher_Register_pkg::REG_DESTINATION_MAC_HI) begin
            return descriptor_bits32('h120) & 'hFFFF;
        end
        if (address == DescriptorFetcher_Register_pkg::REG_SOURCE_MAC_LO) begin
            return descriptor_bits32('h130);
        end
        if (address == DescriptorFetcher_Register_pkg::REG_SOURCE_MAC_HI) begin
            return descriptor_bits32('h150) & 'hFFFF;
        end
        if (address>=DescriptorFetcher_Register_pkg::REG_SOURCE_IP0 && address<=DescriptorFetcher_Register_pkg::REG_SOURCE_IP3) begin
            return descriptor_bits32('h160 + (((((address - DescriptorFetcher_Register_pkg::REG_SOURCE_IP0))/'h4))*'h20));
        end
        if (address>=DescriptorFetcher_Register_pkg::REG_DESTINATION_IP0 && address<=DescriptorFetcher_Register_pkg::REG_DESTINATION_IP3) begin
            return descriptor_bits32('h1E0 + (((((address - DescriptorFetcher_Register_pkg::REG_DESTINATION_IP0))/'h4))*'h20));
        end
        if (address == DescriptorFetcher_Register_pkg::REG_PORTS) begin
            return descriptor_bits32('h260);
        end
        if (address == DescriptorFetcher_Register_pkg::REG_PROTOCOL) begin
            return descriptor_bits32('h280);
        end
        if (address == DescriptorFetcher_Register_pkg::REG_SOURCE_PORT) begin
            return descriptor_bits32('h40) & 'hFF;
        end
        if (address == DescriptorFetcher_Register_pkg::REG_ACTION_DESTINATION) begin
            return unsigned'(32'(action_destination_reg));
        end
        return 'h0;
    endfunction

    always_comb begin : register_read_comb_func  // register_read_comb_func
        logic[31:0] address;
        logic[31:0] byte_lane;
        logic[31:0] _bit;
        logic[31:0] value;
        register_read_comb = 'h0;
        address=unsigned'(32'(mmio__araddr_in));
        byte_lane=address & (((AXI_DATA_WIDTH/'h8) - 'h1));
        value=register_value(address & ~'h3);
        for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
            if (((byte_lane*'h8) + _bit) < AXI_DATA_WIDTH) begin
                register_read_comb[(byte_lane*'h8) + _bit] = ((value >>> _bit)) & 'h1;
            end
        end
    end

    function logic[31:0] write_value ();
        logic[31:0] _bit;
        logic[31:0] value;
        logic[31:0] byte_lane;
        value='h0;
        byte_lane=unsigned'(32'(write_addr_reg)) & (((AXI_DATA_WIDTH/'h8) - 'h1));
        for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
            if ((((byte_lane*'h8) + _bit) < AXI_DATA_WIDTH) && mmio__wdata_in[((byte_lane*'h8) + _bit)]) begin
                value|='h1 <<< _bit;
            end
        end
        return value;
    endfunction

    generate  // _assign
        assign queue_mem__write_addr_in = tail_reg;
        assign queue_mem__write_in = (descriptor_valid_in && descriptor_ready_out) && descriptor_eop_in;
        assign queue_mem__write_data_in = queue_write_data_comb;
        assign queue_mem__read_addr_in = head_reg;
        assign descriptor_ready_out = enabled_reg && (unsigned'(32'(count_reg)) < DEPTH);
        assign descriptor_available_out = unsigned'(32'(count_reg)) != 'h0;
        assign descriptor_count_out = count_reg;
        assign prefetch_enabled_out = enabled_reg;
        assign auto_l2_enabled_out = auto_l2_reg;
        assign protocol_error_out = protocol_error_reg;
        assign packet_command_valid_out = packet_command_valid_reg;
        assign packet_command_handle_out = packet_command_handle_reg;
        assign packet_command_length_out = packet_command_length_reg;
        assign packet_command_system_out = packet_command_system_reg;
        assign packet_command_cache_out = packet_command_cache_reg;
        assign packet_command_network_out = packet_command_network_reg;
        assign packet_command_network_port_out = packet_command_network_port_reg;
        assign packet_command_destination_out = unsigned'(32'(unsigned'(32'(packet_command_destination_reg))));
        assign mmio__awready_out = !write_addr_valid_reg && !write_response_valid_reg;
        assign mmio__wready_out = write_addr_valid_reg && !write_response_valid_reg;
        assign mmio__bvalid_out = write_response_valid_reg;
        assign mmio__bid_out = write_id_reg;
        assign mmio__arready_out = (!read_pending_reg && !read_format_pending_reg) && !read_valid_reg;
        assign mmio__rvalid_out = read_valid_reg;
        assign mmio__rdata_out = read_data_reg;
        assign mmio__rlast_out = read_valid_reg;
        assign mmio__rid_out = read_id_reg;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] count;
        logic[31:0] address;
        logic[31:0] value;
        logic[31:0] _bit;
        logic[31:0] word_index;
        logic[31:0] next_head;
        logic input_fire;
        logic pop;
        logic[1280-1:0] assembly;
        count=unsigned'(32'(count_reg));
        pop=0;
        input_fire=descriptor_valid_in && descriptor_ready_out;
        if (packet_command_valid_reg && packet_command_ready_in) begin
            packet_command_valid_reg_tmp = unsigned'(1'(0));
        end
        if (mmio__awvalid_in && mmio__awready_out) begin
            write_addr_reg_tmp = mmio__awaddr_in;
            write_id_reg_tmp = mmio__awid_in;
            write_addr_valid_reg_tmp = unsigned'(1'(1));
        end
        if (mmio__wvalid_in && mmio__wready_out) begin
            address=unsigned'(32'(write_addr_reg)) & ~'h3;
            value=write_value();
            if (address == DescriptorFetcher_Register_pkg::REG_CONTROL) begin
                enabled_reg_tmp = unsigned'(1'(((value & CONTROL_ENABLE)) != 'h0));
                auto_l2_reg_tmp = unsigned'(1'(((value & CONTROL_AUTO_L2)) != 'h0));
            end
            else begin
                if (address == DescriptorFetcher_Register_pkg::REG_AUTO_SLOT_MASK) begin
                    auto_slot_mask_reg_tmp = value & 'h1FF;
                end
                else begin
                    if (address == DescriptorFetcher_Register_pkg::REG_AUTO_BASE) begin
                        auto_base_reg_tmp = unsigned'(32'(value & ~'h7FF));
                    end
                    else begin
                        if (address == DescriptorFetcher_Register_pkg::REG_ACTION_DESTINATION) begin
                            action_destination_reg_tmp = unsigned'(32'(value));
                        end
                        else begin
                            if ((address == DescriptorFetcher_Register_pkg::REG_ACTION) && (((value & ACTION_NEXT)) != 'h0)) begin
                                if (((value & ((((ACTION_DMA_DISCARD | ACTION_DMA_SYSTEM) | ACTION_DMA_CACHE) | ACTION_DMA_NETWORK)))) == 'h0) begin
                                    pop=count != 'h0;
                                end
                                else begin
                                    if ((((count != 'h0) && packet_command_ready_in) && !packet_command_valid_reg) && (((((((((value & ACTION_DMA_DISCARD)) != 'h0)) + ((((value & ACTION_DMA_SYSTEM)) != 'h0))) + ((((value & ACTION_DMA_CACHE)) != 'h0))) + ((((value & ACTION_DMA_NETWORK)) != 'h0)))) == 'h1)) begin
                                        packet_command_handle_reg_tmp = descriptor_bits32('h0);
                                        packet_command_length_reg_tmp = descriptor_bits32('h20);
                                        packet_command_system_reg_tmp = unsigned'(1'(((value & ACTION_DMA_SYSTEM)) != 'h0));
                                        packet_command_cache_reg_tmp = unsigned'(1'(((value & ACTION_DMA_CACHE)) != 'h0));
                                        packet_command_network_reg_tmp = unsigned'(1'(((value & ACTION_DMA_NETWORK)) != 'h0));
                                        packet_command_network_port_reg_tmp = ((descriptor_bits32('h40) & 'h1)) ^ 'h1;
                                        packet_command_destination_reg_tmp = (((value & ACTION_DMA_CACHE)) != 'h0) ? (unsigned'(32'(action_destination_reg))) : (unsigned'(32'(unsigned'(32'h0))));
                                        packet_command_valid_reg_tmp = unsigned'(1'(1));
                                        pop=1;
                                    end
                                    else begin
                                        protocol_error_reg_tmp = unsigned'(1'(1));
                                    end
                                end
                            end
                        end
                    end
                end
            end
            write_addr_valid_reg_tmp = unsigned'(1'(0));
            write_response_valid_reg_tmp = unsigned'(1'(1));
        end
        if (write_response_valid_reg && mmio__bready_in) begin
            write_response_valid_reg_tmp = unsigned'(1'(0));
        end
        if (mmio__arvalid_in && mmio__arready_out) begin
            read_id_reg_tmp = mmio__arid_in;
            read_addr_reg_tmp = mmio__araddr_in;
            read_pending_reg_tmp = unsigned'(1'(1));
        end
        if ((read_pending_reg && !read_format_pending_reg) && !read_valid_reg) begin
            address=unsigned'(32'(read_addr_reg));
            read_value_reg_tmp = register_value(address & ~'h3);
            read_lane_reg_tmp = address & (((AXI_DATA_WIDTH/'h8) - 'h1));
            read_format_pending_reg_tmp = unsigned'(1'(1));
            read_pending_reg_tmp = unsigned'(1'(0));
        end
        if (read_format_pending_reg && !read_valid_reg) begin
            read_data_reg_tmp = 'h0;
            for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
                if (((unsigned'(32'(read_lane_reg))*'h8) + _bit) < AXI_DATA_WIDTH) begin
                    read_data_reg_tmp[(unsigned'(32'(read_lane_reg))*'h8) + _bit] = read_value_reg[_bit];
                end
            end
            read_valid_reg_tmp = unsigned'(1'(1));
            read_format_pending_reg_tmp = unsigned'(1'(0));
        end
        if (read_valid_reg && mmio__rready_in) begin
            read_valid_reg_tmp = unsigned'(1'(0));
        end
        if ((((auto_l2_reg && (count != 'h0)) && packet_command_ready_in) && !packet_command_valid_reg) && !pop) begin
            packet_command_handle_reg_tmp = descriptor_bits32('h0);
            packet_command_length_reg_tmp = descriptor_bits32('h20);
            packet_command_system_reg_tmp = unsigned'(1'(0));
            packet_command_cache_reg_tmp = unsigned'(1'(1));
            packet_command_network_reg_tmp = unsigned'(1'(0));
            packet_command_network_port_reg_tmp = 'h0;
            packet_command_destination_reg_tmp = unsigned'(32'(auto_base_reg + ((((unsigned'(32'(auto_sequence_reg)) & unsigned'(32'(auto_slot_mask_reg)))) <<< 'hB))));
            packet_command_valid_reg_tmp = unsigned'(1'(1));
            auto_sequence_reg_tmp = unsigned'(32'(auto_sequence_reg + 'h1));
            pop=1;
        end
        if (pop) begin
            next_head=((unsigned'(32'(head_reg)) + 'h1)) & ((DEPTH - 'h1));
            head_reg_tmp = next_head;
            --count;
        end
        if (input_fire) begin
            assembly = queue_write_data_comb;
            word_index=unsigned'(32'(descriptor_word_in));
            if (word_index>=DESCRIPTOR_WORDS) begin
                word_index='h0;
                protocol_error_reg_tmp = unsigned'(1'(1));
            end
            if (descriptor_sop_in) begin
                if (assembly_active_reg || (unsigned'(32'(descriptor_word_in)) != 'h0)) begin
                    protocol_error_reg_tmp = unsigned'(1'(1));
                end
                assembly_active_reg_tmp = unsigned'(1'(1));
                assembly_word_reg_tmp = 'h0;
            end
            if (!assembly_active_reg && !descriptor_sop_in) begin
                protocol_error_reg_tmp = unsigned'(1'(1));
            end
            if (unsigned'(32'(descriptor_word_in)) != unsigned'(32'(assembly_word_reg))) begin
                protocol_error_reg_tmp = unsigned'(1'(1));
            end
            assembly_reg_tmp = assembly;
            if (descriptor_eop_in) begin
                if (unsigned'(32'(descriptor_word_in)) != (DESCRIPTOR_WORDS - 'h1)) begin
                    protocol_error_reg_tmp = unsigned'(1'(1));
                end
                tail_reg_tmp = ((unsigned'(32'(tail_reg)) + 'h1)) & ((DEPTH - 'h1));
                count=count+1;
                assembly_active_reg_tmp = unsigned'(1'(0));
                assembly_word_reg_tmp = 'h0;
            end
            else begin
                assembly_word_reg_tmp = descriptor_word_in + 'h1;
            end
        end
        count_reg_tmp = count;
        if (reset) begin
            head_reg_tmp = '0;
            tail_reg_tmp = '0;
            count_reg_tmp = '0;
            assembly_reg_tmp = '0;
            assembly_word_reg_tmp = '0;
            assembly_active_reg_tmp = '0;
            enabled_reg_tmp = '0;
            auto_l2_reg_tmp = '0;
            auto_slot_mask_reg_tmp = 'h1FF;
            auto_base_reg_tmp = '0;
            auto_sequence_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
            packet_command_valid_reg_tmp = '0;
            packet_command_handle_reg_tmp = '0;
            packet_command_length_reg_tmp = '0;
            packet_command_system_reg_tmp = '0;
            packet_command_cache_reg_tmp = '0;
            packet_command_network_reg_tmp = '0;
            packet_command_network_port_reg_tmp = '0;
            packet_command_destination_reg_tmp = '0;
            action_destination_reg_tmp = '0;
            write_addr_reg_tmp = '0;
            write_id_reg_tmp = '0;
            write_addr_valid_reg_tmp = '0;
            write_response_valid_reg_tmp = '0;
            read_id_reg_tmp = '0;
            read_addr_reg_tmp = '0;
            read_value_reg_tmp = '0;
            read_lane_reg_tmp = '0;
            read_pending_reg_tmp = '0;
            read_format_pending_reg_tmp = '0;
            read_data_reg_tmp = '0;
            read_valid_reg_tmp = '0;
        end
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin
        head_reg_tmp = head_reg;
        tail_reg_tmp = tail_reg;
        count_reg_tmp = count_reg;
        assembly_reg_tmp = assembly_reg;
        assembly_word_reg_tmp = assembly_word_reg;
        assembly_active_reg_tmp = assembly_active_reg;
        enabled_reg_tmp = enabled_reg;
        auto_l2_reg_tmp = auto_l2_reg;
        auto_slot_mask_reg_tmp = auto_slot_mask_reg;
        auto_base_reg_tmp = auto_base_reg;
        auto_sequence_reg_tmp = auto_sequence_reg;
        protocol_error_reg_tmp = protocol_error_reg;
        packet_command_valid_reg_tmp = packet_command_valid_reg;
        packet_command_handle_reg_tmp = packet_command_handle_reg;
        packet_command_length_reg_tmp = packet_command_length_reg;
        packet_command_system_reg_tmp = packet_command_system_reg;
        packet_command_cache_reg_tmp = packet_command_cache_reg;
        packet_command_network_reg_tmp = packet_command_network_reg;
        packet_command_network_port_reg_tmp = packet_command_network_port_reg;
        packet_command_destination_reg_tmp = packet_command_destination_reg;
        action_destination_reg_tmp = action_destination_reg;
        write_addr_reg_tmp = write_addr_reg;
        write_id_reg_tmp = write_id_reg;
        write_addr_valid_reg_tmp = write_addr_valid_reg;
        write_response_valid_reg_tmp = write_response_valid_reg;
        read_id_reg_tmp = read_id_reg;
        read_addr_reg_tmp = read_addr_reg;
        read_value_reg_tmp = read_value_reg;
        read_lane_reg_tmp = read_lane_reg;
        read_pending_reg_tmp = read_pending_reg;
        read_format_pending_reg_tmp = read_format_pending_reg;
        read_data_reg_tmp = read_data_reg;
        read_valid_reg_tmp = read_valid_reg;

        _work(reset);

        head_reg <= head_reg_tmp;
        tail_reg <= tail_reg_tmp;
        count_reg <= count_reg_tmp;
        assembly_reg <= assembly_reg_tmp;
        assembly_word_reg <= assembly_word_reg_tmp;
        assembly_active_reg <= assembly_active_reg_tmp;
        enabled_reg <= enabled_reg_tmp;
        auto_l2_reg <= auto_l2_reg_tmp;
        auto_slot_mask_reg <= auto_slot_mask_reg_tmp;
        auto_base_reg <= auto_base_reg_tmp;
        auto_sequence_reg <= auto_sequence_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
        packet_command_valid_reg <= packet_command_valid_reg_tmp;
        packet_command_handle_reg <= packet_command_handle_reg_tmp;
        packet_command_length_reg <= packet_command_length_reg_tmp;
        packet_command_system_reg <= packet_command_system_reg_tmp;
        packet_command_cache_reg <= packet_command_cache_reg_tmp;
        packet_command_network_reg <= packet_command_network_reg_tmp;
        packet_command_network_port_reg <= packet_command_network_port_reg_tmp;
        packet_command_destination_reg <= packet_command_destination_reg_tmp;
        action_destination_reg <= action_destination_reg_tmp;
        write_addr_reg <= write_addr_reg_tmp;
        write_id_reg <= write_id_reg_tmp;
        write_addr_valid_reg <= write_addr_valid_reg_tmp;
        write_response_valid_reg <= write_response_valid_reg_tmp;
        read_id_reg <= read_id_reg_tmp;
        read_addr_reg <= read_addr_reg_tmp;
        read_value_reg <= read_value_reg_tmp;
        read_lane_reg <= read_lane_reg_tmp;
        read_pending_reg <= read_pending_reg_tmp;
        read_format_pending_reg <= read_format_pending_reg_tmp;
        read_data_reg <= read_data_reg_tmp;
        read_valid_reg <= read_valid_reg_tmp;
    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
