`timescale 1ns/1ps
module tb_w4a8_wave;
    parameter integer ROWS=4,COLS=4,TILE_K=8,GROUP_SIZE=32,MODES=3,MAX_DATA=8192;
    parameter bit COMPACT_SLOTS=0,EFFECTIVE_DRAIN=0,GEMV_FOLD=0,MULTIROW_FOLD=1,BROADCAST_MAC=0,PACKED_MAC=0;
    parameter integer COPY_LANES=1,POST_LANES=1;
    parameter bit DOUBLE_BUFFER=1,SCALE_ONCE=1,PACK_COLS=1;
    parameter integer BUS_BYTES=8;
    parameter bit POST_OVERLAP=1,POST_PIPELINE=1,A_REUSE=1,SYSTOLIC=1,GROUP_STREAM=1;
    logic [31:0] tile_handoffs,wave_hold_cycles,wave_input_wait_cycles;
    integer shadow_checks=0,seam_hold_checks=0,reclaimed_writes=0,seam_resets=0,seam_resumes=0;
    bit force_load_stall=0,seam_job=0;
    integer last_released=-1;
    logic array_pause=0;
    logic [31:0] array_cycles,array_drain_cycles,array_pause_cycles,array_mac_cycles;
    integer counted_macs=0,counted_array_cycles=0,counted_drain=0,counted_pause=0,counted_active=0;
    integer held_array_checks=0,drain_checks=0,extra_array_resets=0,expected_drain_resets=0,directed_reset_cases=0;
    bit held_array=0,force_array_stall=0;
    logic [31:0] previous_advance_counters[0:4];
    logic post_pause=0;
    logic [31:0] psum_wait_cycles,post_drain_cycles,post_active_cycles,post_issue_cycles,
        post_retire_cycles,compute_post_overlap_cycles,psum_groups;
    integer scaled_checks=0,full_queue_checks=0,held_pipe_checks=0,extra_post_resets=0;
    bit force_post_stall=0,pressure_job=0;
    bit held_post=0;
    logic [193:0] previous_pipe;
    wire [193:0] pipe_payload={dut.v0,dut.v1,dut.tag0,dut.tag1,dut.factor,dut.scaled,dut.y_base};
    localparam integer W_LANES=(PACK_COLS && BUS_BYTES==8)?2:1,W_BYTES=BUS_BYTES/W_LANES;
    integer dual_writes=0,holey_keeps=0,odd_k_requests=0;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,load_pause=0,start=0,start_ready,busy,done,error;
    logic [15:0] cfg_m=0,cfg_n=0,cfg_k=0;
    logic req_valid,req_ready,in_valid,in_ready,out_valid,out_ready=1,out_last;
    logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group,out_m,out_n;
    logic [BUS_BYTES*8-1:0] in_data;
    logic [BUS_BYTES-1:0] in_keep;
    logic req_scale,req_activation;
    logic [31:0] input_beats,padding_bytes;
    logic signed [31:0] out_data;
    logic [31:0] total_cycles,weight_bytes,activation_bytes,scale_bytes,valid_macs,compute_cycles,
                       input_wait_cycles,output_wait_cycles,overlap_cycles;
    integer mode=0,m=0,n=0,k=0,ng=0;
    w4a8_wave #(.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),.GROUP_SIZE(GROUP_SIZE),
                   .DOUBLE_BUFFER(DOUBLE_BUFFER),.BUS_BYTES(BUS_BYTES),.SCALE_ONCE(SCALE_ONCE),.PACK_COLS(PACK_COLS),.POST_OVERLAP(POST_OVERLAP),.POST_PIPELINE(POST_PIPELINE),.A_REUSE(A_REUSE),.SYSTOLIC(SYSTOLIC),.GROUP_STREAM(GROUP_STREAM),.COMPACT_SLOTS(COMPACT_SLOTS),.EFFECTIVE_DRAIN(EFFECTIVE_DRAIN),.GEMV_FOLD(GEMV_FOLD),
                   .COPY_LANES(COPY_LANES),.POST_LANES(POST_LANES),.BROADCAST_MAC(BROADCAST_MAC),.PACKED_MAC(PACKED_MAC)) dut(.*);
    w4a8_reuse_memory #(.GROUP_SIZE(GROUP_SIZE),.BUS_BYTES(BUS_BYTES),.PACK_COLS(PACK_COLS),.MAX_DATA(MAX_DATA)) memory(
        .clk(clk),.rst(rst),.task_start(start && start_ready),.mode(mode),.m(m),.n(n),.k(k),.ng(ng),
        .req_valid(req_valid),.req_ready(req_ready),.req_scale(req_scale),.req_activation(req_activation),.req_m(req_m),.req_n(req_n),.req_k(req_k),
        .req_ml(req_ml),.req_nl(req_nl),.req_kl(req_kl),.req_group(req_group),
        .in_valid(in_valid),.in_ready(in_ready),.in_data(in_data),.in_keep(in_keep));
    logic [7:0] unpack_byte=0;logic unpack_high=0;wire signed [7:0] unpack_value;
    w4_unpack unit_unpack(.packed_byte(unpack_byte),.high(unpack_high),.value(unpack_value));
    integer golden[0:4095],psum_golden[0:MAX_DATA-1];
    bit seen[0:4095];
    integer f,rc,cases,cid,report,x,md,elapsed,outputs,groups_checked;
    integer eb,ep,wb,ew,ea,es,et,em,ec,ed,epi,ml,nl,len,mt,nt,q,checks=0,comparisons=0,psum_comparisons=0,tasks=0;
    integer ticks=0,all_overlap=0,all_input_wait=0,all_output_wait=0,held_input_checks=0;
    bit checking=0,force_output_stall=0,held_out=0,held_in=0,held_req=0,ready_overlap=0;
    logic [64:0] old_out;
    logic [BUS_BYTES*9-1:0] old_in;
    logic [113:0] old_req;
    wire [64:0] out_payload={out_m,out_n,out_last,out_data};
    wire [113:0] req_payload={req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group,req_scale,req_activation};
    localparam integer CACHE_DEPTH=((4096+GROUP_SIZE-1)/GROUP_SIZE)*((GROUP_SIZE+TILE_K-1)/TILE_K)*((TILE_K+BUS_BYTES-1)/BUS_BYTES);
    bit cache_valid[0:ROWS-1][0:CACHE_DEPTH-1];
    integer cache_epoch=-1,cache_hits=0,cache_writes=0,cache_switches=0;
    function automatic integer reference_factor(input integer active_rows);
        integer factor;
        factor=1;
        if(GEMV_FOLD && SYSTOLIC && A_REUSE && ROWS<=BUS_BYTES && ROWS<=2*W_BYTES &&
            (ROWS&(ROWS-1))==0 && TILE_K%ROWS==0 && GROUP_SIZE%ROWS==0) begin
            if(m==1) factor=ROWS;
            else if(MULTIROW_FOLD)
                while(factor<ROWS && active_rows*(factor*2)<=ROWS) factor*=2;
        end
        return factor;
    endfunction
    function automatic bit reference_fold(input integer active_rows);
        return reference_factor(active_rows)>1 || (GEMV_FOLD && SYSTOLIC && A_REUSE && m==1 &&
            ROWS<=BUS_BYTES && ROWS<=2*W_BYTES && (ROWS&(ROWS-1))==0 && TILE_K%ROWS==0 && GROUP_SIZE%ROWS==0);
    endfunction
    task automatic require(input bit condition,input string message);
        checks++;
        if(!condition) $fatal(1,"W4A8_WAVE_CHECK_FAILED: %s time=%0t",message,$time);
    endtask
    always @(negedge clk) begin
        if(!rst) begin
            array_pause=force_array_stall || (mode==2 && ticks%13<3);
            load_pause=force_load_stall || (mode==2 && ticks%11<3);
            post_pause=force_post_stall || (mode==2 && ticks%17<4);
            out_ready=!force_output_stall && (mode!=2 || ticks%7>=2);
        end
    end
    always @(posedge clk) begin
        ticks++;
        if(A_REUSE) begin
            if(rst || (start && start_ready) || (busy && cache_epoch!=dut.mt)) begin
                for(integer r=0;r<ROWS;r++)
                    for(integer a=0;a<CACHE_DEPTH;a++) cache_valid[r][a]=0;
                if(busy && cache_epoch!=dut.mt) cache_switches++;
                cache_epoch=dut.mt;
            end
            if(dut.accept_input && dut.phase==dut.ACTIVATIONS) begin
                require(dut.bank_n[dut.load_bank]==0 && dut.bank_m[dut.load_bank]==dut.mt,"cache writes only first N tile in owned M epoch");
                require(dut.cache_wr_addr<CACHE_DEPTH,"cache write address in range");
                require(!cache_valid[dut.load_lane][dut.cache_wr_addr],"cache word loaded exactly once per epoch");
                if(dut.state==dut.RUN) begin
                    for(integer r=0;r<ROWS;r++) if(r<dut.cm_len)
                        require(dut.av[r]==$signed(memory.a[(dut.mt+r)*k+dut.ck+dut.run_k][7:0]),"per-cycle activation matches global matrix");
                end
                if(dut.read_tile) require(dut.cache_rd_addr!=dut.cache_wr_addr,"no cache same-address read/write collision");
                cache_valid[dut.load_lane][dut.cache_wr_addr]=1;cache_writes++;
            end
            if(dut.read_tile) begin
                require(dut.cache_rd_addr<CACHE_DEPTH,"cache read address in range");
                for(integer r=0;r<ROWS;r++) if(r<dut.cm_len) begin
                    require(cache_valid[r][dut.cache_rd_addr],"cache read initialized word in current M epoch");
                    if(dut.nt!=0) cache_hits++;
                end
            end
            if(req_valid && req_ready) begin
                require(req_m==dut.mt,"producer cannot overwrite next M epoch early");
                require(req_activation==(req_n==0),"A present only in first N request");
            end
        end
        if(rst) begin last_released=-1;held_array=0;held_out=0;held_in=0;held_req=0;held_post=0;end
        else begin
            if(held_out) require(out_valid && out_payload===old_out,"output stable during backpressure");
            if(held_in) begin require(in_valid && {in_keep,in_data}===old_in,"input byte stable during load pause");held_input_checks++;end
            if(held_req) require(req_valid && req_payload===old_req,"request stable during backpressure");
            held_out=out_valid && !out_ready;old_out=out_payload;
            held_in=in_valid && !in_ready;old_in={in_keep,in_data};
            held_req=req_valid && !req_ready;old_req=req_payload;
            if(busy && checking) begin
                elapsed++;
                if(SYSTOLIC && GROUP_STREAM && dut.state==dut.RUN && dut.array_step &&
                    dut.run_k+dut.k_step>=dut.clen && dut.ck+dut.clen<k && (dut.ck+dut.clen)%GROUP_SIZE!=0)
                    last_released=dut.consumer_bank;
                if(SYSTOLIC && GROUP_STREAM && dut.group_open && (dut.state==dut.WAIT_TILE || dut.state==dut.PRIME)) begin
                    require(!dut.array_step && !dut.mac_count,"tile seam freezes wave and MAC");
                    seam_hold_checks++;
                    if(dut.accept_input && dut.phase==dut.WEIGHTS && dut.load_bank==last_released) reclaimed_writes++;
                end
                if(dut.array_step) begin
                    counted_array_cycles++;
                    counted_macs+=$countones(dut.mac_fire);
                    if(dut.mac_count!=0) counted_active++;
                    if(dut.state==dut.DRAIN) counted_drain++;
                end
                if(array_pause && (dut.state==dut.RUN || dut.state==dut.DRAIN)) counted_pause++;
                if(dut.state==dut.DRAIN) begin
                    require(!dut.read_tile && dut.bank_state[dut.consumer_bank]==dut.COMPUTING,"drain holds operand bank without RAM requests");
                    drain_checks++;
                end
                if(held_array) begin
                    require(array_cycles==previous_advance_counters[0] && valid_macs==previous_advance_counters[1] &&
                        array_drain_cycles==previous_advance_counters[2] && compute_cycles==previous_advance_counters[3] &&
                        array_mac_cycles==previous_advance_counters[4],"paused array counters hold");
                    held_array_checks++;
                end
                held_array=array_pause && (dut.state==dut.RUN || dut.state==dut.DRAIN);
                previous_advance_counters[0]=array_cycles;previous_advance_counters[1]=valid_macs;
                previous_advance_counters[2]=array_drain_cycles;previous_advance_counters[3]=compute_cycles;
                previous_advance_counters[4]=array_mac_cycles;
                if(req_valid && req_ready && req_k[0]) odd_k_requests++;
                if(in_valid && in_ready) begin
                    integer remaining;
                    require(dut.bank_state[dut.load_bank]==1,"loader owns LOADING bank");
                    case(dut.phase)
                        0:remaining=dut.bank_wbytes[dut.load_bank]-dut.load_pos;
                        1:remaining=dut.bank_kl[dut.load_bank]-dut.load_pos;
                        2:remaining=2*dut.bank_ml[dut.load_bank]-dut.load_pos;
                        3:remaining=2*dut.bank_nl[dut.load_bank]-dut.load_pos;
                    endcase
                    for(integer j=0;j<BUS_BYTES;j++)
                        if(dut.phase==0)
                            require(in_keep[j]==(j%W_BYTES<remaining && dut.load_lane+j/W_BYTES<dut.bank_nl[dut.load_bank]),"weight slot keep mask");
                        else require(in_keep[j]==(j<remaining),"nonweight keep mask");
                    if(dut.phase==0) begin
                        integer writes;
                        writes=$countones(dut.w_write);
                        require(writes==((dut.bank_nl[dut.load_bank]-dut.load_lane<W_LANES)?
                            dut.bank_nl[dut.load_bank]-dut.load_lane:W_LANES),"one write per valid weight bank");
                        if(writes==2) dual_writes++;
                        if(in_keep!=((1<<$countones(in_keep))-1)) holey_keeps++;
                    end
                end
                require(!(dut.p_issue && dut.state==dut.OUT_REQ),"output RAM single read owner");
                require(!(dut.p_retire && dut.state==dut.INIT_Y),"output RAM single write owner");
                if(held_post) begin require(pipe_payload===previous_pipe,"pipeline data stable while paused");held_pipe_checks++;end
                held_post=post_pause;previous_pipe=pipe_payload;
                if(post_pause) require(!dut.p_issue && !dut.p_retire,"paused pipeline has no RAM transactions");
                if(dut.psum_write) require(dut.psum_state[dut.psum_prod]==dut.P_WRITING,"psum producer owns writing bank");
                if(dut.p_issue) begin
                    require(dut.psum_state[dut.psum_cons]==dut.P_SCALING,"post consumer owns scaling bank");
                    require(dut.psum_m[dut.psum_cons]==dut.mt && dut.psum_n[dut.psum_cons]==dut.nt,"post output tile tag");
                end
                if(dut.p_retire) for(integer lane=0;lane<POST_LANES;lane++) if(dut.mask1[lane]) begin
                    integer row,col,g,index;
                    row=dut.psum_m[dut.psum_cons]+dut.tags1[lane]/COLS;
                    col=dut.psum_n[dut.psum_cons]+dut.tags1[lane]%COLS;
                    g=dut.psum_group[dut.psum_cons];
                    if(row<m && col<n) begin
                        index=(row*ng+g)*n+col;
                        require(dut.scaled_lanes[lane]==$signed(psum_golden[index])*
                            $signed({1'b0,memory.sx[row*ng+g][15:0]})*
                            $signed({1'b0,memory.sw[g*n+col][15:0]}),"each post lane matches exact group reference");
                        scaled_checks++;
                    end else require(dut.scaled_lanes[lane]==0,"invalid post lane scales to zero");
                end
                if(dut.state==dut.WAIT_PSUM && dut.psum_state[dut.psum_prod]!=dut.P_FREE) full_queue_checks++;
                if(dut.read_tile) require(dut.bank_state[dut.consumer_bank]==3,"consumer owns COMPUTING bank");
                for(integer b=0;b<(DOUBLE_BUFFER?2:1);b++) begin
                    if(dut.bank_state[b]==2 && dut.bank_state[dut.consumer_bank]==3 && b!=dut.consumer_bank) ready_overlap=1;
                end
                if(dut.psum_write) for(integer column=0;column<COLS;column++)
                    if(column>=dut.slot%COLS && column<dut.slot%COLS+COPY_LANES && dut.slot/COLS<dut.cm_len && column<dut.cn_len) begin
                        integer row,col,index;
                        row=dut.mt+dut.slot/COLS;col=dut.nt+column;
                        index=(row*ng+dut.ck/GROUP_SIZE)*n+col;
                        require(dut.acc[(dut.slot/COLS)*COLS+column]===psum_golden[index],"every parallel snapshot lane matches exact group psum");
                        groups_checked++;psum_comparisons++;
                    end
                if(out_valid && out_ready) begin
                    integer index;
                    require(out_m<m && out_n<n,"valid output coordinates");
                    index=out_m*n+out_n;
                    require(!seen[index],"output exactly once");
                    require(out_data===golden[index],"bit-exact Q16.16 output");
                    require(out_last==(out_m==m-1 && out_n==n-1),"last flag");
                    seen[index]=1;outputs++;comparisons++;
                end
            end
        end
    end
    if(SYSTOLIC) begin: forwarding_monitor
        for(genvar r=0;r<ROWS;r++) begin: row
            for(genvar c=0;c<COLS;c++) begin: col
                logic hold_seen=0;
                logic [49:0] last_payload;
                wire [49:0] payload={
                    dut.systolic_core.array_core.a_path[r][c+1],
                    dut.systolic_core.array_core.b_path[r+1][c],
                    dut.systolic_core.array_core.a_vpath[r][c+1],
                    dut.systolic_core.array_core.b_vpath[r+1][c],dut.pe_acc[r*COLS+c]};
                always @(posedge clk) begin
                    if(rst) hold_seen=0;
                    else begin
                        if(hold_seen) require(payload===last_payload,"PE forwarding and sum hold during array pause");
                        hold_seen=busy && !dut.array_step && dut.state!=dut.CLEAR_PE;
                        last_payload=payload;
                    end
                end
            end
        end
    end
    // Independent math stream: every advance has a history position; wall-clock
    // WAIT_TILE/PRIME/pause cycles do not consume positions.
    if(SYSTOLIC) begin: mathematical_wave_reference
        integer ha[0:8191][0:ROWS-1],hb[0:8191][0:COLS-1];
        bit hv[0:8191];
        integer hml[0:8191],hnl[0:8191],expected_acc[0:ROWS*COLS-1];
        integer step=0,injected=0,group_origin=0;
        bit active=0;
        always @(posedge clk) begin
            bit compare_now;
            compare_now=0;
            if(rst || (start && start_ready)) begin
                step=0;injected=0;active=0;
                for(integer p=0;p<ROWS*COLS;p++) expected_acc[p]=0;
            end else if(dut.state==dut.CLEAR_PE) begin
                step=0;injected=0;active=1;group_origin=dut.ck;
                for(integer p=0;p<ROWS*COLS;p++) expected_acc[p]=0;
            end else if(active && busy && dut.array_step) begin
                require(dut.folded==reference_fold(dut.cm_len),"mapping selected from public shape");
                if(reference_fold(dut.cm_len) || BROADCAST_MAC || PACKED_MAC) begin
                    for(integer r=0;r<ROWS;r++) for(integer c=0;c<COLS;c++) begin
                        integer q,code,row;bit fire;
                        q=dut.ck+dut.run_k+(reference_fold(dut.cm_len)?r%reference_factor(dut.cm_len):0);
                        row=dut.mt+(reference_fold(dut.cm_len)?r/reference_factor(dut.cm_len):r);
                        fire=dut.state==dut.RUN && row<m && c<dut.cn_len && q<dut.ck+dut.clen;
                        require(dut.mac_fire[r*COLS+c]===fire,"broadcast/folded valid term mask");
                        if(fire) begin
                            code=memory.packed_w[(dut.nt+c)*((k+1)/2)+q/2];code=(code>>((q%2)*4))&15;if(code>=8)code-=16;
                            expected_acc[r*COLS+c]+=memory.a[row*k+q]*code;
                        end
                    end
                    if(dut.state==dut.RUN) injected+=(dut.clen-dut.run_k<dut.k_step)?dut.clen-dut.run_k:dut.k_step;
                end else begin
                require(step<8192,"mathematical wave history capacity");
                hv[step]=dut.state==dut.RUN;hml[step]=dut.cm_len;hnl[step]=dut.cn_len;
                for(integer r=0;r<ROWS;r++)
                    ha[step][r]=(hv[step] && r<dut.cm_len)?memory.a[(dut.mt+r)*k+dut.ck+dut.run_k]:0;
                for(integer c=0;c<COLS;c++) begin
                    integer code;
                    code=0;
                    if(hv[step] && c<dut.cn_len) begin
                        code=memory.packed_w[(dut.nt+c)*((k+1)/2)+(dut.ck+dut.run_k)/2];
                        code=(code>>(((dut.ck+dut.run_k)%2)*4))&15;
                        if(code>=8) code-=16;
                    end
                    hb[step][c]=code;
                end
                for(integer r=0;r<ROWS;r++) for(integer c=0;c<COLS;c++) begin
                    integer index;bit fire;
                    index=step-r-c;fire=0;
                    if(index>=0) fire=hv[index] && r<hml[index] && c<hnl[index];
                    require(dut.mac_fire[r*COLS+c]===fire,"per-PE K history valid alignment across tile seam");
                    if(fire) expected_acc[r*COLS+c]+=ha[index][r]*hb[index][c];
                end
                if(hv[step]) injected++;
                end
                step++;
            end
            if(active && busy && dut.state==dut.WAIT_PSUM) begin
                integer length;
                length=(k-group_origin<GROUP_SIZE)?k-group_origin:GROUP_SIZE;
                require(injected==length,"group contains exactly its valid K elements");
                if(GROUP_STREAM) begin
                    integer delay,steps;
                    delay=(dut.folded || BROADCAST_MAC || PACKED_MAC)?0:(EFFECTIVE_DRAIN?dut.cm_len+dut.cn_len-2:ROWS+COLS-2);
                    steps=dut.folded?(length+reference_factor(dut.cm_len)-1)/reference_factor(dut.cm_len):length;
                    require(step==steps+delay,"exact injection and effective drain count per group");
                end
            end
            compare_now=active && busy;
            #1;
            if(compare_now) for(integer p=0;p<ROWS*COLS;p++) begin
                integer sum;
                require(dut.pe_acc[p]===expected_acc[p],"physical PE sum matches independent mathematical stream");
                sum=0;
                if(reference_fold(dut.cm_len) && p/COLS<ROWS/reference_factor(dut.cm_len))
                    for(integer lane=0;lane<reference_factor(dut.cm_len);lane++)
                        sum+=expected_acc[((p/COLS)*reference_factor(dut.cm_len)+lane)*COLS+p%COLS];
                require(dut.acc[p]===(reference_fold(dut.cm_len)?sum:expected_acc[p]),"logical group sum matches independent reduction");
                shadow_checks++;
            end
        end
    end
    task automatic reset_device;
        @(negedge clk);rst=1;start=0;checking=0;held_array=0;array_pause=0;force_array_stall=0;force_load_stall=0;last_released=-1;force_output_stall=0;force_post_stall=0;post_pause=0;
        repeat(3) @(posedge clk);
        #1;require(!busy && !out_valid && !in_ready,"reset aborts work and pending output");
        @(negedge clk);rst=0;
    endtask
    task automatic launch;
        @(negedge clk);cfg_m=m;cfg_n=n;cfg_k=k;start=1;
        #1;require(start_ready,"start ready");
        @(posedge clk);#1;require(busy,"task accepted");
        @(negedge clk);start=0;
    endtask
    task automatic expected_traffic;
        ew=0;ea=0;es=0;et=0;eb=0;ep=0;ec=0;ed=0;epi=0;
        for(mt=0;mt<m;mt+=ROWS) begin
            ml=(m-mt<ROWS)?m-mt:ROWS;
            for(nt=0;nt<n;nt+=COLS) begin
                nl=(n-nt<COLS)?n-nt:COLS;q=0;
                epi+=ng*(COMPACT_SLOTS?ml*((nl+POST_LANES-1)/POST_LANES):ROWS*((COLS+POST_LANES-1)/POST_LANES));
                while(q<k) begin
                    len=TILE_K;
                    if(k-q<len) len=k-q;
                    if(GROUP_SIZE-q%GROUP_SIZE<len) len=GROUP_SIZE-q%GROUP_SIZE;
                    wb=(q%2+len+1)/2;
                    begin
                        integer stride;bit fold;
                        fold=reference_fold(ml);
                        stride=reference_factor(ml);ec+=(len+stride-1)/stride;
                        if(SYSTOLIC && !fold && !BROADCAST_MAC && !PACKED_MAC &&
                            (!GROUP_STREAM || q+len==k || (q+len)%GROUP_SIZE==0)) ed+=EFFECTIVE_DRAIN?ml+nl-2:ROWS+COLS-2;
                    end
                    ew+=nl*wb;if(!A_REUSE || nt==0) ea+=ml*len;et++;
                    eb+=((nl+W_LANES-1)/W_LANES)*((wb+W_BYTES-1)/W_BYTES)+((!A_REUSE || nt==0)?ml*((len+BUS_BYTES-1)/BUS_BYTES):0);
                    if(!SCALE_ONCE || q+len==k || (q+len)%GROUP_SIZE==0) begin
                        es+=2*(ml+nl);
                        eb+=(2*ml+BUS_BYTES-1)/BUS_BYTES+(2*nl+BUS_BYTES-1)/BUS_BYTES;
                    end
                    q+=len;
                end
            end
        end
        ep=eb*BUS_BYTES-ew-ea-es;
        em=m*n*k;
    endtask
    task automatic run_job(input integer case_id,feed_mode,input bit recovery);
        integer timeout_count;
        mode=feed_mode;elapsed=0;outputs=0;groups_checked=0;counted_macs=0;counted_array_cycles=0;counted_drain=0;counted_pause=0;counted_active=0;held_array=0;
        for(integer i=0;i<m*n;i++) seen[i]=0;
        launch();checking=1;
        // A busy start is rejected even if the caller changes configuration.
        @(negedge clk);start=1;cfg_m=0;cfg_n=0;cfg_k=0;
        #1;require(!start_ready,"busy refuses new start");
        @(posedge clk);#1;require(!error,"busy command did not change task");
        @(negedge clk);start=0;cfg_m=m;cfg_n=n;cfg_k=k;
        timeout_count=0;
        if(seam_job) begin
            while(!(dut.state==dut.WAIT_TILE && dut.group_open && dut.ck%GROUP_SIZE!=0 &&
                dut.bank_state[dut.consumer_bank]!=dut.READY)) begin
                @(negedge clk);timeout_count++;
                require(timeout_count<10000,"input-starved live seam reached");
            end
            force_load_stall=1;load_pause=1;
            repeat(20) @(negedge clk);
            force_load_stall=0;seam_resumes++;
        end
        if(pressure_job) begin
            if(POST_OVERLAP) begin
                while(!(dut.state==dut.WAIT_PSUM && dut.psum_state[dut.psum_prod]!=dut.P_FREE)) begin
                    @(negedge clk);timeout_count++;
                    require(timeout_count<10000,"queue pressure reached full");
                end
                require(dut.psum_state[0]!=dut.P_FREE && dut.psum_state[1]!=dut.P_FREE,"both psum banks occupied");
                repeat(20) @(negedge clk);
            end else begin
                wait(dut.state==dut.WAIT_POST);
                repeat(20) @(negedge clk);
            end
            force_post_stall=0;
        end
        while(!done) begin
            @(negedge clk);timeout_count++;
            require(timeout_count<4000000,"per-task timeout");
            require(!error,"no unexpected core error");
        end
        checking=0;expected_traffic();
        require(outputs==m*n && groups_checked==m*n*ng,"all outputs and groups checked");
        require(total_cycles==elapsed,"total cycle counter");
        require(weight_bytes==ew && activation_bytes==ea && scale_bytes==es,"accepted byte counters");
        require(array_cycles==counted_array_cycles && array_drain_cycles==counted_drain &&
            array_pause_cycles==counted_pause && array_mac_cycles==counted_active && valid_macs==counted_macs,"actual wavefront MAC and cycle counters");
        require(array_drain_cycles==ed && array_cycles==compute_cycles+array_drain_cycles,"independent vector/matrix advance budget");
        require(tile_handoffs==((SYSTOLIC && GROUP_STREAM)?et-((m+ROWS-1)/ROWS)*((n+COLS-1)/COLS)*ng:0),"group handoff count");
        require(wave_input_wait_cycles<=input_wait_cycles && wave_input_wait_cycles<=wave_hold_cycles,"wave hold is a subset of input/fixed cycles");
        require(valid_macs==em && compute_cycles==ec,"valid MAC and compute counters");
        require(memory.requests==et && memory.accepted==ew+ea+es,"memory packet totals");
        require(input_beats==eb && memory.beats==eb && padding_bytes==ep,"physical beat and padding counters");
        require(psum_groups==((m+ROWS-1)/ROWS)*((n+COLS-1)/COLS)*ng &&
                post_issue_cycles==epi && post_retire_cycles==post_issue_cycles &&
                dut.post_issue_elements==(COMPACT_SLOTS?m*n*ng:psum_groups*ROWS*COLS) && dut.post_retire_elements==dut.post_issue_elements,"all group elements scaled exactly once across post lanes");
        if(!POST_OVERLAP) require(compute_post_overlap_cycles==0,"serial compute and post do not overlap");
        require(array_cycles+array_pause_cycles+input_wait_cycles+output_wait_cycles+psum_wait_cycles+post_drain_cycles<=total_cycles,"exclusive critical-path classifications");
        if(!DOUBLE_BUFFER) require(overlap_cycles==0,"single bank cannot load during compute");
        all_overlap+=overlap_cycles;all_input_wait+=input_wait_cycles;all_output_wait+=output_wait_cycles;
        $fdisplay(report,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
            case_id,recovery,mode,ROWS,COLS,TILE_K,GROUP_SIZE,DOUBLE_BUFFER,m,n,k,
            total_cycles,weight_bytes,activation_bytes,scale_bytes,valid_macs,compute_cycles,
            input_wait_cycles,output_wait_cycles,overlap_cycles,BUS_BYTES,SCALE_ONCE,input_beats,padding_bytes,PACK_COLS,POST_OVERLAP,POST_PIPELINE,psum_wait_cycles,post_drain_cycles,
            post_active_cycles,post_issue_cycles,post_retire_cycles,compute_post_overlap_cycles,psum_groups,A_REUSE,SYSTOLIC,array_cycles,array_drain_cycles,array_pause_cycles,array_mac_cycles,GROUP_STREAM,tile_handoffs,wave_hold_cycles,wave_input_wait_cycles);
        $display("W4A8_WAVE_CASE_PASS id=%0d recovery=%0d mode=%0d dims=%0dx%0dx%0d cycles=%0d mac=%0d overlap=%0d",
            case_id,recovery,mode,m,n,k,total_cycles,valid_macs,overlap_cycles);
        tasks++;
    endtask
    initial begin
        report=$fopen("results.csv","w");require(report!=0,"report opened");
        $fdisplay(report,"case_id,recovery,mode,ROWS,COLS,TILE_K,GROUP_SIZE,DOUBLE_BUFFER,M,N,K,total_cycles,weight_bytes,activation_bytes,scale_bytes,valid_macs,compute_cycles,input_wait_cycles,output_wait_cycles,overlap_cycles,BUS_BYTES,SCALE_ONCE,input_beats,padding_bytes,PACK_COLS,POST_OVERLAP,POST_PIPELINE,psum_wait_cycles,post_drain_cycles,post_active_cycles,post_issue_cycles,post_retire_cycles,compute_post_overlap_cycles,psum_groups,A_REUSE,SYSTOLIC,array_cycles,array_drain_cycles,array_pause_cycles,array_mac_cycles,GROUP_STREAM,tile_handoffs,wave_hold_cycles,wave_input_wait_cycles");
        for(integer code=0;code<16;code++) begin
            unpack_byte=(code<<4)|code;
            unpack_high=0;#1;require(unpack_value==((code<8)?code:code-16),"all low nibble signed codes");
            unpack_high=1;#1;require(unpack_value==((code<8)?code:code-16),"all high nibble signed codes");
        end
        reset_device();
        @(negedge clk);start=1;cfg_m=0;cfg_n=1;cfg_k=1;
        @(posedge clk);#1;require(error && !busy,"invalid dimensions rejected");
        @(negedge clk);start=0;
        f=$fopen("vectors.txt","r");require(f!=0,"vectors opened");
        rc=$fscanf(f,"%d",cases);require(rc==1 && cases>=15,"case header");
        for(integer job=0;job<cases;job++) begin
            rc=$fscanf(f,"%d %d %d %d %d",cid,m,n,k,ng);require(rc==5,"dimensions parsed");
            require(ng==(k+GROUP_SIZE-1)/GROUP_SIZE,"group count");
            for(x=0;x<m*k;x++) begin rc=$fscanf(f,"%d",memory.a[x]);require(rc==1,"activation vector");end
            for(x=0;x<n*((k+1)/2);x++) begin rc=$fscanf(f,"%d",memory.packed_w[x]);require(rc==1,"packed weights");end
            for(x=0;x<m*ng;x++) begin rc=$fscanf(f,"%d",memory.sx[x]);require(rc==1,"activation scales");end
            for(x=0;x<ng*n;x++) begin rc=$fscanf(f,"%d",memory.sw[x]);require(rc==1,"weight scales");end
            for(x=0;x<m*n;x++) begin rc=$fscanf(f,"%d",golden[x]);require(rc==1,"output golden");end
            for(x=0;x<m*ng*n;x++) begin rc=$fscanf(f,"%d",psum_golden[x]);require(rc==1,"psum golden");end
            for(md=0;md<((cid>=15)?1:MODES);md++) run_job(cid,md,0);
        if(MODES>1 && cid==10) begin
            directed_reset_cases++;
            // Random dataset; abort concurrently loading and computing.
            mode=2;launch();
            wait(dut.state==dut.RUN && (dut.loading || !DOUBLE_BUFFER));reset_device();
            run_job(cid,2,1);
            force_output_stall=1;mode=0;launch();wait(out_valid);
            repeat(5) @(negedge clk);reset_device();
            run_job(cid,0,1);
            // Fill both psum banks while post is frozen, then resume without reset.
            force_post_stall=1;pressure_job=1;run_job(cid,0,1);pressure_job=0;
            // Reset with a nonempty scale pipeline and a retained group snapshot.
            mode=0;launch();wait(dut.v0 || dut.v1);
            @(negedge clk);force_post_stall=1;
            repeat(4) @(negedge clk);reset_device();extra_post_resets++;
            run_job(cid,0,1);
            if(SYSTOLIC && ROWS+COLS>2 && !BROADCAST_MAC && !PACKED_MAC && !dut.folded) begin
                expected_drain_resets++;
                mode=0;launch();wait(dut.state==dut.DRAIN);
                @(negedge clk);force_array_stall=1;array_pause=1;
                repeat(4) @(posedge clk);
                reset_device();extra_array_resets++;
                run_job(cid,0,1);
                if(GROUP_STREAM && TILE_K<GROUP_SIZE) begin
                    seam_job=1;run_job(cid,1,1);seam_job=0;
                    mode=1;launch();
                    wait(dut.state==dut.WAIT_TILE && dut.group_open && dut.ck%GROUP_SIZE!=0 &&
                        dut.bank_state[dut.consumer_bank]!=dut.READY);
                    @(negedge clk);force_load_stall=1;load_pause=1;
                    repeat(8) @(negedge clk);
                    reset_device();seam_resets++;
                    run_job(cid,0,1);
                end
            end
        end
        end
        $fclose(f);
        if(MODES>1) begin
            require(all_input_wait>0 && all_output_wait>0 && held_input_checks>0,"input delays/pause/output backpressure covered");
            if(DOUBLE_BUFFER) require(all_overlap>0 && ready_overlap,"load/compute overlap and ready bank covered");
        end
        if(MODES>1) begin
            require(held_pipe_checks>0 && extra_post_resets==directed_reset_cases && directed_reset_cases>0,"pipeline pause and in-flight reset covered");
            if(POST_OVERLAP) require(full_queue_checks>0,"psum full backpressure covered");
        end
        if(A_REUSE) require(cache_hits>0 && cache_writes>0 && cache_switches>0,"cache reuse/loading/epoch transitions covered");
        if(MODES>1) require(held_array_checks>0,"array pause covered");
        if(SYSTOLIC && ROWS+COLS>2 && !BROADCAST_MAC && !PACKED_MAC) begin
            require(drain_checks>0,"wave drain covered");
            if(MODES>1) require(extra_array_resets==expected_drain_resets,"reset while wave drain paused covered");
        end
        if(SYSTOLIC) require(shadow_checks>0,"per-PE stream history checked");
        if(GROUP_STREAM && TILE_K<GROUP_SIZE && ROWS+COLS>2) begin
            require(seam_hold_checks>0 && reclaimed_writes>0,"live wave hold and freed-bank overwrite covered");
            if(MODES>1) require(seam_resets==expected_drain_resets && seam_resumes==expected_drain_resets,"seam starvation resume and reset covered");
        end
        $fclose(report);
        if(PACK_COLS && COLS>1 && BUS_BYTES==8) require(dual_writes>0 && holey_keeps>0,"paired writes and noncontiguous keeps covered");
        if(TILE_K%2 || GROUP_SIZE%2) require(odd_k_requests>0,"odd K starts covered");
        $display("W4A8_WAVE_TESTS_PASS rows=%0d cols=%0d tile=%0d group=%0d db=%0d tasks=%0d outputs=%0d psums=%0d checks=%0d overlap=%0d held_inputs=%0d bytes=%0d scale_once=%0d pack=%0d dual_writes=%0d holey_keeps=%0d odd_k=%0d post_overlap=%0d pipeline=%0d scaled=%0d full_queue=%0d held_pipe=%0d post_resets=%0d a_reuse=%0d cache_hits=%0d cache_writes=%0d cache_switches=%0d systolic=%0d held_array=%0d drain_checks=%0d array_resets=%0d group_stream=%0d shadow_checks=%0d seam_holds=%0d reclaimed_writes=%0d seam_resets=%0d seam_resumes=%0d",
            ROWS,COLS,TILE_K,GROUP_SIZE,DOUBLE_BUFFER,tasks,comparisons,psum_comparisons,checks,all_overlap,held_input_checks,BUS_BYTES,SCALE_ONCE,PACK_COLS,dual_writes,holey_keeps,odd_k_requests,POST_OVERLAP,POST_PIPELINE,scaled_checks,full_queue_checks,held_pipe_checks,extra_post_resets,A_REUSE,cache_hits,cache_writes,cache_switches,SYSTOLIC,held_array_checks,drain_checks,extra_array_resets,GROUP_STREAM,shadow_checks,seam_hold_checks,reclaimed_writes,seam_resets,seam_resumes);
        $finish;
    end
    initial begin #20000000;$fatal(1,"W4A8_WAVE_GLOBAL_TIMEOUT");end
endmodule
module tb_w4a8_wave_directed;tb_w4a8_wave #(.MODES(1)) test();endmodule
module tb_w4a8_wave8;tb_w4a8_wave #(.ROWS(8),.COLS(8)) test();endmodule
module tb_w4a8_wave_tile4;tb_w4a8_wave #(.GROUP_STREAM(0)) test();endmodule
module tb_w4a8_wave_tile8;tb_w4a8_wave #(.ROWS(8),.COLS(8),.GROUP_STREAM(0)) test();endmodule
module tb_w4a8_wave_alt;tb_w4a8_wave #(.ROWS(2),.COLS(3),.TILE_K(5),.GROUP_SIZE(12)) test();endmodule
module tb_w4a8_wave_words8;tb_w4a8_wave #(.ROWS(8),.COLS(8),.TILE_K(19)) test();endmodule
module tb_w4a8_wave_single;tb_w4a8_wave #(.DOUBLE_BUFFER(0)) test();endmodule
module tb_w4a8_wave_one;tb_w4a8_wave #(.ROWS(1),.COLS(1)) test();endmodule
