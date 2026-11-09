// One host submission and one AXI owner across linear, FFN, KV and attention.
module llm_top #(parameter integer ADDR_WIDTH=64,GROUP_SIZE=32,ROWS=4,COLS=4,TILE_K=32,
    MAX_M=64,MAX_N=64,MAX_K=4096,MAX_H=64,CAPACITY=512,MAX_DIM=64,MAX_TOKENS=16)(
    input logic clk,rst,job_valid,output logic job_ready,input logic [7:0] job_opcode,
    input accelerator_pkg::bounded_task_t linear_task,input accelerator_pkg::ffn_plan_t ffn_plan,
    input kv_cache_pkg::kv_config_t kv_config,input kv_cache_pkg::kv_command_t kv_command,
    input attention_pkg::attention_task_t attention_task,
    input logic append_valid,output logic append_ready,input logic [7:0] append_data,input logic append_last,
    output logic read_valid,input logic read_ready,output logic [7:0] read_data,output logic read_last,
    input logic q_valid,output logic q_ready,input logic signed [7:0] q_data,input logic [15:0] q_scale,input logic q_last,
    input logic load_pause,post_pause,array_pause,
    output logic completion_valid,input logic completion_ready,output logic [31:0] completion_task_id,
    output logic [7:0] completion_status,output logic result_available,output logic configured,output logic [3:0] stage,
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
    import accelerator_pkg::*;import task_desc_pkg::*;
    typedef enum logic [2:0] {IDLE,CHECK_GRAPH,ISSUE,RUN,REJECT} state_t;
    state_t state;logic [7:0] opcode;
    bounded_task_t saved_linear;ffn_plan_t saved_ffn;kv_cache_pkg::kv_config_t saved_cfg;
    kv_cache_pkg::kv_command_t saved_cmd;attention_pkg::attention_task_t saved_attention;
    logic linear_ready,linear_done,kv_cfg_ready,kv_cmd_ready,query_ready,attention_done;
    logic [31:0] linear_id,attention_id,reject_id;logic [7:0] linear_status,attention_status;
    logic [3:0] linear_stage;
    logic [31:0] linear_elapsed,linear_activation_written,linear_scale_written;
    logic graph_attention;
    logic [7:0] reject_status;
    kv_cache_pkg::kv_config_t current_cfg;
    wire graph_active=opcode==OP_Q_ATTENTION;
    wire attention_owner=opcode>=OP_ATTENTION && (!graph_active || graph_attention);
    logic graph_alias;
    always_comb begin
        graph_alias=w4a8_memory_pkg::overlaps(saved_linear.desc.y_addr,saved_linear.y_bytes,saved_attention.y_addr,saved_attention.y_bytes);
        for(integer p=0;p<4;p++) begin
            if(w4a8_memory_pkg::overlaps(saved_linear.desc.y_addr,saved_linear.y_bytes,current_cfg.base[p],current_cfg.bytes[p]) ||
                w4a8_memory_pkg::overlaps(saved_attention.y_addr,saved_attention.y_bytes,current_cfg.base[p],current_cfg.bytes[p])) graph_alias=1;
        end
        if(w4a8_memory_pkg::overlaps(saved_attention.y_addr,saved_attention.y_bytes,saved_linear.desc.a_addr,saved_linear.a_bytes) ||
            w4a8_memory_pkg::overlaps(saved_attention.y_addr,saved_attention.y_bytes,saved_linear.desc.w_addr,saved_linear.w_bytes) ||
            w4a8_memory_pkg::overlaps(saved_attention.y_addr,saved_attention.y_bytes,saved_linear.desc.sx_addr,saved_linear.sx_bytes) ||
            w4a8_memory_pkg::overlaps(saved_attention.y_addr,saved_attention.y_bytes,saved_linear.desc.sw_addr,saved_linear.sw_bytes)) graph_alias=1;
    end
    assign job_ready=state==IDLE && !rst;
    assign completion_valid=!rst && (state==REJECT || (state==RUN && (attention_owner?attention_done:linear_done))) &&
        !(graph_active && !graph_attention && state==RUN && linear_status==STATUS_OK);
    assign completion_task_id=state==REJECT?reject_id:graph_active?saved_attention.task_id:attention_owner?attention_id:linear_id;
    assign completion_status=state==REJECT?reject_status:attention_owner?attention_status:linear_status;
    assign result_available=completion_valid && completion_status==STATUS_OK;
    assign activation_written=attention_owner?0:linear_activation_written;
    assign scale_written=attention_owner?0:linear_scale_written;
    assign stage=state==IDLE?0:graph_active && !graph_attention?1:!attention_owner?linear_stage:(opcode==OP_ATTENTION || graph_active)?5:opcode==OP_KV_CONFIG?6:7;
    always_ff @(posedge clk) begin
        if(rst) begin state<=IDLE;opcode<=0;saved_linear<='0;saved_ffn<='0;saved_cfg<='0;saved_cmd<='0;saved_attention<='0;reject_id<=0;elapsed_cycles<=0;graph_attention<=0;reject_status<=STATUS_BAD_FLAGS;current_cfg<='0;end
        else begin
        if(state==RUN && opcode==OP_KV_CONFIG && attention_done && attention_status==STATUS_OK)current_cfg<=saved_cfg;
        if((state==CHECK_GRAPH || state==ISSUE || state==RUN) && !completion_valid) elapsed_cycles<=elapsed_cycles+1;
        case(state)
            IDLE:if(job_valid) begin
                saved_linear<=linear_task;saved_ffn<=ffn_plan;saved_cfg<=kv_config;saved_cmd<=kv_command;saved_attention<=attention_task;
                opcode<=job_opcode;graph_attention<=0;reject_status<=STATUS_BAD_FLAGS;
                reject_id<=job_opcode==OP_KV_CONFIG?kv_config.config_id:job_opcode==OP_KV_COMMAND?kv_command.task_id:
                    job_opcode==OP_LINEAR?linear_task.desc.task_id:job_opcode==OP_FFN?ffn_plan.task_id:attention_task.task_id;
                elapsed_cycles<=0;
                if(job_opcode>OP_Q_ATTENTION || (job_opcode==OP_Q_ATTENTION && !configured) || (job_opcode==OP_KV_CONFIG && configured) || (job_opcode==OP_KV_COMMAND && !configured)) state<=REJECT;
                else state<=job_opcode==OP_Q_ATTENTION?CHECK_GRAPH:ISSUE;
            end
            CHECK_GRAPH:begin
                if(saved_attention.q_source!=2)begin reject_status<=STATUS_BAD_FLAGS;state<=REJECT;end
                else if(saved_linear.desc.m!=1 || saved_linear.desc.n!=saved_attention.dimension ||
                    saved_attention.dimension==0 || saved_attention.dimension>MAX_DIM || saved_attention.tokens==0 ||
                    saved_attention.tokens>MAX_TOKENS || saved_attention.score_scale==0 ||
                    saved_attention.layer>=current_cfg.layers || saved_attention.head>=current_cfg.heads ||
                    saved_attention.dimension!=current_cfg.dimension)begin reject_status<=STATUS_BAD_DIM;state<=REJECT;end
                else if(graph_alias || saved_attention.q_addr!=saved_linear.desc.y_addr || saved_attention.q_bytes!=saved_linear.y_bytes ||
                    saved_attention.qs_addr!=0 || saved_attention.qs_bytes!=0 || saved_attention.q_addr[1:0]!=0 ||
                    saved_attention.y_addr[1:0]!=0 || saved_attention.q_bytes<4*32'(saved_attention.dimension) ||
                    saved_attention.y_bytes<4*32'(saved_attention.dimension) ||
                    65'(saved_attention.q_addr)+65'(saved_attention.q_bytes)>(65'd1<<ADDR_WIDTH) ||
                    65'(saved_attention.y_addr)+65'(saved_attention.y_bytes)>(65'd1<<ADDR_WIDTH))begin reject_status<=STATUS_BAD_REGION;state<=REJECT;end
                else state<=ISSUE;
            end
            ISSUE:if((!attention_owner && linear_ready) || ((opcode==OP_ATTENTION || graph_active && graph_attention) && query_ready) ||
                (opcode==OP_KV_CONFIG && kv_cfg_ready) || (opcode==OP_KV_COMMAND && kv_cmd_ready)) state<=RUN;
            RUN:if(graph_active && !graph_attention && linear_done && linear_status==STATUS_OK)begin graph_attention<=1;state<=ISSUE;end
                else if(completion_valid && completion_ready) state<=IDLE;
            REJECT:if(completion_ready) state<=IDLE;
        endcase
        end
    end
    wire arvalid_l,arvalid_a;
    assign arvalid=attention_owner?arvalid_a:arvalid_l;
    wire [ADDR_WIDTH-1:0] araddr_l,araddr_a;
    assign araddr=attention_owner?araddr_a:araddr_l;
    wire [4-1:0] arid_l,arid_a;
    assign arid=attention_owner?arid_a:arid_l;
    wire [8-1:0] arlen_l,arlen_a;
    assign arlen=attention_owner?arlen_a:arlen_l;
    wire [3-1:0] arsize_l,arsize_a;
    assign arsize=attention_owner?arsize_a:arsize_l;
    wire [2-1:0] arburst_l,arburst_a;
    assign arburst=attention_owner?arburst_a:arburst_l;
    wire rready_l,rready_a;
    assign rready=attention_owner?rready_a:rready_l;
    wire awvalid_l,awvalid_a;
    assign awvalid=attention_owner?awvalid_a:awvalid_l;
    wire [ADDR_WIDTH-1:0] awaddr_l,awaddr_a;
    assign awaddr=attention_owner?awaddr_a:awaddr_l;
    wire [4-1:0] awid_l,awid_a;
    assign awid=attention_owner?awid_a:awid_l;
    wire [8-1:0] awlen_l,awlen_a;
    assign awlen=attention_owner?awlen_a:awlen_l;
    wire [3-1:0] awsize_l,awsize_a;
    assign awsize=attention_owner?awsize_a:awsize_l;
    wire [2-1:0] awburst_l,awburst_a;
    assign awburst=attention_owner?awburst_a:awburst_l;
    wire wvalid_l,wvalid_a;
    assign wvalid=attention_owner?wvalid_a:wvalid_l;
    wire [64-1:0] wdata_l,wdata_a;
    assign wdata=attention_owner?wdata_a:wdata_l;
    wire [8-1:0] wstrb_l,wstrb_a;
    assign wstrb=attention_owner?wstrb_a:wstrb_l;
    wire wlast_l,wlast_a;
    assign wlast=attention_owner?wlast_a:wlast_l;
    wire bready_l,bready_a;
    assign bready=attention_owner?bready_a:bready_l;
    accelerator_top #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K),.MAX_H(MAX_H),.CAPACITY(CAPACITY)) linear_ffn(
        .clk(clk),.rst(rst),.job_valid(state==ISSUE && !attention_owner),.job_ready(linear_ready),.job_opcode(graph_active?OP_LINEAR:opcode),
        .linear_task(saved_linear),.ffn_plan(saved_ffn),.load_pause(load_pause),.post_pause(post_pause),.array_pause(array_pause),
        .completion_valid(linear_done),.completion_ready(state==RUN && !attention_owner && ((graph_active && linear_status==STATUS_OK) || completion_ready)),
        .completion_task_id(linear_id),.completion_status(linear_status),.result_available(),.stage(linear_stage),
        .elapsed_cycles(linear_elapsed),.activation_written(linear_activation_written),.scale_written(linear_scale_written),
        .arvalid(arvalid_l),
        .araddr(araddr_l),
        .arid(arid_l),
        .arlen(arlen_l),
        .arsize(arsize_l),
        .arburst(arburst_l),
        .rready(rready_l),
        .awvalid(awvalid_l),
        .awaddr(awaddr_l),
        .awid(awid_l),
        .awlen(awlen_l),
        .awsize(awsize_l),
        .awburst(awburst_l),
        .wvalid(wvalid_l),
        .wdata(wdata_l),
        .wstrb(wstrb_l),
        .wlast(wlast_l),
        .bready(bready_l),
        .arready(arready && !attention_owner),
        .rvalid(rvalid && !attention_owner),
        .rdata(rdata),
        .rid(rid),
        .rresp(rresp),
        .rlast(rlast),
        .awready(awready && !attention_owner),
        .wready(wready && !attention_owner),
        .bvalid(bvalid && !attention_owner),
        .bid(bid),
        .bresp(bresp));
    attention_kv_top #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_DIM(MAX_DIM),.MAX_TOKENS(MAX_TOKENS)) attention(
        .clk(clk),.rst(rst),.cfg_valid(state==ISSUE && opcode==OP_KV_CONFIG),.cfg_ready(kv_cfg_ready),.cfg_desc(saved_cfg),
        .cmd_valid(state==ISSUE && opcode==OP_KV_COMMAND),.cmd_ready(kv_cmd_ready),.cmd_desc(saved_cmd),
        .query_valid(state==ISSUE && (opcode==OP_ATTENTION || graph_active && graph_attention)),.query_ready(query_ready),.query_desc(saved_attention),
        .append_valid(append_valid && state==RUN),.append_ready(append_ready),.append_data(append_data),.append_last(append_last),
        .read_valid(read_valid),.read_ready(read_ready),.read_data(read_data),.read_last(read_last),
        .q_valid(q_valid && state==RUN),.q_ready(q_ready),.q_data(q_data),.q_scale(q_scale),.q_last(q_last),
        .completion_valid(attention_done),.completion_ready(state==RUN && attention_owner && completion_ready),
        .completion_task_id(attention_id),.completion_status(attention_status),.result_available(),.configured(configured),
        .arvalid(arvalid_a),
        .araddr(araddr_a),
        .arid(arid_a),
        .arlen(arlen_a),
        .arsize(arsize_a),
        .arburst(arburst_a),
        .rready(rready_a),
        .awvalid(awvalid_a),
        .awaddr(awaddr_a),
        .awid(awid_a),
        .awlen(awlen_a),
        .awsize(awsize_a),
        .awburst(awburst_a),
        .wvalid(wvalid_a),
        .wdata(wdata_a),
        .wstrb(wstrb_a),
        .wlast(wlast_a),
        .bready(bready_a),
        .arready(arready && attention_owner),
        .rvalid(rvalid && attention_owner),
        .rdata(rdata),
        .rid(rid),
        .rresp(rresp),
        .rlast(rlast),
        .awready(awready && attention_owner),
        .wready(wready && attention_owner),
        .bvalid(bvalid && attention_owner),
        .bid(bid),
        .bresp(bresp));
endmodule
