// TB ONLY: independent AXI narrow-transfer slave with finite channel slots.
module w4a8_axi_memory # (parameter integer SIZE=65536)(
    input logic clk,rst,setup,
    input w4a8_memory_pkg::memory_task_t desc,
    input logic random_stalls,hold_b,inject_r,inject_b,inject_rlast,inject_rid,inject_bid,
    input logic arvalid,output logic arready,input logic [31:0] araddr,
    input logic [3:0] arid,input logic [7:0] arlen,input logic [2:0] arsize,input logic [1:0] arburst,
    output logic rvalid,input logic rready,output logic [63:0] rdata,
    output logic [3:0] rid,output logic [1:0] rresp,output logic rlast,
    input logic awvalid,output logic awready,input logic [31:0] awaddr,
    input logic [3:0] awid,input logic [7:0] awlen,input logic [2:0] awsize,input logic [1:0] awburst,
    input logic wvalid,output logic wready,input logic [63:0] wdata,input logic [7:0] wstrb,input logic wlast,
    output logic bvalid,input logic bready,output logic [3:0] bid,output logic [1:0] bresp,
    output integer reads,writes,b_count
);
    import w4a8_memory_pkg::*;
    logic [7:0] mem[0:SIZE-1];
    bit written[0:SIZE/4-1];
    logic [31:0] rng=32'hf13579bd;
    bit rp=0,ap=0,wp=0,bp=0,extra=0;
    integer ra,wa,rd_delay,bd_delay,rsz,read_payload,remaining,read_beats,burst_reads;
    logic [63:0] wd;
    logic [7:0] ws;
    bit saved_re,saved_be,saved_rl,saved_ri,saved_bi;
    function automatic bit in_region(input integer addr,input logic [31:0] base,bytes);
        return 64'(addr)>=64'(base) && 64'(addr)<64'(base)+64'(bytes);
    endfunction
    function automatic bit source_byte(input integer addr);
        integer off,g;
        g=(desc.k+desc.group_size-1)/desc.group_size;
        if(in_region(addr,desc.a_base,desc.a_bytes)) begin
            off=addr-desc.a_base;return off/desc.a_stride<desc.m && off%desc.a_stride<desc.k;
        end
        if(in_region(addr,desc.w_base,desc.w_bytes)) begin
            off=addr-desc.w_base;return off/desc.w_stride<desc.n && off%desc.w_stride<(desc.k+1)/2;
        end
        if(in_region(addr,desc.sx_base,desc.sx_bytes)) begin
            off=addr-desc.sx_base;return off/desc.sx_stride<desc.m && off%desc.sx_stride<2*g;
        end
        if(in_region(addr,desc.sw_base,desc.sw_bytes)) begin
            off=addr-desc.sw_base;return off/desc.sw_stride<g && off%desc.sw_stride<2*desc.n;
        end
        return 0;
    endfunction
    assign arready=!rst && !rp && !rvalid && (!random_stalls || rng[2:0]>1);
    assign awready=!rst && !ap && !bp && !bvalid && (!random_stalls || rng[6:4]>2);
    assign wready=!rst && !wp && !bp && !bvalid && (!random_stalls || rng[10:8]>3);
    always @(posedge clk) begin
        if(rst) begin
            rp=0;ap=0;wp=0;bp=0;extra=0;rvalid<=0;bvalid<=0;rdata<=0;rid<=0;rresp<=0;rlast<=1;
            bid<=0;bresp<=0;reads=0;writes=0;b_count=0;read_payload=0;remaining=0;read_beats=0;burst_reads=0;rng<=32'hf13579bd;
            for(integer i=0;i<SIZE/4;i++) written[i]=0;
        end else begin
            rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            if(setup) begin
                reads=0;writes=0;b_count=0;read_payload=0;read_beats=0;burst_reads=0;
                for(integer i=0;i<SIZE/4;i++) written[i]=0;
            end
            if(rvalid && rready) begin
                rvalid<=0;
                if(extra) begin extra=0;rp=1;rd_delay=3;saved_rl=0;end
                else if(remaining>1) begin remaining--;ra+=rsz;rp=1;rd_delay=0;end
            end
            if(bvalid && bready) begin bvalid<=0;b_count++;end
            if(rp && (!rvalid || rready)) begin
                if(rd_delay>0) rd_delay--;
                else begin
                    rp=0;rvalid<=1;rdata<=0;
                    for(integer b=0;b<rsz;b++)rdata[((ra%8)+b)*8 +:8]<=mem[ra+b];
                    rid<=saved_ri?4'd1:4'd0;rresp<=saved_re?2'd2:2'd0;
                    rlast<=remaining==1 && !saved_rl;extra=saved_rl && remaining==1;
                end
            end
            if(bp && !bvalid && !hold_b) begin
                if(bd_delay>0) bd_delay--;
                else begin bp=0;bvalid<=1;bresp<=saved_be?2'd2:2'd0;bid<=saved_bi?4'd1:4'd0;end
            end
            if(arvalid && arready) begin
                if(arid!=0 || arsize>3 || araddr%(1<<arsize)!=0 || arburst!=1 || 65'(araddr)+((integer'(arlen)+1)<<arsize)>SIZE ||
                    integer'(araddr[11:0])+((integer'(arlen)+1)<<arsize)>4096)
                    $fatal(1,"AXI_MEMORY_BAD_READ address=%h",araddr);
                rsz=1<<arsize;
                for(integer b=0;b<rsz*(integer'(arlen)+1);b++)if(!source_byte(integer'(araddr)+b))$fatal(1,"AXI_MEMORY_READ_PADDING");
                remaining=integer'(arlen)+1;read_payload+=rsz*remaining;read_beats+=remaining;if(arlen!=0) burst_reads++;ra=araddr;rp=1;rd_delay=random_stalls?integer'(rng[15:12]):1;
                saved_re=inject_r;saved_rl=inject_rlast;saved_ri=inject_rid;reads++;
            end
            if(awvalid && awready) begin
                if(awid!=0 || awlen!=0 || awsize!=2 || awburst!=1 || awaddr[1:0]!=0 ||
                    awaddr+3>=SIZE || !in_region(awaddr,desc.y_base,desc.y_bytes) ||
                    (awaddr-desc.y_base)%desc.y_stride>=4*desc.n) $fatal(1,"AXI_MEMORY_BAD_AW");
                wa=awaddr;ap=1;
            end
            if(wvalid && wready) begin if(!wlast) $fatal(1,"AXI_MEMORY_BAD_WLAST");wd=wdata;ws=wstrb;wp=1;end
            if(ap && wp) begin
                if(ws!=(8'h0f << (wa%8)) || written[wa/4]) $fatal(1,"AXI_MEMORY_WSTRB_OR_DUPLICATE");
                written[wa/4]=1;
                for(integer j=0;j<8;j++) if(ws[j]) begin
                    if(!in_region((wa/8)*8+j,desc.y_base,desc.y_bytes)) $fatal(1,"AXI_MEMORY_WRITE_OOB");
                    mem[(wa/8)*8+j]=wd[j*8 +:8];
                end
                ap=0;wp=0;bp=1;bd_delay=random_stalls?integer'(rng[19:16]):2;
                saved_be=inject_b;saved_bi=inject_bid;writes++;
            end
        end
    end
endmodule

