`timescale 1ns/1ps
// Cross-engine ownership and KV lifetime regression on ONE physical llm_top.
module tb_system_mixed;
    import accelerator_pkg::*;import kv_cache_pkg::*;import attention_pkg::*;import task_desc_pkg::*;
    localparam integer ADDR_WIDTH=64;localparam logic [63:0] BASE=64'h3_0000_0000;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,job_valid=0,job_ready,completion_valid,completion_ready=0,result_available,configured;
    logic [7:0] job_opcode=0,completion_status;
    bounded_task_t linear_task;ffn_plan_t ffn_plan;kv_config_t kv_config;kv_command_t kv_command;attention_task_t attention_task;
    logic append_valid=0,append_ready,append_last=0,read_valid,read_ready=1,read_last;
    logic [7:0] append_data=0,read_data;
    logic q_valid=0,q_ready,q_last=0;logic signed [7:0] q_data=3;logic [15:0] q_scale=4096;
    logic load_pause=0,post_pause=0,array_pause=0;logic [3:0] stage;
    logic [31:0] elapsed_cycles,activation_written,scale_written,completion_task_id;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [63:0] araddr,awaddr,rdata,wdata;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic setup=0,hold_b=0,hold_r=0,inject_r=0,inject_b=0;
    integer reads,writes,b_count,checks=0,tasks=0,expected_id;
    llm_graph_top #(.GROUP_SIZE(4),.ROWS(2),.COLS(2),.TILE_K(3),.MAX_M(4),.MAX_N(4),.MAX_K(64),
        .MAX_H(8),.CAPACITY(16),.MAX_DIM(8),.MAX_TOKENS(4)) dut(.qkv_plan('0),.*);
    system_axi_memory #(.BASE(BASE)) memory(.*);
    task automatic require(input bit c,input string m);
        checks++;if(!c)$fatal(1,"MIXED_CHECK_FAILED %s time=%0t",m,$time);
    endtask
    task automatic submit(input logic [7:0] op,input integer id);
        @(negedge clk);require(job_ready,"single host admission");job_opcode=op;expected_id=id;job_valid=1;
        @(negedge clk);job_valid=0;
    endtask
    task automatic finish(input integer status);
        integer wd;wd=0;
        while(!completion_valid)begin @(negedge clk);wd++;require(wd<50000,"mixed watchdog");end
        require(completion_task_id==expected_id && completion_status==status,"mixed completion routing");
        require(!job_ready && result_available==(status==0),"held completion owns system");
        repeat(5)begin @(negedge clk);require(completion_valid && completion_task_id==expected_id,"held task ID");end
        completion_ready=1;@(negedge clk);completion_ready=0;tasks++;
    endtask
    function automatic integer result_at(input integer a);
        return {memory.mem[a+3],memory.mem[a+2],memory.mem[a+1],memory.mem[a]};
    endfunction
    task automatic query(input integer id,input integer status);
        attention_task.task_id=id;submit(OP_ATTENTION,id);
        @(negedge clk);q_valid=1;q_last=1;
        while(!q_ready) @(negedge clk);
        @(negedge clk);q_valid=0;finish(status);
    endtask
    initial begin
        linear_task='0;ffn_plan='0;kv_config='0;kv_command='0;attention_task='0;
        for(integer i=0;i<65536;i++)begin memory.mem[i]=8'hcd;memory.read_allowed[i]=0;memory.write_allowed[i]=0;end
        memory.mem[4093]=2;memory.mem[10001]=8'h0d;memory.mem[16000]=0;memory.mem[16001]=16;
        memory.mem[20000]=0;memory.mem[20001]=16;
        memory.read_allowed[4093]=1;memory.read_allowed[10001]=1;
        for(integer i=0;i<2;i++)begin memory.read_allowed[16000+i]=1;memory.read_allowed[20000+i]=1;end
        for(integer i=0;i<4;i++)begin memory.write_allowed[30004+i]=1;memory.write_allowed[36000+i]=1;end
        linear_task.desc.task_id=100;linear_task.desc.m=1;linear_task.desc.n=1;linear_task.desc.k=1;
        linear_task.desc.a_addr=BASE+4093;linear_task.desc.w_addr=BASE+10001;
        linear_task.desc.sx_addr=BASE+16000;linear_task.desc.sw_addr=BASE+20000;linear_task.desc.y_addr=BASE+30004;
        linear_task.desc.a_stride=1;linear_task.desc.w_stride=1;linear_task.desc.sx_stride=2;linear_task.desc.sw_stride=2;linear_task.desc.y_stride=4;
        linear_task.desc.group_size=4;linear_task.desc.activation_format=1;linear_task.desc.weight_format=1;linear_task.desc.scale_format=1;linear_task.desc.output_format=1;
        linear_task.a_bytes=1;linear_task.w_bytes=1;linear_task.sx_bytes=2;linear_task.sw_bytes=2;linear_task.y_bytes=4;
        kv_config.config_id=200;kv_config.layers=1;kv_config.heads=1;kv_config.capacity=2;kv_config.dimension=1;kv_config.group_size=4;kv_config.format_id=1;
        kv_config.base[0]=BASE+32001;kv_config.base[1]=BASE+33001;kv_config.base[2]=BASE+34000;kv_config.base[3]=BASE+35000;
        for(integer p=0;p<4;p++)begin
            kv_config.token_stride[p]=4;kv_config.head_stride[p]=8;kv_config.layer_stride[p]=8;kv_config.bytes[p]=p<2?5:6;
            for(integer t=0;t<2;t++)for(integer i=0;i<(p<2?1:2);i++)begin
                memory.read_allowed[integer'(kv_config.base[p]-BASE)+t*4+i]=1;
                memory.write_allowed[integer'(kv_config.base[p]-BASE)+t*4+i]=1;
            end
        end
        attention_task.dimension=1;attention_task.tokens=1;attention_task.score_scale=4096;
        attention_task.y_addr=BASE+36000;attention_task.y_bytes=4;
        repeat(4)@(negedge clk);rst=0;repeat(2)@(negedge clk);
        submit(OP_LINEAR,100);finish(0);require(result_at(30004)==-393216,"linear before KV");
        kv_command.task_id=199;kv_command.operation=KV_CLEAR;submit(OP_KV_COMMAND,199);finish(STATUS_BAD_FLAGS);
        require(!configured,"unconfigured command rejects with its own task ID");
        submit(OP_KV_CONFIG,200);finish(0);require(configured,"configuration survives next engine");
        kv_config.config_id=202;submit(OP_KV_CONFIG,202);finish(STATUS_BAD_FLAGS);
        require(configured,"reconfiguration rejection preserves committed configuration");
        kv_command.task_id=201;kv_command.operation=KV_APPEND;kv_command.count=1;
        submit(OP_KV_COMMAND,201);
        for(integer i=0;i<6;i++)begin
            @(negedge clk);append_valid=1;append_last=i==5;
            case(i)0:append_data=4;1:append_data=8'hfb;3,5:append_data=16;default:append_data=0;endcase
            while(!append_ready)@(negedge clk);
            @(negedge clk);append_valid=0;
        end
        finish(0);query(300,0);require(result_at(36000)==-327680,"attention from committed KV");
        memory.mem[4093]=1;linear_task.desc.task_id=101;submit(OP_LINEAR,101);finish(0);
        require(result_at(30004)==-196608,"linear after attention");require(configured,"KV metadata survives linear");
        query(301,0);require(result_at(36000)==-327680,"attention reuses persistent KV");
        inject_r=1;query(302,STATUS_READ_ERROR);inject_r=0;
        linear_task.desc.task_id=102;submit(OP_LINEAR,102);finish(0);
        require(result_at(30004)==-196608,"other engine works after attention read failure");
        query(303,0);require(result_at(36000)==-327680,"attention recovers after cross-engine task");
        $display("ACCELERATOR_TESTS_PASS mixed=1 address_width=64 tasks=%0d checks=%0d",tasks,checks);$finish;
    end
    initial begin #100000000;$fatal(1,"MIXED_GLOBAL_TIMEOUT");end
endmodule
