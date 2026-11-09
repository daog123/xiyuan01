// Single-byte AXI write slot. Unlike the W4A8 output writer, no alignment/padding is needed.
module storage_axi_byte_write #(parameter integer ADDR_WIDTH=32)(
    input logic clk,rst,
    input logic cmd_valid,output logic cmd_ready,input logic [ADDR_WIDTH-1:0] cmd_addr,input logic [7:0] cmd_data,
    output logic ack_valid,ack_error,idle,
    output logic awvalid,input logic awready,output logic [ADDR_WIDTH-1:0] awaddr,
    output wire [3:0] awid,output wire [7:0] awlen,output wire [2:0] awsize,output wire [1:0] awburst,
    output logic wvalid,input logic wready,output logic [63:0] wdata,output logic [7:0] wstrb,output wire wlast,
    input logic bvalid,output logic bready,input logic [3:0] bid,input logic [1:0] bresp
);
    logic occupied,ap,wp;
    assign awid=0;assign awlen=0;assign awsize=0;assign awburst=1;assign wlast=1;
    assign idle=!occupied;assign cmd_ready=idle && !rst;
    assign awvalid=ap && !rst;assign wvalid=wp && !rst;
    assign bready=occupied && !ap && !wp && !rst;
    always_ff @(posedge clk) begin
        if(rst) begin occupied<=0;ap<=0;wp<=0;ack_valid<=0;ack_error<=0;awaddr<=0;wdata<=0;wstrb<=0;end
        else begin
            ack_valid<=0;
            if(cmd_valid && cmd_ready) begin
                occupied<=1;ap<=1;wp<=1;awaddr<=cmd_addr;
                wdata<=64'(cmd_data) << (cmd_addr[2:0]*8);wstrb<=8'h01 << cmd_addr[2:0];
            end
            if(awvalid && awready) ap<=0;
            if(wvalid && wready) wp<=0;
            if(bvalid && bready) begin occupied<=0;ack_valid<=1;ack_error<=bid!=0 || bresp!=0;end
        end
    end
endmodule
