// Storage-side KV manager. No attention arithmetic, quantization or unified scheduler.
module kv_cache #(
    parameter integer ADDR_WIDTH=32,GROUP_SIZE=32,MAX_LAYERS=4,MAX_HEADS=8,MAX_TOKENS=4096,MAX_DIM=128
)(
    input logic clk,rst,
    input logic cfg_valid,output logic cfg_ready,input kv_cache_pkg::kv_config_t cfg_desc,
    input logic cmd_valid,output logic cmd_ready,input kv_cache_pkg::kv_command_t cmd_desc,
    input logic append_valid,output logic append_ready,input logic [7:0] append_data,input logic append_last,
    output logic read_valid,input logic read_ready,output logic [7:0] read_data,output logic read_last,
    output logic completion_valid,input logic completion_ready,
    output logic [31:0] completion_id,output logic [3:0] completion_status,
    output logic configured,
    input logic [15:0] query_layer,query_head,output logic query_valid,output logic [15:0] query_length,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,input logic [3:0] rid,input logic [1:0] rresp,input logic rlast,
    output logic awvalid,input logic awready,output logic [ADDR_WIDTH-1:0] awaddr,
    output wire [3:0] awid,output wire [7:0] awlen,output wire [2:0] awsize,output wire [1:0] awburst,
    output logic wvalid,input logic wready,output logic [63:0] wdata,output logic [7:0] wstrb,output wire wlast,
    input logic bvalid,output logic bready,input logic [3:0] bid,input logic [1:0] bresp,
    output logic [31:0] cycles,accepted_bytes,acknowledged_bytes,returned_bytes,read_wait,write_wait
);
    import kv_cache_pkg::*;
    localparam integer SLOTS=MAX_LAYERS*MAX_HEADS;
    typedef enum logic [3:0] {IDLE,CHECK_CFG,CHECK_CMD,APPEND,APPEND_FENCE,READ_CMD,READ_RESPONSE,COMPLETE} state_t;
    state_t state;
    kv_config_t cfg;
    kv_command_t command;
    logic [15:0] lengths[0:SLOTS-1];
    logic cfg_legal,address_legal,command_legal;
    logic [15:0] committed,token_cursor,byte_cursor;
    logic [1:0] plane_cursor;
    logic [ADDR_WIDTH-1:0] address;logic [31:0] width,total_bytes,sent,acks,received;
    logic rd_cmd_valid,rd_cmd_ready,rd_rsp_valid,rd_rsp_ready,rd_error,rd_idle;
    logic [7:0] rd_data;
    logic wr_cmd_valid,wr_cmd_ready,wr_ack_valid,wr_error,wr_idle;
    initial begin
        if(GROUP_SIZE<1 || GROUP_SIZE>4096 || MAX_LAYERS<1 || MAX_LAYERS>64 || MAX_HEADS<1 ||
            MAX_HEADS>64 || MAX_TOKENS<1 || MAX_TOKENS>4096 || MAX_DIM<1 || MAX_DIM>4096)
            $fatal(1,"Unsupported KV hardware parameters");
    end
    kv_cache_address #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_LAYERS(MAX_LAYERS),.MAX_HEADS(MAX_HEADS),.MAX_TOKENS(MAX_TOKENS),.MAX_DIM(MAX_DIM)) layout(
        .cfg(cfg),.plane(plane_cursor),.layer(command.layer),.head(command.head),.token(token_cursor),.offset(byte_cursor),
        .config_legal(cfg_legal),.access_legal(address_legal),.address(address));
    always_comb begin
        committed=0;
        if(command.layer<MAX_LAYERS && command.head<MAX_HEADS) committed=lengths[32'(command.layer)*MAX_HEADS+32'(command.head)];
        command_legal=configured && command.layer<cfg.layers && command.head<cfg.heads;
        case(command.operation)
            KV_APPEND:command_legal=command_legal && command.count>0 && command.token==committed &&
                17'(command.token)+17'(command.count)<=17'(cfg.capacity) && command.plane==0 && command.offset==0 && command.length==0;
            KV_READ:command_legal=command_legal && command.count>0 && command.length>0 &&
                17'(command.token)+17'(command.count)<=17'(committed) &&
                32'(command.offset)+32'(command.length)<=kv_plane_bytes(cfg,command.plane,GROUP_SIZE);
            KV_CLEAR:command_legal=command_legal && command.token==0 && command.count==0 &&
                command.plane==0 && command.offset==0 && command.length==0;
            default:command_legal=0;
        endcase
        query_valid=configured && !rst && query_layer<cfg.layers && query_head<cfg.heads;
        query_length=0;
        if(query_valid) query_length=lengths[32'(query_layer)*MAX_HEADS+32'(query_head)];
    end
    assign cfg_ready=state==IDLE && !configured && !rst;
    assign cmd_ready=state==IDLE && configured && !rst;
    assign completion_valid=state==COMPLETE && !rst;
    assign width=kv_plane_bytes(cfg,plane_cursor,GROUP_SIZE);
    // Do not accept the next input byte before checking the previous B response.
    assign append_ready=state==APPEND && wr_cmd_ready && !wr_ack_valid && address_legal && !rst;
    assign wr_cmd_valid=append_valid && append_ready && append_last==(sent+1==total_bytes);
    assign rd_cmd_valid=state==READ_CMD && address_legal && !rst;
    assign rd_rsp_ready=state==READ_RESPONSE && (rd_error || read_ready) && !rst;
    assign read_valid=state==READ_RESPONSE && rd_rsp_valid && !rd_error && !rst;
    assign read_data=rd_data;
    assign read_last=received+1==total_bytes;
    w4a8_axi_read #(.ADDR_WIDTH(ADDR_WIDTH)) reader(.clk(clk),.rst(rst),.cmd_valid(rd_cmd_valid),.cmd_ready(rd_cmd_ready),.cmd_addr(address),
        .rsp_valid(rd_rsp_valid),.rsp_ready(rd_rsp_ready),.rsp_data(rd_data),.rsp_error(rd_error),.idle(rd_idle),
        .arvalid(arvalid),.arready(arready),.araddr(araddr),.arid(arid),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .rvalid(rvalid),.rready(rready),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast));
    storage_axi_byte_write #(.ADDR_WIDTH(ADDR_WIDTH)) writer(.clk(clk),.rst(rst),.cmd_valid(wr_cmd_valid),.cmd_ready(wr_cmd_ready),.cmd_addr(address),.cmd_data(append_data),
        .ack_valid(wr_ack_valid),.ack_error(wr_error),.idle(wr_idle),
        .awvalid(awvalid),.awready(awready),.awaddr(awaddr),.awid(awid),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .wvalid(wvalid),.wready(wready),.wdata(wdata),.wstrb(wstrb),.wlast(wlast),
        .bvalid(bvalid),.bready(bready),.bid(bid),.bresp(bresp));
    always_ff @(posedge clk) begin
        if(rst) begin
            cfg<='0;command<='0;configured<=0;state<=IDLE;completion_id<=0;completion_status<=KV_OK;
            token_cursor<=0;plane_cursor<=0;byte_cursor<=0;total_bytes<=0;sent<=0;acks<=0;received<=0;
            cycles<=0;accepted_bytes<=0;acknowledged_bytes<=0;returned_bytes<=0;read_wait<=0;write_wait<=0;
            for(integer i=0;i<SLOTS;i++) lengths[i]<=0;
        end else begin
            if(state!=IDLE && state!=COMPLETE) cycles<=cycles+1;
            if(!rd_idle) read_wait<=read_wait+1;
            if(!wr_idle) write_wait<=write_wait+1;
            case(state)
                IDLE:begin
                    if((cfg_valid && cfg_ready) || (cmd_valid && cmd_ready)) begin
                        cycles<=0;accepted_bytes<=0;acknowledged_bytes<=0;returned_bytes<=0;read_wait<=0;write_wait<=0;
                        sent<=0;acks<=0;received<=0;completion_status<=KV_OK;
                    end
                    if(cfg_valid && cfg_ready) begin cfg<=cfg_desc;completion_id<=cfg_desc.config_id;state<=CHECK_CFG;end
                    else if(cmd_valid && cmd_ready) begin command<=cmd_desc;completion_id<=cmd_desc.task_id;state<=CHECK_CMD;end
                end
                CHECK_CFG:begin
                    if(cfg_legal) configured<=1;else completion_status<=KV_BAD_CONFIG;
                    state<=COMPLETE;
                end
                CHECK_CMD:begin
                    token_cursor<=command.token;byte_cursor<=command.offset;plane_cursor<=command.plane;
                    if(!command_legal) begin completion_status<=KV_BAD_COMMAND;state<=COMPLETE;end
                    else case(command.operation)
                        KV_APPEND:begin
                            total_bytes<=32'(command.count)*(2*32'(cfg.dimension)+4*((32'(cfg.dimension)+GROUP_SIZE-1)/GROUP_SIZE));
                            state<=APPEND;
                        end
                        KV_READ:begin total_bytes<=32'(command.count)*32'(command.length);state<=READ_CMD;end
                        KV_CLEAR:begin lengths[32'(command.layer)*MAX_HEADS+32'(command.head)]<=0;state<=COMPLETE;end
                        default:begin completion_status<=KV_BAD_COMMAND;state<=COMPLETE;end
                    endcase
                end
                APPEND:begin
                    if(wr_ack_valid) begin
                        if(wr_error) begin completion_status<=KV_WRITE_ERROR;state<=COMPLETE;end
                        else begin acks<=acks+1;acknowledged_bytes<=acknowledged_bytes+1;end
                    end else if(!address_legal) begin completion_status<=KV_BAD_COMMAND;state<=COMPLETE;end
                    else if(append_valid && append_ready) begin
                        if(append_last!=(sent+1==total_bytes)) begin completion_status<=KV_STREAM_ERROR;state<=COMPLETE;end
                        else begin
                            sent<=sent+1;accepted_bytes<=accepted_bytes+1;
                            if(sent+1==total_bytes) state<=APPEND_FENCE;
                            else if(32'(byte_cursor)+1==width) begin
                                byte_cursor<=0;
                                if(plane_cursor==KV_SV) begin plane_cursor<=KV_K;token_cursor<=token_cursor+1;end
                                else plane_cursor<=plane_cursor+1;
                            end else byte_cursor<=byte_cursor+1;
                        end
                    end
                end
                APPEND_FENCE:begin
                    if(wr_ack_valid) begin
                        if(wr_error) begin completion_status<=KV_WRITE_ERROR;state<=COMPLETE;end
                        else begin acks<=acks+1;acknowledged_bytes<=acknowledged_bytes+1;end
                    end else if(acks==total_bytes && wr_idle) begin
                        // The entire K/V/scales batch becomes visible atomically for this layer/head.
                        lengths[32'(command.layer)*MAX_HEADS+32'(command.head)]<=command.token+command.count;
                        state<=COMPLETE;
                    end
                end
                READ_CMD:if(!address_legal) begin completion_status<=KV_BAD_COMMAND;state<=COMPLETE;end
                    else if(rd_cmd_ready) state<=READ_RESPONSE;
                READ_RESPONSE:if(rd_rsp_valid && rd_rsp_ready) begin
                    if(rd_error) begin completion_status<=KV_READ_ERROR;state<=COMPLETE;end
                    else begin
                        received<=received+1;returned_bytes<=returned_bytes+1;
                        if(received+1==total_bytes) state<=COMPLETE;
                        else begin
                            if(32'(byte_cursor)+1==32'(command.offset)+32'(command.length)) begin
                                token_cursor<=token_cursor+1;byte_cursor<=command.offset;
                            end else byte_cursor<=byte_cursor+1;
                            state<=READ_CMD;
                        end
                    end
                end
                COMPLETE:if(completion_ready) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
