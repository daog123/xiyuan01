`timescale 1ns/1ps
module tb_axi_burst_protocol #(parameter integer ADDR_WIDTH=64,MAX_BEATS=4);
    logic clk=0;always #5 clk=~clk;
    logic rst=1,cmd_valid=0,cmd_ready,rsp_valid,rsp_ready=0,rsp_error,idle;
    logic [ADDR_WIDTH-1:0] cmd_addr=0,araddr;
    logic [3:0] cmd_bytes=1,rsp_bytes,arid,rid=0;
    logic [15:0] cmd_span=1;
    logic [63:0] rsp_data,rdata=0;
    logic [7:0] arlen;logic [2:0] arsize;logic [1:0] arburst,rresp=0;
    logic arvalid,arready=0,rvalid=0,rready,rlast=1;
    integer checks=0,responses=0,addresses=0;
    w4a8_axi_read_burst #(.ADDR_WIDTH(ADDR_WIDTH),.MAX_BEATS(MAX_BEATS)) dut(.*);
    task automatic require(input bit c,input string msg);
        checks++;if(!c)$fatal(1,"BURST_CHECK_FAILED %s t=%0t",msg,$time);
    endtask
    always @(posedge clk) if(!rst) begin
        if(rsp_valid && rsp_ready) responses++;
        if(arvalid && arready) addresses++;
    end
    function automatic logic [63:0] value(input integer addr,input integer size);
        logic [63:0] v;v=0;
        for(integer j=0;j<size;j++) v[j*8+:8]=8'((addr+j)*37+5);
        return v;
    endfunction
    task automatic reset_reader;
        @(negedge clk);rst=1;cmd_valid=0;arready=0;rvalid=0;rsp_ready=0;
        repeat(3)@(negedge clk);
        require(!arvalid && !rready && !rsp_valid && !cmd_ready,"reset gating");
        rst=0;@(negedge clk);require(idle && cmd_ready,"reset releases reader");
    endtask
    task automatic command(input integer addr,input integer bound,span,size,beats);
        integer old_ar;old_ar=addresses;
        @(negedge clk);cmd_addr=ADDR_WIDTH'(addr);cmd_bytes=4'(bound);cmd_span=16'(span);cmd_valid=1;arready=0;
        @(negedge clk);cmd_valid=0;cmd_addr=~ADDR_WIDTH'(addr);cmd_bytes=1;cmd_span=1;
        repeat(3)begin
            @(negedge clk);
            require(arvalid && araddr==ADDR_WIDTH'(addr) && (1<<arsize)==size && arlen==beats-1,"held AR address/size/len");
            require(arid==0 && arburst==1 && !cmd_ready && !rsp_valid,"single outstanding");
            require(addr%size==0 && beats*size<=span && (addr%4096)+beats*size<=4096,"bounded useful range");
        end
        arready=1;@(negedge clk);arready=0;
        require(addresses==old_ar+1 && rready && !arvalid,"AR accepted once");
    endtask
    task automatic beat(input integer addr,size,input bit last,input integer id,resp);
        @(negedge clk);rvalid=1;rlast=last;rid=4'(id);rresp=2'(resp);
        rdata=value(addr,size)<<(8*(addr%8));require(rready,"all issued beats have reserved capacity");
        @(negedge clk);rvalid=0;rlast=1;rid=0;rresp=0;rdata=0;
    endtask
    task automatic consume(input integer addr,size,input bit err);
        integer old_rsp;old_rsp=responses;
        repeat(4)begin
            @(negedge clk);
            require(rsp_valid && rsp_data==value(addr,size) && rsp_bytes==size && rsp_error==err,"stable response payload");
            require(!cmd_ready && !arvalid && !rready,"response holds ownership under backpressure");
        end
        rsp_ready=1;@(negedge clk);rsp_ready=0;
        require(responses==old_rsp+1 && idle && !rsp_valid,"one response per command");
    endtask
    task automatic cached(input integer addr,size);
        integer old_ar;old_ar=addresses;
        @(negedge clk);cmd_addr=ADDR_WIDTH'(addr);cmd_bytes=4'(size);cmd_span=16'(size);cmd_valid=1;
        @(negedge clk);cmd_valid=0;
        require(!arvalid && addresses==old_ar,"cached beat needs no AR");consume(addr,size,0);
    endtask
    initial begin
        integer size,beats,n,old_rsp;
        reset_reader();
        // Exhaustive narrow alignment/tail choices. No padding permissions assumed.
        for(integer lane=0;lane<8;lane++)for(integer bound=1;bound<=8;bound++)begin
            size=1;if(bound>=8 && lane==0)size=8;else if(bound>=4 && lane%4==0)size=4;else if(bound>=2 && lane%2==0)size=2;
            command(4088+lane,bound,bound,size,1);beat(4088+lane,size,1,0,0);consume(4088+lane,size,0);
        end
        beats=MAX_BEATS;
        command(8192,8,8*beats+7,8,beats);
        for(integer b=0;b<beats;b++)begin
            repeat(b%3)@(negedge clk);beat(8192+8*b,8,b==beats-1,0,0);
            if(b<beats-1)require(!rsp_valid,"no partial burst exposed");
        end
        consume(8192,8,0);for(integer b=1;b<beats;b++)cached(8192+8*b,8);
        // An allocation can continue past 4KiB; one AR cannot.
        n=MAX_BEATS<2?MAX_BEATS:2;command(4080,8,64,8,n);
        for(integer b=0;b<n;b++)beat(4080+8*b,8,b==n-1,0,0);
        consume(4080,8,0);for(integer b=1;b<n;b++)cached(4080+8*b,8);
        command(4096,8,8,8,1);beat(4096,8,1,0,0);consume(4096,8,0);
        // Every beat, including the middle/final beat, can poison the burst.
        for(integer bad=0;bad<beats;bad++)for(integer kind=0;kind<2;kind++)begin
            command(16384,8,8*beats,8,beats);
            for(integer b=0;b<beats;b++)beat(16384+8*b,8,b==beats-1,(kind==0 && b==bad)?7:0,(kind==1 && b==bad)?2:0);
            consume(16384,8,1);
        end
        if(beats>1)begin
            command(16384,8,8*beats,8,beats);beat(16384,8,1,0,0);consume(16384,8,1);
        end
        command(16384,8,8*beats,8,beats);
        for(integer b=0;b<beats;b++)beat(16384+8*b,8,0,0,0);
        old_rsp=responses;
        repeat(7)begin @(negedge clk);require(!rsp_valid && !cmd_ready && rready && responses==old_rsp,"late RLAST drains before response");end
        beat(0,8,0,3,2);beat(0,8,1,0,0);consume(16384,8,1);
        // Reset with AR stalled, with responses outstanding, in drain, with FIFO full.
        @(negedge clk);cmd_addr=0;cmd_bytes=8;cmd_span=32;cmd_valid=1;
        @(negedge clk);cmd_valid=0;reset_reader();
        command(8192,8,8*beats,8,beats);reset_reader();
        command(8192,8,8*beats,8,beats);for(integer b=0;b<beats;b++)beat(8192+8*b,8,0,0,0);reset_reader();
        command(8192,8,8*beats,8,beats);for(integer b=0;b<beats;b++)beat(8192+8*b,8,b==beats-1,0,0);reset_reader();
        // Discontinuous commands invalidate unread cache slots, never return stale data.
        command(8192,8,8*beats,8,beats);for(integer b=0;b<beats;b++)beat(8192+8*b,8,b==beats-1,0,0);consume(8192,8,0);
        command(24576,4,4,4,1);beat(24576,4,1,0,0);consume(24576,4,0);
        command(8192,8,8,8,1);beat(8192,8,1,0,0);consume(8192,8,0);
        $display("BURST_PROTOCOL_PASS address_width=%0d capacity=%0d checks=%0d responses=%0d addresses=%0d",ADDR_WIDTH,MAX_BEATS,checks,responses,addresses);$finish;
    end
    initial begin #2000000;$fatal(1,"BURST_PROTOCOL_TIMEOUT");end
endmodule
module tb_axi_burst_protocol32;tb_axi_burst_protocol #(.ADDR_WIDTH(32)) test();endmodule
module tb_axi_burst_protocol1;tb_axi_burst_protocol #(.MAX_BEATS(1)) test();endmodule
module tb_axi_burst_protocol8;tb_axi_burst_protocol #(.MAX_BEATS(8)) test();endmodule
module tb_w4a8_memory_burst;tb_w4a8_memory #(.TILE_K(32),.REQUIRE_BURST(1)) test();endmodule
module tb_w4a8_memory_burst8;tb_w4a8_memory #(.ROWS(8),.COLS(8),.TILE_K(32),.REQUIRE_BURST(1)) test();endmodule
