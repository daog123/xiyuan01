// Storage-side adapter only. Connect core_reset OR system reset to w4a8_wave.
module w4a8_memory_bridge #(
    parameter integer ADDR_WIDTH=32,ROWS=4,COLS=4,TILE_K=8,GROUP_SIZE=32,
    parameter integer MAX_M=64,MAX_N=64,MAX_K=4096,BURST_READ=1,WEIGHT_CACHE=1,SX_CACHE=1
)(
    input logic clk,rst,
    input logic task_valid,output logic task_ready,input w4a8_memory_pkg::memory_task_t task_desc,
    output logic completion_valid,input logic completion_ready,
    output logic [31:0] completion_task_id,output logic [3:0] completion_status,
    output logic core_start,core_reset,input logic core_start_ready,core_done,core_error,
    output logic [15:0] cfg_m,cfg_n,cfg_k,
    input logic req_valid,output logic req_ready,
    input logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group,
    input logic req_scale,req_activation,
    output logic in_valid,input logic in_ready,output logic [63:0] in_data,output logic [7:0] in_keep,
    input logic out_valid,output logic out_ready,input logic [15:0] out_m,out_n,
    input logic out_last,input logic signed [31:0] out_data,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast,
    output logic awvalid,input logic awready,output logic [ADDR_WIDTH-1:0] awaddr,
    output wire [3:0] awid,output wire [7:0] awlen,output wire [2:0] awsize,output wire [1:0] awburst,
    output logic wvalid,input logic wready,output logic [63:0] wdata,
    output logic [7:0] wstrb,output wire wlast,
    input logic bvalid,output logic bready,input logic [3:0] bid,input logic [1:0] bresp,
    output logic [31:0] cycles,read_bytes,write_bytes,read_bus_bytes,write_bus_bytes,
    output logic [31:0] packet_bytes,packet_bus_bytes,read_wait,write_wait,input_wait,output_wait,
    output logic [3:0] packet_high_water,output logic write_high_water
);
    import w4a8_memory_pkg::*;
    initial begin
        if(ROWS<1 || COLS<1 || ROWS*COLS>64 || TILE_K<1 || TILE_K>4096 ||
            GROUP_SIZE<1 || GROUP_SIZE>4096 || MAX_M<1 || MAX_M>64 ||
            MAX_N<1 || MAX_N>64 || MAX_K<1 || MAX_K>4096)
            $fatal(1,"Unsupported memory bridge hardware parameters");
    end
    typedef enum logic [2:0] {IDLE,CHECK,LAUNCH,RUN,FAIL_DRAIN,COMPLETE} state_t;
    state_t state;
    memory_task_t desc;
    logic legal,packet_fault,read_fault,packet_idle,rd_idle,wr_idle;
    logic rd_valid,rd_ready,rsp_valid,rsp_ready,rsp_error;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [63:0] rsp_data;logic [3:0] rd_bytes,rsp_bytes;logic [15:0] rd_span;
    logic ack_valid,ack_error,wr_cmd_valid,wr_cmd_ready;
    logic done_seen,last_seen;
    logic [31:0] outputs,acks;
    logic [64:0] y_address;
    logic output_legal;
    logic [3:0] buffer_used;
    wire abort_task=state==FAIL_DRAIN;
    wire local_reset=rst || state==IDLE || state==COMPLETE;
    assign task_ready=state==IDLE && !rst;
    assign completion_valid=state==COMPLETE && !rst;
    assign completion_task_id=desc.task_id;
    assign core_reset=rst || state==IDLE || state==CHECK || state==FAIL_DRAIN || state==COMPLETE;
    assign core_start=state==LAUNCH && core_start_ready && !rst;
    assign cfg_m=desc.m;assign cfg_n=desc.n;assign cfg_k=desc.k;
    assign y_address=65'(desc.y_base)+65'(out_m)*65'(desc.y_stride)+4*65'(out_n);
    assign output_legal=out_m<desc.m && out_n<desc.n && outputs<32'(desc.m)*32'(desc.n) &&
        y_address+4<=65'(desc.y_base)+65'(desc.y_bytes) &&
        (!out_last || outputs+1==32'(desc.m)*32'(desc.n));
    assign out_ready=state==RUN && wr_cmd_ready && !rst;
    assign wr_cmd_valid=state==RUN && out_valid && output_legal && !rst;
    w4a8_memory_validate #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) validate(.desc(desc),.legal(legal));
    w4a8_memory_packet #(.ADDR_WIDTH(ADDR_WIDTH),.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),.GROUP_SIZE(GROUP_SIZE),.BURST_READ(BURST_READ),.WEIGHT_CACHE(WEIGHT_CACHE),.SX_CACHE(SX_CACHE)) packet(
        .clk(clk),.rst(local_reset),.enable(state==RUN),.abort_task(abort_task),.desc(desc),
        .req_valid(req_valid),.req_ready(req_ready),.req_m(req_m),.req_n(req_n),.req_k(req_k),
        .req_ml(req_ml),.req_nl(req_nl),.req_kl(req_kl),.req_group(req_group),
        .req_scale(req_scale),.req_activation(req_activation),
        .in_valid(in_valid),.in_ready(in_ready),.in_data(in_data),.in_keep(in_keep),
        .fault(packet_fault),.idle(packet_idle),.read_fault(read_fault),.buffer_used(buffer_used),
        .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_addr(rd_addr),.rd_bytes(rd_bytes),.rd_span(rd_span),.rsp_bytes(rsp_bytes),.rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),.rsp_data(rsp_data),.rsp_error(rsp_error));
    w4a8_axi_read_burst #(.ADDR_WIDTH(ADDR_WIDTH)) reader(.clk(clk),.rst(local_reset),.cmd_valid(rd_valid),.cmd_ready(rd_ready),.cmd_addr(rd_addr),.cmd_bytes(rd_bytes),.cmd_span(rd_span),.rsp_bytes(rsp_bytes),
        .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_data(rsp_data),.rsp_error(rsp_error),.idle(rd_idle),
        .arvalid(arvalid),.arready(arready),.araddr(araddr),.arid(arid),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .rvalid(rvalid),.rready(rready),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast));
    w4a8_axi_write #(.ADDR_WIDTH(ADDR_WIDTH)) writer(.clk(clk),.rst(local_reset),.cmd_valid(wr_cmd_valid),.cmd_ready(wr_cmd_ready),
        .cmd_addr(y_address[ADDR_WIDTH-1:0]),.cmd_data(out_data),.ack_valid(ack_valid),.ack_error(ack_error),.idle(wr_idle),
        .awvalid(awvalid),.awready(awready),.awaddr(awaddr),.awid(awid),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .wvalid(wvalid),.wready(wready),.wdata(wdata),.wstrb(wstrb),.wlast(wlast),
        .bvalid(bvalid),.bready(bready),.bid(bid),.bresp(bresp));
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;desc<='0;completion_status<=MEM_OK;outputs<=0;acks<=0;done_seen<=0;last_seen<=0;
            cycles<=0;read_bytes<=0;write_bytes<=0;read_bus_bytes<=0;write_bus_bytes<=0;
            packet_bytes<=0;packet_bus_bytes<=0;read_wait<=0;write_wait<=0;input_wait<=0;output_wait<=0;
            packet_high_water<=0;write_high_water<=0;
        end else begin
            if(state!=IDLE && state!=COMPLETE) cycles<=cycles+1;
            if(arvalid && arready) begin read_bytes<=read_bytes+((32'd1<<arsize)*(32'(arlen)+1));read_bus_bytes<=read_bus_bytes+8*(32'(arlen)+1);end
            if(wvalid && wready) begin write_bytes<=write_bytes+4;write_bus_bytes<=write_bus_bytes+8;end
            if(!rd_idle) read_wait<=read_wait+1;
            if(!wr_idle) begin write_wait<=write_wait+1;write_high_water<=1;end
            if(buffer_used>packet_high_water) packet_high_water<=buffer_used;
            if(in_valid && !in_ready) input_wait<=input_wait+1;
            if(out_valid && !out_ready && state==RUN) output_wait<=output_wait+1;
            if(in_valid && in_ready) begin
                packet_bus_bytes<=packet_bus_bytes+8;
                packet_bytes<=packet_bytes+32'(buffer_used);
            end
            case(state)
                IDLE:if(task_valid) begin
                    desc<=task_desc;completion_status<=MEM_OK;state<=CHECK;
                    outputs<=0;acks<=0;done_seen<=0;last_seen<=0;
                    cycles<=0;read_bytes<=0;write_bytes<=0;read_bus_bytes<=0;write_bus_bytes<=0;
                    packet_bytes<=0;packet_bus_bytes<=0;read_wait<=0;write_wait<=0;input_wait<=0;output_wait<=0;
                    packet_high_water<=0;write_high_water<=0;
                end
                CHECK:if(legal) state<=LAUNCH;else begin completion_status<=MEM_BAD_TASK;state<=COMPLETE;end
                LAUNCH:if(core_start_ready) state<=RUN;
                RUN:begin
                    if(core_done) done_seen<=1;
                    if(out_valid && out_ready) begin outputs<=outputs+1;if(out_last) last_seen<=1;end
                    if(ack_valid) acks<=acks+1;
                    // Error priority is deterministic; drain all external transactions before recording it.
                    if(read_fault) begin completion_status<=MEM_READ_ERROR;state<=FAIL_DRAIN;end
                    else if(ack_valid && ack_error) begin completion_status<=MEM_WRITE_ERROR;state<=FAIL_DRAIN;end
                    else if(core_error) begin completion_status<=MEM_CORE_ERROR;state<=FAIL_DRAIN;end
                    else if(packet_fault || (out_valid && out_ready && !output_legal) ||
                        (done_seen && (outputs!=32'(desc.m)*32'(desc.n) || !last_seen))) begin
                        completion_status<=MEM_PROTOCOL_ERROR;state<=FAIL_DRAIN;
                    end else if(done_seen && last_seen && outputs==32'(desc.m)*32'(desc.n) &&
                        acks==outputs && rd_idle && wr_idle && packet_idle && !ack_valid) state<=COMPLETE;
                end
                FAIL_DRAIN:if(rd_idle && wr_idle && !ack_valid) state<=COMPLETE;
                COMPLETE:if(completion_ready) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
