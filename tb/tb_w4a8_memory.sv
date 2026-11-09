`timescale 1ns/1ps
module tb_w4a8_memory #(
    parameter integer ROWS=4,COLS=4,TILE_K=8,GROUP_SIZE=32,
    parameter bit REAL_CORE=1,REQUIRE_BURST=0,WEIGHT_CACHE=1,SX_CACHE=1,CONTEXT_PROBE=0
);
    import w4a8_memory_pkg::*;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,task_valid=0,task_ready,completion_valid,completion_ready=0;
    memory_task_t task_desc,loaded_desc;
    logic [31:0] completion_task_id;logic [3:0] completion_status;
    logic core_start,core_reset,core_start_ready,core_done,core_error,core_done_raw,core_error_raw;
    bit inject_core_error=0,inject_core_done=0,inject_bad_req=0;
    assign core_done=core_done_raw || inject_core_done;
    assign core_error=core_error_raw || inject_core_error;
    logic [15:0] cfg_m,cfg_n,cfg_k;
    logic req_valid,req_ready,req_scale,req_activation;
    logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group;
    logic in_valid,in_ready;logic [63:0] in_data;logic [7:0] in_keep;
    logic out_valid,out_ready,out_last;logic [15:0] out_m,out_n;logic signed [31:0] out_data;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [31:0] araddr,awaddr;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic [63:0] rdata,wdata;
    logic [31:0] cycles,read_bytes,write_bytes,read_bus_bytes,write_bus_bytes,
        packet_bytes,packet_bus_bytes,read_wait,write_wait,input_wait,output_wait;
    logic [3:0] packet_high_water;logic write_high_water;
    logic setup=0,random_stalls=1,hold_b=0,inject_r=0,inject_b=0,inject_rlast=0,inject_rid=0,inject_bid=0;
    integer reads,writes,b_count;
    bit load_pause=0,post_pause=0,array_pause=0,force_load=0,force_array=0;
    wire core_rst=rst || core_reset;
    w4a8_memory_bridge #(.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),.GROUP_SIZE(GROUP_SIZE),.WEIGHT_CACHE(WEIGHT_CACHE),.SX_CACHE(SX_CACHE)) bridge(.*);
    w4a8_axi_memory memory(.desc(loaded_desc),.*);
    integer golden[0:4095];
    generate if(REAL_CORE) begin: real_compute
        w4a8_wave #(.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),.GROUP_SIZE(GROUP_SIZE)) core(
            .clk(clk),.rst(core_rst),.load_pause(load_pause),.post_pause(post_pause),.array_pause(array_pause),
            .start(core_start),.start_ready(core_start_ready),.done(core_done_raw),.error(core_error_raw),.busy(),
            .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.req_valid(req_valid),.req_ready(req_ready),
            .req_m(req_m),.req_n(req_n),.req_k(req_k),.req_ml(req_ml),.req_nl(req_nl),.req_kl(req_kl),
            .req_group(req_group),.req_scale(req_scale),.req_activation(req_activation),
            .in_valid(in_valid),.in_ready(in_ready),.in_data(in_data),.in_keep(in_keep),
            .out_valid(out_valid),.out_ready(out_ready),.out_m(out_m),.out_n(out_n),.out_last(out_last),.out_data(out_data));
    end else begin: unit_driver
        // Storage unit driver: all four combinations of activation/scale flags,
        // followed by output coordinates in column order to test address generation.
        integer mt,nt,q,len,oi;
        bit active,waiting,output_phase;
        assign core_start_ready=!active;
        assign in_ready=!load_pause;
        assign core_error_raw=0;
        always @(posedge clk) begin
            if(core_rst) begin
                active<=0;waiting<=0;output_phase<=0;req_valid<=0;out_valid<=0;core_done_raw<=0;
                mt=0;nt=0;q=0;oi=0;
            end else begin
                core_done_raw<=0;
                if(core_start) begin active<=1;mt=0;nt=0;q=0;oi=0;end
                if(active && !output_phase && !waiting && !req_valid) begin
                    len=(cfg_k-q<TILE_K)?cfg_k-q:TILE_K;
                    if(len>GROUP_SIZE-q%GROUP_SIZE) len=GROUP_SIZE-q%GROUP_SIZE;
                    req_m<=16'(mt);req_n<=16'(nt);req_k<=16'(q);req_kl<=inject_bad_req?16'd0:16'(len);
                    req_ml<=16'((CONTEXT_PROBE && nt==0)?1:((cfg_m-mt<ROWS)?cfg_m-mt:ROWS));
                    req_nl<=16'((cfg_n-nt<COLS)?cfg_n-nt:COLS);req_group<=16'(q/GROUP_SIZE);
                    req_activation<=nt==0;req_scale<=q+len==cfg_k || (q+len)%GROUP_SIZE==0;
                    req_valid<=1;
                end
                if(req_valid && req_ready) begin
                    req_valid<=0;waiting<=1;
                    req_m<=16'hffff;req_n<=16'hffff;req_k<=16'hffff;req_ml<=0;req_nl<=0;req_kl<=0;
                    req_group<=16'hffff;req_scale<=0;req_activation<=0;
                end
                if(waiting && bridge.packet_idle) begin
                    waiting<=0;q=q+len;
                    if(q==cfg_k) begin q=0;nt=nt+COLS;end
                    if(nt>=cfg_n) begin nt=0;mt=mt+ROWS;end
                    if(mt>=cfg_m) output_phase<=1;
                end
                if(active && output_phase && !out_valid) begin
                    out_m<=16'(oi%cfg_m);out_n<=16'(oi/cfg_m);
                    out_data<=golden[(oi%cfg_m)*cfg_n+oi/cfg_m];
                    out_last<=oi+1==cfg_m*cfg_n;out_valid<=1;
                end
                if(out_valid && out_ready) begin
                    out_valid<=0;oi=oi+1;
                    if(out_last) begin active<=0;core_done_raw<=1;end
                end
            end
        end
    end endgenerate

    bit corrupted_cache=0;
    always @(negedge clk) if(!rst && !corrupted_cache) begin
        if($test$plusargs("corrupt_weight_cache") && bridge.packet.state==4'd1 && bridge.packet.phase==0 &&
            bridge.packet.weight_hit && bridge.packet.pos==0 && bridge.packet.slot==0) begin
            bridge.packet.weight_row[0]=bridge.packet.weight_row[0]^128'd1;corrupted_cache=1;
        end
        if($test$plusargs("corrupt_sx_cache") && bridge.packet.state==4'd1 && bridge.packet.phase==2 &&
            bridge.packet.sx_hit && bridge.packet.rg==0 && bridge.packet.pos==0) begin
            bridge.packet.scale_byte_bank[0].bytes[0]=bridge.packet.scale_byte_bank[0].bytes[0]^8'd1;corrupted_cache=1;
        end
    end

    logic [7:0] original[0:65535];
    logic [63:0] expected_data[0:10000];logic [7:0] expected_keep[0:10000];
    integer expected_addr[0:100000];
    integer ep=0,cp=0,ea=0,ca=0,outputs=0,checks=0,ticks=0,tasks=0,report,odd_requests=0,holey=0;
    integer aw_first=0,w_first=0,start_count=0,burst_count=0;
    bit pending_aw=0,pending_w=0;
    // Packet order remains exact. Row prefetch can reorder legal reads; scale
    // reuse removes only independently predicted repeated sx bytes.
    integer expected_read_count[0:65535];
    bit reference_sx_valid[0:127],reference_tag_valid=0,reference_sx_hit=0;
    integer reference_m=0,reference_ml=0,logical_bytes=0,ml_context_changes=0;
    bit checking=0,seen[0:4095],held_in=0,held_ar=0,held_aw=0,held_w=0,held_completion=0,held_req=0,held_out=0;
    logic [71:0] old_in,old_w;logic [31:0] old_ar,old_aw;logic [35:0] old_completion;
    logic [113:0] old_req;logic [64:0] old_out;
    wire [113:0] req_payload={req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group,req_scale,req_activation};
    wire [64:0] out_payload={out_m,out_n,out_last,out_data};
    logic [31:0] rng=32'h8593abcd;
    task automatic require(input bit condition,input string message);
        checks++;if(!condition) $fatal(1,"W4A8_MEMORY_CHECK_FAILED %s time=%0t",message,$time);
    endtask
    // Independent enumeration from accepted request and original byte image.
    // Does not use packet state, addr helpers, or read payload as the reference.
    task automatic add_packet(input integer phase,lane,pos,span);
        integer addr;bit valid_byte;
        logic [63:0] data;logic [7:0] keep;
        data=64'ha5a5a5a5a5a5a5a5;keep=0;
        for(integer j=0;j<8;j++) begin
            valid_byte=(phase==0)?(lane+j/4<req_nl && pos+j%4<span):(pos+j<span);
            if(valid_byte) begin
                case(phase)
                    0:addr=loaded_desc.w_base+(req_n+lane+j/4)*loaded_desc.w_stride+req_k/2+pos+j%4;
                    1:addr=loaded_desc.a_base+(req_m+lane)*loaded_desc.a_stride+req_k+pos+j;
                    2:addr=loaded_desc.sx_base+(req_m+(pos+j)/2)*loaded_desc.sx_stride+2*req_group+(pos+j)%2;
                    3:addr=loaded_desc.sw_base+req_group*loaded_desc.sw_stride+2*req_n+pos+j;
                endcase
                require(ea<100000 && addr>=0 && addr<65536,"reference address bounds");
                logical_bytes++;
                if(phase!=2 || !reference_sx_hit) begin
                    expected_addr[ea]=addr;ea++;expected_read_count[addr]++;
                end
                data[j*8 +:8]=original[addr];keep[j]=1;
            end
        end
        require(ep<10000,"packet scoreboard bounds");expected_data[ep]=data;expected_keep[ep]=keep;ep++;
    endtask
    task automatic enumerate_request;
        integer span;
        if(reference_tag_valid && reference_m==req_m && reference_ml!=req_ml)ml_context_changes++;
        if(!reference_tag_valid || reference_m!=req_m || reference_ml!=req_ml)
            for(integer g=0;g<128;g++)reference_sx_valid[g]=0;
        reference_m=req_m;reference_ml=req_ml;reference_tag_valid=1;
        reference_sx_hit=SX_CACHE && req_group<128 && reference_sx_valid[req_group];
        span=(req_k%2+req_kl+1)/2;
        for(integer c=0;c<req_nl;c+=2) for(integer p=0;p<span;p+=4) add_packet(0,c,p,span);
        if(req_activation) for(integer r=0;r<req_ml;r++) for(integer p=0;p<req_kl;p+=8) add_packet(1,r,p,req_kl);
        if(req_scale) begin
            for(integer p=0;p<2*req_ml;p+=8) add_packet(2,0,p,2*req_ml);
            for(integer p=0;p<2*req_nl;p+=8) add_packet(3,0,p,2*req_nl);
            if(SX_CACHE && req_group<128)reference_sx_valid[req_group]=1;
        end
    endtask
    always @(negedge clk) begin
        if(!rst) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            load_pause=force_load || (random_stalls && rng[2:0]<2);
            array_pause=force_array || (random_stalls && rng[6:4]==0);
            post_pause=random_stalls && rng[10:8]==0;
        end
    end
    always @(posedge clk) begin
        ticks++;
        if(rst || core_reset) begin held_in=0;held_req=0;held_out=0;end
        if(rst) begin held_ar=0;held_aw=0;held_w=0;held_completion=0;pending_aw=0;pending_w=0;end
        else begin
            if(core_start) start_count++;
            if(arvalid && arready && arlen!=0) burst_count++;
            if(awvalid && awready) begin if(!pending_w) aw_first++;pending_aw=1;end
            if(wvalid && wready) begin if(!pending_aw) w_first++;pending_w=1;end
            if(bvalid && bready) begin pending_aw=0;pending_w=0;end
            if(held_in) require(in_valid && {in_keep,in_data}===old_in,"packet held under pause");
            if(held_req) require(req_valid && req_payload===old_req,"all request fields held under pause");
            if(held_out) require(out_valid && out_payload===old_out,"output fields held under pause");
            if(held_ar) require(arvalid && araddr===old_ar,"AR held under pause");
            if(held_aw) require(awvalid && awaddr===old_aw,"AW held under pause");
            if(held_w) require(wvalid && {wstrb,wdata}===old_w,"W held under pause");
            if(held_completion) require(completion_valid && {completion_task_id,completion_status}===old_completion,"completion held");
            held_in=in_valid && !in_ready;old_in={in_keep,in_data};
            held_req=req_valid && !req_ready;old_req=req_payload;
            held_out=out_valid && !out_ready;old_out=out_payload;
            held_ar=arvalid && !arready;old_ar=araddr;
            held_aw=awvalid && !awready;old_aw=awaddr;
            held_w=wvalid && !wready;old_w={wstrb,wdata};
            held_completion=completion_valid && !completion_ready;old_completion={completion_task_id,completion_status};
            if(checking) begin
                if(req_valid && req_ready) begin
                    require(ca==ea,"previous request exact read footprint drained before next request");
                    enumerate_request();if(req_k[0]) odd_requests++;
                end
                if(arvalid && arready) begin
                    for(integer b=0;b<((integer'(arlen)+1)<<arsize);b++)begin
                        require(ca<ea && araddr+b<65536 && expected_read_count[araddr+b]>0,"AR useful byte multiplicity, no padding/extra/duplicate read");
                        if(!WEIGHT_CACHE && !SX_CACHE)require(araddr+b==expected_addr[ca],"disabled caches preserve original AR order");
                        expected_read_count[araddr+b]--;ca++;
                    end
                end
                if(in_valid && in_ready) begin
                    require(cp<ep && in_keep===expected_keep[cp] && in_data===expected_data[cp],"packet data/keep exact");cp++;
                    if(in_keep!=((1<<$countones(in_keep))-1)) holey++;
                end
                if(out_valid && out_ready) begin
                    require(out_m<loaded_desc.m && out_n<loaded_desc.n,"output coordinate");
                    require(!seen[out_m*loaded_desc.n+out_n],"no duplicate output");seen[out_m*loaded_desc.n+out_n]=1;
                    require(out_data===golden[out_m*loaded_desc.n+out_n],"core bit-exact output");outputs++;
                end
                if(completion_valid && completion_status==MEM_OK) require(b_count==loaded_desc.m*loaded_desc.n,"success after all B responses");
            end
        end
    end
    task automatic reset_all;
        @(negedge clk);rst=1;task_valid=0;checking=0;completion_ready=0;hold_b=0;
        inject_r=0;inject_b=0;inject_rlast=0;inject_rid=0;inject_bid=0;force_load=0;force_array=0;
        inject_core_error=0;inject_core_done=0;inject_bad_req=0;
        repeat(4) @(negedge clk);rst=0;
    endtask
    task automatic load_job(input integer job);
        string filename;integer f,rc,v;
        filename=$sformatf("g%0d_job%0d.txt",GROUP_SIZE,job);f=$fopen(filename,"r");require(f!=0,"task vector opened");
        rc=$fscanf(f,"%d %d %d %d %d %d",loaded_desc.task_id,loaded_desc.m,loaded_desc.n,loaded_desc.k,loaded_desc.format_id,loaded_desc.group_size);require(rc==6,"task fields");
        rc=$fscanf(f,"%d %d %d %d %d",loaded_desc.a_base,loaded_desc.w_base,loaded_desc.sx_base,loaded_desc.sw_base,loaded_desc.y_base);require(rc==5,"bases");
        rc=$fscanf(f,"%d %d %d %d %d",loaded_desc.a_stride,loaded_desc.w_stride,loaded_desc.sx_stride,loaded_desc.sw_stride,loaded_desc.y_stride);require(rc==5,"strides");
        rc=$fscanf(f,"%d %d %d %d %d",loaded_desc.a_bytes,loaded_desc.w_bytes,loaded_desc.sx_bytes,loaded_desc.sw_bytes,loaded_desc.y_bytes);require(rc==5,"regions");
        for(integer i=0;i<loaded_desc.m*loaded_desc.n;i++) begin rc=$fscanf(f,"%d",v);require(rc==1,"golden");golden[i]=v;end
        $fclose(f);
        if($test$plusargs("corrupt_expected")) golden[0]=golden[0]+1;
        $readmemh($sformatf("g%0d_job%0d.hex",GROUP_SIZE,job),memory.mem);
        for(integer i=0;i<65536;i++) original[i]=memory.mem[i];
        task_desc=loaded_desc;ep=0;cp=0;ea=0;ca=0;outputs=0;logical_bytes=0;reference_tag_valid=0;
        for(integer i=0;i<65536;i++)expected_read_count[i]=0;
        for(integer g=0;g<128;g++)reference_sx_valid[g]=0;
        for(integer i=0;i<4096;i++) seen[i]=0;
        @(negedge clk);setup=1;@(negedge clk);setup=0;
    endtask
    task automatic submit;
        integer watchdog;
        watchdog=0;while(!task_ready) begin @(negedge clk);watchdog++;require(watchdog<1000,"submit watchdog");end
        task_valid=1;@(negedge clk);task_valid=0;
    endtask
    task automatic wait_completion(input logic [3:0] status);
        integer watchdog;
        watchdog=0;while(!completion_valid) begin @(negedge clk);watchdog++;require(watchdog<250000,"per-task watchdog");end
        require(completion_task_id==loaded_desc.task_id && completion_status==status,"completion ID/status");
        repeat(7) @(negedge clk);require(!task_ready,"completion blocks task admission");
        completion_ready=1;@(negedge clk);completion_ready=0;tasks++;
    endtask
    task automatic compare_memory;
        integer addr,value;bit destination;
        for(integer r=0;r<loaded_desc.m;r++) for(integer c=0;c<loaded_desc.n;c++) begin
            addr=loaded_desc.y_base+r*loaded_desc.y_stride+4*c;
            value={memory.mem[addr+3],memory.mem[addr+2],memory.mem[addr+1],memory.mem[addr]};
            require(value===golden[r*loaded_desc.n+c],"external Y bit exact");
        end
        for(integer i=0;i<65536;i++) begin
            destination=i>=loaded_desc.y_base && i<loaded_desc.y_base+loaded_desc.y_bytes &&
                (i-loaded_desc.y_base)%loaded_desc.y_stride<4*loaded_desc.n;
            if(!destination) require(memory.mem[i]===original[i],"guard/source/padding protected");
        end
        require(outputs==loaded_desc.m*loaded_desc.n && cp==ep && ca==ea && memory.read_payload==ea && writes==outputs && b_count==outputs,"scoreboard drained");
        require(packet_bytes==logical_bytes,"all logical packet bytes preserved with sx reuse");
        require(read_bus_bytes==8*memory.read_beats && read_bytes==ea && write_bytes==4*outputs && packet_bus_bytes==8*ep,"traffic counters");
        $fdisplay(report,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",loaded_desc.task_id,cycles,read_bytes,write_bytes,read_bus_bytes,write_bus_bytes,packet_bytes,packet_bus_bytes,read_wait,write_wait,input_wait,output_wait,packet_high_water,write_high_water,outputs);
    endtask
    initial begin: tests
        integer timeout_count,before_reads,before_starts;
        report=$fopen("memory_results.csv","w");require(report!=0,"CSV opened");
        $fdisplay(report,"task_id,cycles,read_bytes,write_bytes,read_bus_bytes,write_bus_bytes,packet_bytes,packet_bus_bytes,read_wait,write_wait,input_wait,output_wait,packet_high_water,write_high_water,outputs");
        reset_all();load_job(0);checking=1;force_load=1;submit();
        timeout_count=0;while(!in_valid) begin @(negedge clk);timeout_count++;require(timeout_count<1000,"packet full reached");end
        repeat(40) @(negedge clk);require(in_valid && packet_high_water>0,"bounded packet full holds");force_load=0;
        // Mutate the submission wires after acceptance; DUT must retain the descriptor.
        task_desc='0;
        timeout_count=0;while(!(out_valid && out_last && out_ready)) begin @(negedge clk);timeout_count++;require(timeout_count<250000,"last output reached");end
        hold_b=1;
        timeout_count=0;while(writes<loaded_desc.m*loaded_desc.n) begin @(negedge clk);timeout_count++;require(timeout_count<1000,"last W reached");end
        repeat(100) begin @(negedge clk);require(!completion_valid,"last B fence");end
        require(bridge.done_seen && bridge.last_seen && bridge.wr_idle==0,"core done and last W still await B");
        if(!$test$plusargs("timeout_probe")) hold_b=0;
        wait_completion(MEM_OK);compare_memory();checking=0;
        // Consecutive task: no reset, changed addresses, dimensions and data.
        load_job(1);checking=1;submit();wait_completion(MEM_OK);compare_memory();checking=0;
        // Invalid descriptors must produce no AR/AW/W and never start the core.
        for(integer bad=0;bad<11;bad++) begin
            load_job(0);before_reads=reads;before_starts=start_count;
            case(bad)
                0:task_desc.m=0;1:task_desc.k=4097;2:task_desc.format_id=2;
                3:task_desc.group_size=GROUP_SIZE+1;4:task_desc.a_stride=task_desc.k-1;
                5:task_desc.y_base=task_desc.y_base+1;6:task_desc.sx_base=32'hfffffff0;
                7:task_desc.w_bytes=1;8:task_desc.y_base=task_desc.a_base;
                9:task_desc.sw_stride=1;10:task_desc.n=65;
            endcase
            submit();wait_completion(MEM_BAD_TASK);require(reads==before_reads && writes==0 && start_count==before_starts,"illegal task no access or core start");
        end
        for(integer core_fault=0;core_fault<2;core_fault++) begin
            load_job(0);submit();timeout_count=0;
            while(!arvalid) begin @(negedge clk);timeout_count++;require(timeout_count<1000,"core fault injection point");end
            inject_core_error=core_fault==0;inject_core_done=core_fault==1;
            wait_completion(core_fault==0?MEM_CORE_ERROR:MEM_PROTOCOL_ERROR);
            inject_core_error=0;inject_core_done=0;
            load_job(1);checking=1;submit();wait_completion(MEM_OK);compare_memory();checking=0;
        end
        if(!REAL_CORE) begin
            load_job(0);inject_bad_req=1;submit();wait_completion(MEM_PROTOCOL_ERROR);inject_bad_req=0;
            load_job(1);checking=1;submit();wait_completion(MEM_OK);compare_memory();checking=0;
        end
        // Error transactions are drained; the next task is accepted without system reset.
        for(integer error_case=0;error_case<5;error_case++) begin
            load_job(0);inject_r=error_case==0;inject_b=error_case==1;inject_rlast=error_case==2;
            inject_rid=error_case==3;inject_bid=error_case==4;
            submit();wait_completion((error_case==1 || error_case==4)?MEM_WRITE_ERROR:MEM_READ_ERROR);
            inject_r=0;inject_b=0;inject_rlast=0;inject_rid=0;inject_bid=0;
            load_job(1);checking=1;submit();wait_completion(MEM_OK);compare_memory();checking=0;
        end
        // Joint reset with read in flight, and with write response pending.
        load_job(0);submit();timeout_count=0;
        while(!rvalid) begin @(negedge clk);timeout_count++;require(timeout_count<1000,"read reset point");end
        reset_all();load_job(1);checking=1;submit();wait_completion(MEM_OK);compare_memory();checking=0;
        load_job(0);hold_b=1;submit();timeout_count=0;
        while(writes==0) begin @(negedge clk);timeout_count++;require(timeout_count<250000,"write reset point");end
        reset_all();load_job(1);checking=1;submit();wait_completion(MEM_OK);compare_memory();checking=0;
        if(CONTEXT_PROBE)require(ml_context_changes>0,"same-M changed-ml cache context exercised");
        if(REQUIRE_BURST) require(burst_count>0,"actual multi-beat burst observed by exact byte oracle");
        require(holey>0,"noncontiguous keep observed");
        require(aw_first>0 && w_first>0,"both independent AW/W handshake orders");
        if(TILE_K%2) require(odd_requests>0,"odd req_k observed");
        require(input_wait>0 && output_wait>0 && write_high_water==1,"pause and finite write slot exercised");
        $display("STORAGE_BURST_COVERAGE bursts=%0d required=%0d",burst_count,REQUIRE_BURST);
        $fclose(report);$display("W4A8_MEMORY_TESTS_PASS real=%0d rows=%0d cols=%0d tasks=%0d checks=%0d holey=%0d odd=%0d",REAL_CORE,ROWS,COLS,tasks,checks,holey,odd_requests);$finish;
    end
    initial begin #100000000;$fatal(1,"W4A8_MEMORY_GLOBAL_TIMEOUT");end
endmodule
module tb_w4a8_memory8;tb_w4a8_memory #(.ROWS(8),.COLS(8)) test();endmodule
module tb_w4a8_memory_alt;tb_w4a8_memory #(.ROWS(2),.COLS(3),.TILE_K(5),.GROUP_SIZE(12)) test();endmodule
module tb_w4a8_memory_unit;tb_w4a8_memory #(.ROWS(2),.COLS(3),.TILE_K(5),.GROUP_SIZE(12),.REAL_CORE(0)) test();endmodule

module tb_memory_round7_off;tb_w4a8_memory #(.TILE_K(32),.WEIGHT_CACHE(0),.SX_CACHE(0)) test();endmodule
module tb_memory_round7_weight;tb_w4a8_memory #(.TILE_K(32),.SX_CACHE(0)) test();endmodule
module tb_memory_round7_scale;tb_w4a8_memory #(.TILE_K(32),.WEIGHT_CACHE(0)) test();endmodule
module tb_memory_round7_wide;tb_w4a8_memory #(.TILE_K(64),.GROUP_SIZE(128)) test();endmodule
module tb_memory_round7_group_tail;tb_w4a8_memory #(.TILE_K(32),.GROUP_SIZE(12)) test();endmodule

module tb_memory_round7_context;tb_w4a8_memory #(.TILE_K(32),.REAL_CORE(0),.CONTEXT_PROBE(1)) test();endmodule
