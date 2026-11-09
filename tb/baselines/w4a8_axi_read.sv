// One reserved byte response slot, one AXI transaction, fixed ID=0.
// Single-beat INCR, ARSIZE=0. Never aligns down or reads padding.
module w4a8_axi_read #(parameter integer ADDR_WIDTH=32)(
    input logic clk,rst,
    input logic cmd_valid, output logic cmd_ready, input logic [ADDR_WIDTH-1:0] cmd_addr,
    output logic rsp_valid, input logic rsp_ready,
    output logic [7:0] rsp_data, output logic rsp_error, output logic idle,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,
    output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast
);
    typedef enum logic [2:0] {EMPTY,ADDRESS,DATA,DRAIN,RESPONSE} state_t;
    state_t state;
    assign arid=0;assign arlen=0;assign arsize=0;assign arburst=1;
    assign idle=state==EMPTY;
    assign cmd_ready=idle && !rst;
    assign arvalid=state==ADDRESS && !rst;
    assign rready=(state==DATA || state==DRAIN) && !rst;
    assign rsp_valid=state==RESPONSE && !rst;
    always_ff @(posedge clk) begin
        if(rst) begin state<=EMPTY;araddr<=0;rsp_data<=0;rsp_error<=0;end
        else case(state)
            EMPTY:if(cmd_valid) begin araddr<=cmd_addr;state<=ADDRESS;rsp_error<=0;end
            ADDRESS:if(arready) state<=DATA;
            DATA:if(rvalid) begin
                rsp_data<=rdata[araddr[2:0]*8 +:8];
                rsp_error<=rresp!=0 || rid!=0 || !rlast;
                state<=rlast?RESPONSE:DRAIN;
            end
            // A malformed longer response is drained to its RLAST; no new task can start.
            DRAIN:if(rvalid && rlast) state<=RESPONSE;
            RESPONSE:if(rsp_ready) state<=EMPTY;
            default:state<=EMPTY;
        endcase
    end
endmodule
