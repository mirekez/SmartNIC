`default_nettype none

import Predef_pkg::*;
import Zicsr_pkg::*;
import Rv32im_pkg::*;
import Rv32ic_pkg::*;
import Rv32i_pkg::*;
import Mem_pkg::*;
import Alu_pkg::*;
import Wb_pkg::*;
import Br_pkg::*;
import Sys_pkg::*;
import Trap_pkg::*;
import Csr_pkg::*;
import State_pkg::*;
import Amo_pkg::*;
import L1CacheFsmState_pkg::*;
import L1InputRequestComb_pkg::*;
import L1LookupComb_pkg::*;
import L1RefillLinesComb_pkg::*;
import L1CpuResponseComb_pkg::*;
import L1CachePerf_pkg::*;
import L1RequestGeometryComb_pkg::*;
import L1MemDriver_pkg::*;
import L1RequestState_pkg::*;
import L1RefillState_pkg::*;
import L1HeldResponse_pkg::*;
import TribeSbiDebug_pkg::*;
import TribePerf_pkg::*;


module Tribe (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   output wire dmem_write_out
,   output wire[31:0] dmem_write_data_out
,   output wire[7:0] dmem_write_mask_out
,   output wire dmem_read_out
,   output wire[31:0] dmem_addr_out
,   output wire[31:0] imem_read_addr_out
,   output wire sbi_set_timer_out
,   output wire[31:0] sbi_timer_lo_out
,   output wire[31:0] sbi_timer_hi_out
,   output wire TribeSbiDebug debug_sbi_out
,   input wire[31:0] reset_pc_in
,   input wire[31:0] boot_hartid_in
,   input wire[31:0] boot_dtb_addr_in
,   input wire[2-1:0] boot_priv_in
,   input wire external_cache_invalidate_in
,   input wire peer_cache_invalidate_in
,   input wire[31:0] peer_cache_invalidate_addr_in
,   input wire[31:0] memory_base_in
,   input wire[31:0] memory_size_in
,   input wire[31:0] mem_region_size_in[4]
,   output wire i_mem_out__read_out
,   output wire i_mem_out__write_out
,   output wire[31:0] i_mem_out__addr_out
,   output wire[31:0] i_mem_out__write_data_out
,   output wire[7:0] i_mem_out__write_mask_out
,   output wire i_mem_out__cache_disable_out
,   input wire[256-1:0] i_mem_out__read_data_in
,   input wire i_mem_out__wait_in
,   output wire d_mem_out__read_out
,   output wire d_mem_out__write_out
,   output wire[31:0] d_mem_out__addr_out
,   output wire[31:0] d_mem_out__write_data_out
,   output wire[7:0] d_mem_out__write_mask_out
,   output wire d_mem_out__cache_disable_out
,   input wire[256-1:0] d_mem_out__read_data_in
,   input wire d_mem_out__wait_in
,   output wire TribePerf perf_out
,   input wire debugen_in
);
    parameter  SBI_EXT_BASE = 'h10;
    parameter  SBI_EXT_TIME = 'h54494D45;
    parameter  SBI_EXT_RFENCE = 'h52464E43;
    parameter  SBI_EXT_IPI = 'h735049;
    parameter  SBI_SUCCESS = 'h0;


    // regs and combs
    reg icache_invalidate_issued_reg;
    TribeSbiDebug debug_sbi_comb;
;
    reg[32-1:0] pc;
    reg valid;
    reg[32-1:0] alu_result_reg;
    State[2-1:0] state_reg;
    reg[2-1:0][32-1:0] predicted_next_reg;
    reg[2-1:0][32-1:0] fallthrough_reg;
    reg[2-1:0] predicted_taken_reg;
    reg[32-1:0] debug_alu_a_reg;
    reg[32-1:0] debug_alu_b_reg;
    reg[32-1:0] debug_branch_target_reg;
    reg debug_branch_taken_reg;
    reg output_write_active_reg;
    reg interrupt_entry_guard_reg;
    reg sbi_ret_a1_valid_reg;
    reg[32-1:0] sbi_ret_a1_reg;
    logic hazard_stall_comb;
;
    logic branch_stall_comb;
;
    logic branch_flush_comb;
;
    logic stall_comb;
;
    TribePerf perf_comb;
;
    logic[31:0] l2_data_addr_comb;
;
    logic memory_wait_comb;
;
    logic fetch_valid_comb;
;
    logic[31:0] decode_fallthrough_comb;
;
    logic decode_branch_valid_comb;
;
    logic decode_indirect_branch_valid_comb;
;
    logic[31:0] decode_branch_target_comb;
;
    logic[31:0] branch_actual_next_comb;
;
    logic branch_mispredict_comb;
;
    logic[31:0] fetch_addr_comb;
;
    logic sbi_legacy_ecall_comb;
    logic sbi_noop_comb;
    logic sbi_base_comb;
    logic sbi_set_timer_comb;
    logic[31:0] sbi_ret_value_comb;
    logic sbi_writes_a1_comb;
    logic sbi_handled_comb;
    logic[31:0] sbi_timer_lo_comb;
    logic[31:0] sbi_timer_hi_comb;
    logic sbi_ecall_debug_comb;
    logic[31:0] sbi_a7_debug_comb;
    logic[31:0] sbi_a6_debug_comb;
    logic[31:0] sbi_a0_debug_comb;
    logic interrupt_accept_comb;
;
    State exe_state_comb;
;
    State csr_state_comb;
;
    logic icache_invalidate_comb;
;
    logic sfence_vma_comb;
;

    // members
    wire[31:0] dec__pc_in;
    wire dec__instr_valid_in;
    wire[31:0] dec__instr_in;
    wire[31:0] dec__regs_data0_in;
    wire[31:0] dec__regs_data1_in;
    wire[5-1:0] dec__rs1_out;
    wire[5-1:0] dec__rs2_out;
    wire State dec__state_out;
    Decode      dec (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .pc_in(dec__pc_in)
,       .instr_valid_in(dec__instr_valid_in)
,       .instr_in(dec__instr_in)
,       .regs_data0_in(dec__regs_data0_in)
,       .regs_data1_in(dec__regs_data1_in)
,       .rs1_out(dec__rs1_out)
,       .rs2_out(dec__rs2_out)
,       .state_out(dec__state_out)
    );
    wire State exe__state_in;
    wire[31:0] exe__alu_result_out;
    wire[31:0] exe__debug_alu_a_out;
    wire[31:0] exe__debug_alu_b_out;
    wire exe__branch_taken_out;
    wire[31:0] exe__branch_target_out;
    Execute      exe (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .state_in(exe__state_in)
,       .alu_result_out(exe__alu_result_out)
,       .debug_alu_a_out(exe__debug_alu_a_out)
,       .debug_alu_b_out(exe__debug_alu_b_out)
,       .branch_taken_out(exe__branch_taken_out)
,       .branch_target_out(exe__branch_target_out)
    );
    wire State exe_mem__state_in;
    wire[31:0] exe_mem__alu_result_in;
    wire exe_mem__mem_stall_in;
    wire exe_mem__hold_in;
    wire exe_mem__transaction_owner_valid_in;
    wire exe_mem__mem_write_out;
    wire[31:0] exe_mem__mem_write_addr_out;
    wire[31:0] exe_mem__mem_write_data_out;
    wire[7:0] exe_mem__mem_write_mask_out;
    wire exe_mem__mem_read_out;
    wire[31:0] exe_mem__mem_read_addr_out;
    wire exe_mem__mem_split_out;
    wire exe_mem__mem_split_busy_out;
    wire exe_mem__split_load_out;
    wire[31:0] exe_mem__split_load_low_out;
    wire[31:0] exe_mem__split_load_high_out;
    ExecuteMem      exe_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .state_in(exe_mem__state_in)
,       .alu_result_in(exe_mem__alu_result_in)
,       .mem_stall_in(exe_mem__mem_stall_in)
,       .hold_in(exe_mem__hold_in)
,       .transaction_owner_valid_in(exe_mem__transaction_owner_valid_in)
,       .mem_write_out(exe_mem__mem_write_out)
,       .mem_write_addr_out(exe_mem__mem_write_addr_out)
,       .mem_write_data_out(exe_mem__mem_write_data_out)
,       .mem_write_mask_out(exe_mem__mem_write_mask_out)
,       .mem_read_out(exe_mem__mem_read_out)
,       .mem_read_addr_out(exe_mem__mem_read_addr_out)
,       .mem_split_out(exe_mem__mem_split_out)
,       .mem_split_busy_out(exe_mem__mem_split_busy_out)
,       .split_load_out(exe_mem__split_load_out)
,       .split_load_low_out(exe_mem__split_load_low_out)
,       .split_load_high_out(exe_mem__split_load_high_out)
    );
    wire State wb__state_in;
    wire[31:0] wb__alu_result_in;
    wire[31:0] wb__mem_data_in;
    wire[31:0] wb__mem_data_hi_in;
    wire[31:0] wb__mem_addr_in;
    wire wb__mem_split_in;
    wire[31:0] wb__regs_data_out;
    wire[7:0] wb__regs_wr_id_out;
    wire wb__regs_write_out;
    Writeback      wb (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .state_in(wb__state_in)
,       .alu_result_in(wb__alu_result_in)
,       .mem_data_in(wb__mem_data_in)
,       .mem_data_hi_in(wb__mem_data_hi_in)
,       .mem_addr_in(wb__mem_addr_in)
,       .mem_split_in(wb__mem_split_in)
,       .regs_data_out(wb__regs_data_out)
,       .regs_wr_id_out(wb__regs_wr_id_out)
,       .regs_write_out(wb__regs_write_out)
    );
    wire State wb_mem__state_in;
    wire[31:0] wb_mem__alu_result_in;
    wire wb_mem__split_load_in;
    wire[31:0] wb_mem__split_load_low_addr_in;
    wire[31:0] wb_mem__split_load_high_addr_in;
    wire wb_mem__dcache_read_valid_in;
    wire[31:0] wb_mem__dcache_read_addr_in;
    wire[31:0] wb_mem__dcache_read_data_in;
    wire wb_mem__dcache_write_valid_in;
    wire[31:0] wb_mem__dcache_write_addr_in;
    wire[31:0] wb_mem__dcache_write_data_in;
    wire[7:0] wb_mem__dcache_write_mask_in;
    wire wb_mem__store_forward_enable_in;
    wire wb_mem__hold_in;
    wire wb_mem__load_ready_out;
    wire[31:0] wb_mem__load_raw_out;
    wire[31:0] wb_mem__load_result_out;
    wire[31:0] wb_mem__wb_mem_data_out;
    wire[31:0] wb_mem__wb_mem_data_hi_out;
    wire wb_mem__debug_load_data_valid_out;
    wire[31:0] wb_mem__debug_load_addr_out;
    wire wb_mem__debug_split_low_valid_out;
    wire wb_mem__debug_split_high_valid_out;
    wire wb_mem__debug_held_load_valid_out;
    WritebackMem      wb_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .state_in(wb_mem__state_in)
,       .alu_result_in(wb_mem__alu_result_in)
,       .split_load_in(wb_mem__split_load_in)
,       .split_load_low_addr_in(wb_mem__split_load_low_addr_in)
,       .split_load_high_addr_in(wb_mem__split_load_high_addr_in)
,       .dcache_read_valid_in(wb_mem__dcache_read_valid_in)
,       .dcache_read_addr_in(wb_mem__dcache_read_addr_in)
,       .dcache_read_data_in(wb_mem__dcache_read_data_in)
,       .dcache_write_valid_in(wb_mem__dcache_write_valid_in)
,       .dcache_write_addr_in(wb_mem__dcache_write_addr_in)
,       .dcache_write_data_in(wb_mem__dcache_write_data_in)
,       .dcache_write_mask_in(wb_mem__dcache_write_mask_in)
,       .store_forward_enable_in(wb_mem__store_forward_enable_in)
,       .hold_in(wb_mem__hold_in)
,       .load_ready_out(wb_mem__load_ready_out)
,       .load_raw_out(wb_mem__load_raw_out)
,       .load_result_out(wb_mem__load_result_out)
,       .wb_mem_data_out(wb_mem__wb_mem_data_out)
,       .wb_mem_data_hi_out(wb_mem__wb_mem_data_hi_out)
,       .debug_load_data_valid_out(wb_mem__debug_load_data_valid_out)
,       .debug_load_addr_out(wb_mem__debug_load_addr_out)
,       .debug_split_low_valid_out(wb_mem__debug_split_low_valid_out)
,       .debug_split_high_valid_out(wb_mem__debug_split_high_valid_out)
,       .debug_held_load_valid_out(wb_mem__debug_held_load_valid_out)
    );
    wire State csr__state_in;
    wire State csr__trap_check_state_in;
    wire[2-1:0] csr__reset_priv_in;
    wire[31:0] csr__hartid_in;
    wire csr__interrupt_valid_in;
    wire[31:0] csr__interrupt_cause_in;
    wire csr__interrupt_to_supervisor_in;
    wire[31:0] csr__irq_pending_bits_in;
    wire csr__software_irq_set_in;
    wire[31:0] csr__read_data_out;
    wire[31:0] csr__time_lo_in;
    wire[31:0] csr__time_hi_in;
    wire[31:0] csr__trap_vector_out;
    wire[31:0] csr__epc_out;
    wire[31:0] csr__mepc_out;
    wire[31:0] csr__mtvec_out;
    wire[31:0] csr__mcause_out;
    wire[31:0] csr__mtval_out;
    wire[31:0] csr__sepc_out;
    wire[31:0] csr__stvec_out;
    wire[31:0] csr__scause_out;
    wire[31:0] csr__stval_out;
    wire csr__illegal_trap_out;
    wire[31:0] csr__mstatus_out;
    wire[31:0] csr__mie_out;
    wire[31:0] csr__mideleg_out;
    wire[31:0] csr__mip_sw_out;
    wire[31:0] csr__satp_out;
    wire[2-1:0] csr__priv_out;
    CSR      csr (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .state_in(csr__state_in)
,       .trap_check_state_in(csr__trap_check_state_in)
,       .reset_priv_in(csr__reset_priv_in)
,       .hartid_in(csr__hartid_in)
,       .interrupt_valid_in(csr__interrupt_valid_in)
,       .interrupt_cause_in(csr__interrupt_cause_in)
,       .interrupt_to_supervisor_in(csr__interrupt_to_supervisor_in)
,       .irq_pending_bits_in(csr__irq_pending_bits_in)
,       .software_irq_set_in(csr__software_irq_set_in)
,       .read_data_out(csr__read_data_out)
,       .time_lo_in(csr__time_lo_in)
,       .time_hi_in(csr__time_hi_in)
,       .trap_vector_out(csr__trap_vector_out)
,       .epc_out(csr__epc_out)
,       .mepc_out(csr__mepc_out)
,       .mtvec_out(csr__mtvec_out)
,       .mcause_out(csr__mcause_out)
,       .mtval_out(csr__mtval_out)
,       .sepc_out(csr__sepc_out)
,       .stvec_out(csr__stvec_out)
,       .scause_out(csr__scause_out)
,       .stval_out(csr__stval_out)
,       .illegal_trap_out(csr__illegal_trap_out)
,       .mstatus_out(csr__mstatus_out)
,       .mie_out(csr__mie_out)
,       .mideleg_out(csr__mideleg_out)
,       .mip_sw_out(csr__mip_sw_out)
,       .satp_out(csr__satp_out)
,       .priv_out(csr__priv_out)
    );
    wire[7:0] regs__write_addr_in;
    wire regs__write_in;
    wire[31:0] regs__write_data_in;
    wire[7:0] regs__write2_addr_in;
    wire regs__write2_in;
    wire[31:0] regs__write2_data_in;
    wire[7:0] regs__read_addr0_in;
    wire[7:0] regs__read_addr1_in;
    wire regs__read_in;
    wire[31:0] regs__read_data0_out;
    wire[31:0] regs__read_data1_out;
    wire[31:0] regs__reset_x10_in;
    wire[31:0] regs__reset_x11_in;
    wire[31:0] regs__x1_out;
    wire[31:0] regs__x10_out;
    wire[31:0] regs__x11_out;
    wire[31:0] regs__x16_out;
    wire[31:0] regs__x17_out;
    wire regs__debugen_in;
    File #(
        32
,       32
    ) regs (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(regs__write_addr_in)
,       .write_in(regs__write_in)
,       .write_data_in(regs__write_data_in)
,       .write2_addr_in(regs__write2_addr_in)
,       .write2_in(regs__write2_in)
,       .write2_data_in(regs__write2_data_in)
,       .read_addr0_in(regs__read_addr0_in)
,       .read_addr1_in(regs__read_addr1_in)
,       .read_in(regs__read_in)
,       .read_data0_out(regs__read_data0_out)
,       .read_data1_out(regs__read_data1_out)
,       .reset_x10_in(regs__reset_x10_in)
,       .reset_x11_in(regs__reset_x11_in)
,       .x1_out(regs__x1_out)
,       .x10_out(regs__x10_out)
,       .x11_out(regs__x11_out)
,       .x16_out(regs__x16_out)
,       .x17_out(regs__x17_out)
,       .debugen_in(regs__debugen_in)
    );
    wire icache__write_in;
    wire[31:0] icache__write_data_in;
    wire[7:0] icache__write_mask_in;
    wire icache__read_in;
    wire[31:0] icache__addr_in;
    wire[31:0] icache__read_data_out;
    wire[31:0] icache__read_addr_out;
    wire icache__read_valid_out;
    wire icache__busy_out;
    wire icache__stall_in;
    wire icache__flush_in;
    wire icache__invalidate_in;
    wire icache__invalidate_line_in;
    wire[31:0] icache__invalidate_addr_in;
    wire icache__cache_disable_in;
    wire icache__mem_out__read_out;
    wire icache__mem_out__write_out;
    wire[31:0] icache__mem_out__addr_out;
    wire[31:0] icache__mem_out__write_data_out;
    wire[7:0] icache__mem_out__write_mask_out;
    wire icache__mem_out__cache_disable_out;
    wire[256-1:0] icache__mem_out__read_data_in;
    wire icache__mem_out__wait_in;
    wire L1CachePerf icache__perf_out;
    wire icache__debugen_in;
    L1Cache #(
        2048
,       32
,       2
,       0
,       32
,       256
    ) icache (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_in(icache__write_in)
,       .write_data_in(icache__write_data_in)
,       .write_mask_in(icache__write_mask_in)
,       .read_in(icache__read_in)
,       .addr_in(icache__addr_in)
,       .read_data_out(icache__read_data_out)
,       .read_addr_out(icache__read_addr_out)
,       .read_valid_out(icache__read_valid_out)
,       .busy_out(icache__busy_out)
,       .stall_in(icache__stall_in)
,       .flush_in(icache__flush_in)
,       .invalidate_in(icache__invalidate_in)
,       .invalidate_line_in(icache__invalidate_line_in)
,       .invalidate_addr_in(icache__invalidate_addr_in)
,       .cache_disable_in(icache__cache_disable_in)
,       .mem_out__read_out(icache__mem_out__read_out)
,       .mem_out__write_out(icache__mem_out__write_out)
,       .mem_out__addr_out(icache__mem_out__addr_out)
,       .mem_out__write_data_out(icache__mem_out__write_data_out)
,       .mem_out__write_mask_out(icache__mem_out__write_mask_out)
,       .mem_out__cache_disable_out(icache__mem_out__cache_disable_out)
,       .mem_out__read_data_in(icache__mem_out__read_data_in)
,       .mem_out__wait_in(icache__mem_out__wait_in)
,       .perf_out(icache__perf_out)
,       .debugen_in(icache__debugen_in)
    );
    wire dcache__write_in;
    wire[31:0] dcache__write_data_in;
    wire[7:0] dcache__write_mask_in;
    wire dcache__read_in;
    wire[31:0] dcache__addr_in;
    wire[31:0] dcache__read_data_out;
    wire[31:0] dcache__read_addr_out;
    wire dcache__read_valid_out;
    wire dcache__busy_out;
    wire dcache__stall_in;
    wire dcache__flush_in;
    wire dcache__invalidate_in;
    wire dcache__invalidate_line_in;
    wire[31:0] dcache__invalidate_addr_in;
    wire dcache__cache_disable_in;
    wire dcache__mem_out__read_out;
    wire dcache__mem_out__write_out;
    wire[31:0] dcache__mem_out__addr_out;
    wire[31:0] dcache__mem_out__write_data_out;
    wire[7:0] dcache__mem_out__write_mask_out;
    wire dcache__mem_out__cache_disable_out;
    wire[256-1:0] dcache__mem_out__read_data_in;
    wire dcache__mem_out__wait_in;
    wire L1CachePerf dcache__perf_out;
    wire dcache__debugen_in;
    L1Cache #(
        1024
,       32
,       2
,       1
,       32
,       256
    ) dcache (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_in(dcache__write_in)
,       .write_data_in(dcache__write_data_in)
,       .write_mask_in(dcache__write_mask_in)
,       .read_in(dcache__read_in)
,       .addr_in(dcache__addr_in)
,       .read_data_out(dcache__read_data_out)
,       .read_addr_out(dcache__read_addr_out)
,       .read_valid_out(dcache__read_valid_out)
,       .busy_out(dcache__busy_out)
,       .stall_in(dcache__stall_in)
,       .flush_in(dcache__flush_in)
,       .invalidate_in(dcache__invalidate_in)
,       .invalidate_line_in(dcache__invalidate_line_in)
,       .invalidate_addr_in(dcache__invalidate_addr_in)
,       .cache_disable_in(dcache__cache_disable_in)
,       .mem_out__read_out(dcache__mem_out__read_out)
,       .mem_out__write_out(dcache__mem_out__write_out)
,       .mem_out__addr_out(dcache__mem_out__addr_out)
,       .mem_out__write_data_out(dcache__mem_out__write_data_out)
,       .mem_out__write_mask_out(dcache__mem_out__write_mask_out)
,       .mem_out__cache_disable_out(dcache__mem_out__cache_disable_out)
,       .mem_out__read_data_in(dcache__mem_out__read_data_in)
,       .mem_out__wait_in(dcache__mem_out__wait_in)
,       .perf_out(dcache__perf_out)
,       .debugen_in(dcache__debugen_in)
    );
    wire bp__lookup_valid_in;
    wire[31:0] bp__lookup_pc_in;
    wire[31:0] bp__lookup_target_in;
    wire[31:0] bp__lookup_fallthrough_in;
    wire[4-1:0] bp__lookup_br_op_in;
    wire bp__predict_taken_out;
    wire[31:0] bp__predict_next_out;
    wire bp__update_valid_in;
    wire[31:0] bp__update_pc_in;
    wire bp__update_taken_in;
    wire[31:0] bp__update_target_in;
    BranchPredictor #(
        16
,       2
    ) bp (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .lookup_valid_in(bp__lookup_valid_in)
,       .lookup_pc_in(bp__lookup_pc_in)
,       .lookup_target_in(bp__lookup_target_in)
,       .lookup_fallthrough_in(bp__lookup_fallthrough_in)
,       .lookup_br_op_in(bp__lookup_br_op_in)
,       .predict_taken_out(bp__predict_taken_out)
,       .predict_next_out(bp__predict_next_out)
,       .update_valid_in(bp__update_valid_in)
,       .update_pc_in(bp__update_pc_in)
,       .update_taken_in(bp__update_taken_in)
,       .update_target_in(bp__update_target_in)
    );

    // tmp variables
    logic icache_invalidate_issued_reg_tmp;
    logic[32-1:0] pc_tmp;
    logic valid_tmp;
    logic[32-1:0] alu_result_reg_tmp;
    State[2-1:0] state_reg_tmp;
    logic[2-1:0][32-1:0] predicted_next_reg_tmp;
    logic[2-1:0][32-1:0] fallthrough_reg_tmp;
    logic[2-1:0] predicted_taken_reg_tmp;
    logic[32-1:0] debug_alu_a_reg_tmp;
    logic[32-1:0] debug_alu_b_reg_tmp;
    logic[32-1:0] debug_branch_target_reg_tmp;
    logic debug_branch_taken_reg_tmp;
    logic output_write_active_reg_tmp;
    logic interrupt_entry_guard_reg_tmp;
    logic sbi_ret_a1_valid_reg_tmp;
    logic[32-1:0] sbi_ret_a1_reg_tmp;


    function logic[31:0] sbi_arg_value (input logic[7:0] reg_id);
        if (wb__regs_write_out && (wb__regs_wr_id_out == reg_id)) begin
            return wb__regs_data_out;
        end
        if (reg_id == 'hA) begin
            return regs__x10_out;
        end
        if (reg_id == 'hB) begin
            return regs__x11_out;
        end
        if (reg_id == 'h10) begin
            return regs__x16_out;
        end
        if (reg_id == 'h11) begin
            return regs__x17_out;
        end
        return 'h0;
    endfunction

    always_comb begin : sbi_legacy_ecall_comb_func  // sbi_legacy_ecall_comb_func
        sbi_legacy_ecall_comb=(state_reg['h0].valid && (state_reg['h0].sys_op == Sys_pkg::ECALL)) && (csr__priv_out == unsigned'(2'(unsigned'(2'h1))));
    end

    always_comb begin : sbi_set_timer_comb_func  // sbi_set_timer_comb_func
        logic[31:0] ext;
        ext=sbi_arg_value('h11);
        sbi_set_timer_comb=sbi_legacy_ecall_comb && (((ext == 'h0) || (((ext == SBI_EXT_TIME) && (sbi_arg_value('h10) == 'h0)))));
    end

    always_comb begin : sbi_timer_lo_comb_func  // sbi_timer_lo_comb_func
        sbi_timer_lo_comb=sbi_arg_value('hA);
    end

    always_comb begin : sbi_timer_hi_comb_func  // sbi_timer_hi_comb_func
        sbi_timer_hi_comb=sbi_arg_value('hB);
    end

    always_comb begin : sbi_ecall_debug_comb_func  // sbi_ecall_debug_comb_func
        sbi_ecall_debug_comb=state_reg['h0].valid && (state_reg['h0].sys_op == Sys_pkg::ECALL);
    end

    always_comb begin : sbi_a7_debug_comb_func  // sbi_a7_debug_comb_func
        sbi_a7_debug_comb=sbi_arg_value('h11);
    end

    always_comb begin : sbi_a6_debug_comb_func  // sbi_a6_debug_comb_func
        sbi_a6_debug_comb=sbi_arg_value('h10);
    end

    always_comb begin : sbi_a0_debug_comb_func  // sbi_a0_debug_comb_func
        sbi_a0_debug_comb=sbi_arg_value('hA);
    end

    always_comb begin : sbi_base_comb_func  // sbi_base_comb_func
        sbi_base_comb=sbi_legacy_ecall_comb && (sbi_arg_value('h11) == SBI_EXT_BASE);
    end

    always_comb begin : sbi_noop_comb_func  // sbi_noop_comb_func
        logic[31:0] ext;
        ext=sbi_arg_value('h11);
        sbi_noop_comb=sbi_legacy_ecall_comb && ((((ext == 'h5) || (ext == 'h6)) || (ext == 'h7)));
    end

    always_comb begin : sbi_handled_comb_func  // sbi_handled_comb_func
        sbi_handled_comb=(sbi_set_timer_comb || sbi_noop_comb) || sbi_base_comb;
    end

    always_comb begin : debug_sbi_comb_func  // debug_sbi_comb_func
        debug_sbi_comb.ecall=sbi_ecall_debug_comb;
        debug_sbi_comb.a7=sbi_a7_debug_comb;
        debug_sbi_comb.a6=sbi_a6_debug_comb;
        debug_sbi_comb.a0=sbi_a0_debug_comb;
        debug_sbi_comb.base=sbi_base_comb;
        debug_sbi_comb.noop=sbi_noop_comb;
        debug_sbi_comb.handled=sbi_handled_comb;
    end

    always_comb begin : fetch_valid_comb_func  // fetch_valid_comb_func
        fetch_valid_comb=(valid && icache__read_valid_out) && (icache__read_addr_out == unsigned'(32'(pc)));
    end

    always_comb begin : hazard_stall_comb_func  // hazard_stall_comb_func
        hazard_stall_comb=0;
        if (((fetch_valid_comb && state_reg['h0].valid) && (state_reg['h0].wb_op == Wb_pkg::MEM)) && (state_reg['h0].rd != 'h0)) begin
            if (state_reg['h0].rd == dec__state_out.rs1) begin
                hazard_stall_comb=1;
            end
            if (state_reg['h0].rd == dec__state_out.rs2) begin
                hazard_stall_comb=1;
            end
        end
        if (exe_mem__mem_split_out || exe_mem__mem_split_busy_out) begin
            hazard_stall_comb=1;
        end
    end

    always_comb begin : exe_state_comb_func  // exe_state_comb_func
        exe_state_comb = state_reg['h0];
        if (sbi_handled_comb) begin
            exe_state_comb.sys_op=Sys_pkg::SNONE;
            exe_state_comb.trap_op=Trap_pkg::TNONE;
            exe_state_comb.csr_op=Csr_pkg::CNONE;
            exe_state_comb.mem_op=Mem_pkg::MNONE;
            exe_state_comb.br_op=Br_pkg::BNONE;
            exe_state_comb.alu_op=Alu_pkg::ADD;
            exe_state_comb.rs1_val='h0;
            exe_state_comb.rs2_val='h0;
            exe_state_comb.imm='h0;
            exe_state_comb.rd='hA;
            exe_state_comb.wb_op=Wb_pkg::ALU;
        end
        if ((state_reg['h0].valid && !sbi_handled_comb) && ((((((state_reg['h0].sys_op == Sys_pkg::ECALL) || (state_reg['h0].sys_op == Sys_pkg::EBREAK)) || (state_reg['h0].sys_op == Sys_pkg::TRAP)) || (state_reg['h0].trap_op != Trap_pkg::TNONE)) || csr__illegal_trap_out))) begin
            exe_state_comb.rs1_val=csr__trap_vector_out;
            exe_state_comb.imm='h0;
            exe_state_comb.br_op=Br_pkg::JR;
            exe_state_comb.mem_op=Mem_pkg::MNONE;
            exe_state_comb.wb_op=Wb_pkg::WNONE;
        end
        else begin
            if (state_reg['h0].valid && (((state_reg['h0].sys_op == Sys_pkg::MRET) || (state_reg['h0].sys_op == Sys_pkg::SRET)))) begin
                exe_state_comb.rs1_val=csr__epc_out;
                exe_state_comb.imm='h0;
            end
        end
        if (state_reg['h0].valid && (state_reg['h0].sys_op == Sys_pkg::FENCEI)) begin
            exe_state_comb.rs1_val=state_reg['h0].pc + 'h4;
            exe_state_comb.imm='h0;
        end
        if (wb_mem__load_ready_out && (state_reg['h1].rd != 'h0)) begin
            if (state_reg['h0].rs1 == state_reg['h1].rd) begin
                exe_state_comb.rs1_val=wb_mem__load_result_out;
            end
            if (state_reg['h0].rs2 == state_reg['h1].rd) begin
                exe_state_comb.rs2_val=wb_mem__load_result_out;
            end
        end
    end

    always_comb begin : branch_actual_next_comb_func  // branch_actual_next_comb_func
        branch_actual_next_comb=(exe__branch_taken_out) ? (exe__branch_target_out) : (unsigned'(32'(fallthrough_reg['h0])));
    end

    always_comb begin : branch_mispredict_comb_func  // branch_mispredict_comb_func
        branch_mispredict_comb=(state_reg['h0].valid && (exe_state_comb.br_op != Br_pkg::BNONE)) && (branch_actual_next_comb != unsigned'(32'(predicted_next_reg['h0])));
    end

    always_comb begin : branch_stall_comb_func  // branch_stall_comb_func
        branch_stall_comb=branch_mispredict_comb;
    end

    always_comb begin : perf_comb_func  // perf_comb_func
        perf_comb.hazard_stall=hazard_stall_comb;
        perf_comb.branch_stall=branch_stall_comb;
        perf_comb.dcache_wait=dcache__busy_out;
        perf_comb.icache_wait=icache__busy_out;
        perf_comb.icache = icache__perf_out;
        perf_comb.dcache = dcache__perf_out;
    end

    always_comb begin : memory_wait_comb_func  // memory_wait_comb_func
        logic data_mem_access;
        logic next_data_mem_access;
        logic dmmu_faulted_access;
        data_mem_access=state_reg['h1].valid && ((((exe_mem__mem_read_out || exe_mem__mem_write_out) || (state_reg['h1].mem_op == Mem_pkg::STORE)) || (state_reg['h1].wb_op == Wb_pkg::MEM)));
        next_data_mem_access=state_reg['h0].valid && (((state_reg['h0].mem_op == Mem_pkg::LOAD) || (state_reg['h0].mem_op == Mem_pkg::STORE)));
        dmmu_faulted_access=0;
        memory_wait_comb=(((((((next_data_mem_access && dcache__busy_out)) || (((data_mem_access && !dmmu_faulted_access) && dcache__busy_out))) || (((data_mem_access && !dmmu_faulted_access) && exe_mem__mem_split_busy_out))) || ((((data_mem_access && !dmmu_faulted_access) && dcache__mem_out__read_out) && d_mem_out__wait_in))) || ((((data_mem_access && !dmmu_faulted_access) && ((exe_mem__mem_write_out || (state_reg['h1].mem_op == Mem_pkg::STORE)))) && d_mem_out__wait_in))) || (((state_reg['h0].valid && (state_reg['h0].sys_op == Sys_pkg::FENCE)) && (((dcache__busy_out || d_mem_out__wait_in) || i_mem_out__wait_in))))) || ((((state_reg['h1].valid && (state_reg['h1].wb_op == Wb_pkg::MEM)) && !dmmu_faulted_access) && !wb_mem__load_ready_out));
    end

    always_comb begin : csr_state_comb_func  // csr_state_comb_func
        csr_state_comb = exe_state_comb;
        if (sbi_handled_comb) begin
            csr_state_comb.sys_op=Sys_pkg::SNONE;
            csr_state_comb.trap_op=Trap_pkg::TNONE;
            csr_state_comb.csr_op=Csr_pkg::CNONE;
        end
        if (csr__illegal_trap_out) begin
            csr_state_comb = state_reg['h0];
            csr_state_comb.sys_op=Sys_pkg::TRAP;
            csr_state_comb.trap_op=Trap_pkg::ILLEGAL_INST;
            csr_state_comb.csr_op=Csr_pkg::CNONE;
            csr_state_comb.mem_op=Mem_pkg::MNONE;
            csr_state_comb.wb_op=Wb_pkg::WNONE;
            csr_state_comb.br_op=Br_pkg::JR;
        end
        if (memory_wait_comb) begin
            csr_state_comb.valid=0;
        end
    end

    always_comb begin : stall_comb_func  // stall_comb_func
        stall_comb=hazard_stall_comb || branch_stall_comb;
    end

    always_comb begin : decode_branch_valid_comb_func  // decode_branch_valid_comb_func
        decode_branch_valid_comb=((((fetch_valid_comb && dec__state_out.valid) && (dec__state_out.br_op != Br_pkg::BNONE)) && (dec__state_out.br_op != Br_pkg::JALR)) && (dec__state_out.br_op != Br_pkg::JR)) && !stall_comb;
    end

    always_comb begin : decode_branch_target_comb_func  // decode_branch_target_comb_func
        decode_branch_target_comb='h0;
        if (dec__state_out.br_op == Br_pkg::JAL) begin
            decode_branch_target_comb=dec__state_out.pc + dec__state_out.imm;
        end
        else begin
            if ((dec__state_out.br_op == Br_pkg::JALR) || (dec__state_out.br_op == Br_pkg::JR)) begin
                decode_branch_target_comb=((dec__state_out.rs1_val + dec__state_out.imm)) & ~'h1;
            end
            else begin
                decode_branch_target_comb=dec__state_out.pc + dec__state_out.imm;
            end
        end
    end

    always_comb begin : decode_fallthrough_comb_func  // decode_fallthrough_comb_func
        decode_fallthrough_comb=pc + (((((dec__instr_in & 'h3)) == 'h3)) ? ('h4) : ('h2));
    end

    always_comb begin : fetch_addr_comb_func  // fetch_addr_comb_func
        fetch_addr_comb=pc;
        if (branch_mispredict_comb) begin
            fetch_addr_comb=branch_actual_next_comb;
        end
    end

    always_comb begin : icache_invalidate_comb_func  // icache_invalidate_comb_func
        icache_invalidate_comb=(((state_reg['h0].valid && (state_reg['h0].sys_op == Sys_pkg::FENCEI)) && !memory_wait_comb) && !icache_invalidate_issued_reg);
    end

    always_comb begin : l2_data_addr_comb_func  // l2_data_addr_comb_func
        l2_data_addr_comb=dcache__mem_out__addr_out;
    end

    generate  // _assign
        assign dec__pc_in = pc;
        assign dec__instr_valid_in = fetch_valid_comb;
        assign dec__regs_data0_in = (dec__rs1_out == 'h0) ? ('h0) : (regs__read_data0_out);
        assign dec__regs_data1_in = (dec__rs2_out == 'h0) ? ('h0) : (regs__read_data1_out);
        assign exe__state_in = exe_state_comb;
        assign exe_mem__state_in = exe_state_comb;
        assign exe_mem__alu_result_in = exe__alu_result_out;
        assign exe_mem__transaction_owner_valid_in = state_reg['h1].valid;
        assign exe_mem__hold_in = memory_wait_comb;
        assign wb_mem__state_in = state_reg['h1];
        assign wb_mem__alu_result_in = alu_result_reg;
        assign wb_mem__split_load_in = exe_mem__split_load_out;
        assign wb_mem__split_load_low_addr_in = exe_mem__split_load_low_out;
        assign wb_mem__split_load_high_addr_in = exe_mem__split_load_high_out;
        assign wb_mem__store_forward_enable_in = unsigned'(32'(wb_mem__alu_result_in)) < (((memory_base_in + mem_region_size_in['h0]) + mem_region_size_in['h1]) + mem_region_size_in['h2]);
        assign wb_mem__hold_in = memory_wait_comb;
        assign csr__state_in = csr_state_comb;
        assign csr__trap_check_state_in = state_reg['h0];
        assign csr__reset_priv_in = boot_priv_in;
        assign csr__hartid_in = boot_hartid_in;
        assign csr__time_lo_in = unsigned'(32'('h0));
        assign csr__time_hi_in = unsigned'(32'('h0));
        assign csr__interrupt_valid_in = 0;
        assign csr__interrupt_cause_in = unsigned'(32'('h0));
        assign csr__interrupt_to_supervisor_in = 0;
        assign csr__irq_pending_bits_in = unsigned'(32'('h0));
        assign wb__state_in = state_reg['h1];
        assign wb__mem_data_in = wb_mem__load_raw_out;
        assign wb__mem_data_hi_in = unsigned'(32'('h0));
        assign wb__mem_addr_in = alu_result_reg;
        assign wb__mem_split_in = 0;
        assign wb__alu_result_in = alu_result_reg;
        assign regs__read_addr0_in = unsigned'(8'(dec__rs1_out));
        assign regs__read_addr1_in = unsigned'(8'(dec__rs2_out));
        assign regs__write_in = (wb__regs_write_out && !memory_wait_comb) && (((state_reg['h1].wb_op != Wb_pkg::MEM) || wb_mem__load_ready_out));
        assign regs__write_addr_in = wb__regs_wr_id_out;
        assign regs__write_data_in = wb__regs_data_out;
        assign regs__write2_in = sbi_ret_a1_valid_reg;
        assign regs__write2_addr_in = unsigned'(8'('hB));
        assign regs__write2_data_in = unsigned'(32'(sbi_ret_a1_reg));
        assign regs__reset_x10_in = boot_hartid_in;
        assign regs__reset_x11_in = boot_dtb_addr_in;
        assign regs__debugen_in=debugen_in;
        assign dcache__read_in = (state_reg['h1].valid && exe_mem__mem_read_out) && !dcache__busy_out;
        assign dcache__write_in = (state_reg['h1].valid && exe_mem__mem_write_out) && !dcache__busy_out;
        assign dcache__addr_in = (exe_mem__mem_read_out) ? (unsigned'(32'(exe_mem__mem_read_addr_out))) : (unsigned'(32'(exe_mem__mem_write_addr_out)));
        assign dcache__write_data_in = exe_mem__mem_write_data_out;
        assign dcache__write_mask_in = exe_mem__mem_write_mask_out;
        assign dcache__stall_in = branch_stall_comb;
        assign dcache__flush_in = 0;
        assign dcache__invalidate_in = external_cache_invalidate_in;
        assign dcache__invalidate_line_in = peer_cache_invalidate_in;
        assign dcache__invalidate_addr_in = peer_cache_invalidate_addr_in;
        assign dcache__cache_disable_in = dcache__addr_in>=(((memory_base_in + mem_region_size_in['h0]) + mem_region_size_in['h1]) + mem_region_size_in['h2]) && (unsigned'(32'(dcache__addr_in)) < (memory_base_in + memory_size_in));
        assign dcache__debugen_in=debugen_in;
        assign exe_mem__mem_stall_in = dcache__busy_out;
        assign wb_mem__dcache_read_valid_in = dcache__read_valid_out;
        assign wb_mem__dcache_read_addr_in = dcache__read_addr_out;
        assign wb_mem__dcache_read_data_in = dcache__read_data_out;
        assign wb_mem__dcache_write_valid_in = dcache__mem_out__write_out;
        assign wb_mem__dcache_write_addr_in = dcache__mem_out__addr_out;
        assign wb_mem__dcache_write_data_in = dcache__mem_out__write_data_out;
        assign wb_mem__dcache_write_mask_in = dcache__mem_out__write_mask_out;
        assign bp__lookup_valid_in = decode_branch_valid_comb;
        assign bp__lookup_pc_in = unsigned'(32'(dec__state_out.pc));
        assign bp__lookup_target_in = decode_branch_target_comb;
        assign bp__lookup_fallthrough_in = decode_fallthrough_comb;
        assign bp__lookup_br_op_in = unsigned'(4'(unsigned'(4'(dec__state_out.br_op))));
        assign bp__update_valid_in = (state_reg['h0].valid && (state_reg['h0].br_op != Br_pkg::BNONE)) && !memory_wait_comb;
        assign bp__update_pc_in = unsigned'(32'(state_reg['h0].pc));
        assign bp__update_taken_in = exe__branch_taken_out;
        assign bp__update_target_in = exe__branch_target_out;
        assign icache__read_in = valid;
        assign icache__addr_in = fetch_addr_comb;
        assign icache__write_in = 0;
        assign icache__write_data_in = unsigned'(32'('h0));
        assign icache__write_mask_in = unsigned'(8'('h0));
        assign icache__stall_in = memory_wait_comb || stall_comb;
        assign icache__flush_in = branch_mispredict_comb && !memory_wait_comb;
        assign icache__invalidate_in = icache_invalidate_comb;
        assign icache__cache_disable_in = 0;
        assign icache__debugen_in=debugen_in;
        assign dec__instr_in = icache__read_data_out;
        assign i_mem_out__read_out = icache__mem_out__read_out;
        assign i_mem_out__write_out = 0;
        assign i_mem_out__addr_out = icache__mem_out__addr_out;
        assign i_mem_out__write_data_out = unsigned'(32'('h0));
        assign i_mem_out__write_mask_out = unsigned'(8'('h0));
        assign i_mem_out__cache_disable_out = 0;
        assign d_mem_out__read_out = dcache__mem_out__read_out;
        assign d_mem_out__write_out = dcache__mem_out__write_out;
        assign d_mem_out__addr_out = l2_data_addr_comb;
        assign d_mem_out__write_data_out = dcache__mem_out__write_data_out;
        assign d_mem_out__write_mask_out = dcache__mem_out__write_mask_out;
        assign d_mem_out__cache_disable_out = l2_data_addr_comb>=(((memory_base_in + mem_region_size_in['h0]) + mem_region_size_in['h1]) + mem_region_size_in['h2]) && (l2_data_addr_comb < (memory_base_in + memory_size_in));
        assign dcache__mem_out__read_data_in = d_mem_out__read_data_in;
        assign dcache__mem_out__wait_in = d_mem_out__wait_in;
        assign icache__mem_out__read_data_in = i_mem_out__read_data_in;
        assign icache__mem_out__wait_in = i_mem_out__wait_in;
        assign dmem_write_out = dcache__mem_out__write_out;
        assign dmem_write_data_out = dcache__mem_out__write_data_out;
        assign dmem_write_mask_out = dcache__mem_out__write_mask_out;
        assign dmem_read_out = dcache__mem_out__read_out;
        assign dmem_addr_out = dcache__mem_out__addr_out;
        assign imem_read_addr_out = icache__mem_out__addr_out;
    endgenerate

    always_comb begin : branch_flush_comb_func  // branch_flush_comb_func
        branch_flush_comb=branch_mispredict_comb;
    end

    always_comb begin : decode_indirect_branch_valid_comb_func  // decode_indirect_branch_valid_comb_func
        decode_indirect_branch_valid_comb=((fetch_valid_comb && dec__state_out.valid) && (((dec__state_out.br_op == Br_pkg::JALR) || (dec__state_out.br_op == Br_pkg::JR)))) && !stall_comb;
    end

    always_comb begin : sbi_ret_value_comb_func  // sbi_ret_value_comb_func
        logic[31:0] fid;
        logic[31:0] ext;
        logic[31:0] probe_ext;
        fid=sbi_arg_value('h10);
        ext=sbi_arg_value('h11);
        probe_ext=sbi_arg_value('hA);
        sbi_ret_value_comb='h0;
        if (ext == SBI_EXT_BASE) begin
            if (fid == 'h0) begin
                sbi_ret_value_comb='h2;
            end
            else begin
                if (fid == 'h1) begin
                    sbi_ret_value_comb='h0;
                end
                else begin
                    if (fid == 'h2) begin
                        sbi_ret_value_comb='h1;
                    end
                    else begin
                        if (fid == 'h3) begin
                            sbi_ret_value_comb=((((probe_ext == SBI_EXT_BASE) || (probe_ext == SBI_EXT_TIME)) || (probe_ext == SBI_EXT_RFENCE))) ? ('h1) : ('h0);
                        end
                        else begin
                            sbi_ret_value_comb='h0;
                        end
                    end
                end
            end
        end
    end

    always_comb begin : sbi_writes_a1_comb_func  // sbi_writes_a1_comb_func
        sbi_writes_a1_comb=sbi_base_comb || sbi_set_timer_comb;
    end

    always_comb begin : interrupt_accept_comb_func  // interrupt_accept_comb_func
        interrupt_accept_comb=0;
    end

    always_comb begin : sfence_vma_comb_func  // sfence_vma_comb_func
        sfence_vma_comb=((state_reg['h0].valid && (state_reg['h0].sys_op == Sys_pkg::SFENCE_VMA)) && !memory_wait_comb);
    end

    task forward ();
    begin: forward
        if ((state_reg['h1].valid && (state_reg['h1].wb_op == Wb_pkg::ALU)) && (state_reg['h1].rd != 'h0)) begin
            if (dec__state_out.rs1 == state_reg['h1].rd) begin
                state_reg_tmp['h0].rs1_val=alu_result_reg;
                if (debugen_in) begin
                    $write("forwarding %.08x from ALU to RS1\n", unsigned'(32'(alu_result_reg)));
                end
            end
            if (dec__state_out.rs2 == state_reg['h1].rd) begin
                state_reg_tmp['h0].rs2_val=alu_result_reg;
                if (debugen_in) begin
                    $write("forwarding %.08x from ALU to RS2\n", unsigned'(32'(alu_result_reg)));
                end
            end
        end
        if (wb_mem__load_ready_out && (state_reg['h1].rd != 'h0)) begin
            if (dec__state_out.rs1 == state_reg['h1].rd) begin
                state_reg_tmp['h0].rs1_val=wb_mem__load_result_out;
                if (debugen_in) begin
                    $write("forwarding %.08x from MEM to RS1\n", unsigned'(32'(wb_mem__load_result_out)));
                end
            end
            if (dec__state_out.rs2 == state_reg['h1].rd) begin
                state_reg_tmp['h0].rs2_val=wb_mem__load_result_out;
                if (debugen_in) begin
                    $write("forwarding %.08x from MEM to RS2\n", unsigned'(32'(wb_mem__load_result_out)));
                end
            end
        end
        if ((state_reg['h1].valid && (((state_reg['h1].wb_op == Wb_pkg::PC2) || (state_reg['h1].wb_op == Wb_pkg::PC4)))) && (state_reg['h1].rd != 'h0)) begin
            logic[31:0] link_value; link_value = state_reg['h1].pc + (((state_reg['h1].wb_op == Wb_pkg::PC2)) ? ('h2) : ('h4));
            if (dec__state_out.rs1 == state_reg['h1].rd) begin
                state_reg_tmp['h0].rs1_val=link_value;
                if (debugen_in) begin
                    $write("forwarding %.08x from LINK to RS1\n", link_value);
                end
            end
            if (dec__state_out.rs2 == state_reg['h1].rd) begin
                state_reg_tmp['h0].rs2_val=link_value;
                if (debugen_in) begin
                    $write("forwarding %.08x from LINK to RS2\n", link_value);
                end
            end
        end
        if ((state_reg['h0].valid && (state_reg['h0].wb_op == Wb_pkg::ALU)) && (state_reg['h0].rd != 'h0)) begin
            if (dec__state_out.rs1 == state_reg['h0].rd) begin
                state_reg_tmp['h0].rs1_val=exe__alu_result_out;
                if (debugen_in) begin
                    $write("forwarding %.08x from ALU to RS1\n", unsigned'(32'(exe__alu_result_out)));
                end
            end
            if (dec__state_out.rs2 == state_reg['h0].rd) begin
                state_reg_tmp['h0].rs2_val=exe__alu_result_out;
                if (debugen_in) begin
                    $write("forwarding %.08x from ALU to RS2\n", unsigned'(32'(exe__alu_result_out)));
                end
            end
        end
        if ((state_reg['h0].valid && (((state_reg['h0].wb_op == Wb_pkg::PC2) || (state_reg['h0].wb_op == Wb_pkg::PC4)))) && (state_reg['h0].rd != 'h0)) begin
            logic[31:0] link_value; link_value = state_reg['h0].pc + (((state_reg['h0].wb_op == Wb_pkg::PC2)) ? ('h2) : ('h4));
            if (dec__state_out.rs1 == state_reg['h0].rd) begin
                state_reg_tmp['h0].rs1_val=link_value;
                if (debugen_in) begin
                    $write("forwarding %.08x from LINK to RS1\n", link_value);
                end
            end
            if (dec__state_out.rs2 == state_reg['h0].rd) begin
                state_reg_tmp['h0].rs2_val=link_value;
                if (debugen_in) begin
                    $write("forwarding %.08x from LINK to RS2\n", link_value);
                end
            end
        end
    end
    endtask

    function logic signed[31:0] Rv32i___sext (
        input Rv32i _this
,       input logic[31:0] val
,       input logic[31:0] bits
    );
        logic signed[31:0] m;
        m = 'h1 <<< ((bits - 'h1));
        return ((val ^ m)) - m;
    endfunction

    function logic signed[31:0] Rv32i___imm_I (input Rv32i _this);
        return Rv32i___sext(_this, _this._.i.imm11_0, 'hC);
    endfunction

    function logic signed[31:0] Rv32i___imm_S (input Rv32i _this);
        return Rv32i___sext(_this, _this._.s.imm4_0 | ((_this._.s.imm11_5 <<< 'h5)), 'hC);
    endfunction

    function logic signed[31:0] Rv32i___imm_B (input Rv32i _this);
        return Rv32i___sext(_this, ((((_this._.b.imm4_1 <<< 'h1)) | ((_this._.b.imm11 <<< 'hB))) | ((_this._.b.imm10_5 <<< 'h5))) | ((_this._.b.imm12 <<< 'hC)), 'hD);
    endfunction

    function logic signed[31:0] Rv32i___imm_J (input Rv32i _this);
        return Rv32i___sext(_this, ((((_this._.j.imm10_1 <<< 'h1)) | ((_this._.j.imm11 <<< 'hB))) | ((_this._.j.imm19_12 <<< 'hC))) | ((_this._.j.imm20 <<< 'h14)), 'h15);
    endfunction

    function logic signed[31:0] Rv32i___imm_U (input Rv32i _this);
        return signed'(32'(_this._.u.imm31_12 <<< 'hC));
    endfunction

    task Rv32i___decode (
        input Rv32i _this
,       output State state_out
    );
    begin: Rv32i___decode
        state_out = 0;
        if (_this._.r.opcode == 'h3) begin
            state_out.rd=_this._.i.rd;
            state_out.imm=Rv32i___imm_I(_this);
            state_out.mem_op=Mem_pkg::LOAD;
            state_out.alu_op=Alu_pkg::ADD;
            state_out.wb_op=Wb_pkg::MEM;
            state_out.funct3=_this._.i.funct3;
            state_out.rs1=_this._.i.rs1;
        end
        else begin
            if (_this._.r.opcode == 'h23) begin
                state_out.imm=Rv32i___imm_S(_this);
                state_out.mem_op=Mem_pkg::STORE;
                state_out.alu_op=Alu_pkg::ADD;
                state_out.funct3=_this._.s.funct3;
                state_out.rs1=_this._.s.rs1;
                state_out.rs2=_this._.s.rs2;
            end
            else begin
                if (_this._.r.opcode == 'h13) begin
                    state_out.rd=_this._.i.rd;
                    state_out.imm=Rv32i___imm_I(_this);
                    state_out.wb_op=Wb_pkg::ALU;
                    case (_this._.i.funct3)
                    'h0: begin
                        state_out.alu_op=Alu_pkg::ADD;
                    end
                    'h2: begin
                        state_out.alu_op=Alu_pkg::SLT;
                    end
                    'h3: begin
                        state_out.alu_op=Alu_pkg::SLTU;
                    end
                    'h4: begin
                        state_out.alu_op=Alu_pkg::XOR;
                    end
                    'h6: begin
                        state_out.alu_op=Alu_pkg::OR;
                    end
                    'h7: begin
                        state_out.alu_op=Alu_pkg::AND;
                    end
                    'h1: begin
                        state_out.alu_op=Alu_pkg::SLL;
                    end
                    'h5: begin
                        state_out.alu_op=(((_this._.i.imm11_0 >>> 'hA)) & 'h1) ? (Alu_pkg::SRA) : (Alu_pkg::SRL);
                    end
                    endcase
                    state_out.funct3=_this._.i.funct3;
                    state_out.rs1=_this._.i.rs1;
                end
                else begin
                    if (_this._.r.opcode == 'h33) begin
                        state_out.rd=_this._.r.rd;
                        state_out.wb_op=Wb_pkg::ALU;
                        case (_this._.r.funct3)
                        'h0: begin
                            state_out.alu_op=((_this._.r.funct7 == 'h20)) ? (Alu_pkg::SUB) : (Alu_pkg::ADD);
                        end
                        'h7: begin
                            state_out.alu_op=((_this._.r.funct7 == 'h1)) ? (Alu_pkg::REM) : (Alu_pkg::AND);
                        end
                        'h6: begin
                            state_out.alu_op=Alu_pkg::OR;
                        end
                        'h4: begin
                            state_out.alu_op=Alu_pkg::XOR;
                        end
                        'h1: begin
                            state_out.alu_op=Alu_pkg::SLL;
                        end
                        'h5: begin
                            state_out.alu_op=((_this._.r.funct7 == 'h20)) ? (Alu_pkg::SRA) : (Alu_pkg::SRL);
                        end
                        'h2: begin
                            state_out.alu_op=Alu_pkg::SLT;
                        end
                        'h3: begin
                            state_out.alu_op=Alu_pkg::SLTU;
                        end
                        endcase
                        state_out.funct3=_this._.r.funct3;
                        state_out.rs1=_this._.r.rs1;
                        state_out.rs2=_this._.r.rs2;
                    end
                    else begin
                        if (_this._.r.opcode == 'h63) begin
                            state_out.imm=Rv32i___imm_B(_this);
                            state_out.br_op=Br_pkg::BNONE;
                            case (_this._.b.funct3)
                            'h0: begin
                                state_out.br_op=Br_pkg::BEQ;
                                state_out.alu_op=Alu_pkg::SLTU;
                            end
                            'h1: begin
                                state_out.br_op=Br_pkg::BNE;
                                state_out.alu_op=Alu_pkg::SLTU;
                            end
                            'h4: begin
                                state_out.br_op=Br_pkg::BLT;
                                state_out.alu_op=Alu_pkg::SLT;
                            end
                            'h5: begin
                                state_out.br_op=Br_pkg::BGE;
                                state_out.alu_op=Alu_pkg::SLT;
                            end
                            'h6: begin
                                state_out.br_op=Br_pkg::BLTU;
                                state_out.alu_op=Alu_pkg::SLTU;
                            end
                            'h7: begin
                                state_out.br_op=Br_pkg::BGEU;
                                state_out.alu_op=Alu_pkg::SLTU;
                            end
                            endcase
                            state_out.funct3=_this._.b.funct3;
                            state_out.rs1=_this._.b.rs1;
                            state_out.rs2=_this._.b.rs2;
                        end
                        else begin
                            if (_this._.r.opcode == 'h6F) begin
                                state_out.rd=_this._.j.rd;
                                state_out.imm=Rv32i___imm_J(_this);
                                state_out.br_op=Br_pkg::JAL;
                                state_out.wb_op=Wb_pkg::PC4;
                            end
                            else begin
                                if (_this._.r.opcode == 'h67) begin
                                    state_out.rd=_this._.i.rd;
                                    state_out.imm=Rv32i___imm_I(_this);
                                    state_out.br_op=Br_pkg::JALR;
                                    state_out.wb_op=Wb_pkg::PC4;
                                    state_out.rs1=_this._.i.rs1;
                                end
                                else begin
                                    if (_this._.r.opcode == 'h37) begin
                                        state_out.rd=_this._.u.rd;
                                        state_out.imm=Rv32i___imm_U(_this);
                                        state_out.alu_op=Alu_pkg::PASS;
                                        state_out.wb_op=Wb_pkg::ALU;
                                    end
                                    else begin
                                        if (_this._.r.opcode == 'h17) begin
                                            state_out.rd=_this._.u.rd;
                                            state_out.imm=Rv32i___imm_U(_this);
                                            state_out.alu_op=Alu_pkg::ADD;
                                            state_out.wb_op=Wb_pkg::ALU;
                                        end
                                        else begin
                                            if (_this._.r.opcode == 'hF) begin
                                                if (_this._.i.funct3 == 'h1) begin
                                                    state_out.sys_op=Sys_pkg::FENCEI;
                                                    state_out.br_op=Br_pkg::BNONE;
                                                end
                                                else begin
                                                    if (_this._.i.funct3 == 'h0) begin
                                                        state_out.sys_op=Sys_pkg::FENCE;
                                                        state_out.br_op=Br_pkg::BNONE;
                                                    end
                                                    else begin
                                                        state_out.sys_op=Sys_pkg::TRAP;
                                                        state_out.trap_op=Trap_pkg::ILLEGAL_INST;
                                                        state_out.imm=_this._.raw;
                                                        state_out.br_op=Br_pkg::BNONE;
                                                    end
                                                end
                                            end
                                            else begin
                                                state_out.sys_op=Sys_pkg::TRAP;
                                                state_out.trap_op=Trap_pkg::ILLEGAL_INST;
                                                state_out.imm=_this._.raw;
                                                state_out.br_op=Br_pkg::BNONE;
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    endtask

    function logic[31:0] Rv32ic___bits (
        input Rv32ic _this
,       input logic signed[31:0] hi
,       input logic signed[31:0] lo
    );
        return ((_this._.raw >>> lo)) & (((('h1 <<< (((hi - lo) + 'h1)))) - 'h1));
    endfunction

    function logic[31:0] Rv32ic___bit (
        input Rv32ic _this
,       input logic signed[31:0] lo
    );
        return ((_this._.raw >>> lo)) & 'h1;
    endfunction

    task Rv32ic___decode (
        input Rv32ic _this
,       output State state_out
    );
    begin: Rv32ic___decode
        logic signed[31:0] imm_tmp;
        logic[31:0] opcode;
        logic[31:0] funct3;
        logic[31:0] rd_p;
        logic[31:0] rs1_p;
        logic[31:0] bits6_5;
        logic[31:0] bits11_10;
        logic[31:0] b12;
        logic[31:0] rd_rs1;
        logic[31:0] rs2;
        state_out = 0;
        if (((_this._.raw & 'h3)) == 'h3) begin
            Rv32i___decode(_this, state_out);
            disable Rv32ic___decode;
        end
        opcode=Rv32ic___bits(_this, 'h1, 'h0);
        funct3=Rv32ic___bits(_this, 'hF, 'hD);
        rd_p=Rv32ic___bits(_this, 'h4, 'h2);
        rs1_p=Rv32ic___bits(_this, 'h9, 'h7);
        bits6_5=Rv32ic___bits(_this, 'h6, 'h5);
        bits11_10=Rv32ic___bits(_this, 'hB, 'hA);
        b12=Rv32ic___bit(_this, 'hC);
        rd_rs1=Rv32ic___bits(_this, 'hB, 'h7);
        rs2=Rv32ic___bits(_this, 'h6, 'h2);
        state_out.funct3='h2;
        if (opcode == 'h0) begin
            if (funct3 == 'h0) begin
                state_out.rd=rd_p + 'h8;
                state_out.rs1='h2;
                state_out.imm=((((Rv32ic___bits(_this, 'hA, 'h7) <<< 'h6)) | ((Rv32ic___bits(_this, 'hC, 'hB) <<< 'h4))) | ((Rv32ic___bit(_this, 'h5) <<< 'h3))) | ((Rv32ic___bit(_this, 'h6) <<< 'h2));
                state_out.alu_op=Alu_pkg::ADD;
                state_out.wb_op=Wb_pkg::ALU;
            end
            else begin
                if (funct3 == 'h2) begin
                    state_out.rd=rd_p + 'h8;
                    state_out.rs1=rs1_p + 'h8;
                    state_out.imm=(((Rv32ic___bit(_this, 'h5) <<< 'h6)) | ((Rv32ic___bits(_this, 'hC, 'hA) <<< 'h3))) | ((Rv32ic___bit(_this, 'h6) <<< 'h2));
                    state_out.alu_op=Alu_pkg::ADD;
                    state_out.mem_op=Mem_pkg::LOAD;
                    state_out.wb_op=Wb_pkg::MEM;
                end
                else begin
                    if (funct3 == 'h6) begin
                        state_out.rs1=rs1_p + 'h8;
                        state_out.rs2=rd_p + 'h8;
                        state_out.imm=(((Rv32ic___bit(_this, 'h5) <<< 'h6)) | ((Rv32ic___bits(_this, 'hC, 'hA) <<< 'h3))) | ((Rv32ic___bit(_this, 'h6) <<< 'h2));
                        state_out.alu_op=Alu_pkg::ADD;
                        state_out.mem_op=Mem_pkg::STORE;
                    end
                end
            end
        end
        else begin
            if (opcode == 'h1) begin
                if (funct3 == 'h0) begin
                    state_out.rd=rd_rs1;
                    state_out.rs1=rd_rs1;
                    imm_tmp=((Rv32ic___bit(_this, 'hC) <<< 'h5)) | Rv32ic___bits(_this, 'h6, 'h2);
                    imm_tmp=((imm_tmp <<< 'h1A)) >>> 'h1A;
                    state_out.imm=imm_tmp;
                    state_out.alu_op=Alu_pkg::ADD;
                    state_out.wb_op=Wb_pkg::ALU;
                end
                else begin
                    if (funct3 == 'h1) begin
                        state_out.rd='h1;
                        state_out.wb_op=Wb_pkg::PC2;
                        state_out.br_op=Br_pkg::JAL;
                        state_out.imm=Rv32i___sext(_this, ((((((((b12 <<< 'hB)) | ((Rv32ic___bit(_this, 'h8) <<< 'hA))) | ((Rv32ic___bits(_this, 'hA, 'h9) <<< 'h8))) | ((Rv32ic___bit(_this, 'h6) <<< 'h7))) | ((Rv32ic___bit(_this, 'h7) <<< 'h6))) | ((Rv32ic___bit(_this, 'h2) <<< 'h5))) | ((Rv32ic___bit(_this, 'hB) <<< 'h4))) | ((Rv32ic___bits(_this, 'h5, 'h3) <<< 'h1)), 'hC);
                    end
                    else begin
                        if (funct3 == 'h2) begin
                            state_out.rd=rd_rs1;
                            imm_tmp=((Rv32ic___bit(_this, 'hC) <<< 'h5)) | Rv32ic___bits(_this, 'h6, 'h2);
                            imm_tmp=((imm_tmp <<< 'h1A)) >>> 'h1A;
                            state_out.imm=imm_tmp;
                            state_out.alu_op=Alu_pkg::PASS;
                            state_out.wb_op=Wb_pkg::ALU;
                        end
                        else begin
                            if (funct3 == 'h3) begin
                                if (rd_rs1 == 'h2) begin
                                    state_out.rd='h2;
                                    state_out.rs1='h2;
                                    imm_tmp=((((((Rv32ic___bit(_this, 'hC) <<< 'h9)) | ((Rv32ic___bit(_this, 'h4) <<< 'h8))) | ((Rv32ic___bit(_this, 'h3) <<< 'h7))) | ((Rv32ic___bit(_this, 'h5) <<< 'h6))) | ((Rv32ic___bit(_this, 'h2) <<< 'h5))) | ((Rv32ic___bit(_this, 'h6) <<< 'h4));
                                    state_out.imm=Rv32i___sext(_this, imm_tmp, 'hA);
                                    state_out.alu_op=Alu_pkg::ADD;
                                    state_out.wb_op=Wb_pkg::ALU;
                                end
                                else begin
                                    state_out.rd=rd_rs1;
                                    imm_tmp=((Rv32ic___bit(_this, 'hC) <<< 'h5)) | Rv32ic___bits(_this, 'h6, 'h2);
                                    imm_tmp=((imm_tmp <<< 'h1A)) >>> 'hE;
                                    state_out.imm=imm_tmp;
                                    state_out.alu_op=Alu_pkg::PASS;
                                    state_out.wb_op=Wb_pkg::ALU;
                                end
                            end
                            else begin
                                if (funct3 == 'h4) begin
                                    if (bits11_10 == 'h0) begin
                                        state_out.rd=rs1_p + 'h8;
                                        state_out.rs1=rs1_p + 'h8;
                                        state_out.imm=Rv32ic___bits(_this, 'h6, 'h2);
                                        state_out.alu_op=Alu_pkg::SRL;
                                        state_out.wb_op=Wb_pkg::ALU;
                                    end
                                    else begin
                                        if (bits11_10 == 'h1) begin
                                            state_out.rd=rs1_p + 'h8;
                                            state_out.rs1=rs1_p + 'h8;
                                            state_out.imm=Rv32ic___bits(_this, 'h6, 'h2);
                                            state_out.alu_op=Alu_pkg::SRA;
                                            state_out.wb_op=Wb_pkg::ALU;
                                        end
                                        else begin
                                            if (bits11_10 == 'h2) begin
                                                state_out.rd=rs1_p + 'h8;
                                                state_out.rs1=rs1_p + 'h8;
                                                imm_tmp=((Rv32ic___bit(_this, 'hC) <<< 'h5)) | Rv32ic___bits(_this, 'h6, 'h2);
                                                imm_tmp=((imm_tmp <<< 'h1A)) >>> 'h1A;
                                                state_out.imm=imm_tmp;
                                                state_out.alu_op=Alu_pkg::AND;
                                                state_out.wb_op=Wb_pkg::ALU;
                                            end
                                            else begin
                                                if ((bits11_10 == 'h3) && (b12 == 'h0)) begin
                                                    state_out.rd=rs1_p + 'h8;
                                                    state_out.rs1=rs1_p + 'h8;
                                                    state_out.rs2=rd_p + 'h8;
                                                    state_out.alu_op=(bits6_5 == 'h0) ? (Alu_pkg::SUB) : (((bits6_5 == 'h1) ? (Alu_pkg::XOR) : (((bits6_5 == 'h2) ? (Alu_pkg::OR) : (Alu_pkg::AND)))));
                                                    state_out.wb_op=Wb_pkg::ALU;
                                                end
                                            end
                                        end
                                    end
                                end
                                else begin
                                    if (funct3 == 'h5) begin
                                        state_out.rd='h0;
                                        state_out.br_op=Br_pkg::JAL;
                                        state_out.imm=Rv32i___sext(_this, ((((((((b12 <<< 'hB)) | ((Rv32ic___bit(_this, 'h8) <<< 'hA))) | ((Rv32ic___bits(_this, 'hA, 'h9) <<< 'h8))) | ((Rv32ic___bit(_this, 'h6) <<< 'h7))) | ((Rv32ic___bit(_this, 'h7) <<< 'h6))) | ((Rv32ic___bit(_this, 'h2) <<< 'h5))) | ((Rv32ic___bit(_this, 'hB) <<< 'h4))) | ((Rv32ic___bits(_this, 'h5, 'h3) <<< 'h1)), 'hC);
                                    end
                                    else begin
                                        if (funct3 == 'h6) begin
                                            state_out.rs1=rs1_p + 'h8;
                                            state_out.br_op=Br_pkg::BEQZ;
                                            state_out.alu_op=Alu_pkg::SLTU;
                                            state_out.imm=(((((b12 <<< 'h8)) | ((Rv32ic___bits(_this, 'h6, 'h5) <<< 'h6))) | ((Rv32ic___bit(_this, 'h2) <<< 'h5))) | ((Rv32ic___bits(_this, 'hB, 'hA) <<< 'h3))) | ((Rv32ic___bits(_this, 'h4, 'h3) <<< 'h1));
                                            if (b12) begin
                                                state_out.imm|=~'h1FF;
                                            end
                                        end
                                        else begin
                                            if (funct3 == 'h7) begin
                                                state_out.rs1=rs1_p + 'h8;
                                                state_out.br_op=Br_pkg::BNEZ;
                                                state_out.alu_op=Alu_pkg::SLTU;
                                                state_out.imm=(((((b12 <<< 'h8)) | ((Rv32ic___bits(_this, 'h6, 'h5) <<< 'h6))) | ((Rv32ic___bit(_this, 'h2) <<< 'h5))) | ((Rv32ic___bits(_this, 'hB, 'hA) <<< 'h3))) | ((Rv32ic___bits(_this, 'h4, 'h3) <<< 'h1));
                                                if (b12) begin
                                                    state_out.imm|=~'h1FF;
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            else begin
                if (opcode == 'h2) begin
                    if (funct3 == 'h0) begin
                        state_out.rd=rd_rs1;
                        state_out.rs1=rd_rs1;
                        state_out.imm=((b12 <<< 'h5)) | Rv32ic___bits(_this, 'h6, 'h2);
                        state_out.alu_op=Alu_pkg::SLL;
                        state_out.wb_op=Wb_pkg::ALU;
                    end
                    else begin
                        if (funct3 == 'h2) begin
                            state_out.rd=rd_rs1;
                            state_out.rs1='h2;
                            state_out.imm=(((b12 <<< 'h5)) | ((Rv32ic___bits(_this, 'h6, 'h4) <<< 'h2))) | ((Rv32ic___bits(_this, 'h3, 'h2) <<< 'h6));
                            state_out.alu_op=Alu_pkg::ADD;
                            state_out.mem_op=Mem_pkg::LOAD;
                            state_out.wb_op=Wb_pkg::MEM;
                        end
                        else begin
                            if (funct3 == 'h4) begin
                                if (((rs2 == 'h0) && (rd_rs1 == 'h0)) && (b12 == 'h1)) begin
                                    state_out.sys_op=Sys_pkg::EBREAK;
                                    state_out.trap_op=Trap_pkg::BREAKPOINT;
                                end
                                else begin
                                    if (rs2 != 'h0) begin
                                        state_out.rd=rd_rs1;
                                        state_out.rs2=rs2;
                                        if (b12 == 'h0) begin
                                            state_out.alu_op=Alu_pkg::PASS;
                                        end
                                        else begin
                                            state_out.rs1=rd_rs1;
                                            state_out.alu_op=Alu_pkg::ADD;
                                        end
                                        state_out.wb_op=Wb_pkg::ALU;
                                    end
                                    else begin
                                        if ((rs2 == 'h0) && (b12 == 'h0)) begin
                                            state_out.rs1=rd_rs1;
                                            state_out.br_op=Br_pkg::JR;
                                            state_out.wb_op=Wb_pkg::PC2;
                                        end
                                        else begin
                                            if ((rs2 == 'h0) && (b12 == 'h1)) begin
                                                state_out.rs1=rd_rs1;
                                                state_out.rd='h1;
                                                state_out.br_op=Br_pkg::JALR;
                                                state_out.wb_op=Wb_pkg::PC2;
                                            end
                                        end
                                    end
                                end
                            end
                            else begin
                                if (funct3 == 'h6) begin
                                    state_out.rs1='h2;
                                    state_out.rs2=rs2;
                                    state_out.imm=((Rv32ic___bits(_this, 'h8, 'h7) <<< 'h6)) | ((Rv32ic___bits(_this, 'hC, 'h9) <<< 'h2));
                                    state_out.mem_op=Mem_pkg::STORE;
                                    state_out.alu_op=Alu_pkg::ADD;
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    endtask

    task Rv32im___decode (
        input Rv32im _this
,       output State state_out
    );
    begin: Rv32im___decode
        state_out = 0;
        Rv32ic___decode(_this, state_out);
        if ((_this._.r.opcode == 'h33) && (_this._.r.funct7 == 'h1)) begin
            state_out = 0;
            state_out.rd=_this._.r.rd;
            state_out.wb_op=Wb_pkg::ALU;
            case (_this._.r.funct3)
            'h0: begin
                state_out.alu_op=Alu_pkg::MUL;
            end
            'h1: begin
                state_out.alu_op=Alu_pkg::MULH;
            end
            'h2: begin
                state_out.alu_op=Alu_pkg::MULHSU;
            end
            'h3: begin
                state_out.alu_op=Alu_pkg::MULHU;
            end
            'h4: begin
                state_out.alu_op=Alu_pkg::DIV;
            end
            'h5: begin
                state_out.alu_op=Alu_pkg::DIVU;
            end
            'h6: begin
                state_out.alu_op=Alu_pkg::REM;
            end
            'h7: begin
                state_out.alu_op=Alu_pkg::REMU;
            end
            endcase
            state_out.funct3=_this._.r.funct3;
            state_out.rs1=_this._.r.rs1;
            state_out.rs2=_this._.r.rs2;
        end
    end
    endtask

    task Zicsr___decode (
        input Zicsr _this
,       output State state_out
    );
    begin: Zicsr___decode
        state_out = 0;
        Rv32im___decode(_this, state_out);
        if (((((_this._.raw & 'h3)) == 'h3) && (_this._.r.opcode == 'h73)) && (_this._.i.funct3 == 'h0)) begin
            if (_this._.raw == 'h73) begin
                state_out = 0;
                state_out.sys_op=Sys_pkg::ECALL;
                state_out.imm=_this._.raw;
                state_out.br_op=Br_pkg::BNONE;
            end
            else begin
                if (_this._.raw == 'h100073) begin
                    state_out = 0;
                    state_out.sys_op=Sys_pkg::EBREAK;
                    state_out.trap_op=Trap_pkg::BREAKPOINT;
                    state_out.imm=_this._.raw;
                    state_out.br_op=Br_pkg::BNONE;
                end
                else begin
                    if (_this._.raw == 'h30200073) begin
                        state_out = 0;
                        state_out.sys_op=Sys_pkg::MRET;
                        state_out.imm='h0;
                        state_out.br_op=Br_pkg::BNONE;
                    end
                    else begin
                        if (_this._.raw == 'h10200073) begin
                            state_out = 0;
                            state_out.sys_op=Sys_pkg::SRET;
                            state_out.imm='h0;
                            state_out.br_op=Br_pkg::BNONE;
                        end
                        else begin
                            if (_this._.raw == 'h10500073) begin
                                state_out = 0;
                                state_out.sys_op=Sys_pkg::WFI;
                                state_out.imm=_this._.raw;
                            end
                            else begin
                                state_out = 0;
                                state_out.sys_op=Sys_pkg::TRAP;
                                state_out.trap_op=Trap_pkg::ILLEGAL_INST;
                                state_out.imm=_this._.raw;
                                state_out.br_op=Br_pkg::BNONE;
                            end
                        end
                    end
                end
            end
        end
        if (((((_this._.raw & 'h3)) == 'h3) && (_this._.r.opcode == 'h73)) && (_this._.i.funct3 != 'h0)) begin
            state_out = 0;
            state_out.rd=_this._.i.rd;
            state_out.funct3=_this._.i.funct3;
            state_out.csr_addr=_this._.i.imm11_0;
            state_out.csr_imm=_this._.i.rs1;
            state_out.imm=_this._.raw;
            case (_this._.i.funct3)
            'h1: begin
                state_out.csr_op=Csr_pkg::CSRRW;
                state_out.rs1=_this._.i.rs1;
                state_out.wb_op=(_this._.i.rd) ? (Wb_pkg::ALU) : (Wb_pkg::WNONE);
            end
            'h2: begin
                state_out.csr_op=Csr_pkg::CSRRS;
                state_out.rs1=_this._.i.rs1;
                state_out.wb_op=(_this._.i.rd) ? (Wb_pkg::ALU) : (Wb_pkg::WNONE);
            end
            'h3: begin
                state_out.csr_op=Csr_pkg::CSRRC;
                state_out.rs1=_this._.i.rs1;
                state_out.wb_op=(_this._.i.rd) ? (Wb_pkg::ALU) : (Wb_pkg::WNONE);
            end
            'h5: begin
                state_out.csr_op=Csr_pkg::CSRRWI;
                state_out.wb_op=(_this._.i.rd) ? (Wb_pkg::ALU) : (Wb_pkg::WNONE);
            end
            'h6: begin
                state_out.csr_op=Csr_pkg::CSRRSI;
                state_out.wb_op=(_this._.i.rd) ? (Wb_pkg::ALU) : (Wb_pkg::WNONE);
            end
            'h7: begin
                state_out.csr_op=Csr_pkg::CSRRCI;
                state_out.wb_op=(_this._.i.rd) ? (Wb_pkg::ALU) : (Wb_pkg::WNONE);
            end
            default: begin
                state_out = 0;
                state_out.sys_op=Sys_pkg::TRAP;
                state_out.trap_op=Trap_pkg::ILLEGAL_INST;
                state_out.imm=_this._.raw;
                state_out.br_op=Br_pkg::BNONE;
            end
            endcase
        end
    end
    endtask

    function string Rv32i___mnemonic (input Rv32i _this);
        logic[31:0] op;
        logic[31:0] f3;
        logic[31:0] f7;
        op=_this._.r.opcode;
        f3=_this._.r.funct3;
        f7=_this._.r.funct7;
        case (op)
        'h33: begin
            if ((f3 == 'h0) && (f7 == 'h0)) begin
                return "add   ";
            end
            if ((f3 == 'h0) && (f7 == 'h20)) begin
                return "sub   ";
            end
            if ((f3 == 'h0) && (f7 == 'h1)) begin
                return "mul   ";
            end
            if ((f3 == 'h7) && (f7 == 'h1)) begin
                return "remu  ";
            end
            if (f3 == 'h7) begin
                return "and   ";
            end
            if (f3 == 'h6) begin
                return "or    ";
            end
            if (f3 == 'h4) begin
                return "xor   ";
            end
            if (f3 == 'h1) begin
                return "sll   ";
            end
            if ((f3 == 'h5) && (f7 == 'h0)) begin
                return "srl   ";
            end
            if ((f3 == 'h5) && (f7 == 'h20)) begin
                return "sra   ";
            end
            if ((f3 == 'h5) && (f7 == 'h1)) begin
                return "divu  ";
            end
            if (f3 == 'h2) begin
                return "slt   ";
            end
            if ((f3 == 'h3) && (f7 == 'h1)) begin
                return "mulhu ";
            end
            if (f3 == 'h3) begin
                return "sltu  ";
            end
            return "r-type";
        end
        'h13: begin
            if (f3 == 'h0) begin
                return "addi  ";
            end
            if (f3 == 'h7) begin
                return "andi  ";
            end
            if (f3 == 'h6) begin
                return "ori   ";
            end
            if (f3 == 'h4) begin
                return "xori  ";
            end
            if (f3 == 'h1) begin
                return "slli  ";
            end
            if ((f3 == 'h5) && (f7 == 'h0)) begin
                return "srli  ";
            end
            if ((f3 == 'h5) && (f7 == 'h20)) begin
                return "srai  ";
            end
            if (f3 == 'h2) begin
                return "slti  ";
            end
            if (f3 == 'h3) begin
                return "sltiu ";
            end
            return "aluimm";
        end
        'h3: begin
            return "load  ";
        end
        'h23: begin
            return "store ";
        end
        'h63: begin
            return "branch";
        end
        'h6F: begin
            return "jal   ";
        end
        'h67: begin
            return "jalr  ";
        end
        'h37: begin
            return "lui   ";
        end
        'h17: begin
            return "auipc ";
        end
        'hF: begin
            return (f3 == 'h1) ? ("fencei") : ("fence ");
        end
        default: begin
            return "unknwn";
        end
        endcase
        return "unknwn";
    endfunction

    function string Rv32ic___mnemonic (input Rv32ic _this);
        logic[7:0] op;
        logic[7:0] f3;
        logic[7:0] b12;
        logic[7:0] rs2;
        logic[7:0] bits6_5;
        logic[7:0] bits11_10;
        if (((_this._.raw & 'h3)) == 'h3) begin
            return Rv32i___mnemonic(_this);
        end
        op=Rv32ic___bits(_this, 'h1, 'h0);
        f3=Rv32ic___bits(_this, 'hF, 'hD);
        b12=Rv32ic___bit(_this, 'hC);
        bits6_5=Rv32ic___bits(_this, 'h6, 'h5);
        bits11_10=Rv32ic___bits(_this, 'hB, 'hA);
        rs2=Rv32ic___bits(_this, 'h6, 'h2);
        case (op)
        'h0: begin
            case (f3)
            'h0: begin
                return "addi4s";
            end
            'h2: begin
                return "lw    ";
            end
            'h6: begin
                return "sw    ";
            end
            'h3: begin
                return "ld    ";
            end
            'h7: begin
                return "sd    ";
            end
            default: begin
                return "rsrvd ";
            end
            endcase
        end
        'h1: begin
            case (f3)
            'h0: begin
                return "addi  ";
            end
            'h1: begin
                return "jal   ";
            end
            'h2: begin
                return "li    ";
            end
            'h3: begin
                return "addisp";
            end
            'h4: begin
                if (bits11_10 == 'h0) begin
                    return "srli  ";
                end
                if (bits11_10 == 'h1) begin
                    return "srai  ";
                end
                if (bits11_10 == 'h2) begin
                    return "andi  ";
                end
                if (((bits11_10 == 'h3) && (b12 == 'h0)) && (bits6_5 == 'h0)) begin
                    return "sub   ";
                end
                if (((bits11_10 == 'h3) && (b12 == 'h0)) && (bits6_5 == 'h1)) begin
                    return "xor   ";
                end
                if (((bits11_10 == 'h3) && (b12 == 'h0)) && (bits6_5 == 'h2)) begin
                    return "or    ";
                end
                if (((bits11_10 == 'h3) && (b12 == 'h0)) && (bits6_5 == 'h3)) begin
                    return "and   ";
                end
                return "illgl ";
            end
            'h5: begin
                return "j     ";
            end
            'h6: begin
                return "beqz  ";
            end
            'h7: begin
                return "bnez  ";
            end
            endcase
        end
        'h2: begin
            case (f3)
            'h0: begin
                return "slli  ";
            end
            'h1: begin
                return "fldsp ";
            end
            'h2: begin
                return "lwsp  ";
            end
            'h4: begin
                if ((rs2 != 'h0) && (b12 == 'h0)) begin
                    return "mv    ";
                end
                if ((rs2 != 'h0) && (b12 == 'h1)) begin
                    return "add   ";
                end
                if ((rs2 == 'h0) && (b12 == 'h0)) begin
                    return "jr    ";
                end
                if ((rs2 == 'h0) && (b12 == 'h1)) begin
                    return "jalr  ";
                end
                return "illgl ";
            end
            'h6: begin
                return "swsp  ";
            end
            'h3: begin
                return "ldsp  ";
            end
            'h7: begin
                return "sdsp  ";
            end
            default: begin
                return "rsrvd ";
            end
            endcase
        end
        endcase
        return "unknwn";
    endfunction

    function string Rv32im___mnemonic (input Rv32im _this);
        if ((_this._.r.opcode == 'h33) && (_this._.r.funct7 == 'h1)) begin
            if (_this._.r.funct3 == 'h0) begin
                return "mul   ";
            end
            if (_this._.r.funct3 == 'h1) begin
                return "mulh  ";
            end
            if (_this._.r.funct3 == 'h2) begin
                return "mulhsu";
            end
            if (_this._.r.funct3 == 'h3) begin
                return "mulhu ";
            end
            if (_this._.r.funct3 == 'h4) begin
                return "div   ";
            end
            if (_this._.r.funct3 == 'h5) begin
                return "divu  ";
            end
            if (_this._.r.funct3 == 'h6) begin
                return "rem   ";
            end
            if (_this._.r.funct3 == 'h7) begin
                return "remu  ";
            end
        end
        return Rv32ic___mnemonic(_this);
    endfunction

    function string Zicsr___mnemonic (input Zicsr _this);
        if ((((_this._.raw & 'h3)) == 'h3) && (_this._.r.opcode == 'h73)) begin
            if (_this._.raw == 'h73) begin
                return "ecall ";
            end
            if (_this._.raw == 'h100073) begin
                return "ebreak";
            end
            if (_this._.raw == 'h30200073) begin
                return "mret  ";
            end
            if (_this._.raw == 'h10200073) begin
                return "sret  ";
            end
            if (_this._.raw == 'h10500073) begin
                return "wfi   ";
            end
            if (_this._.i.funct3 == 'h1) begin
                return "csrrw ";
            end
            if (_this._.i.funct3 == 'h2) begin
                return "csrrs ";
            end
            if (_this._.i.funct3 == 'h3) begin
                return "csrrc ";
            end
            if (_this._.i.funct3 == 'h5) begin
                return "csrrwi";
            end
            if (_this._.i.funct3 == 'h6) begin
                return "csrrsi";
            end
            if (_this._.i.funct3 == 'h7) begin
                return "csrrci";
            end
        end
        return Rv32im___mnemonic(_this);
    endfunction

    task debug ();
    begin: debug
        State tmp;
        Zicsr instr;
        instr = '{icache__read_data_out};
        Zicsr___decode(instr, tmp);
        $write("(%d/%d)%x st[h%x b%x dc%x ic%x is%x ds%x ih%x]: [%s]%08x  rs%02d/%02d,imm:%08x,rd%02d => (%d)ops:%02d/%x/%x/%x sys%x rs%02d/%02d:%08x/%08x,imm:%08x,alu:%09x,rd%02d br(%d)%08x => mem(%d/%d@%08x)%08x/%01x (%d)wop(%x),r(%d)%08x@%02d", valid, stall_comb, pc, hazard_stall_comb, branch_stall_comb, dcache__busy_out, icache__busy_out, unsigned'(32'(icache__perf_out.state)), unsigned'(32'(dcache__perf_out.state)), icache__perf_out.hit, Zicsr___mnemonic(instr), (((instr._.raw & 'h3)) == 'h3) ? (instr._.raw) : ((instr._.raw | 'hFFFF0000)), signed'(32'(tmp.rs1)), signed'(32'(tmp.rs2)), tmp.imm, signed'(32'(tmp.rd)), state_reg['h0].valid, unsigned'(8'(state_reg['h0].alu_op)), unsigned'(8'(state_reg['h0].mem_op)), unsigned'(8'(state_reg['h0].br_op)), unsigned'(8'(state_reg['h0].wb_op)), unsigned'(8'(state_reg['h0].sys_op)), signed'(32'(state_reg['h0].rs1)), signed'(32'(state_reg['h0].rs2)), state_reg['h0].rs1_val, state_reg['h0].rs2_val, state_reg['h0].imm, exe__alu_result_out, signed'(32'(state_reg['h0].rd)), exe__branch_taken_out, exe__branch_target_out, exe_mem__mem_write_out, exe_mem__mem_read_out, exe_mem__mem_write_addr_out, exe_mem__mem_write_data_out, exe_mem__mem_write_mask_out, state_reg['h1].valid, unsigned'(8'(state_reg['h1].wb_op)), wb__regs_write_out, wb__regs_data_out, wb__regs_wr_id_out);
    end
    endtask

    task _work (input logic reset);
    begin: _work
        if (debugen_in && !reset) begin
            debug();
        end
        sbi_ret_a1_valid_reg_tmp = unsigned'(1'(0));
        sbi_ret_a1_reg_tmp = sbi_ret_a1_reg;
        if (((dmem_addr_out == 'h11223344) && dmem_write_out) && !output_write_active_reg) begin
            logic signed[31:0] out; out = $fopen("out.txt", "a");
            if (debugen_in) begin
                $write("OUTPUT pc=%x data=%08x char=%02x\n", pc, dmem_write_data_out, dmem_write_data_out & 'hFF);
            end
            $fwrite(out, "%c", dmem_write_data_out & 'hFF);
            $fclose(out);
        end
        output_write_active_reg_tmp = unsigned'(1'((dmem_addr_out == 'h11223344) && dmem_write_out));
        if ((!reset && state_reg['h0].valid) && (((state_reg['h0].sys_op == Sys_pkg::MRET) || (state_reg['h0].sys_op == Sys_pkg::SRET)))) begin
            logic[31:0] epc; epc = (state_reg['h0].sys_op == Sys_pkg::SRET) ? (unsigned'(32'(csr__sepc_out))) : (unsigned'(32'(csr__mepc_out)));
            pc_tmp = unsigned'(32'(epc));
            valid_tmp = unsigned'(1'(0));
            state_reg_tmp['h0] = 0;
            state_reg_tmp['h0].valid=0;
            state_reg_tmp['h1] = 0;
            state_reg_tmp['h1].valid=0;
            predicted_next_reg_tmp = '0;
            fallthrough_reg_tmp = '0;
            predicted_taken_reg_tmp = '0;
            alu_result_reg_tmp = alu_result_reg;
            debug_branch_target_reg_tmp = unsigned'(32'(epc));
            debug_branch_taken_reg_tmp = unsigned'(1'(1));
            interrupt_entry_guard_reg_tmp = unsigned'(1'(0));
        end
        else begin
            if (sbi_handled_comb) begin
                interrupt_entry_guard_reg_tmp = unsigned'(1'(0));
                pc_tmp = pc;
                valid_tmp = unsigned'(1'(0));
                state_reg_tmp['h0] = 0;
                state_reg_tmp['h0].valid=0;
                state_reg_tmp['h1] = exe_state_comb;
                predicted_next_reg_tmp = '0;
                fallthrough_reg_tmp = '0;
                predicted_taken_reg_tmp = '0;
                alu_result_reg_tmp = unsigned'(32'h0);
                sbi_ret_a1_valid_reg_tmp = unsigned'(1'(sbi_writes_a1_comb));
                sbi_ret_a1_reg_tmp = unsigned'(32'(sbi_ret_value_comb));
                debug_branch_target_reg_tmp = pc;
                debug_branch_taken_reg_tmp = unsigned'(1'(0));
            end
            else begin
                if (memory_wait_comb) begin
                    pc_tmp = pc;
                    interrupt_entry_guard_reg_tmp = unsigned'(1'(0));
                    valid_tmp = valid;
                    state_reg_tmp = state_reg;
                    predicted_next_reg_tmp = predicted_next_reg;
                    fallthrough_reg_tmp = fallthrough_reg;
                    predicted_taken_reg_tmp = predicted_taken_reg;
                    alu_result_reg_tmp = alu_result_reg;
                    if ((wb_mem__load_ready_out && (state_reg['h1].rd != 'h0)) && state_reg['h0].valid) begin
                        if (state_reg['h0].rs1 == state_reg['h1].rd) begin
                            state_reg_tmp['h0].rs1_val=wb_mem__load_result_out;
                        end
                        if (state_reg['h0].rs2 == state_reg['h1].rd) begin
                            state_reg_tmp['h0].rs2_val=wb_mem__load_result_out;
                        end
                    end
                    debug_branch_target_reg_tmp = debug_branch_target_reg;
                    debug_branch_taken_reg_tmp = debug_branch_taken_reg;
                end
                else begin
                    interrupt_entry_guard_reg_tmp = unsigned'(1'(0));
                    pc_tmp = pc;
                    if (fetch_valid_comb && !stall_comb) begin
                        pc_tmp = unsigned'(32'(decode_fallthrough_comb));
                    end
                    if (decode_branch_valid_comb) begin
                        pc_tmp = unsigned'(32'(bp__predict_next_out));
                    end
                    if (branch_mispredict_comb) begin
                        pc_tmp = unsigned'(32'(branch_actual_next_comb));
                    end
                    valid_tmp = unsigned'(1'(!decode_indirect_branch_valid_comb));
                    if (hazard_stall_comb) begin
                        state_reg_tmp['h0] = 0;
                        state_reg_tmp['h0].valid=0;
                        predicted_next_reg_tmp['h0] = pc;
                        fallthrough_reg_tmp['h0] = pc;
                        predicted_taken_reg_tmp['h0] = unsigned'(1'(0));
                    end
                    else begin
                        if (fetch_valid_comb) begin
                            state_reg_tmp['h0] = dec__state_out;
                            state_reg_tmp['h0].valid=(dec__instr_valid_in && !branch_stall_comb) && !branch_flush_comb;
                            predicted_next_reg_tmp['h0] = unsigned'(32'((decode_branch_valid_comb) ? (unsigned'(32'(bp__predict_next_out))) : (decode_fallthrough_comb)));
                            fallthrough_reg_tmp['h0] = unsigned'(32'(decode_fallthrough_comb));
                            predicted_taken_reg_tmp['h0] = unsigned'(1'(decode_branch_valid_comb && bp__predict_taken_out));
                            forward();
                        end
                        else begin
                            state_reg_tmp['h0] = 0;
                            state_reg_tmp['h0].valid=0;
                            predicted_next_reg_tmp['h0] = pc;
                            fallthrough_reg_tmp['h0] = pc;
                            predicted_taken_reg_tmp['h0] = unsigned'(1'(0));
                        end
                    end
                    state_reg_tmp['h1] = state_reg['h0];
                    predicted_next_reg_tmp['h1] = predicted_next_reg['h0];
                    fallthrough_reg_tmp['h1] = fallthrough_reg['h0];
                    predicted_taken_reg_tmp['h1] = predicted_taken_reg['h0];
                    alu_result_reg_tmp = unsigned'(32'((state_reg['h0].csr_op != Csr_pkg::CNONE) ? (csr__read_data_out) : (exe__alu_result_out)));
                    debug_branch_target_reg_tmp = unsigned'(32'(exe__branch_target_out));
                    debug_branch_taken_reg_tmp = unsigned'(1'(exe__branch_taken_out));
                end
            end
        end
        if ((state_reg['h0].valid && (state_reg['h0].sys_op == Sys_pkg::FENCEI)) && !memory_wait_comb) begin
            icache_invalidate_issued_reg_tmp = unsigned'(1'(1));
        end
        else begin
            if (!state_reg['h0].valid || (state_reg['h0].sys_op != Sys_pkg::FENCEI)) begin
                icache_invalidate_issued_reg_tmp = unsigned'(1'(0));
            end
        end
        if (reset) begin
            state_reg_tmp['h0].valid='h0;
            state_reg_tmp['h1].valid='h0;
            pc_tmp = unsigned'(32'(reset_pc_in));
            valid_tmp = '0;
            predicted_next_reg_tmp = '0;
            fallthrough_reg_tmp = '0;
            predicted_taken_reg_tmp = '0;
            output_write_active_reg_tmp = '0;
            interrupt_entry_guard_reg_tmp = '0;
            sbi_ret_a1_valid_reg_tmp = '0;
            sbi_ret_a1_reg_tmp = '0;
            icache_invalidate_issued_reg_tmp = '0;
        end
    end
    endtask

    task _work_neg (input logic reset);
    begin: _work_neg
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin
        icache_invalidate_issued_reg_tmp = icache_invalidate_issued_reg;
        pc_tmp = pc;
        valid_tmp = valid;
        alu_result_reg_tmp = alu_result_reg;
        state_reg_tmp = state_reg;
        predicted_next_reg_tmp = predicted_next_reg;
        fallthrough_reg_tmp = fallthrough_reg;
        predicted_taken_reg_tmp = predicted_taken_reg;
        debug_alu_a_reg_tmp = debug_alu_a_reg;
        debug_alu_b_reg_tmp = debug_alu_b_reg;
        debug_branch_target_reg_tmp = debug_branch_target_reg;
        debug_branch_taken_reg_tmp = debug_branch_taken_reg;
        output_write_active_reg_tmp = output_write_active_reg;
        interrupt_entry_guard_reg_tmp = interrupt_entry_guard_reg;
        sbi_ret_a1_valid_reg_tmp = sbi_ret_a1_valid_reg;
        sbi_ret_a1_reg_tmp = sbi_ret_a1_reg;

        _work(reset);

        icache_invalidate_issued_reg <= icache_invalidate_issued_reg_tmp;
        pc <= pc_tmp;
        valid <= valid_tmp;
        alu_result_reg <= alu_result_reg_tmp;
        state_reg <= state_reg_tmp;
        predicted_next_reg <= predicted_next_reg_tmp;
        fallthrough_reg <= fallthrough_reg_tmp;
        predicted_taken_reg <= predicted_taken_reg_tmp;
        debug_alu_a_reg <= debug_alu_a_reg_tmp;
        debug_alu_b_reg <= debug_alu_b_reg_tmp;
        debug_branch_target_reg <= debug_branch_target_reg_tmp;
        debug_branch_taken_reg <= debug_branch_taken_reg_tmp;
        output_write_active_reg <= output_write_active_reg_tmp;
        interrupt_entry_guard_reg <= interrupt_entry_guard_reg_tmp;
        sbi_ret_a1_valid_reg <= sbi_ret_a1_valid_reg_tmp;
        sbi_ret_a1_reg <= sbi_ret_a1_reg_tmp;
    end

    always_ff @(negedge clk) begin

        _work_neg(reset);

    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end

    assign sbi_set_timer_out = sbi_set_timer_comb;

    assign sbi_timer_lo_out = sbi_timer_lo_comb;

    assign sbi_timer_hi_out = sbi_timer_hi_comb;

    assign debug_sbi_out = debug_sbi_comb;

    assign perf_out = perf_comb;


endmodule
