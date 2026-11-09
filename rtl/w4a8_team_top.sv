// Unified host task -> bounded AXI storage -> C/E wave core -> B-response fence.
// Original A/D packet top and all C/E arithmetic modules remain available.
module w4a8_team_top #(
    parameter integer ADDR_WIDTH=32,ROWS=4,COLS=4,TILE_K=8,GROUP_SIZE=32,
    parameter integer MAX_M=64,MAX_N=64,MAX_K=4096
)(
    input logic clk,rst,load_pause,post_pause,array_pause,
    input logic task_valid,output logic task_ready,input task_desc_pkg::task_desc_t task_desc,
    input logic [31:0] a_bytes,w_bytes,sx_bytes,sw_bytes,y_bytes,
    output logic completion_valid,input logic completion_ready,
    output logic [31:0] completion_task_id,output logic [7:0] completion_status,
    output logic result_available,output logic [31:0] elapsed_cycles,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast,
    output logic awvalid,input logic awready,output logic [ADDR_WIDTH-1:0] awaddr,
    output wire [3:0] awid,output wire [7:0] awlen,output wire [2:0] awsize,output wire [1:0] awburst,
    output logic wvalid,input logic wready,output logic [63:0] wdata,
    output logic [7:0] wstrb,output wire wlast,
    input logic bvalid,output logic bready,input logic [3:0] bid,input logic [1:0] bresp
);
    import task_desc_pkg::*;
    import w4a8_memory_pkg::*;
    typedef enum logic [2:0] {IDLE,CHECK,DISPATCH,RUN,COMPLETE} state_t;
    state_t state;
    task_desc_t active;
    logic [31:0] saved_a,saved_w,saved_sx,saved_sw,saved_y;
    memory_task_t memory_desc;
    logic [7:0] adapter_status;
    logic bridge_task_valid,bridge_task_ready,bridge_completion_valid,bridge_completion_ready;
    logic [31:0] bridge_completion_task_id;
    logic [3:0] bridge_completion_status;
    logic core_start,core_reset,core_start_ready,core_done,core_error;
    logic [15:0] cfg_m,cfg_n,cfg_k;
    logic req_valid,req_ready,req_scale,req_activation;
    logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group;
    logic in_valid,in_ready;logic [63:0] in_data;logic [7:0] in_keep;
    logic out_valid,out_ready,out_last;logic [15:0] out_m,out_n;logic signed [31:0] out_data;
    w4a8_task_adapter #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) adapter(
        .host_desc(active),.a_bytes(saved_a),.w_bytes(saved_w),.sx_bytes(saved_sx),
        .sw_bytes(saved_sw),.y_bytes(saved_y),.memory_desc(memory_desc),.status(adapter_status));
    assign task_ready=state==IDLE && !rst;
    assign completion_valid=state==COMPLETE && !rst;
    assign result_available=completion_valid && completion_status==STATUS_OK;
    assign bridge_task_valid=state==DISPATCH && !rst;
    assign bridge_completion_ready=state==RUN && !rst;
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;active<='0;saved_a<=0;saved_w<=0;saved_sx<=0;saved_sw<=0;saved_y<=0;
            completion_task_id<=0;completion_status<=STATUS_OK;elapsed_cycles<=0;
        end else begin
            if(state!=IDLE && state!=COMPLETE) elapsed_cycles<=elapsed_cycles+1;
            case(state)
                IDLE:if(task_valid) begin
                    active<=task_desc;saved_a<=a_bytes;saved_w<=w_bytes;saved_sx<=sx_bytes;
                    saved_sw<=sw_bytes;saved_y<=y_bytes;completion_task_id<=task_desc.task_id;
                    completion_status<=STATUS_OK;elapsed_cycles<=0;state<=CHECK;
                end
                CHECK:if(adapter_status==STATUS_OK) state<=DISPATCH;
                    else begin completion_status<=adapter_status;state<=COMPLETE;end
                DISPATCH:if(bridge_task_ready) state<=RUN;
                RUN:if(bridge_completion_valid) begin
                    if(bridge_completion_task_id!=active.task_id) completion_status<=STATUS_MEMORY_PROTOCOL;
                    else case(bridge_completion_status)
                        MEM_OK:completion_status<=STATUS_OK;
                        MEM_BAD_TASK:completion_status<=STATUS_BAD_REGION;
                        MEM_READ_ERROR:completion_status<=STATUS_READ_ERROR;
                        MEM_WRITE_ERROR:completion_status<=STATUS_WRITE_ERROR;
                        MEM_CORE_ERROR:completion_status<=STATUS_CORE_ERROR;
                        default:completion_status<=STATUS_MEMORY_PROTOCOL;
                    endcase
                    state<=COMPLETE;
                end
                COMPLETE:if(completion_ready) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
    w4a8_memory_bridge #(.ADDR_WIDTH(ADDR_WIDTH),.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),.GROUP_SIZE(GROUP_SIZE),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) bridge(
        .clk(clk),.rst(rst),.task_valid(bridge_task_valid),.task_ready(bridge_task_ready),.task_desc(memory_desc),
        .completion_valid(bridge_completion_valid),.completion_ready(bridge_completion_ready),
        .completion_task_id(bridge_completion_task_id),.completion_status(bridge_completion_status),
        .core_start(core_start),.core_reset(core_reset),.core_start_ready(core_start_ready),
        .core_done(core_done),.core_error(core_error),.cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),
        .req_valid(req_valid),.req_ready(req_ready),.req_m(req_m),.req_n(req_n),.req_k(req_k),
        .req_ml(req_ml),.req_nl(req_nl),.req_kl(req_kl),.req_group(req_group),
        .req_scale(req_scale),.req_activation(req_activation),.in_valid(in_valid),.in_ready(in_ready),
        .in_data(in_data),.in_keep(in_keep),.out_valid(out_valid),.out_ready(out_ready),
        .out_m(out_m),.out_n(out_n),.out_last(out_last),.out_data(out_data),
        .arvalid(arvalid),.arready(arready),.araddr(araddr),.arid(arid),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .rvalid(rvalid),.rready(rready),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast),
        .awvalid(awvalid),.awready(awready),.awaddr(awaddr),.awid(awid),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .wvalid(wvalid),.wready(wready),.wdata(wdata),.wstrb(wstrb),.wlast(wlast),
        .bvalid(bvalid),.bready(bready),.bid(bid),.bresp(bresp),
        .cycles(),.read_bytes(),.write_bytes(),.read_bus_bytes(),.write_bus_bytes(),.packet_bytes(),
        .packet_bus_bytes(),.read_wait(),.write_wait(),.input_wait(),.output_wait(),.packet_high_water(),.write_high_water());
    w4a8_wave #(.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),.GROUP_SIZE(GROUP_SIZE),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) core(
        .clk(clk),.rst(rst || core_reset),.load_pause(load_pause),.post_pause(post_pause),.array_pause(array_pause),
        .start(core_start),.start_ready(core_start_ready),.busy(),.done(core_done),.error(core_error),
        .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.req_valid(req_valid),.req_ready(req_ready),
        .req_m(req_m),.req_n(req_n),.req_k(req_k),.req_ml(req_ml),.req_nl(req_nl),.req_kl(req_kl),
        .req_group(req_group),.req_scale(req_scale),.req_activation(req_activation),
        .in_valid(in_valid),.in_ready(in_ready),.in_data(in_data),.in_keep(in_keep),
        .out_valid(out_valid),.out_ready(out_ready),.out_m(out_m),.out_n(out_n),.out_last(out_last),.out_data(out_data));
endmodule
