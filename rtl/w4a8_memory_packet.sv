// Finite gather/repack. Weight row windows preserve the original packet ABI;
// sx is immutable within a linear task and cached by M-block/group context.
module w4a8_memory_packet #(
    parameter integer ADDR_WIDTH=32,ROWS=4,COLS=4,TILE_K=8,GROUP_SIZE=32,
    CHUNK_READ=1,BURST_READ=1,WEIGHT_CACHE=1,SX_CACHE=1
)(
    input logic clk,rst,enable,abort_task,
    input w4a8_memory_pkg::memory_task_t desc,
    input logic req_valid,output logic req_ready,
    input logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group,
    input logic req_scale,req_activation,
    output logic in_valid,input logic in_ready,output logic [63:0] in_data,
    output logic [7:0] in_keep,output logic fault,output logic idle,
    output logic rd_valid,input logic rd_ready,output logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [3:0] rd_bytes,output logic [15:0] rd_span,
    input logic rsp_valid,output logic rsp_ready,input logic [63:0] rsp_data,
    input logic [3:0] rsp_bytes,input logic rsp_error,output logic read_fault,
    output logic [3:0] buffer_used
);
    localparam integer SX_GROUPS=128;
    typedef enum logic [3:0] {EMPTY,BUILD,FETCH,RETURN_BYTE,SEND,STOP,W_CHECK,W_FETCH,W_RETURN} state_t;
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
    // At most two real weight rows, sixteen useful bytes per row. A window is
    // completely filled before any packet using it is exposed to the core.
    logic [127:0] weight_row[0:1];
    logic weight_valid,weight_bank;
    logic [15:0] weight_pos,weight_lane;
    logic [4:0] weight_len,weight_fill;
    wire weight_reading=state==W_CHECK || state==W_FETCH || state==W_RETURN;
    wire weight_hit=weight_valid && lane==weight_lane && pos>=weight_pos &&
        17'(pos)<17'(weight_pos)+17'(weight_len);
    // Independent byte banks infer finite distributed RAM without resetting its
    // data. Only the 128 validity bits and one M/ml tag require reset.
    logic [SX_GROUPS-1:0] sx_valid;
    logic sx_tag_valid;logic [15:0] sx_m,sx_ml;
    wire sx_hit=SX_CACHE && sx_tag_valid && rm==sx_m && ml==sx_ml &&
        rg<SX_GROUPS && sx_valid[7'(rg)];
    wire [ROWS*16-1:0] sx_line;
    wire [ROWS*16-1:0] sx_piece=sx_line>>(integer'(pos)*8);
    generate for(genvar sb=0;sb<2*ROWS;sb++) begin: scale_byte_bank
        // A private array per generated bank is required for single-write-port
        // RAM inference. A shared two-dimensional array becomes a register bank.
        (* ram_style = "distributed" *) logic [7:0] bytes[0:SX_GROUPS-1];
        wire first_byte=17'(pos)+17'(slot)==sb;
        wire second_byte=rsp_bytes==2 && 17'(pos)+17'(slot)+1==sb;
        wire write_byte=!rst && !abort_task && SX_CACHE && state==RETURN_BYTE &&
            phase==2 && rsp_valid && !rsp_error && rsp_bytes>0 &&
            rsp_bytes<=rd_bytes && slot+rsp_bytes<=8 && rg<SX_GROUPS &&
            (first_byte || second_byte);
        assign sx_line[sb*8+:8]=bytes[7'(rg)];
        always_ff @(posedge clk) if(write_byte)
            bytes[7'(rg)]<=first_byte?rsp_data[7:0]:rsp_data[15:8];
    end endgenerate
    always_comb begin
        case(phase)
            0:span={1'b0,wspan};1:span={1'b0,kl};
            2:span=2*{1'b0,ml};default:span=2*{1'b0,nl};
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
        rd_span=BURST_READ && phase==1?16'(span)-pos-16'(slot):16'(rd_bytes);
        if(weight_reading) begin
            address_wide=65'(desc.w_base)+(65'(rn)+65'(weight_lane)+65'(weight_bank))*65'(desc.w_stride)+65'(rk/2)+65'(weight_pos)+65'(weight_fill);
            rd_bytes=CHUNK_READ?((weight_len-weight_fill>=8)?4'd8:4'(weight_len-weight_fill)):4'd1;
            rd_span=BURST_READ && CHUNK_READ?16'(weight_len)-16'(weight_fill):16'(rd_bytes);
        end
    end
    assign idle=state==EMPTY;
    assign req_ready=idle && enable && !rst && !abort_task;
    assign rd_valid=(state==FETCH || state==W_FETCH) && !abort_task && !rst;
    assign rd_addr=address_wide[ADDR_WIDTH-1:0];
    assign rsp_ready=(state==RETURN_BYTE || state==W_RETURN || abort_task) && !rst;
    assign in_valid=state==SEND && !abort_task && !rst;
    always_comb begin
        buffer_used=0;for(integer b=0;b<8;b++) buffer_used=buffer_used+4'(in_keep[b]);
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=EMPTY;fault<=0;read_fault<=0;in_data<=0;in_keep<=0;
            rm<=0;rn<=0;rk<=0;ml<=0;nl<=0;kl<=0;rg<=0;wspan<=0;
            lane<=0;pos<=0;phase<=0;slot<=0;scales<=0;activations<=0;
            weight_valid<=0;weight_bank<=0;weight_pos<=0;weight_lane<=0;weight_len<=0;weight_fill<=0;
            sx_valid<=0;sx_tag_valid<=0;sx_m<=0;sx_ml<=0;
        end else if(abort_task) begin state<=STOP;in_keep<=0;weight_valid<=0;sx_valid<=0;end
        else case(state)
            EMPTY:if(req_valid && req_ready) begin
                rm<=req_m;rn<=req_n;rk<=req_k;ml<=req_ml;nl<=req_nl;kl<=req_kl;rg<=req_group;
                scales<=req_scale;activations<=req_activation;
                wspan<=(17'(req_k[0])+17'(req_kl)+1)/2;
                phase<=0;lane<=0;pos<=0;slot<=0;in_data<=64'ha5a5a5a5a5a5a5a5;in_keep<=0;weight_valid<=0;
                if(!sx_tag_valid || req_m!=sx_m || req_ml!=sx_ml) sx_valid<=0;
                sx_m<=req_m;sx_ml<=req_ml;sx_tag_valid<=1;
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
                end else if(phase==0 && WEIGHT_CACHE) begin
                    if(!weight_hit) begin
                        weight_valid<=0;weight_pos<=pos;weight_lane<=lane;weight_bank<=0;weight_fill<=0;
                        weight_len<=(span-17'(pos)>16)?5'd16:5'(span-17'(pos));state<=W_CHECK;
                    end else begin
                        for(integer b=0;b<4;b++) if(b<contiguous) begin
                            in_data[(integer'(slot)+b)*8+:8]<=weight_row[slot/4][(integer'(pos-weight_pos)+integer'(slot%4)+b)*8+:8];
                            in_keep[integer'(slot)+b]<=1;
                        end
                        slot<=slot+4'(contiguous);
                    end
                end else if(phase==2 && sx_hit) begin
                    for(integer b=0;b<8;b++) if(b>=slot && 17'(pos)+b<span) begin
                        in_data[b*8+:8]<=sx_piece[b*8+:8];in_keep[b]<=1;
                    end
                    slot<=span-17'(pos)<8?4'(span-17'(pos)):4'd8;
                end else state<=FETCH;
            W_CHECK:if(weight_len==0 || weight_fill>=weight_len ||
                address_wide<65'(desc.w_base) || address_wide+65'(rd_span)>65'(desc.w_base)+65'(desc.w_bytes) ||
                address_wide>=(65'd1<<ADDR_WIDTH)) begin fault<=1;state<=STOP;end
                else state<=W_FETCH;
            W_FETCH:if(rd_ready) state<=W_RETURN;
            W_RETURN:if(rsp_valid) begin
                if(rsp_error) begin read_fault<=1;weight_valid<=0;state<=STOP;end
                else if(rsp_bytes==0 || rsp_bytes>rd_bytes || 6'(weight_fill)+6'(rsp_bytes)>6'(weight_len)) begin fault<=1;state<=STOP;end
                else begin
                    for(integer b=0;b<8;b++) if(b<rsp_bytes) weight_row[weight_bank][(integer'(weight_fill)+b)*8+:8]<=rsp_data[b*8+:8];
                    if(weight_fill+5'(rsp_bytes)==weight_len) begin
                        if(!weight_bank && weight_lane+1<nl) begin weight_bank<=1;weight_fill<=0;state<=W_CHECK;end
                        else begin weight_valid<=1;state<=BUILD;end
                    end else begin weight_fill<=weight_fill+5'(rsp_bytes);state<=W_CHECK;end
                end
            end
            FETCH:if(rd_ready) state<=RETURN_BYTE;
            RETURN_BYTE:if(rsp_valid) begin
                if(rsp_error) begin read_fault<=1;state<=STOP;end
                else if(rsp_bytes==0 || rsp_bytes>rd_bytes || slot+rsp_bytes>8) begin fault<=1;state<=STOP;end
                else begin
                    for(integer b=0;b<8;b++) if(b<rsp_bytes) begin
                        in_data[(integer'(slot)+b)*8+:8]<=rsp_data[b*8+:8];in_keep[integer'(slot)+b]<=1;
                    end
                    slot<=slot+rsp_bytes;state<=BUILD;
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
                        2:begin phase<=3;if(SX_CACHE && rg<SX_GROUPS) sx_valid[7'(rg)]<=1;end
                        3:state<=EMPTY;
                    endcase
                end
            end
            default:;
        endcase
    end
endmodule
