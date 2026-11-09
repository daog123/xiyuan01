// One host submission and one AXI owner across linear, FFN, KV and attention.
module llm_graph_top #(parameter integer ADDR_WIDTH=64,GROUP_SIZE=32,ROWS=4,COLS=4,TILE_K=32,
    MAX_M=64,MAX_N=64,MAX_K=4096,MAX_H=64,CAPACITY=512,MAX_DIM=64,MAX_TOKENS=16)(
    input logic clk,rst,job_valid,output logic job_ready,input logic [7:0] job_opcode,
    input accelerator_pkg::bounded_task_t linear_task,input accelerator_pkg::ffn_plan_t ffn_plan,
    input kv_cache_pkg::kv_config_t kv_config,input kv_cache_pkg::kv_command_t kv_command,
    input attention_pkg::attention_task_t attention_task,
    input llm_graph_pkg::qkv_plan_t qkv_plan,
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
    import task_desc_pkg::*;import accelerator_pkg::*;import llm_graph_pkg::*;
    typedef enum logic [4:0] {IDLE,FWD_ISSUE,FWD_RUN,CHECK_PLAN,CHECK_TASK,CHECK_ALIAS,
        K_ISSUE,K_RUN,KQ_START,KQ_RUN,V_ISSUE,V_RUN,VQ_START,VQ_RUN,
        APPEND_ISSUE,APPEND_RUN,Q_ISSUE,Q_RUN,COMPLETE} state_t;
    state_t state;
    logic [7:0] saved_opcode,status;logic [3:0] last_graph_stage;
    bounded_task_t selected_check,child_linear;
    kv_cache_pkg::kv_config_t saved_cfg,current_cfg;
    kv_cache_pkg::kv_command_t child_cmd;
    attention_pkg::attention_task_t child_query,quant_desc;
    qkv_plan_t plan;
    logic [1:0] check_index,write_index;
    logic [4:0] alias_index;
    logic [31:0] root_id;
    logic child_valid,child_ready,child_done,child_completion_ready,child_result;
    logic [7:0] child_opcode,child_status,check_status;
    logic [31:0] child_id,child_elapsed,child_activations,child_scales;
    logic [3:0] child_stage;
    logic child_append_ready,child_read_valid,child_read_last,child_q_ready;
    logic [7:0] child_read_data;
    logic child_append_valid,child_append_last;logic [7:0] child_append_data;
    logic signed [7:0] kb[0:MAX_DIM-1],vb[0:MAX_DIM-1];
    localparam integer MG=(MAX_DIM+GROUP_SIZE-1)/GROUP_SIZE;
    logic [15:0] ks[0:MG-1],vs[0:MG-1],capture_index,stream_index;
    wire [15:0] groups=(plan.attention.dimension+GROUP_SIZE-1)/GROUP_SIZE;
    wire [16:0] stream_bytes=2*17'(plan.attention.dimension)+4*17'(groups);
    wire forward_owner=state==FWD_ISSUE || state==FWD_RUN;
    wire quant_owner=state==KQ_START || state==KQ_RUN || state==VQ_START || state==VQ_RUN;
    wire quant_v=state==VQ_START || state==VQ_RUN;
    wire graph_run=state==K_RUN || state==V_RUN || state==APPEND_RUN || state==Q_RUN;
    assign job_ready=state==IDLE && child_ready && !rst;
    assign completion_valid=!rst && (state==COMPLETE || state==FWD_RUN && child_done);
    assign completion_task_id=state==FWD_RUN?child_id:root_id;
    assign completion_status=state==FWD_RUN?child_status:status;
    assign result_available=completion_valid && completion_status==STATUS_OK;
    assign child_completion_ready=state==FWD_RUN?completion_ready:graph_run;
    assign activation_written=forward_owner?child_activations:0;
    assign scale_written=forward_owner?child_scales:0;
    assign append_ready=state==FWD_RUN && child_append_ready;
    assign read_valid=state==FWD_RUN && child_read_valid;
    assign read_data=child_read_data;assign read_last=child_read_last;
    assign q_ready=state==FWD_RUN && child_q_ready;
    always_comb begin
        stage=child_stage;
        if(state==IDLE)stage=0;
        else if(state==COMPLETE)stage=last_graph_stage;
        else if(!forward_owner)case(state)
            K_ISSUE,K_RUN:stage=8;
            KQ_START,KQ_RUN:stage=9;
            V_ISSUE,V_RUN:stage=10;
            VQ_START,VQ_RUN:stage=11;
            APPEND_ISSUE,APPEND_RUN:stage=12;
            Q_ISSUE,Q_RUN:stage=13;
            default:stage=0;
        endcase
        child_valid=state==IDLE && job_valid && job_opcode!=OP_QKV_ATTENTION && !rst || state==K_ISSUE || state==V_ISSUE || state==APPEND_ISSUE || state==Q_ISSUE;
        child_opcode=job_opcode;child_linear=linear_task;child_cmd=kv_command;child_query=attention_task;
        case(state)
            K_ISSUE,K_RUN:begin child_opcode=OP_LINEAR;child_linear=plan.k_task;end
            V_ISSUE,V_RUN:begin child_opcode=OP_LINEAR;child_linear=plan.v_task;end
            APPEND_ISSUE,APPEND_RUN:begin
                child_opcode=OP_KV_COMMAND;child_cmd='0;child_cmd.task_id=root_id;
                child_cmd.operation=kv_cache_pkg::KV_APPEND;child_cmd.layer=plan.attention.layer;
                child_cmd.head=plan.attention.head;child_cmd.token=plan.token;child_cmd.count=1;
            end
            Q_ISSUE,Q_RUN:begin child_opcode=OP_Q_ATTENTION;child_linear=plan.q_task;child_query=plan.attention;end
            default:;
        endcase
        selected_check=check_index==0?plan.q_task:check_index==1?plan.k_task:plan.v_task;
        // CHECK_PLAN proves these upper bits and M are constant before this
        // checker is used. Narrow them to avoid wide geometry multipliers.
        selected_check.desc.m=1;
        selected_check.desc.n={9'd0,plan.attention.dimension[6:0]};
        selected_check.desc.k={3'd0,plan.q_task.desc.k[12:0]};
        quant_desc='0;quant_desc.dimension=plan.attention.dimension;quant_desc.q_source=2;
        quant_desc.q_addr=quant_v?plan.v_task.desc.y_addr:plan.k_task.desc.y_addr;
        quant_desc.q_bytes=quant_v?plan.v_task.y_bytes:plan.k_task.y_bytes;
        child_append_valid=state==FWD_RUN?append_valid:state==APPEND_RUN && 17'(stream_index)<stream_bytes;
        child_append_data=append_data;child_append_last=append_last;
        if(state==APPEND_RUN)begin
            child_append_last=17'(stream_index)+1==stream_bytes;
            if(stream_index<plan.attention.dimension)child_append_data=kb[stream_index];
            else if(32'(stream_index)<2*32'(plan.attention.dimension))child_append_data=vb[stream_index-plan.attention.dimension];
            else if(32'(stream_index)<2*32'(plan.attention.dimension)+2*32'(groups))
                child_append_data=ks[(stream_index-2*plan.attention.dimension)/2][((stream_index-2*plan.attention.dimension)%2)*8 +:8];
            else child_append_data=vs[(stream_index-2*plan.attention.dimension-2*groups)/2][((stream_index-2*plan.attention.dimension-2*groups)%2)*8 +:8];
        end
    end
    w4a8_task_adapter #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(1),.MAX_N(MAX_N),.MAX_K(MAX_K)) validator(
        .host_desc(selected_check.desc),.a_bytes(selected_check.a_bytes),.w_bytes(selected_check.w_bytes),
        .sx_bytes(selected_check.sx_bytes),.sw_bytes(selected_check.sw_bytes),.y_bytes(selected_check.y_bytes),.memory_desc(),.status(check_status));
    logic [63:0] wb[0:3],ib[0:11],alias_base;logic [31:0] ws[0:3],isz[0:11],alias_bytes;
    always_comb begin
        wb[0]=plan.q_task.desc.y_addr;ws[0]=plan.q_task.y_bytes;
        wb[1]=plan.k_task.desc.y_addr;ws[1]=plan.k_task.y_bytes;
        wb[2]=plan.v_task.desc.y_addr;ws[2]=plan.v_task.y_bytes;
        wb[3]=plan.attention.y_addr;ws[3]=plan.attention.y_bytes;
        ib[0]=plan.q_task.desc.a_addr;isz[0]=plan.q_task.a_bytes;ib[1]=plan.q_task.desc.w_addr;isz[1]=plan.q_task.w_bytes;
        ib[2]=plan.q_task.desc.sx_addr;isz[2]=plan.q_task.sx_bytes;ib[3]=plan.q_task.desc.sw_addr;isz[3]=plan.q_task.sw_bytes;
        ib[4]=plan.k_task.desc.a_addr;isz[4]=plan.k_task.a_bytes;ib[5]=plan.k_task.desc.w_addr;isz[5]=plan.k_task.w_bytes;
        ib[6]=plan.k_task.desc.sx_addr;isz[6]=plan.k_task.sx_bytes;ib[7]=plan.k_task.desc.sw_addr;isz[7]=plan.k_task.sw_bytes;
        ib[8]=plan.v_task.desc.a_addr;isz[8]=plan.v_task.a_bytes;ib[9]=plan.v_task.desc.w_addr;isz[9]=plan.v_task.w_bytes;
        ib[10]=plan.v_task.desc.sx_addr;isz[10]=plan.v_task.sx_bytes;ib[11]=plan.v_task.desc.sw_addr;isz[11]=plan.v_task.sw_bytes;
        alias_base=0;alias_bytes=0;
        if(alias_index<12)begin alias_base=ib[alias_index];alias_bytes=isz[alias_index];end
        else if(alias_index<16)begin alias_base=current_cfg.base[alias_index-12];alias_bytes=current_cfg.bytes[alias_index-12];end
        else begin alias_base=wb[alias_index-16];alias_bytes=ws[alias_index-16];end
    end
    logic quant_ready,quant_loaded,quant_failed,quant_idle,quant_valid,quant_last;
    logic signed [7:0] quant_data;logic [15:0] quant_scale;
    wire quant_start=state==KQ_START || state==VQ_START;
    wire quant_send=state==KQ_RUN || state==VQ_RUN;
    always_ff @(posedge clk)begin
        if(rst)begin
            state<=IDLE;saved_opcode<=0;saved_cfg<='0;current_cfg<='0;
            plan<='0;root_id<=0;status<=0;elapsed_cycles<=0;
            check_index<=0;write_index<=0;alias_index<=0;capture_index<=0;stream_index<=0;last_graph_stage<=0;
        end else begin
            if(!forward_owner && stage>=8 && stage<=13)last_graph_stage<=stage;
            if(state!=IDLE && state!=COMPLETE && !completion_valid)elapsed_cycles<=elapsed_cycles+1;
            case(state)
                IDLE:if(job_valid && job_ready)begin
                    saved_opcode<=job_opcode;saved_cfg<=kv_config;
                    plan<=qkv_plan;
                    root_id<=qkv_plan.attention.task_id;status<=STATUS_OK;elapsed_cycles<=0;last_graph_stage<=0;
                    state<=job_opcode==OP_QKV_ATTENTION?CHECK_PLAN:FWD_RUN;
                end
                FWD_ISSUE:if(child_ready)state<=FWD_RUN;
                FWD_RUN:if(child_done)begin
                    if(saved_opcode==OP_KV_CONFIG && child_status==STATUS_OK)current_cfg<=saved_cfg;
                    if(completion_ready)state<=IDLE;
                end
                CHECK_PLAN:begin
                    if(!configured || plan.attention.q_source!=2)begin status<=STATUS_BAD_FLAGS;state<=COMPLETE;end
                    else if(plan.q_task.desc.m!=1 || plan.k_task.desc.m!=1 || plan.v_task.desc.m!=1 ||
                        plan.attention.dimension==0 || plan.attention.dimension>MAX_DIM || plan.attention.dimension>64 ||
                        plan.q_task.desc.n!=plan.attention.dimension || plan.k_task.desc.n!=plan.attention.dimension || plan.v_task.desc.n!=plan.attention.dimension ||
                        plan.q_task.desc.k==0 || plan.q_task.desc.k>MAX_K || plan.q_task.desc.k>4096 ||
                        plan.k_task.desc.k!=plan.q_task.desc.k || plan.v_task.desc.k!=plan.q_task.desc.k ||
                        plan.attention.layer>=current_cfg.layers || plan.attention.head>=current_cfg.heads ||
                        plan.attention.dimension!=current_cfg.dimension || plan.token>=current_cfg.capacity ||
                        plan.attention.tokens!=plan.token+17'd1 || plan.attention.tokens>MAX_TOKENS || plan.attention.score_scale==0)
                        begin status<=STATUS_BAD_DIM;state<=COMPLETE;end
                    else if(plan.q_task.desc.task_id==plan.k_task.desc.task_id || plan.q_task.desc.task_id==plan.v_task.desc.task_id ||
                        plan.k_task.desc.task_id==plan.v_task.desc.task_id)begin status<=STATUS_BAD_FLAGS;state<=COMPLETE;end
                    else if(plan.attention.q_addr!=plan.q_task.desc.y_addr || plan.attention.q_bytes!=plan.q_task.y_bytes ||
                        plan.attention.qs_addr!=0 || plan.attention.qs_bytes!=0 || plan.attention.y_addr[1:0]!=0 ||
                        plan.attention.y_bytes<4*32'(plan.attention.dimension) ||
                        65'(plan.attention.y_addr)+65'(plan.attention.y_bytes)>(65'd1<<ADDR_WIDTH))begin status<=STATUS_BAD_REGION;state<=COMPLETE;end
                    else begin check_index<=0;state<=CHECK_TASK;end
                end
                CHECK_TASK:if(check_status!=STATUS_OK)begin status<=check_status;state<=COMPLETE;end
                    else if(check_index==2)begin alias_index<=0;write_index<=0;state<=CHECK_ALIAS;end
                    else check_index<=check_index+1;
                CHECK_ALIAS:if(!(alias_index>=16 && alias_index-16==write_index) &&
                    w4a8_memory_pkg::overlaps(wb[write_index],ws[write_index],alias_base,alias_bytes))begin status<=STATUS_BAD_REGION;state<=COMPLETE;end
                    else if(alias_index==19)begin
                        alias_index<=0;
                        if(write_index==3)state<=K_ISSUE;else write_index<=write_index+1;
                    end else alias_index<=alias_index+1;
                K_ISSUE:if(child_ready)state<=K_RUN;
                V_ISSUE:if(child_ready)state<=V_RUN;
                APPEND_ISSUE:if(child_ready)begin stream_index<=0;state<=APPEND_RUN;end
                Q_ISSUE:if(child_ready)state<=Q_RUN;
                K_RUN,V_RUN,APPEND_RUN,Q_RUN:begin
                    if(state==APPEND_RUN && child_append_valid && child_append_ready)stream_index<=stream_index+1;
                    if(child_done)begin
                        if(child_status!=STATUS_OK)begin status<=child_status;state<=COMPLETE;end
                        else case(state)
                            K_RUN:state<=KQ_START;
                            V_RUN:state<=VQ_START;
                            APPEND_RUN:if(17'(stream_index)!=stream_bytes)begin status<=STATUS_MEMORY_PROTOCOL;state<=COMPLETE;end else state<=Q_ISSUE;
                            Q_RUN:state<=COMPLETE;
                            default:;
                        endcase
                    end
                end
                KQ_START,VQ_START:if(quant_ready)begin capture_index<=0;state<=quant_v?VQ_RUN:KQ_RUN;end
                KQ_RUN,VQ_RUN:begin
                    if(quant_failed && quant_idle)begin status<=STATUS_READ_ERROR;state<=COMPLETE;end
                    else if(quant_valid)begin
                        if(quant_v)begin vb[capture_index]<=quant_data;vs[capture_index/GROUP_SIZE]<=quant_scale;end
                        else begin kb[capture_index]<=quant_data;ks[capture_index/GROUP_SIZE]<=quant_scale;end
                        capture_index<=capture_index+1;
                        if(quant_last!=(capture_index+1==plan.attention.dimension))begin status<=STATUS_MEMORY_PROTOCOL;state<=COMPLETE;end
                        else if(quant_last)state<=quant_v?APPEND_ISSUE:V_ISSUE;
                    end
                end
                COMPLETE:if(completion_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
    wire  e_arvalid,q_arvalid;
    wire [ADDR_WIDTH-1:0] e_araddr,q_araddr;
    wire [3:0] e_arid,q_arid;
    wire [7:0] e_arlen,q_arlen;
    wire [2:0] e_arsize,q_arsize;
    wire [1:0] e_arburst,q_arburst;
    wire  e_rready,q_rready;
    assign arvalid=quant_owner?q_arvalid:e_arvalid;
    assign araddr=quant_owner?q_araddr:e_araddr;
    assign arid=quant_owner?q_arid:e_arid;
    assign arlen=quant_owner?q_arlen:e_arlen;
    assign arsize=quant_owner?q_arsize:e_arsize;
    assign arburst=quant_owner?q_arburst:e_arburst;
    assign rready=quant_owner?q_rready:e_rready;
    attention_q_dma #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_DIM(MAX_DIM)) quantizer(
        .clk(clk),.rst(rst || !quant_owner),.load_valid(quant_start),.load_ready(quant_ready),.desc(quant_desc),
        .loaded(quant_loaded),.failed(quant_failed),.idle(quant_idle),.send_enable(quant_send),
        .out_valid(quant_valid),.out_ready(quant_send),.out_data(quant_data),.out_scale(quant_scale),.out_last(quant_last),
        .arvalid(q_arvalid),.arready(arready && quant_owner),.araddr(q_araddr),.arid(q_arid),.arlen(q_arlen),.arsize(q_arsize),.arburst(q_arburst),
        .rvalid(rvalid && quant_owner),.rready(q_rready),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast));
    llm_top #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K),.MAX_H(MAX_H),.CAPACITY(CAPACITY),.MAX_DIM(MAX_DIM),.MAX_TOKENS(MAX_TOKENS)) engine(
        .clk(clk),.rst(rst),.job_valid(child_valid),.job_ready(child_ready),.job_opcode(child_opcode),
        .linear_task(child_linear),.ffn_plan(ffn_plan),.kv_config(kv_config),.kv_command(child_cmd),.attention_task(child_query),
        .append_valid(child_append_valid),.append_ready(child_append_ready),.append_data(child_append_data),.append_last(child_append_last),
        .read_valid(child_read_valid),.read_ready(state==FWD_RUN && read_ready),.read_data(child_read_data),.read_last(child_read_last),
        .q_valid(state==FWD_RUN && q_valid),.q_ready(child_q_ready),.q_data(q_data),.q_scale(q_scale),.q_last(q_last),
        .load_pause(load_pause),.post_pause(post_pause),.array_pause(array_pause),
        .completion_valid(child_done),.completion_ready(child_completion_ready),.completion_task_id(child_id),.completion_status(child_status),
        .result_available(child_result),.configured(configured),.stage(child_stage),.elapsed_cycles(child_elapsed),
        .activation_written(child_activations),.scale_written(child_scales),
        .arvalid(e_arvalid),.araddr(e_araddr),.arid(e_arid),.arlen(e_arlen),
        .arsize(e_arsize),.arburst(e_arburst),.rready(e_rready),.arready(arready && !quant_owner),
        .rvalid(rvalid && !quant_owner),.rdata(rdata),.rid(rid),.rresp(rresp),
        .rlast(rlast),.awvalid(awvalid),.awready(awready),.awaddr(awaddr),
        .awid(awid),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .wvalid(wvalid),.wready(wready),.wdata(wdata),.wstrb(wstrb),
        .wlast(wlast),.bvalid(bvalid),.bready(bready),.bid(bid),
        .bresp(bresp));

endmodule
