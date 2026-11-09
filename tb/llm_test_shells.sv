module accelerator_test_shell #(
    parameter integer ADDR_WIDTH=64,GROUP_SIZE=32,ROWS=4,COLS=4,TILE_K=32,
    parameter integer MAX_M=64,MAX_N=64,MAX_K=4096,MAX_H=64,CAPACITY=512
)(
    input logic clk,rst,
    input logic job_valid,output logic job_ready,input logic [7:0] job_opcode,
    input accelerator_pkg::bounded_task_t linear_task,
    input accelerator_pkg::ffn_plan_t ffn_plan,
    input logic load_pause,post_pause,array_pause,
    output logic completion_valid,input logic completion_ready,
    output logic [31:0] completion_task_id,output logic [7:0] completion_status,
    output logic result_available,output logic [3:0] stage,
    output logic [31:0] elapsed_cycles,activation_written,scale_written,

    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output logic [3:0] arid,output logic [7:0] arlen,output logic [2:0] arsize,output logic [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast,
    output logic awvalid,input logic awready,output logic [ADDR_WIDTH-1:0] awaddr,
    output logic [3:0] awid,output logic [7:0] awlen,output logic [2:0] awsize,output logic [1:0] awburst,
    output logic wvalid,input logic wready,output logic [63:0] wdata,output logic [7:0] wstrb,output logic wlast,
    input logic bvalid,output logic bready,input logic [3:0] bid,input logic [1:0] bresp
);

    llm_graph_top #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K),.MAX_H(MAX_H),.CAPACITY(CAPACITY)) dut(
        .qkv_plan('0),.kv_config('0),.kv_command('0),.attention_task('0),.configured(),
        .append_valid(1'b0),.append_ready(),.append_data(8'd0),.append_last(1'b0),
        .read_valid(),.read_ready(1'b1),.read_data(),.read_last(),
        .q_valid(1'b0),.q_ready(),.q_data(8'd0),.q_scale(16'd0),.q_last(1'b0),.*);
endmodule
module attention_test_shell #(parameter integer ADDR_WIDTH=64,GROUP_SIZE=32,
    MAX_DIM=64,MAX_TOKENS=16,MAX_LAYERS=4,MAX_HEADS=8)(
    input logic clk,rst,
    input logic cfg_valid,output logic cfg_ready,input kv_cache_pkg::kv_config_t cfg_desc,
    input logic cmd_valid,output logic cmd_ready,input kv_cache_pkg::kv_command_t cmd_desc,
    input logic append_valid,output logic append_ready,input logic [7:0] append_data,input logic append_last,
    output logic read_valid,input logic read_ready,output logic [7:0] read_data,output logic read_last,
    input logic query_valid,output logic query_ready,input attention_pkg::attention_task_t query_desc,
    input logic q_valid,output logic q_ready,input logic signed [7:0] q_data,input logic [15:0] q_scale,input logic q_last,
    output logic completion_valid,input logic completion_ready,
    output logic [31:0] completion_task_id,output logic [7:0] completion_status,
    output logic result_available,output logic configured,

    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output logic [3:0] arid,output logic [7:0] arlen,output logic [2:0] arsize,output logic [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast,
    output logic awvalid,input logic awready,output logic [ADDR_WIDTH-1:0] awaddr,
    output logic [3:0] awid,output logic [7:0] awlen,output logic [2:0] awsize,output logic [1:0] awburst,
    output logic wvalid,input logic wready,output logic [63:0] wdata,output logic [7:0] wstrb,output logic wlast,
    input logic bvalid,output logic bready,input logic [3:0] bid,input logic [1:0] bresp
);

    wire job_valid=query_valid || cfg_valid || cmd_valid;
    wire job_ready;
    wire [7:0] job_opcode=query_valid?accelerator_pkg::OP_ATTENTION:cfg_valid?accelerator_pkg::OP_KV_CONFIG:accelerator_pkg::OP_KV_COMMAND;
    assign query_ready=job_ready;assign cfg_ready=job_ready;assign cmd_ready=job_ready;
    llm_graph_top #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_DIM(MAX_DIM),.MAX_TOKENS(MAX_TOKENS)) dut(
        .qkv_plan('0),.kv_config(cfg_desc),.kv_command(cmd_desc),.attention_task(query_desc),.linear_task('0),.ffn_plan('0),
        .load_pause(1'b0),.post_pause(1'b0),.array_pause(1'b0),.stage(),.elapsed_cycles(),.activation_written(),.scale_written(),.*);
endmodule
