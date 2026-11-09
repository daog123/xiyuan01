module w4a8_system_top #(
    parameter integer ROWS=4,COLS=4,TILE_K=8,GROUP_SIZE=32,
    parameter integer MAX_M=64,MAX_N=64,MAX_K=4096,
    parameter integer TIMEOUT_CYCLES=1000000
)(
    input logic clk,rst,
    input logic task_valid, output logic task_ready,
    input task_desc_pkg::task_desc_t task_desc,
    input logic load_pause,
    output logic mem_req_valid,input logic mem_req_ready,
    output logic [31:0] mem_task_id,
    output logic [63:0] mem_a_addr,mem_w_addr,mem_sx_addr,mem_sw_addr,
    output logic [31:0] mem_a_stride,mem_w_stride,mem_sx_stride,mem_sw_stride,
    output logic [15:0] mem_req_m,mem_req_n,mem_req_k,mem_req_ml,mem_req_nl,mem_req_kl,mem_req_group,
    output logic mem_req_scale,
    input logic mem_in_valid,output logic mem_in_ready,
    input logic [63:0] mem_in_data,input logic [7:0] mem_in_keep,
    output logic mem_wr_valid,input logic mem_wr_ready,
    output logic [31:0] mem_wr_task_id,output logic [63:0] mem_wr_addr,
    output logic [15:0] mem_wr_m,mem_wr_n,output logic signed [31:0] mem_wr_data,
    output logic mem_wr_last,input logic mem_wr_ack,
    output logic completion_valid,input logic completion_ready,
    output logic [31:0] completion_task_id,output logic [7:0] completion_status,
    output logic result_available,output logic [31:0] elapsed_cycles
);
    logic core_reset,core_start,core_start_ready,core_busy,core_done,core_error;
    logic [15:0] cfg_m,cfg_n,cfg_k;
    logic core_req_valid,core_req_ready,core_req_scale;
    logic [15:0] core_req_m,core_req_n,core_req_k,core_req_ml,core_req_nl,core_req_kl,core_req_group;
    logic core_in_ready,core_out_valid,core_out_ready,core_out_last;
    logic [15:0] core_out_m,core_out_n;
    logic signed [31:0] core_out_data;
    logic [31:0] core_cycles,core_wbytes,core_abytes,core_sbytes,core_macs,core_ccycles;
    logic [31:0] core_iwait,core_owait,core_overlap,core_beats,core_padding;

    task_controller #(.MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K),
        .GROUP_SIZE(GROUP_SIZE),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) control (
        .clk(clk),.rst(rst),.task_valid(task_valid),.task_ready(task_ready),.task_desc(task_desc),
        .core_reset(core_reset),.core_start(core_start),.core_start_ready(core_start_ready),
        .core_busy(core_busy),.core_done(core_done),.core_error(core_error),
        .core_cfg_m(cfg_m),.core_cfg_n(cfg_n),.core_cfg_k(cfg_k),
        .core_req_valid(core_req_valid),.core_req_ready(core_req_ready),
        .core_req_m(core_req_m),.core_req_n(core_req_n),.core_req_k(core_req_k),
        .core_req_ml(core_req_ml),.core_req_nl(core_req_nl),.core_req_kl(core_req_kl),
        .core_req_group(core_req_group),.core_req_scale(core_req_scale),
        .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),.mem_task_id(mem_task_id),
        .mem_a_addr(mem_a_addr),.mem_w_addr(mem_w_addr),.mem_sx_addr(mem_sx_addr),.mem_sw_addr(mem_sw_addr),
        .mem_a_stride(mem_a_stride),.mem_w_stride(mem_w_stride),
        .mem_sx_stride(mem_sx_stride),.mem_sw_stride(mem_sw_stride),
        .mem_req_m(mem_req_m),.mem_req_n(mem_req_n),.mem_req_k(mem_req_k),
        .mem_req_ml(mem_req_ml),.mem_req_nl(mem_req_nl),.mem_req_kl(mem_req_kl),
        .mem_req_group(mem_req_group),.mem_req_scale(mem_req_scale),
        .core_in_ready(core_in_ready),.mem_in_ready(mem_in_ready),
        .core_out_valid(core_out_valid),.core_out_ready(core_out_ready),
        .core_out_m(core_out_m),.core_out_n(core_out_n),.core_out_last(core_out_last),.core_out_data(core_out_data),
        .mem_wr_valid(mem_wr_valid),.mem_wr_ready(mem_wr_ready),.mem_wr_task_id(mem_wr_task_id),
        .mem_wr_addr(mem_wr_addr),.mem_wr_m(mem_wr_m),.mem_wr_n(mem_wr_n),.mem_wr_data(mem_wr_data),
        .mem_wr_last(mem_wr_last),.mem_wr_ack(mem_wr_ack),
        .completion_valid(completion_valid),.completion_ready(completion_ready),
        .completion_task_id(completion_task_id),.completion_status(completion_status),
        .result_available(result_available),.elapsed_cycles(elapsed_cycles));

    w4a8_stream #(.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),.GROUP_SIZE(GROUP_SIZE),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K),.BUS_BYTES(8)) core (
        .clk(clk),.rst(core_reset),.load_pause(load_pause),.start(core_start),
        .start_ready(core_start_ready),.busy(core_busy),.done(core_done),.error(core_error),
        .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),
        .req_valid(core_req_valid),.req_ready(core_req_ready),
        .req_m(core_req_m),.req_n(core_req_n),.req_k(core_req_k),
        .req_ml(core_req_ml),.req_nl(core_req_nl),.req_kl(core_req_kl),.req_group(core_req_group),
        .req_scale(core_req_scale),.in_valid(mem_in_valid),.in_ready(core_in_ready),
        .in_data(mem_in_data),.in_keep(mem_in_keep),.out_valid(core_out_valid),.out_ready(core_out_ready),
        .out_m(core_out_m),.out_n(core_out_n),.out_last(core_out_last),.out_data(core_out_data),
        .total_cycles(core_cycles),.weight_bytes(core_wbytes),.activation_bytes(core_abytes),.scale_bytes(core_sbytes),
        .valid_macs(core_macs),.compute_cycles(core_ccycles),.input_wait_cycles(core_iwait),
        .output_wait_cycles(core_owait),.overlap_cycles(core_overlap),.input_beats(core_beats),.padding_bytes(core_padding));
endmodule
