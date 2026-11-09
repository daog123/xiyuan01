// TB-only source: lane-aligned words, compact scales, finite bandwidth modes.
module w4a8_reuse_memory #(
    parameter integer GROUP_SIZE=32,MAX_DATA=8192,BUS_BYTES=8,
    parameter bit PACK_COLS=1,
    parameter integer FIRST_DELAY=5,BURST_BYTES=8,BURST_GAP=4,REQUEST_PERIOD=5,
    parameter logic [31:0] RANDOM_SEED=32'h20261012
)(
    input logic clk,rst,task_start,
    input integer mode,m,n,k,ng,
    input logic req_valid,req_scale,req_activation,
    output logic req_ready,
    input logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group,
    output logic in_valid,
    input logic in_ready,
    output logic [BUS_BYTES*8-1:0] in_data,
    output logic [BUS_BYTES-1:0] in_keep
);
    localparam integer W_LANES=(PACK_COLS && BUS_BYTES==8)?2:1;
    localparam integer W_BYTES=BUS_BYTES/W_LANES;
    integer a[0:MAX_DATA-1],packed_w[0:MAX_DATA-1],sx[0:MAX_DATA-1],sw[0:MAX_DATA-1];
    integer rm,rn,rk,rml,rnl,rkl,rg,wspan,phase,lane,position,cooldown;
    integer ticks=0,requests=0,accepted=0,beats=0,wire_bytes=0;
    bit active=0,scales=0,activations=0;
    logic [31:0] rng=RANDOM_SEED;
    assign req_ready=!rst && !active && (mode!=2 || ticks%REQUEST_PERIOD!=0);
    function automatic integer span;
        case(phase)
            0:span=wspan;
            1:span=rkl;
            2:span=2*rml;
            default:span=2*rnl;
        endcase
    endfunction
    function automatic [7:0] value_at(input integer pos,weight_lane);
        integer address,value;
        begin
            case(phase)
                0:begin
                    address=(rn+lane+weight_lane)*((k+1)/2)+rk/2+pos;
                    if(rn+lane+weight_lane>=n || rk/2+pos>=(k+1)/2 || address>=MAX_DATA) $fatal(1,"STREAM_MEMORY_WEIGHT_OOB");
                    value_at=packed_w[address];
                end
                1:begin
                    address=(rm+lane)*k+rk+pos;
                    if(rm+lane>=m || rk+pos>=k || address>=MAX_DATA) $fatal(1,"STREAM_MEMORY_ACTIVATION_OOB");
                    value_at=a[address];
                end
                2:begin
                    address=(rm+pos/2)*ng+rg;
                    if(rm+pos/2>=m || rg>=ng || address>=MAX_DATA) $fatal(1,"STREAM_MEMORY_SX_OOB");
                    value=sx[address];value_at=(pos%2)?(value>>8):(value&255);
                end
                3:begin
                    address=rg*n+rn+pos/2;
                    if(rn+pos/2>=n || rg>=ng || address>=MAX_DATA) $fatal(1,"STREAM_MEMORY_SW_OOB");
                    value=sw[address];value_at=(pos%2)?(value>>8):(value&255);
                end
            endcase
        end
    endfunction
    task automatic advance_word;
        begin
            if(position+((phase==0)?W_BYTES:BUS_BYTES)<span()) position=position+((phase==0)?W_BYTES:BUS_BYTES);
            else begin
                position=0;
                case(phase)
                    0:if(lane+W_LANES<rnl) lane=lane+W_LANES;else begin lane=0;if(activations) phase=1;else if(scales) phase=2;else active<=0;end
                    1:if(lane+1<rml) lane=lane+1;
                      else if(scales) begin lane=0;phase=2;end
                      else active<=0;
                    2:phase=3;
                    3:active<=0;
                endcase
            end
        end
    endtask
    always @(posedge clk) begin
        if(rst) begin
            active<=0;in_valid<=0;in_data<=0;in_keep<=0;position=0;cooldown<=0;ticks<=0;
            requests<=0;accepted<=0;beats<=0;wire_bytes<=0;rng<=RANDOM_SEED;phase=0;lane=0;scales=0;activations=0;
        end else begin
            ticks<=ticks+1;
            if(task_start) begin requests<=0;accepted<=0;beats<=0;wire_bytes<=0;rng<=RANDOM_SEED;end
            if(req_valid && req_ready) begin
                if(req_ml==0 || req_nl==0 || req_kl==0 || req_m+req_ml>m || req_n+req_nl>n ||
                   req_k+req_kl>k || req_k/GROUP_SIZE!=req_group ||
                   (req_k+req_kl-1)/GROUP_SIZE!=req_group) $fatal(1,"STREAM_MEMORY_BAD_REQUEST");
                rm=req_m;rn=req_n;rk=req_k;rml=req_ml;rnl=req_nl;rkl=req_kl;rg=req_group;
                wspan=(rk%2+rkl+1)/2;phase=0;lane=0;position=0;scales=req_scale;activations=req_activation;
                active<=1;requests<=requests+1;wire_bytes<=0;
                cooldown<=(mode==0)?0:FIRST_DELAY;
            end
            if(in_valid && in_ready) begin
                integer count;
                count=0;for(integer j=0;j<BUS_BYTES;j++)count+=in_keep[j];
                accepted<=accepted+count;beats<=beats+1;wire_bytes<=wire_bytes+BUS_BYTES;in_valid<=0;
                advance_word();
                // Mode1 budget includes padding: same max physical bytes/time across bus widths.
                if(mode==1) cooldown<=BUS_BYTES-1+(((wire_bytes+BUS_BYTES)%BURST_BYTES==0)?BURST_GAP:0);
            end
        end
    end
    always @(negedge clk) begin
        if(!rst && active) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            if(!in_valid) begin
                if(cooldown>0) cooldown=cooldown-1;
                else if(mode!=2 || rng[1:0]!=0) begin
                    in_keep=0;
                    for(integer j=0;j<BUS_BYTES;j++) begin
                        in_data[j*8 +:8]=8'ha5;
                        if(phase==0) begin
                            if(lane+j/W_BYTES<rnl && position+j%W_BYTES<wspan) begin
                                in_data[j*8 +:8]=value_at(position+j%W_BYTES,j/W_BYTES);in_keep[j]=1;
                            end
                        end else if(position+j<span()) begin
                            in_data[j*8 +:8]=value_at(position+j,0);in_keep[j]=1;
                        end
                    end
                    in_valid=1;
                end
            end
        end
    end
endmodule
