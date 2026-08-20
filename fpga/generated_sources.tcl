# Ordered CppHDL output required by the SmartNIC top level.  Keep package files
# before modules so this list works with both Vivado and standalone lint tools.
proc smartnic_generated_sources {generated_dir} {
    set names [list \
        Predef_pkg.sv \
        PacketParserFields_pkg.sv \
        PacketParserWord_pkg.sv \
        PacketParserProgress_pkg.sv \
        PacketParserPipeWord_pkg.sv \
        PacketParserHeaderId_pkg.sv \
        PacketParserCall_pkg.sv \
        PacketParserFlags_pkg.sv \
        RxRAMWritePair_pkg.sv \
        RxDescriptor_pkg.sv \
        RxDescriptorWord_pkg.sv \
        RxDescriptorFlags_pkg.sv \
        SmartNicMemory.sv \
        Fifo.sv \
        SmartNicRAM.sv \
        InputBalancer.sv \
        PacketParser.sv \
        RxRAM.sv \
        RxFifo.sv \
        TxFifo.sv \
        OutputMerger.sv \
        Network.sv \
        AsyncFifoNetToL2.sv \
        AsyncFifoL2ToNet.sv \
        AsyncPacketStreamNetToL2.sv \
        AsyncPacketStreamL2ToNet.sv \
        SmartNIC.sv]

    set sources [list]
    foreach name $names {
        set path [file normalize [file join $generated_dir $name]]
        if {![file exists $path]} {
            error "Missing generated SmartNIC source: $path"
        }
        lappend sources $path
    }
    return $sources
}

