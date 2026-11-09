`timescale 1ns/1ps
module tb_axi_chunk_protocol #(parameter integer ADDR_WIDTH=64);
    logic clk=0;always #5 clk=~clk;
    logic rst=1,cmd_valid=0,cmd_ready,rsp_valid,rsp_ready=0,rsp_error,idle;
    logic [ADDR_WIDTH-1:0] cmd_addr=0,araddr;logic [3:0] cmd_bytes=1,rsp_bytes;
    logic [63:0] rsp_data;logic [7:0] arlen;
    logic arvalid,arready=0,rvalid=0,rready,rlast=1;
    logic [3:0] arid,rid=0;logic [2:0] arsize;logic [1:0] arburst,rresp=0;
    logic [63:0] rdata=0,last_data;logic last_error;integer last_bytes;
    integer checks=0,responses=0,chosen_size,expected_bytes;
    w4a8_axi_read_chunk #(.ADDR_WIDTH(ADDR_WIDTH)) dut(.*);
    task automatic require(input bit c,input string m);
        checks++;if(!c)$fatal(1,"CHUNK_CHECK_FAILED %s t=%0t",m,$time);
    endtask
    always @(posedge clk)if(!rst && rsp_valid && rsp_ready)begin responses++;last_data=rsp_data;last_error=rsp_error;last_bytes=rsp_bytes;end
    task automatic reset_reader;
        @(negedge clk);rst=1;cmd_valid=0;rvalid=0;arready=0;rsp_ready=0;
        repeat(3)@(negedge clk);require(!arvalid && !rready && !rsp_valid && !cmd_ready,"reset gating");
        rst=0;@(negedge clk);require(idle && cmd_ready,"empty after reset");
    endtask
    task automatic address_stalled(input logic [ADDR_WIDTH-1:0] address,input integer maximum);
        chosen_size=0;
        if(maximum>=8 && address%8==0)chosen_size=3;
        else if(maximum>=4 && address%4==0)chosen_size=2;
        else if(maximum>=2 && address%2==0)chosen_size=1;
        expected_bytes=1<<chosen_size;
        @(negedge clk);cmd_addr=address;cmd_bytes=4'(maximum);cmd_valid=1;arready=0;
        @(negedge clk);cmd_valid=0;cmd_addr=~address;cmd_bytes=1;
        repeat(3)begin
            @(negedge clk);require(arvalid && araddr==address && arsize==chosen_size && !cmd_ready,"saved address/size stable");
            require(arid==0 && arlen==0 && arburst==1 && expected_bytes<=maximum && address%expected_bytes==0,"aligned bounded transfer");
            require((address%4096)+expected_bytes<=4096,"no 4KiB boundary crossing");
        end
        arready=1;@(negedge clk);arready=0;require(rready && !arvalid,"AR once");
    endtask
    task automatic beat(input logic [63:0] data,input bit last,input logic [3:0] id,input logic [1:0] error_code);
        @(negedge clk);rdata=data;rlast=last;rid=id;rresp=error_code;rvalid=1;require(rready,"reserved response slot");
        @(negedge clk);rvalid=0;rdata=0;rlast=1;rid=0;rresp=0;
    endtask
    task automatic consume(input logic [63:0] data,input bit error_flag);
        integer before_count;before_count=responses;
        repeat(5)begin
            @(negedge clk);require(rsp_valid && rsp_data==data && rsp_error==error_flag && rsp_bytes==expected_bytes,"held complete chunk");
            require(!cmd_ready && !arvalid && !rready,"full slot blocks new command");
        end
        rsp_ready=1;@(negedge clk);rsp_ready=0;
        require(responses==before_count+1 && last_data==data && last_error==error_flag && last_bytes==expected_bytes,"one chunk returned");
        require(idle && !rsp_valid,"released slot");
    endtask
    initial begin
        reset_reader();
        for(integer lane=0;lane<8;lane++)for(integer maximum=1;maximum<=8;maximum++)begin
            address_stalled(ADDR_WIDTH'(64'h1_0000_0ff8+lane),maximum);
            beat(64'h8877665544332211,1,0,0);consume(64'h8877665544332211>>(lane*8),0);
        end
        for(integer code=0;code<3;code++)begin
            integer n;address_stalled(ADDR_WIDTH'(64'h1_0000_1000),8);n=responses;rsp_ready=1;
            beat(64'h0123456789abcdef,1,code==2?7:0,code==1?2:0);
            repeat(3)@(negedge clk);rsp_ready=0;require(responses==n+1 && last_data==64'h0123456789abcdef && last_error==(code!=0),"forwarded once with error");
        end
        address_stalled(ADDR_WIDTH'(64'h1_0000_1004),4);beat(64'h1122334455667788,0,0,0);
        repeat(4)begin @(negedge clk);require(!rsp_valid && !cmd_ready && rready,"drain until actual RLAST");end
        beat(0,0,3,2);require(!rsp_valid,"no partial response");beat(0,1,0,0);consume(64'h11223344,1);
        @(negedge clk);cmd_valid=1;cmd_addr=8;cmd_bytes=8;@(negedge clk);cmd_valid=0;reset_reader();
        address_stalled(3,5);reset_reader();
        address_stalled(8,8);beat(0,0,0,0);reset_reader();
        address_stalled(8,8);beat(0,1,0,0);reset_reader();
        $display("CHUNK_PROTOCOL_PASS address_width=%0d checks=%0d responses=%0d",ADDR_WIDTH,checks,responses);$finish;
    end
    initial begin #1000000;$fatal(1,"CHUNK_PROTOCOL_TIMEOUT");end
endmodule
module tb_axi_chunk_protocol32;tb_axi_chunk_protocol #(.ADDR_WIDTH(32)) test();endmodule
