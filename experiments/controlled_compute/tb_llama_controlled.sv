`timescale 1ns/1ps
module tb_llama_controlled #(parameter integer WB_INTERVAL=16,AB_INTERVAL=16);
    logic clk_0_clk=0;always #5 clk_0_clk=~clk_0_clk;
    logic clk_0_resetn=0;
    logic wkvIn_tvalid=0,wkvIn_tready,dotIn_tvalid=0,dotIn_tready,resAdd_tvalid=0,resAdd_tready;
    logic [1023:0] wkvIn_tdata=0,dotIn_tdata=0,resAdd_tdata=0;
    logic axpyIn_tvalid=0,axpyIn_tready,preScale_tvalid=0,preScale_tready;
    logic [15:0] axpyIn_tdata=0,preScale_tdata=16'h3c00;
    logic postScale_tvalid=1,postScale_tready;logic [31:0] postScale_tdata=32'h3f800000;
    logic vecOut_tvalid,scalarOut_tvalid;logic [1023:0] vecOut_tdata;logic [15:0] scalarOut_tdata;
    logic [5:0] vecOut_tuser,scalarOut_tuser,preCfgTag,postCfgTag;
    logic cfg_tvalid=0,cfg_tready;logic [31:0] cfg_tdata=0;
    integer a[0:32767],w[0:262143],golden[0:511];
    integer m,n,k,outputs=0,accepted=0,checks=0,ticks=0,report;bit checking=0;
    MulAddSGNew64 dut(.*);
    task automatic require(input bit ok,input string message);
        checks++;if(!ok)$fatal(1,"LLAMA_CORE_FAILED %s time=%0t",message,$time);
    endtask
    function automatic logic [15:0] half(input integer x);
        return x<0?16'hbc00:x>0?16'h3c00:16'h0000;
    endfunction
    always @(posedge clk_0_clk) begin
        ticks++;
        if(clk_0_resetn && checking) begin
            if(wkvIn_tvalid && wkvIn_tready) accepted+=64;
            if(scalarOut_tvalid) begin
                require(outputs<m*n,"no excess scalar outputs");
                require(scalarOut_tdata===16'(golden[outputs]) ||
                    ((scalarOut_tdata&16'h7fff)==0 && (golden[outputs]&32767)==0),
                    $sformatf("scalar index=%0d got=%h expected=%h",outputs,scalarOut_tdata,16'(golden[outputs])));
                outputs++;
            end
        end
    end
    task automatic send_cfg;
        @(negedge clk_0_clk);cfg_tdata=((k/64-1)<<16)|(n-1);cfg_tvalid=1;
        do @(posedge clk_0_clk);while(!cfg_tready);
        @(negedge clk_0_clk);cfg_tvalid=0;
    endtask
    task automatic send_activation(input integer row);
        for(integer block_index=0;block_index<k/64;block_index++) begin
            @(negedge clk_0_clk);dotIn_tvalid=0;repeat(AB_INTERVAL-1)@(negedge clk_0_clk);dotIn_tvalid=1;
            for(integer lane=0;lane<64;lane++)dotIn_tdata[lane*16 +:16]=half(a[row*k+block_index*64+lane]);
            do @(posedge clk_0_clk);while(!dotIn_tready);
        end
        @(negedge clk_0_clk);dotIn_tvalid=0;
    endtask
    task automatic send_weights;
        for(integer col=0;col<n;col++)for(integer block_index=0;block_index<k/64;block_index++) begin
            @(negedge clk_0_clk);wkvIn_tvalid=0;repeat(WB_INTERVAL-1)@(negedge clk_0_clk);wkvIn_tvalid=1;
            for(integer lane=0;lane<64;lane++)wkvIn_tdata[lane*16 +:16]=half(w[col*k+block_index*64+lane]);
            do @(posedge clk_0_clk);while(!wkvIn_tready);
        end
        @(negedge clk_0_clk);wkvIn_tvalid=0;
    endtask
    initial begin
        integer f,rc,count,cid,started,wd;
        f=$fopen("E:/speed-up/build/controlled_compute/common_vectors_half.txt","r");require(f!=0,"vectors opened");rc=$fscanf(f,"%d",count);require(count==5,"case count");
        report=$fopen("llama_results.csv","w");$fdisplay(report,"case_id,M,N,K,cycles,valid_macs");
        for(integer test=0;test<count;test++) begin
            rc=$fscanf(f,"%d %d %d %d",cid,m,n,k);require(rc==4,"shape");
            for(integer i=0;i<m*k;i++)rc=$fscanf(f,"%d",a[i]);
            for(integer i=0;i<n*k;i++)rc=$fscanf(f,"%d",w[i]);
            for(integer i=0;i<m*n;i++)rc=$fscanf(f,"%d",golden[i]);
            @(negedge clk_0_clk);clk_0_resetn=0;checking=0;cfg_tvalid=0;wkvIn_tvalid=0;dotIn_tvalid=0;
            repeat(8)@(negedge clk_0_clk);clk_0_resetn=1;repeat(100)@(negedge clk_0_clk);
            outputs=0;accepted=0;checking=1;started=ticks+1;
            for(integer row=0;row<m;row++) begin
                send_cfg();
                send_activation(row);send_weights();
                wd=0;while(outputs<(row+1)*n)begin @(negedge clk_0_clk);wd++;require(wd<200000,"row watchdog");end
            end
            require(outputs==m*n && accepted==m*n*k,"all mathematical work");
            $fdisplay(report,"%0d,%0d,%0d,%0d,%0d,%0d",cid,m,n,k,ticks-started,accepted);
            $display("LLAMA_CORE_CASE_PASS case=%0d cycles=%0d macs=%0d",cid,ticks-started,accepted);checking=0;
        end
        $fclose(f);$fclose(report);$display("LLAMA_CORE_PASS checks=%0d cases=5",checks);$finish;
    end
    initial begin #100000000;$fatal(1,"LLAMA_CORE_TIMEOUT");end
endmodule

module tb_llama_controlled_bytes;tb_llama_controlled #(.WB_INTERVAL(16),.AB_INTERVAL(16)) test();endmodule
module tb_llama_controlled_elements;tb_llama_controlled #(.WB_INTERVAL(4),.AB_INTERVAL(8)) test();endmodule
