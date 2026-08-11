package InputBalancerOutput2560_320_pkg;

typedef struct packed {
    logic[8-1:0] valid;
    logic[320-1:0] eop;
    logic[320-1:0] sop;
    logic[320-1:0] keep;
    logic[2560-1:0] data;
} InputBalancerOutput2560_320;


endpackage
