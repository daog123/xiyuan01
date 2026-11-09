// Real memory-backed SwiGLU stage. All read responses and write acknowledgements
// drain before completion; done from ffn_bridge is never a storage fence.
module ffn_dma #(
    parameter integer ADDR_WIDTH=64,GROUP_SIZE=32,MAX_M=64,MAX_H=64,CAPACITY=512
)(
    input logic clk,rst,task_valid,output logic task_ready,
    input accelerator_pkg::ffn_plan_t plan,
    output logic completion_valid,input logic completion_ready,
    output logic [7:0] completion_status,
    output logic [31:0] activation_written,scale_written,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast,
    output logic awvalid,input logic awready,output logic [ADDR_WIDTH-1:0] awaddr,
    output wire [3:0] awid,output wire [7:0] awlen,output wire [2:0] awsize,output wire [1:0] awburst,
    output logic wvalid,input logic wready,output logic [63:0] wdata,output logic [7:0] wstrb,output wire wlast,
    input logic bvalid,output logic bready,input logic [3:0] bid,input logic [1:0] bresp
);
    import task_desc_pkg::*;
    typedef enum logic [3:0] {IDLE,CONFIGURE,READ_CMD,READ_RSP,FEED,WAIT_QUANT,
        WRITE_CMD,WRITE_ACK,FINISH,DRAIN,COMPLETE} state_t;
    state_t state;
    accelerator_pkg::ffn_plan_t active;
    logic [15:0] row,col;logic branch;logic [1:0] byte_index,write_kind;
    logic [31:0] word_value;
    logic cfg_ready,bridge_in_ready,qvalid,qready,bridge_done,done_seen;
    logic [1:0] bridge_error;
    logic signed [7:0] qdata;logic [15:0] qrow,qgroup,qindex,qscale;
    logic qlast,qtlast;
    logic [7:0] saved_q;logic [15:0] saved_row,saved_group,saved_index,saved_scale;
    logic saved_last;
    logic rd_valid,rd_ready,rsp_valid,rsp_ready,rsp_error,rd_idle;
    logic [7:0] rsp_data,write_data;
    logic [ADDR_WIDTH-1:0] read_address,write_address;
    logic wr_valid,wr_ready,ack_valid,ack_error,wr_idle;
    wire local_reset=rst || state==IDLE || state==COMPLETE;
    wire bridge_reset=local_reset || state==DRAIN;
    assign task_ready=state==IDLE && !rst;
    assign completion_valid=state==COMPLETE && !rst;
    assign read_address=ADDR_WIDTH'((branch?active.up_task.desc.y_addr:active.gate_task.desc.y_addr)+
        64'(row)*64'(branch?active.up_task.desc.y_stride:active.gate_task.desc.y_stride)+4*64'(col)+64'(byte_index));
    always_comb begin
        write_address=ADDR_WIDTH'(active.down_task.desc.a_addr+64'(saved_row)*64'(active.down_task.desc.a_stride)+
            64'(saved_group)*GROUP_SIZE+64'(saved_index));
        write_data=saved_q;
        if(write_kind!=0) begin
            write_address=ADDR_WIDTH'(active.down_task.desc.sx_addr+64'(saved_row)*64'(active.down_task.desc.sx_stride)+
                2*64'(saved_group)+64'(write_kind-1));
            write_data=write_kind==1?saved_scale[7:0]:saved_scale[15:8];
        end
    end
    assign rd_valid=state==READ_CMD && !rst;
    assign rsp_ready=(state==READ_RSP || state==DRAIN) && !rst;
    assign wr_valid=state==WRITE_CMD && !rst;
    assign qready=state==WAIT_QUANT && !rst;
    w4a8_axi_read #(.ADDR_WIDTH(ADDR_WIDTH)) reader(
        .clk(clk),.rst(local_reset),.cmd_valid(rd_valid),.cmd_ready(rd_ready),.cmd_addr(read_address),
        .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_data(rsp_data),.rsp_error(rsp_error),.idle(rd_idle),
        .arvalid(arvalid),.arready(arready),.araddr(araddr),.arid(arid),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .rvalid(rvalid),.rready(rready),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast));
    storage_axi_byte_write #(.ADDR_WIDTH(ADDR_WIDTH)) writer(
        .clk(clk),.rst(local_reset),.cmd_valid(wr_valid),.cmd_ready(wr_ready),.cmd_addr(write_address),.cmd_data(write_data),
        .ack_valid(ack_valid),.ack_error(ack_error),.idle(wr_idle),
        .awvalid(awvalid),.awready(awready),.awaddr(awaddr),.awid(awid),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .wvalid(wvalid),.wready(wready),.wdata(wdata),.wstrb(wstrb),.wlast(wlast),
        .bvalid(bvalid),.bready(bready),.bid(bid),.bresp(bresp));
    ffn_bridge #(.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_H(MAX_H),.CAPACITY(CAPACITY)) bridge(
        .clk(clk),.rst(bridge_reset),.cfg_valid(state==CONFIGURE),.cfg_ready(cfg_ready),
        .cfg_m(active.gate_task.desc.m),.cfg_h(active.gate_task.desc.n),
        .in_valid(state==FEED),.in_ready(bridge_in_ready),.in_branch(branch),.in_row(row),.in_col(col),.in_data($signed(word_value)),
        .out_valid(qvalid),.out_ready(qready),.out_data(qdata),.out_row(qrow),.out_group(qgroup),
        .out_index(qindex),.out_scale(qscale),.out_last(qlast),.out_task_last(qtlast),
        .out_saturated(),.group_saturated(),.scale_clipped(),.group_absmax(),.nonlinear_saturated(),
        .busy(),.done(bridge_done),.error_code(bridge_error));
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;active<='0;row<=0;col<=0;branch<=0;byte_index<=0;word_value<=0;
            write_kind<=0;saved_q<=0;saved_row<=0;saved_group<=0;saved_index<=0;saved_scale<=0;saved_last<=0;
            done_seen<=0;activation_written<=0;scale_written<=0;completion_status<=STATUS_OK;
        end else begin
            if(bridge_done) done_seen<=1;
            case(state)
                IDLE:if(task_valid) begin
                    active<=plan;row<=0;col<=0;branch<=0;byte_index<=0;done_seen<=0;
                    activation_written<=0;scale_written<=0;completion_status<=STATUS_OK;state<=CONFIGURE;
                end
                CONFIGURE:if(cfg_ready) state<=READ_CMD;
                READ_CMD:if(rd_ready) state<=READ_RSP;
                READ_RSP:if(rsp_valid) begin
                    if(rsp_error) begin completion_status<=STATUS_READ_ERROR;state<=DRAIN;end
                    else begin
                        word_value[byte_index*8 +:8]<=rsp_data;
                        if(byte_index==3) begin byte_index<=0;state<=FEED;end
                        else begin byte_index<=byte_index+1;state<=READ_CMD;end
                    end
                end
                FEED:if(bridge_in_ready) begin
                    if(!branch) begin branch<=1;state<=READ_CMD;end
                    else begin
                        branch<=0;
                        if(col+1<active.gate_task.desc.n) begin col<=col+1;state<=READ_CMD;end
                        else if(row+1<active.gate_task.desc.m) begin col<=0;row<=row+1;state<=READ_CMD;end
                        else state<=WAIT_QUANT;
                    end
                end
                WAIT_QUANT:if(qvalid) begin
                    saved_q<=qdata;saved_row<=qrow;saved_group<=qgroup;saved_index<=qindex;saved_scale<=qscale;
                    saved_last<=qtlast;write_kind<=0;state<=WRITE_CMD;
                end
                WRITE_CMD:if(wr_ready) state<=WRITE_ACK;
                WRITE_ACK:if(ack_valid) begin
                    if(ack_error) begin completion_status<=STATUS_WRITE_ERROR;state<=DRAIN;end
                    else begin
                        if(write_kind==0) activation_written<=activation_written+1;
                        else scale_written<=scale_written+1;
                        if(write_kind==0 && saved_index==0) begin write_kind<=1;state<=WRITE_CMD;end
                        else if(write_kind==1) begin write_kind<=2;state<=WRITE_CMD;end
                        else if(saved_last) state<=FINISH;
                        else state<=WAIT_QUANT;
                    end
                end
                FINISH:if(done_seen && rd_idle && wr_idle && !ack_valid) begin
                    if(activation_written!=32'(active.gate_task.desc.m)*32'(active.gate_task.desc.n) ||
                        scale_written!=2*32'(active.gate_task.desc.m)*((32'(active.gate_task.desc.n)+GROUP_SIZE-1)/GROUP_SIZE))
                        completion_status<=STATUS_MEMORY_PROTOCOL;
                    state<=COMPLETE;
                end
                DRAIN:if(rd_idle && wr_idle && !ack_valid) state<=COMPLETE;
                COMPLETE:if(completion_ready) state<=IDLE;
                default:state<=IDLE;
            endcase
            if(state!=IDLE && state!=COMPLETE && state!=DRAIN && bridge_error!=0) begin
                completion_status<=STATUS_MEMORY_PROTOCOL;state<=DRAIN;
            end
        end
    end
endmodule
