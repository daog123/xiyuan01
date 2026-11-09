`timescale 1ns/1ps
module tb_large_memory;
    import accelerator_pkg::*;import task_desc_pkg::*;
    localparam integer SIZE=262144;localparam logic [63:0] BASE=64'h5_0000_0000;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,job_valid=0,job_ready,completion_valid,completion_ready=0,result_available;
    logic [7:0] job_opcode=OP_LINEAR,completion_status;bounded_task_t linear_task;ffn_plan_t ffn_plan;
    logic [31:0] completion_task_id,elapsed_cycles,activation_written,scale_written;logic [3:0] stage;
    logic load_pause=0,post_pause=0,array_pause=0;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [63:0] araddr,awaddr,rdata,wdata;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic setup=0,hold_b=0,hold_r=0,inject_r=0,inject_b=0;integer reads,writes,b_count,checks=0;
    logic [7:0] expected[0:SIZE-1];
    accelerator_test_shell dut(.*);
    system_axi_memory #(.SIZE(SIZE),.BASE(BASE),.READ_DELAY(8),.WRITE_DELAY(4)) memory(.*);
    task automatic require(input bit c,input string m);checks++;if(!c)$fatal(1,"LARGE_CHECK_FAILED %s t=%0t",m,$time);endtask
    initial begin
        integer f,rc,wd;string stem;ffn_plan='0;linear_task='0;
        repeat(4)@(negedge clk);rst=0;repeat(2)@(negedge clk);
        for(integer cid=0;cid<4;cid++)begin
            stem=$sformatf("case%0d",cid);f=$fopen({stem,".txt"},"r");require(f!=0,"open large vectors");linear_task='0;
            rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
                linear_task.desc.task_id,linear_task.desc.m,linear_task.desc.n,linear_task.desc.k,
                linear_task.desc.a_addr,linear_task.desc.w_addr,linear_task.desc.sx_addr,linear_task.desc.sw_addr,linear_task.desc.y_addr,
                linear_task.desc.a_stride,linear_task.desc.w_stride,linear_task.desc.sx_stride,linear_task.desc.sw_stride,linear_task.desc.y_stride,
                linear_task.a_bytes,linear_task.w_bytes,linear_task.sx_bytes,linear_task.sw_bytes,linear_task.y_bytes);
            require(rc==19,"large task descriptor");$fclose(f);
            linear_task.desc.a_addr+=BASE;linear_task.desc.w_addr+=BASE;linear_task.desc.sx_addr+=BASE;linear_task.desc.sw_addr+=BASE;linear_task.desc.y_addr+=BASE;
            linear_task.desc.group_size=32;linear_task.desc.activation_format=1;linear_task.desc.weight_format=1;linear_task.desc.scale_format=1;linear_task.desc.output_format=1;
            $readmemh({stem,".input.hex"},memory.mem);$readmemh({stem,".expected.hex"},expected);
            $readmemh({stem,".read.hex"},memory.read_allowed);$readmemh({stem,".write.hex"},memory.write_allowed);
            if($test$plusargs("corrupt_expected"))expected[240000]^=1;
            @(negedge clk);setup=1;@(negedge clk);setup=0;require(job_ready,"large admission");job_valid=1;
            @(negedge clk);job_valid=0;wd=0;
            while(!completion_valid)begin @(negedge clk);wd++;require(wd<10000000,"large task watchdog");end
            require(completion_status==0 && completion_task_id==linear_task.desc.task_id && result_available,"large completion");
            require(writes==linear_task.desc.m*linear_task.desc.n && b_count==writes,"large write fence");
            repeat(3)@(negedge clk);
            for(integer i=0;i<SIZE;i++)require(memory.mem[i]===expected[i],$sformatf("full large image %0d",i));
            $display("LARGE_RECORD case=%0d M=%0d N=%0d K=%0d cycles=%0d reads=%0d payload=%0d writes=%0d acks=%0d",
                cid,linear_task.desc.m,linear_task.desc.n,linear_task.desc.k,elapsed_cycles,reads,memory.read_payload,writes,b_count);
            completion_ready=1;@(negedge clk);completion_ready=0;
        end
        $display("LARGE_MEMORY_PASS jobs=4 bytes=1048576 checks=%0d",checks);$finish;
    end
    initial begin #1000000000;$fatal(1,"LARGE_GLOBAL_TIMEOUT");end
endmodule
