package L2AxiAddressState_pkg;

typedef struct packed {
    logic[4-1:0] _align0;
    logic[4-1:0] id;
    logic[32-1:0] addr;
    logic[7-1:0] _align1;
    logic valid;
} L2AxiAddressState;


endpackage
