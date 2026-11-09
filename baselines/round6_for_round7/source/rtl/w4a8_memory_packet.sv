// Original implementation: finite gather/repack, not the TB reuse memory.
module w4a8_memory_packet #(
    parameter integer ADDR_WIDTH=32,ROWS=4,COLS=4,TILE_K=8,GROUP_SIZE=32,CHUNK_READ=1,BURST_READ=1
)(
    input logic clk,rst,enable,abort_task,
    input w4a8_memory_pkg::memory_task_t desc,
    input logic req_valid,output logic req_ready,
    input logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group,
    input logic req_scale,req_activation,
    output logic in_valid,input logic in_ready,output logic [63:0] in_data,
    output logic [7:0] in_keep,output logic fault,output logic idle,
    output logic rd_valid,input logic rd_ready,output logic [ADDR_WIDTH-1:0] rd_addr,output logic [3:0] rd_bytes,output logic [15:0] rd_span,
    input logic rsp_valid,output logic rsp_ready,input logic [63:0] rsp_data,input logic [3:0] rsp_bytes,
    input logic rsp_error,output logic read_fault,
    output logic [3:0] buffer_used
);
    typedef enum logic [2:0] {EMPTY,BUILD,FETCH,RETURN_BYTE,SEND,STOP} state_t;
    state_t state;
    logic [15:0] rm,rn,rk,ml,nl,kl,rg,wspan,lane,pos;
    logic scales,activations;
    logic [1:0] phase;
    logic [3:0] slot;
    logic byte_valid;
    logic [64:0] address_wide,limit_wide;
    logic [63:0] region_base;logic [31:0] region_bytes;
    logic [16:0] span;
    integer contiguous;
    always_comb begin
        case(phase)
            0:span={1'b0,wspan};
            1:span={1'b0,kl};
            2:span=2*{1'b0,ml};
            default:span=2*{1'b0,nl};
        endcase
        byte_valid=0;address_wide=0;region_base=0;region_bytes=0;
        case(phase)
            0:begin
                byte_valid=lane+16'(slot/4)<nl && 17'(pos)+17'(slot%4)<span;
                region_base=desc.w_base;region_bytes=desc.w_bytes;
                address_wide=65'(desc.w_base)+(65'(rn)+65'(lane)+65'(slot/4))*65'(desc.w_stride)+65'(rk/2)+65'(pos)+65'(slot%4);
            end
            1:begin
                byte_valid=17'(pos)+17'(slot)<span;
                region_base=desc.a_base;region_bytes=desc.a_bytes;
                address_wide=65'(desc.a_base)+(65'(rm)+65'(lane))*65'(desc.a_stride)+65'(rk)+65'(pos)+65'(slot);
            end
            2:begin
                byte_valid=17'(pos)+17'(slot)<span;
                region_base=desc.sx_base;region_bytes=desc.sx_bytes;
                address_wide=65'(desc.sx_base)+(65'(rm)+(65'(pos)+65'(slot))/2)*65'(desc.sx_stride)+2*65'(rg)+(65'(pos)+65'(slot))%2;
            end
            3:begin
                byte_valid=17'(pos)+17'(slot)<span;
                region_base=desc.sw_base;region_bytes=desc.sw_bytes;
                address_wide=65'(desc.sw_base)+65'(rg)*65'(desc.sw_stride)+2*65'(rn)+65'(pos)+65'(slot);
            end
        endcase
        limit_wide=65'(region_base)+65'(region_bytes);
        case(phase)
            0:contiguous=4-integer'(slot%4);
            2:contiguous=2-integer'((pos+slot)%2);
            default:contiguous=8-integer'(slot);
        endcase
        if(phase==0) begin
            if(contiguous>integer'(span)-integer'(pos)-integer'(slot%4)) contiguous=integer'(span)-integer'(pos)-integer'(slot%4);
        end else if(contiguous>integer'(span)-integer'(pos)-integer'(slot)) contiguous=integer'(span)-integer'(pos)-integer'(slot);
        rd_bytes=CHUNK_READ && contiguous>0?4'(contiguous):4'd1;
        // Activation packets traverse one useful row in ascending byte order.
        // Other phases can gather discontiguous rows: never prefetch across them.
        rd_span=BURST_READ && phase==1 ? 16'(span)-pos-16'(slot) : 16'(rd_bytes);
    end
    assign idle=state==EMPTY;
    assign req_ready=idle && enable && !rst && !abort_task;
    assign rd_valid=state==FETCH && !abort_task && !rst;
    assign rd_addr=address_wide[ADDR_WIDTH-1:0];
    assign rsp_ready=(state==RETURN_BYTE || abort_task) && !rst;
    assign in_valid=state==SEND && !abort_task && !rst;
    always_comb begin
        buffer_used=0;
        for(integer b=0;b<8;b++) buffer_used=buffer_used+4'(in_keep[b]);
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=EMPTY;fault<=0;read_fault<=0;in_data<=0;in_keep<=0;
            rm<=0;rn<=0;rk<=0;ml<=0;nl<=0;kl<=0;rg<=0;wspan<=0;
            lane<=0;pos<=0;phase<=0;slot<=0;scales<=0;activations<=0;
        end else if(abort_task) begin state<=STOP;in_keep<=0;end
        else case(state)
            EMPTY:if(req_valid && req_ready) begin
                rm<=req_m;rn<=req_n;rk<=req_k;ml<=req_ml;nl<=req_nl;kl<=req_kl;rg<=req_group;
                scales<=req_scale;activations<=req_activation;
                wspan<=(17'(req_k[0])+17'(req_kl)+1)/2;
                phase<=0;lane<=0;pos<=0;slot<=0;in_data<=64'ha5a5a5a5a5a5a5a5;in_keep<=0;
                if(req_ml==0 || req_ml>ROWS || req_nl==0 || req_nl>COLS || req_kl==0 || req_kl>TILE_K ||
                    17'(req_m)+17'(req_ml)>17'(desc.m) || 17'(req_n)+17'(req_nl)>17'(desc.n) ||
                    17'(req_k)+17'(req_kl)>17'(desc.k) || req_k/GROUP_SIZE!=req_group ||
                    (17'(req_k)+17'(req_kl)-1)/GROUP_SIZE!=req_group) begin fault<=1;state<=STOP;end
                else state<=BUILD;
            end
            BUILD:if(slot==8) state<=SEND;
                else if(!byte_valid) slot<=slot+1;
                else if(address_wide<65'(region_base) || address_wide+65'(rd_span)>limit_wide || address_wide>=(65'd1<<ADDR_WIDTH)) begin
                    fault<=1;state<=STOP;
                end else state<=FETCH;
            FETCH:if(rd_ready) state<=RETURN_BYTE;
            RETURN_BYTE:if(rsp_valid) begin
                if(rsp_error) begin read_fault<=1;state<=STOP;end
                else begin
                    if(rsp_bytes==0 || rsp_bytes>rd_bytes || slot+rsp_bytes>8) begin fault<=1;state<=STOP;end
                    else begin
                        for(integer b=0;b<8;b++) if(b<rsp_bytes) begin
                            in_data[(integer'(slot)+b)*8 +:8]<=rsp_data[b*8 +:8];in_keep[integer'(slot)+b]<=1;
                        end
                        slot<=slot+rsp_bytes;state<=BUILD;
                    end
                end
            end
            SEND:if(in_ready) begin
                slot<=0;in_data<=64'ha5a5a5a5a5a5a5a5;in_keep<=0;state<=BUILD;
                if(17'(pos)+((phase==0)?17'd4:17'd8)<span) pos<=pos+((phase==0)?16'd4:16'd8);
                else begin
                    pos<=0;
                    case(phase)
                        0:if(lane+2<nl) lane<=lane+2;
                            else begin lane<=0;if(activations) phase<=1;else if(scales) phase<=2;else state<=EMPTY;end
                        1:if(lane+1<ml) lane<=lane+1;
                            else begin lane<=0;if(scales) phase<=2;else state<=EMPTY;end
                        2:phase<=3;
                        3:state<=EMPTY;
                    endcase
                end
            end
            default:;
        endcase
    end
endmodule
