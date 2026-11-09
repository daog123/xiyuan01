`timescale 1ns/1ps
module tb_qkv_attention #(parameter integer GROUP_SIZE=32,ADDR_WIDTH=64,
    parameter logic [63:0] BASE=64'h6_0000_0000);
    import accelerator_pkg::*;import llm_graph_pkg::*;import task_desc_pkg::*;import kv_cache_pkg::*;import attention_pkg::*;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,job_valid=0,job_ready,completion_valid,completion_ready=0,result_available,configured;
    logic [7:0] job_opcode=0,completion_status;bounded_task_t linear_task;ffn_plan_t ffn_plan;
    kv_config_t kv_config;kv_command_t kv_command;attention_task_t attention_task;qkv_plan_t qkv_plan,active_plan,good_plan;
    logic append_valid=0,append_ready,append_last=0,read_valid,read_ready=1,read_last;logic [7:0] append_data=0,read_data;
    logic q_valid=0,q_ready,q_last=0;logic signed [7:0] q_data=0;logic [15:0] q_scale=0;
    logic load_pause=0,post_pause=0,array_pause=0;logic [3:0] stage;
    logic [31:0] elapsed_cycles,activation_written,scale_written,completion_task_id;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [ADDR_WIDTH-1:0] araddr,awaddr;logic [63:0] rdata,wdata;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic setup=0,hold_b=0,hold_r=0,inject_r,inject_b;
    integer reads,writes,b_count,checks=0,tasks=0,bytes_checked=0,expected_id,dimension,groups,fault=0,start_b;
    integer expected_q[0:2][0:63],expected_s[0:2][0:63],received[0:2];
    bit checking=0,graph_running=0;
    logic [7:0] expected[0:65535],input_image[0:65535];
    assign inject_r=fault!=0 && fault==stage && fault!=12;
    assign inject_b=fault==12 && stage==12;
    llm_graph_top #(.GROUP_SIZE(GROUP_SIZE),.MAX_DIM(64),.MAX_TOKENS(4)) dut(.*);
    system_axi_memory #(.ADDR_WIDTH(ADDR_WIDTH),.BASE(BASE)) memory(.*);
    task automatic require(input bit c,input string m);
        checks++;if(!c)$fatal(1,"QKV_CHECK_FAILED %s stage=%0d status=%0d t=%0t",m,stage,completion_status,$time);
    endtask
    task automatic check_value(input integer branch,input logic signed [7:0] data,input logic [15:0] scale,input bit last);
        require(received[branch]<dimension,"quantized vector count");
        require(data===8'(expected_q[branch][received[branch]]),"independent Q/K/V quantized value");
        require(scale==expected_s[branch][received[branch]],"independent Q/K/V scale");
        require(last==(received[branch]+1==dimension),"vector last");received[branch]++;
    endtask
    always @(posedge clk)if(!rst)begin
        if(checking && dut.quant_valid && dut.quant_send)check_value(stage==9?1:2,dut.quant_data,dut.quant_scale,dut.quant_last);
        if(checking && dut.engine.attention.dma_q_valid && dut.engine.attention.core_q_ready &&
            (stage==13 || stage==5))check_value(0,dut.engine.attention.dma_q_data,dut.engine.attention.dma_q_scale,dut.engine.attention.dma_q_last);
        if(graph_running)begin
            require(!q_ready && !append_ready,"graph consumes no host Q or KV stream");
            if(stage==13)require(b_count>=start_b+4*dimension+4*groups,"KV append B fence before Q launch");
            if(arvalid && arready)begin
                if(araddr>=BASE+27000 && araddr<BASE+27000+4*dimension)require(b_count>=start_b+dimension,"K projection fence");
                if(araddr>=BASE+28000 && araddr<BASE+28000+4*dimension)require(b_count>=start_b+2*dimension,"V projection fence");
                if(araddr>=BASE+26000 && araddr<BASE+26000+4*dimension)require(b_count>=start_b+5*dimension+4*groups,"Q projection fence");
            end
        end
    end
    task automatic reset_all;
        @(negedge clk);rst=1;job_valid=0;completion_ready=0;hold_r=0;hold_b=0;fault=0;checking=0;graph_running=0;
        repeat(4)@(negedge clk);rst=0;repeat(2)@(negedge clk);require(job_ready && !configured && !completion_valid,"reset invalidates graph/KV");
    endtask
    task automatic submit(input integer op,input integer id);
        @(negedge clk);require(job_ready,"admission");job_opcode=8'(op);expected_id=id;job_valid=1;
        @(negedge clk);job_valid=0;
    endtask
    task automatic finish(input integer code,input integer phase=-1);
        integer wd;logic [3:0] saved_stage;wd=0;
        while(!completion_valid)begin @(negedge clk);wd++;require(wd<1000000,"root watchdog");end
        require(completion_status==code && completion_task_id==expected_id,"root status/ID");
        require(result_available==(code==0),"result visibility");if(phase>=0)require(stage==phase,"commit/recovery phase retained");saved_stage=stage;
        repeat(7)begin @(negedge clk);require(completion_valid && completion_task_id==expected_id && completion_status==code && stage==saved_stage && !job_ready,"held completion and phase");end
        completion_ready=1;@(negedge clk);completion_ready=0;checking=0;graph_running=0;tasks++;
    endtask
    task automatic read_task(input integer f,output bounded_task_t t);
        integer rc;t='0;
        rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
            t.desc.task_id,t.desc.m,t.desc.n,t.desc.k,t.desc.a_addr,t.desc.w_addr,t.desc.sx_addr,t.desc.sw_addr,t.desc.y_addr,
            t.desc.a_stride,t.desc.w_stride,t.desc.sx_stride,t.desc.sw_stride,t.desc.y_stride,t.a_bytes,t.w_bytes,t.sx_bytes,t.sw_bytes,t.y_bytes);
        require(rc==19,"projection metadata");t.desc.a_addr+=BASE;t.desc.w_addr+=BASE;t.desc.sx_addr+=BASE;t.desc.sw_addr+=BASE;t.desc.y_addr+=BASE;
        t.desc.group_size=GROUP_SIZE;t.desc.activation_format=1;t.desc.weight_format=1;t.desc.scale_format=1;t.desc.output_format=1;
    endtask
    task automatic load_step(input integer cid,input integer step);
        integer f,rc,k,head,token,gain,id;string stem;
        stem=$sformatf("g%0d_c%0d_s%0d",GROUP_SIZE,cid,step);f=$fopen({stem,".txt"},"r");require(f!=0,"vectors opened");
        rc=$fscanf(f,"%d %d %d %d %d %d",dimension,k,head,token,gain,id);require(rc==6,"case header");groups=(dimension+GROUP_SIZE-1)/GROUP_SIZE;
        active_plan='0;read_task(f,active_plan.q_task);read_task(f,active_plan.k_task);read_task(f,active_plan.v_task);
        kv_config='0;kv_config.config_id=700+cid;kv_config.layers=1;kv_config.heads=2;kv_config.capacity=4;kv_config.dimension=16'(dimension);kv_config.group_size=GROUP_SIZE;kv_config.format_id=1;
        for(integer p=0;p<4;p++)begin rc=$fscanf(f,"%d",kv_config.base[p]);require(rc==1,"KV base");kv_config.base[p]+=BASE;end
        for(integer p=0;p<4;p++)begin rc=$fscanf(f,"%d",kv_config.token_stride[p]);require(rc==1,"KV token stride");end
        for(integer p=0;p<4;p++)begin rc=$fscanf(f,"%d",kv_config.head_stride[p]);require(rc==1,"KV head stride");end
        for(integer p=0;p<4;p++)begin rc=$fscanf(f,"%d",kv_config.bytes[p]);require(rc==1,"KV size");kv_config.layer_stride[p]=kv_config.bytes[p];end
        for(integer branch=0;branch<3;branch++)for(integer i=0;i<dimension;i++)begin rc=$fscanf(f,"%d",expected_q[branch][i]);require(rc==1,"quant value");end
        for(integer branch=0;branch<3;branch++)for(integer i=0;i<dimension;i++)begin rc=$fscanf(f,"%d",expected_s[branch][i]);require(rc==1,"quant scale");end
        $fclose(f);$readmemh({stem,".input.hex"},input_image);$readmemh({stem,".expected.hex"},expected);
        $readmemh({stem,".read.hex"},memory.read_allowed);$readmemh({stem,".write.hex"},memory.write_allowed);
        for(integer i=0;i<65536;i++)if(step==0 || memory.read_allowed[i] && !memory.write_allowed[i])memory.mem[i]=input_image[i];
        if($test$plusargs("corrupt_expected"))expected[50000]^=1;
        active_plan.token=16'(token);active_plan.attention.task_id=id;active_plan.attention.head=16'(head);
        active_plan.attention.tokens=16'(token+1);active_plan.attention.dimension=16'(dimension);active_plan.attention.score_scale=16'(gain);
        active_plan.attention.y_addr=BASE+30000;active_plan.attention.y_bytes=4*dimension;
        active_plan.attention.q_source=2;active_plan.attention.q_addr=BASE+26000;active_plan.attention.q_bytes=4*dimension;
    endtask
    task automatic start_graph;
        qkv_plan=active_plan;start_b=b_count;for(integer j=0;j<3;j++)received[j]=0;
        checking=1;graph_running=1;submit(OP_QKV_ATTENTION,active_plan.attention.task_id);qkv_plan='0;
    endtask
    task automatic compare_image;
        for(integer i=0;i<65536;i++)begin require(memory.mem[i]===expected[i],$sformatf("full image %0d",i));bytes_checked++;end
    endtask
    initial begin
        integer before_reads,before_writes;linear_task='0;ffn_plan='0;kv_config='0;kv_command='0;attention_task='0;qkv_plan='0;active_plan='0;
        for(integer cid=0;cid<3;cid++)begin
            reset_all();load_step(cid,0);submit(OP_KV_CONFIG,kv_config.config_id);finish(0);
            if(cid==0)begin
                good_plan=active_plan;before_reads=reads;before_writes=writes;
                for(integer bad=0;bad<9;bad++)begin
                    active_plan=good_plan;
                    case(bad)
                        0:active_plan.attention.q_source=1;
                        1:active_plan.v_task.a_bytes=1;
                        2:begin active_plan.q_task.desc.y_addr=kv_config.base[2];active_plan.attention.q_addr=active_plan.q_task.desc.y_addr;end
                        3:active_plan.k_task.desc.y_addr=active_plan.v_task.desc.sx_addr;
                        4:active_plan.v_task.desc.task_id=active_plan.k_task.desc.task_id;
                        5:begin active_plan.q_task.desc.k=8192;active_plan.k_task.desc.k=8192;active_plan.v_task.desc.k=8192;end
                        6:begin active_plan.attention.dimension=129;active_plan.q_task.desc.n=129;active_plan.k_task.desc.n=129;active_plan.v_task.desc.n=129;end
                        7:active_plan.q_task.desc.w_addr=64'hffff_ffff_ffff_fffc;
                        8:active_plan.v_task.desc.flags=1;
                    endcase
                    start_graph();finish((bad==0 || bad==4 || bad==8)?STATUS_BAD_FLAGS:(bad==5 || bad==6)?STATUS_BAD_DIM:bad==7?STATUS_BAD_ADDRESS:STATUS_BAD_REGION,0);
                    require(reads==before_reads && writes==before_writes,"entire graph preflight before AXI");
                end
                active_plan=good_plan;
            end
            for(integer step=0;step<3;step++)begin
                if(step>0)load_step(cid,step);
                if(cid==0 && step==1)begin
                    for(integer phase=8;phase<=12;phase++)begin
                        fault=phase;start_graph();finish(phase==12?STATUS_WRITE_ERROR:STATUS_READ_ERROR,phase);fault=0;
                        require(received[0]==0,"precommit failure prevents Q launch");
                    end
                    attention_task=active_plan.attention;attention_task.tokens=2;
                    submit(OP_ATTENTION,attention_task.task_id);finish(STATUS_BAD_DIM);
                end
                if(cid==0 && step==2)begin
                    fault=13;start_graph();finish(STATUS_READ_ERROR,13);fault=0;
                    linear_task=active_plan.q_task;attention_task=active_plan.attention;received[0]=0;checking=1;
                    submit(OP_Q_ATTENTION,attention_task.task_id);finish(0);require(received[0]==dimension,"Q-only recovery after committed append");compare_image();
                end else begin
                    start_graph();
                    if(step==0)begin
                        wait(stage==12);hold_b=1;wait(wvalid && wready);repeat(40)@(negedge clk);
                        require(!completion_valid && stage==12 && received[0]==0,"pending KV B blocks Q/attention");hold_b=0;
                    end
                    finish(0,13);for(integer j=0;j<3;j++)require(received[j]==dimension,"all three vectors quantized");
                    require(b_count-start_b==6*dimension+4*groups,"all projection/KV/Y writes acknowledged");compare_image();
                end
            end
        end
        // Reset with a real K-quantization read outstanding, then reconfigure.
        reset_all();load_step(0,0);submit(OP_KV_CONFIG,kv_config.config_id);finish(0);start_graph();
        wait(stage==9);hold_r=1;wait(arvalid && arready);repeat(5)@(negedge clk);require(!completion_valid,"quant read pending before reset");
        reset_all();load_step(0,0);submit(OP_KV_CONFIG,kv_config.config_id);finish(0);start_graph();finish(0,13);compare_image();
        $display("QKV_TESTS_PASS group=%0d address_width=%0d tasks=%0d bytes=%0d checks=%0d",GROUP_SIZE,ADDR_WIDTH,tasks,bytes_checked,checks);$finish;
    end
    initial begin #1000000000;$fatal(1,"QKV_GLOBAL_TIMEOUT");end
    initial if($test$plusargs("timeout_probe"))begin #20000;$fatal(1,"QKV_FORCED_TIMEOUT");end
endmodule
module tb_qkv_attention3;tb_qkv_attention #(.GROUP_SIZE(3)) test();endmodule
module tb_qkv_attention32;tb_qkv_attention #(.ADDR_WIDTH(32),.BASE(0)) test();endmodule
module tb_qkv_attention1;tb_qkv_attention #(.GROUP_SIZE(1)) test();endmodule
