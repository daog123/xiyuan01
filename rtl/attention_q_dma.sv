// Bounded Q loader: source 1 = INT8 + UQ4.12 scales; source 2 = contiguous
// Q16.16 projection output dynamically quantized by complete groups on chip.
module attention_q_dma #(parameter integer ADDR_WIDTH=64,GROUP_SIZE=32,MAX_DIM=64)(
    input logic clk,rst,load_valid,output logic load_ready,
    input attention_pkg::attention_task_t desc,
    output logic loaded,failed,idle,
    input logic send_enable,output logic out_valid,input logic out_ready,
    output logic signed [7:0] out_data,output logic [15:0] out_scale,output logic out_last,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast
);
    localparam integer MG=(MAX_DIM+GROUP_SIZE-1)/GROUP_SIZE;
    typedef enum logic [3:0] {IDLE,SCALE_CMD,SCALE_RSP,Q_CMD,Q_RSP,QUANT_CFG,
        WORD_CMD,WORD_RSP,FEED,QUANT_OUT,READY,SENT,FAILED} state_t;
    state_t state;
    attention_pkg::attention_task_t active;
    logic signed [7:0] q_buffer[0:MAX_DIM-1];
    logic [15:0] scales[0:MG-1];
    logic [15:0] cursor,groups,send_index,group_id,value_index;
    logic [31:0] word_value;
    wire rd_valid=state==SCALE_CMD || state==Q_CMD || state==WORD_CMD;
    logic rd_ready,rsp_valid,rsp_error,reader_idle;
    logic [63:0] rsp_data;logic [3:0] rsp_bytes,request_bytes;
    logic [ADDR_WIDTH-1:0] address;
    always_comb begin
        address=ADDR_WIDTH'(active.q_addr+64'(cursor));
        request_bytes=active.dimension-cursor>=8?4'd8:4'(active.dimension-cursor);
        if(state==SCALE_CMD) begin
            address=ADDR_WIDTH'(active.qs_addr+64'(cursor));
            request_bytes=2*groups-cursor>=8?4'd8:4'(2*groups-cursor);
        end else if(state==WORD_CMD) begin
            address=ADDR_WIDTH'(active.q_addr+4*64'(value_index));request_bytes=4;
        end
    end
    assign load_ready=state==IDLE && !rst;
    assign loaded=(state==READY || state==SENT) && !rst;
    assign failed=state==FAILED && !rst;
    assign idle=reader_idle;
    assign out_valid=state==READY && send_enable && !rst;
    assign out_data=q_buffer[send_index];
    assign out_scale=scales[send_index/GROUP_SIZE];
    assign out_last=send_index+1==active.dimension;
    w4a8_axi_read_chunk #(.ADDR_WIDTH(ADDR_WIDTH)) reader(
        .clk(clk),.rst(rst),.cmd_valid(rd_valid),.cmd_ready(rd_ready),.cmd_addr(address),.cmd_bytes(request_bytes),
        .rsp_valid(rsp_valid),.rsp_ready(state==SCALE_RSP || state==Q_RSP || state==WORD_RSP || state==FAILED),
        .rsp_data(rsp_data),.rsp_bytes(rsp_bytes),.rsp_error(rsp_error),.idle(reader_idle),
        .arvalid(arvalid),.arready(arready),.araddr(araddr),.arid(arid),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .rvalid(rvalid),.rready(rready),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast));
    logic quant_cfg_ready,quant_in_ready,quant_valid,quant_last;
    logic signed [7:0] quant_data;logic [15:0] quant_scale,quant_group,quant_index;
    logic [1:0] quant_error;
    wire [15:0] remaining=active.dimension-group_id*GROUP_SIZE;
    wire [15:0] group_len=remaining<GROUP_SIZE?remaining:16'(GROUP_SIZE);
    requant_dynamic #(.GROUP_SIZE(GROUP_SIZE),.MAX_K(MAX_DIM)) quantizer(
        .clk(clk),.rst(rst || state==IDLE),.cfg_valid(state==QUANT_CFG),.cfg_ready(quant_cfg_ready),
        .cfg_row(16'd0),.cfg_group(group_id),.cfg_k(active.dimension),.cfg_len(group_len),
        .in_valid(state==FEED),.in_pause(1'b0),.in_ready(quant_in_ready),.in_data($signed(word_value)),
        .out_valid(quant_valid),.out_ready(state==QUANT_OUT),.out_data(quant_data),
        .out_row(),.out_group(quant_group),.out_index(quant_index),.out_scale(quant_scale),.out_last(quant_last),
        .out_saturated(),.group_saturated(),.scale_clipped(),.group_absmax(),.busy(),.done(),.error_code(quant_error));
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;active<='0;cursor<=0;groups<=0;send_index<=0;group_id<=0;value_index<=0;word_value<=0;
        end else begin
            case(state)
                IDLE:if(load_valid) begin
                    active<=desc;cursor<=0;send_index<=0;group_id<=0;value_index<=0;
                    groups<=(desc.dimension+GROUP_SIZE-1)/GROUP_SIZE;
                    if(desc.dimension==0 || desc.dimension>MAX_DIM || !(desc.q_source==1 || desc.q_source==2) ||
                        (desc.q_source==2 && desc.q_addr[1:0]!=0)) state<=FAILED;
                    else state<=desc.q_source==2?QUANT_CFG:SCALE_CMD;
                end
                SCALE_CMD:if(rd_ready) state<=SCALE_RSP;
                SCALE_RSP:if(rsp_valid) begin
                    if(rsp_error) state<=FAILED;
                    else begin
                        for(integer b=0;b<8;b++) if(b<rsp_bytes)scales[(integer'(cursor)+b)/2][((integer'(cursor)+b)%2)*8 +:8]<=rsp_data[b*8 +:8];
                        if(cursor+rsp_bytes==2*groups) begin cursor<=0;state<=Q_CMD;end
                        else begin cursor<=cursor+rsp_bytes;state<=SCALE_CMD;end
                    end
                end
                Q_CMD:if(rd_ready) state<=Q_RSP;
                Q_RSP:if(rsp_valid) begin
                    if(rsp_error) state<=FAILED;
                    else begin
                        for(integer b=0;b<8;b++)if(b<rsp_bytes)q_buffer[integer'(cursor)+b]<=rsp_data[b*8 +:8];
                        if(cursor+rsp_bytes==active.dimension) state<=READY;
                        else begin cursor<=cursor+rsp_bytes;state<=Q_CMD;end
                    end
                end
                QUANT_CFG:if(quant_cfg_ready) state<=WORD_CMD;
                WORD_CMD:if(rd_ready) state<=WORD_RSP;
                WORD_RSP:if(rsp_valid) begin
                    if(rsp_error || rsp_bytes!=4)state<=FAILED;
                    else begin word_value<=rsp_data[31:0];state<=FEED;end
                end
                FEED:if(quant_in_ready) begin
                    value_index<=value_index+1;
                    if(value_index+1==active.dimension || (value_index+1)%GROUP_SIZE==0) state<=QUANT_OUT;
                    else state<=WORD_CMD;
                end
                QUANT_OUT:if(quant_valid) begin
                    q_buffer[integer'(quant_group)*GROUP_SIZE+integer'(quant_index)]<=quant_data;
                    scales[quant_group]<=quant_scale;
                    if(quant_last) begin
                        if(group_id+1==groups) state<=READY;
                        else begin group_id<=group_id+1;state<=QUANT_CFG;end
                    end
                end
                READY:if(out_valid && out_ready)begin if(out_last)state<=SENT;else send_index<=send_index+1;end
                default:;
            endcase
            if(state!=IDLE && state!=FAILED && quant_error!=0)state<=FAILED;
        end
    end
endmodule
