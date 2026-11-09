`timescale 1ns/1ps
module tb_accelerator #(parameter integer GROUP_SIZE=32,ADDR_WIDTH=64,PERF_ONLY=0,READ_DELAY=-1,WRITE_DELAY=-1,
    parameter logic [63:0] BASE=64'h1_0000_0000);
    import accelerator_pkg::*;import task_desc_pkg::*;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,job_valid=0,job_ready,completion_valid,completion_ready=0,result_available;
    logic [7:0] job_opcode=OP_FFN,completion_status;
    bounded_task_t linear_task;ffn_plan_t ffn_plan;
    logic [31:0] completion_task_id,elapsed_cycles,activation_written,scale_written;
    logic [3:0] stage;
    logic load_pause=0,post_pause=0,array_pause=0;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [ADDR_WIDTH-1:0] araddr,awaddr;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic [63:0] rdata,wdata;
    logic setup=0,hold_b=0,hold_r=0,inject_r,inject_b;
    integer fault_stage=0;bit fault_read=0,fault_write=0,checking=0;
    assign inject_r=fault_read && stage==fault_stage;
    assign inject_b=fault_write && stage==fault_stage;
    integer reads,writes,b_count,checks=0,tasks=0,bytes_checked=0,previous_stage=0,expected_id;
    logic [7:0] expected[0:65535];
    accelerator_test_shell #(.GROUP_SIZE(GROUP_SIZE),.ADDR_WIDTH(ADDR_WIDTH)) dut(.*);
    system_axi_memory #(.ADDR_WIDTH(ADDR_WIDTH),.BASE(BASE),.READ_DELAY(READ_DELAY),.WRITE_DELAY(WRITE_DELAY)) memory(.*);
    task automatic require(input bit condition,input string message);
        checks++;if(!condition) $fatal(1,"ACCELERATOR_CHECK_FAILED %s stage=%0d time=%0t",message,stage,$time);
    endtask
    always @(posedge clk) if(!rst && checking && stage!=previous_stage && stage>0) begin
        if(stage==2) require(b_count==ffn_plan.gate_task.desc.m*ffn_plan.gate_task.desc.n,"gate write fence before up");
        if(stage==3) require(b_count==2*ffn_plan.gate_task.desc.m*ffn_plan.gate_task.desc.n,"both projection fences before vector DMA");
        if(stage==4) begin
            require(activation_written==ffn_plan.down_task.desc.m*ffn_plan.down_task.desc.k,"all qx bytes acknowledged");
            require(scale_written==2*ffn_plan.down_task.desc.m*((ffn_plan.down_task.desc.k+GROUP_SIZE-1)/GROUP_SIZE),"all sx bytes acknowledged");
            require(b_count==2*ffn_plan.gate_task.desc.m*ffn_plan.gate_task.desc.n+activation_written+scale_written,"vector storage fence before down");
        end
        previous_stage=stage;
    end
    task automatic reset_all;
        @(negedge clk);rst=1;job_valid=0;completion_ready=0;hold_b=0;hold_r=0;
        fault_read=0;fault_write=0;fault_stage=0;checking=0;
        repeat(4) @(negedge clk);rst=0;repeat(2) @(negedge clk);
        require(!completion_valid && !result_available,"reset invalidates completion");
    endtask
    task automatic read_task(input integer f,output bounded_task_t t);
        integer rc;
        t='0;
        rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
            t.desc.task_id,t.desc.m,t.desc.n,t.desc.k,t.desc.a_addr,t.desc.w_addr,t.desc.sx_addr,t.desc.sw_addr,t.desc.y_addr,
            t.desc.a_stride,t.desc.w_stride,t.desc.sx_stride,t.desc.sw_stride,t.desc.y_stride,
            t.a_bytes,t.w_bytes,t.sx_bytes,t.sw_bytes,t.y_bytes);
        require(rc==19,"read bounded task");
        t.desc.a_addr+=BASE;t.desc.w_addr+=BASE;t.desc.sx_addr+=BASE;t.desc.sw_addr+=BASE;t.desc.y_addr+=BASE;
        t.desc.activation_format=1;t.desc.weight_format=1;t.desc.scale_format=1;t.desc.output_format=1;t.desc.group_size=GROUP_SIZE;
    endtask
    task automatic load_case(input integer id);
        integer f,rc,grp;string stem;
        stem=$sformatf("g%0d_case%0d",GROUP_SIZE,id);
        f=$fopen({stem,".txt"},"r");require(f!=0,"open vectors");
        rc=$fscanf(f,"%d %d",ffn_plan.task_id,grp);require(rc==2 && grp==GROUP_SIZE,"case header");
        read_task(f,ffn_plan.gate_task);read_task(f,ffn_plan.up_task);read_task(f,ffn_plan.down_task);$fclose(f);
        linear_task=ffn_plan.gate_task;job_opcode=OP_FFN;expected_id=ffn_plan.task_id;
        $readmemh({stem,".input.hex"},memory.mem);$readmemh({stem,".expected.hex"},expected);
        $readmemh({stem,".read.hex"},memory.read_allowed);$readmemh({stem,".write.hex"},memory.write_allowed);
        if($test$plusargs("corrupt_expected")) expected[50000]^=1;
        checking=1;previous_stage=0;
        @(negedge clk);setup=1;@(negedge clk);setup=0;
    endtask
    task automatic submit;
        integer wd;wd=0;
        while(!job_ready) begin @(negedge clk);wd++;require(wd<100,"admission watchdog");end
        job_valid=1;@(negedge clk);job_valid=0;
    endtask
    task automatic finish_job(input integer status);
        integer wd;wd=0;
        while(!completion_valid) begin @(negedge clk);wd++;require(wd<1000000,"job watchdog");end
        require(completion_task_id==expected_id && completion_status==status,"completion ID/status");
        require(result_available==(status==0),"failed tasks do not expose results");
        repeat(8) begin @(negedge clk);require(completion_valid && completion_task_id==expected_id && completion_status==status && !job_ready,"held completion");end
        completion_ready=1;@(negedge clk);completion_ready=0;checking=0;tasks++;
    endtask
    task automatic compare_image;
        for(integer i=0;i<65536;i++) begin
            require(memory.mem[i]===expected[i],$sformatf("full external image byte=%0d actual=%h expected=%h",i,memory.mem[i],expected[i]));
            bytes_checked++;
        end
    endtask
    task automatic fault_case(input integer phase,input bit read_fault);
        load_case(0);fault_stage=phase;fault_read=read_fault;fault_write=!read_fault;
        submit();finish_job(read_fault?STATUS_READ_ERROR:STATUS_WRITE_ERROR);
        require(previous_stage==phase,"failed stage prevents later launch");fault_read=0;fault_write=0;
    endtask
    initial begin
        reset_all();
        if(PERF_ONLY) begin
            for(integer opcode=0;opcode<2;opcode++) begin
                for(integer i=0;i<3;i++) begin
                    load_case(i);
                    if(opcode==0) begin
                        checking=0;job_opcode=OP_LINEAR;expected_id=linear_task.desc.task_id;
                        $readmemh($sformatf("g%0d_case%0d.linear.hex",GROUP_SIZE,i),expected);
                    end
                    submit();finish_job(0);compare_image();
                    $display("PERF_RECORD opcode=%0d case=%0d group=%0d read_delay=%0d write_delay=%0d cycles=%0d reads=%0d writes=%0d acks=%0d bytes=%0d read_payload=%0d read_beats=%0d burst_reads=%0d",
                        opcode,i,GROUP_SIZE,READ_DELAY,WRITE_DELAY,elapsed_cycles,reads,writes,b_count,65536,memory.read_payload,memory.read_beats,memory.burst_reads);
                end
            end
            $display("PERFORMANCE_TESTS_PASS group=%0d read_delay=%0d tasks=%0d bytes=%0d",GROUP_SIZE,READ_DELAY,tasks,bytes_checked);
            $finish;
        end
        for(integer i=0;i<3;i++) begin load_case(i);submit();finish_job(0);compare_image();end
        load_case(0);checking=0;job_opcode=OP_LINEAR;expected_id=linear_task.desc.task_id;
        $readmemh($sformatf("g%0d_case0.linear.hex",GROUP_SIZE),expected);
        submit();finish_job(0);compare_image();
        load_case(0);submit();wait(stage==3);hold_b=1;wait(wvalid && wready);repeat(70) @(negedge clk);
        require(stage==3 && !completion_valid && !job_ready,"pending vector B blocks down and task reuse");
        hold_b=0;finish_job(0);compare_image();
        fault_case(1,1);fault_case(2,0);fault_case(3,1);fault_case(3,0);fault_case(4,0);
        load_case(1);submit();finish_job(0);compare_image();
        for(integer i=0;i<6;i++) begin
            load_case(0);checking=0;
            case(i)
                0:ffn_plan.down_task.desc.k--;
                1:ffn_plan.up_task.desc.y_addr=ffn_plan.gate_task.desc.y_addr;
                2:ffn_plan.gate_task.desc.n=65;
                3:ffn_plan.up_task.desc.task_id=ffn_plan.gate_task.desc.task_id;
                4:ffn_plan.down_task.a_bytes=1;
                5:ffn_plan.down_task.desc.y_addr=64'hffff_ffff_ffff_fffc;
            endcase
            submit();
            begin integer wd;wd=0;while(!completion_valid) begin @(negedge clk);wd++;require(wd<100,"invalid plan watchdog");end end
            require(completion_status!=0 && reads==0 && writes==0,"whole plan rejected before any side effect");
            finish_job(completion_status);
        end
        load_case(0);submit();wait(stage==3);reset_all();load_case(0);submit();finish_job(0);compare_image();
        $display("ACCELERATOR_TESTS_PASS group=%0d address_width=%0d tasks=%0d bytes=%0d checks=%0d",GROUP_SIZE,ADDR_WIDTH,tasks,bytes_checked,checks);
        $finish;
    end
    initial begin #500000000;$fatal(1,"ACCELERATOR_GLOBAL_TIMEOUT");end
    initial if($test$plusargs("timeout_probe")) begin #20000;$fatal(1,"ACCELERATOR_FORCED_TIMEOUT");end
endmodule
module tb_accelerator12;tb_accelerator #(.GROUP_SIZE(12)) test();endmodule
module tb_accelerator32;tb_accelerator #(.ADDR_WIDTH(32),.BASE(0)) test();endmodule

// Controlled memory-service profiles; production profile remains 4x4 / group32.
module tb_perf_r0;tb_accelerator #(.PERF_ONLY(1),.READ_DELAY(0),.WRITE_DELAY(4)) test();endmodule
module tb_perf_r8;tb_accelerator #(.PERF_ONLY(1),.READ_DELAY(8),.WRITE_DELAY(4)) test();endmodule
module tb_perf_r24;tb_accelerator #(.PERF_ONLY(1),.READ_DELAY(24),.WRITE_DELAY(4)) test();endmodule
module tb_perf_g12;tb_accelerator #(.PERF_ONLY(1),.GROUP_SIZE(12),.READ_DELAY(8),.WRITE_DELAY(4)) test();endmodule
