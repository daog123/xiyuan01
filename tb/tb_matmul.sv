`timescale 1ns/1ps
module tb_matmul;
    parameter integer ROWS=4, COLS=4, TILE_K=8;
    parameter bit OPTIMIZED=1, DOUBLE_BUFFER=1;
    parameter integer B_LOAD_GAP=0;
    localparam bit USE_DB=OPTIMIZED && DOUBLE_BUFFER;
    localparam integer MAX_M=16, MAX_N=16, MAX_K=32;
    logic clk=0;
    always #5 clk=~clk;
    logic rst=1,pause=0,wr_valid=0,wr_matrix=0,start=0,rd_req=0;
    logic wr_ready,start_ready,busy,done,error,result_available,rd_ready,rd_valid;
    logic [15:0] wr_row=0,wr_col=0,cfg_m=0,cfg_n=0,cfg_k=0,rd_row=0,rd_col=0;
    logic signed [7:0] wr_data=0;
    wire signed [31:0] rd_data;
    logic [31:0] cycle_count,active_cycles;
    matmul_top #(.ROWS(ROWS),.COLS(COLS),.TILE_K(TILE_K),.OPTIMIZED(OPTIMIZED),.DOUBLE_BUFFER(DOUBLE_BUFFER),.B_LOAD_GAP(B_LOAD_GAP)) dut (.*);

    logic pe_rst=1,pe_load=0,pe_en=0;
    logic signed [31:0] pe_seed=0;
    logic signed [7:0] pe_a=0,pe_b=0;
    wire signed [31:0] pe_acc;
    mac_pe pe_check (.clk(clk),.rst(pe_rst),.load(pe_load),.seed(pe_seed),
                     .en(pe_en),.a(pe_a),.b(pe_b),.acc(pe_acc));
    integer a [0:MAX_M*MAX_K-1];
    integer b [0:MAX_K*MAX_N-1];
    integer golden [0:MAX_M*MAX_N-1];
    integer f,pf,report,rc,cases,cid,m,n,k,x,r,c,pcases,ps,pa,pb,expected;
    integer comparisons=0,checks=0,done_pulses=0,elapsed,stalls,expected_active;
    integer seed_dummy;
    integer a_reads=0,b_reads=0,p_writes=0;
    bit [10:0] paused_states=0;
    integer wait_cycles=0,overlap_cycles=0,takes=0,releases=0;
    integer total_overlap=0,total_wait=0;
    bit paused_loader=0,paused_overlap=0,ready_a_overlap=0,ready_compute_overlap=0;
    bit reset_overlap=0,db_abort_request=0,db_abort_finished=0;

    task automatic require(input bit condition,input string message);
        if (!condition) $fatal(1,"CHECK_FAILED: %s time=%0t",message,$time);
        checks=checks+1;
    endtask

    task automatic reset_dut;
        @(negedge clk); rst=1; pause=0; start=0; wr_valid=0; rd_req=0;
        repeat (3) @(posedge clk);
        #1;
        require(!busy && !done && !error && !rd_valid && !result_available,"reset status");
        @(negedge clk); rst=0;
    endtask

    task automatic write_element(input bit matrix_id,input integer row_id,col_id,value);
        @(negedge clk);
        wr_valid=1; wr_matrix=matrix_id; wr_row=row_id; wr_col=col_id; wr_data=value;
        #1; require(wr_ready,"input write accepted");
        @(posedge clk); #1;
        @(negedge clk); wr_valid=0;
    endtask

    task automatic launch(input integer mm,nn,kk);
        @(negedge clk); cfg_m=mm; cfg_n=nn; cfg_k=kk; start=1;
        #1; require(start_ready,"start accepted");
        @(posedge clk); #1; require(busy && !result_available,"running status");
        @(negedge clk); start=0;
    endtask

    function automatic integer db_output_cycles(input integer kk,input bit with_a);
        integer prev_release,prev_fill,claim,fill,take_time,release_time,index,len,q;
        integer release_times [0:MAX_K-1];
        prev_release=1+(with_a?(ROWS*kk+1):0);prev_fill=0;index=0;
        for(q=0;q<kk;q=q+TILE_K) begin
            len=((kk-q)<TILE_K)?kk-q:TILE_K;
            claim=(index==0)?2:prev_fill+B_LOAD_GAP+1;
            if(index>=2 && release_times[index-2]+1>claim) claim=release_times[index-2]+1;
            fill=claim+COLS*len*(B_LOAD_GAP+1);
            take_time=(prev_release>fill)?prev_release+1:fill+1;
            release_time=take_time+len+2+((q+TILE_K>=kk)?ROWS*COLS:0);
            release_times[index]=release_time;prev_release=release_time;prev_fill=fill;index=index+1;
        end
        return prev_release;
    endfunction

    function automatic integer active_formula(input integer mm,nn,kk);
        integer ot,ktc;
        ot=((mm+ROWS-1)/ROWS)*((nn+COLS-1)/COLS);
        ktc=(kk+TILE_K-1)/TILE_K;
        if(USE_DB) return ((mm+ROWS-1)/ROWS)*(db_output_cycles(kk,1)+
            (((nn+COLS-1)/COLS)-1)*db_output_cycles(kk,0));
        if (OPTIMIZED) return ((mm+ROWS-1)/ROWS)*(ROWS*kk+1) +
            ot*(1+COLS*kk+3*ktc+kk+ROWS*COLS);
        return ot*(1+ktc*(2*TILE_K*(ROWS+COLS)+ROWS*COLS+2)+kk);
    endfunction

    task automatic wait_complete(input bit use_pause,input integer mm,nn,kk);
        elapsed=0; stalls=0;
        // Already at the first negedge after start, before CLEAR executes.
        while (busy) begin
            pause=use_pause && ((elapsed%17)==3 || (elapsed%17)==4);
            if (pause) stalls=stalls+1;
            // Exercise refusal of load/start/read while busy, with poison data.
            wr_valid=(elapsed%3)==0; start=(elapsed%3)==1; rd_req=(elapsed%3)==2;
            wr_matrix=0; wr_row=0; wr_col=0; wr_data=127; rd_row=0; rd_col=0;
            #1;
            require(!wr_ready && !start_ready && !rd_ready,"busy backpressure");
            @(posedge clk); #1;
            elapsed=elapsed+1;
            require(!error && !rd_valid,"busy commands have no effect");
            if (done) done_pulses=done_pulses+1;
            require(elapsed<100000,"per-task timeout");
            @(negedge clk);
        end
        pause=0; wr_valid=0; start=0; rd_req=0;
        expected_active=active_formula(mm,nn,kk);
        require(result_available && done,"completion status");
        require(a_reads==mm*kk*(OPTIMIZED?1:((nn+COLS-1)/COLS)),"A read/reuse count");
        require(b_reads==((mm+ROWS-1)/ROWS)*kk*nn,"B source read count");
        require(p_writes==mm*nn*(OPTIMIZED?1:((kk+TILE_K-1)/TILE_K)),"result/checkpoint write count");
        if(active_cycles!=expected_active) $display("CYCLE_ERROR expected=%0d actual=%0d",expected_active,active_cycles);
        require(active_cycles==expected_active,"analytic active-cycle count");
        if(USE_DB) begin
            require(takes==((mm+ROWS-1)/ROWS)*((nn+COLS-1)/COLS)*((kk+TILE_K-1)/TILE_K),"DB take count");
            require(releases==takes,"DB release count");
            total_overlap=total_overlap+overlap_cycles;total_wait=total_wait+wait_cycles;
        end
        require(cycle_count==elapsed && cycle_count==active_cycles+stalls,"elapsed/pause cycle count");
        if (use_pause) require(stalls>0,"pause exercised");
        @(posedge clk); #1; require(!done,"done is one-cycle pulse");
        $display("CASE_PASS id=%0d dims=%0dx%0dx%0d array=%0dx%0d TK=%0d OPT=%0d active=%0d elapsed=%0d stalls=%0d Areads=%0d Breads=%0d Pwrites=%0d DB=%0d GAP=%0d wait=%0d overlap=%0d",
                 cid,mm,nn,kk,ROWS,COLS,TILE_K,OPTIMIZED,active_cycles,cycle_count,stalls,a_reads,b_reads,p_writes,USE_DB,B_LOAD_GAP,wait_cycles,overlap_cycles);
        $fdisplay(report,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cid,mm,nn,kk,ROWS,COLS,TILE_K,active_cycles,cycle_count,stalls,OPTIMIZED,a_reads,b_reads,p_writes,USE_DB,B_LOAD_GAP,wait_cycles,overlap_cycles);
    endtask

    task automatic read_and_compare(input integer rr,cc,value);
        @(negedge clk); rd_req=1; rd_row=rr; rd_col=cc;
        #1; require(rd_ready,"result request accepted");
        @(posedge clk); #1;
        require(rd_valid,"synchronous result valid");
        if (rd_data !== value) $fatal(1,"MISMATCH case=%0d C[%0d,%0d] expected=%0d actual=%0d",cid,rr,cc,value,rd_data);
        comparisons=comparisons+1;
        @(negedge clk); rd_req=0;
        @(posedge clk); #1; require(!rd_valid,"result valid cleared");
    endtask

    // White-box safety checks complement external numerical comparisons.
    always @(posedge clk) begin
        if (rst || (start && start_ready)) begin a_reads=0; b_reads=0; p_writes=0;wait_cycles=0;overlap_cycles=0;takes=0;releases=0; end
        if (!rst && busy && pause) paused_states[dut.state]=1;
        if (!rst) begin
        if (dut.a_rd_en) begin
            require(dut.a_rd_addr<MAX_M*MAX_K,"A physical address bounds");
            require(dut.mt+dut.a_read_lane<dut.m && dut.kt+dut.a_read_k<dut.k,"A logical bounds");
            a_reads=a_reads+1;
        end
        if (dut.b_rd_en) begin
            require(dut.b_rd_addr<MAX_K*MAX_N,"B physical address bounds");
            require(dut.nt+dut.b_read_lane<dut.n && dut.b_read_k_abs<dut.k,"B logical bounds");
            b_reads=b_reads+1;
        end
        if (dut.p_wr_en) begin
            require(dut.p_wr_addr<MAX_M*MAX_N,"partial-sum write bounds");
            require(dut.mt+dut.save_lane/COLS<dut.m && dut.nt+dut.save_lane%COLS<dut.n,"partial-sum logical bounds");
            p_writes=p_writes+1;
        end
    end

    end

    generate if(USE_DB) begin: db_checks
        always @(posedge clk) begin
            if(rst) begin
                #1;
                require(dut.g_db.prefetch.bank_state[0]==0 && dut.g_db.prefetch.bank_state[1]==0 &&
                        !dut.g_db.prefetch.loading,"DB reset empties ownership");
            end else if(busy) begin
                if(pause && dut.g_db.prefetch.loading) paused_loader=1;
                if(pause && dut.g_db.prefetch.loading && dut.state==dut.RUN) paused_overlap=1;
                if(dut.g_db.prefetch.ready && (dut.state==dut.A_REQ || dut.state==dut.A_WRITE)) ready_a_overlap=1;
                if(dut.g_db.prefetch.bank_state[!dut.g_db.prefetch.consumer_bank]==2 && dut.state==dut.RUN)
                    ready_compute_overlap=1;
                if(!pause) begin
                    if(dut.state==dut.WAIT_B && dut.g_db.prefetch.bank_state[dut.g_db.prefetch.consumer_bank]==2)
                        require(dut.g_db.prefetch.bank_kt[dut.g_db.prefetch.consumer_bank]==dut.kt,"READY tag before handshake");
                    if(dut.state==dut.WAIT_B && !dut.db_ready) wait_cycles=wait_cycles+1;
                    if(dut.state==dut.WAIT_B && dut.db_ready) begin
                        require(dut.g_db.prefetch.bank_kt[dut.g_db.prefetch.consumer_bank]==dut.kt,"DB take tag matches K");
                        takes=takes+1;
                    end
                    if(dut.state==dut.ADVANCE) releases=releases+1;
                    if(dut.tile_rd_en || dut.state==dut.RUN) begin
                        require(dut.g_db.prefetch.bank_state[dut.g_db.prefetch.consumer_bank]==3,"compute bank owned");
                        require(dut.g_db.prefetch.bank_kt[dut.g_db.prefetch.consumer_bank]==dut.kt,"compute bank tag");
                    end
                    if(dut.g_db.prefetch.tile_wr_en) begin
                        require(dut.g_db.prefetch.bank_state[dut.g_db.prefetch.fill_bank]==1,"write bank filling");
                        require(dut.g_db.prefetch.load_lane<COLS && dut.g_db.prefetch.load_k<dut.g_db.prefetch.fill_len,"DB tile write bounds");
                        require(dut.g_db.prefetch.bank_state[dut.g_db.prefetch.consumer_bank]!=3 ||
                                dut.g_db.prefetch.fill_bank!=dut.g_db.prefetch.consumer_bank,"no overwrite computing bank");
                        if(dut.state==dut.RUN) overlap_cycles=overlap_cycles+1;
                    end
                end else begin
                    require(!dut.b_rd_en && !dut.g_db.prefetch.tile_wr_en && !dut.tile_rd_en,"pause stops both bank groups");
                end
            end
        end
        initial begin
            wait(db_abort_request);
            abort_overlap();
            db_abort_finished=1;
        end
        // Abort exactly while loader and array are concurrently active.
        task automatic abort_overlap;
            launch(m,n,k);
            while(!(dut.state==dut.RUN && dut.g_db.prefetch.loading)) @(negedge clk);
            reset_overlap=1;
            reset_dut();
        endtask
    end endgenerate

    initial begin
        #20000000;
        $fatal(1,"GLOBAL_TIMEOUT");
    end

    initial begin
        if (ROWS<1 || COLS<1 || TILE_K<1) $fatal(1,"invalid TB parameters");
        report=$fopen("results.csv","w");
        require(report!=0,"open results report");
        $fdisplay(report,"case_id,M,N,K,ROWS,COLS,TILE_K,active_cycles,elapsed_cycles,stall_cycles,OPTIMIZED,A_reads,B_reads,P_writes,DOUBLE_BUFFER,B_LOAD_GAP,wait_cycles,overlap_cycles");
        reset_dut();
        // PE uses generated Python oracle, including overflow and underflow.
        pf=$fopen("pe_vectors.txt","r"); require(pf!=0,"open PE vectors");
        rc=$fscanf(pf,"%d",pcases); require(rc==1,"read PE count");
        @(negedge clk); pe_rst=0;
        for (x=0;x<pcases;x=x+1) begin
            rc=$fscanf(pf,"%d %d %d %d",ps,pa,pb,expected); require(rc==4,"parse PE vector");
            @(negedge clk); pe_load=1; pe_seed=ps; pe_en=0;
            @(posedge clk); #1; require(pe_acc===ps,"PE seed load");
            @(negedge clk); pe_load=0; pe_en=1; pe_a=pa; pe_b=pb;
            @(posedge clk); #1; require(pe_acc===expected,"PE signed product and INT32 wrap");
            @(negedge clk); pe_en=0;
            repeat (2) @(posedge clk);
            #1; require(pe_acc===expected,"PE enable hold");
        end
        $fclose(pf);
        @(negedge clk); pe_rst=1;
        @(posedge clk); #1; require(pe_acc===32'sd0,"PE reset");

        // Invalid task and invalid input coordinates are rejected.
        @(negedge clk); cfg_m=0; cfg_n=1; cfg_k=1; start=1;
        @(posedge clk); #1; require(error && !busy,"zero dimension rejected");
        @(negedge clk); cfg_m=MAX_M+1;
        @(posedge clk); #1; require(error && !busy,"oversized dimension rejected");
        @(negedge clk); start=0; wr_valid=1; wr_row=MAX_M; wr_col=0;
        #1; require(!wr_ready,"invalid input coordinate rejected");
        @(posedge clk);
        @(negedge clk); wr_valid=0;

        // Hold a pending input across an idle pause, then accept on resume.
        @(negedge clk); pause=1; wr_valid=1; wr_matrix=0; wr_row=0; wr_col=0; wr_data=55;
        #1; require(!wr_ready && !start_ready && !rd_ready,"idle pause blocks commands");
        repeat (2) @(posedge clk);
        @(negedge clk); pause=0;
        #1; require(wr_ready,"pending input accepted after pause");
        @(posedge clk);
        @(negedge clk); wr_valid=0;

        f=$fopen("vectors.txt","r"); require(f!=0,"open matrix vectors");
        rc=$fscanf(f,"%d",cases); require(rc==1,"read case count");
        for (seed_dummy=0;seed_dummy<cases;seed_dummy=seed_dummy+1) begin
            rc=$fscanf(f,"%d %d %d %d",cid,m,n,k); require(rc==4,"parse dimensions");
            for (x=0;x<m*k;x=x+1) begin rc=$fscanf(f,"%d",a[x]); require(rc==1,"parse A"); end
            for (x=0;x<k*n;x=x+1) begin rc=$fscanf(f,"%d",b[x]); require(rc==1,"parse B"); end
            for (x=0;x<m*n;x=x+1) begin rc=$fscanf(f,"%d",golden[x]); require(rc==1,"parse C"); end
            // Poison all unused capacity, so invalid reads cannot silently act as zero.
            for (r=0;r<MAX_M;r=r+1)
                for (c=0;c<MAX_K;c=c+1) write_element(0,r,c,((r*37+c*11)%255)-128);
            for (r=0;r<MAX_K;r=r+1)
                for (c=0;c<MAX_N;c=c+1) write_element(1,r,c,((r*19+c*43)%255)-128);
            for (r=0;r<m;r=r+1)
                for (c=0;c<k;c=c+1) write_element(0,r,c,a[r*k+c]);
            for (r=0;r<k;r=r+1)
                for (c=0;c<n;c=c+1) write_element(1,r,c,b[r*n+c]);
            if (cid==12) begin
                // Abort in-flight work at several phases, then restart without
                // reloading RAM: reset invalidates status, not memory contents.
                launch(m,n,k); repeat (5) @(posedge clk); reset_dut();
                launch(m,n,k);
                while (dut.state!=dut.RUN) @(negedge clk);
                @(posedge clk); reset_dut();
                launch(m,n,k);
                // Wait until partial-sum checkpoint writes begin, then abort.
                while (!dut.p_wr_en) @(negedge clk);
                reset_dut();
            end
            if(USE_DB && cid==4) begin : abort_concurrent
                // Static generate task is used only by double-buffer wrappers.
                db_abort_request=1;
                wait(db_abort_finished);
                db_abort_request=0;
            end
            launch(m,n,k);
            wait_complete((cid%2)==1 || (USE_DB && cid==10),m,n,k);
            if (cid==0) begin
                @(negedge clk); pause=1; rd_req=1; rd_row=0; rd_col=0;
                #1; require(!rd_ready,"result read paused");
                @(posedge clk); #1; require(!rd_valid,"paused read has no response");
                @(negedge clk); pause=0;
                #1; require(rd_ready,"pending result read resumes");
                @(posedge clk); #1; require(rd_valid && rd_data===golden[0],"resumed read result");
                @(negedge clk); rd_req=0;
                @(posedge clk); #1; require(!rd_valid,"resumed read response ends");
            end
            for (r=0;r<m;r=r+1)
                for (c=0;c<n;c=c+1) read_and_compare(r,c,golden[r*n+c]);
            @(negedge clk); rd_req=1; rd_row=m; rd_col=0;
            #1; require(!rd_ready,"out-of-range result rejected");
            @(posedge clk); #1; require(!rd_valid,"invalid result has no valid pulse");
            @(negedge clk); rd_req=0;
        end
        $fclose(f); $fclose(report);
        require(done_pulses==cases,"one completion per completed task");
        reset_dut();
        require(paused_states[dut.A_WRITE] && (USE_DB?paused_loader:paused_states[dut.B_WRITE]) &&
                paused_states[dut.RUN] && paused_states[dut.SAVE],"pause covers loaders, compute and save");
        if(USE_DB) begin
            require(total_overlap>0 && total_wait>0,"DB overlap and consumer wait exercised");
            require(ready_a_overlap,"DB prefetch during A loading exercised");
            if(B_LOAD_GAP==0) require(ready_compute_overlap,"DB next bank ready before current compute ends");
            require(paused_overlap && reset_overlap,"DB concurrent pause and reset exercised");
        end
        $display("ALL_TESTS_PASS array=%0dx%0d TK=%0d matrices=%0d comparisons=%0d PE=%0d checks=%0d OPT=%0d DB=%0d GAP=%0d",ROWS,COLS,TILE_K,cases,comparisons,pcases,checks,OPTIMIZED,USE_DB,B_LOAD_GAP);
        $finish;
    end
endmodule
// Explicit wrapper avoids CMD treating unquoted '=' as an argument separator
// in Vivado's Windows batch launcher.
module tb_matmul_single;
    tb_matmul #(.DOUBLE_BUFFER(0)) test();
endmodule
module tb_matmul_alt_single;
    tb_matmul #(.ROWS(2),.COLS(3),.TILE_K(5),.DOUBLE_BUFFER(0)) test();
endmodule
module tb_matmul_db_slow;
    tb_matmul #(.ROWS(2),.COLS(3),.TILE_K(5),.B_LOAD_GAP(3)) test();
endmodule
module tb_matmul_db_fast;
    tb_matmul #(.ROWS(2),.COLS(1),.TILE_K(3)) test();
endmodule
module tb_matmul_alt;
    tb_matmul #(.ROWS(2),.COLS(3),.TILE_K(5)) test();
endmodule

module tb_matmul_baseline;
    tb_matmul #(.OPTIMIZED(0)) test();
endmodule
module tb_matmul_alt_baseline;
    tb_matmul #(.ROWS(2),.COLS(3),.TILE_K(5),.OPTIMIZED(0)) test();
endmodule
