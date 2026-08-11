package SystemRingDescriptorWord_pkg;
import SystemRingDescriptor_pkg::*;

typedef union packed {
    logic[128-1:0] raw;
    SystemRingDescriptor descriptor;
} SystemRingDescriptorWord;


endpackage
