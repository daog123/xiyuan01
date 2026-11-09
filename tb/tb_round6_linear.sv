`timescale 1ns/1ps
module tb_round6_linear #(parameter integer READ_DELAY=8);
    import accelerator_pkg::*;import task_desc_pkg::*;
    localparam integer ADDR_WIDTH=64,SIZE=262144;
    localparam logic [63:0] BASE=64'h1_0000_0000;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,job_valid=0,job_ready,completion_valid,completion_ready=0,result_available;
    logic [7:0] job_opcode=OP_LINEAR,completion_status;
    bounded_task_t linear_task;ffn_plan_t ffn_plan='0;
    logic [31:0] completion_task_id,elapsed_cycles,activation_written,scale_written;logic [3:0] stage;
    logic load_pause=0,post_pause=0,array_pause=0;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [63:0] araddr,awaddr,rdata,wdata;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic setup=0,hold_b=0,hold_r=0,inject_r=0,inject_b=0;
    integer reads,writes,b_count,checks=0,tasks=0,bytes_checked=0;
    integer waiting_r=0,waiting_ar=0,returned_beats=0,write_acks=0,active_ar=0;
    logic [7:0] expected[0:SIZE-1];
    accelerator_test_shell dut(.*);
    system_axi_memory #(.SIZE(SIZE),.READ_DELAY(READ_DELAY),.WRITE_DELAY(4)) memory(.*);
    task automatic require(input bit c,input string msg);
        checks++;if(!c)$fatal(1,"ROUND6_LINEAR_CHECK_FAILED %s t=%0t",msg,$time);
    endtask
    always @(posedge clk) if(rst || setup)begin waiting_r=0;waiting_ar=0;returned_beats=0;write_acks=0;active_ar=0;end
    else begin
        if(arvalid && arready)begin require(active_ar==0,"one outstanding AR");active_ar=1;end
        if(rvalid && rready)begin returned_beats++;if(rlast)active_ar=0;end
        if(rready && !rvalid)waiting_r++;
        if(arvalid && !arready)waiting_ar++;
        if(bvalid && bready)write_acks++;
    end
    initial begin
        integer f,rc,wd;
        repeat(4)@(negedge clk);rst=0;
        for(integer cid=0;cid<8;cid++)begin
            @(negedge clk);
            f=$fopen($sformatf("large%0d.txt",cid),"r");require(f!=0,"vector opens");linear_task='0;
            rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
                linear_task.desc.task_id,linear_task.desc.m,linear_task.desc.n,linear_task.desc.k,
                linear_task.desc.a_addr,linear_task.desc.w_addr,linear_task.desc.sx_addr,linear_task.desc.sw_addr,linear_task.desc.y_addr,
                linear_task.desc.a_stride,linear_task.desc.w_stride,linear_task.desc.sx_stride,linear_task.desc.sw_stride,linear_task.desc.y_stride,
                linear_task.a_bytes,linear_task.w_bytes,linear_task.sx_bytes,linear_task.sw_bytes,linear_task.y_bytes);
            require(rc==19,"task fields");$fclose(f);
            linear_task.desc.a_addr+=BASE;linear_task.desc.w_addr+=BASE;linear_task.desc.sx_addr+=BASE;linear_task.desc.sw_addr+=BASE;linear_task.desc.y_addr+=BASE;
            linear_task.desc.activation_format=1;linear_task.desc.weight_format=1;linear_task.desc.scale_format=1;linear_task.desc.output_format=1;linear_task.desc.group_size=32;
            $readmemh($sformatf("large%0d.input.hex",cid),memory.mem);$readmemh($sformatf("large%0d.expected.hex",cid),expected);
            $readmemh($sformatf("large%0d.read.hex",cid),memory.read_allowed);$readmemh($sformatf("large%0d.write.hex",cid),memory.write_allowed);
            if($test$plusargs("corrupt_expected"))expected[245760]^=1;
            setup=1;@(negedge clk);setup=0;
            wd=0;while(!job_ready)begin @(negedge clk);wd++;require(wd<100,"admission");end
            job_valid=1;@(negedge clk);job_valid=0;
            wd=0;while(!completion_valid)begin @(negedge clk);wd++;require(wd<3000000,"completion watchdog");end
            require(completion_status==0 && completion_task_id==linear_task.desc.task_id && result_available,"completion identity/status");
            require(b_count==linear_task.desc.m*linear_task.desc.n && active_ar==0 && returned_beats==memory.read_beats && write_acks==writes,"read drain and final B fence");
            for(integer i=0;i<SIZE;i++)begin require(memory.mem[i]===expected[i],$sformatf("full image byte %0d",i));bytes_checked++;end
            $display("LARGE_RECORD case=%0d M=%0d N=%0d K=%0d cycles=%0d reads=%0d read_beats=%0d burst_reads=%0d read_payload=%0d writes=%0d acks=%0d wait_r=%0d wait_ar=%0d bytes=%0d",
                cid,linear_task.desc.m,linear_task.desc.n,linear_task.desc.k,elapsed_cycles,reads,memory.read_beats,memory.burst_reads,memory.read_payload,writes,b_count,waiting_r,waiting_ar,SIZE);
            repeat(5)begin @(negedge clk);require(completion_valid && !job_ready,"completion held");end
            completion_ready=1;@(negedge clk);completion_ready=0;tasks++;
        end
        $display("ROUND6_LARGE_PASS tasks=%0d bytes=%0d checks=%0d",tasks,bytes_checked,checks);$finish;
    end
    initial begin #1000000000;$fatal(1,"ROUND6_LINEAR_TIMEOUT");end
endmodule
