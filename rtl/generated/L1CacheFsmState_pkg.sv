package L1CacheFsmState_pkg;

typedef enum logic[64-1:0] {
    L1_ST_IDLE = 'h0,
    L1_ST_LOOKUP = 'h1,
    L1_ST_DONE = 'h2,
    L1_ST_REFILL = 'h3,
    L1_ST_INIT = 'h4
} L1CacheFsmState;


endpackage
