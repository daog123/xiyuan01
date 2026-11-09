// Single system owner: LINEAR or memory-backed gate/up/SwiGLU/down.
module accelerator_top #(
    parameter integer ADDR_WIDTH=64,GROUP_SIZE=32,ROWS=4,COLS=4,TILE_K=8,
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
    import task_desc_pkg::*;import accelerator_pkg::*;
    typedef enum logic [3:0] {IDLE,CHECK,ISSUE_GATE,GATE,ISSUE_UP,UP,ISSUE_VECTOR,VECTOR,
        ISSUE_DOWN,DOWN,ISSUE_LINEAR,LINEAR,COMPLETE} state_t;
    state_t state;
    bounded_task_t saved_linear,selected;
    ffn_plan_t active;
    logic [7:0] opcode,status_g,status_u,status_d,status_l;
    logic plan_legal;
    logic linear_valid,linear_ready,linear_complete,linear_c_ready;
    logic [31:0] linear_c_id;logic [7:0] linear_c_status;
    logic vector_valid,vector_ready,vector_complete,vector_c_ready;logic [7:0] vector_c_status;
    logic [63:0] wb[0:4],ib[0:9];logic [31:0] ws[0:4],isz[0:9];
    wire vector_owner=state==ISSUE_VECTOR || state==VECTOR;
    assign job_ready=state==IDLE && !rst;
    assign completion_valid=state==COMPLETE && !rst;
    assign result_available=completion_valid && completion_status==STATUS_OK;
    assign linear_valid=(state==ISSUE_GATE || state==ISSUE_UP || state==ISSUE_DOWN || state==ISSUE_LINEAR) && !rst;
    assign linear_c_ready=state==GATE || state==UP || state==DOWN || state==LINEAR;
    assign vector_valid=state==ISSUE_VECTOR && !rst;
    assign vector_c_ready=state==VECTOR;
    always_comb begin
        selected=saved_linear;stage=0;
        case(state)
            ISSUE_GATE,GATE:begin selected=active.gate_task;stage=1;end
            ISSUE_UP,UP:begin selected=active.up_task;stage=2;end
            ISSUE_VECTOR,VECTOR:stage=3;
            ISSUE_DOWN,DOWN:begin selected=active.down_task;stage=4;end
            default:;
        endcase
        wb[0]=active.gate_task.desc.y_addr;ws[0]=active.gate_task.y_bytes;
        wb[1]=active.up_task.desc.y_addr;ws[1]=active.up_task.y_bytes;
        wb[2]=active.down_task.desc.a_addr;ws[2]=active.down_task.a_bytes;
        wb[3]=active.down_task.desc.sx_addr;ws[3]=active.down_task.sx_bytes;
        wb[4]=active.down_task.desc.y_addr;ws[4]=active.down_task.y_bytes;
        ib[0]=active.gate_task.desc.a_addr;isz[0]=active.gate_task.a_bytes;
        ib[1]=active.gate_task.desc.w_addr;isz[1]=active.gate_task.w_bytes;
        ib[2]=active.gate_task.desc.sx_addr;isz[2]=active.gate_task.sx_bytes;
        ib[3]=active.gate_task.desc.sw_addr;isz[3]=active.gate_task.sw_bytes;
        ib[4]=active.up_task.desc.a_addr;isz[4]=active.up_task.a_bytes;
        ib[5]=active.up_task.desc.w_addr;isz[5]=active.up_task.w_bytes;
        ib[6]=active.up_task.desc.sx_addr;isz[6]=active.up_task.sx_bytes;
        ib[7]=active.up_task.desc.sw_addr;isz[7]=active.up_task.sw_bytes;
        ib[8]=active.down_task.desc.w_addr;isz[8]=active.down_task.w_bytes;
        ib[9]=active.down_task.desc.sw_addr;isz[9]=active.down_task.sw_bytes;
        plan_legal=active.gate_task.desc.m==active.up_task.desc.m &&
            active.gate_task.desc.n==active.up_task.desc.n && active.gate_task.desc.k==active.up_task.desc.k &&
            active.down_task.desc.m==active.gate_task.desc.m && active.down_task.desc.k==active.gate_task.desc.n &&
            active.gate_task.desc.n<=MAX_H && 32'(active.gate_task.desc.m)*32'(active.gate_task.desc.n)<=CAPACITY &&
            active.gate_task.desc.task_id!=active.up_task.desc.task_id &&
            active.gate_task.desc.task_id!=active.down_task.desc.task_id && active.up_task.desc.task_id!=active.down_task.desc.task_id;
        for(integer i=0;i<5;i++) begin
            for(integer j=0;j<10;j++) if(w4a8_memory_pkg::overlaps(wb[i],ws[i],ib[j],isz[j])) plan_legal=0;
            for(integer j=i+1;j<5;j++) if(w4a8_memory_pkg::overlaps(wb[i],ws[i],wb[j],ws[j])) plan_legal=0;
        end
    end
    w4a8_task_adapter #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) check_g(
        .host_desc(active.gate_task.desc),.a_bytes(active.gate_task.a_bytes),.w_bytes(active.gate_task.w_bytes),
        .sx_bytes(active.gate_task.sx_bytes),.sw_bytes(active.gate_task.sw_bytes),.y_bytes(active.gate_task.y_bytes),.memory_desc(),.status(status_g));
    w4a8_task_adapter #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) check_u(
        .host_desc(active.up_task.desc),.a_bytes(active.up_task.a_bytes),.w_bytes(active.up_task.w_bytes),
        .sx_bytes(active.up_task.sx_bytes),.sw_bytes(active.up_task.sw_bytes),.y_bytes(active.up_task.y_bytes),.memory_desc(),.status(status_u));
    w4a8_task_adapter #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) check_d(
        .host_desc(active.down_task.desc),.a_bytes(active.down_task.a_bytes),.w_bytes(active.down_task.w_bytes),
        .sx_bytes(active.down_task.sx_bytes),.sw_bytes(active.down_task.sw_bytes),.y_bytes(active.down_task.y_bytes),.memory_desc(),.status(status_d));
    w4a8_task_adapter #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) check_l(
        .host_desc(saved_linear.desc),.a_bytes(saved_linear.a_bytes),.w_bytes(saved_linear.w_bytes),
        .sx_bytes(saved_linear.sx_bytes),.sw_bytes(saved_linear.sw_bytes),.y_bytes(saved_linear.y_bytes),.memory_desc(),.status(status_l));
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;active<='0;saved_linear<='0;opcode<=0;completion_task_id<=0;
            completion_status<=STATUS_OK;elapsed_cycles<=0;
        end else begin
            if(state!=IDLE && state!=COMPLETE) elapsed_cycles<=elapsed_cycles+1;
            case(state)
                IDLE:if(job_valid) begin
                    active<=ffn_plan;saved_linear<=linear_task;opcode<=job_opcode;elapsed_cycles<=0;
                    completion_task_id<=job_opcode==OP_LINEAR?linear_task.desc.task_id:ffn_plan.task_id;
                    completion_status<=STATUS_OK;state<=CHECK;
                end
                CHECK:begin
                    if(opcode==OP_LINEAR) begin
                        if(status_l!=STATUS_OK) begin completion_status<=status_l;state<=COMPLETE;end
                        else state<=ISSUE_LINEAR;
                    end else if(opcode!=OP_FFN) begin completion_status<=STATUS_BAD_FLAGS;state<=COMPLETE;end
                    else if(status_g!=0 || status_u!=0 || status_d!=0 || !plan_legal) begin
                        completion_status<=status_g!=0?status_g:status_u!=0?status_u:status_d!=0?status_d:STATUS_BAD_REGION;
                        state<=COMPLETE;
                    end else state<=ISSUE_GATE;
                end
                ISSUE_GATE:if(linear_ready) state<=GATE;
                ISSUE_UP:if(linear_ready) state<=UP;
                ISSUE_DOWN:if(linear_ready) state<=DOWN;
                ISSUE_LINEAR:if(linear_ready) state<=LINEAR;
                GATE,UP,DOWN,LINEAR:if(linear_complete) begin
                    if(linear_c_status!=0 || linear_c_id!=selected.desc.task_id) begin
                        completion_status<=linear_c_status!=0?linear_c_status:STATUS_MEMORY_PROTOCOL;state<=COMPLETE;
                    end else if(state==GATE) state<=ISSUE_UP;
                    else if(state==UP) state<=ISSUE_VECTOR;
                    else state<=COMPLETE;
                end
                ISSUE_VECTOR:if(vector_ready) state<=VECTOR;
                VECTOR:if(vector_complete) begin
                    if(vector_c_status!=0) begin completion_status<=vector_c_status;state<=COMPLETE;end
                    else state<=ISSUE_DOWN;
                end
                COMPLETE:if(completion_ready) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
    wire arvalid_l,arvalid_v;
    assign arvalid=vector_owner?arvalid_v:arvalid_l;
    wire [ADDR_WIDTH-1:0] araddr_l,araddr_v;
    assign araddr=vector_owner?araddr_v:araddr_l;
    wire [4-1:0] arid_l,arid_v;
    assign arid=vector_owner?arid_v:arid_l;
    wire [8-1:0] arlen_l,arlen_v;
    assign arlen=vector_owner?arlen_v:arlen_l;
    wire [3-1:0] arsize_l,arsize_v;
    assign arsize=vector_owner?arsize_v:arsize_l;
    wire [2-1:0] arburst_l,arburst_v;
    assign arburst=vector_owner?arburst_v:arburst_l;
    wire rready_l,rready_v;
    assign rready=vector_owner?rready_v:rready_l;
    wire awvalid_l,awvalid_v;
    assign awvalid=vector_owner?awvalid_v:awvalid_l;
    wire [ADDR_WIDTH-1:0] awaddr_l,awaddr_v;
    assign awaddr=vector_owner?awaddr_v:awaddr_l;
    wire [4-1:0] awid_l,awid_v;
    assign awid=vector_owner?awid_v:awid_l;
    wire [8-1:0] awlen_l,awlen_v;
    assign awlen=vector_owner?awlen_v:awlen_l;
    wire [3-1:0] awsize_l,awsize_v;
    assign awsize=vector_owner?awsize_v:awsize_l;
    wire [2-1:0] awburst_l,awburst_v;
    assign awburst=vector_owner?awburst_v:awburst_l;
    wire wvalid_l,wvalid_v;
    assign wvalid=vector_owner?wvalid_v:wvalid_l;
    wire [64-1:0] wdata_l,wdata_v;
    assign wdata=vector_owner?wdata_v:wdata_l;
    wire [8-1:0] wstrb_l,wstrb_v;
    assign wstrb=vector_owner?wstrb_v:wstrb_l;
    wire wlast_l,wlast_v;
    assign wlast=vector_owner?wlast_v:wlast_l;
    wire bready_l,bready_v;
    assign bready=vector_owner?bready_v:bready_l;
    w4a8_team_top #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),
        .MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K)) linear_engine(
        .clk(clk),.rst(rst),.load_pause(load_pause),.post_pause(post_pause),.array_pause(array_pause),
        .task_valid(linear_valid),.task_ready(linear_ready),.task_desc(selected.desc),
        .a_bytes(selected.a_bytes),.w_bytes(selected.w_bytes),.sx_bytes(selected.sx_bytes),.sw_bytes(selected.sw_bytes),.y_bytes(selected.y_bytes),
        .completion_valid(linear_complete),.completion_ready(linear_c_ready),.completion_task_id(linear_c_id),
        .completion_status(linear_c_status),.result_available(),.elapsed_cycles(),
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
        .arready(arready && !vector_owner),
        .rvalid(rvalid && !vector_owner),
        .rdata(rdata),
        .rid(rid),
        .rresp(rresp),
        .rlast(rlast),
        .awready(awready && !vector_owner),
        .wready(wready && !vector_owner),
        .bvalid(bvalid && !vector_owner),
        .bid(bid),
        .bresp(bresp));
    ffn_dma #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_H(MAX_H),.CAPACITY(CAPACITY)) vector_engine(
        .clk(clk),.rst(rst),.task_valid(vector_valid),.task_ready(vector_ready),.plan(active),
        .completion_valid(vector_complete),.completion_ready(vector_c_ready),.completion_status(vector_c_status),
        .activation_written(activation_written),.scale_written(scale_written),
        .arvalid(arvalid_v),
        .araddr(araddr_v),
        .arid(arid_v),
        .arlen(arlen_v),
        .arsize(arsize_v),
        .arburst(arburst_v),
        .rready(rready_v),
        .awvalid(awvalid_v),
        .awaddr(awaddr_v),
        .awid(awid_v),
        .awlen(awlen_v),
        .awsize(awsize_v),
        .awburst(awburst_v),
        .wvalid(wvalid_v),
        .wdata(wdata_v),
        .wstrb(wstrb_v),
        .wlast(wlast_v),
        .bready(bready_v),
        .arready(arready && vector_owner),
        .rvalid(rvalid && vector_owner),
        .rdata(rdata),
        .rid(rid),
        .rresp(rresp),
        .rlast(rlast),
        .awready(awready && vector_owner),
        .wready(wready && vector_owner),
        .bvalid(bvalid && vector_owner),
        .bid(bid),
        .bresp(bresp));
endmodule
