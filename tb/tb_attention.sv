`timescale 1ns/1ps
module tb_attention #(parameter integer GROUP_SIZE=4,ADDR_WIDTH=64,MEMORY_Q=0,
    parameter logic [63:0] BASE=64'h2_0000_0000);
    import kv_cache_pkg::*;import attention_pkg::*;import task_desc_pkg::*;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,cfg_valid=0,cfg_ready,cmd_valid=0,cmd_ready,query_valid=0,query_ready;
    kv_config_t cfg_desc;kv_command_t cmd_desc;attention_task_t query_desc,queries[0:4];
    logic append_valid=0,append_ready,append_last=0,read_valid,read_ready=1,read_last;
    logic [7:0] append_data=0,read_data;
    logic q_valid=0,q_ready,q_last=0;logic signed [7:0] q_data=0;logic [15:0] q_scale=0;
    logic completion_valid,completion_ready=0,result_available,configured;
    logic [31:0] completion_task_id;logic [7:0] completion_status;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [ADDR_WIDTH-1:0] araddr,awaddr;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic [63:0] rdata,wdata;
    logic setup=0,hold_b=0,hold_r=0,inject_r=0,inject_b=0;
    integer reads,writes,b_count,checks=0,tasks=0,bytes_checked=0,expected_id;
    integer qs_data[0:4][0:63],qs_scale[0:4][0:63],append_bytes[0:2047],append_count,dimension,capacity,tokens;
    logic [7:0] expected[0:65535];
    attention_test_shell #(.GROUP_SIZE(GROUP_SIZE),.ADDR_WIDTH(ADDR_WIDTH),.MAX_DIM(16),.MAX_TOKENS(8),.MAX_LAYERS(1),.MAX_HEADS(1)) dut(.*);
    system_axi_memory #(.ADDR_WIDTH(ADDR_WIDTH),.BASE(BASE)) memory(.*);
    task automatic require(input bit condition,input string message);
        checks++;if(!condition) $fatal(1,"ATTENTION_CHECK_FAILED %s time=%0t",message,$time);
    endtask
    task automatic finish(input integer status);
        integer wd;wd=0;
        while(!completion_valid) begin @(negedge clk);wd++;require(wd<200000,"attention watchdog");end
        require(completion_task_id==expected_id && completion_status==status,"completion ID/status");
        require(result_available==(status==0),"result visibility");
        repeat(8) begin @(negedge clk);require(completion_valid && completion_task_id==expected_id && completion_status==status && !query_ready && !cmd_ready,"held completion");end
        completion_ready=1;@(negedge clk);completion_ready=0;tasks++;
    endtask
    task automatic load_vectors;
        integer f,rc,g,ncases,v;
        f=$fopen($sformatf("g%0d_meta.txt",GROUP_SIZE),"r");require(f!=0,"metadata opened");
        rc=$fscanf(f,"%d %d %d %d %d",g,dimension,capacity,tokens,ncases);require(rc==5 && ncases==5 && g==GROUP_SIZE,"metadata header");
        cfg_desc='0;cfg_desc.config_id=800;cfg_desc.layers=1;cfg_desc.heads=1;cfg_desc.dimension=16'(dimension);
        cfg_desc.capacity=16'(capacity);cfg_desc.group_size=GROUP_SIZE;cfg_desc.format_id=1;
        for(integer p=0;p<4;p++) begin rc=$fscanf(f,"%d",cfg_desc.base[p]);require(rc==1,"base");cfg_desc.base[p]+=BASE;end
        for(integer p=0;p<4;p++) begin rc=$fscanf(f,"%d",cfg_desc.token_stride[p]);require(rc==1,"stride");end
        for(integer p=0;p<4;p++) begin rc=$fscanf(f,"%d",cfg_desc.bytes[p]);require(rc==1,"bytes");cfg_desc.head_stride[p]=cfg_desc.bytes[p];cfg_desc.layer_stride[p]=cfg_desc.bytes[p];end
        for(integer c=0;c<5;c++) begin
            queries[c]='0;
            rc=$fscanf(f,"%d %d %d %d %d",queries[c].task_id,queries[c].tokens,queries[c].dimension,queries[c].score_scale,queries[c].y_addr);
            require(rc==5,"query descriptor");queries[c].y_addr+=BASE;queries[c].y_bytes=4*32'(queries[c].dimension);
            if(MEMORY_Q) begin
                queries[c].q_source=1;queries[c].q_addr=BASE+22001+c*128;queries[c].qs_addr=BASE+26001+c*128;
                queries[c].q_bytes=dimension;queries[c].qs_bytes=2*((dimension+GROUP_SIZE-1)/GROUP_SIZE);
            end
            for(integer i=0;i<dimension;i++) begin rc=$fscanf(f,"%d",qs_data[c][i]);require(rc==1,"Q byte");end
            for(integer i=0;i<dimension;i++) begin rc=$fscanf(f,"%d",qs_scale[c][i]);require(rc==1,"Q scale");end
        end
        $fclose(f);f=$fopen($sformatf("g%0d_append.txt",GROUP_SIZE),"r");require(f!=0,"append vectors");append_count=0;
        while(!$feof(f)) begin rc=$fscanf(f,"%d",v);if(rc==1) begin append_bytes[append_count]=v;append_count++;end end
        $fclose(f);
        for(integer i=0;i<65536;i++) memory.mem[i]=8'hcd;
        $readmemh($sformatf("g%0d_permissions.hex",GROUP_SIZE),memory.read_allowed);
        $readmemh($sformatf("g%0d_permissions.hex",GROUP_SIZE),memory.write_allowed);
        if(MEMORY_Q) for(integer c=0;c<5;c++) begin
            for(integer i=0;i<dimension;i++) begin
                memory.mem[22001+c*128+i]=8'(qs_data[c][i]);memory.read_allowed[22001+c*128+i]=1;
            end
            for(integer gidx=0;gidx<(dimension+GROUP_SIZE-1)/GROUP_SIZE;gidx++) begin
                memory.mem[26001+c*128+2*gidx]=8'(qs_scale[c][gidx*GROUP_SIZE]);
                memory.mem[26002+c*128+2*gidx]=8'(qs_scale[c][gidx*GROUP_SIZE]>>8);
                memory.read_allowed[26001+c*128+2*gidx]=1;memory.read_allowed[26002+c*128+2*gidx]=1;
            end
        end
    endtask
    task automatic submit_query(input integer c);
        @(negedge clk);require(query_ready,"query admission");query_desc=queries[c];expected_id=queries[c].task_id;
        query_valid=1;@(negedge clk);query_valid=0;query_desc='0;
    endtask
    task automatic feed_query(input integer c,input bit malformed);
        for(integer i=0;i<((MEMORY_Q && !malformed)?0:(malformed?1:dimension));i++) begin
            @(negedge clk);q_valid=1;q_data=8'(qs_data[c][i]);q_scale=16'(qs_scale[c][i]);q_last=malformed || i+1==dimension;
            begin integer wd;wd=0;while(!q_ready) begin @(negedge clk);wd++;require(wd<1000,"Q handshake watchdog");end end
            @(negedge clk);q_valid=0;
        end
    endtask
    task automatic append_batch(input integer first,count);
        integer width,start,amount;
        width=2*dimension+4*((dimension+GROUP_SIZE-1)/GROUP_SIZE);start=first*width;amount=count*width;
        @(negedge clk);require(cmd_ready,"append admission");cmd_desc='0;cmd_desc.task_id=850+first;
        cmd_desc.operation=KV_APPEND;cmd_desc.token=16'(first);cmd_desc.count=16'(count);expected_id=cmd_desc.task_id;
        cmd_valid=1;@(negedge clk);cmd_valid=0;
        for(integer i=0;i<amount;i++) begin
            @(negedge clk);append_valid=1;append_data=8'(append_bytes[start+i]);append_last=i+1==amount;
            begin integer wd;wd=0;while(!append_ready) begin @(negedge clk);wd++;require(wd<1000,"append handshake watchdog");end end
            @(negedge clk);append_valid=0;
        end
        finish(0);
    endtask
    task automatic compare_image(input integer c);
        $readmemh($sformatf("g%0d_expected%0d.hex",GROUP_SIZE,c),expected);
        if(MEMORY_Q) for(integer cidx=0;cidx<5;cidx++) begin
            for(integer i=0;i<dimension;i++) expected[22001+cidx*128+i]=8'(qs_data[cidx][i]);
            for(integer gidx=0;gidx<(dimension+GROUP_SIZE-1)/GROUP_SIZE;gidx++) begin
                expected[26001+cidx*128+2*gidx]=8'(qs_scale[cidx][gidx*GROUP_SIZE]);
                expected[26002+cidx*128+2*gidx]=8'(qs_scale[cidx][gidx*GROUP_SIZE]>>8);
            end
        end
        if($test$plusargs("corrupt_expected")) expected[18000]^=1;
        for(integer i=0;i<65536;i++) begin
            require(memory.mem[i]===expected[i],$sformatf("full image byte=%0d actual=%h expected=%h",i,memory.mem[i],expected[i]));bytes_checked++;
        end
    endtask
    initial begin
        load_vectors();repeat(4) @(negedge clk);rst=0;repeat(2) @(negedge clk);
        submit_query(0);finish(STATUS_BAD_DIM);
        begin kv_config_t saved;
            saved=cfg_desc;cfg_desc.base[0]=64'hffff_ffff_ffff_fffc;
            @(negedge clk);cfg_valid=1;expected_id=800;@(negedge clk);cfg_valid=0;finish(STATUS_BAD_REGION);
            require(!configured && reads==0 && writes==0,"overflowed KV allocation rejected without access");cfg_desc=saved;
        end
        @(negedge clk);require(cfg_ready,"configuration ready");cfg_valid=1;expected_id=800;
        @(negedge clk);cfg_valid=0;finish(0);require(configured,"KV configured");
        for(integer c=0;c<5;c++) begin
            if(c==0) append_batch(0,1);if(c==1) append_batch(1,2);if(c==2) append_batch(3,4);
            submit_query(c);feed_query(c,0);finish(0);compare_image(c);
        end
        if(!MEMORY_Q) begin submit_query(0);feed_query(0,1);finish(STATUS_MEMORY_PROTOCOL);end
        else begin
            @(negedge clk);query_desc=queries[0];query_desc.q_bytes=dimension-1;expected_id=query_desc.task_id;query_valid=1;
            @(negedge clk);query_valid=0;finish(STATUS_BAD_REGION);
        end
        submit_query(0);inject_r=1;feed_query(0,0);finish(STATUS_READ_ERROR);inject_r=0;
        submit_query(0);feed_query(0,0);hold_b=1;wait(wvalid && wready);repeat(80) @(negedge clk);
        require(!completion_valid && !query_ready,"attention completion waits for B response");
        hold_b=0;finish(0);compare_image(4);
        submit_query(0);inject_b=1;feed_query(0,0);finish(STATUS_WRITE_ERROR);inject_b=0;
        submit_query(0);feed_query(0,0);finish(0);compare_image(4);
        @(negedge clk);query_desc=queries[0];query_desc.tokens=capacity;query_valid=1;expected_id=query_desc.task_id;
        @(negedge clk);query_valid=0;finish(STATUS_BAD_DIM);
        @(negedge clk);query_desc=queries[0];query_desc.y_addr=cfg_desc.base[0];query_valid=1;expected_id=query_desc.task_id;
        @(negedge clk);query_valid=0;finish(STATUS_BAD_REGION);
        @(negedge clk);query_desc=queries[0];query_desc.y_addr=64'hffff_ffff_ffff_fffc;query_valid=1;expected_id=query_desc.task_id;
        @(negedge clk);query_valid=0;finish(STATUS_BAD_REGION);
        if(MEMORY_Q) begin
            for(integer kind=0;kind<7;kind++) begin
                integer before_reads,before_writes;
                @(negedge clk);query_desc=queries[0];expected_id=query_desc.task_id;
                case(kind)
                    0:query_desc.q_source=3;
                    1:query_desc.qs_bytes=1;
                    2:query_desc.q_addr=64'hffff_ffff_ffff_fffc;
                    3:query_desc.qs_addr=64'hffff_ffff_ffff_ffff;
                    4:query_desc.q_addr=query_desc.y_addr;
                    5:query_desc.qs_addr=query_desc.q_addr;
                    6:query_desc.q_source=0;
                endcase
                before_reads=reads;before_writes=writes;query_valid=1;
                @(negedge clk);query_valid=0;finish((kind==0 || kind==6)?STATUS_BAD_FLAGS:STATUS_BAD_REGION);
                require(reads==before_reads && writes==before_writes,"invalid Q allocation rejected before any access");
            end
            hold_r=1;submit_query(0);q_valid=1;q_data=127;q_scale=1;q_last=1;
            repeat(80) begin @(negedge clk);require(!completion_valid && !q_ready,"memory Q stalls without accepting host Q");end
            hold_r=0;finish(0);q_valid=0;compare_image(4);
            // Reset both the DUT and fabric while an actual Q read is pending.
            hold_r=1;submit_query(0);wait(arvalid && arready);repeat(3) @(negedge clk);
            rst=1;repeat(4) @(negedge clk);hold_r=0;rst=0;repeat(2) @(negedge clk);
            require(!configured && !completion_valid,"pending Q reset invalidates metadata/completion");
            cfg_valid=1;expected_id=800;@(negedge clk);cfg_valid=0;finish(0);
            append_batch(0,7);submit_query(0);finish(0);compare_image(4);
        end
        $display("ATTENTION_TESTS_PASS group=%0d address_width=%0d memory_q=%0d tasks=%0d bytes=%0d checks=%0d",GROUP_SIZE,ADDR_WIDTH,MEMORY_Q,tasks,bytes_checked,checks);
        $finish;
    end
    initial begin #200000000;$fatal(1,"ATTENTION_GLOBAL_TIMEOUT");end
    initial if($test$plusargs("timeout_probe")) begin #10000;$fatal(1,"ATTENTION_FORCED_TIMEOUT");end
endmodule
module tb_attention3;tb_attention #(.GROUP_SIZE(3)) test();endmodule
module tb_attention32;tb_attention #(.ADDR_WIDTH(32),.BASE(0)) test();endmodule
module tb_attention_default;tb_attention #(.GROUP_SIZE(32)) test();endmodule

module tb_attention_dma;tb_attention #(.MEMORY_Q(1)) test();endmodule
module tb_attention_dma3;tb_attention #(.GROUP_SIZE(3),.MEMORY_Q(1)) test();endmodule
module tb_attention_dma32;tb_attention #(.ADDR_WIDTH(32),.BASE(0),.MEMORY_Q(1)) test();endmodule
module tb_attention_dma_default;tb_attention #(.GROUP_SIZE(32),.MEMORY_Q(1)) test();endmodule
