// Shell-facing LINEAR endpoint: 32-bit AXI4-Lite control, 64-bit AXI4 DDR master.
// This is an integration IP boundary, not a pin-level FPGA top or bitstream.
module w4a8_board_top #(
    parameter integer GROUP_SIZE=32,ROWS=4,COLS=4,TILE_K=32,
    MAX_M=64,MAX_N=64,MAX_K=4096
)(
    input logic clk,rst,ddr_ready,
    input logic [11:0] s_axi_awaddr,input logic s_axi_awvalid,output logic s_axi_awready,
    input logic [31:0] s_axi_wdata,input logic [3:0] s_axi_wstrb,
    input logic s_axi_wvalid,output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,output logic s_axi_bvalid,input logic s_axi_bready,
    input logic [11:0] s_axi_araddr,input logic s_axi_arvalid,output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,input logic s_axi_rready,
    output logic arvalid,input logic arready,output logic [63:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast,
    output logic awvalid,input logic awready,output logic [63:0] awaddr,
    output wire [3:0] awid,output wire [7:0] awlen,output wire [2:0] awsize,output wire [1:0] awburst,
    output logic wvalid,input logic wready,output logic [63:0] wdata,
    output logic [7:0] wstrb,output wire wlast,
    input logic bvalid,output logic bready,input logic [3:0] bid,input logic [1:0] bresp
);
    task_desc_pkg::task_desc_t task_desc;
    logic task_valid,task_ready,completion_valid,completion_ready;
    logic [31:0] a_bytes,w_bytes,sx_bytes,sw_bytes,y_bytes,completion_task_id,elapsed_cycles;
    logic [7:0] completion_status;
    w4a8_board_control #(.GROUP_SIZE(GROUP_SIZE),.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) control(.*);
    w4a8_team_top #(.ADDR_WIDTH(64),.GROUP_SIZE(GROUP_SIZE),.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) core(
        .load_pause(1'b0),.post_pause(1'b0),.array_pause(1'b0),.result_available(),.*);
endmodule
