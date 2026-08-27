foreach(required_file PROCESSING_SV CPU_SV TRIBE_TEST_SV)
    if(NOT DEFINED ${required_file} OR NOT EXISTS "${${required_file}}")
        message(FATAL_ERROR "Missing generated RTL ${required_file}: ${${required_file}}")
    endif()
endforeach()

if(DEFINED OBSOLETE_SMARTNIC_TRIBE_SV AND EXISTS "${OBSOLETE_SMARTNIC_TRIBE_SV}")
    message(FATAL_ERROR
        "Obsolete generated SmartNicTribeTest.sv survived regeneration: ${OBSOLETE_SMARTNIC_TRIBE_SV}")
endif()

file(READ "${PROCESSING_SV}" processing_rtl)
file(READ "${CPU_SV}" cpu_rtl)
file(READ "${TRIBE_TEST_SV}" tribe_test_rtl)

function(require_one_driver rtl variable net index_suffix)
    string(REGEX MATCHALL
        "assign[ \t\r\n]+${net}${index_suffix}[ \t\r\n]*="
        drivers "${${rtl}}")
    list(LENGTH drivers driver_count)
    if(NOT driver_count EQUAL 1)
        message(FATAL_ERROR
            "${net}${index_suffix} has ${driver_count} generated continuous drivers; expected 1")
    endif()
endfunction()

set(single_driver_nets
    cpu__dma_line_valid_in
    cpu__dma_line_addr_in
    cpu__dma_line_data_in
    cpu__dma_line_keep_in
    cpu__dma_line_eop_in
    packet_dma__l2_line_ready_in)

foreach(net IN LISTS single_driver_nets)
    require_one_driver(processing_rtl processing_rtl "${net}" "\\[gindex\\]")
endforeach()

foreach(net tribe__dma_line_valid_in tribe__dma_line_addr_in
        tribe__dma_line_data_in tribe__dma_line_keep_in dma_line_ready_out)
    require_one_driver(cpu_rtl cpu_rtl "${net}" "")
endforeach()

foreach(net l2cache__dma_line_valid_in l2cache__dma_line_addr_in
        l2cache__dma_line_data_in l2cache__dma_line_keep_in dma_line_ready_out)
    require_one_driver(tribe_test_rtl tribe_test_rtl "${net}" "")
endforeach()

message(STATUS
    "Processing coherent-line bindings each have one RTL driver through L2")
