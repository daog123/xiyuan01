`timescale 1ns/1ps
module tb_axi_read_protocol #(parameter integer ADDR_WIDTH=64);
    logic clk=0;always #5 clk=~clk;
    logic rst=1,cmd_valid=0,cmd_ready,rsp_valid,rsp_ready=0,rsp_error,idle;
    logic [ADDR_WIDTH-1:0] cmd_addr=0,araddr;
    logic [7:0] rsp_data,arlen;
    logic arvalid,arready=0,rvalid=0,rready,rlast=1;
    logic [3:0] arid,rid=0;logic [2:0] arsize;logic [1:0] arburst,rresp=0;
    logic [63:0] rdata=0;
    integer checks=0,responses=0;
    logic [7:0] last_data;logic last_error;
    w4a8_axi_read #(.ADDR_WIDTH(ADDR_WIDTH)) dut(.*);
    task automatic require(input bit ok,input string message);
        checks++;if(!ok) $fatal(1,"READ_PROTOCOL_FAILED %s t=%0t",message,$time);
    endtask
    always @(posedge clk) if(!rst && rsp_valid && rsp_ready) begin
        responses++;last_data=rsp_data;last_error=rsp_error;
    end
    task automatic reset_reader;
        @(negedge clk);rst=1;cmd_valid=0;rvalid=0;arready=0;rsp_ready=0;
        repeat(3) @(negedge clk);
        require(!arvalid && !rready && !rsp_valid && !cmd_ready,"reset gates handshakes");
        rst=0;@(negedge clk);require(idle && cmd_ready,"reset empties slot");
    endtask
    // Accept a command while AR is stalled, then check saved address and stability.
    task automatic address_stalled(input logic [ADDR_WIDTH-1:0] address);
        @(negedge clk);cmd_addr=address;cmd_valid=1;arready=0;
        require(cmd_ready,"admit command");
        @(negedge clk);cmd_valid=0;cmd_addr=~address;
        repeat(3) begin
            @(negedge clk);
            require(arvalid && araddr==address && !cmd_ready,"AR holds accepted address");
            require(arid==0 && arlen==0 && arsize==0 && arburst==1,"narrow AXI attributes");
        end
        arready=1;@(negedge clk);arready=0;
        require(!arvalid && rready,"address sent once");
    endtask
    task automatic beat(input logic [63:0] data,input bit last,
                        input logic [3:0] id,input logic [1:0] error_code);
        @(negedge clk);rdata=data;rlast=last;rid=id;rresp=error_code;rvalid=1;
        require(rready,"reserved response capacity");
        @(negedge clk);rvalid=0;rdata=0;rid=0;rresp=0;rlast=1;
    endtask
    task automatic consume_held(input logic [7:0] data,input bit error_flag);
        integer before_count;before_count=responses;
        repeat(5) begin
            @(negedge clk);
            require(rsp_valid && rsp_data==data && rsp_error==error_flag,"response stable under backpressure");
            require(!cmd_ready && !arvalid && !rready,"full slot blocks another transaction");
        end
        rsp_ready=1;@(negedge clk);rsp_ready=0;
        require(responses==before_count+1 && last_data==data && last_error==error_flag,"one response consumed");
        require(idle && !rsp_valid,"response releases slot");
    endtask
    initial begin
        reset_reader();
        for(integer lane=0;lane<8;lane++) begin
            address_stalled(ADDR_WIDTH'(64'h1_0000_1200+lane));
            beat(64'h8877665544332211,1,0,0);
            consume_held(8'(8'h11+lane*8'h11),0);
        end
        // Ready consumers must receive the forwarding path exactly once.
        for(integer code=0;code<3;code++) begin
            integer before_count;
            address_stalled(ADDR_WIDTH'(64'h1_0000_1003));
            before_count=responses;rsp_ready=1;
            beat(64'h0123456789abcdef,1,code==2?4'd7:4'd0,code==1?2'd2:2'd0);
            repeat(3) @(negedge clk);rsp_ready=0;
            require(responses==before_count+1 && last_data==8'h89 && last_error==(code!=0),"ready response/data/error once");
            require(idle,"ready response releases slot");
        end
        // A malformed response keeps the first byte and drains all trailing beats.
        address_stalled(ADDR_WIDTH'(64'h1_0000_1001));
        beat(64'h1122334455667788,0,0,0);
        repeat(3) begin @(negedge clk);require(!rsp_valid && !cmd_ready && rready,"drain waits for RLAST");end
        beat(64'hffffffffffffffff,0,3,2);
        require(!rsp_valid && !cmd_ready,"middle malformed beat not exposed");
        beat(64'h0000000000000000,1,0,0);
        consume_held(8'h77,1);
        // Reset abandons each pending phase together with the external fabric.
        @(negedge clk);cmd_valid=1;cmd_addr=5;arready=0;
        @(negedge clk);cmd_valid=0;reset_reader();
        address_stalled(3);reset_reader();
        address_stalled(3);beat(0,0,0,0);reset_reader();
        address_stalled(3);beat(0,1,0,0);reset_reader();
        // Back-to-back commands with an always-ready address channel.
        for(integer n=0;n<4;n++) begin
            integer before_count;
            @(negedge clk);cmd_valid=1;cmd_addr=2;arready=1;
            @(negedge clk);cmd_valid=0;
            while(arvalid) @(negedge clk);
            arready=0;before_count=responses;rsp_ready=1;
            beat(64'h0102030405060708,1,0,0);
            repeat(2) @(negedge clk);rsp_ready=0;
            require(responses==before_count+1 && last_data==6 && !last_error,"always-ready AR response");
        end
        $display("READ_PROTOCOL_PASS address_width=%0d checks=%0d responses=%0d",ADDR_WIDTH,checks,responses);
        $finish;
    end
    initial begin #1000000;$fatal(1,"READ_PROTOCOL_TIMEOUT");end
endmodule
module tb_axi_read_protocol32;tb_axi_read_protocol #(.ADDR_WIDTH(32)) test();endmodule
