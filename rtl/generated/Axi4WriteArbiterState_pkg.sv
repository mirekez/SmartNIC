package Axi4WriteArbiterState_pkg;

typedef enum logic[8-1:0] {
    AXI4_ARB_IDLE,
    AXI4_ARB_WRITE_DATA,
    AXI4_ARB_WRITE_RESPONSE,
    AXI4_ARB_READ_DATA
} Axi4WriteArbiterState;


endpackage
