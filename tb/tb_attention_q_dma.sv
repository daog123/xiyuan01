`timescale 1ns/1ps
module tb_attention_q_dma #(parameter integer GROUP_SIZE=32);
    localparam integer ADDR_WIDTH=64,MAX_DIM=64;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,load_valid=0,load_ready,loaded,failed,idle,send_enable=0,out_valid,out_ready=0,out_last;
    attention_pkg::attention_task_t desc;
    logic signed [7:0] out_data;logic [15:0] out_scale;
    logic arvalid,arready=1,rvalid=0,rready,rlast=1;
    logic [63:0] araddr,rdata=0;logic [3:0] arid,rid=0;
    logic [7:0] arlen;logic [2:0] arsize;logic [1:0] arburst,rresp=0;
    logic [7:0] mem[0:511];
    integer checks=0,received=0,reads=0,ticks=0,dimension,groups,delay_left=0;
    integer pending_address=0,pending_bytes=0,read_payload=0,error_address=-1;bit pending=0,checking=0,held=0;
    logic [24:0] held_payload;
    attention_q_dma #(.GROUP_SIZE(GROUP_SIZE)) dut(.*);
    task automatic require(input bit ok,input string message);
        checks++;if(!ok)$fatal(1,"Q_DMA_PROTOCOL_FAILED %s time=%0t",message,$time);
    endtask
    always @(posedge clk) begin
        ticks++;
        if(rst) begin pending=0;rvalid<=0;received=0;reads=0;read_payload=0;held=0;end
        else begin
            if(rvalid && rready)rvalid<=0;
            if(pending && !rvalid) begin
                if(delay_left>0)delay_left--;
                else begin pending=0;rvalid<=1;rdata<=0;
                    for(integer b=0;b<pending_bytes;b++)rdata[((pending_address%8)+b)*8 +:8]<=mem[pending_address+b];
                    rresp<=pending_address<=error_address && pending_address+pending_bytes>error_address?2:0;end
            end
            if(arvalid && arready) begin
                require(!pending && !rvalid,"one outstanding read");
                require(arid==0 && arlen==0 && arsize<=3 && araddr%(1<<arsize)==0 && arburst==1,"bounded beat attributes");
                require((araddr>=13 && araddr+(1<<arsize)<=13+dimension) || (araddr>=129 && araddr+(1<<arsize)<=129+2*groups),"no padding or allocation overread");
                pending_address=integer'(araddr);pending_bytes=1<<arsize;read_payload+=pending_bytes;pending=1;delay_left=ticks%4;reads++;
            end
            if(held)require({out_data,out_scale,out_last}===held_payload && out_valid,"Q payload holds under backpressure");
            held=out_valid && !out_ready;held_payload={out_data,out_scale,out_last};
            if(checking && out_valid && out_ready) begin
                require(received<dimension,"no excess Q bytes");
                require(out_data===mem[13+received],"Q byte");
                require(out_scale==16'((received/GROUP_SIZE)*977+1),"little-endian repeated group scale");
                require(out_last==(received+1==dimension),"last on final dimension only");received++;
            end
        end
    end
    task automatic reset_loader;
        @(negedge clk);rst=1;load_valid=0;send_enable=0;out_ready=0;checking=0;
        repeat(4)@(negedge clk);rst=0;repeat(2)@(negedge clk);
        require(load_ready && idle && !loaded && !failed,"empty after reset");
    endtask
    task automatic launch(input integer d);
        dimension=d;groups=(d+GROUP_SIZE-1)/GROUP_SIZE;
        for(integer i=0;i<512;i++)mem[i]=8'ha5;
        for(integer i=0;i<d;i++)mem[13+i]=8'(i*37+131);
        for(integer g=0;g<groups;g++)begin mem[129+2*g]=8'(g*977+1);mem[130+2*g]=8'((g*977+1)>>8);end
        desc='0;desc.q_source=1;desc.dimension=d;desc.q_addr=13;desc.q_bytes=d;desc.qs_addr=129;desc.qs_bytes=2*groups;
        @(negedge clk);load_valid=1;@(negedge clk);load_valid=0;
    endtask
    initial begin
        integer wd;
        desc='0;
        for(integer test=0;test<3;test++) begin
            reset_loader();error_address=-1;launch(test==0?1:test==1?9:64);
            wd=0;while(!loaded)begin @(negedge clk);wd++;require(wd<5000 && !failed,"load watchdog");end
            require(read_payload==dimension+2*groups && idle,"exact Q and scale byte count");
            repeat(10)begin @(negedge clk);require(loaded && !out_valid,"prefetch independent of stream start");end
            send_enable=1;checking=1;repeat(9)@(negedge clk);
            while(received<dimension)begin @(negedge clk);out_ready=ticks%5>1;end
            @(negedge clk);out_ready=0;repeat(5)@(negedge clk);require(!out_valid && loaded && idle,"sent exactly one vector");
        end
        for(integer e=0;e<2;e++) begin
            reset_loader();error_address=e==0?129:13;launch(64);
            wd=0;while(!failed)begin @(negedge clk);wd++;require(wd<5000,"error watchdog");end
            require(!loaded && !out_valid && idle,"failed read never exposes Q");
        end
        reset_loader();error_address=-1;launch(64);wait(arvalid && arready);reset_loader();
        $display("Q_DMA_PROTOCOL_PASS group=%0d checks=%0d",GROUP_SIZE,checks);$finish;
    end
    initial begin #1000000;$fatal(1,"Q_DMA_PROTOCOL_TIMEOUT");end
endmodule
module tb_attention_q_dma3;tb_attention_q_dma #(.GROUP_SIZE(3)) test();endmodule
module tb_attention_q_dma1;tb_attention_q_dma #(.GROUP_SIZE(1)) test();endmodule
