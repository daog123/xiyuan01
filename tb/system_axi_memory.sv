// TB-only finite AXI slave. Permissions come from the independent byte oracle.
module system_axi_memory #(parameter integer ADDR_WIDTH=64,SIZE=65536,
    // Negative values retain randomized regression behavior. Nonnegative values
    // give cycle-comparable performance runs with identical transaction service.
    parameter integer READ_DELAY=-1,WRITE_DELAY=-1,
    parameter logic [63:0] BASE=64'h1_0000_0000)(
    input logic clk,rst,setup,hold_b,hold_r,inject_r,inject_b,
    input logic arvalid,output logic arready,input logic [ADDR_WIDTH-1:0] araddr,
    input logic [3:0] arid,input logic [7:0] arlen,input logic [2:0] arsize,input logic [1:0] arburst,
    output logic rvalid,input logic rready,output logic [63:0] rdata,
    output logic [3:0] rid,output logic [1:0] rresp,output logic rlast,
    input logic awvalid,output logic awready,input logic [ADDR_WIDTH-1:0] awaddr,
    input logic [3:0] awid,input logic [7:0] awlen,input logic [2:0] awsize,input logic [1:0] awburst,
    input logic wvalid,output logic wready,input logic [63:0] wdata,input logic [7:0] wstrb,input logic wlast,
    output logic bvalid,input logic bready,output logic [3:0] bid,output logic [1:0] bresp,
    output integer reads,writes,b_count
);
    logic [7:0] mem[0:SIZE-1],read_allowed[0:SIZE-1],write_allowed[0:SIZE-1];
    logic [31:0] rng;
    bit rp,ap,wp,bp,saved_re,saved_be;integer ra,wa,rd_delay,bd_delay,sz,rsz,read_payload,remaining,read_beats,burst_reads;
    logic [63:0] wd;logic [7:0] ws;
    assign arready=!rst && !rp && !rvalid && (READ_DELAY>=0 || rng[2:0]>1);
    assign awready=!rst && !ap && !bp && !bvalid && (WRITE_DELAY>=0 || rng[6:4]>2);
    assign wready=!rst && !wp && !bp && !bvalid && (WRITE_DELAY>=0 || rng[10:8]>3);
    always @(posedge clk) begin
        if(rst) begin
            rng<=32'h20261015;rp=0;ap=0;wp=0;bp=0;rvalid<=0;bvalid<=0;
            rdata<=0;rid<=0;rresp<=0;rlast<=1;bid<=0;bresp<=0;reads=0;writes=0;b_count=0;read_payload=0;remaining=0;read_beats=0;burst_reads=0;
        end else begin
            rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            if(setup) begin reads=0;writes=0;b_count=0;read_payload=0;read_beats=0;burst_reads=0;end
            if(rvalid && rready) begin
                rvalid<=0;
                if(remaining>1) begin ra+=rsz;remaining--;rp=1;rd_delay=0;end
            end
            if(bvalid && bready) begin bvalid<=0;b_count++;end
            if(rp && (!rvalid || rready) && !hold_r) begin
                if(rd_delay>0) rd_delay--;
                else begin rp=0;rvalid<=1;rdata<=0;
                    for(integer j=0;j<rsz;j++)rdata[(((BASE+64'(ra))%8)+j)*8 +:8]<=mem[ra+j];
                    rresp<=saved_re?2:0;rlast<=remaining==1;end
            end
            if(bp && !bvalid && !hold_b) begin
                if(bd_delay>0) bd_delay--;
                else begin bp=0;bvalid<=1;bresp<=saved_be?2:0;end
            end
            if(arvalid && arready) begin
                if(arid!=0 || arsize>3 || (64'(araddr)% (1<<arsize))!=0 || arburst!=1 || 65'(araddr)<65'(BASE) ||
                    65'(araddr)+((integer'(arlen)+1)<<arsize)>65'(BASE)+SIZE ||
                    integer'(araddr[11:0])+((integer'(arlen)+1)<<arsize)>4096) $fatal(1,"SYSTEM_AXI_BAD_READ address=%h",araddr);
                ra=integer'(64'(araddr)-BASE);
                rsz=1<<arsize;
                for(integer j=0;j<rsz*(integer'(arlen)+1);j++) if(read_allowed[ra+j]!=1) $fatal(1,"SYSTEM_AXI_READ_PERMISSION offset=%0d",ra+j);
                remaining=integer'(arlen)+1;read_payload+=rsz*remaining;read_beats+=remaining;if(arlen!=0) burst_reads++;
                rp=1;rd_delay=READ_DELAY>=0?READ_DELAY:integer'(rng[15:12]);saved_re=inject_r;reads++;
            end
            if(awvalid && awready) begin
                if(awid!=0 || awlen!=0 || !(awsize==0 || awsize==2) || awburst!=1 ||
                    65'(awaddr)<65'(BASE) || 65'(awaddr)+(1<<awsize)>65'(BASE)+SIZE ||
                    (awsize==2 && awaddr[1:0]!=0)) $fatal(1,"SYSTEM_AXI_BAD_WRITE address=%h",awaddr);
                wa=integer'(64'(awaddr)-BASE);sz=1<<awsize;ap=1;
            end
            if(wvalid && wready) begin
                if(!wlast) $fatal(1,"SYSTEM_AXI_BAD_WLAST");wd=wdata;ws=wstrb;wp=1;
            end
            if(ap && wp) begin
                if(ws!=(((1<<sz)-1)<<((BASE+64'(wa))%8))) $fatal(1,"SYSTEM_AXI_BAD_STROBE");
                for(integer j=0;j<sz;j++) begin
                    if(write_allowed[wa+j]!=1) $fatal(1,"SYSTEM_AXI_WRITE_PERMISSION offset=%0d",wa+j);
                    mem[wa+j]=wd[(((BASE+64'(wa))%8)+j)*8 +:8];
                end
                ap=0;wp=0;bp=1;bd_delay=WRITE_DELAY>=0?WRITE_DELAY:integer'(rng[19:16]);saved_be=inject_b;writes++;
            end
        end
    end
endmodule
