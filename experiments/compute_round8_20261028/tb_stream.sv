`timescale 1ns/1ps
module tb_stream;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,start=0,load_pause=0,array_pause=0,post_pause=0;
    logic start_ready,busy,done,error,in_valid=0,in_ready,out_valid,out_ready=1,out_last;
    logic [15:0] cfg_n=0,cfg_k=0,out_n;
    logic [63:0] in_data=0;
    logic [7:0] in_keep=0;
    logic signed [31:0] out_data;
    logic [31:0] total_cycles,input_beats,weight_bytes,activation_bytes,sx_bytes,sw_bytes,
        valid_macs,compute_cycles,input_wait_cycles,output_wait_cycles;
    w4a8_gemv_stream dut(.*);
    logic [63:0] data[0:40000];
    logic [7:0] keep[0:40000];
    integer golden[0:63];
    integer partial_golden[0:8191];
    bit seen[0:63];
    integer f,rc,count,cid,n,k,nb,ew,ea,esx,esw,idx=0,outputs=0,ticks=0,elapsed=0,checks=0,report,mode=0;
    integer held_checks=0,recoveries=0,partial_checks=0;
    bit checking=0,held_in=0,held_out=0,beat_accepted=0,bad_ingress=0;
    logic [71:0] previous_input;
    logic [48:0] previous_output;
    task automatic require(input bit ok,input string message);
        checks++;if(!ok)$fatal(1,"STREAM_FAILED %s case=%0d mode=%0d time=%0t",message,cid,mode,$time);
    endtask
    always @(posedge clk) begin
        ticks++;
        beat_accepted=in_valid && in_ready;
        if(rst) begin held_in=0;held_out=0;beat_accepted=0;end
        else if(checking) begin
            if(busy) elapsed++;
            if(held_in) begin require(in_valid && {in_keep,in_data}===previous_input,"stable stalled input");held_checks++;end
            if(held_out) begin require(out_valid && {out_n,out_last,out_data}===previous_output,"stable stalled output");held_checks++;end
            held_in=in_valid && !in_ready;previous_input={in_keep,in_data};
            held_out=out_valid && !out_ready;previous_output={out_n,out_last,out_data};
            if(in_valid && in_ready) idx++;
            if(integer'(dut.state)==5) for(integer col=0;col<8;col++) if(col<dut.active_nl) begin
                integer sum;
                sum=0;
                for(integer row=0;row<8;row++) sum+=dut.pe[row][col];
                require(sum==partial_golden[dut.active_g*n+dut.active_nt+col],"independent group partial sum");
                partial_checks++;
            end
            if(out_valid && out_ready) begin
                require(out_n<n && !seen[out_n],"unique bounded output");
                require(out_data===32'(golden[out_n]),$sformatf("numeric output n=%0d got=%0d expected=%0d",out_n,out_data,golden[out_n]));
                require(out_last==(out_n+1==n),"last output flag");
                seen[out_n]=1;outputs++;
            end
        end
    end
    always @(negedge clk) begin
        load_pause=mode==1 && ticks%11<3;
        array_pause=mode==1 && ticks%13<3;
        post_pause=mode==1 && ticks%17<4;
        out_ready=mode==0 || (mode==1?ticks%7>=2:ticks%29>=21);
        if(rst || !checking) begin in_valid=0;in_keep=0;end
        else if(!in_valid || beat_accepted) begin
            in_valid=idx<nb && (mode==0 || (mode==1?ticks%5!=0:ticks%19>=9));
            if(idx<nb) begin in_data=data[idx];in_keep=keep[idx];end
        end
        if(bad_ingress && checking) begin in_valid=1;in_keep=0;end
    end
    task automatic launch;
        @(negedge clk);require(start_ready,"task admission");
        cfg_n=16'(n);cfg_k=16'(k);idx=0;outputs=0;elapsed=0;held_in=0;held_out=0;
        for(integer j=0;j<64;j++)seen[j]=0;
        start=1;
        @(negedge clk);start=0;checking=1;
    endtask
    task automatic finish_job(input integer recovery);
        integer wd;
        wd=0;
        while(!done) begin @(negedge clk);wd++;require(wd<300000,"bounded completion");end
        require(!error && !busy,"successful completion");
        require(outputs==n && idx==nb,"all outputs and ingress beats");
        require(total_cycles==elapsed,"independent cycle accounting");
        require(input_beats==nb && weight_bytes==ew && activation_bytes==ea && sx_bytes==esx && sw_bytes==esw,"independent plane byte accounting");
        require(valid_macs==n*k,"independent useful MAC accounting");
        $fdisplay(report,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cid,mode,recovery,n,k,total_cycles,input_beats,weight_bytes,activation_bytes,sx_bytes,sw_bytes,valid_macs,compute_cycles,input_wait_cycles,output_wait_cycles,held_checks);
        $display("STREAM_CASE_PASS id=%0d mode=%0d recovery=%0d N=%0d K=%0d cycles=%0d beats=%0d",cid,mode,recovery,n,k,total_cycles,input_beats);
        checking=0;in_valid=0;repeat(2)@(negedge clk);
    endtask
    initial begin
        integer abort_state,wd;
        report=$fopen("results.csv","w");
        $fdisplay(report,"case_id,mode,recovery,N,K,cycles,input_beats,weight_bytes,activation_bytes,sx_bytes,sw_bytes,valid_macs,compute_cycles,input_wait_cycles,output_wait_cycles,held_checks");
        f=$fopen("vectors.txt","r");require(f!=0,"input vectors available");rc=$fscanf(f,"%d",count);require(rc==1,"case count");
        repeat(5)@(negedge clk);rst=0;repeat(2)@(negedge clk);
        for(integer c=0;c<count;c++) begin
            rc=$fscanf(f,"%d %d %d %d %d %d %d %d",cid,n,k,nb,ew,ea,esx,esw);require(rc==8,"case header");
            for(integer j=0;j<nb;j++) begin rc=$fscanf(f,"%h %h",data[j],keep[j]);require(rc==2,"beat input");end
            for(integer j=0;j<n;j++) begin rc=$fscanf(f,"%d",golden[j]);require(rc==1,"independent expected output");end
            for(integer j=0;j<n*((k+31)/32);j++) begin rc=$fscanf(f,"%d",partial_golden[j]);require(rc==1,"independent expected group sum");end
            if($test$plusargs("corrupt_expected") && c==0) golden[0]=golden[0]^1;
            for(mode=0;mode<(k<=128?3:1);mode++) begin launch();finish_job(0);end
            if(n==17 && k==65) begin
                for(integer a=0;a<3;a++) begin
                    mode=0;abort_state=a==0?4:a==1?6:7;launch();
                    wd=0;
                    while(integer'(dut.state)!=abort_state) begin @(negedge clk);wd++;require(wd<10000,"reach reset target");end
                    checking=0;in_valid=0;rst=1;
                    repeat(3)@(negedge clk);require(!busy && !out_valid,"reset cancels active job");
                    rst=0;repeat(2)@(negedge clk);launch();finish_job(a+1);recoveries++;
                end
            end
        end
        // Invalid geometry is rejected without accepting data.
        mode=0;@(negedge clk);cfg_n=0;cfg_k=32;start=1;
        @(negedge clk);start=0;require(done && error && !busy && !in_ready,"reject invalid shape");
        repeat(2)@(negedge clk);
        bad_ingress=1;launch();wd=0;
        while(!done) begin @(negedge clk);wd++;require(wd<100,"malformed beat completes with error");end
        require(error && !busy,"reject malformed keep");checking=0;bad_ingress=0;in_valid=0;
        repeat(2)@(negedge clk);launch();finish_job(4);
        $fclose(f);$fclose(report);
        require(held_checks>0 && recoveries>=3,"stalls and mid-pipeline reset exercised");
        $display("STREAM_TESTS_PASS cases=%0d checks=%0d held=%0d recoveries=%0d partials=%0d",count,checks,held_checks,recoveries,partial_checks);$finish;
    end
    initial begin #200000000;$fatal(1,"STREAM_TIMEOUT");end
endmodule
