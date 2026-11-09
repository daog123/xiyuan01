// Transactional KV storage plus bounded attention and confirmed Q16.16 writeback.
module attention_kv_top #(parameter integer ADDR_WIDTH=64,GROUP_SIZE=32,
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
    import task_desc_pkg::*;import kv_cache_pkg::*;
    typedef enum logic [2:0] {IDLE,EXTERNAL,CHECK,QLOAD,START,QUERY,DRAIN,COMPLETE} state_t;
    state_t state;
    kv_config_t saved_cfg,candidate;
    attention_pkg::attention_task_t active;
    logic core_query_ready,core_cmd_valid,core_cmd_ready,core_read_ready,core_out_valid,core_out_ready,core_out_last;
    logic core_completion,core_completion_ready;logic [7:0] core_status;
    logic [15:0] core_out_index;logic signed [31:0] core_out_data;
    kv_command_t core_cmd;
    logic kv_cfg_ready,kv_cmd_ready,kv_completion,kv_completion_ready,kv_read_valid,kv_read_last;
    logic [7:0] kv_read_data;logic [31:0] kv_completion_id;logic [3:0] kv_status;
    logic metadata_valid;logic [15:0] committed;
    logic done_seen,wr_ready,wr_idle,ack_valid,ack_error;
    logic [31:0] outputs,acks;
    wire query_owner=state==CHECK || state==START || state==QUERY || state==DRAIN;
    assign query_ready=state==IDLE && !rst;
    assign cfg_ready=state==IDLE && !query_valid && kv_cfg_ready && !rst;
    assign cmd_ready=state==IDLE && !query_valid && !cfg_valid && kv_cmd_ready && !rst;
    assign completion_valid=state==COMPLETE && !rst;
    assign result_available=completion_valid && completion_status==STATUS_OK;
    assign read_valid=state==EXTERNAL && kv_read_valid;
    assign read_data=kv_read_data;assign read_last=kv_read_last;
    assign core_cmd_ready=state==QUERY && kv_cmd_ready;
    assign kv_completion_ready=state==EXTERNAL || (state==QUERY && core_completion_ready);
    assign core_out_ready=state==QUERY && wr_ready && !ack_valid;
    wire bad_region=active.y_addr[1:0]!=0 || active.y_bytes<4*32'(active.dimension) ||
        65'(active.y_addr)+65'(active.y_bytes)>(65'd1<<ADDR_WIDTH) || active.y_bytes==0;
    logic aliases;
    logic core_q_ready,dma_q_valid,dma_q_last,dma_loaded,dma_failed,dma_idle;
    logic signed [7:0] dma_q_data;logic [15:0] dma_q_scale;
    wire memory_q=active.q_source!=0;
    wire q_owner=state==QLOAD;
    wire bad_q_flags=active.q_source>2 || (active.q_source==0 &&
        (active.q_addr!=0 || active.qs_addr!=0 || active.q_bytes!=0 || active.qs_bytes!=0));
    wire bad_shape=!metadata_valid || active.tokens==0 || active.tokens>committed || active.tokens>MAX_TOKENS ||
        active.dimension==0 || active.dimension>MAX_DIM || active.dimension!=saved_cfg.dimension || active.score_scale==0;
    wire bad_q_region=memory_q && (active.q_bytes<(active.q_source==2?4:1)*32'(active.dimension) || active.q_bytes==0 ||
        65'(active.q_addr)+65'(active.q_bytes)>(65'd1<<ADDR_WIDTH) ||
        w4a8_memory_pkg::overlaps(active.y_addr,active.y_bytes,active.q_addr,active.q_bytes) ||
        (active.q_source==2 && (active.q_addr[1:0]!=0 || active.qs_addr!=0 || active.qs_bytes!=0)) ||
        (active.q_source==1 && (active.qs_bytes<2*((32'(active.dimension)+GROUP_SIZE-1)/GROUP_SIZE) || active.qs_bytes==0 ||
            65'(active.qs_addr)+65'(active.qs_bytes)>(65'd1<<ADDR_WIDTH) ||
            w4a8_memory_pkg::overlaps(active.q_addr,active.q_bytes,active.qs_addr,active.qs_bytes) ||
            w4a8_memory_pkg::overlaps(active.y_addr,active.y_bytes,active.qs_addr,active.qs_bytes))));
    assign q_ready=state==QUERY && !memory_q && core_q_ready;
    wire arvalid_k,arvalid_q,rready_k,rready_q;
    wire [ADDR_WIDTH-1:0] araddr_k,araddr_q;
    wire [3:0] arid_k,arid_q;wire [7:0] arlen_k,arlen_q;
    wire [2:0] arsize_k,arsize_q;wire [1:0] arburst_k,arburst_q;
    assign arvalid=q_owner?arvalid_q:arvalid_k;
    assign araddr=q_owner?araddr_q:araddr_k;
    assign arid=q_owner?arid_q:arid_k;
    assign arlen=q_owner?arlen_q:arlen_k;
    assign arsize=q_owner?arsize_q:arsize_k;
    assign arburst=q_owner?arburst_q:arburst_k;
    assign rready=q_owner?rready_q:rready_k;
    always_comb begin
        aliases=0;
        for(integer p=0;p<4;p++) if(w4a8_memory_pkg::overlaps(active.y_addr,active.y_bytes,saved_cfg.base[p],saved_cfg.bytes[p])) aliases=1;
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;saved_cfg<='0;candidate<='0;active<='0;completion_task_id<=0;completion_status<=0;
            done_seen<=0;outputs<=0;acks<=0;
        end else case(state)
            IDLE:begin
                completion_status<=STATUS_OK;done_seen<=0;outputs<=0;acks<=0;
                if(query_valid && query_ready) begin active<=query_desc;completion_task_id<=query_desc.task_id;state<=CHECK;end
                else if(cfg_valid && cfg_ready) begin candidate<=cfg_desc;completion_task_id<=cfg_desc.config_id;state<=EXTERNAL;end
                else if(cmd_valid && cmd_ready) begin completion_task_id<=cmd_desc.task_id;state<=EXTERNAL;end
            end
            EXTERNAL:if(kv_completion) begin
                if(kv_status==KV_OK) begin completion_status<=STATUS_OK;if(!configured) saved_cfg<=candidate;end
                else completion_status<=kv_status==KV_READ_ERROR?STATUS_READ_ERROR:kv_status==KV_WRITE_ERROR?STATUS_WRITE_ERROR:STATUS_BAD_REGION;
                // Configuration is committed in the KV block before its success record.
                if(kv_status==0 && candidate.config_id==kv_completion_id) saved_cfg<=candidate;
                state<=COMPLETE;
            end
            CHECK:if(bad_q_flags) begin completion_status<=STATUS_BAD_FLAGS;state<=COMPLETE;end
                else if(bad_region || aliases || bad_q_region) begin completion_status<=STATUS_BAD_REGION;state<=COMPLETE;end
                else if(bad_shape) begin completion_status<=STATUS_BAD_DIM;state<=COMPLETE;end
                else state<=memory_q?QLOAD:START;
            QLOAD:if(dma_failed && dma_idle) begin completion_status<=STATUS_READ_ERROR;state<=DRAIN;end
                else if(dma_loaded && dma_idle) state<=START;
            START:if(core_query_ready) state<=QUERY;
            QUERY:begin
                if(core_out_valid && core_out_ready) outputs<=outputs+1;
                if(ack_valid) begin
                    acks<=acks+1;
                    if(ack_error) begin completion_status<=STATUS_WRITE_ERROR;state<=DRAIN;end
                end
                if(core_completion) begin
                    done_seen<=1;
                    if(core_status!=0) begin completion_status<=core_status;state<=DRAIN;end
                end
                if(done_seen && wr_idle && !ack_valid) begin
                    if(outputs!=32'(active.dimension) || acks!=outputs) completion_status<=STATUS_MEMORY_PROTOCOL;
                    state<=COMPLETE;
                end
            end
            DRAIN:if(wr_idle && !ack_valid && (kv_cmd_ready || kv_cfg_ready)) state<=COMPLETE;
            COMPLETE:if(completion_ready) state<=IDLE;
            default:state<=IDLE;
        endcase
    end
    wire awvalid_k,awvalid_y;
    assign awvalid=query_owner?awvalid_y:awvalid_k;
    wire [ADDR_WIDTH-1:0] awaddr_k,awaddr_y;
    assign awaddr=query_owner?awaddr_y:awaddr_k;
    wire [4-1:0] awid_k,awid_y;
    assign awid=query_owner?awid_y:awid_k;
    wire [8-1:0] awlen_k,awlen_y;
    assign awlen=query_owner?awlen_y:awlen_k;
    wire [3-1:0] awsize_k,awsize_y;
    assign awsize=query_owner?awsize_y:awsize_k;
    wire [2-1:0] awburst_k,awburst_y;
    assign awburst=query_owner?awburst_y:awburst_k;
    wire wvalid_k,wvalid_y;
    assign wvalid=query_owner?wvalid_y:wvalid_k;
    wire [64-1:0] wdata_k,wdata_y;
    assign wdata=query_owner?wdata_y:wdata_k;
    wire [8-1:0] wstrb_k,wstrb_y;
    assign wstrb=query_owner?wstrb_y:wstrb_k;
    wire wlast_k,wlast_y;
    assign wlast=query_owner?wlast_y:wlast_k;
    wire bready_k,bready_y;
    assign bready=query_owner?bready_y:bready_k;
    kv_cache #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_DIM(MAX_DIM),.MAX_TOKENS(MAX_TOKENS),
        .MAX_LAYERS(MAX_LAYERS),.MAX_HEADS(MAX_HEADS)) cache(
        .clk(clk),.rst(rst),.cfg_valid(state==IDLE && !query_valid && cfg_valid),.cfg_ready(kv_cfg_ready),.cfg_desc(cfg_desc),
        .cmd_valid(state==QUERY?core_cmd_valid:(state==IDLE && !query_valid && !cfg_valid && cmd_valid)),
        .cmd_ready(kv_cmd_ready),.cmd_desc(state==QUERY?core_cmd:cmd_desc),
        .append_valid(state==EXTERNAL && append_valid),.append_ready(append_ready),.append_data(append_data),.append_last(append_last),
        .read_valid(kv_read_valid),.read_ready(state==QUERY?core_read_ready:read_ready),.read_data(kv_read_data),.read_last(kv_read_last),
        .completion_valid(kv_completion),.completion_ready(kv_completion_ready),.completion_id(kv_completion_id),.completion_status(kv_status),
        .configured(configured),.query_layer(active.layer),.query_head(active.head),.query_valid(metadata_valid),.query_length(committed),
        .arvalid(arvalid_k),.arready(arready && !q_owner),.araddr(araddr_k),.arid(arid_k),.arlen(arlen_k),.arsize(arsize_k),.arburst(arburst_k),
        .rvalid(rvalid && !q_owner),.rready(rready_k),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast),
        .awvalid(awvalid_k),
        .awaddr(awaddr_k),
        .awid(awid_k),
        .awlen(awlen_k),
        .awsize(awsize_k),
        .awburst(awburst_k),
        .wvalid(wvalid_k),
        .wdata(wdata_k),
        .wstrb(wstrb_k),
        .wlast(wlast_k),
        .bready(bready_k),
        .awready(awready && !query_owner),.wready(wready && !query_owner),.bvalid(bvalid && !query_owner),.bid(bid),.bresp(bresp),
        .cycles(),.accepted_bytes(),.acknowledged_bytes(),.returned_bytes(),.read_wait(),.write_wait());
    attention_q_dma #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_DIM(MAX_DIM)) q_loader(
        .clk(clk),.rst(rst || state==IDLE || state==COMPLETE),.load_valid(state==QLOAD),.load_ready(),.desc(active),
        .loaded(dma_loaded),.failed(dma_failed),.idle(dma_idle),.send_enable(state==QUERY),
        .out_valid(dma_q_valid),.out_ready(core_q_ready && state==QUERY),.out_data(dma_q_data),.out_scale(dma_q_scale),.out_last(dma_q_last),
        .arvalid(arvalid_q),.arready(arready && q_owner),.araddr(araddr_q),.arid(arid_q),.arlen(arlen_q),.arsize(arsize_q),.arburst(arburst_q),
        .rvalid(rvalid && q_owner),.rready(rready_q),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast));
    attention_compute #(.GROUP_SIZE(GROUP_SIZE),.MAX_DIM(MAX_DIM),.MAX_TOKENS(MAX_TOKENS)) compute(
        .clk(clk),.rst(rst || state==IDLE || state==DRAIN || state==COMPLETE),.query_valid(state==START),.query_ready(core_query_ready),
        .query_desc(active),.metadata_valid(metadata_valid),.committed_tokens(committed),.cache_dimension(saved_cfg.dimension),
        .q_valid(state==QUERY && (memory_q?dma_q_valid:q_valid)),.q_ready(core_q_ready),
        .q_data(memory_q?dma_q_data:q_data),.q_scale(memory_q?dma_q_scale:q_scale),.q_last(memory_q?dma_q_last:q_last),
        .cmd_valid(core_cmd_valid),.cmd_ready(core_cmd_ready),.cmd_desc(core_cmd),
        .cache_valid(kv_read_valid),.cache_ready(core_read_ready),.cache_data(kv_read_data),.cache_last(kv_read_last),
        .cache_completion_valid(kv_completion),.cache_completion_ready(core_completion_ready),
        .cache_completion_id(kv_completion_id),.cache_completion_status(kv_status),
        .out_valid(core_out_valid),.out_ready(core_out_ready),.out_data(core_out_data),.out_index(core_out_index),.out_last(core_out_last),
        .completion_valid(core_completion),.completion_ready(state==QUERY),.completion_status(core_status));
    w4a8_axi_write #(.ADDR_WIDTH(ADDR_WIDTH)) writeback(
        .clk(clk),.rst(rst || state==IDLE || state==COMPLETE),.cmd_valid(core_out_valid && core_out_ready),.cmd_ready(wr_ready),
        .cmd_addr(ADDR_WIDTH'(active.y_addr+4*64'(core_out_index))),.cmd_data(core_out_data),
        .ack_valid(ack_valid),.ack_error(ack_error),.idle(wr_idle),
        .awvalid(awvalid_y),
        .awaddr(awaddr_y),
        .awid(awid_y),
        .awlen(awlen_y),
        .awsize(awsize_y),
        .awburst(awburst_y),
        .wvalid(wvalid_y),
        .wdata(wdata_y),
        .wstrb(wstrb_y),
        .wlast(wlast_y),
        .bready(bready_y),
        .awready(awready && query_owner),.wready(wready && query_owner),.bvalid(bvalid && query_owner),.bid(bid),.bresp(bresp));
endmodule
