# Kintex-board functional CDC constraints.
#
# L1MemFastToSlowCdc bridges the related 312.5 MHz CPU/L1 domain to the
# 156.25 MHz L2 domain with toggle synchronizers and held bundled payloads.
# This file is unconditional because every board Processing instance contains
# these cells; XDC files do not support Tcl control-flow commands.

set l1_l2_sync_regs [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ */request_slow1_reg_reg* ||
        NAME =~ */request_slow2_reg_reg* ||
        NAME =~ */response_fast1_reg_reg* ||
        NAME =~ */response_fast2_reg_reg*)}]
set_property ASYNC_REG TRUE $l1_l2_sync_regs

# Only the first toggle stage is a metastability endpoint. Stage 1 -> stage 2
# remains timed normally in the destination domain.
set l1_l2_first_sync [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ */request_slow1_reg_reg* ||
        NAME =~ */response_fast1_reg_reg*)}]
set l1_l2_first_sync_d [get_pins -quiet -of_objects $l1_l2_first_sync \
    -filter {REF_PIN_NAME == D}]
set_false_path -to $l1_l2_first_sync_d

# Request fields are captured only after the request toggle has traversed two
# L2 synchronizer stages. The source holds them until the response returns.
set l1_request_source [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ */read_fast_reg_reg* ||
        NAME =~ */write_fast_reg_reg* ||
        NAME =~ */addr_fast_reg_reg* ||
        NAME =~ */write_data_fast_reg_reg* ||
        NAME =~ */write_mask_fast_reg_reg* ||
        NAME =~ */cache_disable_fast_reg_reg*)}]
set l1_request_capture [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ */read_slow_reg_reg* ||
        NAME =~ */write_slow_reg_reg* ||
        NAME =~ */addr_slow_reg_reg* ||
        NAME =~ */write_data_slow_reg_reg* ||
        NAME =~ */write_mask_slow_reg_reg* ||
        NAME =~ */cache_disable_slow_reg_reg*)}]
set_multicycle_path -setup 2 -from $l1_request_source \
    -to $l1_request_capture
set_multicycle_path -hold 1 -from $l1_request_source \
    -to $l1_request_capture

# The L2 read payload is registered before response_slow_reg toggles and is
# captured by the CPU only when that toggle reaches synchronizer stage 2.
set l2_response_source [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */read_data_slow_reg_reg*}]
set l2_response_capture [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */read_data_fast_reg_reg*}]
set_multicycle_path -setup 2 -from $l2_response_source \
    -to $l2_response_capture
set_multicycle_path -hold 1 -from $l2_response_source \
    -to $l2_response_capture
