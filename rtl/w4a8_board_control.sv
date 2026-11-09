// Polled, single-task AXI4-Lite mailbox. All ports share clk/rst.
// Reset must cover the downstream AXI fabric; there is no unsafe software abort.
module w4a8_board_control #(
    parameter integer GROUP_SIZE=32, ROWS=4, COLS=4, TILE_K=32,
    MAX_M=64, MAX_N=64, MAX_K=4096
)(
    input logic clk,rst,ddr_ready,
    input logic [11:0] s_axi_awaddr,input logic s_axi_awvalid,output logic s_axi_awready,
    input logic [31:0] s_axi_wdata,input logic [3:0] s_axi_wstrb,
    input logic s_axi_wvalid,output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,output logic s_axi_bvalid,input logic s_axi_bready,
    input logic [11:0] s_axi_araddr,input logic s_axi_arvalid,output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,input logic s_axi_rready,
    output logic task_valid,input logic task_ready,output task_desc_pkg::task_desc_t task_desc,
    output logic [31:0] a_bytes,w_bytes,sx_bytes,sw_bytes,y_bytes,
    input logic completion_valid,output logic completion_ready,
    input logic [31:0] completion_task_id,input logic [7:0] completion_status,
    input logic [31:0] elapsed_cycles
);
    import task_desc_pkg::*;
    logic [31:0] cfg[0:25];
    logic aw_pending,w_pending,active,pending,done;
    logic [11:0] saved_awaddr;
    logic [31:0] saved_wdata,completed_id,completed_cycles;
    logic [3:0] saved_wstrb;
    logic [7:0] completed_status;
    logic [31:0] masked_command;
    logic [1:0] write_response;
    wire commit_write=aw_pending && w_pending && !s_axi_bvalid;
    wire parameters_address=saved_awaddr>=12'h020 && saved_awaddr<=12'h084;
    wire idle_ready=!active && !done && ddr_ready;
    assign s_axi_awready=!rst && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready=!rst && !w_pending && !s_axi_bvalid;
    assign s_axi_arready=!rst && !s_axi_rvalid;
    assign task_valid=!rst && pending;
    assign completion_ready=!rst && active && !pending;
    always_comb begin
        task_desc='0;
        task_desc.task_id=cfg[0];task_desc.m=cfg[1][15:0];
        task_desc.n=cfg[2][15:0];task_desc.k=cfg[3][15:0];
        task_desc.a_addr={cfg[5],cfg[4]};task_desc.w_addr={cfg[7],cfg[6]};
        task_desc.sx_addr={cfg[9],cfg[8]};task_desc.sw_addr={cfg[11],cfg[10]};
        task_desc.y_addr={cfg[13],cfg[12]};
        task_desc.a_stride=cfg[14];task_desc.w_stride=cfg[15];
        task_desc.sx_stride=cfg[16];task_desc.sw_stride=cfg[17];task_desc.y_stride=cfg[18];
        task_desc.activation_format=cfg[19][7:0];task_desc.weight_format=cfg[19][15:8];
        task_desc.scale_format=cfg[19][23:16];task_desc.output_format=cfg[19][31:24];
        task_desc.group_size=cfg[20][15:0];task_desc.flags=cfg[20][31:16];
        a_bytes=cfg[21];w_bytes=cfg[22];sx_bytes=cfg[23];sw_bytes=cfg[24];y_bytes=cfg[25];
        masked_command=0;
        for(integer b=0;b<4;b++)if(saved_wstrb[b])masked_command[b*8+:8]=saved_wdata[b*8+:8];
        write_response=2'b00;
        if(saved_awaddr[1:0]!=0)write_response=2'b10;
        else if(saved_awaddr==12'h008)begin
            if(masked_command==1)begin if(!idle_ready)write_response=2'b10;end
            else if(masked_command==2)begin if(!done || active)write_response=2'b10;end
            else if(masked_command!=0)write_response=2'b10;
        end else if(parameters_address)begin
            if((active || done) && saved_wstrb!=0)write_response=2'b10;
            // Reject nonzero upper shape bits instead of truncating a host value.
            if(saved_awaddr>=12'h024 && saved_awaddr<=12'h02c &&
                ((saved_wstrb[2] && saved_wdata[23:16]!=0) ||
                 (saved_wstrb[3] && saved_wdata[31:24]!=0)))write_response=2'b10;
        end else write_response=2'b10;
    end
    function automatic logic readable(input logic [11:0] address);
        return address[1:0]==0 && (address<=12'h09c);
    endfunction
    function automatic logic [31:0] read_word(input logic [11:0] address);
        if(address>=12'h020 && address<=12'h084)return cfg[(address-12'h020)>>2];
        case(address)
            12'h000:return 32'h58495738; // XIW8, distinct from the borrowed matrix core
            12'h004:return 32'd1;        // mailbox ABI, independent of graph ABI v5
            12'h008:return 0;
            12'h00c:return {27'd0,done && completed_status==STATUS_OK,ddr_ready,done,active,idle_ready};
            12'h010:return completed_id;
            12'h014:return {24'd0,completed_status};
            12'h018:return completed_cycles;
            12'h01c:return GROUP_SIZE;
            12'h088:return {16'(ROWS),16'(COLS)};
            12'h08c:return TILE_K;
            12'h090:return MAX_M;
            12'h094:return MAX_N;
            12'h098:return MAX_K;
            12'h09c:return 64;
            default:return 0;
        endcase
    endfunction
    always_ff @(posedge clk)begin
        if(rst)begin
            aw_pending<=0;w_pending<=0;active<=0;pending<=0;done<=0;
            saved_awaddr<=0;saved_wdata<=0;saved_wstrb<=0;
            completed_id<=0;completed_status<=0;completed_cycles<=0;
            s_axi_bvalid<=0;s_axi_bresp<=0;s_axi_rvalid<=0;s_axi_rdata<=0;s_axi_rresp<=0;
            for(integer i=0;i<26;i++)cfg[i]<=0;
            cfg[19]<=32'h01010101;cfg[20]<=GROUP_SIZE;
        end else begin
            if(s_axi_bvalid && s_axi_bready)s_axi_bvalid<=0;
            if(s_axi_rvalid && s_axi_rready)s_axi_rvalid<=0;
            if(s_axi_awvalid && s_axi_awready)begin aw_pending<=1;saved_awaddr<=s_axi_awaddr;end
            if(s_axi_wvalid && s_axi_wready)begin w_pending<=1;saved_wdata<=s_axi_wdata;saved_wstrb<=s_axi_wstrb;end
            if(s_axi_arvalid && s_axi_arready)begin
                s_axi_rvalid<=1;s_axi_rdata<=readable(s_axi_araddr)?read_word(s_axi_araddr):0;
                s_axi_rresp<=readable(s_axi_araddr)?2'b00:2'b10;
            end
            if(task_valid && task_ready)pending<=0;
            if(completion_valid && completion_ready)begin
                active<=0;done<=1;completed_id<=completion_task_id;
                completed_status<=completion_status;completed_cycles<=elapsed_cycles;
            end
            if(commit_write)begin
                aw_pending<=0;w_pending<=0;s_axi_bvalid<=1;s_axi_bresp<=write_response;
                if(write_response==0)begin
                    if(saved_awaddr==12'h008)begin
                        if(masked_command==1)begin active<=1;pending<=1;end
                        else if(masked_command==2)done<=0;
                    end else if(parameters_address)begin
                        for(integer b=0;b<4;b++)if(saved_wstrb[b])
                            cfg[(saved_awaddr-12'h020)>>2][b*8+:8]<=saved_wdata[b*8+:8];
                    end
                end
            end
        end
    end
endmodule
