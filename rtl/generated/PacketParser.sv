`default_nettype none

import Predef_pkg::*;
import PacketParserFields_pkg::*;
import PacketParserWord_pkg::*;
import PacketParserProgress_pkg::*;
import PacketParserPipeWord_pkg::*;
import PacketParserHeaderId_pkg::*;
import PacketParserCall_pkg::*;
import PacketParserFlags_pkg::*;


module PacketParser #(
    parameter LANE_WIDTH = 'h40
,   parameter ENABLE_RAW = 1
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire valid_in
,   input wire[LANE_WIDTH-1:0] data_in
,   input wire[LANE_BYTES-1:0] keep_in
,   input wire[LANE_BYTES-1:0] sop_in
,   input wire[LANE_BYTES-1:0] eop_in
,   input wire raw_in
,   output wire ready_out
,   output wire PacketParserWord data_out
,   output wire[64-1:0] keep_out
,   output wire valid_out
,   output wire last_out
,   output wire raw_out
,   input wire ready_in
,   output wire protocol_error_out
);
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  OUTPUT_WORD_BITS = 64'h200;
    localparam  OUTPUT_BYTES = 64'h40;
    localparam  OUTPUT_FIFO_WORDS = 64'h4;
    localparam  RAW_BYTES = 64'h80;
    localparam  RAW_STORE_WORDS = 64'h2;
    localparam  MARKUP_BITS = LANE_BYTES*'h8;
    localparam  PIPE_STAGES = 64'h6;


    // regs and combs
    reg[8-1:0] state_reg;
    reg[8-1:0] pos_reg;
    reg[8-1:0] word_cntr_reg;
    reg ethernet_done_reg;
    reg error_reg;
    reg limit_reg;
    reg done_reg;
    PacketParserProgress ethernet_progress_reg;
    PacketParserProgress vlan_progress_reg[4];
    reg[3-1:0] vlan_stage_index_reg[4];
    PacketParserProgress mpls_progress_reg[4];
    reg[3-1:0] mpls_stage_index_reg[4];
    PacketParserProgress ipv4_progress_reg;
    PacketParserProgress ipv6_progress_reg;
    PacketParserProgress ipv6_ext_progress_reg[4];
    reg[3-1:0] ipv6_ext_stage_index_reg[4];
    reg[48-1:0] destination_mac_reg;
    reg[48-1:0] source_mac_reg;
    reg[16-1:0] ethernet_type_reg;
    reg[16-1:0] vlan_next_proto_reg[4];
    reg[3-1:0] vlan_count_reg;
    reg[16-1:0] vlan_tci_reg[2];
    reg[32-1:0] mpls_entry_reg[4];
    reg mpls_entry_done_reg[4];
    reg[3-1:0] mpls_count_reg;
    reg[32-1:0] mpls_output_reg[2];
    reg[128-1:0] source_ip_reg;
    reg[128-1:0] destination_ip_reg;
    reg[8-1:0] protocol_reg;
    reg[8-1:0] ip_version_reg;
    reg[8-1:0] ip_header_bytes_reg;
    reg[8-1:0] transport_pos_reg;
    reg[16-1:0] ipv4_fragment_reg;
    reg initial_fragment_reg;
    reg[128-1:0] ipv6_source_ip_reg;
    reg[128-1:0] ipv6_destination_ip_reg;
    reg[8-1:0] ipv6_base_next_proto_reg;
    reg ipv6_seen_reg;
    reg[8-1:0] ipv6_next_proto_reg[4];
    reg[8-1:0] ipv6_ext_size_reg[4];
    reg ipv6_ext_seen_reg[4];
    reg[16-1:0] ipv6_fragment_reg[4];
    reg noninitial_fragment_reg[4];
    reg[16-1:0] source_port_reg;
    reg[16-1:0] destination_port_reg;
    reg[8-1:0] tcp_header_bytes_reg;
    reg[64-1:0] align_data_reg;
    reg[4-1:0] align_count_reg;
    reg[512-1:0] raw_data_low_reg;
    reg[512-1:0] raw_data_high_reg;
    reg[8-1:0] raw_count_reg;
    reg[5-1:0] raw_word_count_reg;
    reg in_frame_reg;
    reg frame_raw_reg;
    reg pending_valid_reg;
    reg pending_rollover_reg;
    reg[64-1:0] pending_data_reg;
    reg[4-1:0] pending_bytes_reg;
    reg[8-1:0] pending_word_cntr_reg;
    reg pending_sop_reg;
    reg pending_eop_reg;
    reg[8-1:0] align_word_cntr_reg;
    reg align_sop_pending_reg;
    PacketParserPipeWord pipe_reg[6];
    reg pipe_valid_reg[6];
    reg[512-1:0] raw_store_low_reg[2];
    reg[512-1:0] raw_store_high_reg[2];
    reg[8-1:0] raw_store_count_bytes_reg[2];
    reg raw_store_head_reg;
    reg raw_store_tail_reg;
    reg[2-1:0] raw_store_count_reg;
    reg[512-1:0] fifo_data_reg[4];
    reg[64-1:0] fifo_keep_reg[4];
    reg fifo_last_reg[4];
    reg fifo_raw_reg[4];
    reg[2-1:0] fifo_head_reg;
    reg[2-1:0] fifo_tail_reg;
    reg[3-1:0] fifo_count_reg;
    reg[3-1:0] output_reserved_reg;
    reg protocol_error_reg;
    PacketParserWord output_data_comb;
    logic[64-1:0] output_keep_comb;
    logic output_valid_comb;
    logic output_last_comb;
    logic output_raw_comb;
    logic input_ready_comb;

    // members

    // tmp variables
    logic[8-1:0] state_reg_tmp;
    logic[8-1:0] pos_reg_tmp;
    logic[8-1:0] word_cntr_reg_tmp;
    logic ethernet_done_reg_tmp;
    logic error_reg_tmp;
    logic limit_reg_tmp;
    logic done_reg_tmp;
    PacketParserProgress ethernet_progress_reg_tmp;
    PacketParserProgress vlan_progress_reg_tmp[4];
    logic[3-1:0] vlan_stage_index_reg_tmp[4];
    PacketParserProgress mpls_progress_reg_tmp[4];
    logic[3-1:0] mpls_stage_index_reg_tmp[4];
    PacketParserProgress ipv4_progress_reg_tmp;
    PacketParserProgress ipv6_progress_reg_tmp;
    PacketParserProgress ipv6_ext_progress_reg_tmp[4];
    logic[3-1:0] ipv6_ext_stage_index_reg_tmp[4];
    logic[48-1:0] destination_mac_reg_tmp;
    logic[48-1:0] source_mac_reg_tmp;
    logic[16-1:0] ethernet_type_reg_tmp;
    logic[16-1:0] vlan_next_proto_reg_tmp[4];
    logic[3-1:0] vlan_count_reg_tmp;
    logic[16-1:0] vlan_tci_reg_tmp[2];
    logic[32-1:0] mpls_entry_reg_tmp[4];
    logic mpls_entry_done_reg_tmp[4];
    logic[3-1:0] mpls_count_reg_tmp;
    logic[32-1:0] mpls_output_reg_tmp[2];
    logic[128-1:0] source_ip_reg_tmp;
    logic[128-1:0] destination_ip_reg_tmp;
    logic[8-1:0] protocol_reg_tmp;
    logic[8-1:0] ip_version_reg_tmp;
    logic[8-1:0] ip_header_bytes_reg_tmp;
    logic[8-1:0] transport_pos_reg_tmp;
    logic[16-1:0] ipv4_fragment_reg_tmp;
    logic initial_fragment_reg_tmp;
    logic[128-1:0] ipv6_source_ip_reg_tmp;
    logic[128-1:0] ipv6_destination_ip_reg_tmp;
    logic[8-1:0] ipv6_base_next_proto_reg_tmp;
    logic ipv6_seen_reg_tmp;
    logic[8-1:0] ipv6_next_proto_reg_tmp[4];
    logic[8-1:0] ipv6_ext_size_reg_tmp[4];
    logic ipv6_ext_seen_reg_tmp[4];
    logic[16-1:0] ipv6_fragment_reg_tmp[4];
    logic noninitial_fragment_reg_tmp[4];
    logic[16-1:0] source_port_reg_tmp;
    logic[16-1:0] destination_port_reg_tmp;
    logic[8-1:0] tcp_header_bytes_reg_tmp;
    logic[64-1:0] align_data_reg_tmp;
    logic[4-1:0] align_count_reg_tmp;
    logic[512-1:0] raw_data_low_reg_tmp;
    logic[512-1:0] raw_data_high_reg_tmp;
    logic[8-1:0] raw_count_reg_tmp;
    logic[5-1:0] raw_word_count_reg_tmp;
    logic in_frame_reg_tmp;
    logic frame_raw_reg_tmp;
    logic pending_valid_reg_tmp;
    logic pending_rollover_reg_tmp;
    logic[64-1:0] pending_data_reg_tmp;
    logic[4-1:0] pending_bytes_reg_tmp;
    logic[8-1:0] pending_word_cntr_reg_tmp;
    logic pending_sop_reg_tmp;
    logic pending_eop_reg_tmp;
    logic[8-1:0] align_word_cntr_reg_tmp;
    logic align_sop_pending_reg_tmp;
    PacketParserPipeWord pipe_reg_tmp[6];
    logic pipe_valid_reg_tmp[6];
    logic[512-1:0] raw_store_low_reg_tmp[2];
    logic[512-1:0] raw_store_high_reg_tmp[2];
    logic[8-1:0] raw_store_count_bytes_reg_tmp[2];
    logic raw_store_head_reg_tmp;
    logic raw_store_tail_reg_tmp;
    logic[2-1:0] raw_store_count_reg_tmp;
    logic[512-1:0] fifo_data_reg_tmp[4];
    logic[64-1:0] fifo_keep_reg_tmp[4];
    logic fifo_last_reg_tmp[4];
    logic fifo_raw_reg_tmp[4];
    logic[2-1:0] fifo_head_reg_tmp;
    logic[2-1:0] fifo_tail_reg_tmp;
    logic[3-1:0] fifo_count_reg_tmp;
    logic[3-1:0] output_reserved_reg_tmp;
    logic protocol_error_reg_tmp;


    function logic is_vlan (input logic[15:0] selector);
        return ((selector == 'h8100) || (selector == 'h88A8)) || (selector == 'h9100);
    endfunction

    function logic is_mpls (input logic[15:0] selector);
        return (selector == 'h8847) || (selector == 'h8848);
    endfunction

    function logic is_ipv6_extension (input logic[7:0] selector);
        return (((((selector == 'h0) || (selector == 'h2B)) || (selector == 'h2C)) || (selector == 'h33)) || (selector == 'h3C)) || (selector == 'h87);
    endfunction

    function logic[64-1:0] mark_header (
        input logic[64-1:0] previous
,       input logic[7:0] markup_pos
,       input logic[7:0] header_id
    );
        logic[64-1:0] result;
        logic[7:0] lane;
        result = previous;
        lane=markup_pos & ((LANE_BYTES - 'h1));
        if (lane == 'h0) begin
            result['h0 +:8] = unsigned'(8'(unsigned'(8'(header_id))));
        end
        if (lane == 'h1) begin
            result['h8 +:8] = unsigned'(8'(unsigned'(8'(header_id))));
        end
        if (lane == 'h2) begin
            result['h10 +:8] = unsigned'(8'(unsigned'(8'(header_id))));
        end
        if (lane == 'h3) begin
            result['h18 +:8] = unsigned'(8'(unsigned'(8'(header_id))));
        end
        if (lane == 'h4) begin
            result['h20 +:8] = unsigned'(8'(unsigned'(8'(header_id))));
        end
        if (lane == 'h5) begin
            result['h28 +:8] = unsigned'(8'(unsigned'(8'(header_id))));
        end
        if (lane == 'h6) begin
            result['h30 +:8] = unsigned'(8'(unsigned'(8'(header_id))));
        end
        if (lane == 'h7) begin
            result['h38 +:8] = unsigned'(8'(unsigned'(8'(header_id))));
        end
        return result;
    endfunction

    function logic[7:0] marked_header (
        input logic[64-1:0] markup_state
,       input logic[7:0] markup_pos
    );
        logic[7:0] lane;
        logic[7:0] result;
        lane=markup_pos & ((LANE_BYTES - 'h1));
        result='h0;
        if (lane == 'h0) begin
            result=unsigned'(8'(markup_state['h0 +:8]));
        end
        if (lane == 'h1) begin
            result=unsigned'(8'(markup_state['h8 +:8]));
        end
        if (lane == 'h2) begin
            result=unsigned'(8'(markup_state['h10 +:8]));
        end
        if (lane == 'h3) begin
            result=unsigned'(8'(markup_state['h18 +:8]));
        end
        if (lane == 'h4) begin
            result=unsigned'(8'(markup_state['h20 +:8]));
        end
        if (lane == 'h5) begin
            result=unsigned'(8'(markup_state['h28 +:8]));
        end
        if (lane == 'h6) begin
            result=unsigned'(8'(markup_state['h30 +:8]));
        end
        if (lane == 'h7) begin
            result=unsigned'(8'(markup_state['h38 +:8]));
        end
        return result;
    endfunction

    function logic byte_present (
        input logic[7:0] absolute
,       input logic[7:0] word_cntr
,       input logic[7:0] word_bytes
    );
        logic[7:0] lane;
        lane=absolute & ((LANE_BYTES - 'h1));
        return (((absolute >>> 'h3)) == word_cntr) && (lane < word_bytes);
    endfunction

    function logic field_complete (
        input logic[7:0] absolute
,       input logic[7:0] bytes
,       input logic[7:0] word_cntr
,       input logic[7:0] word_bytes
    );
        return byte_present(unsigned'(8'(((absolute + bytes) - 'h1))), word_cntr, word_bytes);
    endfunction

    function logic[7:0] word_byte (
        input logic[64-1:0] word
,       input logic[7:0] absolute
    );
        logic[7:0] lane;
        lane=absolute & ((LANE_BYTES - 'h1));
        return unsigned'(8'(word[lane*'h8 +:8]));
    endfunction

    function logic[8-1:0] capture_u8 (
        input logic[64-1:0] word
,       input logic[8-1:0] previous
,       input logic[7:0] absolute
,       input logic[7:0] word_cntr
,       input logic[7:0] word_bytes
    );
        logic[8-1:0] result;
        result = previous;
        if (byte_present(absolute, word_cntr, word_bytes)) begin
            result = unsigned'(8'(unsigned'(8'(word_byte(word, absolute)))));
        end
        return unsigned'(8'(result));
    endfunction

    function logic[16-1:0] capture_be16 (
        input logic[64-1:0] word
,       input logic[16-1:0] previous
,       input logic[7:0] absolute
,       input logic[7:0] word_cntr
,       input logic[7:0] word_bytes
    );
        logic[15:0] result;
        logic[7:0] _byte;
        result=unsigned'(16'(previous));
        _byte=unsigned'(8'(capture_u8(word, unsigned'(8'(unsigned'(8'(result >>> 'h8)))), absolute, word_cntr, word_bytes)));
        result=((result & 'hFF)) | ((unsigned'(16'(_byte)) <<< 'h8));
        _byte=unsigned'(8'(capture_u8(word, unsigned'(8'(unsigned'(8'(result)))), unsigned'(8'((absolute + 'h1))), word_cntr, word_bytes)));
        result=((result & 'hFF00)) | _byte;
        return unsigned'(16'(unsigned'(16'(result))));
    endfunction

    function logic[32-1:0] capture_be32 (
        input logic[64-1:0] word
,       input logic[32-1:0] previous
,       input logic[7:0] absolute
,       input logic[7:0] word_cntr
,       input logic[7:0] word_bytes
    );
        logic[31:0] result;
        logic[7:0] _byte;
        result=unsigned'(32'(previous));
        _byte=unsigned'(8'(capture_u8(word, unsigned'(8'(unsigned'(8'(result >>> 'h18)))), absolute, word_cntr, word_bytes)));
        result=((result & 'hFFFFFF)) | ((unsigned'(32'(_byte)) <<< 'h18));
        _byte=unsigned'(8'(capture_u8(word, unsigned'(8'(unsigned'(8'(result >>> 'h10)))), unsigned'(8'((absolute + 'h1))), word_cntr, word_bytes)));
        result=((result & 'hFF00FFFF)) | ((unsigned'(32'(_byte)) <<< 'h10));
        _byte=unsigned'(8'(capture_u8(word, unsigned'(8'(unsigned'(8'(result >>> 'h8)))), unsigned'(8'((absolute + 'h2))), word_cntr, word_bytes)));
        result=((result & 'hFFFF00FF)) | ((unsigned'(32'(_byte)) <<< 'h8));
        _byte=unsigned'(8'(capture_u8(word, unsigned'(8'(unsigned'(8'(result)))), unsigned'(8'((absolute + 'h3))), word_cntr, word_bytes)));
        result=((result & 'hFFFFFF00)) | _byte;
        return unsigned'(32'(unsigned'(32'(result))));
    endfunction

    function logic[48-1:0] capture_be48 (
        input logic[64-1:0] word
,       input logic[48-1:0] previous
,       input logic[7:0] absolute
,       input logic[7:0] word_cntr
,       input logic[7:0] word_bytes
    );
        logic[48-1:0] result;
        logic[7:0] _byte;
        result = previous;
        for (_byte='h0;_byte < 'h6;_byte=_byte+1) begin
            result['h28 - (_byte*'h8) +:8] = capture_u8(word, unsigned'(8'(unsigned'(8'(result['h28 - (_byte*'h8) +:8])))), unsigned'(8'((absolute + _byte))), word_cntr, word_bytes);
        end
        return result;
    endfunction

    function logic[128-1:0] capture_be128 (
        input logic[64-1:0] word
,       input logic[128-1:0] previous
,       input logic[7:0] absolute
,       input logic[7:0] word_cntr
,       input logic[7:0] word_bytes
    );
        logic[128-1:0] result;
        logic[7:0] _byte;
        result = previous;
        for (_byte='h0;_byte < 'h10;_byte=_byte+1) begin
            result['h78 - (_byte*'h8) +:8] = capture_u8(word, unsigned'(8'(unsigned'(8'(result['h78 - (_byte*'h8) +:8])))), unsigned'(8'((absolute + _byte))), word_cntr, word_bytes);
        end
        return result;
    endfunction

    function logic header_active (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input logic[7:0] header_id
,       input PacketParserProgress progress
    );
        return ((((!progress.error && !progress.limit) && !progress.done) && (unsigned'(8'(progress.state)) == header_id)) && (unsigned'(8'(progress.pos)) == markup_pos)) && (marked_header(markup_state, markup_pos) == header_id);
    endfunction

    function logic[8-1:0] select_l3 (input logic[15:0] selector);
        if (is_vlan(selector)) begin
            return unsigned'(8'(unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_VLAN))));
        end
        if (is_mpls(selector)) begin
            return unsigned'(8'(unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_MPLS))));
        end
        if (selector == 'h800) begin
            return unsigned'(8'(unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_IPV4))));
        end
        if (selector == 'h86DD) begin
            return unsigned'(8'(unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_IPV6))));
        end
        return unsigned'(8'(unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE))));
    endfunction

    function logic[8-1:0] select_transport (input logic[7:0] protocol);
        if (protocol == 'h6) begin
            return unsigned'(8'(unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_TCP))));
        end
        if (protocol == 'h11) begin
            return unsigned'(8'(unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_UDP))));
        end
        return unsigned'(8'(unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE))));
    endfunction

    task reset_parser ();
    begin: reset_parser
        logic[31:0] index;
        PacketParserProgress progress;
        progress = 0;
        state_reg_tmp = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
        pos_reg_tmp = unsigned'(8'h0);
        word_cntr_reg_tmp = unsigned'(8'h0);
        ethernet_done_reg_tmp = unsigned'(1'h0);
        error_reg_tmp = unsigned'(1'h0);
        limit_reg_tmp = unsigned'(1'h0);
        done_reg_tmp = unsigned'(1'h0);
        ethernet_progress_reg_tmp = progress;
        for (index='h0;index < 'h4;index=index+1) begin
            vlan_progress_reg_tmp[index] = progress;
            vlan_stage_index_reg_tmp[index] = 'h0;
        end
        for (index='h0;index < 'h4;index=index+1) begin
            mpls_progress_reg_tmp[index] = progress;
            mpls_stage_index_reg_tmp[index] = 'h0;
        end
        ipv4_progress_reg_tmp = progress;
        ipv6_progress_reg_tmp = progress;
        for (index='h0;index < 'h4;index=index+1) begin
            ipv6_ext_progress_reg_tmp[index] = progress;
            ipv6_ext_stage_index_reg_tmp[index] = 'h0;
        end
        destination_mac_reg_tmp = 'h0;
        source_mac_reg_tmp = 'h0;
        ethernet_type_reg_tmp = unsigned'(16'h0);
        for (index='h0;index < 'h4;index=index+1) begin
            vlan_next_proto_reg_tmp[index] = unsigned'(16'h0);
        end
        vlan_count_reg_tmp = 'h0;
        for (index='h0;index < 'h2;index=index+1) begin
            vlan_tci_reg_tmp[index] = unsigned'(16'h0);
        end
        for (index='h0;index < 'h4;index=index+1) begin
            mpls_entry_reg_tmp[index] = unsigned'(32'h0);
            mpls_entry_done_reg_tmp[index] = unsigned'(1'h0);
        end
        mpls_count_reg_tmp = 'h0;
        for (index='h0;index < 'h2;index=index+1) begin
            mpls_output_reg_tmp[index] = unsigned'(32'h0);
        end
        source_ip_reg_tmp = 'h0;
        destination_ip_reg_tmp = 'h0;
        protocol_reg_tmp = unsigned'(8'h0);
        ip_version_reg_tmp = unsigned'(8'h0);
        ip_header_bytes_reg_tmp = unsigned'(8'h0);
        transport_pos_reg_tmp = unsigned'(8'h0);
        ipv4_fragment_reg_tmp = unsigned'(16'h0);
        initial_fragment_reg_tmp = unsigned'(1'h1);
        ipv6_source_ip_reg_tmp = 'h0;
        ipv6_destination_ip_reg_tmp = 'h0;
        ipv6_base_next_proto_reg_tmp = unsigned'(8'h0);
        ipv6_seen_reg_tmp = unsigned'(1'h0);
        for (index='h0;index < 'h4;index=index+1) begin
            ipv6_next_proto_reg_tmp[index] = unsigned'(8'h0);
            ipv6_ext_size_reg_tmp[index] = unsigned'(8'h0);
            ipv6_ext_seen_reg_tmp[index] = unsigned'(1'h0);
            ipv6_fragment_reg_tmp[index] = unsigned'(16'h0);
            noninitial_fragment_reg_tmp[index] = unsigned'(1'h0);
        end
        source_port_reg_tmp = unsigned'(16'h0);
        destination_port_reg_tmp = unsigned'(16'h0);
        tcp_header_bytes_reg_tmp = unsigned'(8'h0);
    end
    endtask

    function logic progress_inactive (input PacketParserProgress progress);
        return (((unsigned'(8'(progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_NONE) && !progress.error) && !progress.limit) && !progress.done;
    endfunction

    function PacketParserProgress accept_upstream (
        input PacketParserProgress current
,       input PacketParserProgress upstream
    );
        PacketParserProgress result;
        result = current;
        if (progress_inactive(current)) begin
            result = upstream;
        end
        else begin
            if (upstream.error) begin
                result.error = unsigned'(1'h1);
            end
            if (upstream.limit) begin
                result.limit = unsigned'(1'h1);
            end
            if (upstream.done) begin
                result.done = unsigned'(1'h1);
            end
        end
        return result;
    endfunction

    function PacketParserProgress accept_vlan_upstream (
        input PacketParserProgress current
,       input PacketParserProgress upstream
    );
        logic[7:0] state;
        state=unsigned'(8'(current.state));
        if ((((((((((!current.error && !current.limit) && !current.done) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_VLAN)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_MPLS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV4)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV4_OPTIONS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_TCP)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_UDP)) begin
            return upstream;
        end
        return accept_upstream(current, upstream);
    endfunction

    function PacketParserProgress accept_mpls_upstream (
        input PacketParserProgress current
,       input PacketParserProgress upstream
    );
        logic[7:0] state;
        state=unsigned'(8'(current.state));
        if (((((((((!current.error && !current.limit) && !current.done) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_MPLS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV4)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV4_OPTIONS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_TCP)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_UDP)) begin
            return upstream;
        end
        return accept_upstream(current, upstream);
    endfunction

    function PacketParserProgress accept_ipv4_upstream (
        input PacketParserProgress current
,       input PacketParserProgress upstream
    );
        logic[7:0] state;
        state=unsigned'(8'(current.state));
        if ((((((!current.error && !current.limit) && !current.done) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV4)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV4_OPTIONS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_TCP)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_UDP)) begin
            return upstream;
        end
        return accept_upstream(current, upstream);
    endfunction

    function PacketParserProgress accept_ipv6_upstream (
        input PacketParserProgress current
,       input PacketParserProgress upstream
    );
        logic[7:0] state;
        state=unsigned'(8'(current.state));
        if ((((((!current.error && !current.limit) && !current.done) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_TCP)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_UDP)) begin
            return upstream;
        end
        return accept_upstream(current, upstream);
    endfunction

    function PacketParserProgress accept_ipv6_ext_upstream (
        input PacketParserProgress current
,       input PacketParserProgress upstream
    );
        logic[7:0] state;
        state=unsigned'(8'(current.state));
        if (((((!current.error && !current.limit) && !current.done) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_TCP)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_UDP)) begin
            return upstream;
        end
        return accept_upstream(current, upstream);
    endfunction

    function PacketParserProgress accept_transport_upstream (
        input PacketParserProgress current
,       input PacketParserProgress upstream
    );
        logic[7:0] state;
        state=unsigned'(8'(current.state));
        if ((((!current.error && !current.limit) && !current.done) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_TCP)) && (state != PacketParserHeaderId_pkg::PACKET_HEADER_UDP)) begin
            return upstream;
        end
        return accept_upstream(current, upstream);
    endfunction

    function PacketParserCall vlan_work (
        input logic[7:0] occurrence
,       input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[15:0] selector;
        PacketParserCall call;
        call.markup_state = 'h0;
        call.progress = progress;
        if (!header_active(markup_pos, markup_state, PacketParserHeaderId_pkg::PACKET_HEADER_VLAN, progress)) begin
            return call;
        end
        if (occurrence < 'h2) begin
            vlan_tci_reg_tmp[occurrence] = capture_be16(word, unsigned'(16'(vlan_tci_reg_tmp[occurrence])), markup_pos, word_cntr, word_bytes);
        end
        vlan_next_proto_reg_tmp[occurrence] = capture_be16(word, unsigned'(16'(vlan_next_proto_reg_tmp[occurrence])), unsigned'(8'((markup_pos + 'h2))), word_cntr, word_bytes);
        if (field_complete(unsigned'(8'((markup_pos + 'h2))), 'h2, word_cntr, word_bytes)) begin
            selector=unsigned'(16'(vlan_next_proto_reg_tmp[occurrence]));
            if (((occurrence + 'h1) == 'h4) && is_vlan(selector)) begin
                call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
                call.progress.limit = unsigned'(1'h1);
                call.progress.done = unsigned'(1'h1);
            end
            else begin
                call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + 'h4))));
                call.progress.state = select_l3(selector);
                if (unsigned'(8'(call.progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_NONE) begin
                    call.progress.error = unsigned'(1'h1);
                end
            end
        end
        return call;
    endfunction

    function PacketParserCall mpls_work (
        input logic[7:0] occurrence
,       input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[31:0] entry;
        logic[7:0] version;
        PacketParserCall call;
        call.markup_state = 'h0;
        call.progress = progress;
        if (!header_active(markup_pos, markup_state, PacketParserHeaderId_pkg::PACKET_HEADER_MPLS, progress)) begin
            return call;
        end
        if (!mpls_entry_done_reg_tmp[occurrence]) begin
            mpls_entry_reg_tmp[occurrence] = capture_be32(word, unsigned'(32'(mpls_entry_reg_tmp[occurrence])), markup_pos, word_cntr, word_bytes);
            if (field_complete(markup_pos, 'h4, word_cntr, word_bytes)) begin
                mpls_entry_done_reg_tmp[occurrence] = unsigned'(1'h1);
            end
        end
        if (!mpls_entry_done_reg_tmp[occurrence]) begin
            return call;
        end
        entry=unsigned'(32'(mpls_entry_reg_tmp[occurrence]));
        if (occurrence < 'h2) begin
            mpls_output_reg_tmp[occurrence] = unsigned'(32'(unsigned'(32'(entry))));
        end
        if (((entry & 'h100)) == 'h0) begin
            if ((occurrence + 'h1) == 'h4) begin
                call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
                call.progress.limit = unsigned'(1'h1);
                call.progress.done = unsigned'(1'h1);
            end
            else begin
                call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_MPLS));
                call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + 'h4))));
            end
        end
        else begin
            if (byte_present(unsigned'(8'((markup_pos + 'h4))), word_cntr, word_bytes)) begin
                version=word_byte(word, unsigned'(8'(((markup_pos + 'h4))))) >>> 'h4;
                call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + 'h4))));
                if (version == 'h4) begin
                    call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_IPV4));
                end
                else begin
                    if (version == 'h6) begin
                        call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_IPV6));
                    end
                    else begin
                        call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
                        call.progress.error = unsigned'(1'h1);
                    end
                end
            end
        end
        return call;
    endfunction

    function PacketParserCall parse_tcp (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[7:0] header_bytes;
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_TCP);
        call.markup_state = 'h0;
        call.progress = progress;
        if (!header_active(markup_pos, marked_state, PacketParserHeaderId_pkg::PACKET_HEADER_TCP, progress)) begin
            return call;
        end
        source_port_reg_tmp = capture_be16(word, unsigned'(16'(source_port_reg_tmp)), markup_pos, word_cntr, word_bytes);
        destination_port_reg_tmp = capture_be16(word, unsigned'(16'(destination_port_reg_tmp)), unsigned'(8'((markup_pos + 'h2))), word_cntr, word_bytes);
        if (byte_present(unsigned'(8'((markup_pos + 'hC))), word_cntr, word_bytes)) begin
            header_bytes=((word_byte(word, unsigned'(8'(((markup_pos + 'hC))))) >>> 'h4))*'h4;
            tcp_header_bytes_reg_tmp = unsigned'(8'(unsigned'(8'(header_bytes))));
            if ((header_bytes < 'h14) || ((header_bytes - 'h14) > 'h28)) begin
                call.progress.error = unsigned'(1'h1);
            end
        end
        header_bytes=unsigned'(8'(tcp_header_bytes_reg_tmp));
        if ((header_bytes != 'h0) && field_complete(markup_pos, header_bytes, word_cntr, word_bytes)) begin
            call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
            call.progress.done = unsigned'(1'h1);
        end
        return call;
    endfunction

    function PacketParserCall parse_udp (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_UDP);
        call.markup_state = 'h0;
        call.progress = progress;
        if (!header_active(markup_pos, marked_state, PacketParserHeaderId_pkg::PACKET_HEADER_UDP, progress)) begin
            return call;
        end
        source_port_reg_tmp = capture_be16(word, unsigned'(16'(source_port_reg_tmp)), markup_pos, word_cntr, word_bytes);
        destination_port_reg_tmp = capture_be16(word, unsigned'(16'(destination_port_reg_tmp)), unsigned'(8'((markup_pos + 'h2))), word_cntr, word_bytes);
        if (field_complete(markup_pos, 'h8, word_cntr, word_bytes)) begin
            call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
            call.progress.done = unsigned'(1'h1);
        end
        return call;
    endfunction

    function PacketParserCall parse_ipv4_options (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[7:0] transport_pos;
        logic[7:0] option_bytes;
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_IPV4_OPTIONS);
        transport_pos=unsigned'(8'(transport_pos_reg_tmp));
        option_bytes=transport_pos - markup_pos;
        call.markup_state = 'h0;
        call.progress = progress;
        if ((header_active(markup_pos, marked_state, PacketParserHeaderId_pkg::PACKET_HEADER_IPV4_OPTIONS, progress) && (option_bytes != 'h0)) && field_complete(markup_pos, option_bytes, word_cntr, word_bytes)) begin
            call.progress.pos = unsigned'(8'(unsigned'(8'(transport_pos))));
            call.progress.state = select_transport(unsigned'(8'(protocol_reg_tmp)));
            if (unsigned'(8'(call.progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_NONE) begin
                call.progress.done = unsigned'(1'h1);
            end
        end
        return call;
    endfunction

    function PacketParserCall parse_ipv4 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[7:0] first;
        logic[7:0] header_bytes;
        logic[15:0] fragment;
        logic[32-1:0] address;
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_IPV4);
        call.markup_state = 'h0;
        call.progress = progress;
        if (header_active(markup_pos, marked_state, PacketParserHeaderId_pkg::PACKET_HEADER_IPV4, progress)) begin
            if (byte_present(markup_pos, word_cntr, word_bytes)) begin
                first=word_byte(word, markup_pos);
                header_bytes=((first & 'hF))*'h4;
                ip_version_reg_tmp = unsigned'(8'h4);
                ip_header_bytes_reg_tmp = unsigned'(8'(unsigned'(8'(header_bytes))));
                transport_pos_reg_tmp = unsigned'(8'(unsigned'(8'(markup_pos + header_bytes))));
                if ((((first >>> 'h4)) != 'h4) || (header_bytes < 'h14)) begin
                    call.progress.error = unsigned'(1'h1);
                end
                else begin
                    if ((header_bytes - 'h14) > 'h28) begin
                        call.progress.limit = unsigned'(1'h1);
                    end
                end
            end
            ipv4_fragment_reg_tmp = capture_be16(word, unsigned'(16'(ipv4_fragment_reg_tmp)), unsigned'(8'((markup_pos + 'h6))), word_cntr, word_bytes);
            if (field_complete(unsigned'(8'((markup_pos + 'h6))), 'h2, word_cntr, word_bytes)) begin
                fragment=unsigned'(16'(ipv4_fragment_reg_tmp));
                initial_fragment_reg_tmp = unsigned'(1'(((fragment & 'h1FFF)) == 'h0));
            end
            protocol_reg_tmp = capture_u8(word, unsigned'(8'(protocol_reg_tmp)), unsigned'(8'((markup_pos + 'h9))), word_cntr, word_bytes);
            address = unsigned'(32'(unsigned'(32'(unsigned'(32'(source_ip_reg_tmp))))));
            source_ip_reg_tmp['h0 +:32] = capture_be32(word, unsigned'(32'(address)), unsigned'(8'((markup_pos + 'hC))), word_cntr, word_bytes);
            address = unsigned'(32'(unsigned'(32'(unsigned'(32'(destination_ip_reg_tmp))))));
            destination_ip_reg_tmp['h0 +:32] = capture_be32(word, unsigned'(32'(address)), unsigned'(8'((markup_pos + 'h10))), word_cntr, word_bytes);
            header_bytes=unsigned'(8'(ip_header_bytes_reg_tmp));
            if (header_bytes>='h14 && field_complete(markup_pos, 'h14, word_cntr, word_bytes)) begin
                if (!initial_fragment_reg_tmp) begin
                    call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
                    call.progress.done = unsigned'(1'h1);
                end
                else begin
                    if (header_bytes == 'h14) begin
                        call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + 'h14))));
                        call.progress.state = select_transport(unsigned'(8'(protocol_reg_tmp)));
                        if (unsigned'(8'(call.progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_NONE) begin
                            call.progress.done = unsigned'(1'h1);
                        end
                    end
                    else begin
                        call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_IPV4_OPTIONS));
                        call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + 'h14))));
                    end
                end
            end
        end
        return call;
    endfunction

    function PacketParserCall ipv6_options_work (
        input logic[7:0] occurrence
,       input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[7:0] selector;
        logic[7:0] size;
        logic[15:0] fragment;
        PacketParserCall call;
        call.markup_state = 'h0;
        call.progress = progress;
        if (!header_active(markup_pos, markup_state, PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS, progress)) begin
            return call;
        end
        selector=unsigned'(8'(ipv6_next_proto_reg_tmp[occurrence]));
        if (byte_present(markup_pos, word_cntr, word_bytes)) begin
            ipv6_next_proto_reg_tmp[occurrence] = unsigned'(8'(unsigned'(8'(word_byte(word, markup_pos)))));
        end
        if (byte_present(unsigned'(8'((markup_pos + 'h1))), word_cntr, word_bytes)) begin
            if (selector == 'h2C) begin
                size='h8;
            end
            else begin
                if (selector == 'h33) begin
                    size=((word_byte(word, unsigned'(8'(((markup_pos + 'h1))))) + 'h2))*'h4;
                end
                else begin
                    size=((word_byte(word, unsigned'(8'(((markup_pos + 'h1))))) + 'h1))*'h8;
                end
            end
            ipv6_ext_size_reg_tmp[occurrence] = unsigned'(8'(unsigned'(8'(size))));
            if (unsigned'(16'(((markup_pos + size)))) > 'hC0) begin
                call.progress.limit = unsigned'(1'h1);
            end
        end
        if (selector == 'h2C) begin
            ipv6_fragment_reg_tmp[occurrence] = capture_be16(word, unsigned'(16'(ipv6_fragment_reg_tmp[occurrence])), unsigned'(8'((markup_pos + 'h2))), word_cntr, word_bytes);
            if (field_complete(unsigned'(8'((markup_pos + 'h2))), 'h2, word_cntr, word_bytes)) begin
                fragment=unsigned'(16'(ipv6_fragment_reg_tmp[occurrence]));
                if (((fragment & 'hFFF8)) != 'h0) begin
                    noninitial_fragment_reg_tmp[occurrence] = unsigned'(1'h1);
                end
            end
        end
        size=unsigned'(8'(ipv6_ext_size_reg_tmp[occurrence]));
        if ((size != 'h0) && field_complete(markup_pos, size, word_cntr, word_bytes)) begin
            selector=unsigned'(8'(ipv6_next_proto_reg_tmp[occurrence]));
            if (noninitial_fragment_reg_tmp[occurrence]) begin
                call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
                call.progress.done = unsigned'(1'h1);
            end
            else begin
                if (is_ipv6_extension(selector)) begin
                    if ((occurrence + 'h1) == 'h4) begin
                        call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_NONE));
                        call.progress.limit = unsigned'(1'h1);
                        call.progress.done = unsigned'(1'h1);
                    end
                    else begin
                        call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS));
                        call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + size))));
                    end
                end
                else begin
                    call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + size))));
                    call.progress.state = select_transport(selector);
                    if (unsigned'(8'(call.progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_NONE) begin
                        call.progress.done = unsigned'(1'h1);
                    end
                end
            end
        end
        return call;
    endfunction

    function PacketParserCall parse_ipv6_options4 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work('h3, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_ipv6_options3 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work('h2, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_ipv6_options2 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work('h1, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_ipv6_options1 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS);
        call = ipv6_options_work('h0, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_ipv6 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[7:0] first;
        logic[7:0] selector;
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_IPV6);
        call.markup_state = 'h0;
        call.progress = progress;
        if (header_active(markup_pos, marked_state, PacketParserHeaderId_pkg::PACKET_HEADER_IPV6, progress)) begin
            if (byte_present(markup_pos, word_cntr, word_bytes)) begin
                first=word_byte(word, markup_pos);
                ipv6_seen_reg_tmp = unsigned'(1'h1);
                if (((first >>> 'h4)) != 'h6) begin
                    call.progress.error = unsigned'(1'h1);
                end
            end
            ipv6_base_next_proto_reg_tmp = capture_u8(word, unsigned'(8'(ipv6_base_next_proto_reg_tmp)), unsigned'(8'((markup_pos + 'h6))), word_cntr, word_bytes);
            ipv6_source_ip_reg_tmp = capture_be128(word, ipv6_source_ip_reg_tmp, unsigned'(8'((markup_pos + 'h8))), word_cntr, word_bytes);
            ipv6_destination_ip_reg_tmp = capture_be128(word, ipv6_destination_ip_reg_tmp, unsigned'(8'((markup_pos + 'h18))), word_cntr, word_bytes);
            if (field_complete(markup_pos, 'h28, word_cntr, word_bytes)) begin
                selector=unsigned'(8'(ipv6_base_next_proto_reg_tmp));
                if (is_ipv6_extension(selector)) begin
                    call.progress.state = unsigned'(8'(PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS));
                    call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + 'h28))));
                end
                else begin
                    call.progress.pos = unsigned'(8'(unsigned'(8'(markup_pos + 'h28))));
                    call.progress.state = select_transport(selector);
                    if (unsigned'(8'(call.progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_NONE) begin
                        call.progress.done = unsigned'(1'h1);
                    end
                end
            end
        end
        return call;
    endfunction

    function PacketParserCall parse_mpls4 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_MPLS);
        call = mpls_work('h3, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_mpls3 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_MPLS);
        call = mpls_work('h2, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_mpls2 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_MPLS);
        call = mpls_work('h1, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_mpls1 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_MPLS);
        call = mpls_work('h0, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_vlan4 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_VLAN);
        call = vlan_work('h3, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_vlan3 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_VLAN);
        call = vlan_work('h2, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_vlan2 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_VLAN);
        call = vlan_work('h1, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_vlan1 (
        input logic[7:0] markup_pos
,       input logic[64-1:0] markup_state
,       input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[64-1:0] marked_state;
        PacketParserCall call;
        marked_state = mark_header(markup_state, markup_pos, PacketParserHeaderId_pkg::PACKET_HEADER_VLAN);
        call = vlan_work('h0, markup_pos, marked_state, progress, word, word_bytes, word_cntr);
        return call;
    endfunction

    function PacketParserCall parse_ethernet (
        input PacketParserProgress progress
,       input logic[64-1:0] word
,       input logic[7:0] word_bytes
,       input logic[7:0] word_cntr
    );
        logic[15:0] selector;
        PacketParserCall call;
        call.markup_state = 'h0;
        call.progress = progress;
        if (!ethernet_done_reg_tmp) begin
            destination_mac_reg_tmp = capture_be48(word, destination_mac_reg_tmp, 'h0, word_cntr, word_bytes);
            source_mac_reg_tmp = capture_be48(word, source_mac_reg_tmp, 'h6, word_cntr, word_bytes);
            ethernet_type_reg_tmp = capture_be16(word, unsigned'(16'(ethernet_type_reg_tmp)), 'hC, word_cntr, word_bytes);
            if (field_complete('hC, 'h2, word_cntr, word_bytes)) begin
                ethernet_done_reg_tmp = unsigned'(1'h1);
                selector=unsigned'(16'(ethernet_type_reg_tmp));
                call.progress.pos = unsigned'(8'hE);
                call.progress.state = select_l3(selector);
                if (unsigned'(8'(call.progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_NONE) begin
                    call.progress.error = unsigned'(1'h1);
                end
            end
        end
        return call;
    endfunction

    task hold_parser ();
    begin: hold_parser
        logic[31:0] index;
        state_reg_tmp = state_reg;
        pos_reg_tmp = pos_reg;
        word_cntr_reg_tmp = word_cntr_reg;
        ethernet_done_reg_tmp = ethernet_done_reg;
        error_reg_tmp = error_reg;
        limit_reg_tmp = limit_reg;
        done_reg_tmp = done_reg;
        destination_mac_reg_tmp = destination_mac_reg;
        source_mac_reg_tmp = source_mac_reg;
        ethernet_type_reg_tmp = ethernet_type_reg;
        for (index='h0;index < 'h4;index=index+1) begin
            vlan_next_proto_reg_tmp[index] = vlan_next_proto_reg[index];
        end
        vlan_count_reg_tmp = vlan_count_reg;
        for (index='h0;index < 'h2;index=index+1) begin
            vlan_tci_reg_tmp[index] = vlan_tci_reg[index];
        end
        for (index='h0;index < 'h4;index=index+1) begin
            mpls_entry_reg_tmp[index] = mpls_entry_reg[index];
            mpls_entry_done_reg_tmp[index] = mpls_entry_done_reg[index];
        end
        mpls_count_reg_tmp = mpls_count_reg;
        for (index='h0;index < 'h2;index=index+1) begin
            mpls_output_reg_tmp[index] = mpls_output_reg[index];
        end
        source_ip_reg_tmp = source_ip_reg;
        destination_ip_reg_tmp = destination_ip_reg;
        protocol_reg_tmp = protocol_reg;
        ip_version_reg_tmp = ip_version_reg;
        ip_header_bytes_reg_tmp = ip_header_bytes_reg;
        transport_pos_reg_tmp = transport_pos_reg;
        ipv4_fragment_reg_tmp = ipv4_fragment_reg;
        initial_fragment_reg_tmp = initial_fragment_reg;
        ipv6_source_ip_reg_tmp = ipv6_source_ip_reg;
        ipv6_destination_ip_reg_tmp = ipv6_destination_ip_reg;
        ipv6_base_next_proto_reg_tmp = ipv6_base_next_proto_reg;
        ipv6_seen_reg_tmp = ipv6_seen_reg;
        for (index='h0;index < 'h4;index=index+1) begin
            ipv6_next_proto_reg_tmp[index] = ipv6_next_proto_reg[index];
            ipv6_ext_size_reg_tmp[index] = ipv6_ext_size_reg[index];
            ipv6_ext_seen_reg_tmp[index] = ipv6_ext_seen_reg[index];
            ipv6_fragment_reg_tmp[index] = ipv6_fragment_reg[index];
            noninitial_fragment_reg_tmp[index] = noninitial_fragment_reg[index];
        end
        source_port_reg_tmp = source_port_reg;
        destination_port_reg_tmp = destination_port_reg;
        tcp_header_bytes_reg_tmp = tcp_header_bytes_reg;
    end
    endtask

    function PacketParserPipeWord ethernet_stage (input PacketParserPipeWord item);
        PacketParserPipeWord result;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if (item.sop) begin
            ethernet_done_reg_tmp = unsigned'(1'h0);
            destination_mac_reg_tmp = 'h0;
            source_mac_reg_tmp = 'h0;
            ethernet_type_reg_tmp = unsigned'(16'h0);
            progress = item.progress;
        end
        else begin
            progress = accept_upstream(ethernet_progress_reg, item.progress);
        end
        call = parse_ethernet(progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
        progress = call.progress;
        ethernet_progress_reg_tmp = progress;
        result.progress = progress;
        if (item.eop) begin
            result.fields.destination_mac = destination_mac_reg_tmp;
            result.fields.source_mac = source_mac_reg_tmp;
        end
        return result;
    endfunction

    function PacketParserPipeWord vlan_stage (
        input logic[7:0] occurrence
,       input PacketParserPipeWord item
    );
        PacketParserPipeWord result;
        logic[7:0] markup_pos;
        logic[7:0] prior_pos;
        logic[7:0] stage_index;
        logic[7:0] flags;
        logic[7:0] vlan_count;
        logic[64-1:0] markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if (item.sop) begin
            vlan_next_proto_reg_tmp[occurrence] = unsigned'(16'h0);
            if (occurrence < 'h2) begin
                vlan_tci_reg_tmp[occurrence] = unsigned'(16'h0);
            end
            progress = item.progress;
            stage_index='h0;
            vlan_progress_reg_tmp[occurrence] = progress;
            vlan_stage_index_reg_tmp[occurrence] = 'h0;
            result.progress = progress;
            result.vlan_index = 'h0;
            return result;
        end
        else begin
            progress = vlan_progress_reg[occurrence];
            stage_index=unsigned'(8'(vlan_stage_index_reg[occurrence]));
            if (stage_index < occurrence) begin
                progress = item.progress;
                if (item.vlan_index>=occurrence) begin
                    stage_index=occurrence;
                end
            end
            else begin
                if (stage_index == occurrence) begin
                    progress = accept_vlan_upstream(progress, item.progress);
                end
            end
        end
        markup_state = 'h0;
        markup_pos=unsigned'(8'(progress.pos));
        prior_pos=markup_pos;
        if ((unsigned'(8'(progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_VLAN) && (stage_index == occurrence)) begin
            call.progress = progress;
            call.markup_state = 'h0;
            if (occurrence == 'h0) begin
                call = parse_vlan1(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h1) begin
                call = parse_vlan2(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h2) begin
                call = parse_vlan3(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h3) begin
                call = parse_vlan4(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            progress = call.progress;
            if (((((unsigned'(8'(progress.pos)) != prior_pos) || (unsigned'(8'(progress.state)) != PacketParserHeaderId_pkg::PACKET_HEADER_VLAN)) || progress.error) || progress.limit) || progress.done) begin
                stage_index=occurrence + 'h1;
            end
        end
        vlan_progress_reg_tmp[occurrence] = progress;
        vlan_stage_index_reg_tmp[occurrence] = unsigned'(3'(unsigned'(3'(stage_index))));
        result.progress = progress;
        if (unsigned'(8'(item.vlan_index)) > stage_index) begin
            result.vlan_index = item.vlan_index;
        end
        else begin
            result.vlan_index = unsigned'(3'(unsigned'(3'(stage_index))));
        end
        if (item.eop) begin
            if (occurrence < 'h2) begin
                result.fields.vlan_tci[occurrence] = vlan_tci_reg_tmp[occurrence];
            end
            if (occurrence == 'h3) begin
                flags=unsigned'(8'(result.fields.flags));
                vlan_count=unsigned'(8'(result.vlan_index));
                if (vlan_count != 'h0) begin
                    flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_VLAN;
                end
                result.fields.flags = unsigned'(8'(unsigned'(8'(flags))));
                result.fields.ip_meta = unsigned'(8'(unsigned'(8'(((unsigned'(8'(result.fields.ip_meta)) & 'hCF)) | (((((vlan_count > 'h3)) ? ('h3) : (vlan_count)) <<< 'h4))))));
            end
        end
        return result;
    endfunction

    function PacketParserPipeWord vlan1_stage (input PacketParserPipeWord item);
        return vlan_stage('h0, item);
    endfunction

    function PacketParserPipeWord vlan2_stage (input PacketParserPipeWord item);
        return vlan_stage('h1, item);
    endfunction

    function PacketParserPipeWord vlan3_stage (input PacketParserPipeWord item);
        return vlan_stage('h2, item);
    endfunction

    function PacketParserPipeWord vlan4_stage (input PacketParserPipeWord item);
        return vlan_stage('h3, item);
    endfunction

    function PacketParserPipeWord mpls_stage (
        input logic[7:0] occurrence
,       input PacketParserPipeWord item
    );
        PacketParserPipeWord result;
        logic[7:0] markup_pos;
        logic[7:0] prior_pos;
        logic[7:0] stage_index;
        logic[7:0] flags;
        logic[7:0] mpls_count;
        logic[64-1:0] markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if (item.sop) begin
            mpls_entry_reg_tmp[occurrence] = unsigned'(32'h0);
            mpls_entry_done_reg_tmp[occurrence] = unsigned'(1'h0);
            if (occurrence < 'h2) begin
                mpls_output_reg_tmp[occurrence] = unsigned'(32'h0);
            end
            progress = item.progress;
            stage_index='h0;
            mpls_progress_reg_tmp[occurrence] = progress;
            mpls_stage_index_reg_tmp[occurrence] = 'h0;
            result.progress = progress;
            result.mpls_index = 'h0;
            return result;
        end
        else begin
            progress = mpls_progress_reg[occurrence];
            stage_index=unsigned'(8'(mpls_stage_index_reg[occurrence]));
            if (stage_index < occurrence) begin
                progress = item.progress;
                if (item.mpls_index>=occurrence) begin
                    stage_index=occurrence;
                end
            end
            else begin
                if (stage_index == occurrence) begin
                    progress = accept_mpls_upstream(progress, item.progress);
                end
            end
        end
        markup_state = 'h0;
        markup_pos=unsigned'(8'(progress.pos));
        prior_pos=markup_pos;
        if ((unsigned'(8'(progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_MPLS) && (stage_index == occurrence)) begin
            call.progress = progress;
            call.markup_state = 'h0;
            if (occurrence == 'h0) begin
                call = parse_mpls1(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h1) begin
                call = parse_mpls2(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h2) begin
                call = parse_mpls3(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h3) begin
                call = parse_mpls4(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            progress = call.progress;
            if (((((unsigned'(8'(progress.pos)) != prior_pos) || (unsigned'(8'(progress.state)) != PacketParserHeaderId_pkg::PACKET_HEADER_MPLS)) || progress.error) || progress.limit) || progress.done) begin
                stage_index=occurrence + 'h1;
            end
        end
        mpls_progress_reg_tmp[occurrence] = progress;
        mpls_stage_index_reg_tmp[occurrence] = unsigned'(3'(unsigned'(3'(stage_index))));
        result.progress = progress;
        if (unsigned'(8'(item.mpls_index)) > stage_index) begin
            result.mpls_index = item.mpls_index;
        end
        else begin
            result.mpls_index = unsigned'(3'(unsigned'(3'(stage_index))));
        end
        if (item.eop) begin
            if (occurrence < 'h2) begin
                result.fields.mpls[occurrence] = mpls_output_reg_tmp[occurrence];
            end
            if (occurrence == 'h3) begin
                flags=unsigned'(8'(result.fields.flags));
                mpls_count=unsigned'(8'(result.mpls_index));
                if (mpls_count != 'h0) begin
                    flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_MPLS;
                end
                result.fields.flags = unsigned'(8'(unsigned'(8'(flags))));
                result.fields.ip_meta = unsigned'(8'(unsigned'(8'(((unsigned'(8'(result.fields.ip_meta)) & 'h3F)) | (((((mpls_count > 'h3)) ? ('h3) : (mpls_count)) <<< 'h6))))));
            end
        end
        return result;
    endfunction

    function PacketParserPipeWord mpls1_stage (input PacketParserPipeWord item);
        return mpls_stage('h0, item);
    endfunction

    function PacketParserPipeWord mpls2_stage (input PacketParserPipeWord item);
        return mpls_stage('h1, item);
    endfunction

    function PacketParserPipeWord mpls3_stage (input PacketParserPipeWord item);
        return mpls_stage('h2, item);
    endfunction

    function PacketParserPipeWord mpls4_stage (input PacketParserPipeWord item);
        return mpls_stage('h3, item);
    endfunction

    function PacketParserPipeWord ipv4_stage (input PacketParserPipeWord item);
        PacketParserPipeWord result;
        logic[7:0] markup_pos;
        logic[7:0] flags;
        logic[64-1:0] markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if (item.sop) begin
            source_ip_reg_tmp = 'h0;
            destination_ip_reg_tmp = 'h0;
            protocol_reg_tmp = unsigned'(8'h0);
            ip_version_reg_tmp = unsigned'(8'h0);
            ip_header_bytes_reg_tmp = unsigned'(8'h0);
            transport_pos_reg_tmp = unsigned'(8'h0);
            ipv4_fragment_reg_tmp = unsigned'(16'h0);
            initial_fragment_reg_tmp = unsigned'(1'h1);
            progress = item.progress;
            ipv4_progress_reg_tmp = progress;
            result.progress = progress;
            return result;
        end
        else begin
            progress = accept_ipv4_upstream(ipv4_progress_reg, item.progress);
        end
        markup_state = 'h0;
        markup_pos=unsigned'(8'(progress.pos));
        call = parse_ipv4(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
        progress = call.progress;
        markup_pos=unsigned'(8'(progress.pos));
        call = parse_ipv4_options(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
        progress = call.progress;
        ipv4_progress_reg_tmp = progress;
        result.progress = progress;
        if (unsigned'(8'(ip_version_reg_tmp)) == 'h4) begin
            result.fields.protocol = protocol_reg_tmp;
        end
        if (item.eop && (unsigned'(8'(ip_version_reg_tmp)) == 'h4)) begin
            result.fields.source_ip = source_ip_reg_tmp;
            result.fields.destination_ip = destination_ip_reg_tmp;
            result.fields.protocol = protocol_reg_tmp;
            result.fields.ip_meta = unsigned'(8'(unsigned'(8'(((unsigned'(8'(result.fields.ip_meta)) & 'hF0)) | 'h4))));
            flags=unsigned'(8'(result.fields.flags));
            if (((unsigned'(16'(ipv4_fragment_reg_tmp)) & 'h3FFF)) != 'h0) begin
                flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_FRAGMENT;
            end
            result.fields.flags = unsigned'(8'(unsigned'(8'(flags))));
        end
        return result;
    endfunction

    function PacketParserPipeWord ipv6_stage (input PacketParserPipeWord item);
        PacketParserPipeWord result;
        logic[7:0] markup_pos;
        logic[7:0] flags;
        logic[64-1:0] markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if (item.sop) begin
            ipv6_source_ip_reg_tmp = 'h0;
            ipv6_destination_ip_reg_tmp = 'h0;
            ipv6_base_next_proto_reg_tmp = unsigned'(8'h0);
            ipv6_seen_reg_tmp = unsigned'(1'h0);
            progress = item.progress;
            ipv6_progress_reg_tmp = progress;
            result.progress = progress;
            return result;
        end
        else begin
            progress = accept_ipv6_upstream(ipv6_progress_reg, item.progress);
        end
        markup_state = 'h0;
        markup_pos=unsigned'(8'(progress.pos));
        call = parse_ipv6(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
        progress = call.progress;
        ipv6_progress_reg_tmp = progress;
        result.progress = progress;
        if (ipv6_seen_reg_tmp) begin
            result.fields.protocol = ipv6_base_next_proto_reg_tmp;
        end
        if (item.eop && ipv6_seen_reg_tmp) begin
            result.fields.source_ip = ipv6_source_ip_reg_tmp;
            result.fields.destination_ip = ipv6_destination_ip_reg_tmp;
            result.fields.ip_meta = unsigned'(8'(unsigned'(8'(((unsigned'(8'(result.fields.ip_meta)) & 'hF0)) | 'h6))));
            flags=unsigned'(8'(result.fields.flags));
            flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_IPV6;
            result.fields.flags = unsigned'(8'(unsigned'(8'(flags))));
        end
        return result;
    endfunction

    function PacketParserPipeWord ipv6_ext_stage (
        input logic[7:0] occurrence
,       input PacketParserPipeWord item
    );
        PacketParserPipeWord result;
        logic[7:0] markup_pos;
        logic[7:0] flags;
        logic[7:0] prior_state;
        logic[7:0] stage_index;
        logic[7:0] prior_pos;
        logic[64-1:0] markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if (item.sop) begin
            ipv6_next_proto_reg_tmp[occurrence] = unsigned'(8'h0);
            ipv6_ext_size_reg_tmp[occurrence] = unsigned'(8'h0);
            ipv6_ext_seen_reg_tmp[occurrence] = unsigned'(1'h0);
            ipv6_fragment_reg_tmp[occurrence] = unsigned'(16'h0);
            noninitial_fragment_reg_tmp[occurrence] = unsigned'(1'h0);
            progress = item.progress;
            prior_state=PacketParserHeaderId_pkg::PACKET_HEADER_NONE;
            stage_index='h0;
            ipv6_ext_progress_reg_tmp[occurrence] = progress;
            ipv6_ext_stage_index_reg_tmp[occurrence] = 'h0;
            result.progress = progress;
            result.ipv6_ext_index = 'h0;
            return result;
        end
        else begin
            progress = ipv6_ext_progress_reg[occurrence];
            prior_state=unsigned'(8'(progress.state));
            stage_index=unsigned'(8'(ipv6_ext_stage_index_reg[occurrence]));
            if (stage_index < occurrence) begin
                progress = item.progress;
                if (item.ipv6_ext_index>=occurrence) begin
                    stage_index=occurrence;
                end
            end
            else begin
                if (stage_index == occurrence) begin
                    progress = accept_ipv6_ext_upstream(progress, item.progress);
                end
            end
        end
        if (((unsigned'(8'(progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS) && (stage_index == occurrence)) && (((prior_state != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS) || !ipv6_ext_seen_reg_tmp[occurrence]))) begin
            ipv6_next_proto_reg_tmp[occurrence] = item.fields.protocol;
            ipv6_ext_size_reg_tmp[occurrence] = unsigned'(8'h0);
            ipv6_fragment_reg_tmp[occurrence] = unsigned'(16'h0);
            noninitial_fragment_reg_tmp[occurrence] = unsigned'(1'h0);
            ipv6_ext_seen_reg_tmp[occurrence] = unsigned'(1'h1);
        end
        markup_state = 'h0;
        markup_pos=unsigned'(8'(progress.pos));
        prior_pos=markup_pos;
        if ((unsigned'(8'(progress.state)) == PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS) && (stage_index == occurrence)) begin
            call.progress = progress;
            call.markup_state = 'h0;
            if (occurrence == 'h0) begin
                call = parse_ipv6_options1(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h1) begin
                call = parse_ipv6_options2(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h2) begin
                call = parse_ipv6_options3(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            if (occurrence == 'h3) begin
                call = parse_ipv6_options4(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
            end
            progress = call.progress;
            if (((((unsigned'(8'(progress.pos)) != prior_pos) || (unsigned'(8'(progress.state)) != PacketParserHeaderId_pkg::PACKET_HEADER_IPV6_OPTIONS)) || progress.error) || progress.limit) || progress.done) begin
                stage_index=occurrence + 'h1;
            end
        end
        ipv6_ext_progress_reg_tmp[occurrence] = progress;
        ipv6_ext_stage_index_reg_tmp[occurrence] = unsigned'(3'(unsigned'(3'(stage_index))));
        result.progress = progress;
        result.ipv6_ext_index = unsigned'(3'(unsigned'(3'(stage_index))));
        if (ipv6_ext_seen_reg_tmp[occurrence]) begin
            result.fields.protocol = ipv6_next_proto_reg_tmp[occurrence];
        end
        if (item.eop && (unsigned'(16'(ipv6_fragment_reg_tmp[occurrence])) != 'h0)) begin
            flags=unsigned'(8'(result.fields.flags));
            flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_FRAGMENT;
            result.fields.flags = unsigned'(8'(unsigned'(8'(flags))));
        end
        return result;
    endfunction

    function PacketParserPipeWord ipv6_ext1_stage (input PacketParserPipeWord item);
        return ipv6_ext_stage('h0, item);
    endfunction

    function PacketParserPipeWord ipv6_ext2_stage (input PacketParserPipeWord item);
        return ipv6_ext_stage('h1, item);
    endfunction

    function PacketParserPipeWord ipv6_ext3_stage (input PacketParserPipeWord item);
        return ipv6_ext_stage('h2, item);
    endfunction

    function PacketParserPipeWord ipv6_ext4_stage (input PacketParserPipeWord item);
        return ipv6_ext_stage('h3, item);
    endfunction

    function PacketParserPipeWord transport_stage (input PacketParserPipeWord item);
        PacketParserPipeWord result;
        logic[7:0] markup_pos;
        logic[64-1:0] markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        if (item.sop) begin
            source_port_reg_tmp = unsigned'(16'h0);
            destination_port_reg_tmp = unsigned'(16'h0);
            tcp_header_bytes_reg_tmp = unsigned'(8'h0);
            progress = item.progress;
            state_reg_tmp = progress.state;
            pos_reg_tmp = progress.pos;
            error_reg_tmp = progress.error;
            limit_reg_tmp = progress.limit;
            done_reg_tmp = progress.done;
            word_cntr_reg_tmp = item.word_cntr;
            result.progress = progress;
            return result;
        end
        else begin
            progress.state = state_reg;
            progress.pos = pos_reg;
            progress.error = error_reg;
            progress.limit = limit_reg;
            progress.done = done_reg;
            progress = accept_transport_upstream(progress, item.progress);
        end
        markup_state = 'h0;
        markup_pos=unsigned'(8'(progress.pos));
        call = parse_tcp(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
        progress = call.progress;
        markup_pos=unsigned'(8'(progress.pos));
        call = parse_udp(markup_pos, markup_state, progress, item.data, unsigned'(8'(item.bytes)), unsigned'(8'(item.word_cntr)));
        progress = call.progress;
        state_reg_tmp = progress.state;
        pos_reg_tmp = progress.pos;
        error_reg_tmp = progress.error;
        limit_reg_tmp = progress.limit;
        done_reg_tmp = progress.done;
        word_cntr_reg_tmp = item.word_cntr;
        result.progress = progress;
        if (item.eop) begin
            result.fields.source_port = source_port_reg_tmp;
            result.fields.destination_port = destination_port_reg_tmp;
        end
        return result;
    endfunction

    function PacketParserWord finish_parser (input PacketParserPipeWord item);
        PacketParserWord word;
        PacketParserFields fields;
        logic[7:0] flags;
        word.raw = 'h0;
        fields = item.fields;
        flags=unsigned'(8'(fields.flags));
        if (item.progress.limit) begin
            flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_LIMIT;
        end
        else begin
            if (item.progress.error) begin
                flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED;
            end
            else begin
                if (item.progress.done) begin
                    flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_PARSED;
                    if ((unsigned'(8'(fields.protocol)) == 'h6) || (unsigned'(8'(fields.protocol)) == 'h11)) begin
                        flags|=PacketParserFlags_pkg::PACKET_PARSER_FLAG_TRANSPORT;
                    end
                end
            end
        end
        fields.flags = unsigned'(8'(unsigned'(8'(flags))));
        word.fields = fields;
        return word;
    endfunction

    function logic[64-1:0] store_aligned_byte (
        input logic[64-1:0] previous
,       input logic[8-1:0] _byte
,       input logic[7:0] slot
    );
        logic[64-1:0] result;
        result = previous;
        if (slot == 'h0) begin
            result['h0 +:8] = _byte;
        end
        if (slot == 'h1) begin
            result['h8 +:8] = _byte;
        end
        if (slot == 'h2) begin
            result['h10 +:8] = _byte;
        end
        if (slot == 'h3) begin
            result['h18 +:8] = _byte;
        end
        if (slot == 'h4) begin
            result['h20 +:8] = _byte;
        end
        if (slot == 'h5) begin
            result['h28 +:8] = _byte;
        end
        if (slot == 'h6) begin
            result['h30 +:8] = _byte;
        end
        if (slot == 'h7) begin
            result['h38 +:8] = _byte;
        end
        return result;
    endfunction

    function logic[512-1:0] store_raw_word (
        input logic[512-1:0] previous
,       input logic[64-1:0] word
,       input logic[7:0] slot
,       input logic enable
    );
        logic[512-1:0] result;
        result = previous;
        if (enable && (slot == 'h0)) begin
            result['h0 +:64] = word;
        end
        if (enable && (slot == 'h1)) begin
            result['h40 +:64] = word;
        end
        if (enable && (slot == 'h2)) begin
            result['h80 +:64] = word;
        end
        if (enable && (slot == 'h3)) begin
            result['hC0 +:64] = word;
        end
        if (enable && (slot == 'h4)) begin
            result['h100 +:64] = word;
        end
        if (enable && (slot == 'h5)) begin
            result['h140 +:64] = word;
        end
        if (enable && (slot == 'h6)) begin
            result['h180 +:64] = word;
        end
        if (enable && (slot == 'h7)) begin
            result['h1C0 +:64] = word;
        end
        return result;
    endfunction

    function logic[64-1:0] raw_keep_word (
        input logic[7:0] count
,       input logic[7:0] base
    );
        logic[64-1:0] result;
        logic[7:0] _byte;
        result = 'h0;
        for (_byte='h0;_byte < OUTPUT_BYTES;_byte=_byte+1) begin
            result[_byte] = (unsigned'(16'(base)) + _byte) < count;
        end
        return result;
    endfunction

    always_comb begin : output_data_comb_func  // output_data_comb_func
        logic[31:0] head;
        head='h0;
        output_data_comb.raw = 'h0;
        if (unsigned'(8'(fifo_count_reg)) != 'h0) begin
            head=unsigned'(8'(fifo_head_reg));
            output_data_comb.raw = fifo_data_reg[head];
        end
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        head='h0;
        output_keep_comb = 'h0;
        if (unsigned'(8'(fifo_count_reg)) != 'h0) begin
            head=unsigned'(8'(fifo_head_reg));
            for (_byte='h0;_byte < OUTPUT_BYTES;_byte=_byte+1) begin
                output_keep_comb[_byte] = fifo_keep_reg[head][_byte];
            end
        end
    end

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        output_valid_comb=unsigned'(8'(fifo_count_reg)) != 'h0;
    end

    always_comb begin : output_last_comb_func  // output_last_comb_func
        logic[31:0] head;
        head='h0;
        output_last_comb=0;
        if (unsigned'(8'(fifo_count_reg)) != 'h0) begin
            head=unsigned'(8'(fifo_head_reg));
            output_last_comb=fifo_last_reg[head];
        end
    end

    always_comb begin : output_raw_comb_func  // output_raw_comb_func
        logic[31:0] head;
        head='h0;
        output_raw_comb=0;
        if (unsigned'(8'(fifo_count_reg)) != 'h0) begin
            head=unsigned'(8'(fifo_head_reg));
            output_raw_comb=fifo_raw_reg[head];
        end
    end

    always_comb begin : input_ready_comb_func  // input_ready_comb_func
        logic[7:0] count;
        count=unsigned'(8'(output_reserved_reg));
        if ((unsigned'(8'(fifo_count_reg)) != 'h0) && ready_in) begin
            --count;
        end
        input_ready_comb=(count<=(OUTPUT_FIFO_WORDS - 'h2) && !pending_valid_reg) && (unsigned'(8'(raw_store_count_reg)) < RAW_STORE_WORDS);
    end

    generate  // _assign
        assign ready_out = input_ready_comb;
        assign data_out = output_data_comb;
        assign keep_out = output_keep_comb;
        assign valid_out = output_valid_comb;
        assign last_out = output_last_comb;
        assign raw_out = output_raw_comb;
        assign protocol_error_out = protocol_error_reg;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        logic[31:0] slot;
        logic[31:0] stage;
        logic[31:0] lane;
        logic[31:0] flat;
        logic[7:0] head;
        logic[7:0] tail;
        logic[7:0] fifo_count;
        logic[7:0] raw_store_head;
        logic[7:0] raw_store_tail;
        logic[7:0] raw_store_count;
        logic[7:0] output_reserved;
        logic[7:0] align_count;
        logic[7:0] raw_count;
        logic[7:0] raw_word_count;
        logic[7:0] align_word_cntr;
        logic[7:0] emit_word_cntr;
        logic[7:0] emit2_word_cntr;
        logic in_frame;
        logic frame_raw;
        logic keep;
        logic sop;
        logic eop;
        logic emit_valid;
        logic emit_raw;
        logic emit2_valid;
        logic emit2_raw;
        logic emit_sop;
        logic emit_eop;
        logic emit2_sop;
        logic emit2_eop;
        logic frame_end;
        logic rollover;
        logic end_raw;
        logic pending_valid;
        logic pending_rollover;
        logic parse_valid;
        logic consume_pending;
        logic[7:0] input_byte;
        logic[7:0] emit_bytes;
        logic[7:0] emit2_bytes;
        logic[7:0] pending_bytes;
        logic[7:0] parse_bytes;
        logic[7:0] parse_word_cntr;
        logic parse_sop;
        logic parse_eop;
        logic align_sop_pending;
        logic[64-1:0] align_data;
        logic[64-1:0] emit_data;
        logic[64-1:0] emit2_data;
        logic[64-1:0] pending_data;
        logic[64-1:0] parse_data;
        logic[512-1:0] raw_data_low;
        logic[512-1:0] raw_data_high;
        logic[512-1:0] end_raw_data_low;
        logic[512-1:0] end_raw_data_high;
        logic[7:0] end_raw_count;
        logic[7:0] end_raw_word_count;
        PacketParserWord parsed;
        PacketParserPipeWord pipe_item;
        PacketParserProgress empty_progress;
        if (reset) begin
            reset_parser();
            align_data_reg_tmp = 'h0;
            align_count_reg_tmp = 'h0;
            raw_data_low_reg_tmp = 'h0;
            raw_data_high_reg_tmp = 'h0;
            raw_count_reg_tmp = unsigned'(8'h0);
            raw_word_count_reg_tmp = 'h0;
            in_frame_reg_tmp = unsigned'(1'h0);
            frame_raw_reg_tmp = unsigned'(1'h0);
            pending_valid_reg_tmp = unsigned'(1'h0);
            pending_rollover_reg_tmp = unsigned'(1'h0);
            pending_data_reg_tmp = 'h0;
            pending_bytes_reg_tmp = 'h0;
            pending_word_cntr_reg_tmp = unsigned'(8'h0);
            pending_sop_reg_tmp = unsigned'(1'h0);
            pending_eop_reg_tmp = unsigned'(1'h0);
            align_word_cntr_reg_tmp = unsigned'(8'h0);
            align_sop_pending_reg_tmp = unsigned'(1'h0);
            for (stage='h0;stage < PIPE_STAGES;stage=stage+1) begin
                pipe_reg_tmp[stage] = 0;
                pipe_valid_reg_tmp[stage] = unsigned'(1'h0);
            end
            raw_store_head_reg_tmp = unsigned'(1'h0);
            raw_store_tail_reg_tmp = unsigned'(1'h0);
            raw_store_count_reg_tmp = 'h0;
            for (slot='h0;slot < RAW_STORE_WORDS;slot=slot+1) begin
                raw_store_low_reg_tmp[slot] = 'h0;
                raw_store_high_reg_tmp[slot] = 'h0;
                raw_store_count_bytes_reg_tmp[slot] = unsigned'(8'h0);
            end
            fifo_head_reg_tmp = 'h0;
            fifo_tail_reg_tmp = 'h0;
            fifo_count_reg_tmp = 'h0;
            output_reserved_reg_tmp = 'h0;
            for (slot='h0;slot < OUTPUT_FIFO_WORDS;slot=slot+1) begin
                fifo_data_reg_tmp[slot] = 'h0;
                fifo_keep_reg_tmp[slot] = 'h0;
                fifo_last_reg_tmp[slot] = unsigned'(1'h0);
                fifo_raw_reg_tmp[slot] = unsigned'(1'h0);
            end
            protocol_error_reg_tmp = unsigned'(1'h0);
            disable _work_net_clk;
        end
        protocol_error_reg_tmp = protocol_error_reg;
        hold_parser();
        ethernet_progress_reg_tmp = ethernet_progress_reg;
        for (stage='h0;stage < 'h4;stage=stage+1) begin
            vlan_progress_reg_tmp[stage] = vlan_progress_reg[stage];
            vlan_stage_index_reg_tmp[stage] = vlan_stage_index_reg[stage];
        end
        for (stage='h0;stage < 'h4;stage=stage+1) begin
            mpls_progress_reg_tmp[stage] = mpls_progress_reg[stage];
            mpls_stage_index_reg_tmp[stage] = mpls_stage_index_reg[stage];
        end
        ipv4_progress_reg_tmp = ipv4_progress_reg;
        ipv6_progress_reg_tmp = ipv6_progress_reg;
        for (stage='h0;stage < 'h4;stage=stage+1) begin
            ipv6_ext_progress_reg_tmp[stage] = ipv6_ext_progress_reg[stage];
            ipv6_ext_stage_index_reg_tmp[stage] = ipv6_ext_stage_index_reg[stage];
        end
        for (slot='h0;slot < OUTPUT_FIFO_WORDS;slot=slot+1) begin
            fifo_data_reg_tmp[slot] = fifo_data_reg[slot];
            fifo_keep_reg_tmp[slot] = fifo_keep_reg[slot];
            fifo_last_reg_tmp[slot] = fifo_last_reg[slot];
            fifo_raw_reg_tmp[slot] = fifo_raw_reg[slot];
        end
        for (slot='h0;slot < RAW_STORE_WORDS;slot=slot+1) begin
            raw_store_low_reg_tmp[slot] = raw_store_low_reg[slot];
            raw_store_high_reg_tmp[slot] = raw_store_high_reg[slot];
            raw_store_count_bytes_reg_tmp[slot] = raw_store_count_bytes_reg[slot];
        end
        head=unsigned'(8'(fifo_head_reg));
        tail=unsigned'(8'(fifo_tail_reg));
        fifo_count=unsigned'(8'(fifo_count_reg));
        output_reserved=unsigned'(8'(output_reserved_reg));
        raw_store_head=unsigned'(8'(raw_store_head_reg));
        raw_store_tail=unsigned'(8'(raw_store_tail_reg));
        raw_store_count=unsigned'(8'(raw_store_count_reg));
        if ((fifo_count != 'h0) && ready_in) begin
            head=((head + 'h1)) & ((OUTPUT_FIFO_WORDS - 'h1));
            --fifo_count;
            --output_reserved;
        end
        for (stage='h0;stage < PIPE_STAGES;stage=stage+1) begin
            pipe_reg_tmp[stage] = 0;
            pipe_valid_reg_tmp[stage] = unsigned'(1'h0);
        end
        if (pipe_valid_reg[PIPE_STAGES - 'h1]) begin
            pipe_item = pipe_reg[PIPE_STAGES - 'h1];
            if (pipe_item.eop) begin
                if (pipe_item.raw) begin
                    if ((raw_store_count != 'h0) && fifo_count<=(OUTPUT_FIFO_WORDS - 'h2)) begin
                        fifo_data_reg_tmp[tail] = raw_store_low_reg[raw_store_head];
                        fifo_keep_reg_tmp[tail] = raw_keep_word(unsigned'(8'(raw_store_count_bytes_reg[raw_store_head])), 'h0);
                        fifo_last_reg_tmp[tail] = unsigned'(1'h0);
                        fifo_raw_reg_tmp[tail] = unsigned'(1'h1);
                        tail=((tail + 'h1)) & ((OUTPUT_FIFO_WORDS - 'h1));
                        fifo_count=fifo_count+1;
                        fifo_data_reg_tmp[tail] = raw_store_high_reg[raw_store_head];
                        fifo_keep_reg_tmp[tail] = raw_keep_word(unsigned'(8'(raw_store_count_bytes_reg[raw_store_head])), OUTPUT_BYTES);
                        fifo_last_reg_tmp[tail] = unsigned'(1'h1);
                        fifo_raw_reg_tmp[tail] = unsigned'(1'h1);
                        tail=((tail + 'h1)) & ((OUTPUT_FIFO_WORDS - 'h1));
                        fifo_count=fifo_count+1;
                        raw_store_head=((raw_store_head + 'h1)) & ((RAW_STORE_WORDS - 'h1));
                        --raw_store_count;
                    end
                    else begin
                        protocol_error_reg_tmp = unsigned'(1'h1);
                    end
                end
                else begin
                    if ((!pipe_item.progress.done && !pipe_item.progress.error) && !pipe_item.progress.limit) begin
                        pipe_item.progress.error = unsigned'(1'h1);
                    end
                    parsed = finish_parser(pipe_item);
                    if (fifo_count < OUTPUT_FIFO_WORDS) begin
                        fifo_data_reg_tmp[tail] = parsed.raw;
                        fifo_keep_reg_tmp[tail] = ~('h0);
                        fifo_last_reg_tmp[tail] = unsigned'(1'h1);
                        fifo_raw_reg_tmp[tail] = unsigned'(1'h0);
                        tail=((tail + 'h1)) & ((OUTPUT_FIFO_WORDS - 'h1));
                        fifo_count=fifo_count+1;
                    end
                    else begin
                        protocol_error_reg_tmp = unsigned'(1'h1);
                    end
                end
            end
        end
        if (pipe_valid_reg['h4]) begin
            pipe_reg_tmp['h5] = transport_stage(pipe_reg['h4]);
            pipe_valid_reg_tmp['h5] = unsigned'(1'h1);
        end
        if (pipe_valid_reg['h3]) begin
            pipe_item = ipv4_stage(pipe_reg['h3]);
            pipe_item = ipv6_stage(pipe_item);
            pipe_item = ipv6_ext1_stage(pipe_item);
            pipe_item = ipv6_ext2_stage(pipe_item);
            pipe_item = ipv6_ext3_stage(pipe_item);
            pipe_item = ipv6_ext4_stage(pipe_item);
            pipe_reg_tmp['h4] = pipe_item;
            pipe_valid_reg_tmp['h4] = unsigned'(1'h1);
        end
        if (pipe_valid_reg['h2]) begin
            pipe_item = mpls1_stage(pipe_reg['h2]);
            pipe_item = mpls2_stage(pipe_item);
            pipe_item = mpls3_stage(pipe_item);
            pipe_item = mpls4_stage(pipe_item);
            pipe_reg_tmp['h3] = pipe_item;
            pipe_valid_reg_tmp['h3] = unsigned'(1'h1);
        end
        if (pipe_valid_reg['h1]) begin
            pipe_item = vlan1_stage(pipe_reg['h1]);
            pipe_item = vlan2_stage(pipe_item);
            pipe_item = vlan3_stage(pipe_item);
            pipe_item = vlan4_stage(pipe_item);
            pipe_reg_tmp['h2] = pipe_item;
            pipe_valid_reg_tmp['h2] = unsigned'(1'h1);
        end
        if (pipe_valid_reg['h0]) begin
            pipe_reg_tmp['h1] = ethernet_stage(pipe_reg['h0]);
            pipe_valid_reg_tmp['h1] = unsigned'(1'h1);
        end
        align_data = align_data_reg;
        align_count=unsigned'(8'(align_count_reg));
        raw_data_low = raw_data_low_reg;
        raw_data_high = raw_data_high_reg;
        raw_count=unsigned'(8'(raw_count_reg));
        raw_word_count=unsigned'(8'(raw_word_count_reg));
        in_frame=in_frame_reg;
        frame_raw=frame_raw_reg;
        pending_valid=pending_valid_reg;
        pending_rollover=pending_rollover_reg;
        pending_data = pending_data_reg;
        pending_bytes=unsigned'(8'(pending_bytes_reg));
        pending_word_cntr_reg_tmp = pending_word_cntr_reg;
        pending_sop_reg_tmp = pending_sop_reg;
        pending_eop_reg_tmp = pending_eop_reg;
        align_word_cntr=unsigned'(8'(align_word_cntr_reg));
        align_sop_pending=align_sop_pending_reg;
        emit_valid=0;
        emit_raw=0;
        emit2_valid=0;
        emit2_raw=0;
        emit_sop=0;
        emit_eop=0;
        emit2_sop=0;
        emit2_eop=0;
        emit_word_cntr='h0;
        emit2_word_cntr='h0;
        emit_bytes='h0;
        emit2_bytes='h0;
        emit_data = 'h0;
        emit2_data = 'h0;
        frame_end=0;
        rollover=0;
        end_raw=frame_raw;
        end_raw_data_low = raw_data_low;
        end_raw_data_high = raw_data_high;
        end_raw_count=raw_count;
        end_raw_word_count=raw_word_count;
        if (valid_in && input_ready_comb) begin
            for (lane='h0;lane < LANE_BYTES;lane=lane+1) begin
                flat=lane;
                keep=keep_in[flat];
                sop=sop_in[flat];
                eop=eop_in[flat];
                if (!keep) begin
                    if (sop || eop) begin
                        protocol_error_reg_tmp = unsigned'(1'h1);
                    end
                end
                else begin
                    if (sop) begin
                        if (in_frame) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                        if (frame_end) begin
                            rollover=1;
                        end
                        if (!frame_end) begin
                            end_raw_data_low = 'h0;
                            end_raw_data_high = 'h0;
                            end_raw_count='h0;
                            end_raw_word_count='h0;
                        end
                        align_data = 'h0;
                        align_count='h0;
                        raw_data_low = 'h0;
                        raw_data_high = 'h0;
                        raw_count='h0;
                        raw_word_count='h0;
                        align_word_cntr='h0;
                        align_sop_pending=1;
                        frame_raw=ENABLE_RAW && raw_in;
                        in_frame=1;
                    end
                    else begin
                        if (!in_frame) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                    end
                    if (in_frame) begin
                        input_byte=unsigned'(8'(data_in[flat*'h8 +:8]));
                        align_data = store_aligned_byte(align_data, unsigned'(8'(unsigned'(8'(input_byte)))), align_count);
                        align_count=align_count+1;
                        if (frame_raw && (raw_count < RAW_BYTES)) begin
                            raw_count=raw_count+1;
                        end
                        if ((align_count == LANE_BYTES) || eop) begin
                            if (emit_valid) begin
                                if (eop) begin
                                    emit2_valid=1;
                                    emit2_raw=frame_raw;
                                    emit2_bytes=align_count;
                                    emit2_data = align_data;
                                    emit2_word_cntr=align_word_cntr;
                                    emit2_sop=align_sop_pending;
                                    emit2_eop=eop;
                                    align_sop_pending=0;
                                    align_word_cntr=align_word_cntr+1;
                                    align_data = 'h0;
                                    align_count='h0;
                                end
                                else begin
                                    protocol_error_reg_tmp = unsigned'(1'h1);
                                end
                            end
                            else begin
                                emit_valid=1;
                                emit_raw=frame_raw;
                                emit_bytes=align_count;
                                emit_data = align_data;
                                emit_word_cntr=align_word_cntr;
                                emit_sop=align_sop_pending;
                                emit_eop=eop;
                                align_sop_pending=0;
                                align_word_cntr=align_word_cntr+1;
                                align_data = 'h0;
                                align_count='h0;
                            end
                        end
                        if (eop) begin
                            end_raw=frame_raw;
                            end_raw_data_low = raw_data_low;
                            end_raw_data_high = raw_data_high;
                            end_raw_count=raw_count;
                            end_raw_word_count=raw_word_count;
                            if (frame_end) begin
                                protocol_error_reg_tmp = unsigned'(1'h1);
                            end
                            frame_end=1;
                            in_frame=0;
                        end
                    end
                    else begin
                        if (eop) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                    end
                end
            end
        end
        consume_pending=pending_valid;
        parse_valid=consume_pending || ((emit_valid && !emit_raw));
        parse_data = (consume_pending) ? (pending_data) : (emit_data);
        parse_bytes=(consume_pending) ? (pending_bytes) : (emit_bytes);
        parse_word_cntr=(consume_pending) ? (unsigned'(8'(pending_word_cntr_reg))) : (emit_word_cntr);
        parse_sop=(consume_pending) ? (pending_sop_reg) : (emit_sop);
        parse_eop=(consume_pending) ? (pending_eop_reg) : (emit_eop);
        if (parse_valid) begin
            empty_progress = 0;
            pipe_item = 0;
            pipe_item.data = parse_data;
            pipe_item.fields = 0;
            pipe_item.progress = empty_progress;
            pipe_item.word_cntr = unsigned'(8'(unsigned'(8'(parse_word_cntr))));
            pipe_item.bytes = unsigned'(4'(unsigned'(4'(parse_bytes))));
            pipe_item.sop = unsigned'(1'(parse_sop));
            pipe_item.eop = unsigned'(1'(parse_eop));
            pipe_reg_tmp['h0] = pipe_item;
            pipe_valid_reg_tmp['h0] = unsigned'(1'h1);
            if (parse_eop) begin
                output_reserved=output_reserved+1;
            end
        end
        if ((emit_valid && emit_raw) && (end_raw_word_count < (RAW_BYTES/LANE_BYTES))) begin
            end_raw_data_low = store_raw_word(end_raw_data_low, emit_data, end_raw_word_count, end_raw_word_count < (OUTPUT_BYTES/LANE_BYTES));
            end_raw_data_high = store_raw_word(end_raw_data_high, emit_data, end_raw_word_count - (OUTPUT_BYTES/LANE_BYTES), end_raw_word_count>=OUTPUT_BYTES/LANE_BYTES);
            end_raw_word_count=end_raw_word_count+1;
            if (!rollover) begin
                raw_data_low = end_raw_data_low;
                raw_data_high = end_raw_data_high;
                raw_word_count=end_raw_word_count;
            end
        end
        if (emit2_valid) begin
            if (emit2_raw && (end_raw_word_count < (RAW_BYTES/LANE_BYTES))) begin
                end_raw_data_low = store_raw_word(end_raw_data_low, emit2_data, end_raw_word_count, end_raw_word_count < (OUTPUT_BYTES/LANE_BYTES));
                end_raw_data_high = store_raw_word(end_raw_data_high, emit2_data, end_raw_word_count - (OUTPUT_BYTES/LANE_BYTES), end_raw_word_count>=OUTPUT_BYTES/LANE_BYTES);
                end_raw_word_count=end_raw_word_count+1;
                if (!rollover) begin
                    raw_data_low = end_raw_data_low;
                    raw_data_high = end_raw_data_high;
                    raw_word_count=end_raw_word_count;
                end
            end
            else begin
                if (!emit2_raw) begin
                    pending_valid=1;
                    pending_data = emit2_data;
                    pending_bytes=emit2_bytes;
                    pending_rollover=rollover;
                    pending_word_cntr_reg_tmp = unsigned'(8'(unsigned'(8'(emit2_word_cntr))));
                    pending_sop_reg_tmp = unsigned'(1'(emit2_sop));
                    pending_eop_reg_tmp = unsigned'(1'(emit2_eop));
                    frame_end=0;
                end
            end
        end
        if (consume_pending) begin
            pending_valid=0;
            pending_rollover=0;
        end
        else begin
            if (frame_end) begin
                if (end_raw) begin
                    if ((raw_store_count < RAW_STORE_WORDS) && !parse_valid) begin
                        raw_store_low_reg_tmp[raw_store_tail] = end_raw_data_low;
                        raw_store_high_reg_tmp[raw_store_tail] = end_raw_data_high;
                        raw_store_count_bytes_reg_tmp[raw_store_tail] = unsigned'(8'(unsigned'(8'(end_raw_count))));
                        raw_store_tail=((raw_store_tail + 'h1)) & ((RAW_STORE_WORDS - 'h1));
                        raw_store_count=raw_store_count+1;
                        empty_progress = 0;
                        pipe_item = 0;
                        pipe_item.progress = empty_progress;
                        pipe_item.raw = unsigned'(1'h1);
                        pipe_item.sop = unsigned'(1'h1);
                        pipe_item.eop = unsigned'(1'h1);
                        pipe_reg_tmp['h0] = pipe_item;
                        pipe_valid_reg_tmp['h0] = unsigned'(1'h1);
                        output_reserved+='h2;
                    end
                    else begin
                        protocol_error_reg_tmp = unsigned'(1'h1);
                    end
                end
            end
        end
        align_data_reg_tmp = align_data;
        align_count_reg_tmp = unsigned'(4'(unsigned'(4'(align_count))));
        raw_data_low_reg_tmp = raw_data_low;
        raw_data_high_reg_tmp = raw_data_high;
        raw_count_reg_tmp = unsigned'(8'(unsigned'(8'(raw_count))));
        raw_word_count_reg_tmp = unsigned'(5'(unsigned'(5'(raw_word_count))));
        in_frame_reg_tmp = unsigned'(1'(in_frame));
        frame_raw_reg_tmp = unsigned'(1'(frame_raw));
        pending_valid_reg_tmp = unsigned'(1'(pending_valid));
        pending_rollover_reg_tmp = unsigned'(1'(pending_rollover));
        pending_data_reg_tmp = pending_data;
        pending_bytes_reg_tmp = unsigned'(4'(unsigned'(4'(pending_bytes))));
        if (!pending_valid) begin
            pending_word_cntr_reg_tmp = unsigned'(8'h0);
            pending_sop_reg_tmp = unsigned'(1'h0);
            pending_eop_reg_tmp = unsigned'(1'h0);
        end
        align_word_cntr_reg_tmp = unsigned'(8'(unsigned'(8'(align_word_cntr))));
        align_sop_pending_reg_tmp = unsigned'(1'(align_sop_pending));
        raw_store_head_reg_tmp = unsigned'(1'(raw_store_head != 'h0));
        raw_store_tail_reg_tmp = unsigned'(1'(raw_store_tail != 'h0));
        raw_store_count_reg_tmp = unsigned'(2'(unsigned'(2'(raw_store_count))));
        fifo_head_reg_tmp = unsigned'(2'(unsigned'(2'(head))));
        fifo_tail_reg_tmp = unsigned'(2'(unsigned'(2'(tail))));
        fifo_count_reg_tmp = unsigned'(3'(unsigned'(3'(fifo_count))));
        output_reserved_reg_tmp = unsigned'(3'(unsigned'(3'(output_reserved))));
    end
    endtask

    task _work (input logic reset);
    begin: _work
        _work_net_clk(reset);
    end
    endtask

    task _work_l2_clk (input logic unused);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        state_reg_tmp = state_reg;
        pos_reg_tmp = pos_reg;
        word_cntr_reg_tmp = word_cntr_reg;
        ethernet_done_reg_tmp = ethernet_done_reg;
        error_reg_tmp = error_reg;
        limit_reg_tmp = limit_reg;
        done_reg_tmp = done_reg;
        ethernet_progress_reg_tmp = ethernet_progress_reg;
        vlan_progress_reg_tmp = vlan_progress_reg;
        vlan_stage_index_reg_tmp = vlan_stage_index_reg;
        mpls_progress_reg_tmp = mpls_progress_reg;
        mpls_stage_index_reg_tmp = mpls_stage_index_reg;
        ipv4_progress_reg_tmp = ipv4_progress_reg;
        ipv6_progress_reg_tmp = ipv6_progress_reg;
        ipv6_ext_progress_reg_tmp = ipv6_ext_progress_reg;
        ipv6_ext_stage_index_reg_tmp = ipv6_ext_stage_index_reg;
        destination_mac_reg_tmp = destination_mac_reg;
        source_mac_reg_tmp = source_mac_reg;
        ethernet_type_reg_tmp = ethernet_type_reg;
        vlan_next_proto_reg_tmp = vlan_next_proto_reg;
        vlan_count_reg_tmp = vlan_count_reg;
        vlan_tci_reg_tmp = vlan_tci_reg;
        mpls_entry_reg_tmp = mpls_entry_reg;
        mpls_entry_done_reg_tmp = mpls_entry_done_reg;
        mpls_count_reg_tmp = mpls_count_reg;
        mpls_output_reg_tmp = mpls_output_reg;
        source_ip_reg_tmp = source_ip_reg;
        destination_ip_reg_tmp = destination_ip_reg;
        protocol_reg_tmp = protocol_reg;
        ip_version_reg_tmp = ip_version_reg;
        ip_header_bytes_reg_tmp = ip_header_bytes_reg;
        transport_pos_reg_tmp = transport_pos_reg;
        ipv4_fragment_reg_tmp = ipv4_fragment_reg;
        initial_fragment_reg_tmp = initial_fragment_reg;
        ipv6_source_ip_reg_tmp = ipv6_source_ip_reg;
        ipv6_destination_ip_reg_tmp = ipv6_destination_ip_reg;
        ipv6_base_next_proto_reg_tmp = ipv6_base_next_proto_reg;
        ipv6_seen_reg_tmp = ipv6_seen_reg;
        ipv6_next_proto_reg_tmp = ipv6_next_proto_reg;
        ipv6_ext_size_reg_tmp = ipv6_ext_size_reg;
        ipv6_ext_seen_reg_tmp = ipv6_ext_seen_reg;
        ipv6_fragment_reg_tmp = ipv6_fragment_reg;
        noninitial_fragment_reg_tmp = noninitial_fragment_reg;
        source_port_reg_tmp = source_port_reg;
        destination_port_reg_tmp = destination_port_reg;
        tcp_header_bytes_reg_tmp = tcp_header_bytes_reg;
        align_data_reg_tmp = align_data_reg;
        align_count_reg_tmp = align_count_reg;
        raw_data_low_reg_tmp = raw_data_low_reg;
        raw_data_high_reg_tmp = raw_data_high_reg;
        raw_count_reg_tmp = raw_count_reg;
        raw_word_count_reg_tmp = raw_word_count_reg;
        in_frame_reg_tmp = in_frame_reg;
        frame_raw_reg_tmp = frame_raw_reg;
        pending_valid_reg_tmp = pending_valid_reg;
        pending_rollover_reg_tmp = pending_rollover_reg;
        pending_data_reg_tmp = pending_data_reg;
        pending_bytes_reg_tmp = pending_bytes_reg;
        pending_word_cntr_reg_tmp = pending_word_cntr_reg;
        pending_sop_reg_tmp = pending_sop_reg;
        pending_eop_reg_tmp = pending_eop_reg;
        align_word_cntr_reg_tmp = align_word_cntr_reg;
        align_sop_pending_reg_tmp = align_sop_pending_reg;
        pipe_reg_tmp = pipe_reg;
        pipe_valid_reg_tmp = pipe_valid_reg;
        raw_store_low_reg_tmp = raw_store_low_reg;
        raw_store_high_reg_tmp = raw_store_high_reg;
        raw_store_count_bytes_reg_tmp = raw_store_count_bytes_reg;
        raw_store_head_reg_tmp = raw_store_head_reg;
        raw_store_tail_reg_tmp = raw_store_tail_reg;
        raw_store_count_reg_tmp = raw_store_count_reg;
        fifo_data_reg_tmp = fifo_data_reg;
        fifo_keep_reg_tmp = fifo_keep_reg;
        fifo_last_reg_tmp = fifo_last_reg;
        fifo_raw_reg_tmp = fifo_raw_reg;
        fifo_head_reg_tmp = fifo_head_reg;
        fifo_tail_reg_tmp = fifo_tail_reg;
        fifo_count_reg_tmp = fifo_count_reg;
        output_reserved_reg_tmp = output_reserved_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work_net_clk(reset);

        state_reg <= state_reg_tmp;
        pos_reg <= pos_reg_tmp;
        word_cntr_reg <= word_cntr_reg_tmp;
        ethernet_done_reg <= ethernet_done_reg_tmp;
        error_reg <= error_reg_tmp;
        limit_reg <= limit_reg_tmp;
        done_reg <= done_reg_tmp;
        ethernet_progress_reg <= ethernet_progress_reg_tmp;
        vlan_progress_reg <= vlan_progress_reg_tmp;
        vlan_stage_index_reg <= vlan_stage_index_reg_tmp;
        mpls_progress_reg <= mpls_progress_reg_tmp;
        mpls_stage_index_reg <= mpls_stage_index_reg_tmp;
        ipv4_progress_reg <= ipv4_progress_reg_tmp;
        ipv6_progress_reg <= ipv6_progress_reg_tmp;
        ipv6_ext_progress_reg <= ipv6_ext_progress_reg_tmp;
        ipv6_ext_stage_index_reg <= ipv6_ext_stage_index_reg_tmp;
        destination_mac_reg <= destination_mac_reg_tmp;
        source_mac_reg <= source_mac_reg_tmp;
        ethernet_type_reg <= ethernet_type_reg_tmp;
        vlan_next_proto_reg <= vlan_next_proto_reg_tmp;
        vlan_count_reg <= vlan_count_reg_tmp;
        vlan_tci_reg <= vlan_tci_reg_tmp;
        mpls_entry_reg <= mpls_entry_reg_tmp;
        mpls_entry_done_reg <= mpls_entry_done_reg_tmp;
        mpls_count_reg <= mpls_count_reg_tmp;
        mpls_output_reg <= mpls_output_reg_tmp;
        source_ip_reg <= source_ip_reg_tmp;
        destination_ip_reg <= destination_ip_reg_tmp;
        protocol_reg <= protocol_reg_tmp;
        ip_version_reg <= ip_version_reg_tmp;
        ip_header_bytes_reg <= ip_header_bytes_reg_tmp;
        transport_pos_reg <= transport_pos_reg_tmp;
        ipv4_fragment_reg <= ipv4_fragment_reg_tmp;
        initial_fragment_reg <= initial_fragment_reg_tmp;
        ipv6_source_ip_reg <= ipv6_source_ip_reg_tmp;
        ipv6_destination_ip_reg <= ipv6_destination_ip_reg_tmp;
        ipv6_base_next_proto_reg <= ipv6_base_next_proto_reg_tmp;
        ipv6_seen_reg <= ipv6_seen_reg_tmp;
        ipv6_next_proto_reg <= ipv6_next_proto_reg_tmp;
        ipv6_ext_size_reg <= ipv6_ext_size_reg_tmp;
        ipv6_ext_seen_reg <= ipv6_ext_seen_reg_tmp;
        ipv6_fragment_reg <= ipv6_fragment_reg_tmp;
        noninitial_fragment_reg <= noninitial_fragment_reg_tmp;
        source_port_reg <= source_port_reg_tmp;
        destination_port_reg <= destination_port_reg_tmp;
        tcp_header_bytes_reg <= tcp_header_bytes_reg_tmp;
        align_data_reg <= align_data_reg_tmp;
        align_count_reg <= align_count_reg_tmp;
        raw_data_low_reg <= raw_data_low_reg_tmp;
        raw_data_high_reg <= raw_data_high_reg_tmp;
        raw_count_reg <= raw_count_reg_tmp;
        raw_word_count_reg <= raw_word_count_reg_tmp;
        in_frame_reg <= in_frame_reg_tmp;
        frame_raw_reg <= frame_raw_reg_tmp;
        pending_valid_reg <= pending_valid_reg_tmp;
        pending_rollover_reg <= pending_rollover_reg_tmp;
        pending_data_reg <= pending_data_reg_tmp;
        pending_bytes_reg <= pending_bytes_reg_tmp;
        pending_word_cntr_reg <= pending_word_cntr_reg_tmp;
        pending_sop_reg <= pending_sop_reg_tmp;
        pending_eop_reg <= pending_eop_reg_tmp;
        align_word_cntr_reg <= align_word_cntr_reg_tmp;
        align_sop_pending_reg <= align_sop_pending_reg_tmp;
        pipe_reg <= pipe_reg_tmp;
        pipe_valid_reg <= pipe_valid_reg_tmp;
        raw_store_low_reg <= raw_store_low_reg_tmp;
        raw_store_high_reg <= raw_store_high_reg_tmp;
        raw_store_count_bytes_reg <= raw_store_count_bytes_reg_tmp;
        raw_store_head_reg <= raw_store_head_reg_tmp;
        raw_store_tail_reg <= raw_store_tail_reg_tmp;
        raw_store_count_reg <= raw_store_count_reg_tmp;
        fifo_data_reg <= fifo_data_reg_tmp;
        fifo_keep_reg <= fifo_keep_reg_tmp;
        fifo_last_reg <= fifo_last_reg_tmp;
        fifo_raw_reg <= fifo_raw_reg_tmp;
        fifo_head_reg <= fifo_head_reg_tmp;
        fifo_tail_reg <= fifo_tail_reg_tmp;
        fifo_count_reg <= fifo_count_reg_tmp;
        output_reserved_reg <= output_reserved_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
