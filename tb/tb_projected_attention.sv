`timescale 1ns/1ps
module tb_projected_attention #(parameter integer GROUP_SIZE=32,ADDR_WIDTH=64,
    parameter logic [63:0] BASE=64'h4_0000_0000);
    import accelerator_pkg::*;import task_desc_pkg::*;import kv_cache_pkg::*;import attention_pkg::*;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,job_valid=0,job_ready,completion_valid,completion_ready=0,result_available,configured;
    logic [7:0] job_opcode=0,completion_status;
    bounded_task_t linear_task;ffn_plan_t ffn_plan;kv_config_t kv_config;kv_command_t kv_command;attention_task_t attention_task;
    logic append_valid=0,append_ready,append_last=0,read_valid,read_ready=1,read_last;
    logic [7:0] append_data=0,read_data;
    logic q_valid=0,q_ready,q_last=0;logic signed [7:0] q_data=0;logic [15:0] q_scale=0;
    logic load_pause=0,post_pause=0,array_pause=0;logic [3:0] stage;
    logic [31:0] elapsed_cycles,activation_written,scale_written,completion_task_id;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [ADDR_WIDTH-1:0] araddr,awaddr;logic [63:0] rdata,wdata;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic setup=0,hold_b=0,hold_r=0,inject_r,inject_b;
    integer reads,writes,b_count,checks=0,tasks=0,bytes_checked=0,expected_id,dimension,append_count,gain,ntokens;
    integer expected_q[0:63],expected_s[0:63],append_bytes[0:4095],received=0,fault=0,projection_fence=0;
    bit check_q=0,graph_running=0;
    logic [7:0] expected[0:65535];
    assign inject_r=fault==1 && stage==1 || fault==2 && araddr>=BASE+26000 && araddr<BASE+26000+4*dimension;
    assign inject_b=fault==3 && stage==5;
    llm_graph_top #(.GROUP_SIZE(GROUP_SIZE),.MAX_DIM(64),.MAX_TOKENS(4)) dut(.qkv_plan('0),.*);
    system_axi_memory #(.ADDR_WIDTH(ADDR_WIDTH),.BASE(BASE)) memory(.*);
    task automatic require(input bit c,input string m);
        checks++;if(!c)$fatal(1,"PROJECTION_CHECK_FAILED %s t=%0t status=%0d stage=%0d",m,$time,completion_status,stage);
    endtask
    always @(posedge clk) if(!rst)begin
        if(check_q && dut.engine.attention.dma_q_valid && dut.engine.attention.core_q_ready && stage==5)begin
            require(received<dimension,"Q output count");
            require(dut.engine.attention.dma_q_data===8'(expected_q[received]),"independent quantized Q");
            require(dut.engine.attention.dma_q_scale==expected_s[received],"independent dynamic scale");
            require(dut.engine.attention.dma_q_last==(received+1==dimension),"quantized Q last");received++;
        end
        if(graph_running && arvalid && arready && araddr>=BASE+26000 && araddr<BASE+26000+4*dimension)
            require(b_count>=projection_fence+dimension,"projection B fence before Q read");
        if(graph_running)require(!q_ready,"graph never requests host Q stream");
    end
    task automatic reset_all;
        @(negedge clk);rst=1;job_valid=0;completion_ready=0;hold_b=0;hold_r=0;fault=0;graph_running=0;check_q=0;
        repeat(4)@(negedge clk);rst=0;repeat(2)@(negedge clk);require(job_ready && !completion_valid && !configured,"reset clears graph and KV metadata");
    endtask
    task automatic submit(input integer op,input integer id);
        @(negedge clk);require(job_ready,"single admission");job_opcode=8'(op);expected_id=id;job_valid=1;
        @(negedge clk);job_valid=0;
    endtask
    task automatic finish(input integer status);
        integer wd;wd=0;
        while(!completion_valid)begin @(negedge clk);wd++;require(wd<500000,"graph watchdog");end
        require(completion_task_id==expected_id && completion_status==status,"root completion ID/status");
        require(result_available==(status==0),"result visibility");
        repeat(7)begin @(negedge clk);require(completion_valid && !job_ready && completion_task_id==expected_id && completion_status==status,"held root completion");end
        completion_ready=1;@(negedge clk);completion_ready=0;graph_running=0;check_q=0;tasks++;
    endtask
    task automatic compare_image;
        for(integer i=0;i<65536;i++)begin require(memory.mem[i]===expected[i],$sformatf("external image %0d",i));bytes_checked++;end
    endtask
    task automatic load_case(input integer cid);
        integer f,rc,k;string stem;
        stem=$sformatf("g%0d_c%0d",GROUP_SIZE,cid);f=$fopen({stem,".txt"},"r");require(f!=0,"open graph reference");
        rc=$fscanf(f,"%d %d %d %d %d",dimension,k,ntokens,gain,append_count);require(rc==5,"graph header");
        linear_task='0;
        rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
            linear_task.desc.task_id,linear_task.desc.m,linear_task.desc.n,linear_task.desc.k,
            linear_task.desc.a_addr,linear_task.desc.w_addr,linear_task.desc.sx_addr,linear_task.desc.sw_addr,linear_task.desc.y_addr,
            linear_task.desc.a_stride,linear_task.desc.w_stride,linear_task.desc.sx_stride,linear_task.desc.sw_stride,linear_task.desc.y_stride,
            linear_task.a_bytes,linear_task.w_bytes,linear_task.sx_bytes,linear_task.sw_bytes,linear_task.y_bytes);require(rc==19,"projection descriptor");
        linear_task.desc.a_addr+=BASE;linear_task.desc.w_addr+=BASE;linear_task.desc.sx_addr+=BASE;linear_task.desc.sw_addr+=BASE;linear_task.desc.y_addr+=BASE;
        linear_task.desc.group_size=GROUP_SIZE;linear_task.desc.activation_format=1;linear_task.desc.weight_format=1;linear_task.desc.scale_format=1;linear_task.desc.output_format=1;
        kv_config='0;kv_config.config_id=700+cid;kv_config.layers=1;kv_config.heads=1;kv_config.dimension=16'(dimension);kv_config.capacity=4;kv_config.group_size=GROUP_SIZE;kv_config.format_id=1;
        for(integer p=0;p<4;p++)begin rc=$fscanf(f,"%d",kv_config.base[p]);require(rc==1,"KV base");kv_config.base[p]+=BASE;end
        for(integer p=0;p<4;p++)begin rc=$fscanf(f,"%d",kv_config.token_stride[p]);require(rc==1,"KV stride");end
        for(integer p=0;p<4;p++)begin rc=$fscanf(f,"%d",kv_config.bytes[p]);require(rc==1,"KV bytes");kv_config.head_stride[p]=kv_config.bytes[p];kv_config.layer_stride[p]=kv_config.bytes[p];end
        for(integer i=0;i<dimension;i++)begin rc=$fscanf(f,"%d",expected_q[i]);require(rc==1,"Q ref");end
        for(integer i=0;i<dimension;i++)begin rc=$fscanf(f,"%d",expected_s[i]);require(rc==1,"scale ref");end
        for(integer i=0;i<append_count;i++)begin rc=$fscanf(f,"%d",append_bytes[i]);require(rc==1,"append ref");end
        $fclose(f);$readmemh({stem,".input.hex"},memory.mem);$readmemh({stem,".expected.hex"},expected);
        $readmemh({stem,".read.hex"},memory.read_allowed);$readmemh({stem,".write.hex"},memory.write_allowed);
        if($test$plusargs("corrupt_expected"))expected[50000]^=1;
        attention_task='0;attention_task.task_id=1200+cid;attention_task.tokens=16'(ntokens);attention_task.dimension=16'(dimension);attention_task.score_scale=16'(gain);
        attention_task.y_addr=BASE+30000;attention_task.y_bytes=4*dimension;attention_task.q_source=2;attention_task.q_addr=linear_task.desc.y_addr;attention_task.q_bytes=linear_task.y_bytes;
    endtask
    task automatic configure_and_append;
        submit(OP_KV_CONFIG,kv_config.config_id);finish(0);require(configured,"KV configured");
        kv_command='0;kv_command.task_id=800;kv_command.operation=KV_APPEND;kv_command.count=16'(ntokens);submit(OP_KV_COMMAND,800);
        for(integer i=0;i<append_count;i++)begin
            @(negedge clk);append_valid=1;append_data=8'(append_bytes[i]);append_last=i+1==append_count;
            while(!append_ready)@(negedge clk);
            @(negedge clk);append_valid=0;
        end
        finish(0);projection_fence=b_count;
    endtask
    task automatic start_graph;
        received=0;check_q=1;graph_running=1;projection_fence=b_count;
        submit(OP_Q_ATTENTION,attention_task.task_id);
    endtask
    initial begin
        ffn_plan='0;kv_config='0;kv_command='0;attention_task='0;linear_task='0;
        for(integer c=0;c<3;c++)begin
            reset_all();load_case(c);configure_and_append();
            received=0;check_q=1;submit(OP_ATTENTION,attention_task.task_id);finish(0);require(received==dimension,"direct Q16 vector count");compare_image();
            for(integer i=0;i<4*dimension;i++)memory.mem[26000+i]=8'ha7;
            hold_b=1;start_graph();wait(wvalid && wready);repeat(40)@(negedge clk);
            require(!completion_valid && stage==1 && received==0,"pending projection B blocks quantizer");hold_b=0;
            finish(0);require(received==dimension,"one graph Q vector");compare_image();
            if(c==0)begin
                integer before_reads,before_writes;
                before_reads=reads;before_writes=writes;attention_task.q_source=1;
                submit(OP_Q_ATTENTION,attention_task.task_id);finish(STATUS_BAD_FLAGS);
                require(reads==before_reads && writes==before_writes,"bad graph source rejects before AXI");attention_task.q_source=2;
                attention_task.y_addr=linear_task.desc.a_addr;
                submit(OP_Q_ATTENTION,attention_task.task_id);finish(STATUS_BAD_REGION);
                require(reads==before_reads && writes==before_writes,"graph alias rejects before AXI");attention_task.y_addr=BASE+30000;
                linear_task.desc.y_addr=BASE+42000;attention_task.q_addr=linear_task.desc.y_addr;
                submit(OP_Q_ATTENTION,attention_task.task_id);finish(STATUS_BAD_REGION);
                require(reads==before_reads && writes==before_writes,"projection workspace cannot alias KV");
                linear_task.desc.y_addr=BASE+26000;attention_task.q_addr=linear_task.desc.y_addr;
                for(integer e=1;e<=3;e++)begin
                    fault=e;start_graph();finish(e==3?STATUS_WRITE_ERROR:STATUS_READ_ERROR);fault=0;
                    start_graph();finish(0);require(received==dimension,"recover complete Q vector");compare_image();
                end
                reset_all();load_case(0);configure_and_append();start_graph();
                wait(stage==5);hold_r=1;wait(arvalid && arready);repeat(5)@(negedge clk);
                require(!completion_valid && received==0,"pending Q read cannot complete graph");
                reset_all();load_case(0);configure_and_append();start_graph();finish(0);
                require(received==dimension,"graph recovers after reset with fabric");compare_image();
            end
        end
        $display("PROJECTION_TESTS_PASS group=%0d address_width=%0d tasks=%0d bytes=%0d checks=%0d",GROUP_SIZE,ADDR_WIDTH,tasks,bytes_checked,checks);$finish;
    end
    initial begin #500000000;$fatal(1,"PROJECTION_GLOBAL_TIMEOUT");end
    initial if($test$plusargs("timeout_probe"))begin #20000;$fatal(1,"PROJECTION_FORCED_TIMEOUT");end
endmodule
module tb_projected_attention3;tb_projected_attention #(.GROUP_SIZE(3)) test();endmodule
module tb_projected_attention32;tb_projected_attention #(.ADDR_WIDTH(32),.BASE(0)) test();endmodule
module tb_projected_attention1;tb_projected_attention #(.GROUP_SIZE(1)) test();endmodule
